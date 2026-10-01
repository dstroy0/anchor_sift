// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_levels_test_agree.c: probes, overlaps, cases, errors and main
#include "max_tree_levels_test_internal.h"

// the probe partition at `level` against the flood: absent exactly where the probe's voxel is below the level, and two
// present probes in one part exactly where they are in one flood component
static int levels_probes_agree(const LevelsVolume *volume, const unsigned int *probe_voxels, const unsigned int *part,
                               const unsigned int *label, unsigned int level)
{
    int passed = 1;
    for (unsigned int one = 0u; one < LEVELS_TEST_PROBES; one += 1u)
    {
        const unsigned int voxel = probe_voxels[one];
        const int present = (volume->rank[voxel] != 0u) && (volume->rank[voxel] >= level);
        passed = (present == (part[one] != MAX_TREE_ABSENT)) ? passed : 0;
        for (unsigned int other = 0u; (present != 0) && (other < LEVELS_TEST_PROBES); other += 1u)
        {
            if (part[other] == MAX_TREE_ABSENT)
            {
                continue;
            }
            const int together = (label[voxel] == label[probe_voxels[other]]);
            passed = (together == (part[one] == part[other])) ? passed : 0;
        }
    }
    return passed;
}

// every pair of levels: C counted directly from the two floods at the lag, against the table's rectangle sums over the
// two components' nodes
static void levels_overlap_agree(LevelsResults *results, unsigned int case_number, const LevelsVolume *earlier,
                                 const LevelsVolume *later, const MaxTreeNodes *earlier_nodes,
                                 const MaxTreeNodes *later_nodes, const MaxTreePairs *pairs, const int *lag)
{
    static unsigned int earlier_label[LEVELS_TEST_VOXELS_MAX];
    static unsigned int later_label[LEVELS_TEST_VOXELS_MAX];
    static unsigned int earlier_node[LEVELS_TEST_VOXELS_MAX];
    static unsigned int later_node[LEVELS_TEST_VOXELS_MAX];
    static unsigned long long direct[LEVELS_TEST_VOXELS_MAX * LEVELS_TEST_VOXELS_MAX];
    static unsigned int asked_earlier[LEVELS_TEST_VOXELS_MAX * LEVELS_TEST_VOXELS_MAX];
    static unsigned int asked_later[LEVELS_TEST_VOXELS_MAX * LEVELS_TEST_VOXELS_MAX];
    static unsigned long long sums[LEVELS_TEST_VOXELS_MAX * LEVELS_TEST_VOXELS_MAX];
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
                if ((z < 0) || (z >= (int)earlier->depth) || (y < 0) || (y >= (int)earlier->height) || (x < 0) ||
                    (x >= (int)earlier->width))
                {
                    continue;
                }
                // the target lies inside the volume: its index is not negative
                const unsigned int target =
                    (unsigned int)((((z * (int)earlier->height) + y) * (int)earlier->width) + x);
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
            const MaxTreeOverlapSumsRequest request = {earlier_nodes, later_nodes, pairs, asked_earlier,
                                                       asked_later,   asked,       sums,  &error};
            int passed = (max_tree_overlap_sums(&request) == (long)asked);
            for (unsigned int query = 0u; (passed != 0) && (query < asked); query += 1u)
            {
                passed = (sums[query] == direct[query]) ? passed : 0;
            }
            levels_check(results, passed, "overlap sums equal the direct count at a pair of levels", case_number,
                         level);
        }
    }
}

