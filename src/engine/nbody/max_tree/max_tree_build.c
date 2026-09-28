// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// max_tree_build.c: the tree built
#include "max_tree_internal.h"

AnchorExactInteger s_asked_left;
AnchorExactInteger s_asked_right;
static unsigned int s_asked_ready = 0u;

static void max_tree_exact_of(const unsigned int *residual, unsigned int voxel, AnchorExactInteger *value)
{
    const unsigned int *const limbs = &residual[(size_t)voxel * ENGINE_RESIDUAL_LIMBS];
    const unsigned int negative = (limbs[ENGINE_RESIDUAL_LIMBS - 1u] >> 31u) & 1u;
    const unsigned int flip = 0u - negative;
    unsigned long long carry = (unsigned long long)negative;
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        const unsigned long long total = (unsigned long long)(limbs[limb] ^ flip) + carry;
        value->limb[limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
        any |= value->limb[limb];
    }
    for (unsigned int limb = ENGINE_RESIDUAL_LIMBS; limb < MAX_TREE_KEY_LIMBS; limb += 1u)
    {
        value->limb[limb] = 0u;
    }
    const int magnitude = (any != 0u) ? 1 : 0;
    value->sign = magnitude * ((negative != 0u) ? -1 : 1);
}

void max_tree_ask_ready(void)
{
    if (s_asked_ready == 0u)
    {
        anchor_exact_zero(&s_asked_left);
        anchor_exact_zero(&s_asked_right);
        s_asked_ready = 1u;
    }
}

int max_tree_selects(const unsigned int *residual, unsigned int voxel)
{
    max_tree_ask_ready();
    max_tree_exact_of(residual, voxel, &s_asked_left);
    return (s_asked_left.sign > 0) ? 1 : 0;
}

int max_tree_before(const unsigned int *residual, unsigned int left, unsigned int right)
{
    max_tree_ask_ready();
    max_tree_exact_of(residual, left, &s_asked_left);
    max_tree_exact_of(residual, right, &s_asked_right);
    const int order = anchor_exact_compare(&s_asked_left, &s_asked_right);
    if (order != 0)
    {
        return (order > 0) ? -1 : 1;
    }
    return (left < right) ? -1 : 1;
}

int max_tree_same(const unsigned int *residual, unsigned int left, unsigned int right)
{
    max_tree_ask_ready();
    max_tree_exact_of(residual, left, &s_asked_left);
    max_tree_exact_of(residual, right, &s_asked_right);
    return anchor_exact_equal(&s_asked_left, &s_asked_right);
}

static const unsigned int *s_ordering_residual = NULL;

static int max_tree_compare(const void *left, const void *right)
{
    return max_tree_before(s_ordering_residual, *(const unsigned int *)left, *(const unsigned int *)right);
}

unsigned int max_tree_root(unsigned int *zpar, unsigned int from)
{
    unsigned int at = from;
    while (zpar[at] != at)
    {
        zpar[at] = zpar[zpar[at]];
        at = zpar[at];
    }
    return at;
}

