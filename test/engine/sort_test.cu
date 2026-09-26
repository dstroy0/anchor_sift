// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The sort's S5 (cell_tracking/src/sort/sort_link). The gate on the device is held against a host brute force, pair by
// pair, flag by flag and cost by cost: frames of no points and of one, lattice ties, predictions outside the view, a
// pile of equal places whose ties pass 2 takes in batches, drawn small frames, and 6031 points against 6031 in a
// 64 x 256 x 256 view, under the weights 16, 1, 1 and 1, 1, 1. The host numbers the support components by a breadth
// first walk in gate order and finds them the device's; each gate pair's weight is K - cost, K one more than its
// component's summed costs, and at least 1. The chosen links are gate pairs, one to one, as many as the most any
// matching of the gate holds (augmenting paths on the host); on every component of at most 25 gate pairs an
// enumeration of every matching finds the chosen links' count and cost the most links, then the least cost. The
// crossing counts are recounted on the host. A synthetic chain written as .points and .drift runs through
// sort_link_set: its .links reads back with its header, the predictions p = x + d_t + (x - x_prev - d_{t-1}), their
// flags, and the chosen links following each body. A .drift of other weights refuses and leaves no .links, and so does
// a component whose K passes 32 bits. A span past 2^63 - 1 refuses, a K past 32 bits or past 64 is named, and
// malformed requests refuse. The gate's own refusal, ties past 2^30 pairs, is not forced: it would need frames past
// what a test holds, and the output says so. The test is one job on the device's tessera daemon, submitted before its
// first device work.
//
// The test links no engine.cu, so engine_sample_path below restates engine/engine.cu's, and sort_link.cu's paths are
// built by the restatement here: a change to either format must be made in both. The test prints one path it builds.
#include "sort.h"
#include "device_pool.h"
#include "scan.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#define SORT_TEST_MKDIR(path_) _mkdir(path_)
#else
#include <sys/stat.h>
#define SORT_TEST_MKDIR(path_) mkdir((path_), 0755)
#endif

#define SORT_TEST_POINTS_MOST 6031u

// a component of at most 25 gate pairs is enumerated whole; a drawn frame of at most 5 points against 5 has at most
// 25, so every drawn component is
#define SORT_TEST_ENUMERATED_MOST 25u

#define SORT_TEST_DRAWN_MOST 5ull

#define SORT_TEST_SMALL_DRAWS 400u

#define SORT_TEST_NONE 0xFFFFFFFFu

#define SORT_TEST_PILE_SOURCES 3u

#define SORT_TEST_PILE_TARGETS 50u

// the synthetic chain: 5 frames of 4 bodies in an 8 x 32 x 32 view
#define SORT_TEST_FRAMES 5u

#define SORT_TEST_BODIES 4u

#define SORT_TEST_DEPTH 8u

#define SORT_TEST_SIDE 32u

// .points opens with frames, depth, height, width, limbs and bits, then the readings and the cumulative count, 64 bits
// each
#define SORT_TEST_POINTS_HEAD_WORDS (6u + 2u + (2u * SCAN_READINGS))

// the test links no engine.cu: the engine's sample path, restated as engine/engine.cu's engine_sample_path writes it.
// A change to that format must be made here too
extern "C" int engine_sample_path(char *out, size_t room, const char *set, const char *sample, const char *suffix)
{
    const int written = snprintf(out, room, "%s/%s/%s%s", set, sample, sample, suffix);
    // a non-negative length is compared whole against the room
    return (written > 0) && ((size_t)written < room);
}

typedef struct
{
    unsigned int weights[ENGINE_AXES];
    unsigned int sources;
    unsigned int targets;
    int *source_places;
    int *predictions;
    int *target_places;
} SortTestPair;

typedef struct
{
    unsigned long long cases;
    unsigned long long agreed;
    unsigned long long gate;
    unsigned long long forward;
    unsigned long long backward;
    unsigned long long both;
    unsigned long long components;
    unsigned long long enumerated;
    unsigned long long chosen;
    unsigned long long kept;
    unsigned long long level;
    unsigned long long crossed;
} SortTestSums;

static int sort_test_pair_hold(SortTestPair *pair, unsigned int sources, unsigned int targets,
                               const unsigned int weights[ENGINE_AXES])
{
    memset(pair, 0, sizeof(*pair));
    memcpy(pair->weights, weights, sizeof(pair->weights));
    pair->sources = sources;
    pair->targets = targets;
    pair->source_places = (int *)malloc((ENGINE_AXES * (size_t)sources + 1u) * sizeof(int));
    pair->predictions = (int *)malloc((ENGINE_AXES * (size_t)sources + 1u) * sizeof(int));
    pair->target_places = (int *)malloc((ENGINE_AXES * (size_t)targets + 1u) * sizeof(int));
    return (pair->source_places != NULL) && (pair->predictions != NULL) && (pair->target_places != NULL);
}

static void sort_test_pair_release(SortTestPair *pair)
{
    free(pair->source_places);
    free(pair->predictions);
    free(pair->target_places);
    memset(pair, 0, sizeof(*pair));
}

// the weighted squared length, as the gate defines it
static unsigned long long sort_test_length(const int *one, const int *other, const unsigned int weights[ENGINE_AXES])
{
    unsigned long long length = 0ull;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        const long long difference = (long long)one[axis] - (long long)other[axis];
        // a difference of two 32-bit places is below 2^32 in size, so it re-signs to unsigned long long exactly
        const unsigned long long size = (unsigned long long)((difference < 0ll) ? -difference : difference);
        length += (unsigned long long)weights[axis] * size * size;
    }
    return length;
}

typedef struct
{
    const SortLinks *links;
    const unsigned int *members;
    unsigned int count;
    unsigned char *source_used;
    unsigned char *target_used;
    unsigned int best_links;
    unsigned long long best_cost;
} SortTestEnumeration;

// every matching of a component's gate pairs, each pair taken or passed over: the most links, then the least cost
static void sort_test_enumerate(SortTestEnumeration *enumeration, unsigned int at, unsigned int taken,
                                unsigned long long cost)
{
    if (at == enumeration->count)
    {
        const int better = (taken > enumeration->best_links)
                        || ((taken == enumeration->best_links) && (cost < enumeration->best_cost));
        enumeration->best_links = better ? taken : enumeration->best_links;
        enumeration->best_cost = better ? cost : enumeration->best_cost;
        return;
    }
    sort_test_enumerate(enumeration, at + 1u, taken, cost);
    const unsigned int pair = enumeration->members[at];
    const unsigned int source = enumeration->links->source[pair];
    const unsigned int target = enumeration->links->target[pair];
    if ((enumeration->source_used[source] == 0u) && (enumeration->target_used[target] == 0u))
    {
        enumeration->source_used[source] = 1u;
        enumeration->target_used[target] = 1u;
        sort_test_enumerate(enumeration, at + 1u, taken + 1u, cost + enumeration->links->cost[pair]);
        enumeration->source_used[source] = 0u;
        enumeration->target_used[target] = 0u;
    }
}

typedef struct
{
    const SortLinks *links;
    const unsigned int *start;
    unsigned int *matched;
    unsigned int *seen;
} SortTestAugment;

// an augmenting path from `source` over the gate's pairs, as Kuhn's algorithm walks it
static int sort_test_augment(SortTestAugment *augment, unsigned int source, unsigned int stamp)
{
    for (unsigned int pair = augment->start[source]; pair < augment->start[source + 1u]; pair += 1u)
    {
        const unsigned int target = augment->links->target[pair];
        if (augment->seen[target] == stamp)
        {
            continue;
        }
        augment->seen[target] = stamp;
        if ((augment->matched[target] == SORT_TEST_NONE)
            || (sort_test_augment(augment, augment->matched[target], stamp) != 0))
        {
            augment->matched[target] = source;
            return 1;
        }
    }
    return 0;
}

