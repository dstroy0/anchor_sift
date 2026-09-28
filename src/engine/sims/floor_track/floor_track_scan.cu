// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// floor_track_scan.cu: range, query, bodies, the scan and gating
#include "floor_track_internal.h"

// the positions of one plane word whose value lies in [low, high], from the top bit down by ands and ors alone: a
// value stays equal to a bound while its bits agree, and leaves above the low bound or below the high one at the
// first bit where it differs the right way. Only the wanted positions are read for: the word stops once every one
// of them has left the range or left both bounds, and the others' bits are left for the caller's mask to clear.
static __device__ unsigned int track_range(const unsigned int *planes, unsigned long long word, unsigned int low,
                                           unsigned int high, unsigned int wanted, unsigned int *taken)
{
    unsigned int above = 0u;
    unsigned int below = 0u;
    unsigned int low_equal = 0xFFFFFFFFu;
    unsigned int high_equal = 0xFFFFFFFFu;
    unsigned int open = wanted;
    for (unsigned int bit = TRACK_BITS; (bit > 0u) && (open != 0u); bit -= 1u)
    {
        const unsigned int plane = planes[((unsigned long long)(bit - 1u) * TRACK_WORDS) + word];
        *taken += 1u;
        if (((low >> (bit - 1u)) & 1u) != 0u)
        {
            low_equal &= plane;
        }
        else
        {
            above |= low_equal & plane;
            low_equal &= ~plane;
        }
        if (((high >> (bit - 1u)) & 1u) != 0u)
        {
            below |= high_equal & ~plane;
            high_equal &= plane;
        }
        else
        {
            high_equal &= ~plane;
        }
        // a position is out once it has fallen below the low bound or risen above the high one
        const unsigned int out = ~(above | low_equal) | ~(below | high_equal);
        open = wanted & ~out & (low_equal | high_equal);
    }
    return (above | low_equal) & (below | high_equal);
}

// one query, one block, one word a thread: the positions p where every patch cell c lies inside floor 2 and its
// value at p + c is inside c's range. The center goes first, and a word stops once its candidates are gone.
__global__ void track_query_kernel(const unsigned int *planes, const TrackQuery *queries, unsigned int *candidates,
                                   unsigned int *reads)
{
    const TrackQuery *const query = &queries[blockIdx.x];
    const unsigned long long word = threadIdx.x;
    const unsigned int *const frame_planes = &planes[(unsigned long long)query->frame * TRACK_BITS * TRACK_WORDS];
    const long long side = (long long)TRACK_FLOOR_SIDE;
    unsigned int candidate = 0xFFFFFFFFu;
    unsigned int taken = 0u;
    for (unsigned int cell = 0u; (cell < query->count) && (candidate != 0u); cell += 1u)
    {
        const int *const step = query->step[cell];
        unsigned int inside = 0u;
        for (unsigned int bit = 0u; bit < TRACK_WORD_BITS; bit += 1u)
        {
            // a position on floor 2 is below 2^12, and a step is at most one cell each way
            const long long position = (long long)((word * TRACK_WORD_BITS) + bit);
            const long long x = (position % side) + step[2];
            const long long y = ((position / side) % side) + step[1];
            const long long z = (position / (side * side)) + step[0];
            const int ok = (x >= 0ll) && (x < side) && (y >= 0ll) && (y < side) && (z >= 0ll) && (z < side);
            inside |= ((ok != 0) ? 1u : 0u) << bit;
        }
        candidate &= inside;
        if (candidate != 0u)
        {
            // position p reads p + c: the word's first position moved by c, split into a word and a bit, floored;
            // the first position is below 2^12, and a source word is taken unsigned only once it is found inside
            const long long first = (long long)(word * TRACK_WORD_BITS) + ((long long)step[0] * side * side) +
                                    ((long long)step[1] * side) + (long long)step[2];
            const long long source = (first >= 0ll) ? (first / 32ll) : -(((-first) + 31ll) / 32ll);
            // the remainder of a floored division by 32 lies in [0, 32)
            const unsigned int shift = (unsigned int)(first - (source * 32ll));
            const long long words = (long long)TRACK_WORDS;
            // candidate bit b reads bit b + shift of the source word, or bit b + shift - 32 of the word after it
            const unsigned int lower_wanted = candidate << shift;
            const unsigned int upper_wanted = (shift != 0u) ? (candidate >> (32u - shift)) : 0u;
            const unsigned int lower = ((source >= 0ll) && (source < words) && (lower_wanted != 0u))
                                           ? track_range(frame_planes, (unsigned long long)source, query->low[cell],
                                                         query->high[cell], lower_wanted, &taken)
                                           : 0u;
            unsigned int upper = 0u;
            if ((upper_wanted != 0u) && ((source + 1ll) >= 0ll) && ((source + 1ll) < words))
            {
                upper = track_range(frame_planes, (unsigned long long)(source + 1ll), query->low[cell],
                                    query->high[cell], upper_wanted, &taken);
            }
            candidate &= (shift == 0u) ? lower : ((lower >> shift) | (upper << (32u - shift)));
        }
    }
    candidates[((unsigned long long)blockIdx.x * TRACK_WORDS) + word] = candidate;
    reads[((unsigned long long)blockIdx.x * TRACK_WORDS) + word] = taken;
}

