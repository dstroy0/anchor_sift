// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "max_tree.h"
#include "exact_integer.h"

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

static AnchorExactInteger s_asked_left;
static AnchorExactInteger s_asked_right;
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

static void max_tree_ask_ready(void)
{
    if (s_asked_ready == 0u)
    {
        anchor_exact_zero(&s_asked_left);
        anchor_exact_zero(&s_asked_right);
        s_asked_ready = 1u;
    }
}

static int max_tree_admits(const unsigned int *residual, unsigned int voxel)
{
    max_tree_ask_ready();
    max_tree_exact_of(residual, voxel, &s_asked_left);
    return (s_asked_left.sign > 0) ? 1 : 0;
}

static int max_tree_before(const unsigned int *residual, unsigned int left, unsigned int right)
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

static int max_tree_same(const unsigned int *residual, unsigned int left, unsigned int right)
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

static unsigned int max_tree_root(unsigned int *zpar, unsigned int from)
{
    unsigned int at = from;
    while (zpar[at] != at)
    {
        zpar[at] = zpar[zpar[at]];
        at = zpar[at];
    }
    return at;
}

static long max_tree_grow(const unsigned int *residual, unsigned int depth, unsigned int height,
                          unsigned int width, const unsigned char *bound, MaxTree *tree)
{
    if ((residual == NULL) || (tree == NULL) || (depth == 0u) || (height == 0u) || (width == 0u))
    {
        return MAX_TREE_REFUSED;
    }
    memset(tree, 0, sizeof(*tree));
    const size_t voxels = (size_t)depth * height * width;
    if (voxels > 0xFFFFFFFEu)
    {
        return MAX_TREE_REFUSED;
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
        return MAX_TREE_REFUSED;
    }
    unsigned int admitted = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        tree->parent[voxel] = MAX_TREE_ABSENT;
        admitted += (unsigned int)max_tree_admits(residual, (unsigned int)voxel);
    }
    tree->admitted = admitted;
    tree->order = (unsigned int *)malloc(((size_t)admitted + 1u) * sizeof(unsigned int));
    if (tree->order == NULL)
    {
        free(tree->parent);
        free(zpar);
        free(arrived);
        memset(tree, 0, sizeof(*tree));
        return MAX_TREE_REFUSED;
    }
    unsigned int held = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        if (max_tree_admits(residual, (unsigned int)voxel) != 0)
        {
            tree->order[held] = (unsigned int)voxel;
            held += 1u;
        }
    }
    s_ordering_residual = residual;
    qsort(tree->order, held, sizeof(unsigned int), max_tree_compare);
    s_ordering_residual = NULL;

    const size_t plane = (size_t)height * width;
    const unsigned int every = (unsigned int)(bound == NULL);
    for (unsigned int at = 0u; at < held; at += 1u)
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
            if ((near_z < 0) || (near_z >= (long long)depth) || (near_y < 0) || (near_y >= (long long)height)
             || (near_x < 0) || (near_x >= (long long)width))
            {
                continue;
            }
            const unsigned int near = (unsigned int)(((near_z * (long long)height) + near_y)
                                                     * (long long)width + near_x);
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
    for (unsigned int at = held; at > 0u; at -= 1u)
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

long max_tree_build_bound(const unsigned int *residual, unsigned int depth, unsigned int height,
                          unsigned int width, const unsigned char *bound, MaxTree *tree)
{
    if (bound == NULL)
    {
        return MAX_TREE_REFUSED;
    }
    return max_tree_grow(residual, depth, height, width, bound, tree);
}

