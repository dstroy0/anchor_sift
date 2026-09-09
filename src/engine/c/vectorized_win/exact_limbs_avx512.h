/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_limbs_avx512.h
 * @brief The AVX-512 comparison over a limb array, sixteen limbs to an instruction.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Written for Xeon and for the desktop parts that carry AVX-512F. No machine here has it, so
 *       this arm has never been run. It is verified as far as it can be: it compiles for the target
 *       and the assembler emits zmm registers and vpcmpeqd against a mask register, which is
 *       checked by maint/engine/verify_arm_asm.sh. What is unverified is the behavior at run time.
 * @note AVX-512 comparison does not produce a vector of all-ones lanes the way AVX2 does. It writes
 *       a mask register, one bit per lane, and the comparison is against 0xFFFF for sixteen lanes.
 *       That is a different instruction shape and not a widening of the AVX2 one. It gets its own
 *       file for that reason, instead of a lane count parameter on the other one.
 * @note 108 limbs is six full sixteen-lane blocks and a remainder of twelve. The remainder is
 *       handled with a masked load instead of a scalar tail, since a mask is free on this
 *       instruction set and the tail would otherwise be an eighth of the work.
 */
#ifndef ANCHOR_EXACT_LIMBS_AVX512_H
#define ANCHOR_EXACT_LIMBS_AVX512_H

#include "exact_limbs.h"

#include <immintrin.h>

/** @brief Limbs compared per AVX-512 instruction. 512 bits holds sixteen 32 bit limbs. */
#define ANCHOR_AVX512_LANES 16u

/** @brief Every lane set. A full block of matching limbs compares equal to this. */
#define ANCHOR_AVX512_ALL ((__mmask16)0xFFFFu)

/**
 * @brief Whether two magnitudes are equal, sixteen limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          1 where every limb matches, 0 otherwise.
 * @note Walks from the top limb down. A value scaled to 1024 decimal digits carries hundreds of
 *       trailing zero digits, so the low limbs are zero on both sides and hold no information.
 */
static inline int anchor_avx512_magnitude_equal(const uint32_t *left, const uint32_t *right)
{
    size_t at = (size_t)ANCHOR_EXACT_LIMBS;
    while (at >= (size_t)ANCHOR_AVX512_LANES)
    {
        at -= (size_t)ANCHOR_AVX512_LANES;
        const __m512i one = _mm512_loadu_si512((const void *)(left + at));
        const __m512i two = _mm512_loadu_si512((const void *)(right + at));
        if (_mm512_cmpeq_epi32_mask(one, two) != ANCHOR_AVX512_ALL)
        {
            return 0;
        }
    }
    if (at > 0u)
    {
        // The remainder, as a masked load. Lanes past the remainder read as zero on both sides and
        // compare equal, so the mask is applied to the comparison and not to the load alone.
        const __mmask16 wanted = (__mmask16)((1u << at) - 1u);
        const __m512i one = _mm512_maskz_loadu_epi32(wanted, (const void *)left);
        const __m512i two = _mm512_maskz_loadu_epi32(wanted, (const void *)right);
        if ((_mm512_cmpeq_epi32_mask(one, two) & wanted) != wanted)
        {
            return 0;
        }
    }
    return 1;
}

/**
 * @brief Orders two magnitudes, sixteen limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          -1 where left is smaller, 1 where it is larger, 0 where they are equal.
 * @note The mask says which lanes differ but not which of them sits highest. The block holding
 *       the highest difference is found with the mask and then walked backward one limb at a time,
 *       which runs at most sixteen scalar steps, once per comparison.
 */
static inline int anchor_avx512_magnitude_compare(const uint32_t *left, const uint32_t *right)
{
    size_t at = (size_t)ANCHOR_EXACT_LIMBS;
    while (at >= (size_t)ANCHOR_AVX512_LANES)
    {
        at -= (size_t)ANCHOR_AVX512_LANES;
        const __m512i one = _mm512_loadu_si512((const void *)(left + at));
        const __m512i two = _mm512_loadu_si512((const void *)(right + at));
        if (_mm512_cmpeq_epi32_mask(one, two) != ANCHOR_AVX512_ALL)
        {
            size_t back = at + (size_t)ANCHOR_AVX512_LANES;
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
static inline int anchor_avx512_equal(const AnchorExactInteger *left,
                                      const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return 0;
    }
    return anchor_avx512_magnitude_equal(left->limb, right->limb);
}

/**
 * @brief Orders two integers, sign included.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1, 1 or 0, matching anchor_exact_compare exactly.
 */
static inline int anchor_avx512_compare(const AnchorExactInteger *left,
                                        const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return (left->sign < right->sign) ? -1 : 1;
    }
    const int order = anchor_avx512_magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative, so the larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Counts agreeing places over a sorted run, using the AVX-512 comparison throughout.
 *
 * @param[in] positions Positions, ascending [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test [BORROWS].
 * @return              How many positions agree with the place one lag above them.
 */
static inline size_t anchor_avx512_agreement(const AnchorExactInteger *positions,
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
            const int order = anchor_avx512_compare(&positions[middle], &moved);
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

#endif /* ANCHOR_EXACT_LIMBS_AVX512_H */
