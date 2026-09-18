/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file scan_neon.c
 * @brief The steering scan under NEON, sixteen alignments per compare.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * THE SAME QUESTION AVX2 ANSWERS, ONE ARM OVER. Held at one needle offset, does
 * `corpus[at + offset]` equal `needle[offset]` for consecutive `at`. The needle byte broadcasts
 * once, the corpus side is a sliding window at unit stride, and the survivor mask enters as the
 * alignments still standing. A NEON register is 128 bits and answers sixteen of those in one compare.
 *
 * WHAT THIS ARM IS NOT ALLOWED TO DO. It returns the portable arm's count or it has a defect. The
 * value is an integer count of alignments and the two arms agree exactly or one is wrong. That is
 * the contract AnchorSteerEngine carries, the same one the exact arms carry in no_rounding.
 *
 * @note Written for the Raspberry Pi 5, a Cortex-A76 at aarch64. This arm runs and its name has
 *       no unrun tag. NEON is mandatory in the base aarch64 architecture. A build that reached
 *       here can always run it and there is nothing to detect.
 * @note There is no movemask on NEON. A byte compare sets a lane to all ones where it agrees, the
 *       alive lanes enter the same way, and the count is taken by shifting each surviving lane down
 *       to one and adding the sixteen lanes across the register. The across-vector add is an aarch64
 *       form, which is the architecture this arm targets.
 * @note The tail below sixteen is finished scalar, the same code the portable arm runs.
 */

#include "anchor_sift.h"

#include <arm_neon.h>

/** @brief Alignments one NEON register answers at once. */
#define ANCHOR_STEER_LANES 16u

size_t anchor_steer_truthy_after_neon(const uint8_t *corpus, size_t alignments,
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

    const uint8x16_t broadcast = vdupq_n_u8(wanted);
    const uint8x16_t zero = vdupq_n_u8(0u);
    size_t standing = 0u;
    size_t at = 0u;

    for (; (at + ANCHOR_STEER_LANES) <= alignments; at += ANCHOR_STEER_LANES)
    {
        const uint8x16_t window = vld1q_u8(corpus + at + offset);
        const uint8x16_t standing_bytes = vld1q_u8(alive + at);

        const uint8x16_t agrees = vceqq_u8(window, broadcast);

        /* An alive flag is zero or non-zero. vceqq against zero marks the refuted lanes, and the
         * complement marks the standing ones. Complementing rather than comparing against one keeps
         * this correct if a caller ever stores a flag other than one. */
        const uint8x16_t alive_mask = vmvnq_u8(vceqq_u8(standing_bytes, zero));

        /* A surviving lane is all ones. Shifting it down to one and adding the sixteen lanes gives
         * the block's count, which cannot exceed sixteen and so does not overflow the byte the
         * across-vector add returns. */
        const uint8x16_t hits = vshrq_n_u8(vandq_u8(agrees, alive_mask), 7);
        standing += (size_t)vaddvq_u8(hits);
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

const AnchorSteerEngine *anchor_steer_neon_engine(void)
{
    static const AnchorSteerEngine engine = { "neon", anchor_steer_truthy_after_neon };

    /* NEON is part of the base aarch64 architecture. A build that got here can always run it. */
    return &engine;
}
