/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file cellularum_laboro.c
 * @brief Bounded string work over SWAR words, covering length, compare, search, copy and conversion.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note Strings only. Lengths that arrive off a wire belong to byteio, which is where rd_str and
 *       mpint_fixed live.
 * @note The CatenaFinitaCfg calls are bounded by a cap the caller states, so no walk runs past it even
 *       when the bytes carry no terminator. Several settle the last partial word by loading it whole
 *       and masking after, which touches bytes past cap. cellularum_laboro.h gives the extent for each.
 * @note ws and digit read src at at without consulting cap, and the conversions carry no bound at all.
 */
#include "cellularum_laboro/cellularum_laboro.h"
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"
#include "transformo/transformo.h"
#include "verbum_scrutor/verbum_scrutor.h"

/**
 * @brief Arguments for every cellul backend, grouped by the calls that read them.
 *
 * @note Each backend reads one group, and EMBED_CALL zeroes the members it is not given.
 */
typedef struct
{
    const char *const src;     /**< Bytes to read [BORROWS]. */
    const size_t cap;          /**< Bytes readable from src, and for copy the bytes writable at dst. */
    const char *const other;   /**< Second operand for compare and search [BORROWS]. */
    const size_t other_cap;    /**< Bytes readable from other. */
    char *const dst;           /**< Destination for copy [BORROWS]. */
    const size_t at;           /**< Offset into src where the call starts. */
    const uint8_t byte;        /**< Byte sought by chr. */
    const embed_bool ci;       /**< Fold case while comparing. */
    const embed_bool end_wins; /**< A terminator in the same lane counts as a match. */

    const embed_word word_left;  /**< First word for step_word. */
    const embed_word word_right; /**< Second word for step_word. */
    const uint8_t byte_left;     /**< First byte for step_byte. */
    const uint8_t byte_right;    /**< Second byte for step_byte. */

    const size_t needle_len;    /**< Needle length, read by find_core and pick_rows. */
    size_t *const rows;         /**< Needle offsets chosen by pick_rows [BORROWS]. */
    const size_t needle_offset; /**< Needle offset read by ancorae_fold. */

    const char **const end; /**< Set by the to_ calls past the number, or back to src when none was read [BORROWS]. */
    const char **const cur; /**< Cursor advanced by expo [BORROWS]. */
    embed_iword *const exp; /**< Set by expo to the signed exponent [BORROWS]. */
} CellulCtx;

/**
 * @brief Compares one word pair case sensitively and reports whether the walk continues.
 *
 * @param[in] args Words word_left and word_right, with end_wins [BORROWS].
 * @return         MMGR_SWAR_GO when the words agree and carry no terminator, MMGR_SWAR_YES or
 *                 MMGR_SWAR_NO otherwise.
 * @note MMGR_SWAR_YES when the terminator lane precedes the first differing lane, or ties it when end_wins.
 */
EMBED_INLINE embed_iword cellul_step_word_cs(const CellulCtx *args)
{
    const embed_word diff = args->word_left ^ args->word_right;
    const embed_word term = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = args->word_left);

    if ((diff | term) == 0)
    {
        return MMGR_SWAR_GO;
    }

    size_t diff_lane = MMGR_SWAR_BYTES;
    if (diff != 0)
    {
        diff_lane =
            EMBED_CALL(lane.first, ScrutLaneCfg,
                       .mask = MMGR_VERBUM_SCRUTOR_HIGH & ~EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = diff));
    }
    size_t end_lane = MMGR_SWAR_BYTES;
    if (term != 0)
    {
        end_lane = EMBED_CALL(lane.first, ScrutLaneCfg, .mask = term);
    }
    if (args->end_wins)
    {
        return (end_lane <= diff_lane) ? MMGR_SWAR_YES : MMGR_SWAR_NO;
    }
    return (end_lane < diff_lane) ? MMGR_SWAR_YES : MMGR_SWAR_NO;
}

/**
 * @brief Compares one word pair with case folded and reports whether the walk continues.
 *
 * @param[in] args Words word_left and word_right, with end_wins [BORROWS].
 * @return         MMGR_SWAR_GO when the words agree and carry no terminator, MMGR_SWAR_YES or
 *                 MMGR_SWAR_NO otherwise.
 * @note Differs from cellul_step_word_cs only in taking the difference through lane.xor_ with ci set.
 */
EMBED_INLINE embed_iword cellul_step_word_ci(const CellulCtx *args)
{
    const embed_word diff =
        EMBED_CALL(lane.xor_, ScrutLaneCfg, .word = args->word_left, .val = args->word_right, .ci = EMBED_TRUE);
    const embed_word term = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = args->word_left);

    if ((diff | term) == 0)
    {
        return MMGR_SWAR_GO;
    }

    size_t diff_lane = MMGR_SWAR_BYTES;
    if (diff != 0)
    {
        diff_lane =
            EMBED_CALL(lane.first, ScrutLaneCfg,
                       .mask = MMGR_VERBUM_SCRUTOR_HIGH & ~EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = diff));
    }
    size_t end_lane = MMGR_SWAR_BYTES;
    if (term != 0)
    {
        end_lane = EMBED_CALL(lane.first, ScrutLaneCfg, .mask = term);
    }
    if (args->end_wins)
    {
        return (end_lane <= diff_lane) ? MMGR_SWAR_YES : MMGR_SWAR_NO;
    }
    return (end_lane < diff_lane) ? MMGR_SWAR_YES : MMGR_SWAR_NO;
}

/**
 * @brief Compares one byte pair case sensitively and reports whether the walk continues.
 *
 * @param[in] args Bytes byte_left and byte_right, with end_wins [BORROWS].
 * @return         MMGR_SWAR_GO when the bytes match and byte_left is not the terminator,
 *                 MMGR_SWAR_YES or MMGR_SWAR_NO otherwise.
 * @note A terminating byte_left gives MMGR_SWAR_YES when byte_right also terminates, or when
 *       end_wins is set.
 */
EMBED_INLINE embed_iword cellul_step_byte_cs(const CellulCtx *args)
{
    if (args->byte_left == 0)
    {
        if (args->byte_left == args->byte_right)
        {
            return MMGR_SWAR_YES;
        }
        return args->end_wins ? MMGR_SWAR_YES : MMGR_SWAR_NO;
    }
    if (args->byte_left != args->byte_right)
    {
        return MMGR_SWAR_NO;
    }
    return MMGR_SWAR_GO;
}

/**
 * @brief Compares one byte pair with case folded and reports whether the walk continues.
 *
 * @param[in] args Bytes byte_left and byte_right, with end_wins [BORROWS].
 * @return         MMGR_SWAR_GO when the bytes match and byte_left is not the terminator,
 *                 MMGR_SWAR_YES or MMGR_SWAR_NO otherwise.
 * @note Takes the difference through lane.xor_ with ci set, so only the folded result is tested.
 */
EMBED_INLINE embed_iword cellul_step_byte_ci(const CellulCtx *args)
{
    // Explicit casts widen the two bytes to embed_word, so the lane compare sees one occupied lane each
    const embed_word diff = EMBED_CALL(lane.xor_, ScrutLaneCfg, .word = (embed_word)args->byte_left,
                                       .val = (embed_word)args->byte_right, .ci = EMBED_TRUE);

    if (args->byte_left == 0)
    {
        if (diff == 0)
        {
            return MMGR_SWAR_YES;
        }
        return args->end_wins ? MMGR_SWAR_YES : MMGR_SWAR_NO;
    }
    if (diff != 0)
    {
        return MMGR_SWAR_NO;
    }
    return MMGR_SWAR_GO;
}

/**
 * @brief Returns whether ch is one of the six whitespace characters.
 *
 * @param[in] ch Character to test.
 * @return       EMBED_TRUE for space, tab, newline, carriage return, form feed or vertical tab.
 */
EMBED_INLINE embed_bool cellul_is_ws(char ch)
{
    // Explicit cast reads the byte unsigned before the subtraction, so anything below tab wraps high
    // and fails the range rather than passing it as a negative
    const unsigned code = (unsigned)(unsigned char)ch;

    // Tab, newline, vertical tab, form feed and carriage return are 9 through 13 with nothing else
    // between them, so one unsigned range takes all five and space is the only test left. The six
    // comparisons this replaces were joined by short circuits, so a byte that is not whitespace -
    // which is most of them - ran and failed every one. Measured 2.16x on an ESP32-S3 over a buffer
    // holding none
    // Explicit cast narrows the range test into the embed_bool container
    return (embed_bool)(((code - 9u) <= 4u) || (code == 32u));
}

