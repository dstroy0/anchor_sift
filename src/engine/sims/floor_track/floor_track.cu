// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Floor 2 matched across frames (Doug, 25 September: "build the cross frame match"). Every frame's floor 2 is the
// engine's, the crystal's 16^3 corner lowered as its own tower, held to the host's two-level lifting, and laid once as
// 16 bit planes. A body's signature is its patch of floor-2 values in frame t: its own cell alone, or the 27 cells
// around it. The later frame is searched whole with no value read: each patch cell's range [v - d, v + d] is taken
// on the planes by ands and ors alone, shifted to the patch centre, and the patch's masks anded, a word stopping once
// it is empty. The truth is each body's own path. A control moves every body exactly one floor-2 cell a frame with no
// noise and no ramp, so floor 2 translates exactly and a tolerance of 0 must find every body. The camera law then
// moves bodies a voxel a frame under shot and read noise. From frame t to t + 1 that is a quarter of a floor-2 cell,
// and the decimated floor is not shift-invariant under it; from t to t + 4, floor 2's own time step, it is a whole
// cell again. The 27 cells read the samples within 10 of the body's cell, so a body another body reaches there does
// not translate alone: the camera law's bodies are run again with no noise, and three of them are set apart along z,
// with the noise and without it, where every step is clear and a tolerance of 0 must find every one. The hits, the
// false candidates and the plane words read are counted at every tolerance. Every candidate set is held to the
// host's scan.
#include "sim_camera.h"

#include "tower.h"

#define TRACK_KEY 0x545241434Bull

#define TRACK_CONTROL_PURPOSE 0x434F4E54ull

#define TRACK_FOUNDER_PURPOSE 0x464F554Eull

#define TRACK_SIDE 64ull

#define TRACK_FLOOR 2u

#define TRACK_FLOOR_SIDE (TRACK_SIDE >> TRACK_FLOOR)

// a floor-2 cell covers this many samples along each axis
#define TRACK_CELL (1ll << TRACK_FLOOR)

// a floor-2 value reads the samples within 6 of its centre: two levels of the 5/3 lowpass, 2 + 2 * 2
#define TRACK_SUPPORT 6ll

// the patch centres whose 27 cells, along one axis, every lifting formula takes in its interior form
#define TRACK_CLEAR_FIRST 3ll

#define TRACK_CLEAR_LAST 13ll

#define TRACK_SAMPLES (TRACK_SIDE * TRACK_SIDE * TRACK_SIDE)

#define TRACK_FLOOR_VALUES (TRACK_FLOOR_SIDE * TRACK_FLOOR_SIDE * TRACK_FLOOR_SIDE)

#define TRACK_BITS 16u

#define TRACK_WORD_BITS 32ull

#define TRACK_WORDS (TRACK_FLOOR_VALUES / TRACK_WORD_BITS)

#define TRACK_VALUE_MOST 65535u

#define TRACK_PATCH_MOST 27u

#define TRACK_PATCHES 2u

#define TRACK_DELTAS 6u

#define TRACK_CONTROL_FRAMES 3ull

#define TRACK_CAMERA_FRAMES 9ull

#define TRACK_FRAMES_MOST TRACK_CAMERA_FRAMES

#define TRACK_CONTROL_BODIES 8u

#define TRACK_CAMERA_BODIES 10u

#define TRACK_BODIES_MOST TRACK_CAMERA_BODIES

// the sparse scene: three of the camera law's bodies, set 22 apart along z, where the most a footprint and a body
// reach toward each other is 13 + 3
#define TRACK_SPARSE_BODIES 3u

#define TRACK_SPARSE_FIRST_Z 10ll

#define TRACK_SPARSE_Z_STEP 22ll

#define TRACK_QUERIES_MOST (TRACK_BODIES_MOST * (TRACK_FRAMES_MOST - 1ull) * TRACK_PATCHES * TRACK_DELTAS)

#define TRACK_THREADS 256ull

static_assert(TRACK_WORDS <= 1024ull, "one block holds a query, one thread a word");

static_assert((TRACK_FLOOR_VALUES % TRACK_THREADS) == 0ull, "the plane kernel's blocks are whole warps");

// the tolerances d, and the patch sizes: the body's own cell, then its 27
static const unsigned int s_track_deltas[TRACK_DELTAS] = {0u, 4u, 8u, 16u, 32u, 64u};

static const unsigned int s_track_patch_cells[TRACK_PATCHES] = {1u, TRACK_PATCH_MOST};

// one query: the frame searched, and each patch cell's step from the centre and its range of values
typedef struct
{
    unsigned int frame;
    unsigned int count;
    int step[TRACK_PATCH_MOST][SIM_AXES];
    unsigned int low[TRACK_PATCH_MOST];
    unsigned int high[TRACK_PATCH_MOST];
} TrackQuery;

// what a query is graded by: the setting it belongs to, the body's cell in each of the two frames, and whether the
// step is clear of other bodies and of the edges
typedef struct
{
    unsigned int patch;
    unsigned int delta;
    unsigned long long from;
    unsigned long long truth;
    int clear;
} TrackTruth;

// one setting's counts over its queries
typedef struct
{
    unsigned long long queries;
    unsigned long long hits;
    unsigned long long candidates;
    unsigned long long candidates_most;
    unsigned long long gated;
    unsigned long long alone;
    unsigned long long reads;
    unsigned long long reads_most;
    unsigned long long clear;
    unsigned long long clear_hits;
} TrackSetting;

