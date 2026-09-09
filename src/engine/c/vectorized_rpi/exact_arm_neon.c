/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_neon.c
 * @brief The NEON arm: the same limb comparison, four limbs to an instruction instead of eight.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Written for the Raspberry Pi 5, which is a Cortex-A76 at aarch64. NEON is mandatory in the
 *       base aarch64 architecture, so on a 64 bit ARM build there is nothing to detect and the arm
 *       is always available. A 32 bit ARM build is a different matter and is gated below.
 * @note A NEON register is 128 bits and holds four 32 bit limbs against AVX2's eight. The loop is
 *       otherwise identical. The arithmetic belongs to the representation and not to the
 *       instruction set, and every arm has to return what the portable one returns.
 * @note vceqq_u32 sets a lane to all ones where the two limbs match. There is no movemask on NEON,
 *       so the four lanes are folded to one 64 bit pair with vminvq_u32, which returns the smallest
 *       lane: that is zero exactly when some lane failed to match.
 */

#include "exact_arm.h"

#if defined(__aarch64__) || defined(__ARM_NEON) || defined(_M_ARM64)
#include <arm_neon.h>
/** @brief Set where this translation unit can issue NEON instructions. */
#define ANCHOR_NEON_USABLE 1
#else
#define ANCHOR_NEON_USABLE 0
#endif

#if ANCHOR_NEON_USABLE

/** @brief Limbs compared per NEON instruction. 128 bits holds four 32 bit limbs. */
#define ANCHOR_NEON_LANES 4u

/**
 * @brief Whether two magnitudes are equal, four limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          1 where every limb matches, 0 otherwise.
 * @note Walks from the top limb down. At a scale of 1024 decimal digits a deposited value carries
 *       hundreds of trailing zero digits, so the low limbs are zero on both sides and hold nothing.
 */
static int neon_magnitude_equal(const uint32_t *left, const uint32_t *right)
{
    size_t at = (size_t)ANCHOR_EXACT_LIMBS;
    while (at >= (size_t)ANCHOR_NEON_LANES)
    {
        at -= (size_t)ANCHOR_NEON_LANES;
        const uint32x4_t one = vld1q_u32(left + at);
        const uint32x4_t two = vld1q_u32(right + at);
        // The smallest lane of the comparison is zero exactly when one of the four differed.
        if (vminvq_u32(vceqq_u32(one, two)) == 0u)
        {
            return 0;
        }
    }
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
 * @brief Orders two magnitudes, four limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          -1 where left is smaller, 1 where it is larger, 0 where they are equal.
 * @note The vector says a block differs and not which limb differs first, so the block holding the
 *       highest difference is walked backward one limb at a time. That runs at most four scalar
 *       steps, once per comparison.
 */
static int neon_magnitude_compare(const uint32_t *left, const uint32_t *right)
{
    size_t at = (size_t)ANCHOR_EXACT_LIMBS;
    while (at >= (size_t)ANCHOR_NEON_LANES)
    {
        at -= (size_t)ANCHOR_NEON_LANES;
        const uint32x4_t one = vld1q_u32(left + at);
        const uint32x4_t two = vld1q_u32(right + at);
        if (vminvq_u32(vceqq_u32(one, two)) == 0u)
        {
            size_t back = at + (size_t)ANCHOR_NEON_LANES;
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
static int arm_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return 0;
    }
    return neon_magnitude_equal(left->limb, right->limb);
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
    const int order = neon_magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative, so the larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Counts agreeing places over a sorted run, using the NEON comparison throughout.
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
    // set and not a second algorithm. This arm carried its own ordered search once, which measured
    // the difference between two algorithms and reported it as the difference between two parts.
    return anchor_exact_agreement_using(arm_equal, positions, values, count, lag);
}

/** @brief The arm as a driver sees it. Static storage, so returning its address is safe. */
static const AnchorExactArm NEON_ARM = {
    "neon",
    arm_equal,
    arm_compare,
    arm_agreement,
};

const AnchorExactArm *anchor_exact_neon_arm(void)
{
    // NEON is part of the base aarch64 architecture. A build that got here can always run it.
    return &NEON_ARM;
}

#else

const AnchorExactArm *anchor_exact_neon_arm(void)
{
    return NULL;
}

#endif /* ANCHOR_NEON_USABLE */