/**
 * @brief Returns whether ch lies between '0' and '9'.
 *
 * @param[in] ch Character to test.
 * @return       EMBED_TRUE for the ten decimal digits.
 */
EMBED_INLINE embed_bool cellul_is_digit(char ch)
{
    return (ch >= '0') && (ch <= '9');
}

/**
 * @brief Bytes between start and the first word boundary at or after it, capped at cap.
 *
 * @param[in] start Address a walk is about to start from [BORROWS].
 * @param[in] cap   Bytes readable at start, which the answer never exceeds.
 * @return          Bytes to step one at a time before whole aligned words can be read.
 * @note Normally zero. This library is built for memory that arrives aligned, and an aligned address
 *       is already on a boundary. It is computed rather than assumed because the entries are also
 *       reached on interior pointers - find verifies a candidate at hay + k, which is any address.
 * @note The aligned load is one instruction on every target. The unaligned one is ten on Xtensa and
 *       eleven on RISC-V, because neither has the instruction and the compiler assembles the word
 *       out of byte loads and shifts, in the middle of the walk.
 */
EMBED_INLINE size_t cellul_head_bytes(const char *start, size_t cap)
{
    // Explicit casts read the address and the mask as one integer type so the low bits can be tested,
    // and narrow the result into the size_t the offsets are counted in. The address is never
    // dereferenced through the integer and never converted back
    const size_t off = (size_t)((uintptr_t)start & (uintptr_t)(MMGR_SWAR_BYTES - 1u));
    const size_t need = (off == 0u) ? 0u : (MMGR_SWAR_BYTES - off);

    return (need > cap) ? cap : need;
}

/**
 * @brief Returns the offset of the first zero byte in src, or cap when there is none.
 *
 * @param[in] args Bytes src and the readable extent cap [BORROWS].
 * @return         Bytes before the terminator, at most cap.
 * @note Scans whole words with no mask at all, then masks the one short word at the end. The bound
 *       is known before the loop, so the lanes past cap can only ever fall in that last word, and
 *       building mask.tail per word costs six instructions an iteration to change nothing.
 * @warning src must be readable for cap bytes. That last short word is loaded whole and masked
 *          after, so up to MMGR_SWAR_BYTES - 1 bytes past cap are read.
 */
EMBED_INLINE size_t cellul_len(const CellulCtx *args)
{
    // Bytes between src and the first word boundary at or after it. Normally none: this library is
    // built for memory that arrives aligned. It is walked rather than assumed because an entry is
    // also reached on an interior pointer - find verifies a candidate at hay + k - and the body
    // below reads through the aligned load, which is one instruction where the unaligned one is ten.
    const size_t lead = cellul_head_bytes(args->src, args->cap);
    const size_t full = lead + (((args->cap - lead) / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES);
    const size_t rest = args->cap - full;
    size_t at = 0u;

    while (at != lead)
    {
        if (args->src[at] == '\0')
        {
            return at;
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += 1u;
    }

    // Two words a pass while two remain. The load and the arithmetic that reads it are a dependent
    // pair, and neither part issues them back to back without stalling. Taking two lets the second
    // load be in flight while the first word is examined. The single-word loop below finishes the
    // odd word.
    while ((full - at) >= (2u * MMGR_SWAR_BYTES))
    {
        const embed_word first_word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at);
        const embed_word second_word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at + MMGR_SWAR_BYTES);
        const embed_word first_zero_lanes = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = first_word);
        const embed_word second_zero_lanes = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = second_word);

        if (first_zero_lanes != 0u)
        {
            return at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = first_zero_lanes);
        }
        if (second_zero_lanes != 0u)
        {
            return at + MMGR_SWAR_BYTES + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = second_zero_lanes);
        }
        // Advance separated from the tests above so the loop body carries no side effect
        at += 2u * MMGR_SWAR_BYTES;
    }

    while (at != full)
    {
        const embed_word zero_lanes = EMBED_CALL(lane.has_zero, ScrutLaneCfg,
                                                 .word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at));
        if (zero_lanes != 0u)
        {
            return at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = zero_lanes);
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += MMGR_SWAR_BYTES;
    }

    if (rest != 0u)
    {
        const embed_word zero_lanes =
            EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at)) &
            EMBED_CALL(mask.lanes_below, ScrutMaskCfg, .bytes = rest);
        if (zero_lanes != 0u)
        {
            return at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = zero_lanes);
        }
    }
    return args->cap;
}

/**
 * @brief Settles one word that carried a match, a terminator, or both.
 *
 * @param[in] at  Address the word was read from [BORROWS].
 * @param[in] end Lanes holding a terminator.
 * @param[in] hit Lanes holding the sought byte.
 * @return        Address of the match, or NULL when no match precedes the terminator [BORROWS].
 * @note mask.before drops lanes at or past the terminator, so a match beginning after the run ends
 *       is not reported. Of an empty terminator mask it keeps every lane.
 * @note Takes the address rather than a CellulCtx: the walk reaches it on an interior pointer, and
 *       the point of it is that the loop body does not carry this arithmetic.
 * @note Plain static, not EMBED_INLINE. It runs once per call - the walk reaches it on the word that
 *       ended the scan and not before - so a call costs nothing measurable, while forcing it inline
 *       puts mask.before and lane.first in the loop body and cost 6% at 2048 bytes.
 */
static const char *cellul_chr_settle(const char *at, embed_word end, embed_word hit)
{
    const embed_word live = hit & EMBED_CALL(mask.before, ScrutMaskCfg, .mask = end);

    return (live != 0u) ? (at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = live)) : NULL;
}

/**
 * @brief Finds the first occurrence of byte in src, stopping at the terminator.
 *
 * @param[in] args Bytes src, the extent cap and the byte sought [BORROWS].
 * @return         Address of the match, or NULL when none precedes the terminator [BORROWS].
 * @note A byte of 0 returns src plus cellul_len: the terminator's own address, or src plus cap when
 *       no terminator is in range.
 * @note mask.before drops lanes at or past the terminator, so a later match is not reported. It is
 *       applied once, on the word that carried a hit or a terminator: until one of those turns up
 *       there is nothing for it to drop, and mask.before of an empty terminator mask is every lane.
 * @note Whole words carry no extent mask. cap can only cut the last word short, and that word is
 *       walked once below the loop.
 * @warning src must be readable for cap bytes. That last short word is loaded whole and masked
 *          after, so up to MMGR_SWAR_BYTES - 1 bytes past cap are read.
 */
EMBED_INLINE const char *cellul_chr(const CellulCtx *args)
{
    if (args->byte == 0u)
    {
        return args->src + cellul_len(args);
    }

    // Bytes to the first word boundary, so the walk below reads through the aligned load. See
    // cellul_head_bytes: normally none, and never more than a word.
    const size_t lead = cellul_head_bytes(args->src, args->cap);
    const size_t full = lead + (((args->cap - lead) / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES);
    const size_t rest = args->cap - full;
    // The sought byte repeated into every lane, once, ahead of the walk. lane.eq answers the same
    // question but rebuilds the broadcast from a byte on every call, and it is large enough that the
    // inliner drops it back out of line as this function grows - which cost 2.5x when it happened.
    // Explicit cast widens the byte to embed_word so the multiply fills every lane
    const embed_word bcast = MMGR_SWAR_ONES * (embed_word)args->byte;
    size_t at = 0u;

    while (at != lead)
    {
        // Explicit cast reads the byte as unsigned, matching CellulCtx::byte
        const uint8_t here = (uint8_t)args->src[at];

        if (here == 0u)
        {
            return NULL;
        }
        if (here == args->byte)
        {
            return args->src + at;
        }
        // Advance separated from the tests above so the loop body carries no side effect
        at += 1u;
    }

    // One word a pass, deliberately. Unrolling this the way cellul_len is unrolled was measured and
    // lost: 8261 cycles to 8277 at 2048 bytes, and 98 to 114 at eight. len has one has_zero in its
    // body and stalls waiting for the load. This has two, which is already enough work to cover the
    // load, so a second word buys nothing and the extra prologue costs.
    while (at != full)
    {
        const embed_word loaded = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at);
        const embed_word end = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = loaded);
        const embed_word hit = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = loaded ^ bcast);

        if ((end | hit) != 0u)
        {
            return cellul_chr_settle(args->src + at, end, hit);
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += MMGR_SWAR_BYTES;
    }

    if (rest != 0u)
    {
        const embed_word keep = EMBED_CALL(mask.lanes_below, ScrutMaskCfg, .bytes = rest);
        const embed_word loaded = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at);
        const embed_word end = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = loaded) & keep;
        const embed_word hit = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = loaded ^ bcast) & keep &
                               EMBED_CALL(mask.before, ScrutMaskCfg, .mask = end);

        if (hit != 0u)
        {
            return args->src + at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = hit);
        }
    }
    return NULL;
}

