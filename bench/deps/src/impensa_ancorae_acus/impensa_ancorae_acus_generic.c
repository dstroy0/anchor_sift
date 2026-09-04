/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file impensa_ancorae_acus_generic.c
 * @brief Byte cost table with no floor at 1, where every byte value carries a cost.
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
 * @note 255 marks the NUL and the space, so neither is ever chosen as a sieve offset.
 * @note Bytes 128 through 255 all carry 107, so no high byte is preferred over another.
 * @note The entries carry no U suffix. Each is within 0 to 255, so the initializer stores it as a
 *       uint8_t unchanged.
 */
static const uint8_t s_impensa[256] = {
    255, 136, 136, 136, 136, 136, 136, 136, 136, 163, 199, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 136,
    136, 136, 136, 136, 136, 136, 136, 136, 136, 136, 255, 169, 169, 169, 169, 169, 169, 169, 169, 169, 169, 169,
    169, 169, 169, 169, 193, 193, 193, 193, 193, 193, 193, 193, 193, 193, 169, 169, 169, 169, 169, 169, 169, 173,
    128, 147, 152, 183, 136, 135, 159, 169, 74,  110, 154, 141, 169, 170, 135, 53,  165, 167, 175, 142, 117, 132,
    70,  130, 56,  169, 169, 169, 169, 169, 169, 230, 184, 203, 208, 239, 193, 192, 215, 226, 131, 166, 211, 197,
    225, 226, 191, 109, 222, 223, 231, 198, 173, 188, 127, 186, 112, 169, 169, 169, 169, 136, 107, 107, 107, 107,
    107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107,
    107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107,
    107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107,
    107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107,
    107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107,
    107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107};

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
 * @return         The cost, 53 through 255 in this table.
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
