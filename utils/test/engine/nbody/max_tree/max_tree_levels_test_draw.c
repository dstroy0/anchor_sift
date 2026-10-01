// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_levels_test_draw.c: draws, fills, floods and held nodes
#include "max_tree_levels_test_internal.h"

void levels_check(LevelsResults *results, int passed, const char *what, unsigned int volume, unsigned int level)
{
    results->checks += 1u;
    if (passed == 0)
    {
        results->failed += 1u;
        if (results->failed <= 20u)
        {
            printf("  FAIL %s (volume %u, level %u)\n", what, volume, level);
        }
    }
}

unsigned long long levels_draw(unsigned long long *state)
{
    *state += 0x9E3779B97F4A7C15ull;
    unsigned long long mixed = *state;
    mixed = (mixed ^ (mixed >> 30u)) * 0xBF58476D1CE4E5B9ull;
    mixed = (mixed ^ (mixed >> 27u)) * 0x94D049BB133111EBull;
    return mixed ^ (mixed >> 31u);
}

// each value in `ENGINE_RESIDUAL_LIMBS` limbs of two's complement, as the residual lays it out
static void levels_volume_fill(LevelsVolume *volume)
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

void levels_fill(LevelsVolume *volume, unsigned long long *state, unsigned int depth, unsigned int height,
                 unsigned int width, long long least, long long maximum, int wide)
{
    volume->depth = depth;
    volume->height = height;
    volume->width = width;
    volume->voxels = depth * height * width;
    // the span of values is small and positive, and fits the draw's modulus
    const unsigned long long span = (unsigned long long)(maximum - least) + 1ull;
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
    levels_volume_fill(volume);
    levels_rank(volume);
}

// the components of the upper set {rank >= level}, six-connected, numbered from 0; MAX_TREE_ABSENT outside it
unsigned int levels_flood(const LevelsVolume *volume, unsigned int level, unsigned int *label)
{
    unsigned int waiting[LEVELS_TEST_VOXELS_MAX];
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
                if ((near_z < 0) || (near_z >= (int)volume->depth) || (near_y < 0) || (near_y >= (int)volume->height) ||
                    (near_x < 0) || (near_x >= (int)volume->width))
                {
                    continue;
                }
                // the neighbor lies inside the volume: its index is not negative
                const unsigned int near =
                    (unsigned int)((((near_z * (int)volume->height) + near_y) * (int)volume->width) + near_x);
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
int levels_components_agree(const LevelsVolume *volume, const MaxTreeNodes *nodes, unsigned int level,
                            const unsigned int *label, unsigned int marks, unsigned int *node_of)
{
    unsigned int label_of[LEVELS_TEST_VOXELS_MAX];
    for (unsigned int node = 0u; node < nodes->count; node += 1u)
    {
        label_of[node] = MAX_TREE_ABSENT;
    }
    for (unsigned int mark = 0u; mark < marks; mark += 1u)
    {
        node_of[mark] = MAX_TREE_ABSENT;
    }
    int passed = 1;
    for (unsigned int voxel = 0u; voxel < volume->voxels; voxel += 1u)
    {
        const unsigned int own = nodes->own[voxel];
        const unsigned int node = (own == MAX_TREE_ABSENT) ? MAX_TREE_ABSENT : max_tree_node_at(nodes, own, level);
        if (label[voxel] == MAX_TREE_ABSENT)
        {
            passed = (node == MAX_TREE_ABSENT) ? passed : 0;
            continue;
        }
        if (node == MAX_TREE_ABSENT)
        {
            passed = 0;
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
        passed = ((node_of[label[voxel]] == node) && (label_of[node] == label[voxel])) ? passed : 0;
    }
    return passed;
}

// the nodes' own structure: DFS ranges nest, levels rise from parent to child, roots name themselves, and every
// admitted voxel's own node is at its rank and holds its value
int levels_nodes_valid(const LevelsVolume *volume, const MaxTreeNodes *nodes)
{
    int ok = (nodes->levels == volume->levels);
    for (unsigned int node = 0u; node < nodes->count; node += 1u)
    {
        const unsigned int above = nodes->parent[node];
        ok = ((nodes->subtree_end[node] > node) && (nodes->subtree_end[node] <= nodes->count)) ? ok : 0;
        if (above == node)
        {
            ok = (nodes->root[node] == node) ? ok : 0;
            continue;
        }
        ok = ((above < node) && (nodes->level[above] < nodes->level[node]) &&
              (nodes->subtree_end[node] <= nodes->subtree_end[above]) && (nodes->root[node] == nodes->root[above]))
                 ? ok
                 : 0;
    }
    for (unsigned int voxel = 0u; voxel < volume->voxels; voxel += 1u)
    {
        const unsigned int own = nodes->own[voxel];
        if (volume->rank[voxel] == 0u)
        {
            ok = (own == MAX_TREE_ABSENT) ? ok : 0;
            continue;
        }
        ok = ((own != MAX_TREE_ABSENT) && (nodes->level[own] == volume->rank[voxel]) &&
              (volume->value[nodes->voxel[own]] == volume->value[voxel]))
                 ? ok
                 : 0;
    }
    return ok;
}
