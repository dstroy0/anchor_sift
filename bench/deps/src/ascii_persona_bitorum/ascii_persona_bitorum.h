/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file ascii_persona_bitorum.h
 * @brief ASCII class membership: mask type, class list, and the ascii dispatch table.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Class membership as a bitmap lookup rather than a chain of range compares. One shift, one
 *       mask and one test answer any class, and the cost does not grow with how many ranges the
 *       class covers.
 * @note Covers code points 0 to 127 only. A byte of 0x80 or above is in no class here, which is
 *       what keeps the table sixteen bytes rather than thirty-two.
 */
#ifndef MMGR_ASCII_PERSONA_BITORUM_H
#define MMGR_ASCII_PERSONA_BITORUM_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Sixteen bytes holding one bit for each of the code points 0 to 127.
 *
 * @note A code point is located by shift and mask rather than by search. Code point n is bit
 *       (n & 7) of bits[n >> 3], so any class answers in the same three operations.
 */
typedef struct
{
    uint8_t bits[16]; /**< The bitmap, with code point 0 at the low bit of bits[0]. */
} MmgrAsciiMask;

/**
 * @brief Asserts an MmgrAsciiMask is exactly sixteen bytes.
 *
 * @note mmgr_ascii_in reads bits[byte >> 3] for every byte below 0x80, so all sixteen have to be
 *       there.
 * @note Sixteen reach code point 127 and no further, which is what leaves a byte of 0x80 or above in
 *       no class at all.
 */
EMBED_STATIC_ASSERT(sizeof(MmgrAsciiMask) == 16u, "an ASCII class mask is exactly 128 bits");

/**
 * @brief Character class selector, numbered from 0.
 *
 * @note MMGR_ASCII_CLASSES is the enumerator count, not a class. Passing it is out of range.
 */
typedef enum
{
    MMGR_ASCII_NUM = 0,   /**< '0' to '9'. */
    MMGR_ASCII_ALPHA,     /**< 'A' to 'Z' and 'a' to 'z'. */
    MMGR_ASCII_ALNUM,     /**< '0' to '9', 'A' to 'Z' and 'a' to 'z'. */
    MMGR_ASCII_UPPER,     /**< 'A' to 'Z'. */
    MMGR_ASCII_LOWER,     /**< 'a' to 'z'. */
    MMGR_ASCII_HEX,       /**< '0' to '9', 'A' to 'F' and 'a' to 'f'. */
    MMGR_ASCII_PUNCT,     /**< '!' to '/', ':' to '@', '[' to '`' and '{' to '~'. */
    MMGR_ASCII_SPACE,     /**< 9 to 13, and 32. */
    MMGR_ASCII_CTRL,      /**< 0 to 31, and 127. */
    MMGR_ASCII_PRINT,     /**< 32 to 126. */
    MMGR_ASCII_CLASSES    /**< Enumerator count, not a class. */
} MmgrAsciiClass;

/**
 * @brief Arguments to mmgr_ascii_in: the class and the byte to test.
 */
typedef struct
{
    const MmgrAsciiClass kind; /**< Class to test against, below MMGR_ASCII_CLASSES. */
    const uint8_t byte;        /**< Code point to look up; 0x80 and above are in no class. */
} AsciiCfg;

/**
 * @brief Type of the ascii dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the in member is at offset 0 and that the struct holds nothing else.
 */
typedef struct
{
    embed_bool (*in)(const AsciiCfg *args); /**< Whether a byte belongs to a class. */
} AsciiPersonaBitorumNs;
EMBED_TABLE_LAYOUT(AsciiPersonaBitorumNs, in);

/**
 * @brief Returns whether args->byte has its bit set in the kind bitmap.
 *
 * @param[in] args Class and byte to test [BORROWS].
 * @return         EMBED_TRUE when the bit is set, EMBED_FALSE otherwise.
 * @note Bytes 0x80 and above return EMBED_FALSE.
 * @warning args->kind must be below MMGR_ASCII_CLASSES, and nothing holds it there outside a
 *          MMGR_DEBUG_CHECKS build: the bitmap is indexed by it, so a byte under 0x80 then reads
 *          past the table.
 */
embed_bool mmgr_ascii_in(const AsciiCfg *args);

/**
 * @brief Dispatch table instance named ascii, whose in member is set to mmgr_ascii_in.
 */
EMBED_TABLE_STORAGE AsciiPersonaBitorumNs ascii EMBED_UNUSED = {
    .in = mmgr_ascii_in,
};

EMBED_END_DECLS

#endif
