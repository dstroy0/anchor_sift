/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file binomial_basins.c
 * @brief The portable reference for binomial_basins.h: C11, single threaded, integers only.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @note Written for reading, not for speed. Every loop visits voxels in raster order and every value
 *       is an unsigned integer, so the answer is the definition. binomial_basins.cu must equal it.
 */

#include "binomial_basins.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(unsigned int) == 4u, "binomial_basins: unsigned int must be 32 bits, a limb");
_Static_assert(sizeof(unsigned long long) == 8u,
               "binomial_basins: unsigned long long must be 64 bits, a limb product and its carry");

/** @brief Extents, with the voxel count they multiply to. */
typedef struct
{
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int voxels;
} HostGeometry;

/**
 * @brief The in-line position a half-sample reflected position reads from.
 *
 * @param[in] position Position along the line, possibly outside it.
 * @param[in] length   Line length, at least one.
 * @return             The position inside the line whose value stands there.
 */
static unsigned int host_reflect(long long position, long long length)
{
    const long long period = 2ll * length;
    long long folded = position % period;
    if (folded < 0ll)
    {
        folded += period;
    }
    if (folded >= length)
    {
        folded = period - 1ll - folded;
    }
    // Narrowing is safe: folded lies in [0, length) and length is an extent held in unsigned int.
    return (unsigned int)folded;
}

/**
 * @brief Pascal's row of an order, by integer recurrence.
 *
 * @param[in]  order   Row, at most BINOMIAL_BASINS_PASS_ORDER.
 * @param[out] weights order + 1 weights [BORROWS].
 */
static void host_binomial_row(unsigned int order, unsigned int *weights)
{
    weights[0] = 1u;
    for (unsigned int row = 1u; row <= order; row += 1u)
    {
        weights[row] = 1u;
        for (unsigned int at = row - 1u; at > 0u; at -= 1u)
        {
            weights[at] += weights[at - 1u];
        }
    }
}

/**
 * @brief Limbs needed to hold a non-negative value below 2^bits.
 *
 * @param[in] bits Bits.
 * @return         Limbs, at most BINOMIAL_BASINS_LIMBS for every width the entry admits.
 */
static unsigned int host_limbs(unsigned int bits)
{
    return (bits + 31u) / 32u;
}

/**
 * @brief One binomial pass of an even order along one axis.
 *
 * @param[in]  source      Limbs read [BORROWS].
 * @param[out] destination Limbs written [BORROWS].
 * @param[in]  weights     Pascal's row of the order [BORROWS].
 * @param[in]  order       Even order, at most BINOMIAL_BASINS_PASS_ORDER.
 * @param[in]  axis        0 for z, 1 for y, 2 for x.
 * @param[in]  limbs_in    Limbs that can be nonzero in the source.
 * @param[in]  geometry    Extents.
 * @note The accumulator is safe: 2^16 weight times a limb below 2^32 stays below 2^48, and the carry
 *       added during normalisation stays below 2^32.
 */
