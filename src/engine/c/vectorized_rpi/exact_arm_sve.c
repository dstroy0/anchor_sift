/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_sve.c
 * @brief The SVE arm: asking this part whether it carries SVE, then offering it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note No part in this project has SVE. The Raspberry Pi 5 is a Cortex-A76, which is NEON only, so
 *       this arm has never been run. It is cross compiled for armv8.2-a+sve and its emitted
 *       instructions are read by maint/engine/verify_arm_asm.sh, which confirms the predicated
 *       forms. That says the intrinsics became SVE instructions and not a scalar fallback. It says
 *       nothing about behavior, and the arm's name carries that.
 * @note Detection reads the hardware capability word Linux exposes, never executing an SVE
 *       instruction to see whether it faults. There is no cpuid on ARM: a part's features come from
 *       the kernel, and on anything other than Linux this arm reports itself absent instead of
 *       guessing.
 */

#include "exact_arm.h"

#if defined(ANCHOR_EXACT_HAVE_SVE) && ANCHOR_EXACT_HAVE_SVE

#include "exact_limbs_sve.h"

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
 * @brief Whether two integers hold the same value, through the SVE comparison.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          1 where the values are equal, 0 otherwise.
 */
static int arm_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    return anchor_sve_equal(left, right);
}

/**
 * @brief Orders two integers, through the SVE comparison.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1, 1 or 0.
 */
static int arm_compare(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    return anchor_sve_compare(left, right);
}

/**
 * @brief Counts agreeing places over a sorted run, through the SVE comparison.
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