/**
 * @brief Turns a lane-wise difference word into the mask of lanes that differ.
 *
 * @param[in] diff Difference word, zero in every lane where the two sides agreed.
 * @return         One high bit per differing lane.
 * @note Takes the word rather than a CellulCtx. It is an expression the four compare walks share,
 *       not an entry anything dispatches to.
 */
EMBED_INLINE embed_word cellul_diff_lanes(embed_word diff)
{
    return MMGR_VERBUM_SCRUTOR_HIGH & ~EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = diff);
}

/**
 * @brief Returns the offset of the first byte where src and other differ, case sensitively.
 *
 * @param[in] args Bytes src and other, with the extent cap [BORROWS].
 * @return         Offset of the first difference, or cap when the two agree throughout.
 * @note Compares whole words with nothing but an inequality test, and resolves which lane differs
 *       once, after the loop has found the word that does. Which lane it is cannot matter until a
 *       word differs, and no word differs on all but one iteration of a scan.
 * @warning A terminator does not end the scan. cap is the only bound. Both src and other must be
 *          readable for cap bytes, and the last short word is loaded whole and masked after, so up
 *          to MMGR_SWAR_BYTES - 1 bytes past cap are read from each.
 */
EMBED_INLINE size_t cellul_diff_cs(const CellulCtx *args)
{
    const size_t full = (args->cap / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES;
    const size_t rest = args->cap - full;
    size_t at = 0u;

    // Explicit casts read both addresses as integers so one mask answers for both. When the two
    // arrived on a boundary the run goes through the aligned load, which is one instruction where
    // the unaligned one is a sequence. The test is lifted out rather than carried in the body: as a
    // choice inside the loop the compiler keeps the branch per word and the run costs what the
    // unaligned one costs. memor_cmp took 6.27 cycles a byte to 2.02 on an ESP32-C6 this way
    // Explicit cast narrows the boundary test into the embed_bool container
    const embed_bool level =
        (embed_bool)(((((uintptr_t)args->src) | ((uintptr_t)args->other)) & (uintptr_t)(MMGR_SWAR_BYTES - 1u)) == 0u);

    if (level)
    {
        while (at != full)
        {
            const embed_word src_word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at);
            const embed_word other_word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->other + at);
            if (src_word != other_word)
            {
                return at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = cellul_diff_lanes(src_word ^ other_word));
            }
            // Advance separated from the test above so the loop body carries no side effect
            at += MMGR_SWAR_BYTES;
        }
    }

    while (at != full)
    {
        const embed_word src_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at);
        const embed_word other_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at);
        if (src_word != other_word)
        {
            return at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = cellul_diff_lanes(src_word ^ other_word));
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += MMGR_SWAR_BYTES;
    }

    if (rest != 0u)
    {
        const embed_word diff = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at) ^
                                EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at);
        const embed_word lanes = cellul_diff_lanes(diff) & EMBED_CALL(mask.lanes_below, ScrutMaskCfg, .bytes = rest);
        if (lanes != 0u)
        {
            return at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = lanes);
        }
    }
    return args->cap;
}

/**
 * @brief Returns the offset of the first byte where src and other differ, with case folded.
 *
 * @param[in] args Bytes src and other, with the extent cap [BORROWS].
 * @return         Offset of the first difference, or cap when the two agree throughout.
 * @note Takes the difference through lane.xor_ with ci set. The fold has to happen before the test,
 *       so the walk tests the folded word against zero rather than the two words against each other,
 *       and resolves the lane once on the way out.
 * @note Carries no aligned run: where cellul_diff_cs lifts a boundary test out and walks matched
 *       addresses through the aligned load, every word here goes through the unaligned one.
 * @warning A terminator does not end the scan. cap is the only bound. Both src and other must be
 *          readable for cap bytes, and the last short word is loaded whole and masked after, so up
 *          to MMGR_SWAR_BYTES - 1 bytes past cap are read from each.
 */
EMBED_INLINE size_t cellul_diff_ci(const CellulCtx *args)
{
    const size_t full = (args->cap / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES;
    const size_t rest = args->cap - full;
    size_t at = 0u;

    while (at != full)
    {
        const embed_word diff =
            EMBED_CALL(lane.xor_, ScrutLaneCfg, .word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at),
                       .val = EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at), .ci = EMBED_TRUE);
        if (diff != 0u)
        {
            return at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = cellul_diff_lanes(diff));
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += MMGR_SWAR_BYTES;
    }

    if (rest != 0u)
    {
        const embed_word diff =
            EMBED_CALL(lane.xor_, ScrutLaneCfg, .word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at),
                       .val = EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at), .ci = EMBED_TRUE);
        const embed_word lanes = cellul_diff_lanes(diff) & EMBED_CALL(mask.lanes_below, ScrutMaskCfg, .bytes = rest);
        if (lanes != 0u)
        {
            return at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = lanes);
        }
    }
    return args->cap;
}

/**
 * @brief Settles a pair of words that differ: which came first, the terminator or the difference.
 *
 * @param[in] word_left  Word from the first string.
 * @param[in] word_right Word from the second, which differs from word_left.
 * @param[in] end_wins   Whether a terminator in the same lane as the difference counts as a match.
 * @return               Whether the two agree up to and including where they end.
 * @note Kept out of the walk on purpose. Left inline the loop carries it whether or not it runs, and
 *       the walk measured 4.56 cycles a byte with it there against 2.52 without - the hot path is
 *       two loads, a compare and a terminator test, and it stays that only while this is elsewhere.
 */
static embed_bool cellul_agree_at(embed_word word_left, embed_word word_right, embed_bool end_wins)
{
    const embed_word term = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = word_left);
    const embed_word diff = cellul_diff_lanes(word_left ^ word_right);
    const size_t end_lane = (term != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = term) : MMGR_SWAR_BYTES;
    const size_t diff_lane = (diff != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = diff) : MMGR_SWAR_BYTES;

    // Explicit cast narrows the lane comparison into the embed_bool container
    return (embed_bool)(end_wins ? (end_lane <= diff_lane) : (end_lane < diff_lane));
}

/**
 * @brief Reports whether src reaches its terminator without differing from other, case sensitively.
 *
 * @param[in] args Bytes src and other, the extent cap, and end_wins [BORROWS].
 * @return         EMBED_TRUE when src's terminator precedes the first differing byte.
 * @note end_wins makes a terminator in the same lane as the difference count as agreement.
 * @note Reaching cap with neither a terminator nor a difference returns end_wins.
 * @warning Both src and other must be readable for cap bytes. The last short word is loaded whole
 *          and masked after, so up to MMGR_SWAR_BYTES - 1 bytes past cap are read from each.
 */
