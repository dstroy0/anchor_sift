#ifndef MAX_TREE_H
#define MAX_TREE_H

#include "binomial_basins.h"

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_TREE_REFUSED (-1)

#define MAX_TREE_ABSENT 0xFFFFFFFFu

#define MAX_TREE_KEY_LIMBS (BINOMIAL_BASINS_LIMBS + 1u)

typedef struct
{
    unsigned int voxels;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int admitted;
    unsigned int *parent;
    unsigned int *order;
} MaxTree;

typedef struct
{
    const unsigned int *residual;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    const unsigned int *levels;
    unsigned int level_count;
    unsigned char *bound;
    unsigned int *rounds;
    unsigned int *levels_held;
    unsigned long long *bound_microseconds;
    unsigned long long *proved_microseconds;
} MaxTreeBindRequest;

long max_tree_build(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                    MaxTree *tree);

void max_tree_release(MaxTree *tree);

int max_tree_holds(const unsigned int *residual, const MaxTree *tree, unsigned int levels);

long max_tree_build_bound(const unsigned int *residual, unsigned int depth, unsigned int height,
                          unsigned int width, const unsigned char *bound, MaxTree *tree);

int max_tree_equal(const MaxTree *left, const MaxTree *right);

int max_tree_poc(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                 unsigned char *bound, unsigned int *rounds);

int max_tree_order_agrees(const unsigned int *residual, unsigned int depth, unsigned int height,
                          unsigned int width);

long max_tree_bind(const MaxTreeBindRequest *request);

#ifdef __cplusplus
}
#endif

#endif
