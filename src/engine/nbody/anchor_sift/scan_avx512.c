/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file scan_avx512.c
 * @brief The steering scan under AVX-512, sixty-four alignments per compare.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * THE SAME QUESTION AVX2 ANSWERS, TWICE THE WIDTH. Held at one needle offset, does
 * `corpus[at + offset]` equal `needle[offset]` for consecutive `at`. The needle byte broadcasts
 * once, the corpus side is a sliding window at unit stride, and the survivor mask enters as the
 * alignments still standing. AVX-512 answers sixty-four of those in one compare.
 *
 * WHAT THIS ARM IS NOT ALLOWED TO DO. It returns the portable arm's count or it has a defect. The
 * value is an integer count of alignments and the two arms agree exactly or one is wrong. That is
 * the contract AnchorSteerEngine carries, the same one the exact arms carry in no_rounding.
 *
 * @note No machine in this project has AVX-512. This arm has never been run. It is compiled for
 *       the target and its emitted instructions are read by maint/engine/verify_arm_asm.sh, which
 *       confirms zmm registers and vpcmpeqb against a mask. That rules out a silent fallback to
 *       scalar code. It says nothing about behavior, and the name reads avx512-unrun for that reason.
 * @note AVX-512 comparison writes a mask register, one bit per lane. The count is a population
 *       count over the AND of two masks: where the corpus agrees, and where the alignment stands.
 *       That is a different instruction shape from the AVX2 movemask and not a widening of it.
 * @note Detection asks for AVX-512F and AVX-512BW together. The byte compare and the byte test are
 *       BW instructions, and a part with F alone would fault on them.
 * @note The tail below sixty-four is finished scalar, the same code the portable arm runs. A masked
 *       tail is cheap on this instruction set, and the scalar one is chosen to keep every scan arm
 *       the same shape, since an unrun arm is for correctness and not for the tail's cost.
 */

#include "anchor_sift.h"

#include <immintrin.h>

#if defined(_MSC_VER)
#include <intrin.h>
/** @brief Set where this translation unit can ask the processor about AVX-512. */
#define ANCHOR_STEER_AVX512_CAN_DETECT 1
#elif defined(__GNUC__) || defined(__clang__)
#define ANCHOR_STEER_AVX512_CAN_DETECT 1
#else
#define ANCHOR_STEER_AVX512_CAN_DETECT 0
#endif

/** @brief Alignments one AVX-512 register answers at once. */
#define ANCHOR_STEER_LANES 64u

/**
 * @brief Set bits in a 64-bit mask.
 *
 * @param[in] bits Mask returned by a byte compare.
 * @return         How many lanes agreed.
 * @note Both arms defined. MSVC spells the intrinsic __popcnt64 and GCC and Clang spell it
 *       __builtin_popcountll, and neither name exists on the other compiler.
 */
static size_t steer_popcount64(uint64_t bits)
{
#if defined(_MSC_VER)
    return (size_t)__popcnt64(bits);
#else
    return (size_t)__builtin_popcountll(bits);
#endif
}

/**
 * @brief Whether this processor carries the AVX-512 subsets this arm issues.
 *
 * @return 1 where AVX-512F and AVX-512BW are both present, 0 otherwise.
 * @note Leaf 7 subleaf 0, EBX: bit 16 is AVX-512F and bit 30 is AVX-512BW. The leaf exists only
 *       where leaf 0 reports a maximum of at least 7, which is checked before it is read.
 */
static int steer_avx512_present(void)
{
#if !ANCHOR_STEER_AVX512_CAN_DETECT
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

size_t anchor_steer_truthy_after_avx512(const uint8_t *corpus, size_t alignments,
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

    const __m512i broadcast = _mm512_set1_epi8((char)wanted);
    size_t standing = 0u;
    size_t at = 0u;

    for (; (at + ANCHOR_STEER_LANES) <= alignments; at += ANCHOR_STEER_LANES)
    {
        /* Unaligned loads on purpose. The corpus window starts at an arbitrary offset and forcing
         * alignment would mean copying, which costs more than the load does. */
        const __m512i window = _mm512_loadu_si512((const void *)(corpus + at + offset));
        const __m512i standing_bytes = _mm512_loadu_si512((const void *)(alive + at));

        const __mmask64 agrees = _mm512_cmpeq_epi8_mask(window, broadcast);

        /* An alive flag is zero or non-zero. The mask of alignments still standing is the lanes
         * whose byte ANDs with itself to a non-zero, which is every lane that is not zero. Testing
         * this way and not against one keeps it correct if a caller stores a flag other than
         * one. */
        const __mmask64 alive_mask = _mm512_test_epi8_mask(standing_bytes, standing_bytes);

        standing += steer_popcount64((uint64_t)(agrees & alive_mask));
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

const AnchorSteerEngine *anchor_steer_avx512_engine(void)
{
    static const AnchorSteerEngine engine = {"avx512-unrun", anchor_steer_truthy_after_avx512};

    if (steer_avx512_present() == 0)
    {
        return NULL;
    }
    return &engine;
}
