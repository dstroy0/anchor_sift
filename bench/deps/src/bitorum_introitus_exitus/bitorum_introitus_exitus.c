/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bitorum_introitus_exitus.c
 * @brief Bit writer packing least significant bits first into a caller-supplied buffer.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note bitor_init fills a writer in and writes nothing. Of the two that write, bitor_put writes
 *       whole bytes and nothing else, so bits that do not fill one stay in the residue, and
 *       bitor_align is what puts that last partial byte out.
 * @note The residue is what makes a bit stream possible across calls. Without it a caller would have
 *       to hand whole bytes at every call, which is the problem this module exists to remove.
 * @note Reaches nothing outside config.
 * @warning A stream whose length is not a multiple of eight and that never calls align ends one byte
 *          short, with no flag raised and nothing to notice at the call.
 */
#include "bitorum_introitus_exitus/bitorum_introitus_exitus.h"

/**
 * @brief Argument type built by EMBED_CALL in the three entry points.
 *
 * @note Fields match BitorumCfg, without its const qualifiers. The const on the public type is what
 *       stops an entry writing through its own arguments. The backend needs no such promise.
 * @note bitor_init reads out and cap. bitor_put reads writer, val and bit_count. bitor_align reads
 *       writer alone.
 */
typedef struct
{
    mmgr_bitor *writer;   /**< Writer bitor_put appends to and bitor_align finishes [BORROWS]. */
    uint8_t *out;         /**< Buffer bitor_init builds a writer over [BORROWS]. */
    size_t cap;           /**< Bytes available in out. */
    uint64_t val;         /**< Bits to write, taken from the low end. */
    embed_word bit_count; /**< Number of bits of val to write. */
} BitorCtx;

/**
 * @brief Appends the low args->bit_count bits of args->val to args->writer.
 *
 * @param[in,out] args Writer, value and bit count [BORROWS].
 * @note Writes whole bytes only. Leftover bits stay in writer->residue.
 * @note Does nothing when writer->overflow is already set, so a caller may write a whole stream and
 *       test overflow once at the end rather than after every call.
 * @note Sets writer->overflow and clears the residue when the bytes would pass writer->cap.
 * @warning args->bit_count must not exceed 64, and nothing holds it there outside a
 *          MMGR_DEBUG_CHECKS build. A larger count writes zeros past the sixty-fourth bit and
 *          advances the writer as though they were data.
 */
EMBED_INLINE void bitor_put(const BitorCtx *args)
{
    mmgr_bitor *const writer = args->writer;

    if (writer->overflow)
    {
        return;
    }

    MMGR_ASSERT(writer->bytes_written <= writer->cap, "the count of written bytes has passed the capacity");
    MMGR_ASSERT(writer->bit_count < 8u, "a whole byte was left in the residue instead of being written");
    MMGR_ASSERT(args->bit_count <= 64u, "a put of more bits than a uint64_t holds");

    // A request of 64 or more takes the all-ones mask, because a shift by the full width is
    // undefined. Explicit cast pins that mask at the uint64_t the value is masked in
    const uint64_t mask = (args->bit_count >= 64u) ? ~(uint64_t)0 : ((UINT64_C(1) << args->bit_count) - 1u);
    // Explicit cast converts the combined residue and request bits, in whole bytes, to size_t
    const size_t whole = (size_t)((writer->bit_count + args->bit_count) / 8u);
    uint64_t work = args->val & mask;
    embed_word left = args->bit_count;

    if (whole > (writer->cap - writer->bytes_written))
    {
        writer->overflow = EMBED_TRUE;
        writer->bit_count = 0;
        writer->residue = 0;
        return;
    }

    uint8_t *const to = writer->out + writer->bytes_written;

    if (whole != 0u)
    {
        const embed_word take = 8u - writer->bit_count;
        // Explicit cast narrows the masked byte to the uint8_t chunk the store below merges
        const uint8_t chunk = (uint8_t)(work & 0xFFu);

        // Explicit casts hold each step at uint8_t, because the shift and the or promote away from it
        to[0] = (uint8_t)(writer->residue | (uint8_t)(chunk << writer->bit_count));

        // The value and remaining count step on lines of their own, so neither is a side effect
        // inside the store above
        work >>= take;
        left -= take;
        writer->residue = 0;
        writer->bit_count = 0;

        // The first byte is the only one the residue reaches: it is cleared just above and nothing
        // refills it before the loop ends, so every byte after it is a mask and a store, with no
        // merge and no shift to work out. The value and remaining count step on lines of their own
        // after the store, so neither is a side effect inside it.
        for (size_t index = 1u; index < whole; index++)
        {
            // Explicit cast narrows the masked byte to the uint8_t the buffer holds
            to[index] = (uint8_t)(work & 0xFFu);
            work >>= 8u;
            left -= 8u;
        }
    }

    if (left != 0u)
    {
        // Explicit casts narrow the leftover bits into the uint8_t residue. left plus
        // writer->bit_count is under 8, so the shift below stays inside the byte
        const uint8_t tail = (uint8_t)(work & ((1u << left) - 1u));

        writer->residue = (uint8_t)(writer->residue | (uint8_t)(tail << writer->bit_count));
        writer->bit_count += left;
    }
    writer->bytes_written += whole;
}

