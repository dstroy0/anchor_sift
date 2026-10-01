// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// floor_match_floors.cu: floors, the engine and the kernels
#include "floor_match_internal.h"

// the tower's own floor shift, toward minus infinity, as tower_*.cu takes it
static long long match_floor_shift(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -(((-value) + (1ll << shift) - 1ll) >> shift);
}

// the high d_j of one line, as tower_*.cu's forward kernel reads it: the edge repeats its left neighbor
static long long match_high(const long long *from, unsigned long long line, unsigned long long stride,
                            unsigned long long length, unsigned long long j)
{
    const long long left = from[line + (2ull * j * stride)];
    const long long right = ((2ull * j) + 2ull < length) ? from[line + (((2ull * j) + 2ull) * stride)] : left;
    return from[line + (((2ull * j) + 1ull) * stride)] - match_floor_shift(left + right, 1u);
}

// one coefficient of one line after the lifting along it: the lows first, then the highs
static long long match_lifted(const long long *from, unsigned long long line, unsigned long long stride,
                              unsigned long long length, unsigned long long along)
{
    const unsigned long long lows = (length + 1ull) / 2ull;
    const unsigned long long highs = length / 2ull;
    if (along >= lows)
    {
        return match_high(from, line, stride, length, along - lows);
    }
    const long long before = (along > 0ull) ? match_high(from, line, stride, length, along - 1ull)
                                            : match_high(from, line, stride, length, 0ull);
    const long long after = (along < highs) ? match_high(from, line, stride, length, along) : before;
    return from[line + (2ull * along * stride)] + match_floor_shift(before + after + 2ll, 2u);
}

// the host's floor 2: two levels of the 5/3 lifting, each along z, then y, then x over the active corner, every
// axis pass reading the coefficients as they stood before it, as the engine's kernels do
void match_floor_host(const unsigned short *lanes, long long *work, long long *before, long long *floor_values)
{
    const unsigned long long stride[SIM_AXES] = {MATCH_SIDE * MATCH_SIDE, MATCH_SIDE, 1ull};
    for (unsigned long long sample = 0ull; sample < MATCH_SAMPLES; sample += 1ull)
    {
        work[sample] = (long long)lanes[sample];
    }
    for (unsigned int level = 0u; level < MATCH_FLOOR; level += 1u)
    {
        const unsigned long long active = MATCH_SIDE >> level;
        for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
        {
            memcpy(before, work, (size_t)MATCH_SAMPLES * sizeof(long long));
            for (unsigned long long z = 0ull; z < active; z += 1ull)
            {
                for (unsigned long long y = 0ull; y < active; y += 1ull)
                {
                    for (unsigned long long x = 0ull; x < active; x += 1ull)
                    {
                        const unsigned long long place[SIM_AXES] = {z, y, x};
                        const unsigned long long along = place[axis];
                        const unsigned long long line = (z * stride[0]) + (y * stride[1]) + x - (along * stride[axis]);
                        work[line + (along * stride[axis])] = match_lifted(before, line, stride[axis], active, along);
                    }
                }
            }
        }
    }
    for (unsigned long long z = 0ull; z < MATCH_FLOOR_SIDE; z += 1ull)
    {
        for (unsigned long long y = 0ull; y < MATCH_FLOOR_SIDE; y += 1ull)
        {
            for (unsigned long long x = 0ull; x < MATCH_FLOOR_SIDE; x += 1ull)
            {
                floor_values[(((z * MATCH_FLOOR_SIDE) + y) * MATCH_FLOOR_SIDE) + x] =
                    work[(z * stride[0]) + (y * stride[1]) + x];
            }
        }
    }
}

