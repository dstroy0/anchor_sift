// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the max_tree_levels_test_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef MAX_TREE_LEVELS_TEST_INTERNAL_H
#define MAX_TREE_LEVELS_TEST_INTERNAL_H

// A2 on the host tree, against a flood of each upper level set counted here from the values alone: the nodes and their
// DFS ranges, the component at every level, the probe partition at every level from the k - 1 LCA levels, and the
// overlap at every pair of levels from the one own-node pair table. Host only; no device is touched.
#include "max_tree.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LEVELS_TEST_PROBES 12u

#define LEVELS_TEST_EXTENT_MAX 7u

#define LEVELS_TEST_VOXELS_MAX (LEVELS_TEST_EXTENT_MAX * LEVELS_TEST_EXTENT_MAX * LEVELS_TEST_EXTENT_MAX)

typedef struct
{
    unsigned int checks;
    unsigned int failed;
} LevelsResults;

typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
    long long value[LEVELS_TEST_VOXELS_MAX];
    unsigned int rank[LEVELS_TEST_VOXELS_MAX];
    unsigned int levels;
    unsigned int residual[LEVELS_TEST_VOXELS_MAX * ENGINE_RESIDUAL_LIMBS];
} LevelsVolume;

void levels_check(LevelsResults *results, int passed, const char *what, unsigned int volume, unsigned int level);

unsigned long long levels_draw(unsigned long long *state);

void levels_fill(LevelsVolume *volume, unsigned long long *state, unsigned int depth, unsigned int height,
                 unsigned int width, long long least, long long maximum, int wide);

unsigned int levels_flood(const LevelsVolume *volume, unsigned int level, unsigned int *label);

int levels_components_agree(const LevelsVolume *volume, const MaxTreeNodes *nodes, unsigned int level,
                            const unsigned int *label, unsigned int marks, unsigned int *node_of);

int levels_nodes_valid(const LevelsVolume *volume, const MaxTreeNodes *nodes);

#endif
