/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_avx512.c
 * @brief The AVX-512 arm: asking this processor whether it carries AVX-512F, then offering it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note No machine in this project has AVX-512, so this arm has never been run. It is compiled for
 *       the target and its emitted instructions are read by maint/engine/verify_arm_asm.sh, which
 *       confirms zmm registers and vpcmpeqd against a mask. That rules out a silent fallback to
 *       scalar code. It says nothing about behavior, and the arm's name carries that.
 * @note The name reads avx512-unrun for exactly that reason. A row of results should not be able to
 *       show this arm beside a run one without the difference being visible in the row itself.
 * @note Detection asks for AVX-512F and AVX-512BW together, because the masked load the equality
 *       tail uses is a BW instruction and a part with F alone would fault on it.
 */

#include "exact_arm.h"

#if defined(ANCHOR_EXACT_HAVE_AVX512) && ANCHOR_EXACT_HAVE_AVX512

#include "exact_limbs_avx512.h"

#if defined(_MSC_VER)
#include <intrin.h>
/** @brief Set where this translation unit can ask the processor about AVX-512. */
#define ANCHOR_AVX512_CAN_DETECT 1
#elif defined(__GNUC__) || defined(__clang__)
#define ANCHOR_AVX512_CAN_DETECT 1
#else
#define ANCHOR_AVX512_CAN_DETECT 0
#endif

/**
 * @brief Whether the running processor carries the AVX-512 subsets this arm issues.
 *
 * @return 1 where AVX-512F and AVX-512BW are both present, 0 otherwise.
 * @note Leaf 7 subleaf 0: bit 16 of EBX is AVX-512F and bit 30 is AVX-512BW. The leaf exists only
 *       where leaf 0 reports a maximum of at least 7, which is checked before it is read.
 */
static int avx512_present(void)
{
#if !ANCHOR_AVX512_CAN_DETECT
    return 0;
#elif defined(_MSC_VER)
    int leaves[4] = {0, 0, 0, 0};
    __cpuid(leaves, 0);
    if (leaves[0] < 7)
    {
        return 0;
    }
    __cpuidex(leaves, 7, 0);
    const int foundation = (leaves[1] & (1 << 16)) != 0;
    const int byte_word = (leaves[1] & (1 << 30)) != 0;
    return (foundation && byte_word) ? 1 : 0;
#else
    return (__builtin_cpu_supports("avx512f") && __builtin_cpu_supports("avx512bw")) ? 1 : 0;
#endif
}

/**
 * @brief Whether two integers hold the same value, through the AVX-512 comparison.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          1 where the values are equal, 0 otherwise.
 */
static int arm_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    return anchor_avx512_equal(left, right);
}

/**
 * @brief Orders two integers, through the AVX-512 comparison.
 *
 * @param[in] left  First integer [BORROWS].
 * @param[in] right Second integer [BORROWS].
 * @return          -1, 1 or 0.
 */
static int arm_compare(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    return anchor_avx512_compare(left, right);
}

/**
 * @brief Counts agreeing places over a sorted run, through the AVX-512 comparison.
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
static const AnchorExactArm AVX512_ARM = {
    "avx512-unrun",
    arm_equal,
    arm_compare,
    arm_agreement,
};

const AnchorExactArm *anchor_exact_avx512_arm(void)
{
    return avx512_present() ? &AVX512_ARM : NULL;
}

#else

const AnchorExactArm *anchor_exact_avx512_arm(void)
{
    return NULL;
}

#endif /* ANCHOR_EXACT_HAVE_AVX512 */
