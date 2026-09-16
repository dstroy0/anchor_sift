/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_sve.c
 * @brief The SVE arm of the exact arithmetic, at whatever vector length the part turns out to have.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @note Written for server class ARM: Graviton, Ampere Altra, Grace, the Neoverse cores. No part in
 *       this project has SVE. The Raspberry Pi 5 is a Cortex-A76, which is NEON only, so this arm has
 *       never been run. It is compiled for armv8.2-a+sve and its emitted instructions are read by
 *       maint/engine/verify_arm_asm.sh, which confirms the predicated forms. That says the intrinsics
 *       became SVE instructions and not a scalar fallback. It says nothing about behavior, and the
 *       arm's name carries that.
 * @note SVE has no fixed vector length. A part may be 128, 256, 512 bits or more, and the same
 *       binary runs on all of them: svcntw() answers how many 32 bit lanes this part carries and the
 *       loop is written around a predicate instead of around a constant. No lane count appears in
 *       this file for that reason, and the tail needs no separate scalar loop.
 * @note Detection reads the hardware capability word Linux exposes, never executing an SVE
 *       instruction to see whether it faults. There is no cpuid on ARM: a part's features come from
 *       the kernel, and on anything other than Linux this arm reports itself absent instead of
 *       guessing.
 */

#include "exact_arm.h"

#if defined(ANCHOR_EXACT_HAVE_SVE) && ANCHOR_EXACT_HAVE_SVE

#include <arm_sve.h>

#if defined(__linux__)
#include <sys/auxv.h>
/** @brief Set where this translation unit can ask the kernel about SVE. */
#define ANCHOR_SVE_CAN_DETECT 1
#ifndef HWCAP_SVE
/** @brief The SVE bit in AT_HWCAP, spelled here where the running headers predate it. */
#define HWCAP_SVE (1 << 22)
#endif
#else
#define ANCHOR_SVE_CAN_DETECT 0
#endif

/**
 * @brief Whether this part carries SVE.
 *
 * @return 1 where the kernel reports SVE, 0 where it does not or cannot be asked.
 */
static int sve_present(void)
{
#if ANCHOR_SVE_CAN_DETECT
    return ((getauxval(AT_HWCAP) & (unsigned long)HWCAP_SVE) != 0ul) ? 1 : 0;
#else
    return 0;
#endif
}

/**
 * @brief Whether two magnitudes are equal, a vector's worth of limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          1 where every limb matches, 0 otherwise.
 * @note Walks upward here and not downward. svwhilelt_b32 builds the predicate for a forward run
 *       and there is no reversed form of it, so the direction that costs nothing on this instruction
 *       set is the forward one. Equality has no early information in the high limbs the way ordering
 *       does, so nothing is lost by it.
 */
static int sve_magnitude_equal(const uint32_t *left, const uint32_t *right)
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
 * @note Ordering is settled by the highest limb that differs, so this walks blocks from the top down
 *       and then walks the differing block backward. The block stride is the vector length, which is
 *       not known until run time, so the top block is found by counting down from the limb count
 *       instead of by a constant.
 */
static int sve_magnitude_compare(const uint32_t *left, const uint32_t *right)
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
static int arm_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return 0;
    }
    return sve_magnitude_equal(left->limb, right->limb);
}

/**
 * @brief Orders two integers, sign included.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1, 1 or 0, matching anchor_exact_compare exactly.
 */
static int arm_compare(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return (left->sign < right->sign) ? -1 : 1;
    }
    const int order = sve_magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative, so the larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Counts agreeing places over a sorted run, through the SVE equality.
 *
 * @param[in] positions Positions, ascending [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test [BORROWS].
 * @return              How many positions agree with the place one lag above them.
 */
static size_t arm_agreement(const AnchorExactInteger *positions, const uint64_t *values,
                            size_t count, const AnchorExactInteger *lag)
{
    // The shared search, with only the equality test swapped, so what is timed is the instruction
    // set and not a second algorithm.
    return anchor_exact_agreement_using(arm_equal, positions, values, count, lag);
}

/** @brief The arm as a driver sees it. Static storage, so returning its address is safe. */
static const AnchorExactArm SVE_ARM = {
    "sve-unrun",
    arm_equal,
    arm_compare,
    arm_agreement,
};

const AnchorExactArm *anchor_exact_sve_arm(void)
{
    return sve_present() ? &SVE_ARM : NULL;
}

#else

const AnchorExactArm *anchor_exact_sve_arm(void)
{
    return NULL;
}

#endif /* ANCHOR_EXACT_HAVE_SVE */
