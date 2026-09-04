/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file memoria_operor.c
 * @brief Byte-level copy, move, compare, search and fill.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note cpy and set move whole words then odd bytes, move_up takes the odd bytes first, and cmp and
 *       chr mask the tail lanes instead.
 */
#include "memoria_operor/memoria_operor.h"

#include "proximus_operor/proximus_operor.h"
#include "verbum_scrutor/verbum_scrutor.h"

/**
 * @brief Arguments for the forward copy.
 *
 * @warning Both pointers are restrict qualified, so the two regions must not overlap.
 */
typedef struct
{
    uint8_t *restrict dst;       /**< Destination [BORROWS]. */
    const uint8_t *restrict src; /**< Source [BORROWS]. */
    size_t bytes;                /**< Bytes to copy. */
} MemorCpyCtx;

/**
 * @brief Arguments for the backward move.
 *
 * @note Neither pointer is restrict qualified, unlike MemorCpyCtx.
 */
typedef struct
{
    uint8_t *dst;       /**< Destination [BORROWS]. */
    const uint8_t *src; /**< Source [BORROWS]. */
    size_t bytes;       /**< Bytes to move. */
} MemorMoveCtx;

/**
 * @brief Arguments for the compare and the byte search.
 *
 * @note cmp reads src, other and bytes. chr reads src, bytes and val.
 */
typedef struct
{
    const uint8_t *src;   /**< First region, and the one chr searches [BORROWS]. */
    const uint8_t *other; /**< Second region for cmp [BORROWS]. */
    size_t bytes;         /**< Bytes to examine. */
    uint8_t val;          /**< Byte chr looks for. */
} MemorScanCtx;

/**
 * @brief Arguments for the fill.
 */
typedef struct
{
    uint8_t *dst; /**< Destination [BORROWS]. */
    size_t bytes; /**< Bytes to write. */
    uint8_t val;  /**< Byte to write into each of them. */
} MemorSetCtx;

/**
 * @brief Copies args->bytes from args->src to args->dst, walking upward.
 *
 * @param[in,out] args Destination, source and count [BORROWS].
 * @note Moves whole words first, then the remaining bytes one at a time.
 * @note Advances args->dst and args->src as it goes, so both point past the copy when it returns.
 * @warning The regions must not overlap. MemorCpyCtx declares both pointers restrict.
 * @warning args->dst must be writable and args->src readable for args->bytes.
 */
EMBED_INLINE void memor_cpy(MemorCpyCtx *args)
{
    // Explicit cast holds the remainder mask at size_t, matching the byte count it is applied to
    size_t tail_bytes = args->bytes & (size_t)(sizeof(embed_word) - 1u);
    size_t word_bytes = args->bytes - tail_bytes;

    // Four words an iteration while there are four to take. At one word the two pointer bumps, the
    // counter and the branch cost as much as the move itself. At four, the same bookkeeping covers
    // four times the bytes. ROM memcpy is unrolled for the same reason, and a one-word loop here
    // measured 1.02 cycles/byte against its 0.65 on the S3.
    while (word_bytes >= (4u * sizeof(embed_word)))
    {
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst,
                   .val = EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->src));
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + sizeof(embed_word),
                   .val = EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->src + sizeof(embed_word)));
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + (2u * sizeof(embed_word)),
                   .val = EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->src + (2u * sizeof(embed_word))));
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + (3u * sizeof(embed_word)),
                   .val = EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->src + (3u * sizeof(embed_word))));

        // Advances separated from the moves above so the loop body carries no side effect
        args->dst += 4u * sizeof(embed_word);
        args->src += 4u * sizeof(embed_word);
        word_bytes -= 4u * sizeof(embed_word);
    }
    while (word_bytes != 0u)
    {
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst,
                   .val = EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->src));
        args->dst += sizeof(embed_word);
        args->src += sizeof(embed_word);
        word_bytes -= sizeof(embed_word);
    }
    if (tail_bytes != 0u)
    {
        do
        {
            *args->dst++ = *args->src++;
        } while (--tail_bytes);
    }
}

