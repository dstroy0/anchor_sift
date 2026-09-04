/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file octetus_introitus_exitus.c
 * @brief Byte verbs over a span, with the room test the three appending entries share.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note byteio_put, byteio_raw and byteio_put_be ask the same two questions before they write,
 *       whether the span has room and whether it is still good. Both live in byteio_claim, so each
 *       of the three is only what it does after that call.
 * @note byteio_mpint_fixed does not reach byteio_claim. It writes the field whole rather than
 *       appending to it, so it tests the width against the span's cap itself.
 * @note A whole value moves a word at a time. magna_extremitas.rev reverses it once, and the count
 *       then selects stores or loads of eight, four, two and one byte, so nothing walks a byte at a
 *       time except the odd byte at the end of an odd count.
 */
#include "octetus_introitus_exitus/octetus_introitus_exitus.h"

#include "endian/endian.h"
#include "memoria_operor/memoria_operor.h"
#include "proximus_operor/proximus_operor.h"

/**
 * @brief Arguments for the byteio backends, built from a caller's OctetusCfg by the entry macros.
 *
 * @note Same members as OctetusCfg, without the const qualifiers. Every OctetusCfg member is const,
 *       so neither the struct nor any field of it can be assigned once the caller has built it.
 *       BYTEIO_ENTRY initializes one of these from those fields instead.
 */
typedef struct
{
    mmgr_span *write_span; /**< Span the appending backends write into, and byteio_mpint_fixed fills [BORROWS]. */
    mmgr_cspan *read_span; /**< Span byteio_take_be and byteio_rd_str read from [BORROWS]. */
    const uint8_t *src;    /**< Bytes byteio_raw appends, and the integer byteio_mpint_fixed reads [BORROWS]. */
    uint64_t *out;         /**< Where byteio_take_be stores the value it read [BORROWS]. */
    const uint8_t **blob;  /**< Where byteio_rd_str points at the run it found [BORROWS]. */
    size_t *blob_bytes;    /**< Where byteio_rd_str stores that run's length [BORROWS]. */
    uint64_t value;        /**< Value byteio_put_be writes, taken from its low end. */
    size_t bytes;          /**< Bytes the call moves, or byteio_mpint_fixed's source length. */
    uint8_t byte;          /**< The single byte byteio_put appends. */
} ByteioCtx;

/**
 * @brief Claims bytes at the span's cursor, or latches its overflow.
 *
 * @param[in,out] write_span Span to append into [BORROWS].
 * @param[in]     bytes      Bytes wanted.
 * @return                   Where to write them, or NULL when they do not fit [BORROWS].
 * @note byteio_put, byteio_raw and byteio_put_be all reach this, so the room test, the latch and the
 *       cursor live in one place rather than three.
 * @note pos advances by bytes whether or not they fit, so a span that overran reports how far past
 *       the end the run went rather than stopping at cap. That is a number for reading in a
 *       post-mortem, not a sizing pass to build on - see the warning.
 * @warning Writing past the end is a build failure. What a writer emits and how big its buffer is are
 *          both fixed before the build, so the two are either compatible or the program is wrong.
 *          MMGR_ASSERT stops the program in the checks build. In a shipping build the latch is damage
 *          control, keeping a wrong program from writing past the end, and not a path to design for.
 */
EMBED_INLINE uint8_t *byteio_claim(mmgr_span *write_span, size_t bytes)
{
    const size_t at = write_span->pos;

    MMGR_ASSERT((write_span->buf != NULL) && !write_span->overflow && (at <= write_span->cap) &&
                    (bytes <= (write_span->cap - at)),
                "append runs past the end of the span");

    write_span->pos += bytes;
    if ((write_span->buf == NULL) || write_span->overflow || (bytes > (write_span->cap - at)) || (at > write_span->cap))
    {
        write_span->overflow = EMBED_TRUE;
        return NULL;
    }
    return write_span->buf + at;
}

