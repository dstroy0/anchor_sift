/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_avx512.c
 * @brief The AVX-512 arm of the exact arithmetic, comparing sixteen 32 bit limbs per instruction.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @note No machine in this project has AVX-512. This arm has never been run. It is compiled for
 *       the target and its emitted instructions are read by maint/engine/verify_arm_asm.sh, which
 *       confirms zmm registers and vpcmpeqd against a mask. That rules out a silent fallback to
 *       scalar code. It says nothing about behavior, and the arm's name carries that.
 * @note The name reads avx512-unrun for exactly that reason. A row of results should not be able to
 *       show this arm beside a run one without the difference being visible in the row itself.
 * @note Detection asks for AVX-512F and AVX-512BW together, because the masked load the equality
 *       tail uses is a BW instruction and a part with F alone would fault on it.
 * @note AVX-512 comparison does not produce a vector of all-ones lanes the way AVX2 does. It writes
 *       a mask register, one bit per lane, and the comparison is against 0xFFFF for sixteen lanes.
 *       That is a different instruction shape and not a widening of the AVX2 one.
 * @note 128 limbs is eight full sixteen-lane blocks with no remainder. The masked tail below is not
 *       taken at the default width. It runs for a power-of-two width below 512 bits, whose limb
 *       count is not a multiple of sixteen, handled with a masked load instead of a scalar tail,
 *       since a mask is free on this instruction set and the tail would otherwise be a fraction of
 *       the work.
 */

#include "arm.h"

#if defined(ANCHOR_EXACT_HAVE_AVX512) && ANCHOR_EXACT_HAVE_AVX512

#include <immintrin.h>

#if defined(_MSC_VER)
#include <intrin.h>
/** @brief Set where this translation unit can ask the processor about AVX-512. */
#define ANCHOR_AVX512_CAN_DETECT 1
#elif defined(__GNUC__) || defined(__clang__)
#define ANCHOR_AVX512_CAN_DETECT 1
#else
#define ANCHOR_AVX512_CAN_DETECT 0
#endif

/** @brief Limbs compared per AVX-512 instruction. 512 bits holds sixteen 32 bit limbs. */
#define ANCHOR_AVX512_LANES 16u

/** @brief Every lane set. A full block of matching limbs compares equal to this. */
#define ANCHOR_AVX512_ALL ((__mmask16)0xFFFFu)

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
 * @brief Whether two magnitudes are equal, sixteen limbs at a time.
 *
 * @param[in] left  First magnitude [BORROWS].
 * @param[in] right Second magnitude [BORROWS].
 * @return          1 where every limb matches, 0 otherwise.
 * @note Walks from the top limb down. A value scaled to 1024 decimal digits carries hundreds of
 *       trailing zero digits. The low limbs are zero on both sides and hold no information.
 */
static int avx512_magnitude_equal(const uint32_t *left, const uint32_t *right)
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
        // compare equal. The mask is applied to the comparison and not to the load alone.
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
 * @note The mask marks which lanes differ and not which of them sits highest. The block holding the
 *       highest difference is found with the mask and then walked backward one limb at a time, which
 *       runs at most sixteen scalar steps, once per comparison.
 */
static int avx512_magnitude_compare(const uint32_t *left, const uint32_t *right)
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
static int arm_equal(const AnchorExactInteger *left, const AnchorExactInteger *right)
{
    if (left->sign != right->sign)
    {
        return 0;
    }
    return avx512_magnitude_equal(left->limb, right->limb);
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
    const int order = avx512_magnitude_compare(left->limb, right->limb);
    if (left->sign < 0)
    {
        // Both negative. The larger magnitude is the smaller value.
        return -order;
    }
    return order;
}

/**
 * @brief Counts agreeing places over a sorted run, through the AVX-512 equality.
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
    // The shared search, with only the equality test swapped. What is timed is the instruction
    // set and not a second algorithm.
    return anchor_exact_agreement_using(arm_equal, positions, values, count, lag);
}

/** @brief The arm as a driver sees it. Static storage. Returning its address is safe. */
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
