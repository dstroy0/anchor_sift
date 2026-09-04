/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file clz.h
 * @brief Leading and trailing zero counts: the argument type, the two calls, and the clz dispatch
 *        table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note A zero count is how a scan turns a lane mask into a lane index, so these sit under the SWAR
 *       walks rather than being a general utility.
 * @note Both run branchless and in a fixed number of steps, so a caller pays the same whatever the
 *       value is. That is the reason they are written out rather than reached through a builtin,
 *       which is absent on some targets and a call on others.
 * @warning Neither distinguishes a value of 0 from a value with one bit set at the end it counts
 *          from. A caller that can be handed 0 tests for it first.
 */
#ifndef MMGR_CLZ_H
#define MMGR_CLZ_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Argument for both clz calls: the value to count zeros in.
 */
typedef struct
{
    const embed_u64 val; /**< Value whose leading or trailing zeros are counted. */
} ClzCfg;

/**
 * @brief Type of the clz dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the two members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 */
typedef struct
{
    embed_iword (*lead)(const ClzCfg *args);  /**< Leading zero count of val. */
    embed_iword (*trail)(const ClzCfg *args); /**< Trailing zero count of val. */
} ClzNs;
EMBED_TABLE_LAYOUT(ClzNs, lead, trail);

/**
 * @brief Counts the zero bits above the highest set bit of args->val.
 *
 * @param[in] args Value to measure [BORROWS].
 * @return         Leading zero count, 0 through 63.
 * @note Runs in a fixed number of steps, none of which branches on the value.
 * @warning An args->val of 0 returns 63, the same answer as an args->val of 1.
 */
embed_iword mmgr_clz_lead(const ClzCfg *args);

/**
 * @brief Counts the zero bits below the lowest set bit of args->val.
 *
 * @param[in] args Value to measure [BORROWS].
 * @return         Trailing zero count, 0 through 63.
 * @note Runs in a fixed number of steps, none of which branches on the value.
 * @warning An args->val of 0 returns 63, the same answer as an args->val of 2^63.
 */
embed_iword mmgr_clz_trail(const ClzCfg *args);

/**
 * @brief Dispatch table instance named clz, with each member set to its mmgr_clz_ function.
 */
EMBED_TABLE_STORAGE ClzNs clz EMBED_UNUSED = {
    .lead = mmgr_clz_lead,
    .trail = mmgr_clz_trail,
};

EMBED_END_DECLS

#endif