// the most links any matching of the gate holds, by augmenting paths; the gate is in source order
static unsigned int sort_test_most_links(const SortLinks *links, unsigned int sources, unsigned int targets)
{
    unsigned int *const start = (unsigned int *)calloc((size_t)sources + 2u, sizeof(unsigned int));
    unsigned int *const matched = (unsigned int *)malloc(((size_t)targets + 1u) * sizeof(unsigned int));
    unsigned int *const seen = (unsigned int *)malloc(((size_t)targets + 1u) * sizeof(unsigned int));
    unsigned int most = SORT_TEST_NONE;
    if ((start != NULL) && (matched != NULL) && (seen != NULL))
    {
        for (unsigned int pair = 0u; pair < links->pairs; pair += 1u)
        {
            start[links->source[pair] + 1u] += 1u;
        }
        for (unsigned int source = 0u; source < sources; source += 1u)
        {
            start[source + 1u] += start[source];
        }
        for (unsigned int target = 0u; target < targets; target += 1u)
        {
            matched[target] = SORT_TEST_NONE;
            seen[target] = SORT_TEST_NONE;
        }
        SortTestAugment augment = {links, start, matched, seen};
        most = 0u;
        for (unsigned int source = 0u; source < sources; source += 1u)
        {
            most += (unsigned int)sort_test_augment(&augment, source, source);
        }
    }
    free(start);
    free(matched);
    free(seen);
    return most;
}

// one pair through the sort, held against the host: the gate by brute force, the components by a breadth first walk,
// K and the weights, the chosen links, the most links, the enumerated matchings and the crossings
static int sort_test_prove(const SortTestPair *pair, SortLinks *links, SortTestSums *sums)
{
    const SortPairRequest request = {{pair->weights[0], pair->weights[1], pair->weights[2]}, pair->sources,
                                     pair->targets, pair->source_places, pair->predictions, pair->target_places};
    const long chosen = sort_link_pair(&request, links);
    const unsigned int sources = pair->sources;
    const unsigned int targets = pair->targets;
    unsigned long long *const forward = (unsigned long long *)malloc(((size_t)sources + 1u) * sizeof(unsigned long long));
    unsigned long long *const backward = (unsigned long long *)malloc(((size_t)targets + 1u)
                                                                      * sizeof(unsigned long long));
    int good = (chosen >= 0L) && (forward != NULL) && (backward != NULL);
    for (unsigned int source = 0u; good && (source < sources); source += 1u)
    {
        forward[source] = ~0ull;
    }
    for (unsigned int target = 0u; good && (target < targets); target += 1u)
    {
        backward[target] = ~0ull;
    }
    for (unsigned int source = 0u; good && (source < sources); source += 1u)
    {
        for (unsigned int target = 0u; target < targets; target += 1u)
        {
            const unsigned long long length = sort_test_length(&pair->predictions[ENGINE_AXES * (size_t)source],
                                                               &pair->target_places[ENGINE_AXES * (size_t)target],
                                                               pair->weights);
            forward[source] = (length < forward[source]) ? length : forward[source];
            backward[target] = (length < backward[target]) ? length : backward[target];
        }
    }
    unsigned int at = 0u;
    for (unsigned int source = 0u; good && (source < sources); source += 1u)
    {
        for (unsigned int target = 0u; good && (target < targets); target += 1u)
        {
            const unsigned long long length = sort_test_length(&pair->predictions[ENGINE_AXES * (size_t)source],
                                                               &pair->target_places[ENGINE_AXES * (size_t)target],
                                                               pair->weights);
            const unsigned int flags = ((length == forward[source]) ? SORT_GATE_FORWARD : 0u)
                                     | ((length == backward[target]) ? SORT_GATE_BACKWARD : 0u);
            if (flags == 0u)
            {
                continue;
            }
            good = (at < links->pairs) && (links->source[at] == source) && (links->target[at] == target)
                && (links->cost[at] == length)
                && ((links->flags[at] & (SORT_GATE_FORWARD | SORT_GATE_BACKWARD)) == flags)
                && ((links->flags[at] & ~(SORT_GATE_CHOSEN | SORT_GATE_FORWARD | SORT_GATE_BACKWARD)) == 0u);
            sums->forward += (flags == SORT_GATE_FORWARD) ? 1ull : 0ull;
            sums->backward += (flags == SORT_GATE_BACKWARD) ? 1ull : 0ull;
            sums->both += (flags == (SORT_GATE_FORWARD | SORT_GATE_BACKWARD)) ? 1ull : 0ull;
            at += 1u;
        }
    }
    good = good && (at == links->pairs);
    free(forward);
    free(backward);
    // the components by a breadth first walk from each gate pair's source in gate order
    const unsigned int nodes = sources + targets;
    unsigned int *const label = (unsigned int *)malloc(((size_t)nodes + 1u) * sizeof(unsigned int));
    unsigned int *const queue = (unsigned int *)malloc(((size_t)nodes + 1u) * sizeof(unsigned int));
    unsigned int *const by_source = (unsigned int *)calloc((size_t)sources + 2u, sizeof(unsigned int));
    unsigned int *const by_target = (unsigned int *)calloc((size_t)targets + 2u, sizeof(unsigned int));
    unsigned int *const target_pairs = (unsigned int *)malloc(((size_t)links->pairs + 1u) * sizeof(unsigned int));
    good = good && (label != NULL) && (queue != NULL) && (by_source != NULL) && (by_target != NULL)
        && (target_pairs != NULL);
    for (unsigned int pair_at = 0u; good && (pair_at < links->pairs); pair_at += 1u)
    {
        by_source[links->source[pair_at] + 1u] += 1u;
        by_target[links->target[pair_at] + 2u] += 1u;
    }
    for (unsigned int source = 0u; good && (source < sources); source += 1u)
    {
        by_source[source + 1u] += by_source[source];
    }
    for (unsigned int target = 0u; good && (target < targets); target += 1u)
    {
        by_target[target + 2u] += by_target[target + 1u];
    }
    for (unsigned int pair_at = 0u; good && (pair_at < links->pairs); pair_at += 1u)
    {
        target_pairs[by_target[links->target[pair_at] + 1u]] = pair_at;
        by_target[links->target[pair_at] + 1u] += 1u;
    }
    for (unsigned int node = 0u; good && (node < nodes); node += 1u)
    {
        label[node] = SORT_TEST_NONE;
    }
    unsigned int components = 0u;
    for (unsigned int pair_at = 0u; good && (pair_at < links->pairs); pair_at += 1u)
    {
        if (label[links->source[pair_at]] != SORT_TEST_NONE)
        {
            continue;
        }
        unsigned int head = 0u;
        unsigned int tail = 1u;
        queue[0] = links->source[pair_at];
        label[links->source[pair_at]] = components;
        while (head < tail)
        {
            const unsigned int node = queue[head];
            head += 1u;
            const unsigned int first = (node < sources) ? by_source[node] : by_target[node - sources];
            const unsigned int end = (node < sources) ? by_source[node + 1u] : by_target[node - sources + 1u];
            for (unsigned int edge = first; edge < end; edge += 1u)
            {
                const unsigned int other = (node < sources) ? (sources + links->target[edge])
                                                            : links->source[target_pairs[edge]];
                if (label[other] == SORT_TEST_NONE)
                {
                    label[other] = components;
                    queue[tail] = other;
                    tail += 1u;
                }
            }
        }
        components += 1u;
    }
    good = good && (components == links->components);
    unsigned long long *const need = (unsigned long long *)malloc(((size_t)components + 1u)
                                                                  * sizeof(unsigned long long));
    good = good && (need != NULL);
    for (unsigned int component = 0u; good && (component < components); component += 1u)
    {
        need[component] = 1ull;
    }
    for (unsigned int pair_at = 0u; good && (pair_at < links->pairs); pair_at += 1u)
    {
        good = (links->component[pair_at] == label[links->source[pair_at]]);
        need[label[links->source[pair_at]]] += links->cost[pair_at];
    }
    for (unsigned int pair_at = 0u; good && (pair_at < links->pairs); pair_at += 1u)
    {
        const unsigned long long weight = need[links->component[pair_at]] - links->cost[pair_at];
        good = (need[links->component[pair_at]] <= 0xFFFFFFFFull) && (weight >= 1ull)
            && (links->weight[pair_at] == weight);
    }
    // the chosen links: one to one, as many as the sort says, and as many as any matching of the gate holds
    unsigned char *const source_used = (unsigned char *)calloc((size_t)sources + 1u, 1u);
    unsigned char *const target_used = (unsigned char *)calloc((size_t)targets + 1u, 1u);
    good = good && (source_used != NULL) && (target_used != NULL);
    unsigned int counted = 0u;
    for (unsigned int pair_at = 0u; good && (pair_at < links->pairs); pair_at += 1u)
    {
        if ((links->flags[pair_at] & SORT_GATE_CHOSEN) == 0u)
        {
            continue;
        }
        good = (source_used[links->source[pair_at]] == 0u) && (target_used[links->target[pair_at]] == 0u);
        source_used[links->source[pair_at]] = 1u;
        target_used[links->target[pair_at]] = 1u;
        counted += 1u;
    }
    // a chosen count that is not a refusal is below 2^30, so it re-signs to unsigned long long exactly
    good = good && (counted == links->chosen) && ((unsigned long long)chosen == counted)
        && (sort_test_most_links(links, sources, targets) == counted);
    // each component's gate pairs and chosen links, grouped by the host's labels
    unsigned int *const group_start = (unsigned int *)calloc((size_t)components + 2u, sizeof(unsigned int));
    unsigned int *const group = (unsigned int *)malloc(((size_t)links->pairs + 1u) * sizeof(unsigned int));
    good = good && (group_start != NULL) && (group != NULL);
    for (unsigned int pair_at = 0u; good && (pair_at < links->pairs); pair_at += 1u)
    {
        group_start[label[links->source[pair_at]] + 2u] += 1u;
    }
    for (unsigned int component = 0u; good && (component < components); component += 1u)
    {
        group_start[component + 2u] += group_start[component + 1u];
    }
    for (unsigned int pair_at = 0u; good && (pair_at < links->pairs); pair_at += 1u)
    {
        group[group_start[label[links->source[pair_at]] + 1u]] = pair_at;
        group_start[label[links->source[pair_at]] + 1u] += 1u;
    }
    memset(source_used, 0, (size_t)sources + 1u);
    memset(target_used, 0, (size_t)targets + 1u);
    unsigned long long kept = 0ull;
    unsigned long long level = 0ull;
    unsigned long long crossed = 0ull;
    for (unsigned int component = 0u; good && (component < components); component += 1u)
    {
        const unsigned int first = group_start[component];
        const unsigned int end = group_start[component + 1u];
        unsigned int chosen_links = 0u;
        unsigned long long chosen_cost = 0ull;
        for (unsigned int one = first; one < end; one += 1u)
        {
            const unsigned int a = group[one];
            if ((links->flags[a] & SORT_GATE_CHOSEN) == 0u)
            {
                continue;
            }
            chosen_links += 1u;
            chosen_cost += links->cost[a];
            for (unsigned int other = one + 1u; other < end; other += 1u)
            {
                const unsigned int b = group[other];
                if ((links->flags[b] & SORT_GATE_CHOSEN) == 0u)
                {
                    continue;
                }
                long long dot = 0ll;
                for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
                {
                    const long long before = (long long)pair->source_places[(ENGINE_AXES * (size_t)links->source[a]) + axis]
                                           - (long long)pair->source_places[(ENGINE_AXES * (size_t)links->source[b]) + axis];
                    const long long after = (long long)pair->target_places[(ENGINE_AXES * (size_t)links->target[a]) + axis]
                                          - (long long)pair->target_places[(ENGINE_AXES * (size_t)links->target[b]) + axis];
                    dot += (long long)pair->weights[axis] * before * after;
                }
                kept += (dot > 0ll) ? 1ull : 0ull;
                level += (dot == 0ll) ? 1ull : 0ull;
                crossed += (dot < 0ll) ? 1ull : 0ull;
            }
        }
        if ((end - first) <= SORT_TEST_ENUMERATED_MOST)
        {
            SortTestEnumeration enumeration = {links, &group[first], end - first, source_used, target_used, 0u, 0ull};
            sort_test_enumerate(&enumeration, 0u, 0u, 0ull);
            good = (enumeration.best_links == chosen_links) && (enumeration.best_cost == chosen_cost);
            sums->enumerated += 1ull;
        }
    }
    good = good && (kept == links->kept) && (level == links->level) && (crossed == links->crossed);
    free(label);
    free(queue);
    free(by_source);
    free(by_target);
    free(target_pairs);
    free(need);
    free(source_used);
    free(target_used);
    free(group_start);
    free(group);
    sums->cases += 1ull;
    sums->agreed += (good != 0) ? 1ull : 0ull;
    sums->gate += links->pairs;
    sums->components += links->components;
    sums->chosen += links->chosen;
    sums->kept += links->kept;
    sums->level += links->level;
    sums->crossed += links->crossed;
    return good;
}

