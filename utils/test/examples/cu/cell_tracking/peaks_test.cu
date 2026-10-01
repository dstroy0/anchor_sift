// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The tracker's peaks (cell_tracking/src/peaks): every positive voxel of an exact residual that no one of its 26
// neighbors exceeds, a tie going to the lower index, at any width the request names in limbs. The device's points are
// checked against a host scan that orders the residual through the exact integer library, at 1, 9, 10 and 12 limbs, on
// fields that mix zeros, small and half-width values of both signs and many ties. The capacity protocol is proved (a
// capacity too small writes nothing and returns the count), a flat positive field gives the one first voxel, a field
// with no positive voxel gives none, and a malformed request, a width of no limbs among them, errors. The test is one
// job on the device's tessera daemon, submitted before its first device work.
#include "../../../../../src/c/types/integers/exact_integer.h"
#include "peaks.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define PEAKS_TEST_EXTENTS 4u

#define PEAKS_TEST_WIDTHS 4u

#define PEAKS_TEST_LIMBS_MAX 12u

#define PEAKS_TEST_KINDS 6ull

#define PEAKS_TEST_VOXELS_MAX (16u * 32u * 32u)

// the most the test puts on the device at once: the residual, the peaks' flags, ranks and scratch, and the points
#define PEAKS_TEST_DECLARED                                                                                            \
    ((unsigned long long)PEAKS_TEST_VOXELS_MAX * ((2ull * PEAKS_TEST_LIMBS_MAX) + 4ull) * sizeof(unsigned int))

static_assert(ANCHOR_EXACT_LIMBS >= PEAKS_TEST_LIMBS_MAX,
              "peaks_test: the exact integer must hold the widest residual");

static const unsigned int PEAKS_TEST_EXTENT[PEAKS_TEST_EXTENTS][3] = {
    {6u, 10u, 12u}, {1u, 1u, 1u}, {3u, 1u, 7u}, {16u, 32u, 32u}};

static const unsigned int PEAKS_TEST_WIDTH[PEAKS_TEST_WIDTHS] = {1u, 9u, 10u, PEAKS_TEST_LIMBS_MAX};

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    unsigned int limbs;
    unsigned int *residual;
    AnchorExactInteger *values;
    unsigned int *expected;
    unsigned int expected_count;
} PeaksTestField;

static void peaks_test_value(unsigned long long key, unsigned long long voxel, unsigned int limbs,
                             unsigned int *residual)
{
    const unsigned long long draw = sim_draw(key, voxel);
    // a remainder below the kinds' count fits unsigned int
    const unsigned int kind = (unsigned int)(draw % PEAKS_TEST_KINDS);
    // a remainder below 3, plus one, fits unsigned int
    const unsigned int small = 1u + (unsigned int)((draw >> 8u) % 3ull);
    const unsigned int middle = limbs / 2u;
    memset(residual, 0, limbs * sizeof(unsigned int));
    if (kind == 1u)
    {
        residual[0] = small;
    }
    else if (kind == 2u)
    {
        for (unsigned int limb = 1u; limb < limbs; limb += 1u)
        {
            residual[limb] = 0xFFFFFFFFu;
        }
        residual[0] = 0u - small;
    }
    else if (kind == 3u)
    {
        residual[middle] = small;
    }
    else if (kind == 4u)
    {
        residual[middle] = 1u;
        residual[0] = small;
    }
    else if (kind == 5u)
    {
        residual[0] = small;
        // the high half of the draw, shifted down, is below 2^32
        residual[limbs - 1u] = 0x80000000u | (unsigned int)(draw >> 32u);
    }
}

static void peaks_test_exact(const unsigned int *residual, unsigned int limbs, AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    const unsigned int negative = residual[limbs - 1u] >> 31u;
    unsigned int carry = negative;
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned int flipped = (negative != 0u) ? ~residual[limb] : residual[limb];
        const unsigned int sum = flipped + carry;
        carry = ((carry != 0u) && (sum == 0u)) ? 1u : 0u;
        value->limb[limb] = sum;
        any |= sum;
    }
    value->sign = (any == 0u) ? 0 : ((negative != 0u) ? -1 : 1);
}

