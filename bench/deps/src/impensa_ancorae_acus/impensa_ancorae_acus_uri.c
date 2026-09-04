/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file impensa_ancorae_acus_uri.c
 * @brief Byte cost table scoring letters, digits and URI punctuation.
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
 * @note 255 marks the NUL and the slash, so neither is ever chosen as a sieve offset.
 * @note The space sits at 1 here, where the two text tables give it 255.
 * @note Every initializer is a plain int constant from 1 to 255, so narrowing to the uint8_t element keeps its value.
 */
static const uint8_t s_impensa[256] = {
    255, 1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   1,   107, 1,   155, 107, 188, 199, 107, 107, 107, 107, 163,
    144, 225, 244, 255, 201, 201, 201, 201, 201, 201, 201, 201, 201, 201, 218, 136, 1,   207, 1,   193, 144, 162,
    117, 136, 141, 172, 126, 124, 148, 158, 63,  99,  143, 130, 158, 159, 124, 42,  154, 156, 164, 131, 106, 121,
    60,  119, 45,  93,  1,   93,  1,   188, 1,   230, 184, 203, 208, 239, 193, 192, 215, 226, 131, 166, 211, 197,
    225, 226, 191, 109, 222, 223, 231, 198, 173, 188, 127, 186, 112, 1,   1,   1,   136, 1,   1,   1,   1,   1,
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