/**
 * @brief Takes bytes at the read span's cursor and advances past them.
 *
 * @param[in,out] read_span Span to read from [BORROWS].
 * @param[in]     bytes     Bytes wanted.
 * @return                  Where they start, or NULL when the span is short [BORROWS].
 * @note The cursor moves only when the bytes were there. A failed read leaves it where it was, so a
 *       caller that keeps going still knows where it is.
 * @note No assert here, unlike byteio_claim, and the difference is not an oversight. A writer's
 *       output length is settled before the build, so writing past the end means the program is
 *       wrong. A reader is handed whatever was sent to it, so a short read is a fact about the
 *       input rather than a defect.
 * @note byteio_take_be and byteio_rd_str return a result, because a caller has to act on a short
 *       read. byteio_put, byteio_raw and byteio_put_be return nothing, because the span latches its
 *       own failure and leaves no answer to act on.
 */
EMBED_INLINE const uint8_t *byteio_take(mmgr_cspan *read_span, size_t bytes)
{
    const size_t at = read_span->pos;

    if ((read_span->buf == NULL) || read_span->err || (at > read_span->len) || (bytes > (read_span->len - at)))
    {
        read_span->err = EMBED_TRUE;
        return NULL;
    }
    read_span->pos = at + bytes;
    return read_span->buf + at;
}

/**
 * @brief Appends args->byte to the span.
 *
 * @param[in,out] args Span and the byte [BORROWS].
 * @note byteio_claim asks whether the byte fits. It does not on a span with no room, and then the
 *       byte is dropped and the span's overflow is latched - see the warning there.
 */
EMBED_INLINE void byteio_put(const ByteioCtx *args)
{
    uint8_t *const at = byteio_claim(args->write_span, 1u);

    if (at != NULL)
    {
        *at = args->byte;
    }
}

/**
 * @brief Appends args->bytes from args->src as they are.
 *
 * @param[in,out] args Span, source and count [BORROWS].
 * @note Reaches memor.cpy rather than walking bytes here, so this module carries no second copy.
 * @note args->src must hold args->bytes readable bytes, and byteio_claim asks whether the span has
 *       room for them. It does not on a full span, and then nothing is copied and the span's
 *       overflow is latched - see the warning there.
 */
EMBED_INLINE void byteio_raw(const ByteioCtx *args)
{
    uint8_t *const at = byteio_claim(args->write_span, args->bytes);

    if (at != NULL)
    {
        EMBED_CALL(memor.cpy, MemoriaCfg, .dst = at, .src = args->src, .bytes = args->bytes);
    }
}

/**
 * @brief Appends the low args->bytes of args->value, most significant byte first.
 *
 * @param[in,out] args Span, value and count [BORROWS].
 * @note magna_extremitas.rev right-aligns the reversed value into its low args->bytes, so storing those
 *       in the target's own order lays the bytes out most significant first.
 * @note The count selects the stores: eight is one, seven is three, and only an odd final byte is
 *       ever written alone.
 * @note args->bytes must be 1 to 8, which is what the cast to mmgr_endian_width below rests on.
 *       byteio_claim asks whether that many fit, and on a span with no room nothing is stored and
 *       the span's overflow is latched - see the warning there.
 */
EMBED_INLINE void byteio_put_be(const ByteioCtx *args)
{
    uint8_t *at = byteio_claim(args->write_span, args->bytes);

    if (at == NULL)
    {
        return;
    }

    // Explicit cast narrows the count to the mmgr_endian_width the reversal takes. The 1 to 8 bound
    // on args->bytes is what keeps it inside that type
    uint64_t reversed =
        EMBED_CALL(magna_extremitas.rev, EndianCfg, .val = args->value, .width = (mmgr_endian_width)args->bytes);

    // A count of eight takes the first branch alone, so the shifts below never reach the full width
    if ((args->bytes & 8u) != 0u)
    {
        EMBED_CALL(proxim.put64, ProximusCfg, .dst = at, .val = reversed);
        return;
    }

    // The cursor and the value advance on lines of their own after each store, so neither is a side
    // effect of the store that read them
    if ((args->bytes & 4u) != 0u)
    {
        EMBED_CALL(proxim.put32, ProximusCfg, .dst = at, .val = reversed);
        at += 4;
        reversed >>= 32;
    }
    if ((args->bytes & 2u) != 0u)
    {
        EMBED_CALL(proxim.put16, ProximusCfg, .dst = at, .val = reversed);
        at += 2;
        reversed >>= 16;
    }
    if ((args->bytes & 1u) != 0u)
    {
        // Explicit cast narrows what is left of the value to the single byte this store writes
        *at = (uint8_t)reversed;
    }
}