// a body's floor-2 cell at a frame: its center's cell along each axis, as a position on floor 2
unsigned long long track_body_cell(const SimBody *body, unsigned long long frame)
{
    unsigned long long cell[SIM_AXES];
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        // a body here stays inside the view. Its center is non-negative
        cell[axis] = (unsigned long long)(sim_body_at(body, frame, axis) / TRACK_CELL);
    }
    return (((cell[0] * TRACK_FLOOR_SIDE) + cell[1]) * TRACK_FLOOR_SIDE) + cell[2];
}

// the control's bodies: all move by one floor-2 cell a frame along y and x, and none nears an edge in any frame
void track_control_bodies(SimBody *body, unsigned long long frames)
{
    SimDraws draws;
    draws.key = TRACK_KEY ^ TRACK_CONTROL_PURPOSE;
    draws.counter = 0ull;
    for (unsigned int index = 0u; index < TRACK_CONTROL_BODIES; index += 1u)
    {
        SimBody *const one = &body[index];
        // each draw is a few tens of voxels, far inside a long long
        one->center[0] = (long long)sim_draws_between(&draws, 14ull, 50ull);
        one->center[1] = (long long)sim_draws_between(&draws, 20ull, 36ull);
        one->center[2] = (long long)sim_draws_between(&draws, 20ull, 36ull);
        one->velocity[0] = 0ll;
        one->velocity[1] = TRACK_CELL;
        one->velocity[2] = TRACK_CELL;
        one->range[0] = (long long)sim_draws_between(&draws, 2ull, 3ull);
        one->range[1] = (long long)sim_draws_between(&draws, 4ull, 7ull);
        one->range[2] = (long long)sim_draws_between(&draws, 4ull, 7ull);
        one->brightness = sim_draws_between(&draws, 150ull, 400ull);
        one->born = 0ull;
        one->ended = frames;
        one->parent = -1ll;
    }
}

// the host's scan of one query: every position whose patch lies inside floor 2 with every value in range
void track_scan(const TrackQuery *query, const unsigned short *floor_values, unsigned int *expected)
{
    const long long side = (long long)TRACK_FLOOR_SIDE;
    memset(expected, 0, (size_t)TRACK_WORDS * sizeof(unsigned int));
    for (long long position = 0ll; position < (long long)TRACK_FLOOR_VALUES; position += 1ll)
    {
        int ok = 1;
        for (unsigned int cell = 0u; ok && (cell < query->count); cell += 1u)
        {
            const long long x = (position % side) + query->step[cell][2];
            const long long y = ((position / side) % side) + query->step[cell][1];
            const long long z = (position / (side * side)) + query->step[cell][0];
            ok = (x >= 0ll) && (x < side) && (y >= 0ll) && (y < side) && (z >= 0ll) && (z < side);
            if (ok)
            {
                const unsigned int value = floor_values[(((z * side) + y) * side) + x];
                ok = (value >= query->low[cell]) && (value <= query->high[cell]);
            }
        }
        if (ok)
        {
            expected[position / (long long)TRACK_WORD_BITS] |= 1u << (position % (long long)TRACK_WORD_BITS);
        }
    }
}

// the positions within one cell of `from` along every axis, the gate a body moving under a cell a frame keeps to
int track_gated(unsigned long long from, unsigned long long position)
{
    const long long side = (long long)TRACK_FLOOR_SIDE;
    // both positions are below 2^12
    const long long a = (long long)from;
    const long long b = (long long)position;
    const long long dz = (a / (side * side)) - (b / (side * side));
    const long long dy = ((a / side) % side) - ((b / side) % side);
    const long long dx = (a % side) - (b % side);
    return (dz >= -1ll) && (dz <= 1ll) && (dy >= -1ll) && (dy <= 1ll) && (dx >= -1ll) && (dx <= 1ll);
}

// a body's step is clear when, in both frames, no other body reaches the samples its 27 cells read, and those cells
// sit where every lifting formula along y and x is the interior one. The z pass acts on each column alone. A
// shift along y and x carries it whole, edges and all. A clear step of whole cells translates floor 2 exactly.
int track_clear(const SimScene *scene, unsigned int index, unsigned long long frame, unsigned long long stride,
                unsigned long long from, unsigned long long truth)
{
    const long long side = (long long)TRACK_FLOOR_SIDE;
    const unsigned long long ends[2] = {frame, frame + stride};
    const unsigned long long cells[2] = {from, truth};
    int clear = 1;
    for (unsigned int end = 0u; clear && (end < 2u); end += 1u)
    {
        // a position on floor 2 is below 2^12
        const long long place = (long long)cells[end];
        const long long cell[SIM_AXES] = {place / (side * side), (place / side) % side, place % side};
        for (unsigned int axis = 1u; axis < SIM_AXES; axis += 1u)
        {
            clear = clear && (cell[axis] >= TRACK_CLEAR_FIRST) && (cell[axis] <= TRACK_CLEAR_LAST);
        }
        for (unsigned int other = 0u; clear && (other < scene->bodies); other += 1u)
        {
            const SimBody *const body = &scene->body[other];
            int meets = (other != index);
            for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
            {
                const long long center = sim_body_at(body, ends[end], axis);
                const long long low = (TRACK_CELL * (cell[axis] - 1ll)) - TRACK_SUPPORT;
                const long long high = (TRACK_CELL * (cell[axis] + 1ll)) + TRACK_SUPPORT;
                meets = meets && ((center + body->range[axis]) >= low) && ((center - body->range[axis]) <= high);
            }
            clear = clear && (meets == 0);
        }
    }
    return clear;
}