EMBED_INLINE embed_bool cellul_agree_cs(const CellulCtx *args)
{
    const size_t full = (args->cap / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES;
    const size_t rest = args->cap - full;
    size_t at = 0u;

    // Explicit casts read both addresses as integers so one mask answers for both, and the aligned
    // run is lifted into its own loop rather than chosen inside the body - as a choice per word the
    // compiler keeps the branch and the run costs what the unaligned one costs. The same shape took
    // memor_cmp from 6.27 cycles a byte to 2.02 on an ESP32-C6
    // Explicit cast narrows the boundary test into the embed_bool container
    const embed_bool level =
        (embed_bool)(((((uintptr_t)args->src) | ((uintptr_t)args->other)) & (uintptr_t)(MMGR_SWAR_BYTES - 1u)) == 0u);

    // level is fixed before the loop, so a false one skips this run whole and leaves every word to
    // the unaligned loop below
    while (level && (at != full))
    {
        const embed_word src_word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at);
        const embed_word other_word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->other + at);

        // The difference test comes first and the terminator test only runs when the two words
        // agree. Both still run on a word that agrees, which is every word of a matching pair, so
        // this is not short circuiting anything - it is that the terminator test is four operations
        // on a dependency chain and taking it off the front lets the compare issue against it.
        // Measured 4.32 cycles a byte to 2.52 on an ESP32-S3 over two thousand bytes, which is 1.68x
        if (src_word != other_word)
        {
            return cellul_agree_at(src_word, other_word, args->end_wins);
        }
        if (EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = src_word) != 0u)
        {
            // The two words agree, so a terminator in one is a terminator in both and they end
            // together whatever end_wins says about a tie
            return EMBED_TRUE;
        }
        // Advance separated from the tests above so the loop body carries no side effect
        at += MMGR_SWAR_BYTES;
    }

    while (at != full)
    {
        const embed_word src_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at);
        const embed_word other_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at);
        const embed_word term = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = src_word);

        if ((term != 0u) || (src_word != other_word))
        {
            const embed_word diff = cellul_diff_lanes(src_word ^ other_word);
            const size_t end_lane = (term != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = term) : MMGR_SWAR_BYTES;
            const size_t diff_lane =
                (diff != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = diff) : MMGR_SWAR_BYTES;
            // Explicit cast narrows the lane comparison into the embed_bool container
            return (embed_bool)(args->end_wins ? (end_lane <= diff_lane) : (end_lane < diff_lane));
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += MMGR_SWAR_BYTES;
    }

    if (rest != 0u)
    {
        const embed_word keep = EMBED_CALL(mask.lanes_below, ScrutMaskCfg, .bytes = rest);
        const embed_word src_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at);
        const embed_word other_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at);
        const embed_word term = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = src_word) & keep;
        const embed_word diff = cellul_diff_lanes(src_word ^ other_word) & keep;

        if ((diff | term) != 0u)
        {
            const size_t end_lane = (term != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = term) : MMGR_SWAR_BYTES;
            const size_t diff_lane =
                (diff != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = diff) : MMGR_SWAR_BYTES;
            // Explicit cast narrows the lane comparison into the embed_bool container
            return (embed_bool)(args->end_wins ? (end_lane <= diff_lane) : (end_lane < diff_lane));
        }
    }
    return args->end_wins;
}

/**
 * @brief Reports whether src reaches its terminator without differing from other, case folded.
 *
 * @param[in] args Bytes src and other, the extent cap, and end_wins [BORROWS].
 * @return         EMBED_TRUE when src's terminator precedes the first differing byte.
 * @note Folds the two words through lane.xor_ with ci set and tests the folded result, so a
 *       terminator and a difference are settled together on the word that carried either.
 * @note Carries no aligned run: where cellul_agree_cs lifts a boundary test out and walks matched
 *       addresses through the aligned load and cellul_agree_at, every word here goes through the
 *       unaligned load and resolves in place.
 * @note Reaching cap with neither a terminator nor a difference returns end_wins.
 * @warning Both src and other must be readable for cap bytes. The last short word is loaded whole
 *          and masked after, so up to MMGR_SWAR_BYTES - 1 bytes past cap are read from each.
 */
EMBED_INLINE embed_bool cellul_agree_ci(const CellulCtx *args)
{
    const size_t full = (args->cap / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES;
    const size_t rest = args->cap - full;
    size_t at = 0u;

    while (at != full)
    {
        const embed_word src_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at);
        const embed_word other_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at);
        const embed_word term = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = src_word);
        const embed_word fold =
            EMBED_CALL(lane.xor_, ScrutLaneCfg, .word = src_word, .val = other_word, .ci = EMBED_TRUE);

        if ((term | fold) != 0u)
        {
            const embed_word diff = cellul_diff_lanes(fold);
            const size_t end_lane = (term != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = term) : MMGR_SWAR_BYTES;
            const size_t diff_lane =
                (diff != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = diff) : MMGR_SWAR_BYTES;
            // Explicit cast narrows the lane comparison into the embed_bool container
            return (embed_bool)(args->end_wins ? (end_lane <= diff_lane) : (end_lane < diff_lane));
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += MMGR_SWAR_BYTES;
    }

    if (rest != 0u)
    {
        const embed_word keep = EMBED_CALL(mask.lanes_below, ScrutMaskCfg, .bytes = rest);
        const embed_word src_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at);
        const embed_word other_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at);
        const embed_word term = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = src_word) & keep;
        const embed_word fold =
            EMBED_CALL(lane.xor_, ScrutLaneCfg, .word = src_word, .val = other_word, .ci = EMBED_TRUE);
        const embed_word diff = cellul_diff_lanes(fold) & keep;

        if ((diff | term) != 0u)
        {
            const size_t end_lane = (term != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = term) : MMGR_SWAR_BYTES;
            const size_t diff_lane =
                (diff != 0u) ? EMBED_CALL(lane.first, ScrutLaneCfg, .mask = diff) : MMGR_SWAR_BYTES;
            // Explicit cast narrows the lane comparison into the embed_bool container
            return (embed_bool)(args->end_wins ? (end_lane <= diff_lane) : (end_lane < diff_lane));
        }
    }
    return args->end_wins;
}

/**
 * @brief Reads other[needle_offset] and folds it to lower case when ci is set.
 *
 * @param[in] args Needle bytes other, the offset needle_offset, and ci [BORROWS].
 * @return         The byte, with 'A' to 'Z' mapped to 'a' to 'z' when ci is set.
 * @warning other must be readable at needle_offset. Nothing here bounds the index, so the caller states it.
 */
EMBED_INLINE uint8_t cellul_ancorae_fold(const CellulCtx *args)
{
    // Explicit cast reads the needle byte as unsigned, so the range tests below do not depend on char's signedness
    const uint8_t needle_byte = (uint8_t)args->other[args->needle_offset];

    if (args->ci && (needle_byte >= (uint8_t)'A') && (needle_byte <= (uint8_t)'Z'))
    {
        // Explicit cast keeps the result in uint8_t. Bit 5 is what separates the two cases
        return (uint8_t)(needle_byte | 0x20u);
    }
    return needle_byte;
}

/**
 * @brief Returns the lanes of the word read from at that match the byte filling broadcast.
 *
 * @param[in] at        Haystack address the candidate word is read from [BORROWS].
 * @param[in] broadcast The sought byte, repeated in every lane.
 * @param[in] ci        Fold case while comparing.
 * @return              One high bit per lane that matched.
 * @note Takes its arguments directly rather than a CellulCtx. lane.eq answers the same question,
 *       but it rebuilds the broadcast from a byte on every call, and the sieve's byte is fixed for
 *       the whole walk, and passing the broadcast in is what lets it be built once.
 * @warning at must be readable for MMGR_SWAR_BYTES bytes. The load takes a whole word however few
 *          are wanted, so the caller places at where that many remain.
 */
EMBED_INLINE embed_word cellul_sieve_hit(const char *at, embed_word broadcast, embed_bool ci)
{
    const embed_word loaded = EMBED_CALL(word.load, ScrutWordCfg, .at = at);
    const embed_word diff = ci ? EMBED_CALL(lane.xor_, ScrutLaneCfg, .word = loaded, .val = broadcast, .ci = EMBED_TRUE)
                               : (loaded ^ broadcast);

    return EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = diff);
}

/**
 * @brief Chooses the needle offsets whose bytes cost least, for the search sieve.
 *
 * @param[in,out] args Needle other, its needle_len, ci, and the rows array to fill [BORROWS].
 * @return             Number of offsets written to args->rows, at most MMGR_SIEVE_ROWS.
 * @note Only the first MMGR_SWAR_BYTES of the needle are candidates, since one word is tested at a time.
 * @note Cost comes from ancorae.impensa, so rarer bytes are preferred.
 * @warning other must be readable for needle_len bytes, of which at most MMGR_SWAR_BYTES are read, and
 *          rows must hold MMGR_SIEVE_ROWS entries. Neither is checked here.
 */
EMBED_INLINE size_t cellul_pick_rows(const CellulCtx *args)
{
    const size_t limit = (args->needle_len > MMGR_SWAR_BYTES) ? MMGR_SWAR_BYTES : args->needle_len;
    const size_t want = (limit > MMGR_SIEVE_ROWS) ? MMGR_SIEVE_ROWS : limit;

    for (size_t row = 0; row < want; ++row)
    {
        size_t best = 0;
        // 255 is the largest cost a uint8_t holds, so it acts as the no-row-chosen sentinel and any
        // real cost from ancorae.impensa compares below it
        uint8_t best_cost = 255;

        for (size_t offset = 0; offset < limit; ++offset)
        {
            size_t taken = 0;

            // Only rows 0 through row - 1 have been chosen so far, so the scan for an offset already
            // taken stops at row
            for (size_t prior = 0; prior < row; ++prior)
            {
                if (args->rows[prior] == offset)
                {
                    taken = 1;
                }
            }

            const uint8_t cost = EMBED_CALL(ancorae.impensa, AncoraeCfg,
                                            .byte = cellul_ancorae_fold(&(CellulCtx){
                                                .other = args->other, .needle_offset = offset, .ci = args->ci}));
            if (!taken && (cost < best_cost))
            {
                best_cost = cost;
                best = offset;
            }
        }
        args->rows[row] = best;
    }
    return want;
}

