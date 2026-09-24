// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "anchor_sift.h"

typedef struct
{
    unsigned int level;
    uint64_t occurrences;
    uint64_t magnitude;
} SteerLevel;

static int steer_order(const void *left, const void *right)
{
    const SteerLevel *a = (const SteerLevel *)left;
    const SteerLevel *b = (const SteerLevel *)right;
    if ((a->occurrences == 0u) != (b->occurrences == 0u))
    {
        return (a->occurrences == 0u) ? 1 : -1;
    }
    if (a->occurrences < b->occurrences)
    {
        return -1;
    }
    return (a->occurrences > b->occurrences) ? 1 : 0;
}

int main(int argc, char **argv)
{
    if (argc < 3)
    {
        (void)fprintf(stderr,
                      "  usage: steer_cells VOLUME_TXT SHARE\n"
                      "         VOLUME_TXT  rows of \"z y x level\", the whole field\n"
                      "         SHARE       parts per thousand of the field to admit as cells\n");
        return 2;
    }

    FILE *handle = fopen(argv[1], "r");
    if (handle == NULL)
    {
        (void)fprintf(stderr, "  could not read %s\n", argv[1]);
        return 1;
    }

    size_t room = 1u << 16;
    size_t count = 0u;
    unsigned int *levels = malloc(room * sizeof(*levels));
    unsigned int *zs = malloc(room * sizeof(*zs));
    unsigned int *ys = malloc(room * sizeof(*ys));
    unsigned int *xs = malloc(room * sizeof(*xs));
    if ((levels == NULL) || (zs == NULL) || (ys == NULL) || (xs == NULL))
    {
        return 1;
    }

    unsigned int z = 0u;
    unsigned int y = 0u;
    unsigned int x = 0u;
    unsigned int value = 0u;
    while (fscanf(handle, "%u %u %u %u", &z, &y, &x, &value) == 4)
    {
        if (count == room)
        {
            room *= 2u;
            levels = realloc(levels, room * sizeof(*levels));
            zs = realloc(zs, room * sizeof(*zs));
            ys = realloc(ys, room * sizeof(*ys));
            xs = realloc(xs, room * sizeof(*xs));
            if ((levels == NULL) || (zs == NULL) || (ys == NULL) || (xs == NULL))
            {
                return 1;
            }
        }
        zs[count] = z;
        ys[count] = y;
        xs[count] = x;
        levels[count] = value;
        count++;
    }
    fclose(handle);

    uint8_t *field = malloc(count);
    if (field == NULL)
    {
        return 1;
    }
    for (size_t at = 0u; at < count; at++)
    {
        field[at] = (uint8_t)(levels[at] & 0xFFu);
    }

    AnchorFieldCensus census;
    anchor_field_census(field, count, &census);

    SteerLevel ranked[ANCHOR_STEER_SYMBOLS];
    for (unsigned int level = 0u; level < ANCHOR_STEER_SYMBOLS; level++)
    {
        ranked[level].level = level;
        ranked[level].occurrences = census.occurrences[level];
        ranked[level].magnitude = anchor_steer_magnitude(&census, (uint8_t)level);
    }
    qsort(ranked, ANCHOR_STEER_SYMBOLS, sizeof(*ranked), steer_order);

    const unsigned long share = strtoul(argv[2], NULL, 10);
    const uint64_t budget = (census.total * (uint64_t)share) / 1000u;

    (void)printf("  field %llu voxels, %u distinct levels, admitting %llu voxels (%lu per mille)\n",
                 (unsigned long long)census.total, census.distinct,
                 (unsigned long long)budget, share);
    (void)printf("\n  rank  level  occurrences  magnitude\n");

    uint64_t spent = 0u;
    unsigned char admitted[ANCHOR_STEER_SYMBOLS];
    memset(admitted, 0, sizeof(admitted));
    unsigned int taken = 0u;
    for (unsigned int at = 0u; at < ANCHOR_STEER_SYMBOLS; at++)
    {
        if (ranked[at].occurrences == 0u)
        {
            break;
        }
        if ((spent + ranked[at].occurrences) > budget)
        {
            break;
        }
        admitted[ranked[at].level] = 1u;
        spent += ranked[at].occurrences;
        if (taken < 8u)
        {
            (void)printf("  %-5u %-6u %-12llu %llu\n", taken, ranked[at].level,
                         (unsigned long long)ranked[at].occurrences,
                         (unsigned long long)ranked[at].magnitude);
        }
        taken++;
    }

    (void)printf("\n  %u levels admitted, %llu voxels, %.3f per mille of the field\n",
                 taken, (unsigned long long)spent,
                 census.total ? (1000.0 * (double)spent / (double)census.total) : 0.0);

    FILE *out = fopen("steered.txt", "w");
    if (out != NULL)
    {
        for (size_t at = 0u; at < count; at++)
        {
            if (admitted[field[at]])
            {
                (void)fprintf(out, "%u %u %u %u\n", zs[at], ys[at], xs[at], levels[at]);
            }
        }
        fclose(out);
        (void)printf("  wrote steered.txt\n");
    }
    return 0;
}