// the engine's floor 2: the tower lifts the whole frame, and the levels past floor 2 lift only its corner. The
// corner of the crystal lowered as a tower of its own side is floor 2. The lowering holds every value in the lane.
int match_floor_engine(SimResults *results, const unsigned short *device_lanes, int *crystal, int *corner,
                       unsigned short *floor_values)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    unsigned int floors = 0u;
    TowerLiftRequest lift;
    memset(&lift, 0, sizeof(lift));
    lift.device_lanes = device_lanes;
    lift.extent[0] = 1ull;
    lift.extent[1] = MATCH_SIDE;
    lift.extent[2] = MATCH_SIDE;
    lift.extent[3] = MATCH_SIDE;
    lift.coefficients = &coefficients;
    lift.scratch = &scratch;
    lift.floors = &floors;
    lift.error = &error;
    int ok = (tower_lift(&lift) == 0L) && (error.kind == ENGINE_ERROR_NONE);
    sim_check(results, ok, "the engine's tower lifts the frame");
    ok = ok &&
         sim_status_check(
             results, cudaMemcpy(crystal, coefficients, (size_t)MATCH_SAMPLES * sizeof(int), cudaMemcpyDeviceToHost),
             "crystal read");
    for (unsigned long long z = 0ull; ok && (z < MATCH_FLOOR_SIDE); z += 1ull)
    {
        for (unsigned long long y = 0ull; y < MATCH_FLOOR_SIDE; y += 1ull)
        {
            for (unsigned long long x = 0ull; x < MATCH_FLOOR_SIDE; x += 1ull)
            {
                corner[(((z * MATCH_FLOOR_SIDE) + y) * MATCH_FLOOR_SIDE) + x] =
                    crystal[(((z * MATCH_SIDE) + y) * MATCH_SIDE) + x];
            }
        }
    }
    const unsigned long long floor_extent[4] = {1ull, MATCH_FLOOR_SIDE, MATCH_FLOOR_SIDE, MATCH_FLOOR_SIDE};
    int *device_buffer = NULL;
    ok = ok && (tower_capacity(floor_extent, &device_buffer, &error) == 0L) &&
         sim_status_check(
             results,
             cudaMemcpy(device_buffer, corner, (size_t)MATCH_FLOOR_VALUES * sizeof(int), cudaMemcpyHostToDevice),
             "corner write");
    unsigned long long mismatches = 0ull;
    const unsigned short *device_rebuilt = NULL;
    TowerLowerRequest lower;
    memset(&lower, 0, sizeof(lower));
    memcpy(lower.extent, floor_extent, sizeof(lower.extent));
    lower.mismatches = &mismatches;
    lower.device_rebuilt = &device_rebuilt;
    lower.rebuilt = floor_values;
    lower.error = &error;
    ok = ok && (tower_lower(&lower) == 0L) && (error.kind == ENGINE_ERROR_NONE);
    sim_check(results, ok, "the crystal's 16^3 corner lowers as its own tower, every value inside the 16-bit lane");
    return ok;
}

// the planes: bit j of floor 2's value at position i is bit i % 32 of plane j's word i / 32, one warp a word
__global__ void match_planes_kernel(const unsigned short *floor_values, unsigned int *planes)
{
    const unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int value = floor_values[index];
    for (unsigned int bit = 0u; bit < MATCH_BITS; bit += 1u)
    {
        const unsigned int word = __ballot_sync(0xFFFFFFFFu, ((value >> bit) & 1u) != 0u);
        if ((threadIdx.x % MATCH_WORD_BITS) == 0u)
        {
            planes[((unsigned long long)bit * MATCH_WORDS) + (index / MATCH_WORD_BITS)] = word;
        }
    }
}

// one query's one word: the and over the planes, from the lowest bit up, of each plane where x's bit is 1 and its
// complement where it is 0. The word stops once its mask is empty, and its reads are the plane words it took.
__global__ void match_query_kernel(const unsigned int *planes, const unsigned int *queries, unsigned int *matches,
                                   unsigned char *reads)
{
    const unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (index >= ((unsigned long long)MATCH_QUERIES * MATCH_WORDS))
    {
        return;
    }
    const unsigned int target = queries[index / MATCH_WORDS];
    const unsigned long long word = index % MATCH_WORDS;
    unsigned int mask = 0xFFFFFFFFu;
    unsigned int taken = 0u;
    for (unsigned int bit = 0u; (bit < MATCH_BITS) && (mask != 0u); bit += 1u)
    {
        const unsigned int plane = planes[((unsigned long long)bit * MATCH_WORDS) + word];
        taken += 1u;
        mask &= (((target >> bit) & 1u) != 0u) ? plane : ~plane;
    }
    matches[index] = mask;
    // at most MATCH_BITS reads, far below a byte's range
    reads[index] = (unsigned char)taken;
}

void match_print_side(ScripturaLine *line, const char *name, const MatchSide *side)
{
    scriptura_text(line, "    ");
    scriptura_text(line, name);
    scriptura_text(line, ": ");
    scriptura_decimal(line, side->matched, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, MATCH_QUERIES_EACH, 1u);
    scriptura_text(line, " match sets equal the host's scan; positions found a query ");
    sim_fraction_print(line, side->found, MATCH_QUERIES_EACH, 2u);
    scriptura_text(line, " on average, ");
    scriptura_decimal(line, side->found_max, 1u);
    scriptura_text(line, " at most; plane words read a query ");
    sim_fraction_print(line, side->total, MATCH_QUERIES_EACH, 2u);
    scriptura_text(line, " on average, ");
    scriptura_decimal(line, side->maximum, 1u);
    scriptura_text(line, " at most\n");
}