/**
 * @brief The word one byte along, taken from the current word and the byte past it rather than reloaded.
 *
 * @param[in] current The word at some offset.
 * @param[in] next    The byte at that offset plus MMGR_SWAR_BYTES.
 * @return            The word the load at that offset plus one would have returned.
 * @note A word load at an odd address goes through mmgr_proxim_word_t, which carries EMBED_ALIGN(1),
 *       and neither Xtensa nor RISC-V has an unaligned word load - the compiler assembles one out of
 *       MMGR_SWAR_BYTES byte loads and shifts. Deriving it costs one byte load, one shift and an or.
 * @note Branches on MMGR_HW_BIG_ENDIAN because this is lane order, not wire order: which end of the
 *       word byte zero sits at. verbum_scrutor decides the same question the same way. The endian
 *       module answers a different one - what order a value is written in - and does not apply.
 */
#if !MMGR_HW_FAST_UNALIGNED
EMBED_INLINE embed_word cellul_word_next(embed_word current, uint8_t next)
{
#if MMGR_HW_BIG_ENDIAN
    // Explicit casts hold the shifted word and the byte entering the low lane at embed_word width
    return (embed_word)((current << 8u) | (embed_word)next);
#else
    // Explicit casts hold the shifted word and the byte entering the high lane at embed_word width
    return (embed_word)((current >> 8u) | ((embed_word)next << (EMBED_WORD_BITS - 8u)));
#endif
}
#endif

/**
 * @brief Finds a needle of one or two bytes, case sensitively.
 *
 * @param[in] hay      Haystack [BORROWS].
 * @param[in] needle   Needle, of length nlen [BORROWS].
 * @param[in] nlen     Needle length, 1 or 2.
 * @param[in] read_cap Bytes readable at hay.
 * @param[in] starts   Start positions to consider, one past the last.
 * @return             Address of the match, or NULL when none precedes the terminator [BORROWS].
 * @note One broadcast per needle byte settles every start in a word at once: a lane matches when its
 *       byte equals the first and the byte after it equals the second. There is no anchor to choose
 *       and nothing to verify afterwards, which is the whole of what the sieve does.
 * @note Self-contained rather than folded into the sieve walk, tail and all. The two walks answer to
 *       different bounds - this one reads nlen - 1 bytes past its word, the sieve reads a whole
 *       verify span - and every previous attempt to share their structure cost more than it saved.
 * @warning Lanes at or past the terminator are dropped through mask.before, so a match that begins
 *          after the run ends is not reported.
 */
EMBED_INLINE const char *cellul_find_short(const char *hay, const char *needle, size_t nlen, size_t read_cap,
                                           size_t starts)
{
    // Explicit casts read the needle bytes as unsigned before they are repeated into every lane
    const embed_word bcast_first = MMGR_SWAR_ONES * (embed_word)(uint8_t)needle[0];
    const embed_word bcast_second = (nlen == 2u) ? (MMGR_SWAR_ONES * (embed_word)(uint8_t)needle[1]) : 0u;

    // A word step reads the word at `at` and, for a two-byte needle, the one at `at + 1`, so it needs
    // MMGR_SWAR_BYTES + nlen - 1 bytes in hand.
    const size_t span = MMGR_SWAR_BYTES + (nlen - 1u);
    const size_t safe = (read_cap >= span) ? ((read_cap - span) + 1u) : 0u;
    const size_t reach = (safe > starts) ? starts : safe;

    // Bytes to the first word boundary, so the walk below reads through the aligned load. See
    // cellul_head_bytes. Normally none, and the starts it covers are taken one at a time first.
    const size_t lead = cellul_head_bytes(hay, reach);
    const size_t word_count = (reach - lead) / MMGR_SWAR_BYTES;

    for (size_t start = 0; start < lead; ++start)
    {
        // Explicit casts read both bytes as unsigned, so neither test depends on char's signedness
        const uint8_t here = (uint8_t)hay[start];

        if (here == 0u)
        {
            return NULL;
        }
        // The first byte has to match, and for a two-byte needle so does the one after it. The nlen
        // test is fixed for the whole call and is there only to skip the second compare
        if ((here == (uint8_t)needle[0]) && ((nlen == 1u) || ((uint8_t)hay[start + 1u] == (uint8_t)needle[1])))
        {
            return hay + start;
        }
    }

    for (size_t word_index = 0; word_index < word_count; ++word_index)
    {
        const size_t at = lead + (word_index * MMGR_SWAR_BYTES);
        const embed_word loaded = EMBED_CALL(word.load_al, ScrutWordCfg, .at = hay + at);
        const embed_word end = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = loaded);
        embed_word starts_here = EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = loaded ^ bcast_first);

        if (nlen == 2u)
        {
            // Where the hardware loads a word from any address in one instruction, that is cheaper
            // than deriving it. Where it does not, the load is a dozen instructions and deriving it
            // from the word already in hand costs three.
#if MMGR_HW_FAST_UNALIGNED
            const embed_word loaded_next = EMBED_CALL(word.load, ScrutWordCfg, .at = hay + at + 1u);
#else
            // Explicit cast reads the byte past this word as unsigned, matching the lane it fills
            const embed_word loaded_next = cellul_word_next(loaded, (uint8_t)hay[at + MMGR_SWAR_BYTES]);
#endif
            starts_here &= EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = loaded_next ^ bcast_second);
        }
        if (end != 0u)
        {
            starts_here &= EMBED_CALL(mask.before, ScrutMaskCfg, .mask = end);
        }
        if (starts_here != 0u)
        {
            return hay + at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = starts_here);
        }
        if (end != 0u)
        {
            return NULL;
        }
    }

    for (size_t start = lead + (word_count * MMGR_SWAR_BYTES); start < starts; ++start)
    {
        // Explicit casts read both bytes as unsigned, so neither test depends on char's signedness
        const uint8_t here = (uint8_t)hay[start];

        if (here == 0u)
        {
            return NULL;
        }
        // The first byte has to match, and for a two-byte needle so does the one after it. The nlen
        // test is fixed for the whole call and is there only to skip the second compare
        if ((here == (uint8_t)needle[0]) && ((nlen == 1u) || ((uint8_t)hay[start + 1u] == (uint8_t)needle[1])))
        {
            return hay + start;
        }
    }
    return NULL;
}

/**
 * @brief Finds the first occurrence of the needle inside the haystack.
 *
 * @param[in] args Haystack src with cap, and needle other with other_cap [BORROWS].
 * @param[in] ci   Fold case while matching.
 * @return         Address of the match, or NULL when there is none [BORROWS].
 * @note An empty needle returns the haystack start. A needle longer than cap returns NULL.
 * @note Candidate words are sieved on the cheapest needle offsets, then verified in full.
 * @note Word scanning covers only the starts that stay in bounds. The rest are walked one byte at a
 *       time.
 * @note args->needle_len when the caller knows the needle's length, and only otherwise a measure of it. A
 *       needle is nearly always a literal, so its length is settled before the build and measuring it
 *       on every call is work the caller already did.
 * @warning src must be readable for cap bytes and other for other_cap bytes. The needle is loaded a
 *          whole word at a time and masked after, so up to MMGR_SWAR_BYTES - 1 bytes past other_cap
 *          are read. The haystack walk holds itself inside cap.
 */
