/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_steer_arm.c
 * @brief The portable steering scan, which every vectorized arm is graded against.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @note No intrinsic and no compiler extension, so this builds anywhere a C11 compiler runs and is
 *       the arm a disagreement is resolved against. A vectorized arm that differs from this one is
 *       wrong, whatever it measures.
 */

#include "anchor_steer_arm.h"

uint64_t anchor_steer_scan_calls = 0u;
uint64_t anchor_steer_wide_calls = 0u;

void anchor_steer_scan_counters_reset(void)
{
    anchor_steer_scan_calls = 0u;
    anchor_steer_wide_calls = 0u;
}

const AnchorSteerArm *anchor_steer_best_arm(void)
{
#if defined(ANCHOR_STEER_HAVE_AVX2) && ANCHOR_STEER_HAVE_AVX2
    {
        const AnchorSteerArm *wide = anchor_steer_avx2_arm();
        if (wide != NULL)
        {
            return wide;
        }
    }
#endif
    return anchor_steer_portable_arm();
}

size_t anchor_steer_truthy_after_portable(const uint8_t *corpus, size_t alignments,
                                          const uint8_t *alive, uint8_t wanted, size_t offset)
{
    anchor_steer_scan_calls += 1u;

    if ((corpus == NULL) || (alive == NULL) || (alignments == 0u))
    {
        return 0u;
    }

    size_t standing = 0u;
    for (size_t at = 0u; at < alignments; at += 1u)
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

const AnchorSteerArm *anchor_steer_portable_arm(void)
{
    static const AnchorSteerArm arm = { "portable", anchor_steer_truthy_after_portable };

    return &arm;
}
