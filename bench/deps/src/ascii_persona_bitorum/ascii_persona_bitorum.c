/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file ascii_persona_bitorum.c
 * @brief ASCII class membership, read from the 128-bit s_class bitmaps.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note The whole module is one table lookup. The bitmaps are emitted as initialized data, so
 *       nothing runs before main and a membership test costs a shift, a mask and a compare whatever
 *       the class covers.
 * @note Reaches nothing outside config.
 */
#include "ascii_persona_bitorum/ascii_persona_bitorum.h"

/**
 * @brief One 128-bit membership bitmap per MmgrAsciiClass value.
 *
 * @note Indexed by MmgrAsciiClass. Code point n is bit (n & 7) of byte (n >> 3).
 * @note Worked through, MMGR_ASCII_NUM holds 0xFF at byte 6 and 0x03 at byte 7. Byte 6 carries code
 *       points 48 through 55, which is '0' to '7', and the low two bits of byte 7 carry 56 and 57,
 *       which is '8' and '9'. Every row below reads the same way, so none of them has to be taken
 *       on trust.
 * @note Sixteen bytes reach code point 127 and no further, which is what leaves a byte at 0x80 or
 *       above with no row it could be found in.
 */
static const MmgrAsciiMask s_class[MMGR_ASCII_CLASSES] = {
    [MMGR_ASCII_NUM] = {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                         0x00}},
    [MMGR_ASCII_ALPHA] = {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0xFF, 0xFF, 0x07, 0xFE, 0xFF, 0xFF,
                           0x07}},
    [MMGR_ASCII_ALNUM] = {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x03, 0xFE, 0xFF, 0xFF, 0x07, 0xFE, 0xFF, 0xFF,
                           0x07}},
    [MMGR_ASCII_UPPER] = {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0xFF, 0xFF, 0x07, 0x00, 0x00, 0x00,
                           0x00}},
    [MMGR_ASCII_LOWER] = {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFE, 0xFF, 0xFF,
                           0x07}},
    [MMGR_ASCII_HEX] = {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x03, 0x7E, 0x00, 0x00, 0x00, 0x7E, 0x00, 0x00,
                         0x00}},
    [MMGR_ASCII_PUNCT] = {{0x00, 0x00, 0x00, 0x00, 0xFE, 0xFF, 0x00, 0xFC, 0x01, 0x00, 0x00, 0xF8, 0x01, 0x00, 0x00,
                           0x78}},
    [MMGR_ASCII_SPACE] = {{0x00, 0x3E, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                           0x00}},
    [MMGR_ASCII_CTRL] = {{0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                          0x80}},
    [MMGR_ASCII_PRINT] = {{0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                           0x7F}},
};

/**
 * @brief Argument type built by EMBED_CALL in mmgr_ascii_in.
 *
 * @note Fields match AsciiCfg, without its const qualifiers.
 */
typedef struct
{
    MmgrAsciiClass kind; /**< Class whose bitmap is read. */
    uint8_t byte;        /**< Code point to look up. */
} AsciiCtx;

/**
 * @brief Returns whether args->byte has its bit set in s_class[args->kind].
 *
 * @param[in] args Class and byte to test [BORROWS].
 * @return         EMBED_TRUE when the bit is set, EMBED_FALSE otherwise.
 * @note Bytes 0x80 and above return EMBED_FALSE without reading s_class.
 * @warning args->kind must be below MMGR_ASCII_CLASSES, and nothing holds it there outside a
 *          MMGR_DEBUG_CHECKS build: a byte under 0x80 then reads past s_class.
 */
EMBED_INLINE embed_bool ascii_in(const AsciiCtx *args)
{
    MMGR_ASSERT(args->kind < MMGR_ASCII_CLASSES, "no such character class");

    const MmgrAsciiMask *const entry = &s_class[args->kind];

    // The byte test comes first and && stops there. A byte of 0x80 or above would index bits[16] or
    // past it, outside the sixteen the mask holds. Explicit cast narrows the int result of && to
    // the embed_bool container
    return (embed_bool)((args->byte < 0x80u) && (((entry->bits[args->byte >> 3] >> (args->byte & 7u)) & 1u) != 0u));
}

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_ascii_ and ascii_ prefixes, which the two share.
 * @param[in] ...         Initializers for the AsciiCtx literal, written in terms of args.
 * @note Four of EMBED_ENTRY's six arguments are the same at every entry in this module, so they
 *       are bound once here and each entry below states only what differs.
 */
#define ASCII_ENTRY(ReturnType_, name_, ...)                                                                           \
    EMBED_ENTRY(mmgr_ascii_, ascii_, AsciiCtx, AsciiCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in ascii_persona_bitorum.h.
 */
ASCII_ENTRY(embed_bool, in, .kind = args->kind, .byte = args->byte)