EMBED_INLINE const char *cellul_find_core(const CellulCtx *args, embed_bool ci)
{
    const char *const hay = args->src;
    const char *const needle = args->other;
    const size_t read_cap = args->cap;

    const size_t nlen =
        (args->needle_len != 0u) ? args->needle_len : cellul_len(&(CellulCtx){.src = needle, .cap = args->other_cap});

    if (nlen == 0u)
    {
        return hay;
    }
    if (nlen > read_cap)
    {
        return NULL;
    }

    const size_t take = (nlen > MMGR_SWAR_BYTES) ? MMGR_SWAR_BYTES : nlen;
    const size_t starts = read_cap - nlen + 1u;

    // A needle this short is settled by a mask chain, with no anchor to choose and nothing to verify.
    // The sieve below earns its prologue by finding a rare byte in a long needle and proving the rest
    // once. Over one or two bytes there is no rare byte to find and no rest to prove, and the
    // prologue is most of the call.
    if ((nlen <= 2u) && !ci && (read_cap <= MMGR_FIND_CHAIN_MAX))
    {
        return cellul_find_short(hay, needle, nlen, read_cap, starts);
    }

    const size_t tail =
        (nlen > take) ? (EMBED_CALL(word.count, ScrutWordCfg, .bytes = nlen - take) * MMGR_SWAR_BYTES) : 0u;
    const size_t verify_reach = (MMGR_SWAR_BYTES - 1u) + take + tail;

    size_t rows[MMGR_SIEVE_ROWS];
    const size_t nrows = cellul_pick_rows(&(CellulCtx){.other = needle, .needle_len = nlen, .rows = rows, .ci = ci});

    const embed_word nmask = EMBED_CALL(mask.bytes_below, ScrutMaskCfg, .bytes = take);
    const embed_word nraw = EMBED_CALL(word.load, ScrutWordCfg, .at = needle) & nmask;
    const embed_word nword = ci ? (EMBED_CALL(word.fold_lower, ScrutWordCfg, .word = nraw) & nmask) : nraw;

    size_t maxrow = rows[0];

    for (size_t row = 1; row < nrows; ++row)
    {
        if (rows[row] > maxrow)
        {
            maxrow = rows[row];
        }
    }

    const size_t ancorae_reach = maxrow + MMGR_SWAR_BYTES;
    const size_t reach = (ancorae_reach > verify_reach) ? ancorae_reach : verify_reach;

    size_t safe = (read_cap >= reach) ? ((read_cap - reach) + 1u) : 0u;

    if (safe > starts)
    {
        safe = starts;
    }

    const size_t word_count = safe / MMGR_SWAR_BYTES;

    // The sieve's bytes broadcast once, ahead of the walk. They depend only on the needle, which
    // does not move, and rebuilding a broadcast is a multiply that would otherwise land on every
    // haystack word.
    embed_word bcast[MMGR_SIEVE_ROWS];

    for (size_t row = 0; row < nrows; ++row)
    {
        // Explicit casts read the needle byte as unsigned, then widen it into the lane it fills
        bcast[row] = MMGR_SWAR_ONES * (embed_word)(uint8_t)needle[rows[row]];
    }

    for (size_t word_index = 0; word_index < word_count; ++word_index)
    {
        const size_t at = word_index * MMGR_SWAR_BYTES;
        const embed_word end =
            EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = EMBED_CALL(word.load, ScrutWordCfg, .at = hay + at));
        embed_word survivors = cellul_sieve_hit(hay + at + rows[0], bcast[0], ci);

        for (size_t row = 1; row < nrows; ++row)
        {
            survivors &= cellul_sieve_hit(hay + at + rows[row], bcast[row], ci);
        }

        if (end != 0)
        {
            survivors &= EMBED_CALL(mask.before, ScrutMaskCfg, .mask = end);
        }

        while (survivors != 0)
        {
            const size_t start = at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = survivors);
            const embed_word candidate_word = EMBED_CALL(word.load, ScrutWordCfg, .at = hay + start);

            // A plain xor answers whenever there is no case to fold - either the caller did not ask
            // for it, or the candidate word carries no upper case - and the folding xor is reached
            // only when there is
            const embed_word diff =
                ((!ci || (EMBED_CALL(lane.any_upper, ScrutLaneCfg, .word = candidate_word) == 0))
                     ? (candidate_word ^ nword)
                     : EMBED_CALL(lane.xor_, ScrutLaneCfg, .word = candidate_word, .val = nword, .ci = EMBED_TRUE)) &
                nmask;

            if (diff == 0)
            {
                if (take == nlen)
                {
                    return hay + start;
                }

                const CellulCtx rest = {.src = hay + start + take, .other = needle + take, .cap = nlen - take};
                const size_t agreed = ci ? cellul_diff_ci(&rest) : cellul_diff_cs(&rest);

                if (agreed == (nlen - take))
                {
                    return hay + start;
                }
            }
            survivors = EMBED_CALL(mask.drop_first, ScrutMaskCfg, .mask = survivors);
        }
        if (end != 0)
        {
            return NULL;
        }
    }

    for (size_t start = word_count * MMGR_SWAR_BYTES; start < starts; ++start)
    {
        if (hay[start] == '\0')
        {
            return NULL;
        }

        size_t matched = 0;
        while (matched < nlen)
        {
            // Explicit casts read both bytes as unsigned, matching CellulCtx::byte_left and ::byte_right
            const uint8_t here = (uint8_t)hay[start + matched];
            const uint8_t want = (uint8_t)needle[matched];

            if (here == 0u)
            {
                break;
            }
            // The case-sensitive step is a byte compare once the terminator is out of the way, so it
            // is written as one. This walk covers the starts the word loop could not reach, which on
            // a short haystack is most of them, and reaching cellul_step_byte_cs through a CellulCtx
            // for every byte of every start is what made find cost twice libc at eight bytes.
            if (ci)
            {
                const CellulCtx pair = {.byte_left = want, .byte_right = here, .end_wins = EMBED_FALSE};

                if (cellul_step_byte_ci(&pair) == MMGR_SWAR_NO)
                {
                    break;
                }
            }
            else if (here != want)
            {
                break;
            }
            // Advance separated from the tests above so the loop body carries no side effect
            ++matched;
        }
        if (matched == nlen)
        {
            return hay + start;
        }
    }
    return NULL;
}

/**
 * @brief Copies src into dst and terminates it, writing at most cap bytes in total.
 *
 * @param[in,out] args Source src, destination dst, and the destination extent cap [BORROWS].
 * @return             Bytes copied, not counting the terminator.
 * @note A cap of 0 copies nothing and writes no terminator.
 * @note The source is measured against cap minus one, leaving room for the terminator.
 * @warning dst must be writable for cap bytes, and src readable until its terminator or cap minus
 *          one bytes, whichever comes first.
 */
EMBED_INLINE size_t cellul_copy(const CellulCtx *args)
{
    if (args->cap == 0u)
    {
        return 0u;
    }

    const size_t limit = args->cap - 1u;
    size_t at = 0u;

    // One walk rather than two. Measuring with cellul_len and then copying with proxim.read reads
    // every byte twice. A word that holds no terminator is one this can store as it goes. Measured
    // 1.46x to 1.66x on an ESP32-S3, which also takes it past the strncpy it is compared with.
    // Explicit casts read both addresses as integers so one mask answers for both: the store is as
    // wide as the load, so the word run needs the two on a boundary together
    if (((((uintptr_t)args->dst) | ((uintptr_t)args->src)) & (uintptr_t)(MMGR_SWAR_BYTES - 1u)) == 0u)
    {
        const size_t full = (limit / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES;

        while (at != full)
        {
            const embed_word loaded = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at);

            if (EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = loaded) != 0u)
            {
                break;
            }
            // Explicit cast widens the word into the uint64_t that ProximusCfg::val carries
            EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + at, .val = (uint64_t)loaded);
            // Advance separated from the store above so the loop body carries no side effect
            at += MMGR_SWAR_BYTES;
        }
    }

    // Whatever the word run did not take, which is the tail of a run that met a terminator, the
    // bytes below a boundary the two did not share, or the whole string when they never did
    while ((at != limit) && (args->src[at] != '\0'))
    {
        args->dst[at] = args->src[at];
        // Advance separated from the store above so the loop body carries no side effect
        at += 1u;
    }
    args->dst[at] = '\0';
    return at;
}

/**
 * @brief Reads an optionally signed decimal integer from src.
 *
 * @param[in,out] args Text src, and the optional end target [BORROWS].
 * @return             The value, negated when a minus sign was read.
 * @note Leading whitespace is skipped, then one optional '+' or '-'.
 * @note When end is not NULL it is set past the last digit, or back to src when no digit was read.
 * @warning The digit accumulator is embed_word wide and wraps on a longer run.
 * @warning src carries no bound. The read runs until the first byte that is not part of the number,
 *          so the caller owes one inside readable storage. A terminator is the usual one.
 */