/**
 * @brief Copies args->bytes from args->src to args->dst, walking downward from the far end.
 *
 * @param[in,out] args Destination, source and count [BORROWS].
 * @note Starts at the end of both regions and works back toward the start.
 * @note Takes the odd bytes first, then whole words, which is the reverse of memor_cpy's order.
 * @note Advances both pointers to the end, then walks them back, so each ends where it began.
 * @note What this is worth is not one number. Measured 2026-09-03 at -O2 against each part's own
 *       memmove, over 8 to 2048 bytes with the two regions MMGR_ALIGN_BYTES apart: on an ESP32-S3
 *       this runs 2.7x to 14.0x faster, since that part's memmove walks a byte at a time and never
 *       comes under nine cycles a byte at any length. On an ESP32-C6 it runs 1.1x to 2.6x faster,
 *       where memmove costs about 1.8 cycles a byte. Nothing in the library differs between the two
 *       runs. A byte path is only ever as good as the mem family the part it lands on happens to
 *       carry.
 * @note At 2048 bytes this costs 0.646 cycles a byte on the S3 and 0.707 on the C6. The S3 figure
 *       is level with mmgr_memor_cpy's 0.644, which is where a backward move belongs - the address
 *       arithmetic is a subtraction either way and neither direction is inherently dearer. It got
 *       there by taking the same four word width memor_cpy takes. Before that it was 1.517 and
 *       1.763, entirely for want of the unroll.
 * @note The C6 figure is under mmgr_memor_cpy's 0.892 on that part, because the four loads here are
 *       taken before the four stores and memor_cpy interleaves its own. Measured as its own row,
 *       that ordering is worth nothing on the S3 and 1.27x on the C6.
 * @warning args->dst must be writable and args->src readable for args->bytes.
 */
EMBED_INLINE void memor_move_up(MemorMoveCtx *args)
{
    // Explicit cast holds the remainder mask at size_t, matching the byte count it is applied to
    size_t tail_bytes = args->bytes & (size_t)(sizeof(embed_word) - 1u);
    size_t word_bytes = args->bytes - tail_bytes;

    args->dst += args->bytes;
    args->src += args->bytes;

    if (tail_bytes != 0u)
    {
        do
        {
            *--args->dst = *--args->src;
        } while (--tail_bytes);
    }
    // Four words an iteration while there are four to take, for the reason memor_cpy gives: at one
    // word a pass the two pointer bumps, the counter and the branch cost as much as the move. All
    // four loads are taken before any store, which neither pointer being restrict qualified stops -
    // the compiler cannot lift a load over a store on its own here, and this arrangement does not
    // ask it to. Measured at 2048 bytes: 1.517 cycles a byte to 0.643 on an ESP32-S3 and 1.763 to
    // 0.697 on an ESP32-C6, which puts both level with the forward copy. The ordering is worth
    // nothing on the S3 and 1.27x on the C6.
    while (word_bytes >= (4u * sizeof(embed_word)))
    {
        args->dst -= 4u * sizeof(embed_word);
        args->src -= 4u * sizeof(embed_word);

        const embed_word word_three = EMBED_CALL(proxim.al_load, ProximusCfg,
                                                 .at = args->src + (3u * sizeof(embed_word)));
        const embed_word word_two = EMBED_CALL(proxim.al_load, ProximusCfg,
                                               .at = args->src + (2u * sizeof(embed_word)));
        const embed_word word_one = EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->src + sizeof(embed_word));
        const embed_word word_zero = EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->src);

        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + (3u * sizeof(embed_word)), .val = word_three);
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + (2u * sizeof(embed_word)), .val = word_two);
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + sizeof(embed_word), .val = word_one);
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst, .val = word_zero);

        word_bytes -= 4u * sizeof(embed_word);
    }
    while (word_bytes != 0u)
    {
        args->dst -= sizeof(embed_word);
        args->src -= sizeof(embed_word);
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst,
                   .val = EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->src));
        word_bytes -= sizeof(embed_word);
    }
}

/**
 * @brief Bytes between p and the first word boundary at or after it, capped at bytes.
 *
 * @param[in] at    Address a walk is about to start from [BORROWS].
 * @param[in] bytes Bytes readable at that address, which the answer never exceeds.
 * @return          Bytes to step one at a time before whole aligned words can be read.
 * @note Normally zero. This library is built for memory that arrives aligned, and an aligned address
 *       is already on a boundary. It is computed rather than assumed because a region entry takes
 *       whatever address a caller hands it.
 * @warning at is examined as an address and never read, so a bytes larger than the region there is
 *          not caught here. The answer is capped at bytes, so it is a safe number of steps only when
 *          bytes is.
 */