static long max_tree_grow(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                          const unsigned char *bound, MaxTree *tree)
{
    if ((residual == NULL) || (tree == NULL) || (depth == 0u) || (height == 0u) || (width == 0u))
    {
        return MAX_TREE_ERROR;
    }
    memset(tree, 0, sizeof(*tree));
    const size_t voxels = (size_t)depth * height * width;
    if (voxels > 0xFFFFFFFEu)
    {
        return MAX_TREE_ERROR;
    }
    tree->voxels = (unsigned int)voxels;
    tree->depth = depth;
    tree->height = height;
    tree->width = width;
    tree->parent = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const zpar = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned char *const arrived = (unsigned char *)calloc(voxels, 1u);
    if ((tree->parent == NULL) || (zpar == NULL) || (arrived == NULL))
    {
        free(tree->parent);
        free(zpar);
        free(arrived);
        memset(tree, 0, sizeof(*tree));
        return MAX_TREE_ERROR;
    }
    unsigned int admitted = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        tree->parent[voxel] = MAX_TREE_ABSENT;
        admitted += (unsigned int)max_tree_selects(residual, (unsigned int)voxel);
    }
    tree->admitted = admitted;
    tree->order = (unsigned int *)malloc(((size_t)admitted + 1u) * sizeof(unsigned int));
    if (tree->order == NULL)
    {
        free(tree->parent);
        free(zpar);
        free(arrived);
        memset(tree, 0, sizeof(*tree));
        return MAX_TREE_ERROR;
    }
    unsigned int order_count = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        if (max_tree_selects(residual, (unsigned int)voxel) != 0)
        {
            tree->order[order_count] = (unsigned int)voxel;
            order_count += 1u;
        }
    }
    s_ordering_residual = residual;
    qsort(tree->order, order_count, sizeof(unsigned int), max_tree_compare);
    s_ordering_residual = NULL;

    const size_t plane = (size_t)height * width;
    const unsigned int every = (unsigned int)(bound == NULL);
    for (unsigned int at = 0u; at < order_count; at += 1u)
    {
        const unsigned int voxel = tree->order[at];
        tree->parent[voxel] = voxel;
        zpar[voxel] = voxel;
        arrived[voxel] = 1u;
        const long long z = (long long)(voxel / plane);
        const long long y = (long long)((voxel % plane) / width);
        const long long x = (long long)((voxel % plane) % width);
        const long long steps[6][3] = {
            {-1, 0, 0}, {1, 0, 0}, {0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1},
        };
        for (unsigned int step = 0u; step < 6u; step += 1u)
        {
            const long long near_z = z + steps[step][0];
            const long long near_y = y + steps[step][1];
            const long long near_x = x + steps[step][2];
            if ((near_z < 0) || (near_z >= (long long)depth) || (near_y < 0) || (near_y >= (long long)height) ||
                (near_x < 0) || (near_x >= (long long)width))
            {
                continue;
            }
            const unsigned int near =
                (unsigned int)(((near_z * (long long)height) + near_y) * (long long)width + near_x);
            const unsigned int axis = step / 2u;
            const unsigned int lower = ((step % 2u) != 0u) ? voxel : near;
            const int kept = (every != 0u) || (bound[((size_t)lower * 3u) + axis] != 0u);
            if ((arrived[near] == 0u) || (kept == 0))
            {
                continue;
            }
            const unsigned int root = max_tree_root(zpar, near);
            if (root != voxel)
            {
                tree->parent[root] = voxel;
                zpar[root] = voxel;
            }
        }
    }
    for (unsigned int at = order_count; at > 0u; at -= 1u)
    {
        const unsigned int voxel = tree->order[at - 1u];
        const unsigned int above = tree->parent[voxel];
        if ((above != MAX_TREE_ABSENT) && (above != voxel))
        {
            const unsigned int over = tree->parent[above];
            const int same = (over != MAX_TREE_ABSENT) && (max_tree_same(residual, above, over) != 0);
            tree->parent[voxel] = (same != 0) ? over : above;
        }
    }
    free(zpar);
    free(arrived);
    return (long)admitted;
}

long max_tree_build(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                    MaxTree *tree)
{
    return max_tree_grow(residual, depth, height, width, NULL, tree);
}

long max_tree_build_bound(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                          const unsigned char *bound, MaxTree *tree)
{
    if (bound == NULL)
    {
        return MAX_TREE_ERROR;
    }
    return max_tree_grow(residual, depth, height, width, bound, tree);
}

int max_tree_equal(const MaxTree *left, const MaxTree *right)
{
    if ((left == NULL) || (right == NULL) || (left->parent == NULL) || (right->parent == NULL) ||
        (left->voxels != right->voxels) || (left->admitted != right->admitted))
    {
        return 0;
    }
    return (memcmp(left->parent, right->parent, (size_t)left->voxels * sizeof(unsigned int)) == 0) &&
           (memcmp(left->order, right->order, (size_t)left->admitted * sizeof(unsigned int)) == 0);
}

void max_tree_release(MaxTree *tree)
{
    if (tree == NULL)
    {
        return;
    }
    free(tree->parent);
    free(tree->order);
    memset(tree, 0, sizeof(*tree));
}