/**
 * @brief Reads a big endian value of args->bytes at the cursor and advances past it.
 *
 * @param[in,out] args Span, count and where to store the value [BORROWS].
 * @return             EMBED_TRUE when the bytes were there.
 * @note This reads back what byteio_put_be writes. The bytes are gathered in the target's own order
 *       at the widest step the count allows, and reversed once at the end.
 * @note args->bytes must be 1 to 8, which is what the cast to mmgr_endian_width below rests on.
 *       args->out is written only on EMBED_TRUE, and a span too short to answer is a fact about the
 *       input rather than a wrong program - see byteio_take.
 */
EMBED_INLINE embed_bool byteio_take_be(const ByteioCtx *args)
{
    const uint8_t *at = byteio_take(args->read_span, args->bytes);

    if (at == NULL)
    {
        return EMBED_FALSE;
    }

    uint64_t gathered = 0u;

    // A count of eight is the whole width, so the narrower tests below cannot be true
    if ((args->bytes & 8u) != 0u)
    {
        gathered = EMBED_CALL(proxim.load64, ProximusCfg, .at = at);
    }
    else
    {
        // Explicit casts widen each load to the uint64_t gathered collects into, before the shift
        // promotes it. The cursor and the shift then advance on lines of their own, so neither is a
        // side effect of the bitwise or that reads them
        size_t shift = 0u;

        if ((args->bytes & 4u) != 0u)
        {
            gathered |= (uint64_t)EMBED_CALL(proxim.load32, ProximusCfg, .at = at) << shift;
            at += 4;
            shift += 32u;
        }
        if ((args->bytes & 2u) != 0u)
        {
            gathered |= (uint64_t)EMBED_CALL(proxim.load16, ProximusCfg, .at = at) << shift;
            at += 2;
            shift += 16u;
        }
        if ((args->bytes & 1u) != 0u)
        {
            gathered |= (uint64_t)(*at) << shift;
        }
    }

    // Explicit cast narrows the count to the mmgr_endian_width the reversal takes. The 1 to 8 bound
    // on args->bytes is what keeps it inside that type
    *args->out = EMBED_CALL(magna_extremitas.rev, EndianCfg, .val = gathered, .width = (mmgr_endian_width)args->bytes);
    return EMBED_TRUE;
}

/**
 * @brief Reads a length-prefixed run at the cursor and points args->blob at it.
 *
 * @param[in,out] args Span, and where to report the run [BORROWS].
 * @return             EMBED_TRUE when the length and its run both lay within the span.
 * @note The length ahead of the run is four bytes, big endian, which is what fixes the format.
 * @note The cursor is put back when the run does not fit. A length read that is then not followed by
 *       its payload is not a read at all, and leaving the cursor between the two would give a caller
 *       a position that means nothing.
 * @warning args->blob is left pointing into the read span itself, not at a copy, so the run is good
 *          only as long as that buffer is [BORROWS]. Nothing here allocates and nothing frees, and
 *          args->blob and args->blob_bytes are written only on EMBED_TRUE.
 */
EMBED_INLINE embed_bool byteio_rd_str(const ByteioCtx *args)
{
    const size_t started_at = args->read_span->pos;
    uint64_t run_bytes = 0u;

    if (!EMBED_CALL(byteio_take_be, ByteioCtx, .read_span = args->read_span, .out = &run_bytes, .bytes = 4u))
    {
        return EMBED_FALSE;
    }

    // Explicit casts narrow the length to the size_t the span is measured in and args->blob_bytes
    // holds. It was read as four bytes, so it cannot exceed what a 32-bit size_t carries
    const uint8_t *const at = byteio_take(args->read_span, (size_t)run_bytes);

    if (at == NULL)
    {
        args->read_span->pos = started_at;
        return EMBED_FALSE;
    }
    *args->blob = at;
    *args->blob_bytes = (size_t)run_bytes;
    return EMBED_TRUE;
}

