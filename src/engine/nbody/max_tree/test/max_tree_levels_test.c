// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// A2 on the host tree, against a flood of each upper level set counted here from the values alone: the nodes and their
// DFS ranges, the component at every level, the probe partition at every level from the k - 1 LCA levels, and the
// overlap at every pair of levels from the one own-node pair table. Host only; no device is touched.
#include "max_tree.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LEVELS_TEST_PROBES 12u

#define LEVELS_TEST_EXTENT_MOST 7u

#define LEVELS_TEST_VOXELS_MOST (LEVELS_TEST_EXTENT_MOST * LEVELS_TEST_EXTENT_MOST * LEVELS_TEST_EXTENT_MOST)

typedef struct
{
    unsigned int checks;
    unsigned int failed;
} LevelsTally;

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    long long value[LEVELS_TEST_VOXELS_MOST];
    unsigned int rank[LEVELS_TEST_VOXELS_MOST];
    unsigned int levels;
    unsigned int residual[LEVELS_TEST_VOXELS_MOST * ENGINE_RESIDUAL_LIMBS];
} LevelsVolume;

static void levels_check(LevelsTally *tally, int held, const char *what, unsigned int volume, unsigned int level)
{
    tally->checks += 1u;
    if (held == 0)
    {
        tally->failed += 1u;
        if (tally->failed <= 20u)
        {
            printf("  FAIL %s (volume %u, level %u)\n", what, volume, level);
        }
    }
}

static unsigned long long levels_draw(unsigned long long *state)
{
    *state += 0x9E3779B97F4A7C15ull;
    unsigned long long mixed = *state;
    mixed = (mixed ^ (mixed >> 30u)) * 0xBF58476D1CE4E5B9ull;
    mixed = (mixed ^ (mixed >> 27u)) * 0x94D049BB133111EBull;
    return mixed ^ (mixed >> 31u);
}