static void sort_test_sums_print(SimTally *tally, const char *what, const SortTestSums *sums)
{
    scriptura_text(&tally->line, "  ");
    scriptura_text(&tally->line, what);
    scriptura_text(&tally->line, ": ");
    scriptura_decimal(&tally->line, sums->agreed, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, sums->cases, 1u);
    scriptura_text(&tally->line, " pairs the host's; ");
    scriptura_decimal(&tally->line, sums->gate, 1u);
    scriptura_text(&tally->line, " gate pairs (");
    scriptura_decimal(&tally->line, sums->forward, 1u);
    scriptura_text(&tally->line, " forward, ");
    scriptura_decimal(&tally->line, sums->backward, 1u);
    scriptura_text(&tally->line, " backward, ");
    scriptura_decimal(&tally->line, sums->both, 1u);
    scriptura_text(&tally->line, " both), ");
    scriptura_decimal(&tally->line, sums->components, 1u);
    scriptura_text(&tally->line, " components, ");
    scriptura_decimal(&tally->line, sums->enumerated, 1u);
    scriptura_text(&tally->line, " enumerated; ");
    scriptura_decimal(&tally->line, sums->chosen, 1u);
    scriptura_text(&tally->line, " chosen; ");
    scriptura_decimal(&tally->line, sums->kept, 1u);
    scriptura_text(&tally->line, " kept, ");
    scriptura_decimal(&tally->line, sums->level, 1u);
    scriptura_text(&tally->line, " level, ");
    scriptura_decimal(&tally->line, sums->crossed, 1u);
    scriptura_text(&tally->line, " crossed\n");
    sim_flush(tally);
}

static void sort_test_place(int *place, unsigned long long key, unsigned long long counter, const long long low[3],
                            const long long span[3])
{
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        // a draw below the span, from a low bound, lies in the test's views, well inside int
        place[axis] = (int)(low[axis] + (long long)sim_draw_below(key, (counter * ENGINE_AXES) + axis,
                                                                  (unsigned long long)span[axis]));
    }
}

