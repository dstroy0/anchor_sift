/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file impensa_ancorae_acus.h
 * @brief Byte cost lookup: its argument, the call, and the ancorae dispatch table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Five source files define the call, each with its own table. A build links exactly one.
 */
#ifndef MMGR_IMPENSA_ANCORAE_ACUS_H
#define MMGR_IMPENSA_ANCORAE_ACUS_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Argument for the cost lookup.
 */
typedef struct
{
    const uint8_t byte; /**< Byte value to look up. */
} AncoraeCfg;

/**
 * @brief Type of the ancorae dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the impensa member is at offset 0 and that the struct holds nothing else.
 */
typedef struct
{
    uint8_t (*impensa)(const AncoraeCfg *args); /**< Cost of one byte value. */
} ImpensaAncoraeAcusNs;
EMBED_TABLE_LAYOUT(ImpensaAncoraeAcusNs, impensa);

/**
 * @brief Returns the cost of args->byte under the table this build links.
 *
 * @param[in] args Byte to look up [BORROWS].
 * @return         The cost, 1 through 255.
 * @note Lower means the byte is rarer under the linked table. cellul_pick_rows keeps the lowest it
 *       finds.
 * @warning args is dereferenced without a null check, so it must point to a readable AncoraeCfg.
 * @warning The value depends on which of the five tables was linked, so it is not portable between builds.
 */
uint8_t mmgr_ancorae_impensa(const AncoraeCfg *args);

/**
 * @brief Dispatch table instance named ancorae, whose impensa member is mmgr_ancorae_impensa.
 */
EMBED_TABLE_STORAGE ImpensaAncoraeAcusNs ancorae EMBED_UNUSED = {
    .impensa = mmgr_ancorae_impensa,
};

EMBED_END_DECLS

#endif
