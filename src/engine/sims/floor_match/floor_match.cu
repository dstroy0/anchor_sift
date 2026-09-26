// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Finding x in a for less than half of a (Doug, 25 September: "say we want to find x and x is on floor 2, we have
// the knf, we only need to &&"). a is one camera-law frame of n samples. The engine's tower lifts it, and floor 2 is
// the approximation after two levels: the 16^3 corner, m = n / 64 values, read from the engine by lowering that
// corner as its own tower and held to the host's own two-level lifting. Floor 2's values are laid once as 16 bit
// planes. A query x then reads no value at all: the positions holding x are the and, over the planes, of each plane
// where x's bit is 1 and its complement where it is 0, 32 positions a word, and a word stops being read once its mask
// is empty. Every match set is held to the host's scan of floor 2, for values on floor 2 and values not on it, and
// every query's reads are counted against n / 2. The index is built once: the lift reads a's n samples and the planes
// floor 2's m values, and every query after reads only plane words.
#include "sim_camera.h"

#include "tower.h"

#define MATCH_KEY 0x464C4F4F52ull

#define MATCH_FOUNDER_PURPOSE 0x464F554Eull

#define MATCH_PRESENT_PURPOSE 0x50524553ull

#define MATCH_ABSENT_PURPOSE 0x41425345ull

#define MATCH_SIDE 64ull

#define MATCH_FLOOR 2u

// floor 2's side: two halvings of every axis
#define MATCH_FLOOR_SIDE (MATCH_SIDE >> MATCH_FLOOR)

#define MATCH_SAMPLES (MATCH_SIDE * MATCH_SIDE * MATCH_SIDE)

#define MATCH_FLOOR_VALUES (MATCH_FLOOR_SIDE * MATCH_FLOOR_SIDE * MATCH_FLOOR_SIDE)

// a floor-2 value's width: the engine's lowering holds every value inside the 16-bit lane
#define MATCH_BITS 16u

#define MATCH_WORD_BITS 32ull

#define MATCH_WORDS (MATCH_FLOOR_VALUES / MATCH_WORD_BITS)

#define MATCH_VALUES_MOST 65536ull

#define MATCH_FOUNDERS 6u

// queries of each kind: values on floor 2, drawn at keyed positions, and values not on it
#define MATCH_QUERIES_EACH 1024u

#define MATCH_QUERIES (2u * MATCH_QUERIES_EACH)

#define MATCH_THREADS 256ull

static_assert((MATCH_FLOOR_VALUES % MATCH_WORD_BITS) == 0ull, "floor 2 fills whole plane words, one warp a word");

static_assert((MATCH_FLOOR_VALUES % MATCH_THREADS) == 0ull, "the plane kernel's blocks are whole warps");

// what the sim puts on the device at once: the frame, the tower's two held coefficient arrays, floor 2, the planes,
// the queries, and each query's match word and reads for every plane word
#define MATCH_DECLARED \
    ((MATCH_SAMPLES * sizeof(unsigned short)) + (2ull * MATCH_SAMPLES * sizeof(int)) \
     + (MATCH_FLOOR_VALUES * sizeof(unsigned short)) + (MATCH_BITS * MATCH_WORDS * sizeof(unsigned int)) \
     + (MATCH_QUERIES * sizeof(unsigned int)) \
     + ((unsigned long long)MATCH_QUERIES * MATCH_WORDS * (sizeof(unsigned int) + sizeof(unsigned char))))

// the tower's own floor shift, toward minus infinity, as tower.cu takes it
static long long match_floor_shift(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -(((-value) + (1ll << shift) - 1ll) >> shift);
}

// the high d_j of one line, as tower.cu's forward kernel reads it: the edge repeats its left neighbour
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
static void match_floor_host(const unsigned short *lanes, long long *work, long long *before, long long *floor_values)
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
                floor_values[(((z * MATCH_FLOOR_SIDE) + y) * MATCH_FLOOR_SIDE) + x]
                    = work[(z * stride[0]) + (y * stride[1]) + x];
            }
        }
    }
}