// no points on either side, one on each, and the host's gate on every one
static void sort_test_small_frames(SimTally *tally, SortLinks *links)
{
    const unsigned int weights[3] = {16u, 1u, 1u};
    const unsigned int shapes[3][2] = {{0u, 3u}, {3u, 0u}, {1u, 1u}};
    SortTestSums sums;
    memset(&sums, 0, sizeof(sums));
    int good = 1;
    for (unsigned int shape = 0u; shape < 3u; shape += 1u)
    {
        SortTestPair pair;
        if (sort_test_pair_hold(&pair, shapes[shape][0], shapes[shape][1], weights) == 0)
        {
            good = 0;
            sort_test_pair_release(&pair);
            continue;
        }
        const long long low[3] = {0ll, 0ll, 0ll};
        const long long span[3] = {4ll, 9ll, 9ll};
        for (unsigned int source = 0u; source < pair.sources; source += 1u)
        {
            sort_test_place(&pair.source_places[ENGINE_AXES * source], 0x50E7ull, source, low, span);
            sort_test_place(&pair.predictions[ENGINE_AXES * source], 0x50E8ull, source, low, span);
        }
        for (unsigned int target = 0u; target < pair.targets; target += 1u)
        {
            sort_test_place(&pair.target_places[ENGINE_AXES * target], 0x50E9ull, target, low, span);
        }
        good = sort_test_prove(&pair, links, &sums) && good;
        good = good && (links->pairs == ((shape == 2u) ? 1u : 0u));
        sort_test_pair_release(&pair);
    }
    sim_check(tally, good, "frames of no points give no gate, and one point against one gives one chosen link");
    sort_test_sums_print(tally, "no points, and one against one", &sums);
}

// targets on a lattice of even places and predictions at its odd midpoints: under 1, 1, 1 each prediction ties with
// eight targets
static void sort_test_lattice(SimTally *tally, SortLinks *links)
{
    const unsigned int weight_sets[2][3] = {{1u, 1u, 1u}, {16u, 1u, 1u}};
    SortTestSums sums;
    memset(&sums, 0, sizeof(sums));
    int good = 1;
    for (unsigned int set = 0u; set < 2u; set += 1u)
    {
        SortTestPair pair;
        if (sort_test_pair_hold(&pair, 2u * 3u * 3u, 3u * 4u * 4u, weight_sets[set]) == 0)
        {
            good = 0;
            sort_test_pair_release(&pair);
            continue;
        }
        unsigned int target = 0u;
        for (int z = 0; z <= 4; z += 2)
        {
            for (int y = 0; y <= 6; y += 2)
            {
                for (int x = 0; x <= 6; x += 2)
                {
                    pair.target_places[(ENGINE_AXES * target) + 0u] = z;
                    pair.target_places[(ENGINE_AXES * target) + 1u] = y;
                    pair.target_places[(ENGINE_AXES * target) + 2u] = x;
                    target += 1u;
                }
            }
        }
        unsigned int source = 0u;
        for (int z = 1; z <= 3; z += 2)
        {
            for (int y = 1; y <= 5; y += 2)
            {
                for (int x = 1; x <= 5; x += 2)
                {
                    const int place[3] = {z, y, x};
                    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
                    {
                        pair.predictions[(ENGINE_AXES * source) + axis] = place[axis];
                        pair.source_places[(ENGINE_AXES * source) + axis] = place[axis] - ((axis == 2u) ? 1 : 0);
                    }
                    source += 1u;
                }
            }
        }
        good = sort_test_prove(&pair, links, &sums) && good;
        sort_test_pair_release(&pair);
    }
    sim_check(tally, good, "a lattice's tied gate is the host's under 1, 1, 1 and 16, 1, 1");
    sort_test_sums_print(tally, "lattice ties", &sums);
}

// predictions drawn past every face of the view; the gate reads them as they are
static void sort_test_outside(SimTally *tally, SortLinks *links)
{
    const unsigned int weights[3] = {16u, 1u, 1u};
    SortTestSums sums;
    memset(&sums, 0, sizeof(sums));
    SortTestPair pair;
    int good = sort_test_pair_hold(&pair, 200u, 180u, weights);
    const long long view_low[3] = {0ll, 0ll, 0ll};
    const long long view_span[3] = {8ll, 40ll, 40ll};
    const long long wide_low[3] = {-6ll, -20ll, -20ll};
    const long long wide_span[3] = {20ll, 80ll, 80ll};
    unsigned long long outside = 0ull;
    for (unsigned int source = 0u; good && (source < pair.sources); source += 1u)
    {
        sort_test_place(&pair.source_places[ENGINE_AXES * source], 0x0875ull, source, view_low, view_span);
        sort_test_place(&pair.predictions[ENGINE_AXES * source], 0x0876ull, source, wide_low, wide_span);
        const int *const predicted = &pair.predictions[ENGINE_AXES * source];
        outside += ((predicted[0] < 0) || (predicted[0] >= 8) || (predicted[1] < 0) || (predicted[1] >= 40)
                    || (predicted[2] < 0) || (predicted[2] >= 40)) ? 1ull : 0ull;
    }
    for (unsigned int target = 0u; good && (target < pair.targets); target += 1u)
    {
        sort_test_place(&pair.target_places[ENGINE_AXES * target], 0x0877ull, target, view_low, view_span);
    }
    good = good && sort_test_prove(&pair, links, &sums);
    sort_test_pair_release(&pair);
    sim_check(tally, good && (outside != 0ull), "predictions outside the view are gated as the host gates them");
    scriptura_text(&tally->line, "  ");
    scriptura_decimal(&tally->line, outside, 1u);
    scriptura_text(&tally->line, " of 200 predictions outside the view\n");
    sort_test_sums_print(tally, "outside the view", &sums);
}

// three sources predicted at one place and fifty targets at one place: every pair ties both ways, 150 each way, past
// the tie list's room of twice the 50 points, so pass 2 takes each direction in batches
static void sort_test_pile(SimTally *tally, SortLinks *links)
{
    const unsigned int weights[3] = {16u, 1u, 1u};
    SortTestSums sums;
    memset(&sums, 0, sizeof(sums));
    SortTestPair pair;
    int good = sort_test_pair_hold(&pair, SORT_TEST_PILE_SOURCES, SORT_TEST_PILE_TARGETS, weights);
    for (unsigned int source = 0u; good && (source < pair.sources); source += 1u)
    {
        const int place[3] = {2, 7, 9};
        const int predicted[3] = {3, 5, 11};
        memcpy(&pair.source_places[ENGINE_AXES * source], place, sizeof(place));
        memcpy(&pair.predictions[ENGINE_AXES * source], predicted, sizeof(predicted));
    }
    for (unsigned int target = 0u; good && (target < pair.targets); target += 1u)
    {
        const int place[3] = {4, 6, 10};
        memcpy(&pair.target_places[ENGINE_AXES * target], place, sizeof(place));
    }
    // the pool is given back first, so the pile holds it for its own 50 points
    sort_release();
    good = good && sort_test_prove(&pair, links, &sums);
    good = good && (links->pairs == (SORT_TEST_PILE_SOURCES * SORT_TEST_PILE_TARGETS))
        && (links->chosen == SORT_TEST_PILE_SOURCES) && (links->components == 1u);
    sort_test_pair_release(&pair);
    sim_check(tally, good, "a pile of 150 ties each way, past the tie list's room, is gated whole in batches");
    sort_test_sums_print(tally, "a pile of ties in batches", &sums);
}