EMBED_INLINE embed_iword cellul_to_long(const CellulCtx *args)
{
    const char *cursor = args->src;

    while (cellul_is_ws(*cursor))
    {
        cursor++;
    }

    embed_bool neg = EMBED_FALSE;
    if ((*cursor == '+') || (*cursor == '-'))
    {
        neg = (*cursor++ == '-');
    }

    const char *const digits_start = cursor;
    embed_word value = 0;
    while (cellul_is_digit(*cursor))
    {
        // Explicit casts hold the running value and the digit at embed_word width
        // The cursor++ belongs on a line of its own. An increment folded into this expression is the
        // side effect the standard bans, and the cursor advance does not depend on the arithmetic
        value = (embed_word)(value * 10u) + (embed_word)(*cursor++ - '0');
    }

    if (args->end != NULL)
    {
        *args->end = (cursor != digits_start) ? cursor : args->src;
    }
    if (neg)
    {
        // Explicit cast carries the unsigned negation into embed_iword. 0u - value wraps at embed_word
        // width first
        return (embed_iword)(0u - value);
    }
    // Explicit cast moves the accumulated value into the signed embed_iword container
    return (embed_iword)value;
}

/**
 * @brief Reads an unsigned decimal integer from src.
 *
 * @param[in,out] args Text src, and the optional end target [BORROWS].
 * @return             The accumulated value.
 * @note Leading whitespace is skipped, then one optional '+'. A '-' is not accepted and stops the read.
 * @note When end is not NULL it is set past the last digit, or back to src when no digit was read.
 * @warning The digit accumulator is embed_word wide and wraps on a longer run.
 * @warning src carries no bound. The read runs until the first byte that is not part of the number,
 *          so the caller owes one inside readable storage. A terminator is the usual one.
 */
EMBED_INLINE embed_word cellul_to_ulong(const CellulCtx *args)
{
    const char *cursor = args->src;

    while (cellul_is_ws(*cursor))
    {
        cursor++;
    }
    if (*cursor == '+')
    {
        cursor++;
    }

    const char *const digits_start = cursor;
    embed_word value = 0;
    while (cellul_is_digit(*cursor))
    {
        // Explicit casts hold the running value and the digit at embed_word width
        // The cursor++ belongs on a line of its own. An increment folded into this expression is the
        // side effect the standard bans, and the cursor advance does not depend on the arithmetic
        value = (embed_word)(value * 10u) + (embed_word)(*cursor++ - '0');
    }

    if (args->end != NULL)
    {
        *args->end = (cursor != digits_start) ? cursor : args->src;
    }
    return value;
}

/**
 * @brief Reads a signed decimal exponent, advancing the cursor past it.
 *
 * @param[in,out] args Cursor cur and the exponent target exp [BORROWS].
 * @note The cursor sits on the 'e' or 'E', which is consumed first.
 * @note When no digit follows, the cursor is put back where it started and exp is left alone.
 * @note Digits beyond MMGR_MUTO_EXP_LIMIT are consumed but stop changing the value.
 * @warning The walk carries no bound. It stops at the first byte that is not a digit, which the
 *          caller owes inside readable storage.
 */
EMBED_INLINE void cellul_expo(const CellulCtx *args)
{
    const char *const mark = *args->cur;

    (*args->cur)++;

    embed_bool eneg = EMBED_FALSE;
    if ((**args->cur == '+') || (**args->cur == '-'))
    {
        // The increment belongs on a line of its own, as in cellul_to_long and cellul_to_ulong:
        // folded through the double indirection and into an assignment, it is the side effect the
        // standard bans
        eneg = (*(*args->cur)++ == '-');
    }
    if (!cellul_is_digit(**args->cur))
    {
        *args->cur = mark;
        return;
    }

    embed_iword ex = 0;
    while (cellul_is_digit(**args->cur))
    {
        if (ex < MMGR_MUTO_EXP_LIMIT)
        {
            // Explicit cast holds the accumulate in embed_iword. The guard above keeps it below the limit
            ex = (embed_iword)((ex * 10) + (**args->cur - '0'));
        }
        (*args->cur)++;
    }
    *args->exp = eneg ? -ex : ex;
}

/**
 * @brief Reads a decimal floating point number from src.
 *
 * @param[in,out] args Text src, and the optional end target [BORROWS].
 * @return             The value assembled by muto.scale from the mantissa and exponent.
 * @note Accepts leading whitespace, one optional sign, digits, one optional point, then an optional exponent.
 * @note Digits that no longer fit the mantissa advance the exponent instead, and a non-zero one sets the sticky rest.
 * @note An exponent is read only when at least one digit was seen before it.
 * @note When end is not NULL it is set past the number, or back to src when no digit was read.
 * @warning src carries no bound. The read runs until the first byte that is not part of the number,
 *          so the caller owes one inside readable storage. A terminator is the usual one.
 */
EMBED_INLINE double cellul_to_double(const CellulCtx *args)
{
    const char *cursor = args->src;

    while (cellul_is_ws(*cursor))
    {
        cursor++;
    }

    embed_bool neg = EMBED_FALSE;
    if ((*cursor == '+') || (*cursor == '-'))
    {
        // The increment belongs on a line of its own, as ++cursor does below. Folded into this
        // assignment it is the side effect the standard bans
        neg = (*cursor++ == '-');
    }

    embed_bool any = EMBED_FALSE;
    embed_u64 mant = 0;
    embed_iword drop = 0;
    embed_iword over = 0;
    embed_iword lost = 0;

    while (cellul_is_digit(*cursor))
    {
        if (!EMBED_CALL(muto.take, TransformoCfg, .mant = &mant, .digit = *cursor))
        {
            ++over;
            lost |= (*cursor != '0') ? 1 : 0;
        }
        any = EMBED_TRUE;
        ++cursor;
    }
    if (*cursor == '.')
    {
        ++cursor;
        while (cellul_is_digit(*cursor))
        {
            if (EMBED_CALL(muto.take, TransformoCfg, .mant = &mant, .digit = *cursor))
            {
                ++drop;
            }
            else
            {
                lost |= (*cursor != '0') ? 1 : 0;
            }
            any = EMBED_TRUE;
            ++cursor;
        }
    }

    embed_iword ex = 0;
    if (any && ((*cursor == 'e') || (*cursor == 'E')))
    {
        cellul_expo(&(CellulCtx){.cur = &cursor, .exp = &ex});
    }

    // Explicit cast holds the combined exponent in embed_iword, ex from the suffix and over and drop from the mantissa
    const double val = EMBED_CALL(muto.scale, TransformoCfg, .mant = &mant, .ex = (embed_iword)(ex + over - drop),
                                  .rest = lost, .neg = neg);

    if (args->end != NULL)
    {
        *args->end = any ? cursor : args->src;
    }
    return val;
}

/**
 * @brief Reads a decimal floating point number from src and narrows it to float.
 *
 * @param[in,out] args Text src, and the optional end target [BORROWS].
 * @return             The value from cellul_to_double, narrowed to float.
 * @note Rounding happens once, on the narrowing. The parse itself is done at double width.
 * @warning src carries no bound, exactly as cellul_to_double describes.
 */
EMBED_INLINE float cellul_to_float(const CellulCtx *args)
{
    // Explicit cast narrows the double result into the float container
    return (float)cellul_to_double(args);
}

/**
 * @brief Picks the folded or exact difference walk on args->ci.
 *
 * @param[in] args Bytes src and other, the extent cap, and ci [BORROWS].
 * @return         Offset of the first difference, or cap when the two agree.
 * @warning Both src and other must be readable for cap bytes. The last short word is loaded whole
 *          and masked after, so up to MMGR_SWAR_BYTES - 1 bytes past cap are read from each.
 */
EMBED_INLINE size_t cellul_diff(const CellulCtx *args)
{
    return args->ci ? cellul_diff_ci(args) : cellul_diff_cs(args);
}

/**
 * @brief Picks the folded or exact agreement walk on args->ci.
 *
 * @param[in] args Bytes src and other, the extent cap, ci and end_wins [BORROWS].
 * @return         EMBED_TRUE when src's terminator precedes the first difference.
 * @note The caller sets end_wins. It is clear for eq, so both must end together, and set for starts.
 * @warning Both src and other must be readable for cap bytes. The last short word is loaded whole
 *          and masked after, so up to MMGR_SWAR_BYTES - 1 bytes past cap are read from each.
 */
EMBED_INLINE embed_bool cellul_eq(const CellulCtx *args)
{
    return args->ci ? cellul_agree_ci(args) : cellul_agree_cs(args);
}

