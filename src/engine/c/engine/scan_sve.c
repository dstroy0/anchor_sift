/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file scan_sve.c
 * @brief The steering scan under SVE, at whatever vector length the part turns out to have.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * THE SAME QUESTION AVX2 ANSWERS, WITHOUT A FIXED WIDTH. Held at one needle offset, does
 * `corpus[at + offset]` equal `needle[offset]` for consecutive `at`. The needle byte broadcasts
 * once, the corpus side is a sliding window at unit stride, and the survivor mask enters as the
 * alignments still standing. SVE answers a vector's worth of those per compare, and the vector is
 * as wide as the part.
 *
 * WHAT THIS ARM IS NOT ALLOWED TO DO. It returns the portable arm's count or it has a defect. The
 * value is an integer count of alignments and the two arms agree exactly or one is wrong. That is
 * the contract AnchorSteerEngine carries, the same one the exact arms carry in no_rounding.
 *
 * @note No part in this project has SVE. The Raspberry Pi 5 is a Cortex-A76, NEON only. This arm
 *       has never been run. It is compiled for armv8.2-a+sve and its emitted instructions are read by
 *       maint/engine/verify_arm_asm.sh, which confirms the predicated forms. That rules out a scalar
 *       fallback. It says nothing about behavior, and the name reads sve-unrun for that reason.
 * @note SVE has no fixed vector length. svcntb() answers how many byte lanes this part carries and
 *       the loop is written around a predicate. No lane count appears here and the tail needs no
 *       separate scalar loop: svwhilelt_b8 covers only the lanes that exist and the count comes from
 *       svcntp_b8 over the surviving predicate.
 * @note Detection reads the hardware capability word Linux exposes, never executing an SVE
 *       instruction to see whether it faults. There is no cpuid on ARM: a part's features come from
 *       the kernel, and on anything other than Linux this arm reports itself absent instead of
 *       guessing.
 */

#include "anchor_sift.h"

#include <arm_sve.h>

#if defined(__linux__)
#include <sys/auxv.h>
/** @brief Set where this translation unit can ask the kernel about SVE. */
#define ANCHOR_STEER_SVE_CAN_DETECT 1
#ifndef HWCAP_SVE
/** @brief The SVE bit in AT_HWCAP, spelled here where the running headers predate it. */
#define HWCAP_SVE (1 << 22)
#endif
#else
#define ANCHOR_STEER_SVE_CAN_DETECT 0
#endif

/**
 * @brief Whether this part carries SVE.
 *
 * @return 1 where the kernel reports SVE, 0 where it does not or cannot be asked.
 */
static int steer_sve_present(void)
{
#if ANCHOR_STEER_SVE_CAN_DETECT
    return ((getauxval(AT_HWCAP) & (unsigned long)HWCAP_SVE) != 0ul) ? 1 : 0;
#else
    return 0;
#endif
}

size_t anchor_steer_truthy_after_sve(const uint8_t *corpus, size_t alignments,
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

    const uint64_t total = (uint64_t)alignments;
    uint64_t standing = 0u;

    for (uint64_t at = 0u; at < total; at += svcntb())
    {
        /* The predicate covers only the lanes that exist. The tail needs no separate loop and the
         * predicated load reads no byte past the alignment count. */
        const svbool_t live = svwhilelt_b8(at, total);
        const svuint8_t window = svld1_u8(live, corpus + at + offset);
        const svuint8_t standing_bytes = svld1_u8(live, alive + at);

        const svbool_t agrees = svcmpeq_n_u8(live, window, wanted);

        /* An alive flag is zero or non-zero. The standing lanes are the ones not equal to zero.
         * Testing this way. */
        const svbool_t alive_mask = svcmpne_n_u8(live, standing_bytes, 0u);

        standing += (uint64_t)svcntp_b8(live, svand_b_z(live, agrees, alive_mask));
    }

    return (size_t)standing;
}

const AnchorSteerEngine *anchor_steer_sve_engine(void)
{
    static const AnchorSteerEngine engine = {"sve-unrun", anchor_steer_truthy_after_sve};

    if (steer_sve_present() == 0)
    {
        return NULL;
    }
    return &engine;
}