// small drawn frames whose components are small enough to enumerate every matching
static void sort_test_small_draws(SimTally *tally, SortLinks *links)
{
    const unsigned int weight_sets[2][3] = {{16u, 1u, 1u}, {1u, 1u, 1u}};
    SortTestSums sums;
    memset(&sums, 0, sizeof(sums));
    int good = 1;
    for (unsigned int draw = 0u; draw < SORT_TEST_SMALL_DRAWS; draw += 1u)
    {
        const unsigned long long key = 0x5A11ull + draw;
        // draws below 5, plus one, fit unsigned int
        const unsigned int sources = 1u + (unsigned int)sim_draw_below(key, 0ull, SORT_TEST_DRAWN_MOST);
        const unsigned int targets = 1u + (unsigned int)sim_draw_below(key, 1ull, SORT_TEST_DRAWN_MOST);
        SortTestPair pair;
        if (sort_test_pair_hold(&pair, sources, targets, weight_sets[draw % 2u]) == 0)
        {
            good = 0;
            sort_test_pair_release(&pair);
            continue;
        }
        const long long view_low[3] = {0ll, 0ll, 0ll};
        const long long view_span[3] = {3ll, 5ll, 5ll};
        const long long wide_low[3] = {-1ll, -1ll, -1ll};
        const long long wide_span[3] = {5ll, 7ll, 7ll};
        for (unsigned int source = 0u; source < sources; source += 1u)
        {
            sort_test_place(&pair.source_places[ENGINE_AXES * source], key ^ 0x100ull, source, view_low, view_span);
            sort_test_place(&pair.predictions[ENGINE_AXES * source], key ^ 0x200ull, source, wide_low, wide_span);
        }
        for (unsigned int target = 0u; target < targets; target += 1u)
        {
            sort_test_place(&pair.target_places[ENGINE_AXES * target], key ^ 0x300ull, target, view_low, view_span);
        }
        good = sort_test_prove(&pair, links, &sums) && good;
        sort_test_pair_release(&pair);
    }
    sim_check(tally, good, "small drawn frames: the gate, K, the matching and the crossings are the host's");
    sim_check(tally, sums.enumerated == sums.components,
              "every small drawn component is enumerated, and the chosen links are its most links at its least cost");
    sort_test_sums_print(tally, "small drawn frames", &sums);
}

// 6031 points against 6031, the most a frame of the scanned set holds, in a 64 x 256 x 256 view: most targets lie
// near a prediction and the rest are drawn anywhere
static void sort_test_large(SimTally *tally, SortLinks *links)
{
    const unsigned int weight_sets[2][3] = {{16u, 1u, 1u}, {1u, 1u, 1u}};
    const long long view_low[3] = {0ll, 0ll, 0ll};
    const long long view_span[3] = {64ll, 256ll, 256ll};
    const long long noise_low[3] = {-2ll, -2ll, -2ll};
    const long long noise_span[3] = {5ll, 5ll, 5ll};
    const int drift[3] = {1, -3, 2};
    for (unsigned int set = 0u; set < 2u; set += 1u)
    {
        SortTestSums sums;
        memset(&sums, 0, sizeof(sums));
        SortTestPair pair;
        int good = sort_test_pair_hold(&pair, SORT_TEST_POINTS_MOST, SORT_TEST_POINTS_MOST, weight_sets[set]);
        for (unsigned int source = 0u; good && (source < pair.sources); source += 1u)
        {
            int noise[3];
            sort_test_place(&pair.source_places[ENGINE_AXES * source], 0x1A7Eull, source, view_low, view_span);
            sort_test_place(noise, 0x1A7Full, source, noise_low, noise_span);
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                pair.predictions[(ENGINE_AXES * source) + axis]
                    = pair.source_places[(ENGINE_AXES * source) + axis] + drift[axis] + noise[axis];
            }
        }
        for (unsigned int target = 0u; good && (target < pair.targets); target += 1u)
        {
            int noise[3];
            sort_test_place(noise, 0x1A80ull, target, noise_low, noise_span);
            const int near = sim_draw_below(0x1A81ull, target, 10ull) != 0ull;
            if (near)
            {
                for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
                {
                    pair.target_places[(ENGINE_AXES * target) + axis]
                        = pair.predictions[(ENGINE_AXES * target) + axis] + noise[axis];
                }
            }
            else
            {
                sort_test_place(&pair.target_places[ENGINE_AXES * target], 0x1A82ull, target, view_low, view_span);
            }
        }
        good = good && sort_test_prove(&pair, links, &sums);
        sort_test_pair_release(&pair);
        sim_check(tally, good, (set == 0u) ? "6031 against 6031 under 16, 1, 1 is the host's"
                                           : "6031 against 6031 under 1, 1, 1 is the host's");
        sort_test_sums_print(tally, (set == 0u) ? "6031 against 6031, weights 16, 1, 1"
                                                : "6031 against 6031, weights 1, 1, 1", &sums);
    }
}

// one pair built from explicit places, each source predicted at its own place
static long sort_test_explicit(SortLinks *links, const unsigned int weights[3], unsigned int sources,
                               const int *source_places, unsigned int targets, const int *target_places)
{
    const SortPairRequest request = {{weights[0], weights[1], weights[2]}, sources, targets, source_places,
                                     source_places, target_places};
    return sort_link_pair(&request, links);
}

static void sort_test_refusals(SimTally *tally, SortLinks *links)
{
    const unsigned int ones[3] = {1u, 1u, 1u};
    const int origin[3] = {0, 0, 0};
    sim_check(tally, sort_link_pair(NULL, links) == SORT_REFUSED, "no request refuses");
    const SortPairRequest none = {{1u, 1u, 1u}, 1u, 1u, NULL, origin, origin};
    sim_check(tally, sort_link_pair(&none, NULL) == SORT_REFUSED, "nowhere to write the links refuses");
    sim_check(tally, (sort_link_pair(&none, links) == SORT_REFUSED) && (links->why == SORT_WHY_REQUEST),
              "sources with no places refuse as a request");
    const SortPairRequest crowded = {{1u, 1u, 1u}, SORT_COUNT_MOST + 1u, 1u, origin, origin, origin};
    sim_check(tally, (sort_link_pair(&crowded, links) == SORT_REFUSED) && (links->why == SORT_WHY_REQUEST),
              "more sources than the matching takes refuse as a request");
    // one axis's span of 3037000500 squares past 2^63 - 1; 3037000499 squares to 9223372030926249001, below it
    const int far_source[3] = {0, 0, -1518500250};
    const int far_target[3] = {0, 0, 1518500250};
    const int near_target[3] = {0, 0, 1518500249};
    sim_check(tally, (sort_test_explicit(links, ones, 1u, far_source, 1u, far_target) == SORT_REFUSED)
                         && (links->why == SORT_WHY_SPAN),
              "a span of 3037000500 on one axis squares past 2^63 - 1 and refuses");
    const long wide = sort_test_explicit(links, ones, 1u, far_source, 1u, near_target);
    sim_check(tally, (wide == SORT_REFUSED) && (links->why == SORT_WHY_WIDE) && (links->wide_component == 0u)
                         && (links->needs == 9223372030926249002ull) && (links->needs_past_64 == 0),
              "a cost of 9223372030926249001 needs K = 9223372030926249002, named, past 32 bits");
    scriptura_text(&tally->line, "  one link across 3037000499 needs K = ");
    scriptura_decimal(&tally->line, links->needs, 1u);
    scriptura_text(&tally->line, "\n");
    const int far_sources[9] = {0, 0, -1518500250, 0, 0, -1518500250, 0, 0, -1518500250};
    const long past = sort_test_explicit(links, ones, 3u, far_sources, 1u, near_target);
    sim_check(tally, (past == SORT_REFUSED) && (links->why == SORT_WHY_WIDE) && (links->needs_past_64 != 0),
              "three such costs in one component need K past 64 bits, named as such");
    // 5^2 + 362^2 + 65535^2 = 4294967294: K = 2^32 - 1 fits, and one more cost unit in the component does not
    const int edge_source[3] = {0, 0, 0};
    const int edge_target[3] = {5, 362, 65535};
    const long fits = sort_test_explicit(links, ones, 1u, edge_source, 1u, edge_target);
    sim_check(tally, (fits == 1L) && (links->weight[0] == 1u) && (links->cost[0] == 4294967294ull),
              "a cost of 4294967294 gives K = 4294967295, the widest that fits, and the weight 1");
    const int edge_sources[6] = {0, 0, 0, 5, 362, 65534};
    const long over = sort_test_explicit(links, ones, 2u, edge_sources, 1u, edge_target);
    sim_check(tally, (over == SORT_REFUSED) && (links->why == SORT_WHY_WIDE) && (links->needs == 4294967296ull),
              "costs of 4294967294 and 1 in one component need K = 4294967296 and refuse");
    scriptura_text(&tally->line, "  costs 4294967294 and 1 need K = ");
    scriptura_decimal(&tally->line, links->needs, 1u);
    scriptura_text(&tally->line, "\n");
    scriptura_text(&tally->line, "  not forced here: the gate's refusal when its ties pass 2^30 pairs (why ");
    scriptura_decimal(&tally->line, SORT_WHY_GATE, 1u);
    scriptura_text(&tally->line, "), which needs frames past what a test holds\n");
    sim_flush(tally);
}