static void levels_case(LevelsResults *results, unsigned int case_number, const LevelsVolume *earlier,
                        const LevelsVolume *later, const int *lag, unsigned long long *state)
{
    static unsigned int label[LEVELS_TEST_VOXELS_MAX];
    static unsigned int node_of[LEVELS_TEST_VOXELS_MAX];
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
    const long built =
        max_tree_build(earlier->residual, earlier->depth, earlier->height, earlier->width, &earlier_tree);
    const long later_built = max_tree_build(later->residual, later->depth, later->height, later->width, &later_tree);
    levels_check(results, (built >= 0L) && (later_built >= 0L), "both trees build", case_number, 0u);
    if ((built < 0L) || (later_built < 0L))
    {
        return;
    }
    const MaxTreeNodesRequest earlier_request = {earlier->residual, &earlier_tree, &earlier_nodes, &error};
    const MaxTreeNodesRequest later_request = {later->residual, &later_tree, &later_nodes, &error};
    const long counted = max_tree_nodes(&earlier_request);
    const long later_counted = max_tree_nodes(&later_request);
    levels_check(results, (counted >= 0L) && (later_counted >= 0L), "both trees give their nodes", case_number, 0u);
    if ((counted >= 0L) && (later_counted >= 0L))
    {
        levels_check(results, levels_nodes_valid(earlier, &earlier_nodes) && levels_nodes_valid(later, &later_nodes),
                     "nodes nest in DFS order, rise in level and hold their voxels' ranks", case_number, 0u);
        for (unsigned int level = 1u; level <= earlier->levels; level += 1u)
        {
            const unsigned int marks = levels_flood(earlier, level, label);
            levels_check(results, levels_components_agree(earlier, &earlier_nodes, level, label, marks, node_of),
                         "the component at a level is the flood's", case_number, level);
        }
        for (unsigned int level = 1u; level <= later->levels; level += 1u)
        {
            const unsigned int marks = levels_flood(later, level, label);
            levels_check(results, levels_components_agree(later, &later_nodes, level, label, marks, node_of),
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
        const MaxTreeProbeRequest probe_request = {&earlier_nodes, probe_voxels, LEVELS_TEST_PROBES, sorted, own_level,
                                                   joined,         &error};
        const long probed = max_tree_probe_levels(&probe_request);
        levels_check(results, probed == (long)LEVELS_TEST_PROBES, "the probe levels are read", case_number, 0u);
        for (unsigned int level = 1u; (probed >= 0L) && (level <= earlier->levels); level += 1u)
        {
            levels_flood(earlier, level, label);
            max_tree_probe_partition(sorted, own_level, joined, LEVELS_TEST_PROBES, level, part);
            levels_check(results, levels_probes_agree(earlier, probe_voxels, part, label, level),
                         "the probe partition at a level is the flood's", case_number, level);
        }
        const MaxTreePairsRequest pairs_request = {
            &earlier_nodes, &later_nodes, {lag[0], lag[1], lag[2]}, &pairs, &error};
        const long entries = max_tree_pairs(&pairs_request);
        levels_check(results, entries >= 0L, "the pair table is built", case_number, 0u);
        if (entries >= 0L)
        {
            levels_overlap_agree(results, case_number, earlier, later, &earlier_nodes, &later_nodes, &pairs, lag);
        }
    }
    max_tree_pairs_release(&pairs);
    max_tree_nodes_release(&earlier_nodes);
    max_tree_nodes_release(&later_nodes);
    max_tree_release(&earlier_tree);
    max_tree_release(&later_tree);
}

// requests the module must error, each with a request error from max_tree and nothing written
static void levels_errors(LevelsResults *results, const LevelsVolume *volume)
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
        levels_check(results, 0, "the errors' tree builds", 0u, 0u);
        return;
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    const MaxTreeNodesRequest unerrored = {volume->residual, &tree, &nodes, NULL};
    levels_check(results, max_tree_nodes(&unerrored) == MAX_TREE_ERROR, "a request with no error errors", 0u, 0u);
    const MaxTreeNodesRequest request = {volume->residual, &tree, &nodes, &error};
    levels_check(results, max_tree_nodes(&request) >= 0L, "the errors' nodes are given", 0u, 0u);
    unsigned int probe_voxels[2] = {0u, volume->voxels};
    unsigned int sorted[2];
    unsigned int own_level[2];
    unsigned int joined[2];
    const MaxTreeProbeRequest outside = {&nodes, probe_voxels, 2u, sorted, own_level, joined, &error};
    levels_check(results,
                 (max_tree_probe_levels(&outside) == MAX_TREE_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                     (error.module == ENGINE_MODULE_MAX_TREE),
                 "a probe past the volume errors, a request error from max_tree", 0u, 0u);
    memset(&error, 0, sizeof(error));
    other_nodes = nodes;
    other_nodes.width = nodes.width + 1u;
    const MaxTreePairsRequest mismatched = {&nodes, &other_nodes, {0, 0, 0}, &pairs, &error};
    levels_check(results,
                 (max_tree_pairs(&mismatched) == MAX_TREE_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                     (pairs.count == 0u) && (pairs.earlier == NULL),
                 "two frames of different extents error on the pair table", 0u, 0u);
    memset(&error, 0, sizeof(error));
    const MaxTreePairsRequest same = {&nodes, &nodes, {0, 0, 0}, &pairs, &error};
    const long entries = max_tree_pairs(&same);
    const unsigned int end = nodes.count;
    const unsigned int first = 0u;
    unsigned long long sum = 0ull;
    const MaxTreeOverlapSumsRequest beyond = {&nodes, &nodes, &pairs, &end, &first, 1u, &sum, &error};
    levels_check(results,
                 (entries >= 0L) && (max_tree_overlap_sums(&beyond) == MAX_TREE_ERROR) &&
                     (error.kind == ENGINE_ERROR_REQUEST),
                 "a node past the tree errors on the overlap sums", 0u, 0u);
    max_tree_pairs_release(&pairs);
    max_tree_nodes_release(&nodes);
    max_tree_release(&tree);
}

int main(void)
{
    static LevelsVolume earlier;
    static LevelsVolume later;
    LevelsResults results = {0u, 0u};
    unsigned long long state = 0x243F6A8885A308D3ull;
    unsigned int case_number = 0u;
    // many ties and plateaus, then more levels, then values that cross the limb boundary
    const long long least[3] = {-2ll, -40ll, -9ll};
    const long long maximum[3] = {5ll, 60ll, 9ll};
    const unsigned int cases[3] = {60u, 30u, 20u};
    for (unsigned int kind = 0u; kind < 3u; kind += 1u)
    {
        for (unsigned int drawn = 0u; drawn < cases[kind]; drawn += 1u)
        {
            // each extent is drawn from 1 to 7, and the lag from -1 to 1 on each axis
            const unsigned int depth = 1u + (unsigned int)(levels_draw(&state) % 3ull);
            const unsigned int height = 1u + (unsigned int)(levels_draw(&state) % LEVELS_TEST_EXTENT_MAX);
            const unsigned int width = 1u + (unsigned int)(levels_draw(&state) % LEVELS_TEST_EXTENT_MAX);
            const int lag[3] = {(int)(levels_draw(&state) % 3ull) - 1, (int)(levels_draw(&state) % 3ull) - 1,
                                (int)(levels_draw(&state) % 3ull) - 1};
            levels_fill(&earlier, &state, depth, height, width, least[kind], maximum[kind], kind == 2u);
            levels_fill(&later, &state, depth, height, width, least[kind], maximum[kind], kind == 2u);
            levels_case(&results, case_number, &earlier, &later, lag, &state);
            case_number += 1u;
        }
    }
    levels_fill(&earlier, &state, 3u, 5u, 6u, -2ll, 5ll, 0);
    levels_errors(&results, &earlier);
    printf("  max_tree levels test: %u volumes, %u checks, %u failed\n", case_number, results.checks, results.failed);
    return (results.failed == 0u) ? 0 : 1;
}
