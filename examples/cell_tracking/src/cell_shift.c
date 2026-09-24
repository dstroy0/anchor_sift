// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "exact_integer.h"
#include "arm.h"

#define SHIFT_TEXT 64u

typedef struct
{
    AnchorExactInteger *positions;
    uint64_t *values;
    size_t count;
} CellFrame;

static int shift_from_unsigned(unsigned long long value, AnchorExactInteger *result)
{
    char text[SHIFT_TEXT];
    const int written = snprintf(text, sizeof(text), "%llu", value);
    if ((written <= 0) || ((size_t)written >= sizeof(text)))
    {
        return 0;
    }
    return anchor_exact_from_decimal(text, (size_t)written, ANCHOR_EXACT_DIGITS, result)
           == ANCHOR_EXACT_OK;
}

static int shift_read_frame(const char *path, unsigned long long side_y, unsigned long long side_x,
                            CellFrame *frame)
{
    FILE *handle = fopen(path, "r");
    if (handle == NULL)
    {
        return 0;
    }

    size_t room = 1024u;
    frame->positions = malloc(room * sizeof(*frame->positions));
    frame->values = malloc(room * sizeof(*frame->values));
    frame->count = 0u;
    if ((frame->positions == NULL) || (frame->values == NULL))
    {
        fclose(handle);
        return 0;
    }

    unsigned long long z = 0u;
    unsigned long long y = 0u;
    unsigned long long x = 0u;
    unsigned long long value = 0u;
    while (fscanf(handle, "%llu %llu %llu %llu", &z, &y, &x, &value) == 4)
    {
        if (frame->count == room)
        {
            room *= 2u;
            AnchorExactInteger *grown = realloc(frame->positions, room * sizeof(*grown));
            uint64_t *grown_values = realloc(frame->values, room * sizeof(*grown_values));
            if ((grown == NULL) || (grown_values == NULL))
            {
                fclose(handle);
                return 0;
            }
            frame->positions = grown;
            frame->values = grown_values;
        }
        const unsigned long long index = (z * side_y * side_x) + (y * side_x) + x;
        if (!shift_from_unsigned(index, &frame->positions[frame->count]))
        {
            fclose(handle);
            return 0;
        }
        frame->values[frame->count] = value;
        frame->count++;
    }
    fclose(handle);
    return 1;
}

static int shift_order(const void *left, const void *right)
{
    return anchor_exact_compare((const AnchorExactInteger *)left,
                                (const AnchorExactInteger *)right);
}

int main(int argc, char **argv)
{
    if (argc < 6)
    {
        (void)fprintf(stderr,
                      "  usage: cell_shift FRAME_A FRAME_B SIDE_Y SIDE_X MAX_STEP [engine]\n"
                      "         FRAME_A, FRAME_B  text files of \"z y x value\" rows\n"
                      "         SIDE_Y, SIDE_X    volume extents, for the linearization\n"
                      "         MAX_STEP          largest displacement to sweep, in voxels\n"
                      "         engine            portable or cuda, default whichever is present\n");
        return 2;
    }

    const unsigned long long side_y = strtoull(argv[3], NULL, 10);
    const unsigned long long side_x = strtoull(argv[4], NULL, 10);
    const long max_step = strtol(argv[5], NULL, 10);

    CellFrame first;
    CellFrame second;
    if (!shift_read_frame(argv[1], side_y, side_x, &first))
    {
        (void)fprintf(stderr, "  could not read %s\n", argv[1]);
        return 1;
    }
    if (!shift_read_frame(argv[2], side_y, side_x, &second))
    {
        (void)fprintf(stderr, "  could not read %s\n", argv[2]);
        return 1;
    }

    const size_t total = first.count + second.count;
    AnchorExactInteger *positions = malloc(total * sizeof(*positions));
    uint64_t *values = malloc(total * sizeof(*values));
    if ((positions == NULL) || (values == NULL))
    {
        (void)fprintf(stderr, "  out of memory at %zu positions\n", total);
        return 1;
    }
    memcpy(positions, first.positions, first.count * sizeof(*positions));
    memcpy(values, first.values, first.count * sizeof(*values));
    memcpy(positions + first.count, second.positions, second.count * sizeof(*positions));
    memcpy(values + first.count, second.values, second.count * sizeof(*values));
    qsort(positions, total, sizeof(*positions), shift_order);

    const AnchorExactArm *engine = anchor_exact_portable_arm();
#if defined(ANCHOR_EXACT_HAVE_CUDA) && ANCHOR_EXACT_HAVE_CUDA
    if ((argc < 7) || (strcmp(argv[6], "portable") != 0))
    {
        const AnchorExactArm *device = anchor_exact_cuda_arm();
        if (device != NULL)
        {
            engine = device;
        }
    }
#endif

    (void)printf("  %zu positions from two frames, engine %s, sweeping to %ld voxels\n\n",
                 total, engine->name, max_step);
    (void)printf("  %-10s %-14s %s\n", "dz", "lag", "agreement");

    size_t best = 0u;
    long best_dz = 0;
    for (long dz = 0; dz <= max_step; dz++)
    {
        AnchorExactInteger lag;
        const unsigned long long step = (unsigned long long)dz * side_y * side_x;
        if (!shift_from_unsigned(step, &lag))
        {
            continue;
        }
        const size_t agreed = engine->agreement(positions, values, total, &lag);
        if (agreed == (size_t)-1)
        {
            (void)fprintf(stderr, "  the engine refused the work at dz %ld\n", dz);
            break;
        }
        (void)printf("  %-10ld %-14llu %zu\n", dz, step, agreed);
        if ((dz > 0) && (agreed > best))
        {
            best = agreed;
            best_dz = dz;
        }
    }

    (void)printf("\n  peak away from zero: dz %ld at %zu agreements.\n", best_dz, best);
    (void)printf("  Lag zero counts every position against itself and is not a displacement.\n");
    return 0;
}