/**
 * @brief The same walk as cellul_eq, reached under the name the starts entry pastes.
 *
 * @param[in] args Bytes src and other, the extent cap, ci and end_wins [BORROWS].
 * @return         EMBED_TRUE when src's terminator precedes the first difference.
 * @note starts swaps the operands and sets end_wins in its entry line, so the walk is the same one.
 * @warning Both src and other must be readable for cap bytes. The last short word is loaded whole
 *          and masked after, so up to MMGR_SWAR_BYTES - 1 bytes past cap are read from each.
 */
EMBED_INLINE embed_bool cellul_starts(const CellulCtx *args)
{
    return cellul_eq(args);
}

/**
 * @brief Searches src for other, folding case on args->ci.
 *
 * @param[in] args Haystack src with cap, needle other with other_cap, and ci [BORROWS].
 * @return         Address of the match, or NULL when there is none [BORROWS].
 * @note Plain static, not EMBED_INLINE, and it is the only backend here that is. EMBED_INLINE carries
 *       always_inline, and cellul_has calls this one, so forcing it would emit the whole sieve search
 *       a second time inside has. Measured at 2880 bytes duplicated at -O2.
 * @warning src must be readable for cap bytes and other for other_cap bytes, with the needle read
 *          past other_cap exactly as cellul_find_core describes.
 */
static const char *cellul_find(const CellulCtx *args)
{
    return cellul_find_core(args, args->ci);
}

/**
 * @brief Reports whether cellul_find returns a match.
 *
 * @param[in] args Haystack src with cap, needle other with other_cap, and ci [BORROWS].
 * @return         EMBED_TRUE when the needle is present.
 * @warning src and other carry the same bounds cellul_find describes, needle over-read included.
 */
EMBED_INLINE embed_bool cellul_has(const CellulCtx *args)
{
    // Explicit cast narrows the pointer test into the embed_bool container
    return (embed_bool)(cellul_find(args) != NULL);
}

/**
 * @brief Tests the byte at src[at] for whitespace.
 *
 * @param[in] args Bytes src and the offset at [BORROWS].
 * @return         EMBED_TRUE for one of the six whitespace characters.
 * @warning src must be readable at at. cap is not consulted here.
 */
EMBED_INLINE embed_bool cellul_ws(const CellulCtx *args)
{
    return cellul_is_ws(args->src[args->at]);
}

/**
 * @brief Tests the byte at src[at] for a decimal digit.
 *
 * @param[in] args Bytes src and the offset at [BORROWS].
 * @return         EMBED_TRUE for '0' through '9'.
 * @warning src must be readable at at. cap is not consulted here.
 */
EMBED_INLINE embed_bool cellul_digit(const CellulCtx *args)
{
    return cellul_is_digit(args->src[args->at]);
}

/**
 * @brief Picks the folded or exact word step on args->ci.
 *
 * @param[in] args Words word_left and word_right, with ci and end_wins [BORROWS].
 * @return         MMGR_SWAR_GO, MMGR_SWAR_YES or MMGR_SWAR_NO.
 */
EMBED_INLINE embed_iword cellul_step_word(const CellulCtx *args)
{
    return args->ci ? cellul_step_word_ci(args) : cellul_step_word_cs(args);
}

/**
 * @brief Picks the folded or exact byte step on args->ci.
 *
 * @param[in] args Bytes byte_left and byte_right, with ci and end_wins [BORROWS].
 * @return         MMGR_SWAR_GO, MMGR_SWAR_YES or MMGR_SWAR_NO.
 */
EMBED_INLINE embed_iword cellul_step_byte(const CellulCtx *args)
{
    return args->ci ? cellul_step_byte_ci(args) : cellul_step_byte_cs(args);
}

/**
 * @brief Returns a copy of the argument struct.
 *
 * @note Hand-rolled rather than an entry line, as mmgr_anular_init is: it returns a CatenaFinitaCfg
 *       rather than forwarding one, so there is no argument pack for EMBED_ENTRY to build.
 * @note The name is parenthesized so a like-named macro from mmgr_string_shim.h cannot expand here.
 * @note Documented at the declaration in cellularum_laboro.h.
 */
CatenaFinitaCfg(mmgr_cellul_init)(const CatenaFinitaCfg *args)
{
    return *args;
}

/**
 * @brief Binds the string calls to the entry shape, keeping the parenthesized name.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_cellul_ and cellul_ prefixes, which the two share.
 * @param[in] ...         Initializers for the CellulCtx literal, written in terms of args.
 * @note Written out rather than reached for as EMBED_ENTRY, and this is the only module that does
 *       so. EMBED_ENTRY pastes the entry name bare, and these names must stay parenthesized so a
 *       like-named macro from mmgr_string_shim.h cannot expand over them. The body is otherwise the
 *       one EMBED_ENTRY builds, which infinitas reaches through RING_ENTRY.
 */
#define CELLUL_ENTRY(ReturnType_, name_, ...)                                                                          \
    ReturnType_(mmgr_cellul_##name_)(const CatenaFinitaCfg *args)                                                      \
    {                                                                                                                  \
        return EMBED_CALL(cellul_##name_, CellulCtx, __VA_ARGS__);                                                     \
    }

/**
 * @brief The same shape for the single-step compares, which take their own argument type.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_cellul_ and cellul_ prefixes.
 * @param[in] ...         Initializers for the CellulCtx literal, written in terms of args.
 */
#define CELLUL_STEP_ENTRY(ReturnType_, name_, ...)                                                                     \
    ReturnType_(mmgr_cellul_##name_)(const VerboProgrediorCfg *args)                                                   \
    {                                                                                                                  \
        return EMBED_CALL(cellul_##name_, CellulCtx, __VA_ARGS__);                                                     \
    }

/**
 * @brief The same shape for the conversions, which take their own argument type.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] name_       Name after the mmgr_cellul_ and cellul_ prefixes.
 * @param[in] ...         Initializers for the CellulCtx literal, written in terms of args.
 */
#define CELLUL_CONV_ENTRY(ReturnType_, name_, ...)                                                                     \
    ReturnType_(mmgr_cellul_##name_)(const TransfiguroCfg *args)                                                       \
    {                                                                                                                  \
        return EMBED_CALL(cellul_##name_, CellulCtx, __VA_ARGS__);                                                     \
    }

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in cellularum_laboro.h.
 * @note The fields each line forwards are the ones that entry reads; EMBED_CALL zeroes the rest.
 * @note eq and starts reach the same backend. starts swaps src and other and sets end_wins, so it is
 *       other that is measured for its terminator and the prefix may end early.
 */
CELLUL_ENTRY(size_t, len, .src = args->src + args->at, .cap = args->cap - args->at)
CELLUL_ENTRY(size_t, diff, .src = args->src, .other = args->other, .cap = args->cap, .ci = args->ci)
CELLUL_ENTRY(embed_bool, eq, .src = args->src, .other = args->other, .cap = args->cap, .ci = args->ci,
             .end_wins = EMBED_FALSE)
CELLUL_ENTRY(embed_bool, starts, .src = args->other, .other = args->src, .cap = args->cap, .ci = args->ci,
             .end_wins = EMBED_TRUE)
CELLUL_ENTRY(const char *, find, .src = args->src, .cap = args->cap, .other = args->other, .other_cap = args->other_cap,
             .needle_len = args->other_len, .ci = args->ci)
CELLUL_ENTRY(embed_bool, has, .src = args->src, .cap = args->cap, .other = args->other, .other_cap = args->other_cap,
             .needle_len = args->other_len, .ci = args->ci)
CELLUL_ENTRY(const char *, chr, .src = args->src, .cap = args->cap, .byte = args->byte)
CELLUL_ENTRY(size_t, copy, .dst = args->dst, .src = args->src, .cap = args->cap)
CELLUL_ENTRY(embed_bool, ws, .src = args->src, .at = args->at)
CELLUL_ENTRY(embed_bool, digit, .src = args->src, .at = args->at)
CELLUL_STEP_ENTRY(embed_iword, step_word, .word_left = args->word_left, .word_right = args->word_right, .ci = args->ci,
                  .end_wins = args->end_wins)
CELLUL_STEP_ENTRY(embed_iword, step_byte, .byte_left = args->byte_left, .byte_right = args->byte_right, .ci = args->ci,
                  .end_wins = args->end_wins)
CELLUL_CONV_ENTRY(embed_iword, to_long, .src = args->src, .end = args->end)
CELLUL_CONV_ENTRY(embed_word, to_ulong, .src = args->src, .end = args->end)
CELLUL_CONV_ENTRY(double, to_double, .src = args->src, .end = args->end)
CELLUL_CONV_ENTRY(float, to_float, .src = args->src, .end = args->end)