int max_tree_equal(const MaxTree *left, const MaxTree *right)
{
    if ((left == NULL) || (right == NULL) || (left->parent == NULL) || (right->parent == NULL)
     || (left->voxels != right->voxels) || (left->admitted != right->admitted))
    {
        return 0;
    }
    return (memcmp(left->parent, right->parent, (size_t)left->voxels * sizeof(unsigned int)) == 0)
        && (memcmp(left->order, right->order, (size_t)left->admitted * sizeof(unsigned int)) == 0);
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

static int max_tree_reaches(const unsigned int *residual, unsigned int voxel, unsigned int level)
{
    return (max_tree_before(residual, voxel, level) < 0) || (max_tree_same(residual, voxel, level) != 0);
}

int max_tree_holds(const unsigned int *residual, const MaxTree *tree, unsigned int levels)
{
    if ((residual == NULL) || (tree == NULL) || (tree->parent == NULL) || (tree->admitted == 0u)
     || (levels == 0u))
    {
        return 0;
    }
    const size_t voxels = tree->voxels;
    const size_t plane = (size_t)tree->height * tree->width;
    unsigned int *const standing = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const flooded = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const waiting = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    int good = (standing != NULL) && (flooded != NULL) && (waiting != NULL);
    for (unsigned int taken = 0u; (good != 0) && (taken < levels); taken += 1u)
    {
        const unsigned int level = tree->order[(size_t)(taken + 1u) * tree->admitted / (levels + 1u)];

        for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
        {
            standing[voxel] = MAX_TREE_ABSENT;
        }
        for (unsigned int at = 0u; at < tree->admitted; at += 1u)
        {
            const unsigned int voxel = tree->order[at];
            if (max_tree_reaches(residual, voxel, level) == 0)
            {
                continue;
            }
            unsigned int walk = voxel;
            while ((tree->parent[walk] != walk) && (tree->parent[walk] != MAX_TREE_ABSENT)
                   && (max_tree_reaches(residual, tree->parent[walk], level) != 0))
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
            if ((flooded[seed] != MAX_TREE_ABSENT)
             || (max_tree_admits(residual, (unsigned int)seed) == 0)
             || (max_tree_reaches(residual, (unsigned int)seed, level) == 0))
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
                    if ((near_z < 0) || (near_z >= (long long)tree->depth) || (near_y < 0)
                     || (near_y >= (long long)tree->height) || (near_x < 0)
                     || (near_x >= (long long)tree->width))
                    {
                        continue;
                    }
                    const unsigned int near = (unsigned int)(((near_z * (long long)tree->height) + near_y)
                                                             * (long long)tree->width + near_x);
                    if ((flooded[near] != MAX_TREE_ABSENT)
                     || (max_tree_admits(residual, near) == 0)
                     || (max_tree_reaches(residual, near, level) == 0))
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

        for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
        {
            if (standing[voxel] == MAX_TREE_ABSENT)
            {
                good = (flooded[voxel] == MAX_TREE_ABSENT) ? good : 0;
                continue;
            }
            good = (flooded[voxel] != MAX_TREE_ABSENT) ? good : 0;
            good = ((good != 0) && (flooded[voxel] == flooded[standing[voxel]])) ? good : 0;
        }
    }
    free(standing);
    free(flooded);
    free(waiting);
    return good;
}

static void max_tree_part(const unsigned int *residual, const MaxTree *theirs, const MaxTree *mine)
{
    unsigned int *const place = (unsigned int *)malloc((size_t)theirs->voxels * sizeof(unsigned int));
    if (place == NULL)
    {
        return;
    }
    for (unsigned int at = 0u; at < theirs->admitted; at += 1u)
    {
        place[theirs->order[at]] = at;
    }
    unsigned int differing = 0u;
    unsigned int first = MAX_TREE_ABSENT;
    for (unsigned int at = 0u; at < theirs->admitted; at += 1u)
    {
        const unsigned int voxel = theirs->order[at];
        const unsigned int parts = (unsigned int)(theirs->parent[voxel] != mine->parent[voxel]);
        differing += parts;
        first = ((parts != 0u) && (first == MAX_TREE_ABSENT)) ? voxel : first;
    }
    if (first != MAX_TREE_ABSENT)
    {
        const unsigned int their_parent = theirs->parent[first];
        const unsigned int my_parent = mine->parent[first];
        printf("    part: %u of %u voxels differ; first voxel %u at %u, reference parent %u at %u, asked parent %u "
               "at %u; voxel level equals reference parent %d, asked parent %d; parents equal %d; reference "
               "parent's parent %u, asked parent's parent %u\n",
               differing, theirs->admitted, first, place[first], their_parent, place[their_parent], my_parent,
               place[my_parent], max_tree_same(residual, first, their_parent),
               max_tree_same(residual, first, my_parent), max_tree_same(residual, their_parent, my_parent),
               theirs->parent[their_parent], mine->parent[my_parent]);
    }
    free(place);
}

static void max_tree_imprint(const unsigned int *residual, unsigned int weaker, unsigned int name,
                             unsigned int *key)
{
    const unsigned int *const limbs = &residual[(size_t)weaker * ENGINE_RESIDUAL_LIMBS];
    key[0] = ~name;
    for (unsigned int limb = 0u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
    {
        key[limb + 1u] = limbs[limb];
    }
}

static void max_tree_key_exact(const unsigned int *key, AnchorExactInteger *value)
{
    unsigned int any = 0u;
    for (unsigned int limb = 0u; limb < MAX_TREE_KEY_LIMBS; limb += 1u)
    {
        value->limb[limb] = key[limb];
        any |= key[limb];
    }
    value->sign = (any != 0u) ? 1 : 0;
}

static int max_tree_stronger(const unsigned int *keys, unsigned int face, unsigned int standing)
{
    max_tree_ask_ready();
    max_tree_key_exact(&keys[(size_t)face * MAX_TREE_KEY_LIMBS], &s_asked_left);
    max_tree_key_exact(&keys[(size_t)standing * MAX_TREE_KEY_LIMBS], &s_asked_right);
    return (anchor_exact_compare(&s_asked_left, &s_asked_right) > 0) ? 1 : 0;
}

int max_tree_poc(const unsigned int *residual, unsigned int depth, unsigned int height, unsigned int width,
                 unsigned char *bound, unsigned int *rounds)
{
    MaxTree reference;
    if ((bound == NULL) || (max_tree_build(residual, depth, height, width, &reference) < 0L))
    {
        return 0;
    }
    const size_t voxels = (size_t)depth * height * width;
    const size_t plane = (size_t)height * width;
    memset(bound, 0, voxels * 3u);
    unsigned int *const left = (unsigned int *)malloc(voxels * 3u * sizeof(unsigned int));
    unsigned int *const right = (unsigned int *)malloc(voxels * 3u * sizeof(unsigned int));
    unsigned int *const axes = (unsigned int *)malloc(voxels * 3u * sizeof(unsigned int));
    unsigned int *const keys = (unsigned int *)malloc(voxels * 3u * MAX_TREE_KEY_LIMBS * sizeof(unsigned int));
    unsigned int *const belongs = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned int *const strongest = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    int good = (left != NULL) && (right != NULL) && (axes != NULL) && (keys != NULL) && (belongs != NULL)
            && (strongest != NULL);
    unsigned int faces = 0u;
    for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
    {
        const unsigned int here = (unsigned int)voxel;
        if (max_tree_admits(residual, here) == 0)
        {
            continue;
        }
        const long long z = (long long)(voxel / plane);
        const long long y = (long long)((voxel % plane) / width);
        const long long x = (long long)((voxel % plane) % width);
        const long long steps[3][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
        for (unsigned int step = 0u; step < 3u; step += 1u)
        {
            const long long near_z = z + steps[step][0];
            const long long near_y = y + steps[step][1];
            const long long near_x = x + steps[step][2];
            if ((near_z >= (long long)depth) || (near_y >= (long long)height) || (near_x >= (long long)width))
            {
                continue;
            }
            const unsigned int near = (unsigned int)(((near_z * (long long)height) + near_y)
                                                     * (long long)width + near_x);
            if (max_tree_admits(residual, near) == 0)
            {
                continue;
            }
            left[faces] = here;
            right[faces] = near;
            axes[faces] = step;
            const unsigned int weaker = (max_tree_before(residual, here, near) < 0) ? near : here;
            max_tree_imprint(residual, weaker, (here * 3u) + step, &keys[(size_t)faces * MAX_TREE_KEY_LIMBS]);
            faces += 1u;
        }
    }
    for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
    {
        belongs[voxel] = (unsigned int)voxel;
    }
    unsigned int turns = 0u;
    unsigned int moving = 1u;
    while ((good != 0) && (moving != 0u))
    {
        moving = 0u;
        turns += 1u;
        for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
        {
            strongest[voxel] = MAX_TREE_ABSENT;
        }
        for (unsigned int face = 0u; face < faces; face += 1u)
        {
            const unsigned int one = max_tree_root(belongs, left[face]);
            const unsigned int other = max_tree_root(belongs, right[face]);
            if (one == other)
            {
                continue;
            }
            const unsigned int standing_one = strongest[one];
            const unsigned int standing_other = strongest[other];
            if ((standing_one == MAX_TREE_ABSENT)
             || (max_tree_stronger(keys, face, standing_one) != 0))
            {
                strongest[one] = face;
            }
            if ((standing_other == MAX_TREE_ABSENT)
             || (max_tree_stronger(keys, face, standing_other) != 0))
            {
                strongest[other] = face;
            }
        }
        for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
        {
            if (strongest[voxel] == MAX_TREE_ABSENT)
            {
                continue;
            }
            const unsigned int face = strongest[voxel];
            const unsigned int one = max_tree_root(belongs, left[face]);
            const unsigned int other = max_tree_root(belongs, right[face]);
            if (one == other)
            {
                continue;
            }
            belongs[(one < other) ? other : one] = (one < other) ? one : other;
            bound[((size_t)left[face] * 3u) + axes[face]] = 1u;
            moving += 1u;
        }
    }
    if (rounds != NULL)
    {
        *rounds = turns;
    }

    MaxTree asked;
    memset(&asked, 0, sizeof(asked));
    good = (good != 0) && (max_tree_build_bound(residual, depth, height, width, bound, &asked) >= 0L);
    const int built = good;
    good = (good != 0) && (max_tree_equal(&reference, &asked) != 0);
    if ((built != 0) && (good == 0))
    {
        max_tree_part(residual, &reference, &asked);
    }
    max_tree_release(&asked);
    free(left);
    free(right);
    free(axes);
    free(keys);
    free(belongs);
    free(strongest);
    max_tree_release(&reference);
    return good;
}

#define MAX_TREE_HOST_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_MAX_TREE, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

static int max_tree_key_compare(const void *left, const void *right)
{
    const unsigned long long one = *(const unsigned long long *)left;
    const unsigned long long other = *(const unsigned long long *)right;
    return (one < other) ? -1 : ((one > other) ? 1 : 0);
}

void max_tree_nodes_release(MaxTreeNodes *nodes)
{
    if (nodes == NULL)
    {
        return;
    }
    free(nodes->voxel);
    free(nodes->parent);
    free(nodes->level);
    free(nodes->subtree_end);
    free(nodes->root);
    free(nodes->own);
    memset(nodes, 0, sizeof(*nodes));
}

// the node arrays numbered in DFS order from the canonical voxels: `slot` names each canonical voxel's place among
// them in voxel order, `rank` each admitted voxel's dense rank; returns 0 where a voxel's parent is not canonical
static int max_tree_nodes_lay(const MaxTree *tree, const unsigned int *slot, const unsigned int *rank,
                              unsigned int count, MaxTreeNodes *nodes, EngineError *error)
{
    const size_t voxels = tree->voxels;
    unsigned int *const starts = (unsigned int *)calloc((size_t)count + 2u, sizeof(unsigned int));
    unsigned int *const children = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    unsigned int *const canonical = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    unsigned int *const filled = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    unsigned int *const placed = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    unsigned int *const waiting = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
    int good = MAX_TREE_HOST_HELD((starts != NULL) && (children != NULL) && (canonical != NULL) && (filled != NULL)
                                      && (placed != NULL) && (waiting != NULL),
                                  tree, error, ENGINE_ERROR_RESOURCE);
    for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
    {
        if (slot[voxel] == MAX_TREE_ABSENT)
        {
            continue;
        }
        // a voxel index is below the tree's voxel count, which max_tree_grow holds below 2^32 - 1
        canonical[slot[voxel]] = (unsigned int)voxel;
        const unsigned int above = tree->parent[voxel];
        if (above == voxel)
        {
            continue;
        }
        // a canonical voxel's parent is the canonical voxel of the node below it
        good = MAX_TREE_HOST_HELD(slot[above] != MAX_TREE_ABSENT, &tree->parent[voxel], error, ENGINE_ERROR_LOGIC);
        starts[slot[above] + 1u] += (good != 0) ? 1u : 0u;
    }
    for (unsigned int node = 0u; (good != 0) && (node < count); node += 1u)
    {
        starts[node + 1u] += starts[node];
    }
    for (unsigned int node = 0u; (good != 0) && (node < count); node += 1u)
    {
        filled[node] = starts[node];
    }
    for (unsigned int node = 0u; (good != 0) && (node < count); node += 1u)
    {
        const unsigned int voxel = canonical[node];
        const unsigned int above = tree->parent[voxel];
        if (above != voxel)
        {
            children[filled[slot[above]]] = node;
            filled[slot[above]] += 1u;
        }
    }
    unsigned int waiting_count = 0u;
    for (unsigned int node = count; (good != 0) && (node > 0u); node -= 1u)
    {
        if (tree->parent[canonical[node - 1u]] == canonical[node - 1u])
        {
            waiting[waiting_count] = node - 1u;
            waiting_count += 1u;
        }
    }
    unsigned int next = 0u;
    while ((good != 0) && (waiting_count != 0u))
    {
        waiting_count -= 1u;
        const unsigned int node = waiting[waiting_count];
        placed[node] = next;
        next += 1u;
        for (unsigned int child = starts[node + 1u]; child > starts[node]; child -= 1u)
        {
            waiting[waiting_count] = children[child - 1u];
            waiting_count += 1u;
        }
    }
    good = (good != 0) && MAX_TREE_HOST_HELD(next == count, tree, error, ENGINE_ERROR_LOGIC);
    for (unsigned int node = 0u; (good != 0) && (node < count); node += 1u)
    {
        const unsigned int voxel = canonical[node];
        const unsigned int at = placed[node];
        const unsigned int above = tree->parent[voxel];
        nodes->voxel[at] = voxel;
        nodes->level[at] = rank[voxel];
        nodes->parent[at] = (above == voxel) ? at : placed[slot[above]];
        nodes->subtree_end[at] = 1u;
    }
    for (unsigned int at = count; (good != 0) && (at > 0u); at -= 1u)
    {
        const unsigned int node = at - 1u;
        if (nodes->parent[node] != node)
        {
            nodes->subtree_end[nodes->parent[node]] += nodes->subtree_end[node];
        }
    }
    for (unsigned int node = 0u; (good != 0) && (node < count); node += 1u)
    {
        nodes->subtree_end[node] += node;
        nodes->root[node] = (nodes->parent[node] == node) ? node : nodes->root[nodes->parent[node]];
    }
    for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
    {
        const unsigned int above = tree->parent[voxel];
        if (above == MAX_TREE_ABSENT)
        {
            nodes->own[voxel] = MAX_TREE_ABSENT;
            continue;
        }
        const unsigned int held = (slot[voxel] != MAX_TREE_ABSENT) ? slot[voxel] : slot[above];
        // an admitted voxel that is not canonical points at its node's canonical voxel
        good = MAX_TREE_HOST_HELD(held != MAX_TREE_ABSENT, &tree->parent[voxel], error, ENGINE_ERROR_LOGIC);
        nodes->own[voxel] = (good != 0) ? placed[held] : MAX_TREE_ABSENT;
    }
    free(starts);
    free(children);
    free(canonical);
    free(filled);
    free(placed);
    free(waiting);
    return good;
}

long max_tree_nodes(const MaxTreeNodesRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    if (!MAX_TREE_HOST_HELD((request->residual != NULL) && (request->tree != NULL) && (request->nodes != NULL)
                                && (request->tree->parent != NULL) && (request->tree->order != NULL),
                            request, error, ENGINE_ERROR_REQUEST))
    {
        return MAX_TREE_REFUSED;
    }
    const unsigned int *const residual = request->residual;
    const MaxTree *const tree = request->tree;
    MaxTreeNodes *const nodes = request->nodes;
    memset(nodes, 0, sizeof(*nodes));
    const size_t voxels = tree->voxels;
    const unsigned int admitted = tree->admitted;
    unsigned int *const rank = (unsigned int *)malloc((voxels + 1u) * sizeof(unsigned int));
    unsigned int *const slot = (unsigned int *)malloc((voxels + 1u) * sizeof(unsigned int));
    int good = MAX_TREE_HOST_HELD((rank != NULL) && (slot != NULL), request, error, ENGINE_ERROR_RESOURCE);
    unsigned int levels = 0u;
    for (unsigned int at = admitted; (good != 0) && (at > 0u); at -= 1u)
    {
        const unsigned int voxel = tree->order[at - 1u];
        levels += ((at == admitted) || (max_tree_same(residual, voxel, tree->order[at]) == 0)) ? 1u : 0u;
        rank[voxel] = levels;
    }
    unsigned int count = 0u;
    for (size_t voxel = 0u; (good != 0) && (voxel < voxels); voxel += 1u)
    {
        const unsigned int above = tree->parent[voxel];
        // a voxel index is below the tree's voxel count, which max_tree_grow holds below 2^32 - 1
        const unsigned int here = (unsigned int)voxel;
        const int canonical = (above != MAX_TREE_ABSENT)
                           && ((above == here) || (max_tree_same(residual, here, above) == 0));
        slot[voxel] = (canonical != 0) ? count : MAX_TREE_ABSENT;
        count += (canonical != 0) ? 1u : 0u;
    }
    if (good != 0)
    {
        nodes->voxel = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
        nodes->parent = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
        nodes->level = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
        nodes->subtree_end = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
        nodes->root = (unsigned int *)malloc(((size_t)count + 1u) * sizeof(unsigned int));
        nodes->own = (unsigned int *)malloc((voxels + 1u) * sizeof(unsigned int));
        good = MAX_TREE_HOST_HELD((nodes->voxel != NULL) && (nodes->parent != NULL) && (nodes->level != NULL)
                                      && (nodes->subtree_end != NULL) && (nodes->root != NULL)
                                      && (nodes->own != NULL),
                                  request, error, ENGINE_ERROR_RESOURCE);
    }
    good = (good != 0) && max_tree_nodes_lay(tree, slot, rank, count, nodes, error);
    free(rank);
    free(slot);
    if (good == 0)
    {
        max_tree_nodes_release(nodes);
        return MAX_TREE_REFUSED;
    }
    nodes->count = count;
    nodes->levels = levels;
    nodes->voxels = tree->voxels;
    nodes->depth = tree->depth;
    nodes->height = tree->height;
    nodes->width = tree->width;
    return (long)count;
}

unsigned int max_tree_node_at(const MaxTreeNodes *nodes, unsigned int node, unsigned int level)
{
    if ((nodes == NULL) || (node >= nodes->count) || (nodes->level[node] < level))
    {
        return MAX_TREE_ABSENT;
    }
    unsigned int at = node;
    while ((nodes->parent[at] != at) && (nodes->level[nodes->parent[at]] >= level))
    {
        at = nodes->parent[at];
    }
    return at;
}

long max_tree_probe_levels(const MaxTreeProbeRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    const MaxTreeNodes *const nodes = request->nodes;
    const unsigned int probes = request->probe_count;
    if (!MAX_TREE_HOST_HELD((nodes != NULL) && (nodes->own != NULL)
                                && ((probes == 0u) || ((request->probe_voxels != NULL) && (request->sorted != NULL)
                                                       && (request->own_level != NULL) && (request->joined != NULL))),
                            request, error, ENGINE_ERROR_REQUEST))
    {
        return MAX_TREE_REFUSED;
    }
    for (unsigned int probe = 0u; probe < probes; probe += 1u)
    {
        if (!MAX_TREE_HOST_HELD(request->probe_voxels[probe] < nodes->voxels, &request->probe_voxels[probe], error,
                                ENGINE_ERROR_REQUEST))
        {
            return MAX_TREE_REFUSED;
        }
    }
    if (probes == 0u)
    {
        return 0L;
    }
    unsigned long long *const keys = (unsigned long long *)malloc((size_t)probes * sizeof(unsigned long long));
    if (!MAX_TREE_HOST_HELD(keys != NULL, request, error, ENGINE_ERROR_RESOURCE))
    {
        return MAX_TREE_REFUSED;
    }
    for (unsigned int probe = 0u; probe < probes; probe += 1u)
    {
        const unsigned int own = nodes->own[request->probe_voxels[probe]];
        request->own_level[probe] = (own == MAX_TREE_ABSENT) ? 0u : nodes->level[own];
        // MAX_TREE_ABSENT in the high word sorts a probe that is not admitted after every node
        keys[probe] = ((unsigned long long)own << 32u) | probe;
    }
    qsort(keys, probes, sizeof(unsigned long long), max_tree_key_compare);
    for (unsigned int at = 0u; at < probes; at += 1u)
    {
        // the low word of a key is the probe's index
        request->sorted[at] = (unsigned int)(keys[at] & 0xFFFFFFFFull);
    }
    for (unsigned int at = 0u; (at + 1u) < probes; at += 1u)
    {
        const unsigned int one = nodes->own[request->probe_voxels[request->sorted[at]]];
        const unsigned int other = nodes->own[request->probe_voxels[request->sorted[at + 1u]]];
        unsigned int joined = 0u;
        if ((one != MAX_TREE_ABSENT) && (other != MAX_TREE_ABSENT) && (one == other))
        {
            joined = nodes->level[one];
        }
        else if ((one != MAX_TREE_ABSENT) && (other != MAX_TREE_ABSENT) && (nodes->root[one] == nodes->root[other]))
        {
            // every node in (one, other] lies under the LCA, and the LCA's child toward other is one of them
            unsigned int lowest = nodes->level[nodes->parent[one + 1u]];
            for (unsigned int node = one + 2u; node <= other; node += 1u)
            {
                const unsigned int above = nodes->level[nodes->parent[node]];
                lowest = (above < lowest) ? above : lowest;
            }
            joined = lowest;
        }
        request->joined[at] = joined;
    }
    free(keys);
    return (long)probes;
}

unsigned int max_tree_probe_partition(const unsigned int *sorted, const unsigned int *own_level,
                                      const unsigned int *joined, unsigned int probe_count, unsigned int level,
                                      unsigned int *part)
{
    if ((sorted == NULL) || (own_level == NULL) || (part == NULL) || ((probe_count > 1u) && (joined == NULL)))
    {
        return 0u;
    }
    unsigned int parts = 0u;
    int open = 0;
    for (unsigned int at = 0u; at < probe_count; at += 1u)
    {
        const unsigned int probe = sorted[at];
        if ((at > 0u) && (joined[at - 1u] < level))
        {
            open = 0;
        }
        if ((own_level[probe] == 0u) || (own_level[probe] < level))
        {
            part[probe] = MAX_TREE_ABSENT;
            open = 0;
            continue;
        }
        if (open == 0)
        {
            open = 1;
            parts += 1u;
        }
        part[probe] = parts - 1u;
    }
    return parts;
}

void max_tree_pairs_release(MaxTreePairs *pairs)
{
    if (pairs == NULL)
    {
        return;
    }
    free(pairs->earlier);
    free(pairs->later);
    free(pairs->voxels);
    memset(pairs, 0, sizeof(*pairs));
}

long max_tree_pairs(const MaxTreePairsRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    const MaxTreeNodes *const earlier = request->earlier;
    const MaxTreeNodes *const later = request->later;
    MaxTreePairs *const pairs = request->pairs;
    if (!MAX_TREE_HOST_HELD((earlier != NULL) && (later != NULL) && (pairs != NULL) && (earlier->own != NULL)
                                && (later->own != NULL),
                            request, error, ENGINE_ERROR_REQUEST)
     || !MAX_TREE_HOST_HELD((earlier->depth == later->depth) && (earlier->height == later->height)
                                && (earlier->width == later->width) && (earlier->voxels == later->voxels),
                            later, error, ENGINE_ERROR_REQUEST))
    {
        return MAX_TREE_REFUSED;
    }
    memset(pairs, 0, sizeof(*pairs));
    const size_t voxels = earlier->voxels;
    const size_t plane = (size_t)earlier->height * earlier->width;
    unsigned long long *const keys = (unsigned long long *)malloc((voxels + 1u) * sizeof(unsigned long long));
    if (!MAX_TREE_HOST_HELD(keys != NULL, request, error, ENGINE_ERROR_RESOURCE))
    {
        return MAX_TREE_REFUSED;
    }
    size_t found = 0u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const unsigned int from = earlier->own[voxel];
        if (from == MAX_TREE_ABSENT)
        {
            continue;
        }
        // each coordinate is below its extent, far under 2^63, and the lag is an int
        const long long z = (long long)(voxel / plane) + request->lag[0];
        const long long y = (long long)((voxel % plane) / earlier->width) + request->lag[1];
        const long long x = (long long)((voxel % plane) % earlier->width) + request->lag[2];
        if ((z < 0) || (z >= (long long)earlier->depth) || (y < 0) || (y >= (long long)earlier->height) || (x < 0)
         || (x >= (long long)earlier->width))
        {
            continue;
        }
        // the target lies inside the extent: its index is below the voxel count
        const size_t target = (size_t)((((z * (long long)earlier->height) + y) * (long long)earlier->width) + x);
        const unsigned int to = later->own[target];
        if (to == MAX_TREE_ABSENT)
        {
            continue;
        }
        keys[found] = ((unsigned long long)from << 32u) | to;
        found += 1u;
    }
    qsort(keys, found, sizeof(unsigned long long), max_tree_key_compare);
    unsigned int distinct = 0u;
    for (size_t at = 0u; at < found; at += 1u)
    {
        distinct += ((at == 0u) || (keys[at] != keys[at - 1u])) ? 1u : 0u;
    }
    pairs->earlier = (unsigned int *)malloc(((size_t)distinct + 1u) * sizeof(unsigned int));
    pairs->later = (unsigned int *)malloc(((size_t)distinct + 1u) * sizeof(unsigned int));
    pairs->voxels = (unsigned long long *)malloc(((size_t)distinct + 1u) * sizeof(unsigned long long));
    if (!MAX_TREE_HOST_HELD((pairs->earlier != NULL) && (pairs->later != NULL) && (pairs->voxels != NULL), request,
                            error, ENGINE_ERROR_RESOURCE))
    {
        free(keys);
        max_tree_pairs_release(pairs);
        return MAX_TREE_REFUSED;
    }
    unsigned int entry = 0u;
    for (size_t at = 0u; at < found; at += 1u)
    {
        if ((at != 0u) && (keys[at] == keys[at - 1u]))
        {
            pairs->voxels[entry - 1u] += 1ull;
            continue;
        }
        // the high word is the earlier node and the low word the later one
        pairs->earlier[entry] = (unsigned int)(keys[at] >> 32u);
        pairs->later[entry] = (unsigned int)(keys[at] & 0xFFFFFFFFull);
        pairs->voxels[entry] = 1ull;
        entry += 1u;
    }
    free(keys);
    pairs->count = distinct;
    return (long)distinct;
}

static void max_tree_fenwick_add(unsigned long long *fenwick, unsigned int size, unsigned int at,
                                 unsigned long long amount)
{
    for (unsigned int slot = at + 1u; slot <= size; slot += slot & (0u - slot))
    {
        fenwick[slot] += amount;
    }
}

static unsigned long long max_tree_fenwick_below(const unsigned long long *fenwick, unsigned int end)
{
    unsigned long long total = 0ull;
    for (unsigned int slot = end; slot > 0u; slot -= slot & (0u - slot))
    {
        total += fenwick[slot];
    }
    return total;
}

long max_tree_overlap_sums(const MaxTreeOverlapSumsRequest *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return MAX_TREE_REFUSED;
    }
    EngineError *const error = request->error;
    const MaxTreeNodes *const earlier = request->earlier;
    const MaxTreeNodes *const later = request->later;
    const MaxTreePairs *const pairs = request->pairs;
    const unsigned int asked = request->asked;
    if (!MAX_TREE_HOST_HELD((earlier != NULL) && (later != NULL) && (pairs != NULL) && (asked <= 0x7FFFFFFFu)
                                && ((asked == 0u) || ((request->earlier_nodes != NULL) && (request->later_nodes != NULL)
                                                      && (request->sums != NULL))),
                            request, error, ENGINE_ERROR_REQUEST))
    {
        return MAX_TREE_REFUSED;
    }
    for (unsigned int entry = 0u; entry < pairs->count; entry += 1u)
    {
        // the sweep reads the table in the order max_tree_pairs lays it, sorted by the earlier node
        if (!MAX_TREE_HOST_HELD((pairs->earlier[entry] < earlier->count) && (pairs->later[entry] < later->count)
                                    && ((entry == 0u) || (pairs->earlier[entry - 1u] <= pairs->earlier[entry])),
                                &pairs->earlier[entry], error, ENGINE_ERROR_REQUEST))
        {
            return MAX_TREE_REFUSED;
        }
    }
    for (unsigned int query = 0u; query < asked; query += 1u)
    {
        if (!MAX_TREE_HOST_HELD((request->earlier_nodes[query] < earlier->count)
                                    && (request->later_nodes[query] < later->count),
                                &request->earlier_nodes[query], error, ENGINE_ERROR_REQUEST))
        {
            return MAX_TREE_REFUSED;
        }
    }
    if (asked == 0u)
    {
        return 0L;
    }
    const size_t events = 2u * (size_t)asked;
    unsigned long long *const keys = (unsigned long long *)malloc(events * sizeof(unsigned long long));
    unsigned long long *const below = (unsigned long long *)malloc((size_t)asked * sizeof(unsigned long long));
    unsigned long long *const fenwick = (unsigned long long *)calloc((size_t)later->count + 1u,
                                                                     sizeof(unsigned long long));
    if (!MAX_TREE_HOST_HELD((keys != NULL) && (below != NULL) && (fenwick != NULL), request, error,
                            ENGINE_ERROR_RESOURCE))
    {
        free(keys);
        free(below);
        free(fenwick);
        return MAX_TREE_REFUSED;
    }
    for (unsigned int query = 0u; query < asked; query += 1u)
    {
        const unsigned int node = request->earlier_nodes[query];
        // an event's low word is twice the query, plus 1 for the range's lower edge; the high word is the row edge
        keys[2u * (size_t)query] = ((unsigned long long)earlier->subtree_end[node] << 32u) | (2ull * query);
        keys[(2u * (size_t)query) + 1u] = ((unsigned long long)node << 32u) | ((2ull * query) + 1ull);
    }
    qsort(keys, events, sizeof(unsigned long long), max_tree_key_compare);
    unsigned int entry = 0u;
    for (size_t at = 0u; at < events; at += 1u)
    {
        // the high word is a node index or a subtree's end, each below 2^32
        const unsigned int edge = (unsigned int)(keys[at] >> 32u);
        while ((entry < pairs->count) && (pairs->earlier[entry] < edge))
        {
            max_tree_fenwick_add(fenwick, later->count, pairs->later[entry], pairs->voxels[entry]);
            entry += 1u;
        }
        // the low word is twice the query plus the edge, below 2^32
        const unsigned int event = (unsigned int)(keys[at] & 0xFFFFFFFFull);
        const unsigned int query = event / 2u;
        const unsigned int node = request->later_nodes[query];
        const unsigned long long held = max_tree_fenwick_below(fenwick, later->subtree_end[node])
                                      - max_tree_fenwick_below(fenwick, node);
        if ((event % 2u) == 0u)
        {
            request->sums[query] = held;
        }
        else
        {
            below[query] = held;
        }
    }
    int good = 1;
    for (unsigned int query = 0u; (good != 0) && (query < asked); query += 1u)
    {
        // the rows below a subtree's start are a subset of the rows below its end
        good = MAX_TREE_HOST_HELD(request->sums[query] >= below[query], &request->sums[query], error,
                                  ENGINE_ERROR_LOGIC);
        request->sums[query] -= (good != 0) ? below[query] : 0ull;
    }
    free(keys);
    free(below);
    free(fenwick);
    return (good != 0) ? (long)asked : MAX_TREE_REFUSED;
}
