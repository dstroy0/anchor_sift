// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Proves the reversible lookup edges sandwiched between tower floors: a lift that lays permutation
// edges between its floors and a lower that replays their inverses in reverse rebuilds the lanes
// exactly, the edges actually change the crystal, and a table that is not a permutation is refused.

#include "tower.h"

#include <cuda_runtime.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>

#define EDGE_BITS 8u
#define EDGE_SIZE 256u

// A Bennett edge splits its low bits into an x field (the argument) and a y field above it (the carrier).
#define BENNETT_X_BITS 8u
#define BENNETT_Y_BITS 8u
#define BENNETT_BITS (BENNETT_X_BITS + BENNETT_Y_BITS)
#define BENNETT_SIZE (1u << BENNETT_BITS)
#define BENNETT_FIELD 0xFFu
#define BENNETT_TRIALS 64u

// 1 x 8 x 8 x 8 halves three times to a single coefficient, the collapsed floor
#define TOWER_TEST_COLLAPSED 3u

static int s_checks = 0;
static int s_failed = 0;

static void check(const char *name, int ok)
{
    s_checks += 1;
    if (ok == 0)
    {
        s_failed += 1;
        printf("  FAIL %s\n", name);
    }
    else
    {
        printf("  ok   %s\n", name);
    }
}

// an affine map on the byte alphabet is a permutation when the multiplier is odd (coprime to 256)
static void tower_test_affine(unsigned int *table, unsigned int multiplier, unsigned int addend)
{
    for (unsigned int index = 0u; index < EDGE_SIZE; index += 1u)
    {
        table[index] = ((multiplier * index) + addend) & 0xFFu;
    }
}

static void tower_test_lanes(unsigned short *lanes, unsigned long long count, unsigned long long seed)
{
    unsigned long long state = seed;
    for (unsigned long long index = 0ull; index < count; index += 1ull)
    {
        state = (state * 6364136223846793005ull) + 1442695040888963407ull;
        lanes[index] = (unsigned short)((state >> 33) & 0xFFFFu);
    }
}

// |x| of the 8-bit two's complement field; |-128| is 128, which the 8-bit carrier still holds
static unsigned int tower_test_absolute(unsigned int x)
{
    return (x < 128u) ? x : (256u - x);
}

static unsigned int tower_test_compare(unsigned int x)
{
    return (x >= 100u) ? 1u : 0u;
}

// The Bennett embedding of f: (x, y) -> (x, y xor f(x)). It is a permutation of the pair for any f, lossy or
// not, since y comes back as the carrier xor f(x); the price is the carrier's width.
static void tower_test_bennett(unsigned int *table, unsigned int (*function)(unsigned int))
{
    for (unsigned int carrier = 0u; carrier <= BENNETT_FIELD; carrier += 1u)
    {
        for (unsigned int argument = 0u; argument <= BENNETT_FIELD; argument += 1u)
        {
            const unsigned int image = carrier ^ (function(argument) & BENNETT_FIELD);
            table[(carrier << BENNETT_X_BITS) | argument] = (image << BENNETT_X_BITS) | argument;
        }
    }
}

// f(x) reads out of the edged word: x is kept, the carrier moved by exactly f(x), the high bits passed through
static int tower_test_readout(int plain, int edged, unsigned int (*function)(unsigned int))
{
    // a coefficient's two's complement bits, read as a word
    const unsigned int before = (unsigned int)plain;
    const unsigned int after = (unsigned int)edged;
    const unsigned int argument = before & BENNETT_FIELD;
    const int argument_kept = (after & BENNETT_FIELD) == argument;
    const int carrier_moved = (((after ^ before) >> BENNETT_X_BITS) & BENNETT_FIELD) == (function(argument) & BENNETT_FIELD);
    const int high_kept = (after >> BENNETT_BITS) == (before >> BENNETT_BITS);
    return argument_kept && carrier_moved && high_kept;
}

struct TowerRig
{
    unsigned short *device_lanes;
    unsigned short *host;
    unsigned long long extent[4];
    unsigned long long lanes;
};

