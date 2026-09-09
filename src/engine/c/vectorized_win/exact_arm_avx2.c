/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_avx2.c
 * @brief The AVX2 arm on Windows: asking this processor whether it carries AVX2, then offering it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note The arithmetic is in exact_limbs_avx2.h and is shared with the Linux arm. This file is the
 *       detection alone, because detection is the part that actually differs between the two.
 * @note Two detection paths and both arms of the gate are defined. MSVC has no __builtin_cpu_supports
 *       and takes __cpuidex directly; GCC and Clang have the builtin and use it, on any host.
 *       A build where neither is available reports the arm absent instead of guessing.
 * @note Asked at run time deliberately. A binary built where AVX2 was available still runs on
 *       machines that lack it, and calling in there raises an illegal instruction.
 */

#include "exact_arm.h"
#include "exact_limbs_avx2.h"

#if defined(_MSC_VER)
#include <intrin.h>
/** @brief Set where this translation unit can ask the processor about AVX2. */
#define ANCHOR_AVX2_CAN_DETECT 1
#elif defined(__GNUC__) || defined(__clang__)
#define ANCHOR_AVX2_CAN_DETECT 1
#else
#define ANCHOR_AVX2_CAN_DETECT 0
#endif

/**
 * @brief Whether the running processor carries AVX2.
 *
 * @return 1 where AVX2 is present, 0 where it is absent or cannot be determined.
 * @note Leaf 7 subleaf 0, bit 5 of EBX is the AVX2 flag. The leaf itself only exists where the
 *       maximum leaf reported by leaf 0 reaches 7, so that is checked before it is read.
 */
static int avx2_present(void)
{
#if !ANCHOR_AVX2_CAN_DETECT
    return 0;
#elif defined(_MSC_VER)
    int leaves[4] = {0, 0, 0, 0};
    __cpuid(leaves, 0);
    if (leaves[0] < 7)
    {
        return 0;
    }
    __cpuidex(leaves, 7, 0);
    return ((leaves[1] & (1 << 5)) != 0) ? 1 : 0;
#else
    // The builtin resolves against the processor at run time and needs no cpuid handling here.
    return __builtin_cpu_supports("avx2") ? 1 : 0;
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
    // The shared search, with only the equality test swapped. This arm carried its own ordered
    // search once, and timing that against a portable arm doing a membership lookup measured the
    // difference between two algorithms and reported it as the difference between two instruction
    // sets. It read 3.44x that way and 1.75x this way.
    return anchor_exact_agreement_using(arm_equal, positions, values, count, lag);
}

/** @brief The arm as a driver sees it. Static storage, so returning its address is safe. */
static const AnchorExactArm AVX2_ARM = {
    "avx2-win",
    arm_equal,
    arm_compare,
    arm_agreement,
};

const AnchorExactArm *anchor_exact_avx2_arm(void)
{
    return avx2_present() ? &AVX2_ARM : NULL;
}