/**
 * @brief Writes the partial byte args->writer still holds, padded with zeros above its bits.
 *
 * @param[in,out] args Writer to finish [BORROWS].
 * @note The residue holds its bits in the low bit_count positions with zeros above, so no padding is
 *       added here.
 * @note Does nothing when the residue is empty, so it is safe to call at the end of any stream.
 * @note Does nothing when writer->overflow is already set.
 * @warning Sets writer->overflow when the byte would pass writer->cap.
 */
EMBED_INLINE void bitor_align(const BitorCtx *args)
{
    mmgr_bitor *const writer = args->writer;

    // Two ways there is nothing to do: the writer already overflowed, or the residue is empty
    if (writer->overflow || (writer->bit_count == 0u))
    {
        return;
    }
    if (writer->bytes_written >= writer->cap)
    {
        writer->overflow = EMBED_TRUE;
        return;
    }
    writer->out[writer->bytes_written] = writer->residue;
    writer->bytes_written++;
    writer->residue = 0;
    writer->bit_count = 0;
}

/**
 * @brief Fills an mmgr_bitor from args->out and args->cap, with the counters zeroed.
 *
 * @param[in] args Buffer out and its extent cap [BORROWS].
 * @return         A writer with no bytes written and no residue.
 * @note The returned writer keeps args->out, which must outlive it [BORROWS].
 * @warning args->out must not be null and args->cap must not be zero. Neither is held to outside a
 *          MMGR_DEBUG_CHECKS build, and a null out is not noticed here: bitor_put writes through it
 *          on the first whole byte.
 */
EMBED_INLINE mmgr_bitor bitor_init(const BitorCtx *args)
{
    MMGR_ASSERT(args->out != NULL, "a bit writer needs a buffer");
    MMGR_ASSERT(args->cap != 0, "a bit writer needs a capacity");

    mmgr_bitor writer;
    writer.out = args->out;
    writer.cap = args->cap;
    writer.bytes_written = 0;
    writer.residue = 0;
    writer.bit_count = 0;
    writer.overflow = EMBED_FALSE;
    return writer;
}

/**
 * @brief Binds this module's four fixed arguments to EMBED_ENTRY.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_bitor_ and bitor_ prefixes, which the two share.
 * @param[in] ...         Initializers for the BitorCtx literal, written in terms of args.
 * @note Four of EMBED_ENTRY's six arguments are the same at every entry here, so they are bound
 *       once and each entry below states only what differs.
 */
#define BITOR_ENTRY(ReturnType_, name_, ...)                                                                           \
    EMBED_ENTRY(mmgr_bitor_, bitor_, BitorCtx, BitorumCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds the same four to EMBED_ENTRY_V, for an entry that returns nothing.
 *
 * @param[in] name_ Name after the mmgr_bitor_ and bitor_ prefixes, which the two share.
 * @param[in] ...   Initializers for the BitorCtx literal, written in terms of args.
 * @note Two binders rather than one because EMBED_ENTRY_V takes no return type, as its own block
 *       in mmgr_config.h describes.
 */
#define BITOR_ENTRY_V(name_, ...) EMBED_ENTRY_V(mmgr_bitor_, bitor_, BitorCtx, BitorumCfg, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in bitorum_introitus_exitus.h.
 * @note The fields each line forwards are the ones that entry reads; EMBED_CALL zeroes the rest.
 */
BITOR_ENTRY(mmgr_bitor, init, .out = args->out, .cap = args->cap)
BITOR_ENTRY_V(put, .writer = args->writer, .val = args->val, .bit_count = args->bit_count)
BITOR_ENTRY_V(align, .writer = args->writer)