/**
 * @brief Right-aligns the integer at args->src into args->write_span's whole buffer, zero filling
 *        ahead of it.
 *
 * @param[in,out] args The integer and its length, and the field [BORROWS].
 * @return             EMBED_TRUE when the integer fits the field.
 * @note args->src must hold args->bytes readable bytes. The field is the span's cap wide, not
 *       args->bytes, and a value too wide for it latches the span's overflow and stores nothing.
 * @note Leading zero bytes are skipped before the width is tested, so a value carrying a sign byte
 *       still fits a field of its own size.
 * @note The zero fill covers only what lies ahead of the value, since the copy lands on the rest of
 *       the field exactly.
 */
EMBED_INLINE embed_bool byteio_mpint_fixed(const ByteioCtx *args)
{
    mmgr_span *const field = args->write_span;
    size_t leading_zeros = 0u;

    // The step is kept out of the condition, so the bound and the byte test read the offset without
    // advancing it
    while ((leading_zeros < args->bytes) && (args->src[leading_zeros] == 0u))
    {
        leading_zeros++;
    }

    const size_t value_bytes = args->bytes - leading_zeros;

    if ((field->buf == NULL) || (value_bytes > field->cap))
    {
        field->overflow = EMBED_TRUE;
        return EMBED_FALSE;
    }
    // Only the run ahead of the value is cleared. The copy below fills the rest of the field
    // exactly, so clearing that part first would store every byte of it twice
    // Explicit cast matches MemoriaCfg, where val is a single byte and bytes is a size_t count
    EMBED_CALL(memor.set, MemoriaCfg, .dst = field->buf, .val = (uint8_t)0, .bytes = field->cap - value_bytes);
    EMBED_CALL(memor.cpy, MemoriaCfg, .dst = field->buf + (field->cap - value_bytes), .src = args->src + leading_zeros,
               .bytes = value_bytes);
    // The field is written whole rather than appended to, so the cursor ends at cap
    field->pos = field->cap;
    return EMBED_TRUE;
}

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_byteio_ and byteio_ prefixes, which the two share.
 * @param[in] ...         Initializers for the ByteioCtx literal, written in terms of args.
 * @warning The emitted entry takes a const OctetusCfg * named args and the initializers dereference
 *          it, so it must not be NULL [BORROWS].
 */
#define BYTEIO_ENTRY(ReturnType_, name_, ...)                                                                          \
    EMBED_ENTRY(mmgr_byteio_, byteio_, ByteioCtx, OctetusCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY_V, for an entry returning nothing.
 *
 * @param[in] name_ Name after the mmgr_byteio_ and byteio_ prefixes, which the two share.
 * @param[in] ...   Initializers for the ByteioCtx literal, written in terms of args.
 * @warning The emitted entry takes a const OctetusCfg * named args and the initializers dereference
 *          it, so it must not be NULL [BORROWS].
 */
#define BYTEIO_ENTRY_V(name_, ...) EMBED_ENTRY_V(mmgr_byteio_, byteio_, ByteioCtx, OctetusCfg, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in octetus_introitus_exitus.h.
 */
BYTEIO_ENTRY_V(put, .write_span = args->write_span, .byte = args->byte)
BYTEIO_ENTRY_V(put_be, .write_span = args->write_span, .value = args->value, .bytes = args->bytes)
BYTEIO_ENTRY_V(raw, .write_span = args->write_span, .src = args->src, .bytes = args->bytes)
BYTEIO_ENTRY(embed_bool, take_be, .read_span = args->read_span, .bytes = args->bytes, .out = args->out)
BYTEIO_ENTRY(embed_bool, rd_str, .read_span = args->read_span, .blob = args->blob, .blob_bytes = args->blob_bytes)
BYTEIO_ENTRY(embed_bool, mpint_fixed, .write_span = args->write_span, .src = args->src, .bytes = args->bytes)
