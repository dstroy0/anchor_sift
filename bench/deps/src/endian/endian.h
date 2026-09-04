/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file endian.h
 * @brief Endian reads and writes: the width enum, the argument type, the five entry points and the two
 *        order tables.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note parva_extremitas moves bytes in the host's own order and magna_extremitas in the reverse of it.
 *       Nothing here consults MMGR_HW_BIG_ENDIAN, so the two names hold on a little endian host and
 *       stand for the opposite orders on a big endian one.
 * @note The two tables share the table type and the rev entry. Their wr and rd differ, since one pair
 *       reverses and the other does not.
 */
#ifndef MMGR_ENDIAN_H
#define MMGR_ENDIAN_H

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Width of one endian read or write, counted in bytes.
 *
 * @note The enumerators are the byte counts themselves, so the implementation switches on them directly.
 * @note Packed to one byte. mmgr_types.h asserts that packing reaches the compiler.
 * @warning Nothing holds a value to these three. The switches in endian.c test 2 and 4 and take
 *          everything else on the default arm, which moves eight bytes.
 */
typedef enum EMBED_ENUM_PACKED
{
    MMGR_ENDIAN_16 = 2, /**< Two bytes. */
    MMGR_ENDIAN_32 = 4, /**< Four bytes. */
    MMGR_ENDIAN_64 = 8, /**< Eight bytes. */
} mmgr_endian_width;

/**
 * @brief Arguments for the endian calls, where each call reads only the members it needs.
 *
 * @note wr reads dst, val and width. rd reads src and width. rev reads val and width.
 * @note width is what bounds both pointers. wr and rd touch that many bytes of the one they use, or
 *       eight when width is not one of the mmgr_endian_width enumerators. rev reads neither pointer.
 * @warning Neither pointer is checked. endian.c passes them straight to proximus_operor, which
 *          dereferences them with no test and no assertion.
 */
typedef struct
{
    uint8_t *const dst;            /**< Destination for wr [BORROWS]. */
    const uint8_t *const src;      /**< Source for rd [BORROWS]. */
    const uint64_t val;            /**< Value for wr, or the value rev reverses. */
    const mmgr_endian_width width; /**< Bytes the call moves. */
} EndianCfg;

/**
 * @brief Type of an endian dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the three members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note Two instances share this type, one per byte order. Which one a call goes through is what sets
 *       the order, and no member takes it as an argument.
 * @note wr hands back args->width as it was given. The other two return the value they produced.
 */
typedef struct
{
    size_t (*wr)(const EndianCfg *args);    /**< Writes width bytes of val to dst in the table's order. */
    uint64_t (*rd)(const EndianCfg *args);  /**< Reads width bytes from src in the table's order. */
    uint64_t (*rev)(const EndianCfg *args); /**< Reverses val at width bytes. */
} EndianNs;
EMBED_TABLE_LAYOUT(EndianNs, wr, rd, rev);

/**
 * @brief Writes args->width bytes of args->val to args->dst without reversing them.
 *
 * @param[in,out] args Destination, value and width [BORROWS].
 * @return             args->width.
 * @warning args->dst must be writable for args->width bytes. Nothing checks it. endian.c hands it to
 *          proxim.put16, put32 or put64, each of which stores through it with no test.
 * @warning args->width must be one of the mmgr_endian_width enumerators. Any other value writes eight
 *          bytes.
 */
size_t mmgr_wr_le(const EndianCfg *args);

/**
 * @brief Reads args->width bytes from args->src without reversing them.
 *
 * @param[in] args Source and width [BORROWS].
 * @return         The value read, in the low args->width bytes.
 * @warning args->src must be readable for args->width bytes. Nothing checks it. endian.c hands it to
 *          proxim.load16, load32 or load64, each of which reads through it with no test.
 * @warning args->width must be one of the mmgr_endian_width enumerators. Any other value reads eight
 *          bytes.
 */
uint64_t mmgr_rd_le(const EndianCfg *args);

/**
 * @brief Reverses args->val, then writes args->width bytes of it to args->dst.
 *
 * @param[in,out] args Destination, value and width [BORROWS].
 * @return             args->width.
 * @warning args->dst must be writable for args->width bytes. Nothing checks it. endian.c hands it to
 *          proxim.put16, put32 or put64, each of which stores through it with no test.
 * @warning args->width must be one of the mmgr_endian_width enumerators. Any other value writes eight
 *          bytes. One above eight wraps the reversal's shift count, and a width of 0 shifts by 64,
 *          which is undefined.
 */
size_t mmgr_wr_be(const EndianCfg *args);

/**
 * @brief Reads args->width bytes from args->src, then reverses them.
 *
 * @param[in] args Source and width [BORROWS].
 * @return         The reversed value, in the low args->width bytes.
 * @warning args->src must be readable for args->width bytes. Nothing checks it. endian.c hands it to
 *          proxim.load16, load32 or load64, each of which reads through it with no test.
 * @warning args->width must be one of the mmgr_endian_width enumerators. Any other value reads eight
 *          bytes. One above eight wraps the reversal's shift count, and a width of 0 shifts by 64,
 *          which is undefined.
 */
uint64_t mmgr_rd_be(const EndianCfg *args);

/**
 * @brief Reverses the byte order of args->val at args->width bytes.
 *
 * @param[in] args Value and width [BORROWS].
 * @return         The reversed value, right-aligned into the low args->width bytes.
 * @note Reads args->val and args->width and nothing else, so it touches no buffer and dst and src take
 *       no part.
 * @note Both tables point rev at this one function, which reverses whatever it is given without
 *       reference to either order.
 * @warning args->width must be one of the mmgr_endian_width enumerators. 8 minus it is unsigned, so a
 *          width above eight wraps into a very large shift count, and a width of 0 shifts a 64-bit
 *          value by 64, which is undefined.
 */
uint64_t mmgr_endian_rev(const EndianCfg *args);

/**
 * @brief Dispatch table instance named parva_extremitas, the little endian order.
 *
 * @note wr and rd move bytes as they lie, so they land in the host's own order. This module never
 *       consults MMGR_HW_BIG_ENDIAN, so the name holds on a little endian host and this table writes
 *       big endian bytes on a big endian one.
 * @note rev is the same function both tables use.
 */
EMBED_TABLE_STORAGE EndianNs parva_extremitas EMBED_UNUSED = {
    .wr = mmgr_wr_le,
    .rd = mmgr_rd_le,
    .rev = mmgr_endian_rev,
};

/**
 * @brief Dispatch table instance named magna_extremitas, the big endian order.
 *
 * @note wr reverses before writing and rd reverses after reading, so the bytes land in the reverse of
 *       the host's own order. That is big endian on a little endian host, which is what the name
 *       records, and little endian on a big endian one.
 * @note rev is shared with parva_extremitas.
 */
EMBED_TABLE_STORAGE EndianNs magna_extremitas EMBED_UNUSED = {
    .wr = mmgr_wr_be,
    .rd = mmgr_rd_be,
    .rev = mmgr_endian_rev,
};

EMBED_END_DECLS

#endif
