/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file binomial_basins.c
 * @brief The host arm of the binomial residual and its basins, the reference the device arm is
 *        graded against.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-18
 *
 * @note One voxel at a time and one pass at a time, with nothing fused and nothing transformed.
 *       Slow on a full frame, and the simplest form of the arithmetic the device arm speeds up.
 */

#include "binomial_basins.h"

#include <stdlib.h>
#include <string.h>

_Static_assert(sizeof(unsigned int) == 4u, "binomial_basins: unsigned int must be 32 bits, a limb");
_Static_assert(sizeof(unsigned long long) == 8u,
               "binomial_basins: unsigned long long must be 64 bits, a limb product and its carry");

/** @brief The volume's shape. */
typedef struct
{
    unsigned int depth;  /**< Voxels along axis 0. */
    unsigned int height; /**< Voxels along axis 1. */
    unsigned int width;  /**< Voxels along axis 2. */
    unsigned int voxels; /**< Voxels in the volume. */
} HostGeometry;

/**
 * @brief Folds a position outside a line back into it, repeating the edge sample.
 *
 * @param[in] position A position along the line, possibly negative or past its end.
 * @param[in] length   The line's length.
 * @return             The position reflected into 0 to length - 1: d c b a | a b c d | d c b a.
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

    // folded lies in 0 to length - 1, and a line is below 2^32 voxels.
    return (unsigned int)folded;
}

/**
 * @brief Writes row `order` of Pascal's triangle, the coefficients of (1 + x)^order.
 *
 * @param[in]  order   The row, at most BINOMIAL_BASINS_PASS_ORDER.
 * @param[out] weights order + 1 coefficients [BORROWS].
 * @note Built in place, each row from the one before, adding right to left so every entry reads
 *       its left neighbor before that neighbor is overwritten. C(32, 16) is 601080390, which fits
 *       the unsigned int.
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
 * @brief Limbs a value of a given bit width occupies.
 *
 * @param[in] bits The bit width.
 * @return         bits / 32, rounded up.
 */
static unsigned int host_limbs(unsigned int bits)
{
    return (bits + 31u) / 32u;
}