static void sort_test_hold_bytes(SimTally *tally)
{
    const unsigned long long most = sort_hold_bytes(SORT_TEST_POINTS_MOST);
    sim_check(tally, (most != 0ull) && ((most % DEVICE_POOL_PAGE_BYTES) == 0ull),
              "the gate's pool for 6031 points is whole pages");
    sim_check(tally, sort_hold_bytes(0u) == 0ull, "no points hold nothing");
    sim_check(tally, sort_hold_bytes(SORT_COUNT_MOST + 1u) == 0ull, "points past the matching's bound hold nothing");
    scriptura_text(&tally->line, "  the gate holds ");
    scriptura_decimal(&tally->line, most, 1u);
    scriptura_text(&tally->line, " bytes for 6031 points a frame, ");
    scriptura_decimal(&tally->line, sort_hold_bytes(1u), 1u);
    scriptura_text(&tally->line, " for one\n");
    sim_flush(tally);
}

typedef struct
{
    unsigned int *words;
    size_t count;
    size_t room;
} SortTestWords;

static void sort_test_put(SortTestWords *words, unsigned int word)
{
    if (words->count < words->room)
    {
        words->words[words->count] = word;
    }
    words->count += 1u;
}

static int sort_test_file(const char *set, const char *sample, const char *suffix, const SortTestWords *words)
{
    char path[ENGINE_PATH_ROOM];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, suffix) ? fopen(path, "wb") : NULL;
    const int written = (file != NULL) && (words->count <= words->room)
                     && (fwrite(words->words, sizeof(unsigned int), words->count, file) == words->count);
    const int closed = (file != NULL) && (fclose(file) == 0);
    return written && closed;
}

static int sort_test_directory(const char *set, const char *sample)
{
    char path[ENGINE_PATH_ROOM];
    (void)SORT_TEST_MKDIR(set);
    const int written = snprintf(path, sizeof(path), "%s/%s", set, sample);
    // a non-negative length is compared whole against the room
    if ((written <= 0) || ((size_t)written >= sizeof(path)))
    {
        return 0;
    }
    (void)SORT_TEST_MKDIR(path);
    return 1;
}

// the whole file, as words; returns the words read, or SORT_TEST_NONE
static unsigned int sort_test_read(const char *set, const char *sample, const char *suffix, unsigned int *words,
                                   unsigned int room)
{
    char path[ENGINE_PATH_ROOM];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, suffix) ? fopen(path, "rb") : NULL;
    if (file == NULL)
    {
        return SORT_TEST_NONE;
    }
    const size_t read = fread(words, sizeof(unsigned int), room, file);
    const int ended = (read < room) && (feof(file) != 0);
    fclose(file);
    // a count below the room fits unsigned int
    return ended ? (unsigned int)read : SORT_TEST_NONE;
}

static int sort_test_exists(const char *set, const char *sample, const char *suffix)
{
    char path[ENGINE_PATH_ROOM];
    FILE *const file = engine_sample_path(path, sizeof(path), set, sample, suffix) ? fopen(path, "rb") : NULL;
    if (file != NULL)
    {
        fclose(file);
    }
    return file != NULL;
}

// the lag the .drift records at frame t + 1, carrying frame t onto it
static const int SORT_TEST_LAG[SORT_TEST_FRAMES - 1u][3] = {{0, 1, 0}, {0, 1, 1}, {1, 0, 0}, {0, -1, 0}};

static const int SORT_TEST_START[SORT_TEST_BODIES][3] = {{1, 3, 3}, {3, 20, 5}, {5, 5, 22}, {6, 22, 2}};

// each body's own step from frame t to t + 1 on top of the lag; body 3 stops after its first
static const int SORT_TEST_STEP[SORT_TEST_BODIES][3] = {{0, 1, 1}, {0, 0, 2}, {0, -1, 0}, {0, 0, -2}};

static int sort_test_step(unsigned int body, unsigned int frame, unsigned int axis)
{
    return ((body == 3u) && (frame > 0u)) ? 0 : SORT_TEST_STEP[body][axis];
}

// body b's place at frame t; frame t lists body (k + t) % 4 at index k
static void sort_test_chain_places(int places[SORT_TEST_FRAMES][SORT_TEST_BODIES][3])
{
    for (unsigned int body = 0u; body < SORT_TEST_BODIES; body += 1u)
    {
        for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
        {
            places[0][body][axis] = SORT_TEST_START[body][axis];
            for (unsigned int frame = 0u; (frame + 1u) < SORT_TEST_FRAMES; frame += 1u)
            {
                places[frame + 1u][body][axis] = places[frame][body][axis] + SORT_TEST_LAG[frame][axis]
                                               + sort_test_step(body, frame, axis);
            }
        }
    }
}