static unsigned int peaks_test_expected(const PeaksTestField *field, unsigned int *voxels)
{
    const unsigned int plane = field->height * field->width;
    // each extent is below 2^31 in this test. Each widens to long long exactly
    const long long extent[3] = {(long long)field->depth, (long long)field->height, (long long)field->width};
    unsigned int count = 0u;
    for (unsigned int voxel = 0u; voxel < field->voxels; voxel += 1u)
    {
        // each coordinate is below its extent. Each widens to long long exactly
        const long long place[3] = {(long long)(voxel / plane), (long long)((voxel % plane) / field->width),
                                    (long long)(voxel % field->width)};
        int peak = (field->values[voxel].sign > 0);
        for (long long dz = -1ll; peak && (dz <= 1ll); dz += 1ll)
        {
            for (long long dy = -1ll; peak && (dy <= 1ll); dy += 1ll)
            {
                for (long long dx = -1ll; peak && (dx <= 1ll); dx += 1ll)
                {
                    const long long z = place[0] + dz;
                    const long long y = place[1] + dy;
                    const long long x = place[2] + dx;
                    const int inside = ((dz != 0ll) || (dy != 0ll) || (dx != 0ll)) && (z >= 0ll) && (z < extent[0]) &&
                                       (y >= 0ll) && (y < extent[1]) && (x >= 0ll) && (x < extent[2]);
                    // an inside neighbor's index is below the field's voxel count, which fits unsigned int
                    const unsigned int other = inside ? (unsigned int)((((z * extent[1]) + y) * extent[2]) + x) : 0u;
                    const int order = inside ? anchor_exact_compare(&field->values[other], &field->values[voxel]) : -1;
                    peak = (order < 0) || ((order == 0) && (other > voxel));
                }
            }
        }
        if (peak)
        {
            voxels[count] = voxel;
            count += 1u;
        }
    }
    return count;
}

static int peaks_test_counted(long found, unsigned int expected)
{
    // a count that is not an error is not negative. It re-signs to unsigned long long exactly
    return (found >= 0L) && ((unsigned long long)found == expected);
}

static int peaks_test_reserve(PeaksTestField *field, unsigned int depth, unsigned int height, unsigned int width,
                              unsigned int limbs)
{
    memset(field, 0, sizeof(*field));
    field->depth = depth;
    field->height = height;
    field->width = width;
    field->voxels = depth * height * width;
    field->limbs = limbs;
    field->residual = (unsigned int *)malloc(((size_t)field->voxels * limbs + 1u) * sizeof(unsigned int));
    field->values = (AnchorExactInteger *)malloc(((size_t)field->voxels + 1u) * sizeof(AnchorExactInteger));
    field->expected = (unsigned int *)malloc(((size_t)field->voxels + 1u) * sizeof(unsigned int));
    return (field->residual != NULL) && (field->values != NULL) && (field->expected != NULL);
}

static void peaks_test_release(PeaksTestField *field)
{
    free(field->residual);
    free(field->values);
    free(field->expected);
    memset(field, 0, sizeof(*field));
}

static void peaks_test_prove(SimResults *results, PeaksTestField *field, const char *name)
{
    const unsigned int limbs = field->limbs;
    for (unsigned int voxel = 0u; voxel < field->voxels; voxel += 1u)
    {
        peaks_test_exact(&field->residual[(size_t)voxel * limbs], limbs, &field->values[voxel]);
    }
    field->expected_count = peaks_test_expected(field, field->expected);
    const size_t bytes = (size_t)field->voxels * limbs * sizeof(unsigned int);
    unsigned int *device = NULL;
    int ok = sim_status_check(results, cudaMalloc((void **)&device, bytes), "the residual is held on the device") &&
             sim_status_check(results, cudaMemcpy(device, field->residual, bytes, cudaMemcpyHostToDevice),
                              "the residual reaches the device");
    unsigned int *const voxels = (unsigned int *)malloc(((size_t)field->expected_count + 1u) * sizeof(unsigned int));
    unsigned int *const levels =
        (unsigned int *)malloc(((size_t)field->expected_count * limbs + 1u) * sizeof(unsigned int));
    ok = ok && (voxels != NULL) && (levels != NULL);
    PeaksRequest request = {device, field->depth, field->height, field->width, limbs, 0u, NULL, NULL};
    const long counted = ok ? peaks_find(&request) : PEAKS_ERROR;
    sim_check(results, peaks_test_counted(counted, field->expected_count),
              "a capacity of none returns the count and writes nothing");
    request.capacity = (field->expected_count != 0u) ? (field->expected_count - 1u) : 0u;
    request.voxels = voxels;
    request.levels = levels;
    const long short_of_capacity = ok ? peaks_find(&request) : PEAKS_ERROR;
    sim_check(results, peaks_test_counted(short_of_capacity, field->expected_count),
              "a capacity one short returns the count");
    request.capacity = field->expected_count;
    const long found = ok ? peaks_find(&request) : PEAKS_ERROR;
    int agree = peaks_test_counted(found, field->expected_count);
    for (unsigned int point = 0u; agree && (point < field->expected_count); point += 1u)
    {
        const unsigned int voxel = field->expected[point];
        agree =
            (voxels[point] == voxel) && (memcmp(&levels[(size_t)point * limbs], &field->residual[(size_t)voxel * limbs],
                                                limbs * sizeof(unsigned int)) == 0);
    }
    sim_check(results, agree, name);
    scriptura_text(&results->line, "  ");
    scriptura_text(&results->line, name);
    scriptura_text(&results->line, ": ");
    scriptura_decimal(&results->line, limbs, 1u);
    scriptura_text(&results->line, " limbs, ");
    scriptura_decimal(&results->line, field->depth, 1u);
    scriptura_character(&results->line, 'x');
    scriptura_decimal(&results->line, field->height, 1u);
    scriptura_character(&results->line, 'x');
    scriptura_decimal(&results->line, field->width, 1u);
    scriptura_text(&results->line, ", ");
    scriptura_decimal(&results->line, field->expected_count, 1u);
    scriptura_text(&results->line, " points on the host, ");
    // an error is -1 and is shown as the widest word, never as a count
    scriptura_decimal(&results->line, (found >= 0L) ? (unsigned long long)found : ~0ull, 1u);
    scriptura_text(&results->line, " on the device\n");
    sim_flush(results);
    free(voxels);
    free(levels);
    cudaFree(device);
}