EMBED_INLINE size_t memor_head_bytes(const uint8_t *at, size_t bytes)
{
    // Explicit cast reads the address as an integer so its low bits can be tested. The value is
    // never dereferenced through it and never converted back
    const size_t past_boundary = (size_t)((uintptr_t)at & (uintptr_t)(MMGR_SWAR_BYTES - 1u));
    const size_t to_boundary = (past_boundary == 0u) ? 0u : (MMGR_SWAR_BYTES - past_boundary);

    return (to_boundary > bytes) ? bytes : to_boundary;
}

/**
 * @brief Turns a lane-wise difference word into the mask of lanes that differ.
 *
 * @param[in] difference Zero in every lane where the two sides agreed, non-zero where they did not.
 * @return               One high bit per differing lane.
 * @note Takes a word rather than a context type. memor_cmp shares it between the loop that reads
 *       whole words and the tail that reads the last one. Nothing dispatches to it.
 */
EMBED_INLINE embed_word memor_diff_lanes(embed_word difference)
{
    return MMGR_VERBUM_SCRUTOR_HIGH & ~EMBED_CALL(lane.has_zero, ScrutLaneCfg, .word = difference);
}

/**
 * @brief Compares args->bytes of args->src against args->other.
 *
 * @param[in] args The two regions and the count [BORROWS].
 * @return         The difference of the first unequal byte pair, or 0 when every byte matches.
 * @note Compares whole words with nothing but an inequality test, and resolves which lane differs
 *       once, after the loop has found the word that does. Which lane it is cannot matter until a
 *       word differs, and no word differs on all but one iteration of a scan.
 * @note The count is settled before the loop, so lanes past it can only fall in the last word.
 *       mask.lanes_below is applied to that word alone rather than rebuilt on every iteration.
 * @note The sign follows the differing bytes, so the result orders the two regions.
 * @warning Both args->src and args->other must be readable for args->bytes rounded up to a whole word.
 *          The tail goes through word.load, which takes MMGR_SWAR_BYTES whatever the count leaves.
 */
EMBED_INLINE embed_iword memor_cmp(MemorScanCtx *args)
{
    const size_t full = (args->bytes / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES;
    const size_t rest = args->bytes - full;
    size_t at = 0u;

    // Explicit casts read both addresses as integers so one mask answers for both. Two aligned
    // addresses select the loop that uses the aligned load, which is one instruction where the
    // unaligned one is a sequence on a part that has no unaligned access. Alignment is tested once
    // here rather than once a word. Measured 3.55x on an ESP32-C6 over two thousand bytes, which
    // took the comparison from 6.27 cycles a byte to 1.76 and past memcmp's 2.14
    const embed_bool level =
        (embed_bool)(((((uintptr_t)args->src) | ((uintptr_t)args->other)) & (uintptr_t)(MMGR_SWAR_BYTES - 1u)) == 0u);

    // Two loops rather than one carrying the test. With the choice written inside the body, the
    // compiler keeps a branch per word and the loop costs what the unaligned one costs. Lifted
    // out, each loop holds one kind of load, and the aligned one is a single instruction a word
    if (level)
    {
        while (at != full)
        {
            const embed_word src_word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at);
            const embed_word other_word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->other + at);

            if (src_word != other_word)
            {
                const size_t first_diff =
                    at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = memor_diff_lanes(src_word ^ other_word));

                // Explicit casts widen both bytes to embed_iword so the difference keeps its sign
                return (embed_iword)args->src[first_diff] - (embed_iword)args->other[first_diff];
            }
            // Advance separated from the test above so the loop body carries no side effect
            at += MMGR_SWAR_BYTES;
        }
    }
    else
    {
        while (at != full)
        {
            const embed_word src_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at);
            const embed_word other_word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at);

            if (src_word != other_word)
            {
                const size_t first_diff =
                    at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = memor_diff_lanes(src_word ^ other_word));

                // Explicit casts widen both bytes to embed_iword so the difference keeps its sign
                return (embed_iword)args->src[first_diff] - (embed_iword)args->other[first_diff];
            }
            // Advance separated from the test above so the loop body carries no side effect
            at += MMGR_SWAR_BYTES;
        }
    }

    if (rest != 0u)
    {
        const embed_word difference = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at) ^
                                      EMBED_CALL(word.load, ScrutWordCfg, .at = args->other + at);
        // Explicit cast holds the differing-lane mask at embed_word width, bounded to the bytes in range
        const embed_word differing_lanes =
            (embed_word)(memor_diff_lanes(difference) & EMBED_CALL(mask.lanes_below, ScrutMaskCfg, .bytes = rest));

        if (differing_lanes != 0u)
        {
            const size_t first_diff = at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = differing_lanes);

            // Explicit casts widen both bytes to embed_iword so the difference keeps its sign
            return (embed_iword)args->src[first_diff] - (embed_iword)args->other[first_diff];
        }
    }
    return 0;
}