// the chain's .points and a .drift of the given weights
static int sort_test_chain_write(const char *set, const char *sample, const unsigned int weights[3],
                                 SortTestWords *words)
{
    int places[SORT_TEST_FRAMES][SORT_TEST_BODIES][3];
    sort_test_chain_places(places);
    words->count = 0u;
    const unsigned int head[6] = {SORT_TEST_FRAMES, SORT_TEST_DEPTH, SORT_TEST_SIDE, SORT_TEST_SIDE, 1u, 1u};
    for (unsigned int at = 0u; at < 6u; at += 1u)
    {
        sort_test_put(words, head[at]);
    }
    for (unsigned int at = 0u; at < (2u + (2u * SCAN_READINGS)); at += 1u)
    {
        sort_test_put(words, 0u);
    }
    for (unsigned int frame = 0u; frame < SORT_TEST_FRAMES; frame += 1u)
    {
        sort_test_put(words, SORT_TEST_BODIES);
        for (unsigned int index = 0u; index < SORT_TEST_BODIES; index += 1u)
        {
            const int *const place = places[frame][(index + frame) % SORT_TEST_BODIES];
            // a place inside the 8 x 32 x 32 view gives a voxel below 8192
            sort_test_put(words, (unsigned int)((((place[0] * (int)SORT_TEST_SIDE) + place[1]) * (int)SORT_TEST_SIDE)
                                                + place[2]));
        }
        for (unsigned int index = 0u; index < SORT_TEST_BODIES; index += 1u)
        {
            sort_test_put(words, 7u + index);
        }
    }
    int good = sort_test_file(set, sample, ".points", words);
    words->count = 0u;
    const unsigned int drift_head[7] = {SORT_TEST_FRAMES, SORT_TEST_DEPTH, SORT_TEST_SIDE, SORT_TEST_SIDE,
                                        weights[0], weights[1], weights[2]};
    for (unsigned int at = 0u; at < 7u; at += 1u)
    {
        sort_test_put(words, drift_head[at]);
    }
    for (unsigned int frame = 0u; frame < SORT_TEST_FRAMES; frame += 1u)
    {
        sort_test_put(words, 100u + frame);
        for (unsigned int axis = 0u; (frame != 0u) && (axis < ENGINE_AXES); axis += 1u)
        {
            // a signed lag is written as its two's complement word
            sort_test_put(words, (unsigned int)SORT_TEST_LAG[frame - 1u][axis]);
        }
        if (frame != 0u)
        {
            sort_test_put(words, 50u);
        }
    }
    good = good && sort_test_file(set, sample, ".drift", words);
    return good;
}

// a view one voxel deep and high and 2^31 - 1 wide: one point at x = 0, then one at x = 100000, and no drift; under
// 16, 1, 1 the link costs 10^10, and its component needs K = 10000000001
static int sort_test_wide_write(const char *set, const char *sample, SortTestWords *words)
{
    words->count = 0u;
    const unsigned int head[6] = {2u, 1u, 1u, 0x7FFFFFFFu, 1u, 1u};
    for (unsigned int at = 0u; at < 6u; at += 1u)
    {
        sort_test_put(words, head[at]);
    }
    for (unsigned int at = 0u; at < (2u + (2u * SCAN_READINGS)); at += 1u)
    {
        sort_test_put(words, 0u);
    }
    const unsigned int frames[2][3] = {{1u, 0u, 9u}, {1u, 100000u, 9u}};
    for (unsigned int frame = 0u; frame < 2u; frame += 1u)
    {
        for (unsigned int at = 0u; at < 3u; at += 1u)
        {
            sort_test_put(words, frames[frame][at]);
        }
    }
    int good = sort_test_file(set, sample, ".points", words);
    words->count = 0u;
    const unsigned int drift[7 + 1 + 5] = {2u, 1u, 1u, 0x7FFFFFFFu, 16u, 1u, 1u, 1u, 1u, 0u, 0u, 0u, 1u};
    for (unsigned int at = 0u; at < (7u + 1u + 5u); at += 1u)
    {
        sort_test_put(words, drift[at]);
    }
    good = good && sort_test_file(set, sample, ".drift", words);
    return good;
}

// the chain's .links read back: its header, each pair's counts, each source's prediction and flags, the chosen links
// following each body with their costs, the crossings recounted, and nothing past the last record
static int sort_test_chain_read(SimTally *tally, const unsigned int *links, unsigned int count)
{
    int places[SORT_TEST_FRAMES][SORT_TEST_BODIES][3];
    sort_test_chain_places(places);
    const unsigned int weights[3] = {16u, 1u, 1u};
    const unsigned int header[SORT_HEADER_WORDS] = {SORT_TEST_FRAMES, SORT_TEST_DEPTH, SORT_TEST_SIDE, SORT_TEST_SIDE,
                                                    16u, 1u, 1u, SORT_TERMS};
    int good = (count >= SORT_HEADER_WORDS) && (memcmp(links, header, sizeof(header)) == 0);
    sim_check(tally, good, "the chain's .links opens with its frames, view, weights 16, 1, 1 and terms 1");
    unsigned int at = SORT_HEADER_WORDS;
    unsigned int predicted = 0u;
    unsigned int outside = 0u;
    unsigned int carried = 0u;
    unsigned int followed = 0u;
    unsigned int zero_cost = 0u;
    for (unsigned int frame = 0u; good && ((frame + 1u) < SORT_TEST_FRAMES); frame += 1u)
    {
        good = (at + SORT_PAIR_WORDS) <= count;
        const unsigned int *const record = &links[at];
        good = good && (record[0] == SORT_TEST_BODIES) && (record[1] == SORT_TEST_BODIES)
            && (record[4] == SORT_TEST_BODIES);
        const unsigned int pairs = good ? record[2] : 0u;
        const unsigned long long counted[3] = {good ? (record[5] | ((unsigned long long)record[6] << 32u)) : 0ull,
                                               good ? (record[7] | ((unsigned long long)record[8] << 32u)) : 0ull,
                                               good ? (record[9] | ((unsigned long long)record[10] << 32u)) : 0ull};
        at += SORT_PAIR_WORDS;
        good = good && ((at + (SORT_SOURCE_WORDS * SORT_TEST_BODIES) + (SORT_GATE_WORDS * (size_t)pairs)) <= count);
        int source_places[SORT_TEST_BODIES][3];
        int target_places[SORT_TEST_BODIES][3];
        for (unsigned int index = 0u; good && (index < SORT_TEST_BODIES); index += 1u)
        {
            const unsigned int body = (index + frame) % SORT_TEST_BODIES;
            const unsigned int *const source = &links[at + (SORT_SOURCE_WORDS * index)];
            unsigned int flags = (frame != 0u) ? SORT_SOURCE_CARRIED : 0u;
            const int extent[3] = {(int)SORT_TEST_DEPTH, (int)SORT_TEST_SIDE, (int)SORT_TEST_SIDE};
            for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
            {
                const int want = places[frame][body][axis] + SORT_TEST_LAG[frame][axis]
                               + ((frame != 0u) ? sort_test_step(body, frame - 1u, axis) : 0);
                flags |= ((want < 0) || (want >= extent[axis])) ? SORT_SOURCE_OUTSIDE : 0u;
                // a prediction word is read back as the two's complement it was written as
                good = good && ((int)source[axis] == want);
                source_places[index][axis] = places[frame][body][axis];
                target_places[index][axis] = places[frame + 1u][(index + frame + 1u) % SORT_TEST_BODIES][axis];
            }
            good = good && (source[ENGINE_AXES] == flags);
            predicted += good ? 1u : 0u;
            outside += ((flags & SORT_SOURCE_OUTSIDE) != 0u) ? 1u : 0u;
            carried += ((flags & SORT_SOURCE_CARRIED) != 0u) ? 1u : 0u;
        }
        at += SORT_SOURCE_WORDS * SORT_TEST_BODIES;
        unsigned long long kept = 0ull;
        unsigned long long level = 0ull;
        unsigned long long crossed = 0ull;
        for (unsigned int one = 0u; good && (one < pairs); one += 1u)
        {
            const unsigned int *const gate = &links[at + (SORT_GATE_WORDS * one)];
            good = (gate[0] < SORT_TEST_BODIES) && (gate[1] < SORT_TEST_BODIES);
            if ((gate[6] & SORT_GATE_CHOSEN) == 0u)
            {
                continue;
            }
            const unsigned long long cost = gate[2] | ((unsigned long long)gate[3] << 32u);
            const unsigned int *const prediction = &links[at - (SORT_SOURCE_WORDS * SORT_TEST_BODIES)
                                                          + (SORT_SOURCE_WORDS * gate[0])];
            const int predicted_place[3] = {(int)prediction[0], (int)prediction[1], (int)prediction[2]};
            good = good && (gate[1] == ((gate[0] + SORT_TEST_BODIES - 1u) % SORT_TEST_BODIES))
                && (cost == sort_test_length(predicted_place, target_places[gate[1]], weights));
            followed += good ? 1u : 0u;
            zero_cost += (good && (cost == 0ull)) ? 1u : 0u;
            for (unsigned int other = one + 1u; good && (other < pairs); other += 1u)
            {
                const unsigned int *const next = &links[at + (SORT_GATE_WORDS * other)];
                if (((next[6] & SORT_GATE_CHOSEN) == 0u) || (next[5] != gate[5]))
                {
                    continue;
                }
                long long dot = 0ll;
                for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
                {
                    dot += (long long)weights[axis]
                         * (long long)(source_places[gate[0]][axis] - source_places[next[0]][axis])
                         * (long long)(target_places[gate[1]][axis] - target_places[next[1]][axis]);
                }
                kept += (dot > 0ll) ? 1ull : 0ull;
                level += (dot == 0ll) ? 1ull : 0ull;
                crossed += (dot < 0ll) ? 1ull : 0ull;
            }
        }
        good = good && (kept == counted[0]) && (level == counted[1]) && (crossed == counted[2]);
        at += SORT_GATE_WORDS * pairs;
    }
    good = good && (at == count);
    sim_check(tally, good, "the chain's .links reads back whole, record by record, with nothing past its last");
    sim_check(tally, (predicted == (SORT_TEST_BODIES * (SORT_TEST_FRAMES - 1u))) && (outside == 1u)
                         && (carried == (SORT_TEST_BODIES * (SORT_TEST_FRAMES - 2u))),
              "each prediction is x + d_t + (x - x_prev - d_{t-1}), one outside the view, and every source after the"
              " first frame carried");
    sim_check(tally, followed == (SORT_TEST_BODIES * (SORT_TEST_FRAMES - 1u)),
              "every chosen link follows its body, at the cost from its prediction");
    scriptura_text(&tally->line, "  the chain: ");
    scriptura_decimal(&tally->line, predicted, 1u);
    scriptura_text(&tally->line, " predictions as drawn, ");
    scriptura_decimal(&tally->line, outside, 1u);
    scriptura_text(&tally->line, " outside, ");
    scriptura_decimal(&tally->line, carried, 1u);
    scriptura_text(&tally->line, " carried; ");
    scriptura_decimal(&tally->line, followed, 1u);
    scriptura_text(&tally->line, " chosen links follow their bodies, ");
    scriptura_decimal(&tally->line, zero_cost, 1u);
    scriptura_text(&tally->line, " of them at cost 0\n");
    sim_flush(tally);
    return good;
}