// the engine's floor 2: the tower lifts the whole frame, and the levels past floor 2 lift only its corner, so the
// corner of the crystal lowered as a tower of its own side is floor 2. The lowering holds every value in the lane.
static int match_floor_engine(SimTally *tally, const unsigned short *device_lanes, int *crystal, int *corner,
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
    int good = (tower_lift(&lift) == 0L) && (error.kind == ENGINE_ERROR_NONE);
    sim_check(tally, good, "the engine's tower lifts the frame");
    good = good && sim_took(tally, cudaMemcpy(crystal, coefficients, (size_t)MATCH_SAMPLES * sizeof(int),
                                              cudaMemcpyDeviceToHost), "crystal read");
    for (unsigned long long z = 0ull; good && (z < MATCH_FLOOR_SIDE); z += 1ull)
    {
        for (unsigned long long y = 0ull; y < MATCH_FLOOR_SIDE; y += 1ull)
        {
            for (unsigned long long x = 0ull; x < MATCH_FLOOR_SIDE; x += 1ull)
            {
                corner[(((z * MATCH_FLOOR_SIDE) + y) * MATCH_FLOOR_SIDE) + x]
                    = crystal[(((z * MATCH_SIDE) + y) * MATCH_SIDE) + x];
            }
        }
    }
    const unsigned long long floor_extent[4] = {1ull, MATCH_FLOOR_SIDE, MATCH_FLOOR_SIDE, MATCH_FLOOR_SIDE};
    int *room = NULL;
    good = good && (tower_room(floor_extent, &room, &error) == 0L)
        && sim_took(tally, cudaMemcpy(room, corner, (size_t)MATCH_FLOOR_VALUES * sizeof(int), cudaMemcpyHostToDevice),
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
    good = good && (tower_lower(&lower) == 0L) && (error.kind == ENGINE_ERROR_NONE);
    sim_check(tally, good, "the crystal's 16^3 corner lowers as its own tower, every value inside the 16-bit lane");
    return good;
}

// the planes: bit j of floor 2's value at position i is bit i % 32 of plane j's word i / 32, one warp a word
static __global__ void match_planes_kernel(const unsigned short *floor_values, unsigned int *planes)
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
static __global__ void match_query_kernel(const unsigned int *planes, const unsigned int *queries, unsigned int *matches,
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

typedef struct
{
    unsigned long long total;
    unsigned long long most;
    unsigned long long found;
    unsigned long long found_most;
    unsigned long long held;
} MatchSide;

static void match_print_side(ScripturaLine *line, const char *name, const MatchSide *side)
{
    scriptura_text(line, "    ");
    scriptura_text(line, name);
    scriptura_text(line, ": ");
    scriptura_decimal(line, side->held, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, MATCH_QUERIES_EACH, 1u);
    scriptura_text(line, " match sets equal the host's scan; positions found a query ");
    sim_fraction_print(line, side->found, MATCH_QUERIES_EACH, 2u);
    scriptura_text(line, " on average, ");
    scriptura_decimal(line, side->found_most, 1u);
    scriptura_text(line, " at most; plane words read a query ");
    sim_fraction_print(line, side->total, MATCH_QUERIES_EACH, 2u);
    scriptura_text(line, " on average, ");
    scriptura_decimal(line, side->most, 1u);
    scriptura_text(line, " at most\n");
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    unsigned short *const lanes = (unsigned short *)malloc((size_t)MATCH_SAMPLES * sizeof(unsigned short));
    int *const crystal = (int *)malloc((size_t)MATCH_SAMPLES * sizeof(int));
    int *const corner = (int *)malloc((size_t)MATCH_FLOOR_VALUES * sizeof(int));
    unsigned short *const floor_values = (unsigned short *)malloc((size_t)MATCH_FLOOR_VALUES * sizeof(unsigned short));
    long long *const work = (long long *)malloc((size_t)MATCH_SAMPLES * sizeof(long long));
    long long *const before = (long long *)malloc((size_t)MATCH_SAMPLES * sizeof(long long));
    long long *const floor_host = (long long *)malloc((size_t)MATCH_FLOOR_VALUES * sizeof(long long));
    unsigned int *const planes = (unsigned int *)malloc((size_t)(MATCH_BITS * MATCH_WORDS) * sizeof(unsigned int));
    unsigned int *const queries = (unsigned int *)malloc((size_t)MATCH_QUERIES * sizeof(unsigned int));
    unsigned int *const matches = (unsigned int *)malloc((size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned int));
    unsigned char *const reads = (unsigned char *)malloc((size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned char));
    unsigned char *const present = (unsigned char *)calloc((size_t)MATCH_VALUES_MOST, sizeof(unsigned char));
    unsigned int *const expected = (unsigned int *)malloc((size_t)MATCH_WORDS * sizeof(unsigned int));
    int good = (lanes != NULL) && (crystal != NULL) && (corner != NULL) && (floor_values != NULL) && (work != NULL)
            && (before != NULL) && (floor_host != NULL) && (planes != NULL) && (queries != NULL) && (matches != NULL)
            && (reads != NULL) && (present != NULL) && (expected != NULL);
    sim_check(&tally, good, "the host buffers are held");
    good = good && sim_job_submit(&tally, "floor_match", count, arguments, MATCH_DECLARED);

    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = 1ull;
    scene.extent[0] = MATCH_SIDE;
    scene.extent[1] = MATCH_SIDE;
    scene.extent[2] = MATCH_SIDE;
    scene.background = 200ull;
    scene.ramp = 1ull;
    scene.bodies = MATCH_FOUNDERS;
    SimBody body[MATCH_FOUNDERS];
    SimCamera camera;
    memset(&camera, 0, sizeof(camera));
    camera.key = MATCH_KEY;
    camera.offset = 100ull;
    camera.gain = 1ull;
    camera.read_square = 3ull;
    camera.pattern_reach = 8ull;
    camera.shot = 1ull;
    SimDraws draws;
    draws.key = MATCH_KEY ^ MATCH_FOUNDER_PURPOSE;
    draws.counter = 0ull;
    sim_founders_draw(&draws, &scene, body, MATCH_FOUNDERS);
    scene.body = body;

    unsigned short *device_lanes = NULL;
    unsigned short *device_floor = NULL;
    unsigned int *device_planes = NULL;
    unsigned int *device_queries = NULL;
    unsigned int *device_matches = NULL;
    unsigned char *device_reads = NULL;
    good = good && sim_took(&tally, cudaMalloc((void **)&device_lanes, (size_t)MATCH_SAMPLES * sizeof(unsigned short)),
                            "device frame");
    unsigned long long clipped = 0ull;
    good = good && sim_render(&tally, &scene, &camera, device_lanes, NULL, NULL, &clipped);
    sim_check(&tally, good && (clipped == 0ull), "the frame renders with nothing clipped");
    good = good && (clipped == 0ull)
        && sim_took(&tally, cudaMemcpy(lanes, device_lanes, (size_t)MATCH_SAMPLES * sizeof(unsigned short),
                                       cudaMemcpyDeviceToHost), "frame read");

    // floor 2 from the engine, held to the host's own lifting at every coefficient
    good = good && match_floor_engine(&tally, device_lanes, crystal, corner, floor_values);
    unsigned long long equal = 0ull;
    if (good)
    {
        match_floor_host(lanes, work, before, floor_host);
        for (unsigned long long at = 0ull; at < MATCH_FLOOR_VALUES; at += 1ull)
        {
            equal += (floor_host[at] == (long long)floor_values[at]) ? 1ull : 0ull;
        }
    }
    sim_check(&tally, good && (equal == MATCH_FLOOR_VALUES),
              "the engine's floor 2 equals the host's two-level lifting of the frame at every coefficient");

    // the planes, laid once on the device from floor 2's values
    good = good && sim_took(&tally, cudaMalloc((void **)&device_floor, (size_t)MATCH_FLOOR_VALUES * sizeof(unsigned short)),
                            "device floor")
        && sim_took(&tally, cudaMalloc((void **)&device_planes, (size_t)(MATCH_BITS * MATCH_WORDS) * sizeof(unsigned int)),
                    "device planes")
        && sim_took(&tally, cudaMemcpy(device_floor, floor_values, (size_t)MATCH_FLOOR_VALUES * sizeof(unsigned short),
                                       cudaMemcpyHostToDevice), "floor write");
    if (good)
    {
        // floor 2's values fill whole blocks, far fewer than 2^31
        match_planes_kernel<<<(unsigned int)(MATCH_FLOOR_VALUES / MATCH_THREADS), (unsigned int)MATCH_THREADS>>>(
            device_floor, device_planes);
        good = sim_took(&tally, cudaGetLastError(), "planes launch") && sim_took(&tally, cudaDeviceSynchronize(), "planes run")
            && sim_took(&tally, cudaMemcpy(planes, device_planes, (size_t)(MATCH_BITS * MATCH_WORDS) * sizeof(unsigned int),
                                           cudaMemcpyDeviceToHost), "planes read");
    }
    unsigned long long bits_held = 0ull;
    for (unsigned long long at = 0ull; good && (at < MATCH_FLOOR_VALUES); at += 1ull)
    {
        present[floor_values[at]] = 1u;
        for (unsigned int bit = 0u; bit < MATCH_BITS; bit += 1u)
        {
            const unsigned int laid = (planes[((unsigned long long)bit * MATCH_WORDS) + (at / MATCH_WORD_BITS)]
                                       >> (at % MATCH_WORD_BITS)) & 1u;
            bits_held += (laid == ((floor_values[at] >> bit) & 1u)) ? 1ull : 0ull;
        }
    }
    sim_check(&tally, good && (bits_held == (MATCH_FLOOR_VALUES * MATCH_BITS)),
              "the 16 planes hold every bit of every floor-2 value");

    // the queries: values drawn at keyed positions of floor 2, then values drawn over the lane that floor 2 lacks
    unsigned long long distinct = 0ull;
    for (unsigned long long value = 0ull; value < MATCH_VALUES_MOST; value += 1ull)
    {
        distinct += present[value];
    }
    for (unsigned int query = 0u; good && (query < MATCH_QUERIES_EACH); query += 1u)
    {
        // the drawn position is below floor 2's count
        queries[query] = floor_values[sim_draw_below(MATCH_KEY ^ MATCH_PRESENT_PURPOSE, query, MATCH_FLOOR_VALUES)];
    }
    unsigned long long absent_counter = 0ull;
    for (unsigned int query = 0u; good && (query < MATCH_QUERIES_EACH); query += 1u)
    {
        unsigned int value = 0u;
        do
        {
            // the draw is below the lane's 2^16 values
            value = (unsigned int)sim_draw_below(MATCH_KEY ^ MATCH_ABSENT_PURPOSE, absent_counter, MATCH_VALUES_MOST);
            absent_counter += 1ull;
        } while (present[value] != 0u);
        queries[MATCH_QUERIES_EACH + query] = value;
    }
    good = good && sim_took(&tally, cudaMalloc((void **)&device_queries, (size_t)MATCH_QUERIES * sizeof(unsigned int)),
                            "device queries")
        && sim_took(&tally, cudaMalloc((void **)&device_matches, (size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned int)),
                    "device matches")
        && sim_took(&tally, cudaMalloc((void **)&device_reads, (size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned char)),
                    "device reads")
        && sim_took(&tally, cudaMemcpy(device_queries, queries, (size_t)MATCH_QUERIES * sizeof(unsigned int),
                                       cudaMemcpyHostToDevice), "queries write");
    if (good)
    {
        const unsigned long long threads = (unsigned long long)MATCH_QUERIES * MATCH_WORDS;
        // the grid is far below 2^31 blocks
        match_query_kernel<<<(unsigned int)sim_launch_blocks(threads, MATCH_THREADS), (unsigned int)MATCH_THREADS>>>(
            device_planes, device_queries, device_matches, device_reads);
        good = sim_took(&tally, cudaGetLastError(), "query launch") && sim_took(&tally, cudaDeviceSynchronize(), "query run")
            && sim_took(&tally, cudaMemcpy(matches, device_matches,
                                           (size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned int),
                                           cudaMemcpyDeviceToHost), "matches read")
            && sim_took(&tally, cudaMemcpy(reads, device_reads, (size_t)MATCH_QUERIES * MATCH_WORDS * sizeof(unsigned char),
                                           cudaMemcpyDeviceToHost), "reads read");
    }

    // each query's match set against the host's scan of floor 2, and its reads
    MatchSide sides[2];
    memset(sides, 0, sizeof(sides));
    unsigned long long first_query_cell = MATCH_FLOOR_VALUES;
    for (unsigned int query = 0u; good && (query < MATCH_QUERIES); query += 1u)
    {
        MatchSide *const side = &sides[query / MATCH_QUERIES_EACH];
        memset(expected, 0, (size_t)MATCH_WORDS * sizeof(unsigned int));
        for (unsigned long long at = 0ull; at < MATCH_FLOOR_VALUES; at += 1ull)
        {
            if ((unsigned int)floor_values[at] == queries[query])
            {
                expected[at / MATCH_WORD_BITS] |= 1u << (at % MATCH_WORD_BITS);
            }
        }
        int same = 1;
        unsigned long long found = 0ull;
        unsigned long long taken = 0ull;
        for (unsigned long long word = 0ull; word < MATCH_WORDS; word += 1ull)
        {
            const unsigned int got = matches[((unsigned long long)query * MATCH_WORDS) + word];
            same = same && (got == expected[word]);
            found += sim_bits_set((unsigned long long)got);
            taken += reads[((unsigned long long)query * MATCH_WORDS) + word];
            if ((query == 0u) && (got != 0u) && (first_query_cell == MATCH_FLOOR_VALUES))
            {
                // the lowest set bit of a nonzero word, counted up from bit 0
                unsigned int low = 0u;
                while (((got >> low) & 1u) == 0u)
                {
                    low += 1u;
                }
                first_query_cell = (word * MATCH_WORD_BITS) + low;
            }
        }
        side->held += (same != 0) ? 1ull : 0ull;
        side->found += found;
        side->found_most = (found > side->found_most) ? found : side->found_most;
        side->total += taken;
        side->most = (taken > side->most) ? taken : side->most;
    }

    const unsigned long long half = MATCH_SAMPLES / 2ull;
    const unsigned long long full = MATCH_BITS * MATCH_WORDS;
    ScripturaLine *const line = &tally.line;
    scriptura_text(line, "  a: one 64^3 camera frame, n = ");
    scriptura_decimal(line, MATCH_SAMPLES, 1u);
    scriptura_text(line, " samples; floor 2, its 16^3 corner after two levels, m = ");
    scriptura_decimal(line, MATCH_FLOOR_VALUES, 1u);
    scriptura_text(line, " = n / 64 values, ");
    scriptura_decimal(line, distinct, 1u);
    scriptura_text(line, " distinct; equal to the host's lifting at ");
    scriptura_decimal(line, equal, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, MATCH_FLOOR_VALUES, 1u);
    scriptura_text(line, "\n  the index, built once: the lift read a's n samples and the planes floor 2's m values; ");
    scriptura_decimal(line, MATCH_BITS, 1u);
    scriptura_text(line, " planes of ");
    scriptura_decimal(line, MATCH_WORDS, 1u);
    scriptura_text(line, " words\n  a query reads no value: the and over the planes takes at most ");
    scriptura_decimal(line, full, 1u);
    scriptura_text(line, " plane words, and half of a is ");
    scriptura_decimal(line, half, 1u);
    scriptura_text(line, " samples\n");
    match_print_side(line, "on floor 2", &sides[0]);
    match_print_side(line, "not on floor 2", &sides[1]);
    if (first_query_cell < MATCH_FLOOR_VALUES)
    {
        const unsigned long long z = first_query_cell / (MATCH_FLOOR_SIDE * MATCH_FLOOR_SIDE);
        const unsigned long long y = (first_query_cell / MATCH_FLOOR_SIDE) % MATCH_FLOOR_SIDE;
        const unsigned long long x = first_query_cell % MATCH_FLOOR_SIDE;
        scriptura_text(line, "    the first query, x = ");
        scriptura_decimal(line, queries[0], 1u);
        scriptura_text(line, ": its first cell on floor 2 is (");
        scriptura_decimal(line, z, 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, y, 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, x, 1u);
        scriptura_text(line, "), centred on a's (");
        scriptura_decimal(line, 4ull * z, 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, 4ull * y, 1u);
        scriptura_text(line, ", ");
        scriptura_decimal(line, 4ull * x, 1u);
        scriptura_text(line, ")\n");
    }
    sim_check(&tally, good && (sides[0].held == MATCH_QUERIES_EACH),
              "every value on floor 2 is found at exactly the positions the host's scan finds");
    sim_check(&tally, good && (sides[1].held == MATCH_QUERIES_EACH) && (sides[1].found == 0ull),
              "every value not on floor 2 is found nowhere");
    sim_check(&tally, good && (sides[0].most <= full) && (sides[1].most <= full) && (full < half),
              "no query reads more than 16 m / 32 plane words, below half of a");

    cudaFree(device_reads);
    cudaFree(device_matches);
    cudaFree(device_queries);
    cudaFree(device_planes);
    cudaFree(device_floor);
    cudaFree(device_lanes);
    free(expected);
    free(present);
    free(reads);
    free(matches);
    free(queries);
    free(planes);
    free(floor_host);
    free(before);
    free(work);
    free(floor_values);
    free(corner);
    free(crystal);
    free(lanes);
    return sim_close(&tally, "floor match");
}
