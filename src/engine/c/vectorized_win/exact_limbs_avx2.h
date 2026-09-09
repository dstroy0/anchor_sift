/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_limbs_avx2.h
 * @brief The AVX2 comparison over a limb array, written once for every x86 build that wants it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note The Windows build and the Linux build run identical arithmetic on identical instructions,
 *       so the loops live here and both compile this one file. A second copy in the other directory
 *       would be one edit away from disagreeing with this one, and a disagreement between two arms
 *       is a defect by definition.
 * @note What differs per platform is asking the processor whether it carries AVX2. Detection is all
 *       vectorized_win and vectorized_linux each hold, being a property of the compiler and the
 *       operating system. The arithmetic is a property of the instruction set.
 * @note Both comparisons walk from the top limb down. At a scale of 1024 decimal digits a deposited
 *       value has hundreds of trailing zero digits, so the low limbs are zero on both sides and
 *       carry no information. The first difference is near the top and the scan finds it at once.
 */
#ifndef ANCHOR_EXACT_LIMBS_AVX2_H
#define ANCHOR_EXACT_LIMBS_AVX2_H

#include "exact_limbs.h"

#include <immintrin.h>

/** @brief Limbs compared per AVX2 instruction. 256 bits holds eight 32 bit limbs. */
#define ANCHOR_AVX2_LANES 8u

/**
 * @brief Whether two magnitudes are equal, eight limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          1 where every limb matches, 0 otherwise.
 * @note _mm256_cmpeq_epi32 sets a lane to all ones where the two limbs match, and the byte mask is
 *       therefore -1 exactly when all eight matched. Anything else means a difference is in the
 *       block and the values are not equal.
 */
static inline int anchor_avx2_magnitude_equal(const uint32_t *left, const uint32_t *right)
{
    size_t at = (size_t)ANCHOR_EXACT_LIMBS;
    while (at >= (size_t)ANCHOR_AVX2_LANES)
    {
        at -= (size_t)ANCHOR_AVX2_LANES;
        const __m256i one = _mm256_loadu_si256((const __m256i *)(left + at));
        const __m256i two = _mm256_loadu_si256((const __m256i *)(right + at));
        if (_mm256_movemask_epi8(_mm256_cmpeq_epi32(one, two)) != -1)
        {
            return 0;
        }
    }
    // The limb count is not a multiple of the lane count, and the remainder is at the bottom.
    while (at > 0u)
    {
        at--;
        if (left[at] != right[at])
        {
            return 0;
        }
    }
    return 1;
}

/**
 * @brief Orders two magnitudes, eight limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          -1 where left is smaller, 1 where it is larger, 0 where they are equal.
 * @note A vector says a block differs; it does not say which limb differs first. The block holding
 *       the highest difference is found with the vector and then walked backward one limb at a
 *       time, which runs at most eight scalar steps once per comparison.
 */
static inline int anchor_avx2_magnitude_compare(const uint32_t *left, const uint32_t *right)
{
    size_t at = (size_t)ANCHOR_EXACT_LIMBS;
    while (at >= (size_t)ANCHOR_AVX2_LANES)
    {
        at -= (size_t)ANCHOR_AVX2_LANES;
        const __m256i one = _mm256_loadu_si256((const __m256i *)(left + at));
        const __m256i two = _mm256_loadu_si256((const __m256i *)(right + at));
        if (_mm256_movemask_epi8(_mm256_cmpeq_epi32(one, two)) != -1)
        {
            size_t back = at + (size_t)ANCHOR_AVX2_LANES;
            while (back > at)
            {
                back--;
                if (left[back] != right[back])
                {
                    return (left[back] < right[back]) ? -1 : 1;
                }
            }
        }
    }
    while (at > 0u)
    {
        at--;
        if (left[at] != right[at])
        {
            return (left[at] < right[at]) ? -1 : 1;
        }
    }
    return 0;
}

/**
 * @brief Whether two integers hold the same value, sign included.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          1 where the values are equal, 0 otherwise.
 */
static inline int anchor_avx2_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return 0;
    }
    return anchor_avx2_magnitude_equal(left->limb, right->limb);
}

/**
 * @brief Orders two integers, sign included.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1, 1 or 0, matching anchor_exact_compare exactly.
 */
static inline int anchor_avx2_compare(const AnchorExactInteger *left,
                                      const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return (left->sign < right->sign) ? -1 : 1;
    }
    const int order = anchor_avx2_magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative, so the larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Counts agreeing places over a sorted run, using the vector comparison throughout.
 *
 * @param[in] positions Positions, ascending [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test [BORROWS].
 * @return              How many positions have an equal value exactly `lag` above them.
 * @note The search is the same binary search the portable arm runs. Only the comparison inside it
 *       is widened, which is where the time goes: a comparison touches up to 108 limbs and the
 *       search runs log2(count) of them per position.
 */
static inline size_t anchor_avx2_agreement(const AnchorExactInteger *positions,
                                           const uint64_t *values, size_t count,
                                           const AnchorExactInteger *lag)
{
    size_t agreed = 0u;
    for (size_t at = 0u; at < count; at++)
    {
        AnchorExactInteger moved;
        if (anchor_exact_add(&positions[at], lag, &moved) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        size_t low = 0u;
        size_t high = count;
        size_t found = count;
        while (low < high)
        {
            const size_t middle = low + ((high - low) / 2u);
            const int order = anchor_avx2_compare(&positions[middle], &moved);
            if (order == 0)
            {
                found = middle;
                break;
            }
            if (order < 0)
            {
                low = middle + 1u;
            }
            else
            {
                high = middle;
            }
        }
        if ((found < count) && (values[found] == values[at]))
        {
            agreed++;
        }
    }
    return agreed;
}

#endif /* ANCHOR_EXACT_LIMBS_AVX2_H */