// lift with the given edges, optionally copy the collapsed crystal, then lower with the same edges
static long tower_test_trip(const TowerRig *rig, const TowerEdge *edges, unsigned int edge_count,
                            unsigned long long *mismatches, int *rebuilt_ok, int *crystal)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    unsigned int floors = 0u;
    TowerLiftRequest lift;
    memset(&lift, 0, sizeof(lift));
    lift.device_lanes = rig->device_lanes;
    memcpy(lift.extent, rig->extent, sizeof(lift.extent));
    lift.coefficients = &coefficients;
    lift.scratch = &scratch;
    lift.floors = &floors;
    lift.edges = edges;
    lift.edge_count = edge_count;
    lift.error = &error;
    const long lifted = tower_lift(&lift);
    if (lifted != 0L)
    {
        return lifted;
    }
    if (crystal != NULL)
    {
        cudaMemcpy(crystal, coefficients, (size_t)rig->lanes * sizeof(int), cudaMemcpyDeviceToHost);
    }
    unsigned short *const rebuilt = (unsigned short *)malloc((size_t)rig->lanes * sizeof(unsigned short));
    const unsigned short *device_rebuilt = NULL;
    unsigned long long miss = 1ull;
    TowerLowerRequest lower;
    memset(&lower, 0, sizeof(lower));
    lower.device_lanes = rig->device_lanes;
    memcpy(lower.extent, rig->extent, sizeof(lower.extent));
    lower.mismatches = &miss;
    lower.device_rebuilt = &device_rebuilt;
    lower.rebuilt = rebuilt;
    lower.edges = edges;
    lower.edge_count = edge_count;
    lower.error = &error;
    const long lowered = tower_lower(&lower);
    if (lowered != 0L)
    {
        free(rebuilt);
        return lowered;
    }
    *mismatches = miss;
    int same = 1;
    for (unsigned long long index = 0ull; index < rig->lanes; index += 1ull)
    {
        if (rebuilt[index] != rig->host[index])
        {
            same = 0;
        }
    }
    *rebuilt_ok = same;
    free(rebuilt);
    return 0L;
}