/**
 * @brief Finds the first byte in args->src equal to args->val, within args->bytes.
 *
 * @param[in] args Region, count and the byte sought [BORROWS].
 * @return         Address of the match, or NULL when the byte does not occur [BORROWS].
 * @note Scans whole words with no mask at all, then masks the one short word at the end. The count
 *       is settled before the loop, so lanes past it can only fall in that last word.
 * @note The sought byte is broadcast once, ahead of the walk. lane.eq answers the same question but
 *       rebuilds the broadcast from a byte on every call, which is a multiply per word.
 * @note A terminator is not special here. All args->bytes are searched.
 * @warning args->src must be readable for args->bytes rounded up to a whole word. The tail goes
 *          through word.load, which takes MMGR_SWAR_BYTES whatever the count leaves.
 */
EMBED_INLINE const void *memor_chr(MemorScanCtx *args)
{
    // Bytes to the first word boundary, so the walk below reads through the aligned load. Normally
    // none, since this library is built for memory that arrives aligned. The unaligned load is not
    // one instruction on either shipping part - eleven on RISC-V, twelve on Xtensa, because neither
    // has it and the compiler assembles the word out of byte loads and shifts inside the walk.
    const size_t lead = memor_head_bytes(args->src, args->bytes);
    const size_t full = lead + (((args->bytes - lead) / MMGR_SWAR_BYTES) * MMGR_SWAR_BYTES);
    const size_t rest = args->bytes - full;
    // Explicit cast widens the sought byte into the lane it fills before it is repeated
    const embed_word broadcast = MMGR_SWAR_ONES * (embed_word)args->val;
    size_t at = 0u;

    while (at != lead)
    {
        if (args->src[at] == args->val)
        {
            return args->src + at;
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += 1u;
    }

    // One word a pass, deliberately. Unrolling this the way cellul_len is unrolled was measured and
    // lost: 6696 cycles to 6959 at 2048 bytes, and 64 to 72 at eight. This walk was already the
    // faster of the two before either was touched, so there was no stall left for a second word to
    // cover, and the extra prologue is all it added.
    while (at != full)
    {
        const embed_word matching_lanes =
            EMBED_CALL(lane.has_zero, ScrutLaneCfg,
                       .word = EMBED_CALL(word.load_al, ScrutWordCfg, .at = args->src + at) ^ broadcast);
        if (matching_lanes != 0u)
        {
            return args->src + at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = matching_lanes);
        }
        // Advance separated from the test above so the loop body carries no side effect
        at += MMGR_SWAR_BYTES;
    }

    if (rest != 0u)
    {
        // Explicit cast holds the match mask at embed_word width, bounded to the bytes in range
        const embed_word matching_lanes =
            (embed_word)(EMBED_CALL(lane.has_zero, ScrutLaneCfg,
                                    .word = EMBED_CALL(word.load, ScrutWordCfg, .at = args->src + at) ^ broadcast) &
                         EMBED_CALL(mask.lanes_below, ScrutMaskCfg, .bytes = rest));
        if (matching_lanes != 0u)
        {
            return args->src + at + EMBED_CALL(lane.first, ScrutLaneCfg, .mask = matching_lanes);
        }
    }
    return NULL;
}

/**
 * @brief Writes args->val into args->bytes of args->dst.
 *
 * @param[in,out] args Destination, count and the byte to write [BORROWS].
 * @note Builds a word with args->val in every lane, stores whole words, then finishes byte by byte.
 * @note Advances args->dst as it goes, so it points past the bytes it wrote when it returns.
 * @warning args->dst must be writable for args->bytes. Nothing past the count is written. The word
 *          stores cover a whole number of words, and the byte loop finishes what they leave.
 */