/**
 * @brief One binomial pass along one axis, every voxel of the volume.
 *
 * @param[in]  source      The volume read, BINOMIAL_BASINS_LIMBS limbs per voxel [BORROWS].
 * @param[out] destination The volume written [BORROWS].
 * @param[in]  weights     The order + 1 weights [BORROWS].
 * @param[in]  order       The pass's order, even.
 * @param[in]  axis        The axis.
 * @param[in]  limbs_in    Limbs the source values occupy. The limbs above are zero.
 * @param[in]  geometry    The shape.
 * @note Each limb of the result is summed on its own in 64 bits and the carries run once at the
 *       end. The weights sum to at most 2^32 and a limb is below 2^32. No 64 bit sum wraps.
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

            // Taps run from order / 2 before the voxel to order / 2 after it, centered because the
            // order is even.
            const long long position = (long long)along + (long long)tap - (long long)(order / 2u);
            const unsigned int read = line_start + (host_reflect(position, (long long)length) * stride);
            for (unsigned int limb = 0u; limb < limbs_in; limb += 1u)
            {

                accumulator[limb] += (unsigned long long)weights[tap]
                                   * (unsigned long long)source[(read * BINOMIAL_BASINS_LIMBS) + limb];
            }
        }
        unsigned long long carry = 0ull;
        for (unsigned int limb = 0u; limb < BINOMIAL_BASINS_LIMBS; limb += 1u)
        {
            const unsigned long long total = accumulator[limb] + carry;

            // The low half is the limb and the high half carries into the next.
            destination[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(total & 0xFFFFFFFFull);
            carry = total >> 32u;
        }
    }
}

/**
 * @brief Smooths along all three axes by the given orders, depth first.
 *
 * @param[in,out] current  The volume, replaced by the smoothed volume [BORROWS].
 * @param[in,out] spare    A second volume the passes alternate with [BORROWS].
 * @param[in]     orders   The order per axis [BORROWS].
 * @param[in,out] bits     The values' bit width, raised by each pass's order [BORROWS].
 * @param[in]     geometry The shape.
 * @note An order above BINOMIAL_BASINS_PASS_ORDER runs as several passes. Binomial kernels
 *       compose by adding orders, and the passes together apply the full order.
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
 * @brief Orders two two's complement residuals.
 *
 * @param[in] left  One residual [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          -1, 0 or 1 as `left` is below, equal to or above `right`.
 * @note Flipping the sign bit of the top limb maps two's complement order onto unsigned order,
 *       and the rest compares limb by limb from the top.
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
 * @brief Whether a two's complement residual is above zero.
 *
 * @param[in] value The residual [BORROWS].
 * @return          1 where the sign bit is clear and some limb is nonzero, 0 otherwise.
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
 * @brief Orders two peak pairs for qsort, by first peak then second.
 *
 * @param[in] left  One pair, two unsigned ints [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          -1, 0 or 1.
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
 * @brief Appends a pair, lower peak first, doubling the array when full.
 *
 * @param[in,out] pairs    The pair array, reallocated when it grows [BORROWS].
 * @param[in,out] capacity Pairs the array holds [BORROWS].
 * @param[in,out] total    Pairs held [BORROWS].
 * @param[in]     here     One peak.
 * @param[in]     there    The other.
 * @return                 1 where the pair was appended, 0 where the array could not grow, with
 *                         the array as it was.
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
 * @brief Sorts pairs and removes repeats in place.
 *
 * @param[in,out] pairs The pairs [BORROWS].
 * @param[in]     total How many.
 * @return              How many distinct pairs are left at the front.
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
    // A 16 bit sample, one sign bit, and one bit per unit of order must fit the limbs.
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

    const unsigned long long plane_count = (unsigned long long)args->height * (unsigned long long)args->width;
    if ((total_bits > (32ull * BINOMIAL_BASINS_LIMBS)) || (plane_count > 0xFFFFFFFFull))
    {
        return BINOMIAL_BASINS_REFUSED;
    }
    // Every limb index, voxel times BINOMIAL_BASINS_LIMBS plus a limb, has to fit 32 bits.
    const unsigned long long voxel_count = plane_count * (unsigned long long)args->depth;
    if (voxel_count > (0xFFFFFFFFull / BINOMIAL_BASINS_LIMBS))
    {
        return BINOMIAL_BASINS_REFUSED;
    }

    HostGeometry geometry;
    geometry.depth = args->depth;
    geometry.height = args->height;
    geometry.width = args->width;

    // Bounded below 2^32 just above. The count fits the unsigned int.
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

    // residual = smoothed * 2^gain - background, the smoothed field shifted left by gain bits and
    // the background subtracted with a running borrow. gain splits into whole limbs and a part.
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

            // 2^32 is added before subtracting. The difference is never negative, and a result
            // below 2^32 means a borrow was taken.
            const unsigned long long difference = (1ull << 32u) + (unsigned long long)shifted
                                                - (unsigned long long)background[limb] - borrow;
            spare[(voxel * BINOMIAL_BASINS_LIMBS) + limb] = (unsigned int)(difference & 0xFFFFFFFFull);
            borrow = (difference < (1ull << 32u)) ? 1ull : 0ull;
        }
    }
    const unsigned int *const residual = spare;

    const unsigned int plane = geometry.height * geometry.width;
    for (unsigned int voxel = 0u; voxel < geometry.voxels; voxel += 1u)
    {
        positive[voxel] = (unsigned char)host_positive(&residual[voxel * BINOMIAL_BASINS_LIMBS]);

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

                    const unsigned int neighbour = ((unsigned int)at_slice * plane)
                                                 + ((unsigned int)at_row * geometry.width)
                                                 + (unsigned int)at_column;
                    const int order = host_compare(&residual[neighbour * BINOMIAL_BASINS_LIMBS],
                                                   &residual[best * BINOMIAL_BASINS_LIMBS]);
                    // A tie goes to the lower index, which leaves no cycle across a plateau.
                    if ((order > 0) || ((order == 0) && (neighbour < best)))
                    {
                        best = neighbour;
                    }
                }
            }
        }
        successor[voxel] = best;
    }

    // Walk each voxel to its peak, then point the whole path straight at it.
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

    // A positive voxel's peak is at least as high. It is positive too and counted as a peak.
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

    // Every face between two voxels of different positive basins adds a pair, and a face whose two
    // voxels are both positive adds a joined pair as well. Each face is visited once, from the voxel
    // on its lower side.
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

        // All three counts are at most BINOMIAL_BASINS_ROOM_LIMIT, which fits an unsigned int and
        // a long on every target.
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
            // Peaks in ascending voxel index, the order the device arm writes them in.
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
