/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file scan_avx2.c
 * @brief The steering scan under AVX2, thirty-two alignments per compare.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * WHY THIS SHAPE VECTORIZES AT ALL. Every hot loop in the steering engine asks the same question:
 * held at one needle offset, does `corpus[at + offset]` equal `needle[offset]`, for consecutive
 * `at`. The needle byte is fixed across the whole sweep. It broadcasts once. The corpus side is a
 * sliding window read at unit stride. That is one wide load against one broadcast register, and it
 * answers thirty-two alignments in the instruction where the portable arm answers one.
 *
 * The survivor mask enters the same way. An alignment already refuted contributes nothing. The
 * count is a population count over the AND of two masks: where the corpus agrees, and where the
 * alignment was still standing.
 *
 * WHAT THIS ARM IS NOT ALLOWED TO DO. It returns the portable arm's count or it has a defect. There
 * is no tolerance, no reordering that changes an answer, and no fast path that is right most of the
 * time: the value is an integer count of alignments and the two arms agree exactly or one is wrong.
 * That is the contract base/no_rounding/arm.h states for the exact arms and it is kept here for the same
 * reason.
 *
 * @note Asks the processor at run time and not the build. A binary compiled with AVX2 available
 *       still runs on machines without it, and calling in would raise an illegal instruction.
 * @note Two detection paths, both arms of the gate defined. MSVC has no __builtin_cpu_supports and
 *       takes __cpuidex; GCC and Clang have the builtin.
 * @note The tail below thirty-two is finished scalar and not masked. A masked tail costs more to
 *       get right than it saves at this width, and the scalar remainder is the same code the
 *       portable arm runs.
 */

#include "anchor_sift.h"

#include <immintrin.h>

#if defined(_MSC_VER)
#include <intrin.h>
/** @brief Set where this translation unit can ask the processor about AVX2. */
#define ANCHOR_STEER_AVX2_CAN_DETECT 1
#elif defined(__GNUC__) || defined(__clang__)
#define ANCHOR_STEER_AVX2_CAN_DETECT 1
#else
#define ANCHOR_STEER_AVX2_CAN_DETECT 0
#endif

/** @brief Alignments one AVX2 register answers at once. */
#define ANCHOR_STEER_LANES 32u

/**
 * @brief Set bits in a 32-bit mask.
 *
 * @param[in] bits Mask returned by a movemask.
 * @return         How many lanes agreed.
 * @note Both arms defined. MSVC spells the intrinsic __popcnt and GCC and Clang spell it
 *       __builtin_popcount, and neither name exists on the other compiler.
 */
static size_t steer_popcount(unsigned int bits)
{
#if defined(_MSC_VER)
    return (size_t)__popcnt(bits);
#else
    return (size_t)__builtin_popcount(bits);
#endif
}

/**
 * @brief Whether this processor carries AVX2.
 *
 * @return 1 where AVX2 is present, 0 otherwise.
 */
static int steer_avx2_present(void)
{
#if !ANCHOR_STEER_AVX2_CAN_DETECT
    return 0;
#elif defined(_MSC_VER)
    int leaves[4];

    __cpuid(leaves, 0);
    if (leaves[0] < 7)
    {
        return 0;
    }
    __cpuidex(leaves, 7, 0);

    /* Leaf 7 sub-leaf 0, EBX bit 5. */
    return ((leaves[1] & (1 << 5)) != 0) ? 1 : 0;
#else
    /* The builtin resolves against the processor at run time and needs no cpuid handling here. */
    return __builtin_cpu_supports("avx2") ? 1 : 0;
#endif
}

size_t anchor_steer_truthy_after_avx2(const uint8_t *corpus, size_t alignments,
                                      const uint8_t *alive, uint8_t wanted, size_t offset)
{
    /* Counted before the argument check. A caller passing nothing still records that this arm
     * was the one asked. The claim the counters carry is which arm RAN and not what it returned. */
    anchor_steer_scan_calls += 1u;
    anchor_steer_wide_calls += 1u;

    if ((corpus == NULL) || (alive == NULL) || (alignments == 0u))
    {
        return 0u;
    }

    const __m256i broadcast = _mm256_set1_epi8((char)wanted);
    const __m256i zero = _mm256_setzero_si256();
    size_t standing = 0u;
    size_t at = 0u;

    for (; (at + ANCHOR_STEER_LANES) <= alignments; at += ANCHOR_STEER_LANES)
    {
        /* Unaligned loads on purpose. The corpus window starts at an arbitrary offset and forcing
         * alignment would mean copying, which costs more than the load does. */
        const __m256i window = _mm256_loadu_si256((const __m256i *)(corpus + at + offset));
        const __m256i standing_bytes = _mm256_loadu_si256((const __m256i *)(alive + at));

        const __m256i agrees = _mm256_cmpeq_epi8(window, broadcast);

        /* An alive flag is zero or non-zero. The mask of alignments still standing is the
         * complement of "equals zero". Testing against zero and complementing instead of testing
         * against one keeps this correct if a caller ever stores a flag other than one. */
        const __m256i refuted = _mm256_cmpeq_epi8(standing_bytes, zero);
        const __m256i alive_mask = _mm256_andnot_si256(refuted, _mm256_set1_epi8((char)0xFF));

        const unsigned int bits = (unsigned int)_mm256_movemask_epi8(
            _mm256_and_si256(agrees, alive_mask));
        standing += steer_popcount(bits);
    }

    for (; at < alignments; at += 1u)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (corpus[at + offset] == wanted)
        {
            standing += 1u;
        }
    }
    return standing;
}

const AnchorSteerEngine *anchor_steer_avx2_engine(void)
{
    static const AnchorSteerEngine engine = {"avx2", anchor_steer_truthy_after_avx2};

    if (steer_avx2_present() == 0)
    {
        return NULL;
    }
    return &engine;
}