static int max_tree_ranges(const unsigned int *residual, unsigned int voxel, unsigned int level)
{
    return (max_tree_before(residual, voxel, level) < 0) || (max_tree_same(residual, voxel, level) != 0);
}

int max_tree_valid(const unsigned int *residual, const MaxTree *tree, unsigned int levels)
{
    if ((residual == NULL) || (tree == NULL) || (tree->parent == NULL) || (tree->admitted == 0u) || (levels == 0u))
    {
        return 0;
    }
    const size_t voxels = tree->voxels;
    const size_t plane = (size_t)tree->height * tree->width;
    unsigned int *const standing = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const flooded = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const waiting = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    int ok = (standing != NULL) && (flooded != NULL) && (waiting != NULL);
    for (unsigned int taken = 0u; (ok != 0) && (taken < levels); taken += 1u)
    {
        const unsigned int level = tree->order[(size_t)(taken + 1u) * tree->admitted / (levels + 1u)];

        for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
        {
            standing[voxel] = MAX_TREE_ABSENT;
        }
        for (unsigned int at = 0u; at < tree->admitted; at += 1u)
        {
            const unsigned int voxel = tree->order[at];
            if (max_tree_ranges(residual, voxel, level) == 0)
            {
                continue;
            }
            unsigned int walk = voxel;
            while ((tree->parent[walk] != walk) && (tree->parent[walk] != MAX_TREE_ABSENT) &&
                   (max_tree_ranges(residual, tree->parent[walk], level) != 0))
            {
                walk = tree->parent[walk];
            }
            standing[voxel] = walk;
        }

        for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
        {
            flooded[voxel] = MAX_TREE_ABSENT;
        }
        unsigned int marks = 0u;
        for (size_t seed = 0u; seed < voxels; seed += 1u)
        {
            if ((flooded[seed] != MAX_TREE_ABSENT) || (max_tree_selects(residual, (unsigned int)seed) == 0) ||
                (max_tree_ranges(residual, (unsigned int)seed, level) == 0))
            {
                continue;
            }
            unsigned int wanted = 0u;
            waiting[wanted] = (unsigned int)seed;
            wanted += 1u;
            flooded[seed] = marks;
            while (wanted != 0u)
            {
                wanted -= 1u;
                const unsigned int voxel = waiting[wanted];
                const long long z = (long long)(voxel / plane);
                const long long y = (long long)((voxel % plane) / tree->width);
                const long long x = (long long)((voxel % plane) % tree->width);
                const long long steps[6][3] = {
                    {-1, 0, 0}, {1, 0, 0}, {0, -1, 0}, {0, 1, 0}, {0, 0, -1}, {0, 0, 1},
                };
                for (unsigned int step = 0u; step < 6u; step += 1u)
                {
                    const long long near_z = z + steps[step][0];
                    const long long near_y = y + steps[step][1];
                    const long long near_x = x + steps[step][2];
                    if ((near_z < 0) || (near_z >= (long long)tree->depth) || (near_y < 0) ||
                        (near_y >= (long long)tree->height) || (near_x < 0) || (near_x >= (long long)tree->width))
                    {
                        continue;
                    }
                    const unsigned int near =
                        (unsigned int)(((near_z * (long long)tree->height) + near_y) * (long long)tree->width + near_x);
                    if ((flooded[near] != MAX_TREE_ABSENT) || (max_tree_selects(residual, near) == 0) ||
                        (max_tree_ranges(residual, near, level) == 0))
                    {
                        continue;
                    }
                    flooded[near] = marks;
                    waiting[wanted] = near;
                    wanted += 1u;
                }
            }
            marks += 1u;
        }

        for (size_t voxel = 0u; (ok != 0) && (voxel < voxels); voxel += 1u)
        {
            if (standing[voxel] == MAX_TREE_ABSENT)
            {
                ok = (flooded[voxel] == MAX_TREE_ABSENT) ? ok : 0;
                continue;
            }
            ok = (flooded[voxel] != MAX_TREE_ABSENT) ? ok : 0;
            ok = ((ok != 0) && (flooded[voxel] == flooded[standing[voxel]])) ? ok : 0;
        }
    }
    free(standing);
    free(flooded);
    free(waiting);
    return ok;
}