static void host_pass(const unsigned int *source, unsigned int *destination, const unsigned int *weights,
                      unsigned int order, unsigned int axis, unsigned int limbs_in, HostGeometry geometry)
{
    const unsigned int plane = geometry.height * geometry.width;
    for (unsigned int voxel = 0u; voxel < geometry.voxels; voxel += 1u)
    {
        const unsigned int column = voxel % geometry.width;
        const unsigned int row = (voxel / geometry.width) % geometry.height;
        const unsigned int slice = voxel / plane;
        unsigned int along = column;
        unsigned int length = geometry.width;
        unsigned int stride = 1u;
        if (axis == 0u)
        {
            along = slice;
            length = geometry.depth;
            stride = plane;
        }
        else if (axis == 1u)
        {
            along = row;
            length = geometry.height;
            stride = geometry.width;
        }
        const unsigned int line_start = voxel - (along * stride);

        unsigned long long accumulator[BINOMIAL_BASINS_LIMBS] = {0ull};
        for (unsigned int tap = 0u; tap <= order; tap += 1u)
        {
            // Signed, because a tap before the line's start is reflected, not indexed.
            const long long position = (long long)along + (long long)tap - (long long)(order / 2u);
            const unsigned int read = line_start + (host_reflect(position, (long long)length) * stride);
            for (unsigned int limb = 0u; limb < limbs_in; limb += 1u)
            {
                // Widening both factors to unsigned long long is exact.
                accumulator[limb] += (unsigned long long)weights[tap]
                                   * (unsigned long long)source[(read * BINOMIAL_BASINS_LIMBS) + limb];
            }
        }
        unsigned long long carry = 0ull;
        for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
        {
            const unsigned long long total = accumulator[limb] + carry;
            // Narrowing to a limb keeps the low 32 bits; the high bits are carried, not lost.
            destination[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
    }
}

/**
 * @brief Applies one separable binomial smoothing, z then y then x, in passes of at most order 16.
 *
 * @param[in,out] current  Limbs smoothed; on return, the smoothed volume [BORROWS].
 * @param[in,out] spare    A second volume of limbs the passes alternate with [BORROWS].
 * @param[in]     orders   Order per axis, each even.
 * @param[in,out] bits     Bits the values fit, updated by each pass [BORROWS].
 * @param[in]     geometry Extents.
 */
static void host_smooth(unsigned int **current, unsigned int **spare, const unsigned int *orders,
                        unsigned int *bits, HostGeometry geometry)
{
    unsigned int weights[BINOMIAL_BASINS_PASS_ORDER + 1u];
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        unsigned int remaining = orders[axis];
        while (remaining > 0u)
        {
            const unsigned int order = (remaining > BINOMIAL_BASINS_PASS_ORDER)
                                     ? BINOMIAL_BASINS_PASS_ORDER
                                     : remaining;
            host_binomial_row(order, weights);
            host_pass(*current, *spare, weights, order, axis, host_limbs(*bits), geometry);
            unsigned int *const swapped = *current;
            *current = *spare;
            *spare = swapped;
            *bits += order;
            remaining -= order;
        }
    }
}

/**
 * @brief Orders two residual values, sign included.
 *
 * @param[in] left  Limbs of one value [BORROWS].
 * @param[in] right Limbs of the other [BORROWS].
 * @return          -1, 0 or 1.
 * @note Flipping the top limb's sign bit turns two's complement order into unsigned order, so the
 *       comparison never converts a limb to a signed type.
 */
static int host_compare(const unsigned int *left, const unsigned int *right)
{
    const unsigned int top = BINOMIAL_BASINS_LIMBS - 1u;
    const unsigned int left_top = left[top] ^ 0x80000000u;
    const unsigned int right_top = right[top] ^ 0x80000000u;
    if (left_top != right_top)
    {
        return (left_top < right_top) ? -1 : 1;
    }
    for (unsigned int limb = top; limb > 0u; limb -= 1u)
    {
        if (left[limb - 1u] != right[limb - 1u])
        {
            return (left[limb - 1u] < right[limb - 1u]) ? -1 : 1;
        }
    }
    return 0;
}

/**
 * @brief Whether a residual value is above zero.
 *
 * @param[in] value Limbs [BORROWS].
 * @return          1 where positive, 0 otherwise.
 */
static int host_positive(const unsigned int *value)
{
    if ((value[BINOMIAL_BASINS_LIMBS - 1u] & 0x80000000u) != 0u)
    {
        return 0;
    }
    for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
    {
        if (value[limb] != 0u)
        {
            return 1;
        }
    }
    return 0;
}

/**
 * @brief Orders two adjacency pairs for qsort, lower peak first then higher.
 *
 * @param[in] left  One pair [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          Negative, zero or positive.
 */
static int host_pair_order(const void *left, const void *right)
{
    const unsigned int *const one = (const unsigned int *)left;
    const unsigned int *const other = (const unsigned int *)right;
    if (one[0] != other[0])
    {
        return (one[0] < other[0]) ? -1 : 1;
    }
    if (one[1] != other[1])
    {
        return (one[1] < other[1]) ? -1 : 1;
    }
    return 0;
}

/**
 * @brief Appends a pair, lower peak first, growing the buffer when it is full.
 *
 * @param[in,out] pairs    The buffer, reallocated as it grows [BORROWS].
 * @param[in,out] capacity Pairs the buffer holds [BORROWS].
 * @param[in,out] total    Pairs held [BORROWS].
 * @param[in]     here     One peak.
 * @param[in]     there    The other peak.
 * @return                 1 on success, 0 where memory ran out.
 */
static int host_push_pair(unsigned int **pairs, size_t *capacity, size_t *total, unsigned int here,
                          unsigned int there)
{
    if (*total == *capacity)
    {
        const size_t grown_capacity = *capacity * 2u;
        unsigned int *const grown = (unsigned int *)realloc(*pairs, grown_capacity * 2u * sizeof(unsigned int));
        if (grown == NULL)
        {
            return 0;
        }
        *pairs = grown;
        *capacity = grown_capacity;
    }
    (*pairs)[*total * 2u] = (here < there) ? here : there;
    (*pairs)[(*total * 2u) + 1u] = (here < there) ? there : here;
    *total += 1u;
    return 1;
}

/**
 * @brief Sorts pairs and keeps each once, in place.
 *
 * @param[in,out] pairs The pairs [BORROWS].
 * @param[in]     total Pairs held.
 * @return              Unique pairs, which now lead the buffer.
 */
static size_t host_unique_pairs(unsigned int *pairs, size_t total)
{
    size_t unique_total = 0u;
    if (total == 0u)
    {
        return 0u;
    }
    qsort(pairs, total, 2u * sizeof(unsigned int), host_pair_order);
    for (size_t pair = 0u; pair < total; pair += 1u)
    {
        if ((unique_total == 0u) || (host_pair_order(&pairs[pair * 2u], &pairs[(unique_total - 1u) * 2u]) != 0))
        {
            pairs[unique_total * 2u] = pairs[pair * 2u];
            pairs[(unique_total * 2u) + 1u] = pairs[(pair * 2u) + 1u];
            unique_total += 1u;
        }
    }
    return unique_total;
}

long binomial_basins_host(const BinomialBasinsRequest *args)
{
    if ((args == NULL) || (args->volume == NULL) || (args->adjacency_count == NULL) || (args->joined_count == NULL)
     || (args->depth == 0u) || (args->height == 0u) || (args->width == 0u)
     || (args->room > BINOMIAL_BASINS_ROOM_LIMIT) || (args->adjacency_room > BINOMIAL_BASINS_ROOM_LIMIT)
     || (args->joined_room > BINOMIAL_BASINS_ROOM_LIMIT)
     || ((args->room != 0u) && ((args->peak_indices == NULL) || (args->sizes == NULL)
                                || (args->sums == NULL) || (args->peak_limbs == NULL)))
     || ((args->adjacency_room != 0u) && (args->adjacency == NULL))
     || ((args->joined_room != 0u) && (args->joined == NULL)))
    {
        return BINOMIAL_BASINS_REFUSED;
    }
    unsigned long long total_bits = 16ull + 1ull;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        if (((args->smooth_orders[axis] % 2u) != 0u) || ((args->background_orders[axis] % 2u) != 0u))
        {
            return BINOMIAL_BASINS_REFUSED;
        }
        total_bits += (unsigned long long)args->smooth_orders[axis]
                    + (unsigned long long)args->background_orders[axis];
    }
    // Widening each extent to unsigned long long is exact; the plane is checked before the third
    // multiply so neither product wraps.
    const unsigned long long plane_count = (unsigned long long)args->height * (unsigned long long)args->width;
    if ((total_bits > (32ull * BINOMIAL_BASINS_LIMBS)) || (plane_count > 0xFFFFFFFFull))
    {
        return BINOMIAL_BASINS_REFUSED;
    }
    const unsigned long long voxel_count = plane_count * (unsigned long long)args->depth;
    if (voxel_count > (0xFFFFFFFFull / BINOMIAL_BASINS_LIMBS))
    {
        return BINOMIAL_BASINS_REFUSED;
    }

    HostGeometry geometry;
    geometry.depth = args->depth;
    geometry.height = args->height;
    geometry.width = args->width;
    // Narrowing is safe: voxel_count was just bounded well below 2^32.
    geometry.voxels = (unsigned int)voxel_count;
    const size_t voxels = (size_t)geometry.voxels;
    const size_t limb_bytes = voxels * BINOMIAL_BASINS_LIMBS * sizeof(unsigned int);

    unsigned int *first = (unsigned int *)calloc(voxels * BINOMIAL_BASINS_LIMBS, sizeof(unsigned int));
    unsigned int *second = (unsigned int *)calloc(voxels * BINOMIAL_BASINS_LIMBS, sizeof(unsigned int));
    unsigned int *smoothed = (unsigned int *)malloc(limb_bytes);
    unsigned int *successor = (unsigned int *)malloc(voxels * sizeof(unsigned int));
    unsigned char *positive = (unsigned char *)malloc(voxels);
    unsigned int *sizes = (unsigned int *)calloc(voxels, sizeof(unsigned int));
    unsigned long long *sums = (unsigned long long *)calloc(voxels * 3u, sizeof(unsigned long long));
    long answer = BINOMIAL_BASINS_REFUSED;
    if ((first == NULL) || (second == NULL) || (smoothed == NULL) || (successor == NULL)
     || (positive == NULL) || (sizes == NULL) || (sums == NULL))
    {
        free(first);
        free(second);
        free(smoothed);
        free(successor);
        free(positive);
        free(sizes);
        free(sums);
        return answer;
    }

    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        first[voxel * BINOMIAL_BASINS_LIMBS] = (unsigned int)args->volume[voxel];
    }
    unsigned int *current = first;
    unsigned int *spare = second;
    unsigned int bits = 16u;
    host_smooth(&current, &spare, args->smooth_orders, &bits, geometry);
    memcpy(smoothed, current, limb_bytes);
    host_smooth(&current, &spare, args->background_orders, &bits, geometry);

    // residual = smoothed * 2^gain - background, two's complement across every limb, into spare.
    unsigned int gain = 0u;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        gain += args->background_orders[axis];
    }
    const unsigned int whole = gain / 32u;
    const unsigned int part = gain % 32u;
    for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const unsigned int *const scaled = &smoothed[voxel * BINOMIAL_BASINS_LIMBS];
        const unsigned int *const background = &current[voxel * BINOMIAL_BASINS_LIMBS];
        unsigned long long borrow = 0ull;
        for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
        {
            unsigned int shifted = 0u;
            if (limb >= whole)
            {
                shifted = scaled[limb - whole] << part;
                if ((part != 0u) && (limb > whole))
                {
                    shifted |= scaled[limb - whole - 1u] >> (32u - part);
                }
            }
            // The base keeps the difference non-negative before narrowing, so no wrap is reasoned
            // about at the store.
            const unsigned long long difference = (1ull << 32u) + (unsigned long long)shifted
                                                - (unsigned long long)background[limb] - borrow;
            spare[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(difference & 0xFFFFFFFFull);
            borrow = (difference < (1ull << 32u)) ? 1ull : 0ull;
        }
    }
    const unsigned int *const residual = spare;

    // Ascent: the highest of each voxel and its 26 neighbours, lower index first among equals.
    const unsigned int plane = geometry.height * geometry.width;
    for (unsigned int voxel = 0u; voxel < geometry.voxels; voxel += 1u)
    {
        positive[voxel] = (unsigned char)host_positive(&residual[voxel * BINOMIAL_BASINS_LIMBS]);
        // Signed coordinates, because a neighbour one step before the volume is tested, not indexed.
        const long long column = (long long)(voxel % geometry.width);
        const long long row = (long long)((voxel / geometry.width) % geometry.height);
        const long long slice = (long long)(voxel / plane);
        unsigned int best = voxel;
        for (long long step_slice = -1ll; step_slice <= 1ll; step_slice += 1ll)
        {
            for (long long step_row = -1ll; step_row <= 1ll; step_row += 1ll)
            {
                for (long long step_column = -1ll; step_column <= 1ll; step_column += 1ll)
                {
                    const long long at_slice = slice + step_slice;
                    const long long at_row = row + step_row;
                    const long long at_column = column + step_column;
                    if ((at_slice < 0ll) || (at_slice >= (long long)geometry.depth) || (at_row < 0ll)
                     || (at_row >= (long long)geometry.height) || (at_column < 0ll)
                     || (at_column >= (long long)geometry.width))
                    {
                        continue;
                    }
                    // Narrowing is safe: each coordinate was just shown to lie inside the volume.
                    const unsigned int neighbour = ((unsigned int)at_slice * plane)
                                                 + ((unsigned int)at_row * geometry.width)
                                                 + (unsigned int)at_column;
                    const int order = host_compare(&residual[neighbour * BINOMIAL_BASINS_LIMBS],
                                                   &residual[best * BINOMIAL_BASINS_LIMBS]);
                    if ((order > 0) || ((order == 0) && (neighbour < best)))
                    {
                        best = neighbour;
                    }
                }
            }
        }
        successor[voxel] = best;
    }

    // Every voxel to its peak. A successor is always a strictly higher voxel under the total order,
    // so each walk ends, and writing the found peak back along the walk makes later walks short.
    for (unsigned int voxel = 0u; voxel < geometry.voxels; voxel += 1u)
    {
        unsigned int peak = voxel;
        while (successor[peak] != peak)
        {
            peak = successor[peak];
        }
        unsigned int walk = voxel;
        while (successor[walk] != peak)
        {
            const unsigned int next = successor[walk];
            successor[walk] = peak;
            walk = next;
        }
    }

    unsigned long long peak_count = 0ull;
    for (unsigned int voxel = 0u; voxel < geometry.voxels; voxel += 1u)
    {
        if (positive[voxel] != 0u)
        {
            const unsigned int peak = successor[voxel];
            sizes[peak] += 1u;
            sums[(size_t)peak * 3u] += (unsigned long long)(voxel / plane);
            sums[((size_t)peak * 3u) + 1u] += (unsigned long long)((voxel / geometry.width) % geometry.height);
            sums[((size_t)peak * 3u) + 2u] += (unsigned long long)(voxel % geometry.width);
            if (successor[voxel] == voxel)
            {
                peak_count += 1ull;
            }
        }
    }

    // Adjacency: every face between two basins whose peaks are both positive, as sorted unique pairs.
    // Joined: the faces among those whose two voxels are themselves both positive.
    size_t pair_capacity = 1u << 20u;
    size_t pair_total = 0u;
    unsigned int *pairs = (unsigned int *)malloc(pair_capacity * 2u * sizeof(unsigned int));
    size_t joined_capacity = 1u << 20u;
    size_t joined_total = 0u;
    unsigned int *joined = (unsigned int *)malloc(joined_capacity * 2u * sizeof(unsigned int));
    int ok = ((pairs != NULL) && (joined != NULL)) ? 1 : 0;
    for (unsigned int voxel = 0u; (voxel < geometry.voxels) && (ok != 0); voxel += 1u)
    {
        const unsigned int column = voxel % geometry.width;
        const unsigned int row = (voxel / geometry.width) % geometry.height;
        const unsigned int slice = voxel / plane;
        const unsigned int forward[3] = {voxel + 1u, voxel + geometry.width, voxel + plane};
        const int inside[3] = {(column + 1u) < geometry.width, (row + 1u) < geometry.height,
                               (slice + 1u) < geometry.depth};
        for (unsigned int face = 0u; (face < 3u) && (ok != 0); face += 1u)
        {
            if (inside[face] == 0)
            {
                continue;
            }
            const unsigned int here = successor[voxel];
            const unsigned int there = successor[forward[face]];
            if ((here == there) || (positive[here] == 0u) || (positive[there] == 0u))
            {
                continue;
            }
            // A caller that passes no adjacency buffer has not asked for adjacency; none is collected.
            if (args->adjacency != NULL)
            {
                ok = host_push_pair(&pairs, &pair_capacity, &pair_total, here, there);
            }
            if ((ok != 0) && (positive[voxel] != 0u) && (positive[forward[face]] != 0u))
            {
                ok = host_push_pair(&joined, &joined_capacity, &joined_total, here, there);
            }
        }
    }
    const size_t unique_total = (ok != 0) ? host_unique_pairs(pairs, pair_total) : 0u;
    const size_t joined_unique = (ok != 0) ? host_unique_pairs(joined, joined_total) : 0u;

    if ((ok != 0) && (peak_count <= (unsigned long long)BINOMIAL_BASINS_ROOM_LIMIT)
     && (unique_total <= (size_t)BINOMIAL_BASINS_ROOM_LIMIT) && (joined_unique <= (size_t)BINOMIAL_BASINS_ROOM_LIMIT))
    {
        // Narrowing is safe: every count was just held to BINOMIAL_BASINS_ROOM_LIMIT.
        *args->adjacency_count = (unsigned int)unique_total;
        *args->joined_count = (unsigned int)joined_unique;
        answer = (long)peak_count;
        if ((peak_count <= (unsigned long long)args->room) && (unique_total <= (size_t)args->adjacency_room)
         && (joined_unique <= (size_t)args->joined_room))
        {
            if (joined_unique != 0u)
            {
                memcpy(args->joined, joined, joined_unique * 2u * sizeof(unsigned int));
            }
            size_t slot = 0u;
            for (unsigned int voxel = 0u; voxel < geometry.voxels; voxel += 1u)
            {
                if ((successor[voxel] != voxel) || (positive[voxel] == 0u))
                {
                    continue;
                }
                args->peak_indices[slot] = voxel;
                args->sizes[slot] = sizes[voxel];
                memcpy(&args->sums[slot * 3u], &sums[(size_t)voxel * 3u], 3u * sizeof(unsigned long long));
                memcpy(&args->peak_limbs[slot * BINOMIAL_BASINS_LIMBS], &residual[(size_t)voxel * BINOMIAL_BASINS_LIMBS],
                       BINOMIAL_BASINS_LIMBS * sizeof(unsigned int));
                slot += 1u;
            }
            if (unique_total != 0u)
            {
                memcpy(args->adjacency, pairs, unique_total * 2u * sizeof(unsigned int));
            }
            if (args->labels != NULL)
            {
                memcpy(args->labels, successor, voxels * sizeof(unsigned int));
            }
            if (args->residual_limbs != NULL)
            {
                memcpy(args->residual_limbs, residual, limb_bytes);
            }
            if (args->positive_words != NULL)
            {
                const size_t words = (voxels + 63u) / 64u;
                memset(args->positive_words, 0, words * sizeof(unsigned long long));
                for (size_t voxel = 0u; voxel < voxels; voxel += 1u)
                {
                    if (positive[voxel] != 0u)
                    {
                        args->positive_words[voxel / 64u] |= 1ull << (voxel % 64u);
                    }
                }
            }
        }
    }

    free(pairs);
    free(joined);
    free(first);
    free(second);
    free(smoothed);
    free(successor);
    free(positive);
    free(sizes);
    free(sums);
    return answer;
}