// the host buffers one scene needs
typedef struct
{
    unsigned short *lanes;
    int *crystal;
    int *corner;
    unsigned short *floors;
    long long *work;
    long long *before;
    long long *floor_host;
    unsigned int *planes;
    TrackQuery *queries;
    TrackTruth *truths;
    unsigned int *candidates;
    unsigned int *reads;
    unsigned int *expected;
} TrackHost;

// the device buffers one scene needs
typedef struct
{
    unsigned short *lanes;
    unsigned short *floors;
    unsigned int *planes;
    TrackQuery *queries;
    unsigned int *candidates;
    unsigned int *reads;
} TrackDevice;

// what the sim puts on the device at once: the longest scene's frames, the tower's two held coefficient arrays,
// floor 2 and its planes for every frame, the queries, and each query's candidate word and reads for every word
#define TRACK_DECLARED \
    ((TRACK_FRAMES_MOST * TRACK_SAMPLES * sizeof(unsigned short)) + (2ull * TRACK_SAMPLES * sizeof(int)) \
     + (TRACK_FRAMES_MOST * TRACK_FLOOR_VALUES * sizeof(unsigned short)) \
     + (TRACK_FRAMES_MOST * TRACK_BITS * TRACK_WORDS * sizeof(unsigned int)) \
     + (TRACK_QUERIES_MOST * sizeof(TrackQuery)) \
     + (2ull * TRACK_QUERIES_MOST * TRACK_WORDS * sizeof(unsigned int)))

// the tower's own floor shift, toward minus infinity, as tower.cu takes it
static long long track_floor_shift(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -(((-value) + (1ll << shift) - 1ll) >> shift);
}

// the high d_j of one line, as tower.cu's forward kernel reads it: the edge repeats its left neighbour
static long long track_high(const long long *from, unsigned long long line, unsigned long long stride,
                            unsigned long long length, unsigned long long j)
{
    const long long left = from[line + (2ull * j * stride)];
    const long long right = ((2ull * j) + 2ull < length) ? from[line + (((2ull * j) + 2ull) * stride)] : left;
    return from[line + (((2ull * j) + 1ull) * stride)] - track_floor_shift(left + right, 1u);
}

// one coefficient of one line after the lifting along it: the lows first, then the highs
static long long track_lifted(const long long *from, unsigned long long line, unsigned long long stride,
                              unsigned long long length, unsigned long long along)
{
    const unsigned long long lows = (length + 1ull) / 2ull;
    const unsigned long long highs = length / 2ull;
    if (along >= lows)
    {
        return track_high(from, line, stride, length, along - lows);
    }
    const long long before = (along > 0ull) ? track_high(from, line, stride, length, along - 1ull)
                                            : track_high(from, line, stride, length, 0ull);
    const long long after = (along < highs) ? track_high(from, line, stride, length, along) : before;
    return from[line + (2ull * along * stride)] + track_floor_shift(before + after + 2ll, 2u);
}

// the host's floor 2 of one frame: two levels of the 5/3 lifting, each along z, then y, then x over the active
// corner, every axis pass reading the coefficients as they stood before it, as the engine's kernels do
static void track_floor_host(const unsigned short *lanes, long long *work, long long *before, long long *floor_values)
{
    const unsigned long long stride[SIM_AXES] = {TRACK_SIDE * TRACK_SIDE, TRACK_SIDE, 1ull};
    for (unsigned long long sample = 0ull; sample < TRACK_SAMPLES; sample += 1ull)
    {
        work[sample] = (long long)lanes[sample];
    }
    for (unsigned int level = 0u; level < TRACK_FLOOR; level += 1u)
    {
        const unsigned long long active = TRACK_SIDE >> level;
        for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
        {
            memcpy(before, work, (size_t)TRACK_SAMPLES * sizeof(long long));
            for (unsigned long long z = 0ull; z < active; z += 1ull)
            {
                for (unsigned long long y = 0ull; y < active; y += 1ull)
                {
                    for (unsigned long long x = 0ull; x < active; x += 1ull)
                    {
                        const unsigned long long place[SIM_AXES] = {z, y, x};
                        const unsigned long long along = place[axis];
                        const unsigned long long line = (z * stride[0]) + (y * stride[1]) + x - (along * stride[axis]);
                        work[line + (along * stride[axis])] = track_lifted(before, line, stride[axis], active, along);
                    }
                }
            }
        }
    }
    for (unsigned long long z = 0ull; z < TRACK_FLOOR_SIDE; z += 1ull)
    {
        for (unsigned long long y = 0ull; y < TRACK_FLOOR_SIDE; y += 1ull)
        {
            for (unsigned long long x = 0ull; x < TRACK_FLOOR_SIDE; x += 1ull)
            {
                floor_values[(((z * TRACK_FLOOR_SIDE) + y) * TRACK_FLOOR_SIDE) + x]
                    = work[(z * stride[0]) + (y * stride[1]) + x];
            }
        }
    }
}

