/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm_portable.c
 * @brief Presents the portable C11 operations as an arm, letting a driver hold it in one table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note The functions are the ones in exact_limbs.c and are not reimplemented here. This file is a
 *       table of pointers to them. The reference arm and the reference implementation can never
 *       become two different things that way.
 */

#include "exact_arm.h"

/** @brief The arm as a driver sees it. Static storage, so returning its address is safe. */
static const AnchorExactArm PORTABLE_ARM = {
    "portable",
    anchor_exact_equal,
    anchor_exact_compare,
    anchor_exact_agreement,
};

const AnchorExactArm *anchor_exact_portable_arm(void)
{
    return &PORTABLE_ARM;
}