EMBED_INLINE void memor_set(MemorSetCtx *args)
{
    // Explicit casts broadcast the byte into every lane. MMGR_SWAR_ONES has a 1 in each lane's low bit
    const embed_word fill = (embed_word)(MMGR_SWAR_ONES * (embed_word)args->val);

    // Explicit cast holds the remainder mask at size_t, matching the byte count it is applied to
    size_t tail_bytes = args->bytes & (size_t)(sizeof(embed_word) - 1u);
    size_t word_bytes = args->bytes - tail_bytes;

    // Four words an iteration while there are four to take, for the reason memor_cpy gives: the
    // pointer bump, the counter and the branch cost as much as the store at one word a pass.
    while (word_bytes >= (4u * sizeof(embed_word)))
    {
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst, .val = fill);
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + sizeof(embed_word), .val = fill);
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + (2u * sizeof(embed_word)), .val = fill);
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst + (3u * sizeof(embed_word)), .val = fill);

        // Advances separated from the stores above so the loop body carries no side effect
        args->dst += 4u * sizeof(embed_word);
        word_bytes -= 4u * sizeof(embed_word);
    }
    while (word_bytes != 0u)
    {
        EMBED_CALL(proxim.al_put, ProximusCfg, .dst = args->dst, .val = fill);
        args->dst += sizeof(embed_word);
        word_bytes -= sizeof(embed_word);
    }
    if (tail_bytes != 0u)
    {
        do
        {
            *args->dst++ = args->val;
        } while (--tail_bytes);
    }
}

/**
 * @brief Binds this module's fixed arguments to EMBED_ENTRY, with the context type per entry.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] CtxType_    Context type this entry's backend takes.
 * @param[in] name_       Name after the mmgr_memor_ and memor_ prefixes, which the two share.
 * @param[in] ...         Initializers for the CtxType_ literal, written in terms of args.
 * @note CtxType_ is a parameter here, unlike locus_carcerum and memoria_anularis, which
 *       each have one. The backends split by what they touch: a copy takes two pointers, a scan takes
 *       two and a value, a fill takes one and a value, so each has its own argument type.
 */
#define MEMOR_ENTRY(ReturnType_, CtxType_, name_, ...)                                                                 \
    EMBED_ENTRY(mmgr_memor_, memor_, CtxType_, MemoriaCfg, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief Binds the same to EMBED_ENTRY_V, for an entry that returns nothing.
 *
 * @param[in] CtxType_ Context type this entry's backend takes.
 * @param[in] name_    Name after the mmgr_memor_ and memor_ prefixes.
 * @param[in] ...      Initializers for the CtxType_ literal, written in terms of args.
 */
#define MEMOR_ENTRY_V(CtxType_, name_, ...) EMBED_ENTRY_V(mmgr_memor_, memor_, CtxType_, MemoriaCfg, name_, __VA_ARGS__)

/**
 * @brief The public surface, one line per entry point.
 *
 * @note Each is documented at its declaration in memoria_operor.h.
 * @note Every line casts the caller's void pointers to the uint8_t pointers the context declares.
 * @note There is no move_down function. The dispatch table points that member at mmgr_memor_cpy,
 *       because a destination below the source is what the upward copy already handles.
 */
MEMOR_ENTRY_V(MemorCpyCtx, cpy, .dst = (uint8_t *)args->dst, .src = (const uint8_t *)args->src, .bytes = args->bytes)
MEMOR_ENTRY_V(MemorMoveCtx, move_up, .dst = (uint8_t *)args->dst, .src = (const uint8_t *)args->src,
              .bytes = args->bytes)
MEMOR_ENTRY(embed_iword, MemorScanCtx, cmp, .src = (const uint8_t *)args->src, .other = (const uint8_t *)args->other,
            .bytes = args->bytes)
MEMOR_ENTRY(const void *, MemorScanCtx, chr, .src = (const uint8_t *)args->src, .bytes = args->bytes, .val = args->val)
MEMOR_ENTRY_V(MemorSetCtx, set, .dst = (uint8_t *)args->dst, .bytes = args->bytes, .val = args->val)