static void peaks_test_hessians(SimResults *results, unsigned int width_at)
{
    const unsigned int limbs = PEAKS_TEST_WIDTH[width_at];
    for (unsigned int extent = 0u; extent < PEAKS_TEST_EXTENTS; extent += 1u)
    {
        PeaksTestField field;
        const int ok = peaks_test_reserve(&field, PEAKS_TEST_EXTENT[extent][0], PEAKS_TEST_EXTENT[extent][1],
                                          PEAKS_TEST_EXTENT[extent][2], limbs);
        sim_check(results, ok, "the field is held on the host");
        const unsigned long long key = 0x7EA45ull + ((unsigned long long)width_at * PEAKS_TEST_EXTENTS) + extent;
        for (unsigned int voxel = 0u; ok && (voxel < field.voxels); voxel += 1u)
        {
            peaks_test_value(key, voxel, limbs, &field.residual[(size_t)voxel * limbs]);
        }
        if (ok)
        {
            peaks_test_prove(results, &field, "the device's points are the host's, voxel and level, on a mixed field");
        }
        peaks_test_release(&field);
    }
}

static void peaks_test_uniform(SimResults *results, unsigned int limbs, unsigned int low, unsigned int high,
                               unsigned int points, const char *name)
{
    PeaksTestField field;
    const int ok = peaks_test_reserve(&field, 5u, 7u, 9u, limbs);
    sim_check(results, ok, "the uniform field is held on the host");
    for (unsigned int voxel = 0u; ok && (voxel < field.voxels); voxel += 1u)
    {
        unsigned int *const residual = &field.residual[(size_t)voxel * limbs];
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            residual[limb] = high;
        }
        residual[0] = low;
    }
    if (ok)
    {
        peaks_test_prove(results, &field, name);
        sim_check(results, (field.expected_count == points) && ((points == 0u) || (field.expected[0] == 0u)), name);
    }
    peaks_test_release(&field);
}

static void peaks_test_errors(SimResults *results)
{
    unsigned int *device = NULL;
    const int ok = sim_status_check(results, cudaMalloc((void **)&device, PEAKS_TEST_LIMBS_MAX * sizeof(unsigned int)),
                                    "one voxel is held on the device");
    const PeaksRequest none = {NULL, 1u, 1u, 1u, 1u, 0u, NULL, NULL};
    const PeaksRequest flat = {device, 0u, 1u, 1u, 1u, 0u, NULL, NULL};
    const PeaksRequest narrow = {device, 1u, 1u, 1u, 0u, 0u, NULL, NULL};
    const PeaksRequest unplaced = {device, 1u, 1u, 1u, 1u, 1u, NULL, NULL};
    sim_check(results, peaks_find(NULL) == PEAKS_ERROR, "no request errors");
    sim_check(results, peaks_find(&none) == PEAKS_ERROR, "no residual errors");
    sim_check(results, ok && (peaks_find(&flat) == PEAKS_ERROR), "an empty extent errors");
    sim_check(results, ok && (peaks_find(&narrow) == PEAKS_ERROR), "a width of no limbs errors");
    sim_check(results, ok && (peaks_find(&unplaced) == PEAKS_ERROR), "a capacity with nowhere to write errors");
    cudaFree(device);
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    const int admitted = sim_job_submit(&results, "peaks_test", count, arguments, PEAKS_TEST_DECLARED);
    for (unsigned int width_at = 0u; (admitted != 0) && (width_at < PEAKS_TEST_WIDTHS); width_at += 1u)
    {
        const unsigned int limbs = PEAKS_TEST_WIDTH[width_at];
        peaks_test_hessians(&results, width_at);
        peaks_test_uniform(&results, limbs, 1u, 0u, 1u, "a flat positive field gives one point, the first voxel");
        peaks_test_uniform(&results, limbs, 0xFFFFFFFFu, 0xFFFFFFFFu, 0u, "a field of -1 gives no point");
        peaks_test_uniform(&results, limbs, 0u, 0u, 0u, "a field of zeros gives no point");
    }
    if (admitted != 0)
    {
        peaks_test_errors(&results);
    }
    return sim_close(&results, "peaks test");
}
