/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_limbs_sve.h
 * @brief The SVE comparison over a limb array, at whatever vector length the part turns out to have.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Written for server class ARM: Graviton, Ampere Altra, Grace, the Neoverse cores. Nothing
 *       here has SVE, so this arm has never been run. It compiles for the target and the assembler
 *       emits the predicated SVE forms, which maint/engine/verify_arm_asm.sh checks. Its behavior
 *       at run time is unverified and is marked as such wherever it is reported.
 * @note SVE has no fixed vector length. A part may be 128, 256, 512 bits or more, and the same
 *       binary runs on all of them: svcntw() answers how many 32 bit lanes this part carries and
 *       the loop is written around a predicate instead of around a constant. No lane count appears
 *       in this file for that reason, and the tail needs no separate scalar loop.
 * @note The Raspberry Pi 5 is a Cortex-A76, which is NEON and not SVE, so the Pi runs the NEON arm
 *       beside this one and never this one. Both are gated on their own feature and both are
 *       defined on both arms of that gate.
 */
#ifndef ANCHOR_EXACT_LIMBS_SVE_H
#define ANCHOR_EXACT_LIMBS_SVE_H

#include "exact_limbs.h"

#include <arm_sve.h>

/**
 * @brief Whether two magnitudes are equal, a vector's worth of limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          1 where every limb matches, 0 otherwise.
 * @note Walks upward here and not downward. svwhilelt_b32 builds the predicate for a forward
 *       run and there is no reversed form of it, so the direction that costs nothing on this
 *       instruction set is the forward one. Equality has no early information in the high limbs the
 *       way ordering does, so nothing is lost by it.
 */
static inline int anchor_sve_magnitude_equal(const uint32_t *left, const uint32_t *right)
{
    for (uint64_t at = 0u; at < (uint64_t)ANCHOR_EXACT_LIMBS; at += svcntw())
    {
        // The predicate covers only the lanes that exist, so the tail needs no separate loop.
        const svbool_t live = svwhilelt_b32(at, (uint64_t)ANCHOR_EXACT_LIMBS);
        const svuint32_t one = svld1_u32(live, left + at);
        const svuint32_t two = svld1_u32(live, right + at);
        if (svptest_any(live, svcmpne_u32(live, one, two)))
        {
            return 0;
        }
    }
    return 1;
}

/**
 * @brief Orders two magnitudes.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          -1 where left is smaller, 1 where it is larger, 0 where they are equal.
 * @note Ordering is settled by the highest limb that differs, so this walks blocks from the top
 *       down and then walks the differing block backward. The block stride is the vector length,
 *       which is not known until run time, so the top block is found by counting down from the
 *       limb count instead of by a constant.
 */
static inline int anchor_sve_magnitude_compare(const uint32_t *left, const uint32_t *right)
{
    const uint64_t lanes = svcntw();
    uint64_t at = (uint64_t)ANCHOR_EXACT_LIMBS;
    while (at > 0u)
    {
        const uint64_t span = (at >= lanes) ? lanes : at;
        at -= span;
        const svbool_t live = svwhilelt_b32(at, at + span);
        const svuint32_t one = svld1_u32(live, left + at);
        const svuint32_t two = svld1_u32(live, right + at);
        if (svptest_any(live, svcmpne_u32(live, one, two)))
        {
            uint64_t back = at + span;
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
    return 0;
}

/**
 * @brief Whether two integers hold the same value, sign included.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          1 where the values are equal, 0 otherwise.
 */
static inline int anchor_sve_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return 0;
    }
    return anchor_sve_magnitude_equal(left->limb, right->limb);
}

/**
 * @brief Orders two integers, sign included.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1, 1 or 0, matching anchor_exact_compare exactly.
 */
static inline int anchor_sve_compare(const AnchorExactInteger *left,
                                     const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return (left->sign < right->sign) ? -1 : 1;
    }
    const int order = anchor_sve_magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative, so the larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Counts agreeing places over a sorted run, using the SVE comparison throughout.
 *
 * @param[in] positions Positions, ascending [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test [BORROWS].
 * @return              How many positions agree with the place one lag above them.
 */
static inline size_t anchor_sve_agreement(const AnchorExactInteger *positions,
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
            const int order = anchor_sve_compare(&positions[middle], &moved);
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

#endif /* ANCHOR_EXACT_LIMBS_SVE_H */