static void sort_test_walk(SimTally *tally, const char *set)
{
    const unsigned int weights[3] = {16u, 1u, 1u};
    const unsigned int others[3] = {1u, 1u, 1u};
    SortTestWords words;
    words.room = SORT_TEST_POINTS_HEAD_WORDS + 64u;
    words.count = 0u;
    words.words = (unsigned int *)malloc(words.room * sizeof(unsigned int));
    unsigned int *const read = (unsigned int *)malloc(4096u * sizeof(unsigned int));
    unsigned int *const again = (unsigned int *)malloc(4096u * sizeof(unsigned int));
    const char *const names[3] = {"chain", "weighed", "wide"};
    int good = (set != NULL) && (words.words != NULL) && (read != NULL) && (again != NULL);
    for (unsigned int at = 0u; good && (at < 3u); at += 1u)
    {
        good = sort_test_directory(set, names[at]);
    }
    good = good && sort_test_chain_write(set, "chain", weights, &words)
        && sort_test_chain_write(set, "weighed", others, &words) && sort_test_wide_write(set, "wide", &words);
    // stale .links from an earlier run, which a refusing sample must not leave behind
    words.count = 0u;
    sort_test_put(&words, 0xDEADu);
    good = good && sort_test_file(set, "weighed", ".links", &words) && sort_test_file(set, "wide", ".links", &words);
    sim_check(tally, good, "the synthetic set is written: a chain, a chain of other weights, and a wide pair");
    char shown[ENGINE_PATH_ROOM];
    if (good && engine_sample_path(shown, sizeof(shown), set, "chain", ".links"))
    {
        scriptura_text(&tally->line, "  the chain's .links, by the restated engine_sample_path: ");
        scriptura_text(&tally->line, shown);
        scriptura_text(&tally->line, "\n");
    }
    unsigned int most = 0u;
    char *const every[3] = {(char *)"chain", (char *)"weighed", (char *)"wide"};
    char *const missing[1] = {(char *)"absent"};
    sim_check(tally, good && sort_points_most(set, every, 3u, &most) && (most == SORT_TEST_BODIES),
              "the most points a frame over the synthetic set is 4");
    sim_check(tally, good && (sort_points_most(set, missing, 1u, &most) == 0),
              "a sample with no .points gives no most points a frame");
    sim_flush(tally);
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long voxel_pm[3] = {1625000ull, 406250ull, 406250ull};
    SortRequest request;
    memset(&request, 0, sizeof(request));
    request.set = set;
    request.samples = every;
    request.count = 1u;
    memcpy(request.voxel_pm, voxel_pm, sizeof(voxel_pm));
    request.error = &error;
    fflush(stdout);
    const long alone = good ? sort_link_set(&request) : SORT_REFUSED;
    fflush(stdout);
    fflush(stderr);
    sim_check(tally, alone == 0L, "the chain alone sorts");
    const unsigned int count = (alone == 0L) ? sort_test_read(set, "chain", ".links", read, 4096u) : SORT_TEST_NONE;
    good = (count != SORT_TEST_NONE) && sort_test_chain_read(tally, read, count);
    request.count = 3u;
    const long all = good ? sort_link_set(&request) : 0L;
    fflush(stdout);
    fflush(stderr);
    const unsigned int count_again = sort_test_read(set, "chain", ".links", again, 4096u);
    sim_check(tally, all == SORT_REFUSED, "a set with a refusing sample refuses");
    sim_check(tally, (count_again == count) && (memcmp(read, again, (size_t)count * sizeof(unsigned int)) == 0),
              "the chain's .links, sorted again beside refusing samples, is the same to the word");
    sim_check(tally, sort_test_exists(set, "weighed", ".links") == 0,
              "a .drift of weights 1, 1, 1 under voxel_pm's 16, 1, 1 refuses and leaves no .links");
    sim_check(tally, sort_test_exists(set, "wide", ".links") == 0,
              "a component needing K = 10000000001 refuses and leaves no .links");
    request.count = 0u;
    sim_check(tally, sort_link_set(&request) == SORT_REFUSED, "a set of no samples refuses");
    sim_check(tally, sort_link_set(NULL) == SORT_REFUSED, "no request refuses");
    free(words.words);
    free(read);
    free(again);
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    const int admitted = sim_job_submit(&tally, "sort_test", count, arguments,
                                        sort_hold_bytes(SORT_TEST_POINTS_MOST));
    SortLinks links;
    memset(&links, 0, sizeof(links));
    if (admitted != 0)
    {
        sort_test_hold_bytes(&tally);
        sort_test_small_frames(&tally, &links);
        sort_test_pile(&tally, &links);
        sort_test_lattice(&tally, &links);
        sort_test_outside(&tally, &links);
        sort_test_small_draws(&tally, &links);
        sort_test_large(&tally, &links);
        sort_test_refusals(&tally, &links);
        sort_test_walk(&tally, (count > 1) ? arguments[1] : NULL);
    }
    sort_links_release(&links);
    sort_release();
    return sim_close(&tally, "sort test");
}