// the engine's floor 2 of one frame: the tower lifts the frame, and the levels past floor 2 lift only its corner, so
// the crystal's corner lowered as a tower of its own side is floor 2, every value held inside the lane
static int track_floor_engine(const unsigned short *device_lanes, int *crystal, int *corner,
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
    lift.extent[1] = TRACK_SIDE;
    lift.extent[2] = TRACK_SIDE;
    lift.extent[3] = TRACK_SIDE;
    lift.coefficients = &coefficients;
    lift.scratch = &scratch;
    lift.floors = &floors;
    lift.error = &error;
    int good = (tower_lift(&lift) == 0L) && (error.kind == ENGINE_ERROR_NONE)
            && (cudaMemcpy(crystal, coefficients, (size_t)TRACK_SAMPLES * sizeof(int), cudaMemcpyDeviceToHost)
                == cudaSuccess);
    for (unsigned long long z = 0ull; good && (z < TRACK_FLOOR_SIDE); z += 1ull)
    {
        for (unsigned long long y = 0ull; y < TRACK_FLOOR_SIDE; y += 1ull)
        {
            for (unsigned long long x = 0ull; x < TRACK_FLOOR_SIDE; x += 1ull)
            {
                corner[(((z * TRACK_FLOOR_SIDE) + y) * TRACK_FLOOR_SIDE) + x]
                    = crystal[(((z * TRACK_SIDE) + y) * TRACK_SIDE) + x];
            }
        }
    }
    const unsigned long long floor_extent[4] = {1ull, TRACK_FLOOR_SIDE, TRACK_FLOOR_SIDE, TRACK_FLOOR_SIDE};
    int *room = NULL;
    good = good && (tower_room(floor_extent, &room, &error) == 0L)
        && (cudaMemcpy(room, corner, (size_t)TRACK_FLOOR_VALUES * sizeof(int), cudaMemcpyHostToDevice) == cudaSuccess);
    unsigned long long mismatches = 0ull;
    const unsigned short *device_rebuilt = NULL;
    TowerLowerRequest lower;
    memset(&lower, 0, sizeof(lower));
    memcpy(lower.extent, floor_extent, sizeof(lower.extent));
    lower.mismatches = &mismatches;
    lower.device_rebuilt = &device_rebuilt;
    lower.rebuilt = floor_values;
    lower.error = &error;
    return good && (tower_lower(&lower) == 0L) && (error.kind == ENGINE_ERROR_NONE);
}

// the planes: bit j of floor 2's value at position i is bit i % 32 of plane j's word i / 32, one warp a word
static __global__ void track_planes_kernel(const unsigned short *floor_values, unsigned int *planes)
{
    const unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned int value = floor_values[index];
    for (unsigned int bit = 0u; bit < TRACK_BITS; bit += 1u)
    {
        const unsigned int word = __ballot_sync(0xFFFFFFFFu, ((value >> bit) & 1u) != 0u);
        if ((threadIdx.x % TRACK_WORD_BITS) == 0u)
        {
            planes[((unsigned long long)bit * TRACK_WORDS) + (index / TRACK_WORD_BITS)] = word;
        }
    }
}

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
// value at p + c is inside c's range. The centre goes first, and a word stops once its candidates are gone.
static __global__ void track_query_kernel(const unsigned int *planes, const TrackQuery *queries,
                                          unsigned int *candidates, unsigned int *reads)
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
            const int held = (x >= 0ll) && (x < side) && (y >= 0ll) && (y < side) && (z >= 0ll) && (z < side);
            inside |= ((held != 0) ? 1u : 0u) << bit;
        }
        candidate &= inside;
        if (candidate != 0u)
        {
            // position p reads p + c: the word's first position moved by c, split into a word and a bit, floored;
            // the first position is below 2^12, and a source word is taken unsigned only once it is found inside
            const long long first = (long long)(word * TRACK_WORD_BITS) + ((long long)step[0] * side * side)
                                  + ((long long)step[1] * side) + (long long)step[2];
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

// a body's floor-2 cell at a frame: its centre's cell along each axis, as a position on floor 2
static unsigned long long track_body_cell(const SimBody *body, unsigned long long frame)
{
    unsigned long long cell[SIM_AXES];
    for (unsigned int axis = 0u; axis < SIM_AXES; axis += 1u)
    {
        // a body here stays inside the view, so its centre is non-negative
        cell[axis] = (unsigned long long)(sim_body_at(body, frame, axis) / TRACK_CELL);
    }
    return (((cell[0] * TRACK_FLOOR_SIDE) + cell[1]) * TRACK_FLOOR_SIDE) + cell[2];
}

// the control's bodies: all move by one floor-2 cell a frame along y and x, and none nears an edge in any frame
static void track_control_bodies(SimBody *body, unsigned long long frames)
{
    SimDraws draws;
    draws.key = TRACK_KEY ^ TRACK_CONTROL_PURPOSE;
    draws.counter = 0ull;
    for (unsigned int index = 0u; index < TRACK_CONTROL_BODIES; index += 1u)
    {
        SimBody *const one = &body[index];
        // each draw is a few tens of voxels, far inside a long long
        one->centre[0] = (long long)sim_draws_between(&draws, 14ull, 50ull);
        one->centre[1] = (long long)sim_draws_between(&draws, 20ull, 36ull);
        one->centre[2] = (long long)sim_draws_between(&draws, 20ull, 36ull);
        one->velocity[0] = 0ll;
        one->velocity[1] = TRACK_CELL;
        one->velocity[2] = TRACK_CELL;
        one->reach[0] = (long long)sim_draws_between(&draws, 2ull, 3ull);
        one->reach[1] = (long long)sim_draws_between(&draws, 4ull, 7ull);
        one->reach[2] = (long long)sim_draws_between(&draws, 4ull, 7ull);
        one->brightness = sim_draws_between(&draws, 150ull, 400ull);
        one->born = 0ull;
        one->ended = frames;
        one->parent = -1ll;
    }
}

// the host's scan of one query: every position whose patch lies inside floor 2 with every value in range
static void track_scan(const TrackQuery *query, const unsigned short *floor_values, unsigned int *expected)
{
    const long long side = (long long)TRACK_FLOOR_SIDE;
    memset(expected, 0, (size_t)TRACK_WORDS * sizeof(unsigned int));
    for (long long position = 0ll; position < (long long)TRACK_FLOOR_VALUES; position += 1ll)
    {
        int held = 1;
        for (unsigned int cell = 0u; held && (cell < query->count); cell += 1u)
        {
            const long long x = (position % side) + query->step[cell][2];
            const long long y = ((position / side) % side) + query->step[cell][1];
            const long long z = (position / (side * side)) + query->step[cell][0];
            held = (x >= 0ll) && (x < side) && (y >= 0ll) && (y < side) && (z >= 0ll) && (z < side);
            if (held)
            {
                const unsigned int value = floor_values[(((z * side) + y) * side) + x];
                held = (value >= query->low[cell]) && (value <= query->high[cell]);
            }
        }
        if (held)
        {
            expected[position / (long long)TRACK_WORD_BITS] |= 1u << (position % (long long)TRACK_WORD_BITS);
        }
    }
}

// the positions within one cell of `from` along every axis, the gate a body moving under a cell a frame keeps to
static int track_gated(unsigned long long from, unsigned long long position)
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
// sit where every lifting formula along y and x is the interior one. The z pass acts on each column alone, so a
// shift along y and x carries it whole, edges and all. A clear step of whole cells translates floor 2 exactly.
static int track_clear(const SimScene *scene, unsigned int index, unsigned long long frame, unsigned long long stride,
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
                const long long centre = sim_body_at(body, ends[end], axis);
                const long long low = (TRACK_CELL * (cell[axis] - 1ll)) - TRACK_SUPPORT;
                const long long high = (TRACK_CELL * (cell[axis] + 1ll)) + TRACK_SUPPORT;
                meets = meets && ((centre + body->reach[axis]) >= low) && ((centre - body->reach[axis]) <= high);
            }
            clear = clear && (meets == 0);
        }
    }
    return clear;
}

