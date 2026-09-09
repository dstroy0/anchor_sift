/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_avx2.c
 * @brief The AVX2 arm on Linux: asking this processor whether it carries AVX2, then offering it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note The arithmetic is in vectorized_win/exact_limbs_avx2.h and is shared with the Windows arm.
 *       Both run identical instructions on identical data, and a second copy of those loops here
 *       would be one edit away from disagreeing with that one. What this file holds is detection.
 * @note Linux builds run GCC or Clang, and both carry __builtin_cpu_supports, which resolves
 *       against the processor at run time. The gate still has both arms defined, and a compiler
 *       carrying neither reports the arm absent instead of being assumed to have it.
 * @note The arm reports a different name from the Windows one. Two arms that run the same
 *       instructions still have to be told apart in a row of results, because what is being
 *       compared includes the compiler and the operating system that built them.
 */

#include "exact_arm.h"
#include "exact_limbs_avx2.h"

#if defined(__GNUC__) || defined(__clang__)
/** @brief Set where this translation unit can ask the processor about AVX2. */
#define ANCHOR_AVX2_CAN_DETECT 1
#else
#define ANCHOR_AVX2_CAN_DETECT 0
#endif

/**
 * @brief Whether the running processor carries AVX2.
 *
 * @return 1 where AVX2 is present, 0 where it is absent or cannot be determined.
 */
static int avx2_present(void)
{
#if ANCHOR_AVX2_CAN_DETECT
    return __builtin_cpu_supports("avx2") ? 1 : 0;
#else
    return 0;
#endif
}

/**
 * @brief Whether two integers hold the same value, through the shared AVX2 comparison.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          1 where the values are equal, 0 otherwise.
 */
static int arm_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    return anchor_avx2_equal(left, right);
}

/**
 * @brief Orders two integers, through the shared AVX2 comparison.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1, 1 or 0.
 */
static int arm_compare(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    return anchor_avx2_compare(left, right);
}

/**
 * @brief Counts agreeing places over a sorted run, through the shared AVX2 comparison.
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
static const AnchorExactArm AVX2_ARM = {
    "avx2-linux",
    arm_equal,
    arm_compare,
    arm_agreement,
};

const AnchorExactArm *anchor_exact_avx2_arm(void)
{
    return avx2_present() ? &AVX2_ARM : NULL;
}
