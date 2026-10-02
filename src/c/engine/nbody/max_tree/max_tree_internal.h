// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the max_tree_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef MAX_TREE_INTERNAL_H
#define MAX_TREE_INTERNAL_H

#include "../../../types/integers/exact_integer.h"
#include "max_tree.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__cplusplus)
static_assert(ANCHOR_EXACT_LIMBS >= ENGINE_RESIDUAL_LIMBS,
              "the exact type must be at least as wide as the residual it is asked about");
static_assert(ANCHOR_EXACT_LIMBS >= MAX_TREE_KEY_LIMBS,
              "the exact type must be at least as wide as a face's key, the residual and its name");
#else
_Static_assert(ANCHOR_EXACT_LIMBS >= ENGINE_RESIDUAL_LIMBS,
               "the exact type must be at least as wide as the residual it is asked about");
_Static_assert(ANCHOR_EXACT_LIMBS >= MAX_TREE_KEY_LIMBS,
               "the exact type must be at least as wide as a face's key, the residual and its name");
#endif

extern AnchorExactInteger g_asked_left;

extern AnchorExactInteger g_asked_right;

void max_tree_ask_ready(void);

int max_tree_selects(const unsigned int *residual, unsigned int voxel);

int max_tree_before(const unsigned int *residual, unsigned int left, unsigned int right);

int max_tree_same(const unsigned int *residual, unsigned int left, unsigned int right);

unsigned int max_tree_root(unsigned int *zpar, unsigned int from);

long max_tree_build(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                    MaxTree *tree);

long max_tree_build_bound(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                          const unsigned char *bound, MaxTree *tree);

int max_tree_equal(const MaxTree *left, const MaxTree *right);

void max_tree_release(MaxTree *tree);

#define MAX_TREE_HOST_CHECK(condition_, evacaddr_, error_, kind_)                                                      \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_MAX_TREE, (unsigned int)__LINE__,                          \
                       (const void *)(evacaddr_), (error_))

int max_tree_key_compare(const void *left, const void *right);

#endif
