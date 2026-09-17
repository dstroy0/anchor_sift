/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_avx2.c
 * @brief The AVX2 arm of the exact arithmetic, comparing eight 32 bit limbs per instruction.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @note ONE FILE FOR EVERY x86 BUILD. This arm was two files, one per operating system, sharing a
 *       header of loops. The loops are a property of the instruction set and were already shared.
 *       The two files differed only in how they asked the processor about AVX2, and the Windows
 *       copy already carried both ways of asking. So the loops and both detection paths live here
 *       together, and a second copy that could disagree with this one no longer exists.
 * @note Two detection paths, both arms of the gate defined. MSVC has no __builtin_cpu_supports and
 *       takes __cpuidex directly. GCC and Clang have the builtin and use it on any host. A compiler
 *       carrying neither reports the arm absent instead of guessing.
 * @note Asked at run time deliberately. A binary built where AVX2 was available still runs on
 *       machines that lack it, and calling in there raises an illegal instruction.
 * @note THE NAME STILL NAMES THE OPERATING SYSTEM. Two builds running the same instructions have
 *       to be told apart in a row of results, because what a row compares includes the compiler and
 *       the operating system that built it. Folding the files did not change what a row prints.
 * @note Both comparisons walk from the top limb down. At a scale of 1024 decimal digits a deposited
 *       value has hundreds of trailing zero digits, so the low limbs are zero on both sides and carry
 *       no information. The first difference is near the top and the scan finds it at once.
 */

#include "arm.h"

#include <immintrin.h>

#if defined(_MSC_VER)
#include <intrin.h>
/** @brief Set where this translation unit can ask the processor about AVX2. */
#define ANCHOR_AVX2_CAN_DETECT 1
#elif defined(__GNUC__) || defined(__clang__)
#define ANCHOR_AVX2_CAN_DETECT 1
#else
#define ANCHOR_AVX2_CAN_DETECT 0
#endif

#if defined(_WIN32)
/** @brief What a row of results prints for this arm, which names the operating system that built it. */
#define ANCHOR_AVX2_ARM_NAME "avx2-win"
#else
#define ANCHOR_AVX2_ARM_NAME "avx2-linux"
#endif

/** @brief Limbs compared per AVX2 instruction. 256 bits holds eight 32 bit limbs. */
#define ANCHOR_AVX2_LANES 8u

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
 * @brief Whether two magnitudes are equal, eight limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          1 where every limb matches, 0 otherwise.
 * @note _mm256_cmpeq_epi32 sets a lane to all ones where the two limbs match, and the byte mask is
 *       therefore -1 exactly when all eight matched. Anything else means a difference is in the
 *       block and the values are not equal.
 */
static int avx2_magnitude_equal(const uint32_t *left, const uint32_t *right)
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
 * @note A vector reports that a block differs and not which limb differs first. The block holding
 *       the highest difference is found with the vector and then walked backward one limb at a time,
 *       which runs at most eight scalar steps once per comparison.
 */
static int avx2_magnitude_compare(const uint32_t *left, const uint32_t *right)
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
static int arm_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return 0;
    }
    return avx2_magnitude_equal(left->limb, right->limb);
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
    const int order = avx2_magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative, so the larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Counts agreeing places over a sorted run, through the AVX2 equality.
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
    ANCHOR_AVX2_ARM_NAME,
    arm_equal,
    arm_compare,
    arm_agreement,
};

const AnchorExactArm *anchor_exact_avx2_arm(void)
{
    return avx2_present() ? &AVX2_ARM : NULL;
}
