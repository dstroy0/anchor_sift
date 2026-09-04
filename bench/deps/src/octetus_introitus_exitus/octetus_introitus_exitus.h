/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file octetus_introitus_exitus.h
 * @brief Byte verbs that append into a caller's span or read out of it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note These act on a caller's span and hold nothing of their own. The span carries the cursor and
 *       the sticky flag, so a caller may append a whole message and test once at the end.
 * @note mmgr_byteio_put, mmgr_byteio_put_be and mmgr_byteio_raw return nothing. What a writer emits
 *       and how big its buffer is are both fixed before the build, so writing past the end means the
 *       program is wrong. Those three assert, store nothing, and latch overflow to keep a wrong
 *       program off the end, and none of that leaves a caller anything to act on.
 * @note mmgr_byteio_take_be and mmgr_byteio_rd_str answer EMBED_FALSE when the bytes are not there,
 *       set the read span's err, and leave the cursor and the output where they were. A reader is
 *       handed whatever was sent to it, so a short read is a runtime fact rather than a build
 *       failure. The cursor does not advance on failure, because a caller that keeps reading still
 *       needs it to mean something.
 * @note mmgr_byteio_mpint_fixed is neither of those. It writes a whole field rather than appending,
 *       and answers whether the integer fit, so its own declaration carries the contract.
 * @note Whole values move a word at a time. The big endian entries reverse once and then store or
 *       load at the widest step the count allows, rather than walking bytes.
 */
#ifndef MMGR_OCTETUS_INTROITUS_EXITUS_H
#define MMGR_OCTETUS_INTROITUS_EXITUS_H

#include "spatium/spatium.h"

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Arguments for the byteio calls, where each call reads only the members it needs.
 *
 * @note put reads write_span and byte. put_be reads write_span, value and bytes. raw reads
 *       write_span, src and bytes. take_be reads read_span, bytes and out. rd_str reads read_span,
 *       blob and blob_bytes. mpint_fixed reads write_span, src and bytes, where bytes is the
 *       integer's length rather than a big endian width.
 */
typedef struct
{
    mmgr_span *const write_span; /**< Span put, put_be and raw append into, or mpint_fixed fills [BORROWS]. */
    mmgr_cspan *const read_span; /**< Span take_be and rd_str read from [BORROWS]. */
    const uint8_t *const src;    /**< Bytes raw appends, or the integer mpint_fixed reads [BORROWS]. */
    uint64_t *const out;         /**< Where take_be stores the value it read [BORROWS]. */
    const uint8_t **const blob;  /**< Where rd_str points at the payload it found [BORROWS]. */
    size_t *const blob_bytes;    /**< Where rd_str stores that payload's length [BORROWS]. */
    const uint64_t value;        /**< Value put_be writes, taken from its low bytes. */
    const size_t bytes;          /**< Bytes the call moves, 1 through 8 for the big endian entries. */
    const uint8_t byte;          /**< The single byte put appends. */
} OctetusCfg;

/**
 * @brief Type of the byteio dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the six members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note put, put_be and raw answer nothing, because a span latches its own failure and leaves a
 *       caller nothing to act on.
 * @note take_be and rd_str answer, because a read that did not happen has to be distinguishable
 *       from one that read a zero. mpint_fixed answers whether the integer fit the field.
 */
typedef struct
{
    void (*put)(const OctetusCfg *args);               /**< Appends one byte. */
    void (*put_be)(const OctetusCfg *args);            /**< Appends bytes of a value, most significant first. */
    void (*raw)(const OctetusCfg *args);               /**< Appends a run of bytes as they are. */
    embed_bool (*take_be)(const OctetusCfg *args);     /**< Reads a big endian value and advances past it. */
    embed_bool (*rd_str)(const OctetusCfg *args);      /**< Reads a length-prefixed run and points at it. */
    embed_bool (*mpint_fixed)(const OctetusCfg *args); /**< Right-aligns an integer into a fixed field. */
} OctetusIntroitusExitusNs;
EMBED_TABLE_LAYOUT(OctetusIntroitusExitusNs, put, put_be, raw, take_be, rd_str, mpint_fixed);

