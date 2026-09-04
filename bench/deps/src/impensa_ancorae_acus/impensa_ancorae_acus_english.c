/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file impensa_ancorae_acus_english.c
 * @brief Byte cost table weighted for English text.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note One of five files defining mmgr_ancorae_impensa. A build links exactly one of them.
 */
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"

/**
 * @brief Cost of each byte value, indexed by the byte itself.
 *
 * @note Lower means rarer in this corpus, and cellul_pick_rows keeps the lowest cost it finds.
 * @note The floor is 1. The ceiling 255 sits on the NUL and the space, so neither is ever chosen as a
 *       sieve offset.
 */
static const uint8_t s_impensa[256] = {
    255, 1,   1,   1,   1,   1,   1,   1,   1,   134, 191, 1,   1,   145, 1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   255, 100, 145, 1,   1,   1,   1,   158, 117, 117, 1,   1,
    177, 145, 180, 127, 145, 145, 145, 145, 145, 145, 145, 145, 145, 145, 122, 108, 1,   1,   1,   104, 1,   146,
    104, 121, 126, 155, 112, 111, 133, 142, 54,  87,  128, 116, 142, 143, 111, 34,  139, 140, 147, 117, 94,  107,
    50,  106, 37,  1,   1,   1,   1,   100, 1,   222, 180, 197, 202, 231, 187, 186, 208, 218, 130, 162, 204, 191,
    217, 218, 186, 110, 214, 216, 223, 193, 169, 183, 126, 181, 112, 1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1};

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
