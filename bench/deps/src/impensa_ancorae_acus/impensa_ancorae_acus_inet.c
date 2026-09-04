/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file impensa_ancorae_acus_inet.c
 * @brief Byte cost table scoring only the characters an address is built from.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note One of five files defining mmgr_ancorae_impensa. A build links exactly one of them.
 */
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"

/**
 * @brief Cost of each byte value, indexed by the byte itself.
 *
 * @note Lower means rarer, and cellul_pick_rows keeps the lowest cost it finds.
 * @note 255 marks the NUL and the colon, so neither is ever chosen as a sieve offset.
 * @note Also above 1: the digits, 'a' to 'f', 'A' to 'F', and 37 '%', 46 '.', 47 '/', 91 '[', 93 ']'.
 */
static const uint8_t s_impensa[256] = {
    255, 1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 1,   1, 1, 1, 1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 137, 1, 1, 1, 1,   1,   1,   1,   1,   242, 178,
    240, 235, 231, 228, 228, 228, 228, 228, 228, 228, 255, 1, 1, 1,   1, 1, 1, 178, 178, 178, 178, 178, 178, 1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 1,   1, 1, 1, 1,   1,   160, 1,   160, 1,   1,
    1,   206, 206, 206, 206, 206, 206, 1,   1,   1,   1,   1, 1, 1,   1, 1, 1, 1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 1,   1, 1, 1, 1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 1,   1, 1, 1, 1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 1,   1, 1, 1, 1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 1,   1, 1, 1, 1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 1,   1, 1, 1, 1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1, 1, 1,   1, 1};

/**
 * @brief Argument type built by EMBED_CALL in mmgr_ancorae_impensa.
 *
 * @note Mirrors AncoraeCfg without its const qualifier.
 */
typedef struct
{
    uint8_t byte; /**< Byte value to look up. */
} AncoraeCtx;

/**
 * @brief Returns the table entry for args->byte.
 *
 * @param[in] args Byte to look up [BORROWS].
 * @return         The cost, 1 through 255.
 * @note The table holds 256 entries, so every uint8_t value indexes it in range.
 */
EMBED_INLINE uint8_t ancorae_impensa(const AncoraeCtx *args)
{
    return s_impensa[args->byte];
}

/**
 * @brief Copies args->byte into an AncoraeCtx and returns the table entry.
 *
 * @note Documented at the declaration in impensa_ancorae_acus.h.
 */
uint8_t mmgr_ancorae_impensa(const AncoraeCfg *args)
{
    return EMBED_CALL(ancorae_impensa, AncoraeCtx, .byte = args->byte);
}
