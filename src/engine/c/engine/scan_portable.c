/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file scan_portable.c
 * @brief The steering scan in portable C11, the reference every other scan arm is graded against.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * ONE PRIMITIVE. Held at one needle offset, count the alignments still standing whose corpus byte at
 * that offset equals the needle byte the level is testing. That is the whole operation a planner asks
 * of a scan engine, and it is the same question every wide arm answers faster.
 *
 * @note THE REFERENCE. This arm uses no intrinsic and no compiler extension, so it builds anywhere a
 *       C11 compiler runs, and every other scan arm returns the same count or has a defect. That is
 *       the contract AnchorSteerEngine carries, the same one the exact arms carry in no_rounding.
 * @note It counts a scan call and never a wide call. anchor_steer_scan_calls and
 *       anchor_steer_wide_calls are defined in anchor_sift.c and declared in the header; a wide arm
 *       counts both, so wide over total is the share served on the vector path.
 */

#include "anchor_sift.h"

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

const AnchorSteerEngine *anchor_steer_portable_engine(void)
{
    static const AnchorSteerEngine engine = { "portable", anchor_steer_truthy_after_portable };

    return &engine;
}