// one scene: render its frames, take every frame's floor 2 from the engine and hold it to the host, lay the planes,
// build a query for every body, step of `stride` frames, patch and tolerance, run them, and grade them by the
// bodies' paths
static int track_scene(SimTally *tally, const char *name, const SimScene *scene, const SimCamera *camera,
                       unsigned long long stride, TrackHost *host, TrackDevice *device,
                       TrackSetting settings[TRACK_PATCHES][TRACK_DELTAS], unsigned int deltas)
{
    const unsigned long long frames = scene->frames;
    unsigned long long clipped = 0ull;
    int good = sim_render(tally, scene, camera, device->lanes, NULL, NULL, &clipped);
    sim_check(tally, good && (clipped == 0ull), "the scene's frames render with nothing clipped");
    const size_t frame_bytes = (size_t)(frames * TRACK_SAMPLES) * sizeof(unsigned short);
    good = good && (clipped == 0ull)
        && sim_took(tally, cudaMemcpy(host->lanes, device->lanes, frame_bytes, cudaMemcpyDeviceToHost), "frames read");
    int lowered = good;
    unsigned long long equal = 0ull;
    for (unsigned long long frame = 0ull; good && (frame < frames); frame += 1ull)
    {
        unsigned short *const floor_values = &host->floors[frame * TRACK_FLOOR_VALUES];
        lowered = lowered && track_floor_engine(&device->lanes[frame * TRACK_SAMPLES], host->crystal, host->corner,
                                                floor_values);
        track_floor_host(&host->lanes[frame * TRACK_SAMPLES], host->work, host->before, host->floor_host);
        for (unsigned long long at = 0ull; lowered && (at < TRACK_FLOOR_VALUES); at += 1ull)
        {
            equal += (host->floor_host[at] == (long long)floor_values[at]) ? 1ull : 0ull;
        }
    }
    sim_check(tally, good && lowered, "the engine's tower lifts every frame and its corner lowers inside the lane");
    good = good && lowered;
    sim_check(tally, good && (equal == (frames * TRACK_FLOOR_VALUES)),
              "every frame's floor 2 equals the host's two-level lifting at every coefficient");

    // the planes of every frame, laid once
    good = good && sim_took(tally, cudaMemcpy(device->floors, host->floors,
                                              (size_t)(frames * TRACK_FLOOR_VALUES) * sizeof(unsigned short),
                                              cudaMemcpyHostToDevice), "floors write");
    for (unsigned long long frame = 0ull; good && (frame < frames); frame += 1ull)
    {
        // floor 2's values fill whole blocks, far fewer than 2^31
        track_planes_kernel<<<(unsigned int)(TRACK_FLOOR_VALUES / TRACK_THREADS), (unsigned int)TRACK_THREADS>>>(
            &device->floors[frame * TRACK_FLOOR_VALUES], &device->planes[frame * TRACK_BITS * TRACK_WORDS]);
        good = sim_took(tally, cudaGetLastError(), "planes launch");
    }
    good = good && sim_took(tally, cudaDeviceSynchronize(), "planes run")
        && sim_took(tally, cudaMemcpy(host->planes, device->planes,
                                      (size_t)(frames * TRACK_BITS * TRACK_WORDS) * sizeof(unsigned int),
                                      cudaMemcpyDeviceToHost), "planes read");
    unsigned long long bits_held = 0ull;
    for (unsigned long long frame = 0ull; good && (frame < frames); frame += 1ull)
    {
        for (unsigned long long at = 0ull; at < TRACK_FLOOR_VALUES; at += 1ull)
        {
            const unsigned int value = host->floors[(frame * TRACK_FLOOR_VALUES) + at];
            for (unsigned int bit = 0u; bit < TRACK_BITS; bit += 1u)
            {
                const unsigned long long word = (((frame * TRACK_BITS) + bit) * TRACK_WORDS) + (at / TRACK_WORD_BITS);
                const unsigned int laid = (host->planes[word] >> (at % TRACK_WORD_BITS)) & 1u;
                bits_held += (laid == ((value >> bit) & 1u)) ? 1ull : 0ull;
            }
        }
    }
    sim_check(tally, good && (bits_held == (frames * TRACK_FLOOR_VALUES * TRACK_BITS)),
              "every frame's 16 planes hold every bit of its floor 2");

    // the queries: a body's patch at frame t, its values' ranges, searched in frame t + stride
    unsigned int count = 0u;
    for (unsigned int index = 0u; good && (index < scene->bodies); index += 1u)
    {
        const SimBody *const body = &scene->body[index];
        for (unsigned long long frame = 0ull; (frame + stride) < frames; frame += 1ull)
        {
            const unsigned long long from = track_body_cell(body, frame);
            const unsigned long long truth = track_body_cell(body, frame + stride);
            const int clear = track_clear(scene, index, frame, stride, from, truth);
            // the cell's coordinates on floor 2, each below 16
            const long long centre[SIM_AXES] = {(long long)(from / (TRACK_FLOOR_SIDE * TRACK_FLOOR_SIDE)),
                                                (long long)((from / TRACK_FLOOR_SIDE) % TRACK_FLOOR_SIDE),
                                                (long long)(from % TRACK_FLOOR_SIDE)};
            for (unsigned int patch = 0u; patch < TRACK_PATCHES; patch += 1u)
            {
                for (unsigned int delta = 0u; delta < deltas; delta += 1u)
                {
                    TrackQuery *const query = &host->queries[count];
                    memset(query, 0, sizeof(*query));
                    // frame t + stride is below the scene's frame count, far under 2^32
                    query->frame = (unsigned int)(frame + stride);
                    for (unsigned int cell = 0u; cell < TRACK_PATCH_MOST; cell += 1u)
                    {
                        // the centre first, then the other 26 in order; each digit of the order is 0, 1 or 2, so
                        // every step is -1, 0 or 1 once the digit is taken signed
                        const unsigned int order = (cell == 0u) ? 13u : ((cell <= 13u) ? (cell - 1u) : cell);
                        const int step[SIM_AXES] = {(int)(order / 9u) - 1, (int)((order / 3u) % 3u) - 1,
                                                    (int)(order % 3u) - 1};
                        const long long at[SIM_AXES] = {centre[0] + step[0], centre[1] + step[1], centre[2] + step[2]};
                        const long long side = (long long)TRACK_FLOOR_SIDE;
                        const int inside = (at[0] >= 0ll) && (at[0] < side) && (at[1] >= 0ll) && (at[1] < side)
                                        && (at[2] >= 0ll) && (at[2] < side);
                        if ((inside == 0) || (query->count >= s_track_patch_cells[patch]))
                        {
                            continue;
                        }
                        // the cell is inside floor 2 just above, so its position is non-negative and below 2^12
                        const unsigned long long place
                            = (unsigned long long)((((at[0] * side) + at[1]) * side) + at[2]);
                        const unsigned int value = host->floors[(frame * TRACK_FLOOR_VALUES) + place];
                        const unsigned int reach = s_track_deltas[delta];
                        memcpy(query->step[query->count], step, sizeof(step));
                        query->low[query->count] = (value > reach) ? (value - reach) : 0u;
                        query->high[query->count]
                            = ((TRACK_VALUE_MOST - value) > reach) ? (value + reach) : TRACK_VALUE_MOST;
                        query->count += 1u;
                    }
                    host->truths[count].patch = patch;
                    host->truths[count].delta = delta;
                    host->truths[count].from = from;
                    host->truths[count].truth = truth;
                    host->truths[count].clear = clear;
                    count += 1u;
                }
            }
        }
    }
    good = good && sim_took(tally, cudaMemcpy(device->queries, host->queries, (size_t)count * sizeof(TrackQuery),
                                              cudaMemcpyHostToDevice), "queries write");
    if (good && (count != 0u))
    {
        track_query_kernel<<<count, (unsigned int)TRACK_WORDS>>>(device->planes, device->queries, device->candidates,
                                                                device->reads);
        good = sim_took(tally, cudaGetLastError(), "query launch")
            && sim_took(tally, cudaDeviceSynchronize(), "query run")
            && sim_took(tally, cudaMemcpy(host->candidates, device->candidates,
                                          (size_t)count * TRACK_WORDS * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                        "candidates read")
            && sim_took(tally, cudaMemcpy(host->reads, device->reads,
                                          (size_t)count * TRACK_WORDS * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                        "reads read");
    }

    // every candidate set against the host's scan, then graded by the body's path
    unsigned long long scanned = 0ull;
    for (unsigned int index = 0u; good && (index < count); index += 1u)
    {
        const TrackQuery *const query = &host->queries[index];
        const TrackTruth *const truth = &host->truths[index];
        TrackSetting *const setting = &settings[truth->patch][truth->delta];
        track_scan(query, &host->floors[(unsigned long long)query->frame * TRACK_FLOOR_VALUES], host->expected);
        const unsigned int *const found = &host->candidates[(unsigned long long)index * TRACK_WORDS];
        int same = 1;
        unsigned long long candidates = 0ull;
        unsigned long long gated = 0ull;
        unsigned long long taken = 0ull;
        for (unsigned long long word = 0ull; word < TRACK_WORDS; word += 1ull)
        {
            same = same && (found[word] == host->expected[word]);
            candidates += sim_bits_set((unsigned long long)found[word]);
            taken += host->reads[((unsigned long long)index * TRACK_WORDS) + word];
            for (unsigned int bit = 0u; bit < TRACK_WORD_BITS; bit += 1u)
            {
                if (((found[word] >> bit) & 1u) != 0u)
                {
                    gated += (track_gated(truth->from, (word * TRACK_WORD_BITS) + bit) != 0) ? 1ull : 0ull;
                }
            }
        }
        const int hit = ((found[truth->truth / TRACK_WORD_BITS] >> (truth->truth % TRACK_WORD_BITS)) & 1u) != 0u;
        scanned += (same != 0) ? 1ull : 0ull;
        setting->queries += 1ull;
        setting->hits += (hit != 0) ? 1ull : 0ull;
        setting->candidates += candidates;
        setting->candidates_most = (candidates > setting->candidates_most) ? candidates : setting->candidates_most;
        setting->gated += gated;
        setting->alone += ((hit != 0) && (gated == 1ull)) ? 1ull : 0ull;
        setting->reads += taken;
        setting->reads_most = (taken > setting->reads_most) ? taken : setting->reads_most;
        setting->clear += (truth->clear != 0) ? 1ull : 0ull;
        setting->clear_hits += ((truth->clear != 0) && (hit != 0)) ? 1ull : 0ull;
    }
    sim_check(tally, good && (scanned == count),
              "every candidate set equals the host's scan of the later frame's floor 2");

    ScripturaLine *const line = &tally->line;
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, ": ");
    scriptura_decimal(line, scene->bodies, 1u);
    scriptura_text(line, " bodies over ");
    scriptura_decimal(line, frames, 1u);
    scriptura_text(line, " frames, frame t to t + ");
    scriptura_decimal(line, stride, 1u);
    scriptura_text(line, ", ");
    scriptura_decimal(line, count, 1u);
    scriptura_text(line, " queries; half of a frame is ");
    scriptura_decimal(line, TRACK_SAMPLES / 2ull, 1u);
    scriptura_text(line, " samples, ");
    scriptura_decimal(line, TRACK_SAMPLES, 1u);
    scriptura_text(line, " bytes\n");
    for (unsigned int patch = 0u; patch < TRACK_PATCHES; patch += 1u)
    {
        for (unsigned int delta = 0u; delta < deltas; delta += 1u)
        {
            const TrackSetting *const setting = &settings[patch][delta];
            scriptura_text(line, "    patch ");
            scriptura_decimal_columns(line, s_track_patch_cells[patch], 2u);
            scriptura_text(line, ", d ");
            scriptura_decimal_columns(line, s_track_deltas[delta], 2u);
            scriptura_text(line, ": found ");
            scriptura_decimal(line, setting->hits, 1u);
            scriptura_text(line, " of ");
            scriptura_decimal(line, setting->queries, 1u);
            scriptura_text(line, " (clear steps ");
            scriptura_decimal(line, setting->clear_hits, 1u);
            scriptura_text(line, " of ");
            scriptura_decimal(line, setting->clear, 1u);
            scriptura_text(line, "), alone in the gate on ");
            scriptura_decimal(line, setting->alone, 1u);
            scriptura_text(line, "; candidates a query ");
            sim_fraction_print(line, setting->candidates, setting->queries, 2u);
            scriptura_text(line, " (most ");
            scriptura_decimal(line, setting->candidates_most, 1u);
            scriptura_text(line, "), in the gate ");
            sim_fraction_print(line, setting->gated, setting->queries, 2u);
            scriptura_text(line, "; plane words read ");
            sim_fraction_print(line, setting->reads, setting->queries, 1u);
            scriptura_text(line, " (most ");
            scriptura_decimal(line, setting->reads_most, 1u);
            scriptura_text(line, ", ");
            scriptura_decimal(line, 4ull * setting->reads_most, 1u);
            scriptura_text(line, " bytes)\n");
        }
    }
    sim_flush(tally);
    return good;
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    TrackHost host;
    host.lanes = (unsigned short *)malloc((size_t)(TRACK_FRAMES_MOST * TRACK_SAMPLES) * sizeof(unsigned short));
    host.crystal = (int *)malloc((size_t)TRACK_SAMPLES * sizeof(int));
    host.corner = (int *)malloc((size_t)TRACK_FLOOR_VALUES * sizeof(int));
    host.floors = (unsigned short *)malloc((size_t)(TRACK_FRAMES_MOST * TRACK_FLOOR_VALUES) * sizeof(unsigned short));
    host.work = (long long *)malloc((size_t)TRACK_SAMPLES * sizeof(long long));
    host.before = (long long *)malloc((size_t)TRACK_SAMPLES * sizeof(long long));
    host.floor_host = (long long *)malloc((size_t)TRACK_FLOOR_VALUES * sizeof(long long));
    host.planes = (unsigned int *)malloc((size_t)(TRACK_FRAMES_MOST * TRACK_BITS * TRACK_WORDS) * sizeof(unsigned int));
    host.queries = (TrackQuery *)malloc((size_t)TRACK_QUERIES_MOST * sizeof(TrackQuery));
    host.truths = (TrackTruth *)malloc((size_t)TRACK_QUERIES_MOST * sizeof(TrackTruth));
    host.candidates = (unsigned int *)malloc((size_t)(TRACK_QUERIES_MOST * TRACK_WORDS) * sizeof(unsigned int));
    host.reads = (unsigned int *)malloc((size_t)(TRACK_QUERIES_MOST * TRACK_WORDS) * sizeof(unsigned int));
    host.expected = (unsigned int *)malloc((size_t)TRACK_WORDS * sizeof(unsigned int));
    int good = (host.lanes != NULL) && (host.crystal != NULL) && (host.corner != NULL) && (host.floors != NULL)
            && (host.work != NULL) && (host.before != NULL) && (host.floor_host != NULL) && (host.planes != NULL)
            && (host.queries != NULL) && (host.truths != NULL) && (host.candidates != NULL) && (host.reads != NULL)
            && (host.expected != NULL);
    sim_check(&tally, good, "the host buffers are held");
    good = good && sim_job_submit(&tally, "floor_track", count, arguments, TRACK_DECLARED);
    TrackDevice device;
    memset(&device, 0, sizeof(device));
    good = good
        && sim_took(&tally, cudaMalloc((void **)&device.lanes,
                                       (size_t)(TRACK_FRAMES_MOST * TRACK_SAMPLES) * sizeof(unsigned short)),
                    "device frames")
        && sim_took(&tally, cudaMalloc((void **)&device.floors,
                                       (size_t)(TRACK_FRAMES_MOST * TRACK_FLOOR_VALUES) * sizeof(unsigned short)),
                    "device floors")
        && sim_took(&tally, cudaMalloc((void **)&device.planes,
                                       (size_t)(TRACK_FRAMES_MOST * TRACK_BITS * TRACK_WORDS) * sizeof(unsigned int)),
                    "device planes")
        && sim_took(&tally, cudaMalloc((void **)&device.queries, (size_t)TRACK_QUERIES_MOST * sizeof(TrackQuery)),
                    "device queries")
        && sim_took(&tally, cudaMalloc((void **)&device.candidates,
                                       (size_t)(TRACK_QUERIES_MOST * TRACK_WORDS) * sizeof(unsigned int)),
                    "device candidates")
        && sim_took(&tally, cudaMalloc((void **)&device.reads,
                                       (size_t)(TRACK_QUERIES_MOST * TRACK_WORDS) * sizeof(unsigned int)),
                    "device reads");

    // the control: every body a floor-2 cell a frame, no noise, no ramp, no pattern, so floor 2 translates exactly
    SimBody control_body[TRACK_CONTROL_BODIES];
    SimScene control;
    memset(&control, 0, sizeof(control));
    control.frames = TRACK_CONTROL_FRAMES;
    control.extent[0] = TRACK_SIDE;
    control.extent[1] = TRACK_SIDE;
    control.extent[2] = TRACK_SIDE;
    control.background = 200ull;
    control.bodies = TRACK_CONTROL_BODIES;
    track_control_bodies(control_body, TRACK_CONTROL_FRAMES);
    control.body = control_body;
    SimCamera still;
    memset(&still, 0, sizeof(still));
    still.key = TRACK_KEY;
    still.offset = 100ull;
    still.gain = 1ull;
    TrackSetting control_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(control_settings, 0, sizeof(control_settings));
    good = good && track_scene(&tally, "control, a cell a frame, no noise", &control, &still, 1ull, &host, &device,
                               control_settings, 1u);
    sim_check(&tally, good && (control_settings[0][0].hits == control_settings[0][0].queries)
                          && (control_settings[1][0].hits == control_settings[1][0].queries),
              "the control finds every body at its true next cell at d = 0, by its own cell and by its 27");

    // the camera law: bodies a voxel a frame, shot and read noise, the ramp and the fixed pattern
    SimBody camera_body[TRACK_CAMERA_BODIES];
    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = TRACK_CAMERA_FRAMES;
    scene.extent[0] = TRACK_SIDE;
    scene.extent[1] = TRACK_SIDE;
    scene.extent[2] = TRACK_SIDE;
    scene.background = 200ull;
    scene.ramp = 1ull;
    scene.bodies = TRACK_CAMERA_BODIES;
    SimDraws draws;
    draws.key = TRACK_KEY ^ TRACK_FOUNDER_PURPOSE;
    draws.counter = 0ull;
    sim_founders_draw(&draws, &scene, camera_body, TRACK_CAMERA_BODIES);
    scene.body = camera_body;
    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.key = TRACK_KEY;
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_reach = 8ull;
    camera.shot = 1ull;
    TrackSetting camera_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(camera_settings, 0, sizeof(camera_settings));
    good = good && track_scene(&tally, "camera law, a voxel a frame", &scene, &camera, 1ull, &host, &device,
                               camera_settings, TRACK_DELTAS);
    // the floor's own time step: over 2^2 frames a body moving a whole voxel a frame moves whole floor-2 cells
    TrackSetting floor_step_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(floor_step_settings, 0, sizeof(floor_step_settings));
    good = good && track_scene(&tally, "camera law, a voxel a frame", &scene, &camera, (unsigned long long)TRACK_CELL,
                               &host, &device, floor_step_settings, TRACK_DELTAS);
    // the same bodies with no noise, no ramp and no pattern: what the floor's time step leaves once the noise is gone
    SimScene quiet = scene;
    quiet.ramp = 0ull;
    TrackSetting quiet_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(quiet_settings, 0, sizeof(quiet_settings));
    good = good && track_scene(&tally, "the camera law's bodies, no noise", &quiet, &still,
                               (unsigned long long)TRACK_CELL, &host, &device, quiet_settings, TRACK_DELTAS);

    // the first three of those bodies spread along z, so no body reaches another's footprint, with the camera's noise
    // and without it
    SimBody sparse_body[TRACK_SPARSE_BODIES];
    memcpy(sparse_body, camera_body, sizeof(sparse_body));
    for (unsigned int index = 0u; index < TRACK_SPARSE_BODIES; index += 1u)
    {
        sparse_body[index].centre[0] = TRACK_SPARSE_FIRST_Z + ((long long)index * TRACK_SPARSE_Z_STEP);
    }
    SimScene sparse = scene;
    sparse.bodies = TRACK_SPARSE_BODIES;
    sparse.body = sparse_body;
    TrackSetting sparse_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(sparse_settings, 0, sizeof(sparse_settings));
    good = good && track_scene(&tally, "three bodies apart, camera law", &sparse, &camera,
                               (unsigned long long)TRACK_CELL, &host, &device, sparse_settings, TRACK_DELTAS);
    SimScene sparse_quiet = sparse;
    sparse_quiet.ramp = 0ull;
    TrackSetting sparse_quiet_settings[TRACK_PATCHES][TRACK_DELTAS];
    memset(sparse_quiet_settings, 0, sizeof(sparse_quiet_settings));
    good = good && track_scene(&tally, "three bodies apart, no noise", &sparse_quiet, &still,
                               (unsigned long long)TRACK_CELL, &host, &device, sparse_quiet_settings, TRACK_DELTAS);
    scriptura_text(&tally.line, "  clear steps among the three, no noise: ");
    scriptura_decimal(&tally.line, sparse_quiet_settings[1][0].clear, 1u);
    scriptura_text(&tally.line, " of ");
    scriptura_decimal(&tally.line, sparse_quiet_settings[1][0].queries, 1u);
    scriptura_text(&tally.line, "\n");
    sim_check(&tally, good && (sparse_quiet_settings[1][0].clear != 0ull)
                          && (sparse_quiet_settings[0][0].clear_hits == sparse_quiet_settings[0][0].clear)
                          && (sparse_quiet_settings[1][0].clear_hits == sparse_quiet_settings[1][0].clear),
              "at floor 2's time step every clear step is found at d = 0, by its own cell and by its 27");
    unsigned long long most = 0ull;
    for (unsigned int patch = 0u; patch < TRACK_PATCHES; patch += 1u)
    {
        for (unsigned int delta = 0u; delta < TRACK_DELTAS; delta += 1u)
        {
            most = (camera_settings[patch][delta].reads_most > most) ? camera_settings[patch][delta].reads_most : most;
            most = (floor_step_settings[patch][delta].reads_most > most) ? floor_step_settings[patch][delta].reads_most
                                                                         : most;
            most = (quiet_settings[patch][delta].reads_most > most) ? quiet_settings[patch][delta].reads_most : most;
            most = (sparse_settings[patch][delta].reads_most > most) ? sparse_settings[patch][delta].reads_most : most;
            const unsigned long long quiet_most = sparse_quiet_settings[patch][delta].reads_most;
            most = (quiet_most > most) ? quiet_most : most;
        }
    }
    most = (control_settings[1][0].reads_most > most) ? control_settings[1][0].reads_most : most;
    scriptura_text(&tally.line, "  the most plane words any query read: ");
    scriptura_decimal(&tally.line, most, 1u);
    scriptura_text(&tally.line, ", ");
    scriptura_decimal(&tally.line, 4ull * most, 1u);
    scriptura_text(&tally.line, " bytes, against half of a frame, ");
    scriptura_decimal(&tally.line, TRACK_SAMPLES, 1u);
    scriptura_text(&tally.line, " bytes\n");
    // a plane word is 4 bytes and a sample 2, so half of a frame's samples is TRACK_SAMPLES bytes
    sim_check(&tally, good && ((4ull * most) < TRACK_SAMPLES),
              "no query reads as many bytes of planes as half of a frame holds");

    cudaFree(device.reads);
    cudaFree(device.candidates);
    cudaFree(device.queries);
    cudaFree(device.planes);
    cudaFree(device.floors);
    cudaFree(device.lanes);
    free(host.expected);
    free(host.reads);
    free(host.candidates);
    free(host.truths);
    free(host.queries);
    free(host.planes);
    free(host.floor_host);
    free(host.before);
    free(host.work);
    free(host.floors);
    free(host.corner);
    free(host.crystal);
    free(host.lanes);
    return sim_close(&tally, "floor track");
}