int main(void)
{
    TowerRig rig;
    memset(&rig, 0, sizeof(rig));
    rig.extent[0] = 1ull;
    rig.extent[1] = 8ull;
    rig.extent[2] = 8ull;
    rig.extent[3] = 8ull;
    rig.lanes = rig.extent[0] * rig.extent[1] * rig.extent[2] * rig.extent[3];
    rig.host = (unsigned short *)malloc((size_t)rig.lanes * sizeof(unsigned short));
    tower_test_lanes(rig.host, rig.lanes, 0x0123456789ABCDEFull);
    if (cudaMalloc((void **)&rig.device_lanes, (size_t)rig.lanes * sizeof(unsigned short)) != cudaSuccess)
    {
        printf("  FAIL could not hold the device lanes\n");
        return 1;
    }
    cudaMemcpy(rig.device_lanes, rig.host, (size_t)rig.lanes * sizeof(unsigned short), cudaMemcpyHostToDevice);

    unsigned int affine_a[EDGE_SIZE];
    unsigned int affine_b[EDGE_SIZE];
    unsigned int affine_c[EDGE_SIZE];
    tower_test_affine(affine_a, 7u, 3u);
    tower_test_affine(affine_b, 11u, 5u);
    tower_test_affine(affine_c, 5u, 1u);

    unsigned long long mismatches = 1ull;
    int rebuilt_ok = 0;

    // the plain tower still round-trips with no edges at all
    long trip = tower_test_trip(&rig, NULL, 0u, &mismatches, &rebuilt_ok, NULL);
    check("baseline lift/lower returns", trip == 0L);
    check("baseline no mismatches", mismatches == 0ull);
    check("baseline rebuilt matches lanes", rebuilt_ok != 0);

    // one non-involution edge on the second floor round-trips only if lower replays its inverse
    TowerEdge one;
    one.floor = 1u;
    one.index_bits = EDGE_BITS;
    one.forward = affine_a;
    trip = tower_test_trip(&rig, &one, 1u, &mismatches, &rebuilt_ok, NULL);
    check("single edge lift/lower returns", trip == 0L);
    check("single edge no mismatches", mismatches == 0ull);
    check("single edge rebuilt matches lanes", rebuilt_ok != 0);

    // the edge must actually change the collapsed crystal, or it is doing nothing
    int *const plain = (int *)malloc((size_t)rig.lanes * sizeof(int));
    int *const edged = (int *)malloc((size_t)rig.lanes * sizeof(int));
    tower_test_trip(&rig, NULL, 0u, &mismatches, &rebuilt_ok, plain);
    tower_test_trip(&rig, &one, 1u, &mismatches, &rebuilt_ok, edged);
    int differ = 0;
    for (unsigned long long index = 0ull; index < rig.lanes; index += 1ull)
    {
        if (plain[index] != edged[index])
        {
            differ += 1;
        }
    }
    check("edge changes the crystal", differ > 0);
    free(plain);
    free(edged);

    // two edges stacked on one floor plus one on another: the reverse-order inverse must unwind the stack
    TowerEdge stack[3];
    stack[0].floor = 0u;
    stack[0].index_bits = EDGE_BITS;
    stack[0].forward = affine_c;
    stack[1].floor = 2u;
    stack[1].index_bits = EDGE_BITS;
    stack[1].forward = affine_a;
    stack[2].floor = 2u;
    stack[2].index_bits = EDGE_BITS;
    stack[2].forward = affine_b;
    trip = tower_test_trip(&rig, stack, 3u, &mismatches, &rebuilt_ok, NULL);
    check("stacked edges lift/lower returns", trip == 0L);
    check("stacked edges no mismatches", mismatches == 0ull);
    check("stacked edges rebuilt matches lanes", rebuilt_ok != 0);

    // edges on every floor, including the fully collapsed floor slot
    TowerEdge spread[4];
    for (unsigned int slot = 0u; slot < 4u; slot += 1u)
    {
        spread[slot].floor = slot;
        spread[slot].index_bits = EDGE_BITS;
        spread[slot].forward = (slot & 1u) ? affine_b : affine_a;
    }
    trip = tower_test_trip(&rig, spread, 4u, &mismatches, &rebuilt_ok, NULL);
    check("every floor lift/lower returns", trip == 0L);
    check("every floor no mismatches", mismatches == 0ull);
    check("every floor rebuilt matches lanes", rebuilt_ok != 0);

    // a table that repeats a value is not a permutation and is refused, changing no state
    unsigned int broken[EDGE_SIZE];
    tower_test_affine(broken, 7u, 0u);
    broken[1] = broken[0];
    TowerEdge bad;
    bad.floor = 1u;
    bad.index_bits = EDGE_BITS;
    bad.forward = broken;
    trip = tower_test_trip(&rig, &bad, 1u, &mismatches, &rebuilt_ok, NULL);
    check("non-permutation refused", trip != 0L);

    // index_bits out of range is refused on both ends
    TowerEdge zero_bits;
    zero_bits.floor = 1u;
    zero_bits.index_bits = 0u;
    zero_bits.forward = affine_a;
    trip = tower_test_trip(&rig, &zero_bits, 1u, &mismatches, &rebuilt_ok, NULL);
    check("zero index_bits refused", trip != 0L);

    TowerEdge wide_bits;
    wide_bits.floor = 1u;
    wide_bits.index_bits = TOWER_EDGE_INDEX_BITS_MOST + 1u;
    wide_bits.forward = affine_a;
    trip = tower_test_trip(&rig, &wide_bits, 1u, &mismatches, &rebuilt_ok, NULL);
    check("oversize index_bits refused", trip != 0L);

    // a floor slot past the collapsed floor is refused
    TowerEdge far;
    far.floor = 50u;
    far.index_bits = EDGE_BITS;
    far.forward = affine_a;
    trip = tower_test_trip(&rig, &far, 1u, &mismatches, &rebuilt_ok, NULL);
    check("out-of-range floor refused", trip != 0L);

    // after all the refusals, a clean edge still round-trips: the refusals left no state behind
    trip = tower_test_trip(&rig, &one, 1u, &mismatches, &rebuilt_ok, NULL);
    check("clean edge after refusals returns", trip == 0L);
    check("clean edge after refusals no mismatches", mismatches == 0ull);
    check("clean edge after refusals rebuilt matches lanes", rebuilt_ok != 0);

    // Bennett edges: a lossy function carried as a permutation of the widened pair (x, y) -> (x, y xor f(x))
    unsigned int *const absolute = (unsigned int *)malloc((size_t)BENNETT_SIZE * sizeof(unsigned int));
    unsigned int *const compare = (unsigned int *)malloc((size_t)BENNETT_SIZE * sizeof(unsigned int));
    unsigned int *const bare = (unsigned int *)malloc((size_t)BENNETT_SIZE * sizeof(unsigned int));
    int *const plain_crystal = (int *)malloc((size_t)rig.lanes * sizeof(int));
    int *const edged_crystal = (int *)malloc((size_t)rig.lanes * sizeof(int));
    tower_test_bennett(absolute, tower_test_absolute);
    tower_test_bennett(compare, tower_test_compare);
    unsigned int exact_trips = 0u;
    unsigned int readouts = 0u;
    unsigned int untouched = 0u;
    for (unsigned int trial = 0u; trial < BENNETT_TRIALS; trial += 1u)
    {
        tower_test_lanes(rig.host, rig.lanes, 0x0123456789ABCDEFull + (0x9E3779B97F4A7C15ull * (trial + 1u)));
        cudaMemcpy(rig.device_lanes, rig.host, (size_t)rig.lanes * sizeof(unsigned short), cudaMemcpyHostToDevice);
        unsigned int (*const function)(unsigned int) = ((trial & 1u) != 0u) ? tower_test_compare : tower_test_absolute;
        TowerEdge top;
        top.floor = TOWER_TEST_COLLAPSED;
        top.index_bits = BENNETT_BITS;
        top.forward = ((trial & 1u) != 0u) ? compare : absolute;
        const long plain_trip = tower_test_trip(&rig, NULL, 0u, &mismatches, &rebuilt_ok, plain_crystal);
        const long edged_trip = tower_test_trip(&rig, &top, 1u, &mismatches, &rebuilt_ok, edged_crystal);
        exact_trips += ((plain_trip == 0L) && (edged_trip == 0L) && (mismatches == 0ull) && (rebuilt_ok != 0)) ? 1u : 0u;
        readouts += tower_test_readout(plain_crystal[0], edged_crystal[0], function) ? 1u : 0u;
        // the collapsed floor is one coefficient, so every other coefficient is the plain crystal's
        untouched += (memcmp(&plain_crystal[1], &edged_crystal[1], (size_t)(rig.lanes - 1ull) * sizeof(int)) == 0) ? 1u : 0u;
    }
    check("bennett |x| and compare edges round-trip on every lattice", exact_trips == BENNETT_TRIALS);
    check("f(x) reads out of the carrier field on the collapsed floor", readouts == BENNETT_TRIALS);
    check("a collapsed-floor edge touches only its one coefficient", untouched == BENNETT_TRIALS);

    // the same two Bennett edges laid mid-tower, where lifting mixes their outputs, still round-trip
    TowerEdge inside[2];
    inside[0].floor = 1u;
    inside[0].index_bits = BENNETT_BITS;
    inside[0].forward = absolute;
    inside[1].floor = 2u;
    inside[1].index_bits = BENNETT_BITS;
    inside[1].forward = compare;
    trip = tower_test_trip(&rig, inside, 2u, &mismatches, &rebuilt_ok, NULL);
    check("bennett edges mid-tower round-trip", (trip == 0L) && (mismatches == 0ull) && (rebuilt_ok != 0));

    // |x| laid bare on the 16-bit field, not embedded: x and -x collide, so it is no permutation and is refused
    for (unsigned int index = 0u; index < BENNETT_SIZE; index += 1u)
    {
        bare[index] = (index < (BENNETT_SIZE / 2u)) ? index : (BENNETT_SIZE - index);
    }
    TowerEdge lossy;
    lossy.floor = 1u;
    lossy.index_bits = BENNETT_BITS;
    lossy.forward = bare;
    trip = tower_test_trip(&rig, &lossy, 1u, &mismatches, &rebuilt_ok, NULL);
    check("|x| laid bare, not embedded, is refused", trip != 0L);
    free(absolute);
    free(compare);
    free(bare);
    free(plain_crystal);
    free(edged_crystal);

    cudaFree(rig.device_lanes);
    free(rig.host);
    printf("  tower edge test %d checks %d failed\n", s_checks, s_failed);
    return (s_failed == 0) ? 0 : 1;
}