// each value in `ENGINE_RESIDUAL_LIMBS` limbs of two's complement, as the residual lays it
static void levels_lay(LevelsVolume *volume)
{
    for (unsigned int voxel = 0u; voxel < volume->voxels; voxel += 1u)
    {
        // the value's 64-bit two's complement, split into its two 32-bit halves
        const unsigned long long bits = (unsigned long long)volume->value[voxel];
        unsigned int *const limbs = &volume->residual[voxel * ENGINE_RESIDUAL_LIMBS];
        // the low half of the 64-bit pattern
        limbs[0] = (unsigned int)(bits & 0xFFFFFFFFull);
        // the high half of the 64-bit pattern
        limbs[1] = (unsigned int)(bits >> 32u);
        for (unsigned int limb = 2u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
        {
            limbs[limb] = (volume->value[voxel] < 0ll) ? 0xFFFFFFFFu : 0u;
        }
    }
}

// each positive value's dense rank among the positive values, 1 the least; 0 for a value not above zero
static void levels_rank(LevelsVolume *volume)
{
    volume->levels = 0u;
    for (unsigned int voxel = 0u; voxel < volume->voxels; voxel += 1u)
    {
        unsigned int below = 0u;
        for (unsigned int other = 0u; (volume->value[voxel] > 0ll) && (other < volume->voxels); other += 1u)
        {
            int lower = (volume->value[other] > 0ll) && (volume->value[other] < volume->value[voxel]);
            for (unsigned int earlier = 0u; (lower != 0) && (earlier < other); earlier += 1u)
            {
                lower = (volume->value[earlier] != volume->value[other]) ? lower : 0;
            }
            below += (lower != 0) ? 1u : 0u;
        }
        volume->rank[voxel] = (volume->value[voxel] > 0ll) ? (below + 1u) : 0u;
        volume->levels = (volume->rank[voxel] > volume->levels) ? volume->rank[voxel] : volume->levels;
    }
}

static void levels_fill(LevelsVolume *volume, unsigned long long *state, unsigned int depth, unsigned int height,
                        unsigned int width, long long least, long long most, int wide)
{
    volume->depth = depth;
    volume->height = height;
    volume->width = width;
    volume->voxels = depth * height * width;
    // the span of values is small and positive, and fits the draw's modulus
    const unsigned long long span = (unsigned long long)(most - least) + 1ull;
    for (unsigned int voxel = 0u; voxel < volume->voxels; voxel += 1u)
    {
        // a draw below the span is below 2^63
        long long value = least + (long long)(levels_draw(state) % span);
        if (wide != 0)
        {
            // a small high part moves the value across the limb boundary; the sum stays far inside 64 bits
            value += ((long long)(levels_draw(state) % 5ull) - 2ll) * 4294967296ll;
        }
        volume->value[voxel] = value;
    }
    levels_lay(volume);
    levels_rank(volume);
}

// the components of the upper set {rank >= level}, six-connected, numbered from 0; MAX_TREE_ABSENT outside it
static unsigned int levels_flood(const LevelsVolume *volume, unsigned int level, unsigned int *label)
{
    unsigned int waiting[LEVELS_TEST_VOXELS_MOST];
    unsigned int marks = 0u;
    const unsigned int plane = volume->height * volume->width;
    for (unsigned int voxel = 0u; voxel < volume->voxels; voxel += 1u)
    {
        label[voxel] = MAX_TREE_ABSENT;
    }
    for (unsigned int seed = 0u; seed < volume->voxels; seed += 1u)
    {
        if ((label[seed] != MAX_TREE_ABSENT) || (volume->rank[seed] == 0u) || (volume->rank[seed] < level))
        {
            continue;
        }
        unsigned int wanted = 0u;
        waiting[wanted] = seed;
        wanted += 1u;
        label[seed] = marks;
        while (wanted != 0u)
        {
            wanted -= 1u;
            const unsigned int voxel = waiting[wanted];
            // coordinates of a voxel inside a volume of at most 7 on a side
            const int z = (int)(voxel / plane);
            const int y = (int)((voxel % plane) / volume->width);
            const int x = (int)((voxel % plane) % volume->width);
            const int steps[6][3] = {{-1, 0, 0}, {1, 0, 0}, {0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1}};
            for (unsigned int step = 0u; step < 6u; step += 1u)
            {
                const int near_z = z + steps[step][0];
                const int near_y = y + steps[step][1];
                const int near_x = x + steps[step][2];
                // each extent is at most 7 and compares as an int
                if ((near_z < 0) || (near_z >= (int)volume->depth) || (near_y < 0) || (near_y >= (int)volume->height)
                 || (near_x < 0) || (near_x >= (int)volume->width))
                {
                    continue;
                }
                // the neighbor lies inside the volume: its index is not negative
                const unsigned int near = (unsigned int)((((near_z * (int)volume->height) + near_y)
                                                          * (int)volume->width) + near_x);
                if ((label[near] != MAX_TREE_ABSENT) || (volume->rank[near] == 0u) || (volume->rank[near] < level))
                {
                    continue;
                }
                label[near] = marks;
                waiting[wanted] = near;
                wanted += 1u;
            }
        }
        marks += 1u;
    }
    return marks;
}

// at every level, the flood's components and the tree's components are one to one over the voxels; `node_of` is left
// naming each flood component's node at the last level asked
static int levels_components_agree(const LevelsVolume *volume, const MaxTreeNodes *nodes, unsigned int level,
                                   const unsigned int *label, unsigned int marks, unsigned int *node_of)
{
    unsigned int label_of[LEVELS_TEST_VOXELS_MOST];
    for (unsigned int node = 0u; node < nodes->count; node += 1u)
    {
        label_of[node] = MAX_TREE_ABSENT;
    }
    for (unsigned int mark = 0u; mark < marks; mark += 1u)
    {
        node_of[mark] = MAX_TREE_ABSENT;
    }
    int held = 1;
    for (unsigned int voxel = 0u; voxel < volume->voxels; voxel += 1u)
    {
        const unsigned int own = nodes->own[voxel];
        const unsigned int node = (own == MAX_TREE_ABSENT) ? MAX_TREE_ABSENT : max_tree_node_at(nodes, own, level);
        if (label[voxel] == MAX_TREE_ABSENT)
        {
            held = (node == MAX_TREE_ABSENT) ? held : 0;
            continue;
        }
        if (node == MAX_TREE_ABSENT)
        {
            held = 0;
            continue;
        }
        if (node_of[label[voxel]] == MAX_TREE_ABSENT)
        {
            node_of[label[voxel]] = node;
        }
        if (label_of[node] == MAX_TREE_ABSENT)
        {
            label_of[node] = label[voxel];
        }
        held = ((node_of[label[voxel]] == node) && (label_of[node] == label[voxel])) ? held : 0;
    }
    return held;
}

// the nodes' own shape: DFS ranges nest, levels rise from parent to child, roots name themselves, and every admitted
// voxel's own node is at its rank and holds its value
static int levels_nodes_hold(const LevelsVolume *volume, const MaxTreeNodes *nodes)
{
    int held = (nodes->levels == volume->levels);
    for (unsigned int node = 0u; node < nodes->count; node += 1u)
    {
        const unsigned int above = nodes->parent[node];
        held = ((nodes->subtree_end[node] > node) && (nodes->subtree_end[node] <= nodes->count)) ? held : 0;
        if (above == node)
        {
            held = (nodes->root[node] == node) ? held : 0;
            continue;
        }
        held = ((above < node) && (nodes->level[above] < nodes->level[node])
                && (nodes->subtree_end[node] <= nodes->subtree_end[above]) && (nodes->root[node] == nodes->root[above]))
             ? held : 0;
    }
    for (unsigned int voxel = 0u; voxel < volume->voxels; voxel += 1u)
    {
        const unsigned int own = nodes->own[voxel];
        if (volume->rank[voxel] == 0u)
        {
            held = (own == MAX_TREE_ABSENT) ? held : 0;
            continue;
        }
        held = ((own != MAX_TREE_ABSENT) && (nodes->level[own] == volume->rank[voxel])
                && (volume->value[nodes->voxel[own]] == volume->value[voxel]))
             ? held : 0;
    }
    return held;
}

// the probe partition at `level` against the flood: absent exactly where the probe's voxel is below the level, and two
// present probes in one part exactly where they are in one flood component
static int levels_probes_agree(const LevelsVolume *volume, const unsigned int *probe_voxels, const unsigned int *part,
                               const unsigned int *label, unsigned int level)
{
    int held = 1;
    for (unsigned int one = 0u; one < LEVELS_TEST_PROBES; one += 1u)
    {
        const unsigned int voxel = probe_voxels[one];
        const int present = (volume->rank[voxel] != 0u) && (volume->rank[voxel] >= level);
        held = (present == (part[one] != MAX_TREE_ABSENT)) ? held : 0;
        for (unsigned int other = 0u; (present != 0) && (other < LEVELS_TEST_PROBES); other += 1u)
        {
            if (part[other] == MAX_TREE_ABSENT)
            {
                continue;
            }
            const int together = (label[voxel] == label[probe_voxels[other]]);
            held = (together == (part[one] == part[other])) ? held : 0;
        }
    }
    return held;
}

// every pair of levels: C counted directly from the two floods at the lag, against the table's rectangle sums over the
// two components' nodes
static void levels_overlap_agree(LevelsTally *tally, unsigned int case_number, const LevelsVolume *earlier,
                                 const LevelsVolume *later, const MaxTreeNodes *earlier_nodes,
                                 const MaxTreeNodes *later_nodes, const MaxTreePairs *pairs, const int *lag)
{
    static unsigned int earlier_label[LEVELS_TEST_VOXELS_MOST];
    static unsigned int later_label[LEVELS_TEST_VOXELS_MOST];
    static unsigned int earlier_node[LEVELS_TEST_VOXELS_MOST];
    static unsigned int later_node[LEVELS_TEST_VOXELS_MOST];
    static unsigned long long direct[LEVELS_TEST_VOXELS_MOST * LEVELS_TEST_VOXELS_MOST];
    static unsigned int asked_earlier[LEVELS_TEST_VOXELS_MOST * LEVELS_TEST_VOXELS_MOST];
    static unsigned int asked_later[LEVELS_TEST_VOXELS_MOST * LEVELS_TEST_VOXELS_MOST];
    static unsigned long long sums[LEVELS_TEST_VOXELS_MOST * LEVELS_TEST_VOXELS_MOST];
    const unsigned int plane = earlier->height * earlier->width;
    for (unsigned int level = 1u; level <= earlier->levels; level += 1u)
    {
        const unsigned int earlier_marks = levels_flood(earlier, level, earlier_label);
        levels_components_agree(earlier, earlier_nodes, level, earlier_label, earlier_marks, earlier_node);
        for (unsigned int later_level = 1u; later_level <= later->levels; later_level += 1u)
        {
            const unsigned int later_marks = levels_flood(later, later_level, later_label);
            levels_components_agree(later, later_nodes, later_level, later_label, later_marks, later_node);
            memset(direct, 0, (size_t)earlier_marks * later_marks * sizeof(unsigned long long));
            for (unsigned int voxel = 0u; voxel < earlier->voxels; voxel += 1u)
            {
                if (earlier_label[voxel] == MAX_TREE_ABSENT)
                {
                    continue;
                }
                // coordinates of a voxel inside a volume of at most 7 on a side, moved by a lag of at most 1
                const int z = (int)(voxel / plane) + lag[0];
                const int y = (int)((voxel % plane) / earlier->width) + lag[1];
                const int x = (int)((voxel % plane) % earlier->width) + lag[2];
                // each extent is at most 7 and compares as an int
                if ((z < 0) || (z >= (int)earlier->depth) || (y < 0) || (y >= (int)earlier->height) || (x < 0)
                 || (x >= (int)earlier->width))
                {
                    continue;
                }
                // the target lies inside the volume: its index is not negative
                const unsigned int target = (unsigned int)((((z * (int)earlier->height) + y) * (int)earlier->width)
                                                           + x);
                if (later_label[target] == MAX_TREE_ABSENT)
                {
                    continue;
                }
                direct[(earlier_label[voxel] * later_marks) + later_label[target]] += 1ull;
            }
            unsigned int asked = 0u;
            for (unsigned int one = 0u; one < earlier_marks; one += 1u)
            {
                for (unsigned int other = 0u; other < later_marks; other += 1u)
                {
                    asked_earlier[asked] = earlier_node[one];
                    asked_later[asked] = later_node[other];
                    asked += 1u;
                }
            }
            EngineError error;
            memset(&error, 0, sizeof(error));
            const MaxTreeOverlapSumsRequest request = {earlier_nodes, later_nodes, pairs, asked_earlier, asked_later,
                                                       asked, sums, &error};
            int held = (max_tree_overlap_sums(&request) == (long)asked);
            for (unsigned int query = 0u; (held != 0) && (query < asked); query += 1u)
            {
                held = (sums[query] == direct[query]) ? held : 0;
            }
            levels_check(tally, held, "overlap sums equal the direct count at a pair of levels", case_number, level);
        }
    }
}

static void levels_case(LevelsTally *tally, unsigned int case_number, const LevelsVolume *earlier,
                        const LevelsVolume *later, const int *lag, unsigned long long *state)
{
    static unsigned int label[LEVELS_TEST_VOXELS_MOST];
    static unsigned int node_of[LEVELS_TEST_VOXELS_MOST];
    MaxTree earlier_tree;
    MaxTree later_tree;
    MaxTreeNodes earlier_nodes;
    MaxTreeNodes later_nodes;
    MaxTreePairs pairs;
    memset(&earlier_nodes, 0, sizeof(earlier_nodes));
    memset(&later_nodes, 0, sizeof(later_nodes));
    memset(&pairs, 0, sizeof(pairs));
    EngineError error;
    memset(&error, 0, sizeof(error));
    const long built = max_tree_build(earlier->residual, earlier->depth, earlier->height, earlier->width,
                                      &earlier_tree);
    const long later_built = max_tree_build(later->residual, later->depth, later->height, later->width, &later_tree);
    levels_check(tally, (built >= 0L) && (later_built >= 0L), "both trees build", case_number, 0u);
    if ((built < 0L) || (later_built < 0L))
    {
        return;
    }
    const MaxTreeNodesRequest earlier_request = {earlier->residual, &earlier_tree, &earlier_nodes, &error};
    const MaxTreeNodesRequest later_request = {later->residual, &later_tree, &later_nodes, &error};
    const long counted = max_tree_nodes(&earlier_request);
    const long later_counted = max_tree_nodes(&later_request);
    levels_check(tally, (counted >= 0L) && (later_counted >= 0L), "both trees give their nodes", case_number, 0u);
    if ((counted >= 0L) && (later_counted >= 0L))
    {
        levels_check(tally, levels_nodes_hold(earlier, &earlier_nodes) && levels_nodes_hold(later, &later_nodes),
                     "nodes nest in DFS order, rise in level and hold their voxels' ranks", case_number, 0u);
        for (unsigned int level = 1u; level <= earlier->levels; level += 1u)
        {
            const unsigned int marks = levels_flood(earlier, level, label);
            levels_check(tally, levels_components_agree(earlier, &earlier_nodes, level, label, marks, node_of),
                         "the component at a level is the flood's", case_number, level);
        }
        for (unsigned int level = 1u; level <= later->levels; level += 1u)
        {
            const unsigned int marks = levels_flood(later, level, label);
            levels_check(tally, levels_components_agree(later, &later_nodes, level, label, marks, node_of),
                         "the later frame's component at a level is the flood's", case_number, level);
        }
        unsigned int probe_voxels[LEVELS_TEST_PROBES];
        unsigned int sorted[LEVELS_TEST_PROBES];
        unsigned int own_level[LEVELS_TEST_PROBES];
        unsigned int joined[LEVELS_TEST_PROBES];
        unsigned int part[LEVELS_TEST_PROBES];
        for (unsigned int probe = 0u; probe < LEVELS_TEST_PROBES; probe += 1u)
        {
            // a draw below the voxel count fits an unsigned int
            probe_voxels[probe] = (unsigned int)(levels_draw(state) % earlier->voxels);
        }
        const MaxTreeProbeRequest probe_request = {&earlier_nodes, probe_voxels, LEVELS_TEST_PROBES, sorted,
                                                   own_level, joined, &error};
        const long probed = max_tree_probe_levels(&probe_request);
        levels_check(tally, probed == (long)LEVELS_TEST_PROBES, "the probe levels are read", case_number, 0u);
        for (unsigned int level = 1u; (probed >= 0L) && (level <= earlier->levels); level += 1u)
        {
            levels_flood(earlier, level, label);
            max_tree_probe_partition(sorted, own_level, joined, LEVELS_TEST_PROBES, level, part);
            levels_check(tally, levels_probes_agree(earlier, probe_voxels, part, label, level),
                         "the probe partition at a level is the flood's", case_number, level);
        }
        const MaxTreePairsRequest pairs_request = {&earlier_nodes, &later_nodes, {lag[0], lag[1], lag[2]}, &pairs,
                                                  &error};
        const long entries = max_tree_pairs(&pairs_request);
        levels_check(tally, entries >= 0L, "the pair table is built", case_number, 0u);
        if (entries >= 0L)
        {
            levels_overlap_agree(tally, case_number, earlier, later, &earlier_nodes, &later_nodes, &pairs, lag);
        }
    }
    max_tree_pairs_release(&pairs);
    max_tree_nodes_release(&earlier_nodes);
    max_tree_nodes_release(&later_nodes);
    max_tree_release(&earlier_tree);
    max_tree_release(&later_tree);
}

// requests the module must refuse, each with a request error from max_tree and nothing written
static void levels_refusals(LevelsTally *tally, const LevelsVolume *volume)
{
    MaxTree tree;
    MaxTreeNodes nodes;
    MaxTreeNodes other_nodes;
    MaxTreePairs pairs;
    memset(&nodes, 0, sizeof(nodes));
    memset(&other_nodes, 0, sizeof(other_nodes));
    memset(&pairs, 0, sizeof(pairs));
    if (max_tree_build(volume->residual, volume->depth, volume->height, volume->width, &tree) < 0L)
    {
        levels_check(tally, 0, "the refusals' tree builds", 0u, 0u);
        return;
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    const MaxTreeNodesRequest unerrored = {volume->residual, &tree, &nodes, NULL};
    levels_check(tally, max_tree_nodes(&unerrored) == MAX_TREE_REFUSED, "a request with no error refuses", 0u, 0u);
    const MaxTreeNodesRequest request = {volume->residual, &tree, &nodes, &error};
    levels_check(tally, max_tree_nodes(&request) >= 0L, "the refusals' nodes are given", 0u, 0u);
    unsigned int probe_voxels[2] = {0u, volume->voxels};
    unsigned int sorted[2];
    unsigned int own_level[2];
    unsigned int joined[2];
    const MaxTreeProbeRequest outside = {&nodes, probe_voxels, 2u, sorted, own_level, joined, &error};
    levels_check(tally,
                 (max_tree_probe_levels(&outside) == MAX_TREE_REFUSED) && (error.kind == ENGINE_ERROR_REQUEST)
                     && (error.module == ENGINE_MODULE_MAX_TREE),
                 "a probe past the volume refuses, a request error from max_tree", 0u, 0u);
    memset(&error, 0, sizeof(error));
    other_nodes = nodes;
    other_nodes.width = nodes.width + 1u;
    const MaxTreePairsRequest mismatched = {&nodes, &other_nodes, {0, 0, 0}, &pairs, &error};
    levels_check(tally,
                 (max_tree_pairs(&mismatched) == MAX_TREE_REFUSED) && (error.kind == ENGINE_ERROR_REQUEST)
                     && (pairs.count == 0u) && (pairs.earlier == NULL),
                 "two frames of different extents refuse the pair table", 0u, 0u);
    memset(&error, 0, sizeof(error));
    const MaxTreePairsRequest same = {&nodes, &nodes, {0, 0, 0}, &pairs, &error};
    const long entries = max_tree_pairs(&same);
    const unsigned int past = nodes.count;
    const unsigned int first = 0u;
    unsigned long long sum = 0ull;
    const MaxTreeOverlapSumsRequest beyond = {&nodes, &nodes, &pairs, &past, &first, 1u, &sum, &error};
    levels_check(tally,
                 (entries >= 0L) && (max_tree_overlap_sums(&beyond) == MAX_TREE_REFUSED)
                     && (error.kind == ENGINE_ERROR_REQUEST),
                 "a node past the tree refuses the overlap sums", 0u, 0u);
    max_tree_pairs_release(&pairs);
    max_tree_nodes_release(&nodes);
    max_tree_release(&tree);
}

int main(void)
{
    static LevelsVolume earlier;
    static LevelsVolume later;
    LevelsTally tally = {0u, 0u};
    unsigned long long state = 0x243F6A8885A308D3ull;
    unsigned int case_number = 0u;
    // many ties and plateaus, then more levels, then values that cross the limb boundary
    const long long least[3] = {-2ll, -40ll, -9ll};
    const long long most[3] = {5ll, 60ll, 9ll};
    const unsigned int cases[3] = {60u, 30u, 20u};
    for (unsigned int kind = 0u; kind < 3u; kind += 1u)
    {
        for (unsigned int drawn = 0u; drawn < cases[kind]; drawn += 1u)
        {
            // each extent is drawn from 1 to 7, and the lag from -1 to 1 on each axis
            const unsigned int depth = 1u + (unsigned int)(levels_draw(&state) % 3ull);
            const unsigned int height = 1u + (unsigned int)(levels_draw(&state) % LEVELS_TEST_EXTENT_MOST);
            const unsigned int width = 1u + (unsigned int)(levels_draw(&state) % LEVELS_TEST_EXTENT_MOST);
            const int lag[3] = {(int)(levels_draw(&state) % 3ull) - 1, (int)(levels_draw(&state) % 3ull) - 1,
                                (int)(levels_draw(&state) % 3ull) - 1};
            levels_fill(&earlier, &state, depth, height, width, least[kind], most[kind], kind == 2u);
            levels_fill(&later, &state, depth, height, width, least[kind], most[kind], kind == 2u);
            levels_case(&tally, case_number, &earlier, &later, lag, &state);
            case_number += 1u;
        }
    }
    levels_fill(&earlier, &state, 3u, 5u, 6u, -2ll, 5ll, 0);
    levels_refusals(&tally, &earlier);
    printf("  max_tree levels test: %u volumes, %u checks, %u failed\n", case_number, tally.checks, tally.failed);
    return (tally.failed == 0u) ? 0 : 1;
}