/**
 * @brief Appends args->byte to args->write_span.
 *
 * @param[in,out] args Span and the byte to append [BORROWS].
 * @warning Appending past the span's cap is a build failure. It asserts, stores nothing and latches
 *          overflow. pos counts the byte either way.
 */
void mmgr_byteio_put(const OctetusCfg *args);

/**
 * @brief Appends the low args->bytes of args->value to args->write_span, most significant byte first.
 *
 * @param[in,out] args Span, value and byte count [BORROWS].
 * @note The value is reversed once and then stored at the widest step the count allows, so a count of
 *       eight is one store and a count of seven is three.
 * @warning Appending past the span's cap is a build failure. It asserts, stores nothing and latches
 *          overflow. pos advances either way.
 * @warning args->bytes must be 1 through 8.
 */
void mmgr_byteio_put_be(const OctetusCfg *args);

/**
 * @brief Appends args->bytes from args->src to args->write_span as they are.
 *
 * @param[in,out] args Span, source and byte count [BORROWS].
 * @warning Appending past the span's cap is a build failure. It asserts, stores nothing and latches
 *          overflow. pos advances either way.
 * @warning args->src must be readable for args->bytes, and must not overlap the span's buffer.
 */
void mmgr_byteio_raw(const OctetusCfg *args);

/**
 * @brief Reads a big endian value of args->bytes at args->read_span's cursor and advances past it.
 *
 * @param[in,out] args Span, byte count and where to store the value [BORROWS].
 * @return             EMBED_TRUE when the bytes were there, EMBED_FALSE when the span was short.
 * @note Reads at the cursor and nowhere else. A codec that leads with a tag advances past it itself.
 * @note A read reaching past the end sets the span's err and leaves the cursor and args->out untouched.
 * @warning args->bytes must be 1 through 8.
 */
embed_bool mmgr_byteio_take_be(const OctetusCfg *args);

/**
 * @brief Reads a big endian 32-bit length at args->read_span's cursor, then points args->blob at the
 *        run behind it.
 *
 * @param[in,out] args Span, and where to report the run and its length [BORROWS].
 * @return             EMBED_TRUE when the length and its run both lay within the span.
 * @note Nothing is copied. args->blob points into the span's own bytes, so it lives only as long as
 *       they do [BORROWS].
 * @note The cursor advances past the length and the run together, so a caller reading a sequence of
 *       these needs to track nothing between them.
 * @note A run reaching past the end leaves the cursor where it started, sets the span's err, and
 *       writes nothing through args->blob or args->blob_bytes. The length alone having been read does
 *       not move the cursor either, since a partial read is not a read.
 */
embed_bool mmgr_byteio_rd_str(const OctetusCfg *args);

/**
 * @brief Right-aligns the big endian integer at args->src into args->write_span's whole buffer, zero
 *        filling ahead of it.
 *
 * @param[in,out] args The integer with its length in args->src and args->bytes, and the field as
 *                     args->write_span [BORROWS].
 * @return             EMBED_TRUE when the integer fits the field, EMBED_FALSE when it does not.
 * @note Leading zero bytes of the integer are skipped before the width is tested, so a value carrying
 *       a sign byte still fits a field of its own size.
 * @note The field is written whole rather than appended to. On success args->write_span's cursor ends
 *       at its cap.
 * @note Nothing is written to the field when it returns EMBED_FALSE, but args->write_span's overflow
 *       is latched, so a span tested later reports the failure too.
 * @warning args->src must be readable for args->bytes, and must not overlap args->write_span's buffer.
 */
embed_bool mmgr_byteio_mpint_fixed(const OctetusCfg *args);

/**
 * @brief Dispatch table instance named byteio, with each member set to its mmgr_byteio_ function.
 */
EMBED_TABLE_STORAGE OctetusIntroitusExitusNs byteio EMBED_UNUSED = {
    .put = mmgr_byteio_put,
    .put_be = mmgr_byteio_put_be,
    .raw = mmgr_byteio_raw,
    .take_be = mmgr_byteio_take_be,
    .rd_str = mmgr_byteio_rd_str,
    .mpint_fixed = mmgr_byteio_mpint_fixed,
};

EMBED_END_DECLS

#endif
