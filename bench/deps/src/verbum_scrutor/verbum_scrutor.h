/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file verbum_scrutor.h
 * @brief SWAR byte tests, the lane constants, the arguments, and the lane, mask and word dispatch
 *        tables.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note One embed_word is treated as MMGR_SWAR_BYTES independent lanes, so a whole word is tested at once.
 * @note A lane mask carries one set bit per matching lane, in that lane's high bit. mask.spread widens it.
 * @note The entries whose meaning depends on byte order are bound through MMGR_HW_BIG_ENDIAN in the tables below.
 */
#ifndef MMGR_VERBUM_SCRUTOR_H
#define MMGR_VERBUM_SCRUTOR_H

#include "proximus_operor/proximus_operor.h"

#include "mmgr.h"

EMBED_BEGIN_DECLS

/**
 * @brief Expands to sizeof(embed_word), which is how many lanes one word carries.
 *
 * @note Eight at EMBED_WORD_BITS 64, four at 32 and two at 16.
 * @note Also the value both lane index calls report when the mask they are given is empty.
 */
#define MMGR_SWAR_BYTES (sizeof(embed_word))

/**
 * @brief Expands to EMBED_WORD_BITS, the width of a whole word in bits.
 *
 * @note This is the word's width rather than one lane's, despite the name. A lane is eight bits.
 * @note Bounds the shift doubling in scrut_smear and supplies the final shift in scrut_lane_count, both of
 *       which want the whole width.
 */
#define MMGR_SWAR_LANE_BITS (EMBED_WORD_BITS)

/**
 * @brief Expands to a word holding 1 in every lane, which is 0x0101...01.
 *
 * @note Multiplying it by a byte broadcasts that byte into every lane, which is how the comparisons start.
 * @note Multiplying a lane mask by it sums the lanes, which is how scrut_lane_count counts them.
 */
#define MMGR_SWAR_ONES (((embed_word) ~(embed_word)0) / 0xFFu)

/**
 * @brief Expands to a word holding 0x80 in every lane, which is 0x8080...80.
 *
 * @note The shape every lane mask takes, so a caller can and two masks together lane by lane.
 * @note Or-ing it into a word before a subtraction gives each lane a borrow to spend, keeping lanes separate.
 */
#define MMGR_VERBUM_SCRUTOR_HIGH (MMGR_SWAR_ONES * 0x80u)

/**
 * @brief Expands to a word holding 0x7F in every lane, which is 0x7F7F...7F.
 *
 * @note The complement of MMGR_VERBUM_SCRUTOR_HIGH, so the two split each lane into its value and its mask bit.
 * @note scrut_has_zero adds it to make every non-zero lane carry into its high bit.
 */
#define MMGR_SWAR_LOW7 (MMGR_SWAR_ONES * 0x7Fu)

/**
 * @brief Expands to 0, the first of three verdicts a scan step can report.
 *
 * @note MMGR_SWAR_GO, MMGR_SWAR_YES and MMGR_SWAR_NO are 0, 1 and 2, so the three fit in one byte.
 * @note The three carry no sizing suffix, so each takes int in an expression. A scanner keeping a
 *       verdict in a uint8_t converts it on the way in.
 * @note verbum_scrutor.c reads none of the three. They are declared here for the scanners that
 *       include it.
 */
#define MMGR_SWAR_GO 0

/** @brief Expands to 1, the second of the three verdicts described at MMGR_SWAR_GO. */
#define MMGR_SWAR_YES 1

/** @brief Expands to 2, the third of the three verdicts described at MMGR_SWAR_GO. */
#define MMGR_SWAR_NO 2

/**
 * @brief Expands to 0x60u, the two bits that separate the ASCII blocks a letter can fall in.
 *
 * @note Passed to lane.fam_eq as the family, with MMGR_FAM_CI as the byte, to pick out the capital block.
 */
#define MMGR_FAM_CS 0x60u

/**
 * @brief Expands to 0x40u, the value the MMGR_FAM_CS bits take across the 0x40 to 0x5F block.
 *
 * @note That block holds A through Z along with six other bytes: the at sign, and the five that follow Z.
 */
#define MMGR_FAM_CI 0x40u

/**
 * @brief Arguments for the lane calls.
 *
 * @note ge, le and sub7 read word and byte. eq adds ci. xor_ reads word, val and ci. fam_eq adds fam.
 * @note has_zero, alpha, any_upper and any_digit read word alone.
 * @note count, first and last read mask alone.
 */
typedef struct
{
    const embed_word word; /**< The MMGR_SWAR_BYTES bytes under test, one per lane. */
    const embed_word val;  /**< Whole word xor_ compares against, which the caller broadcasts itself. */
    const embed_word mask; /**< Lane mask the three index calls read. */
    const uint8_t byte;    /**< Byte the call broadcasts into every lane before comparing. */
    const uint8_t fam;     /**< Bits fam_eq keeps on both sides before comparing. */
    const embed_bool ci;   /**< Non-zero to let a letter match either case. */
} ScrutLaneCfg;

/**
 * @brief Arguments for the mask calls.
 *
 * @note spread, drop_first, drop_last and before read mask.
 * @note bytes_below, lanes_below and run_edge read bytes.
 * @note run reads both mask and bytes. tail reads bytes and wi, and is the only call that reads wi.
 */
typedef struct
{
    const embed_word mask; /**< Lane mask to reshape or examine. */
    const size_t bytes;    /**< Byte count the mask is built over, or the run length wanted. */
    const size_t wi;       /**< Whole words a scan has already covered. */
} ScrutMaskCfg;

/**
 * @brief Arguments for the word calls.
 *
 * @note load and load_al read at. fold_lower reads word. count reads bytes.
 */
typedef struct
{
    const embed_word word; /**< Word fold_lower folds. */
    const void *const at;  /**< Address the two loads read a word from [BORROWS]. */
    const size_t bytes;    /**< Byte count count converts into a word count. */
} ScrutWordCfg;

/**
 * @brief Type of the lane dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the thirteen members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note Eight of the first ten return lane masks. sub7 returns seven bit values and xor_ a whole word.
 * @note count, first and last return positions instead of words.
 * @note first and last mean first and last in memory order, which is what the endian binding below delivers.
 * @note xor_ carries a trailing underscore because xor is an alternative spelling of an operator in C++.
 */
typedef struct
{
    embed_word (*ge)(const ScrutLaneCfg *args);        /**< Lanes at or above a byte. */
    embed_word (*le)(const ScrutLaneCfg *args);        /**< Lanes at or below a byte. */
    embed_word (*sub7)(const ScrutLaneCfg *args);      /**< Seven low bits of each lane's difference from a byte. */
    embed_word (*has_zero)(const ScrutLaneCfg *args);  /**< Lanes holding zero. */
    embed_word (*eq)(const ScrutLaneCfg *args);        /**< Lanes equal to a byte. */
    embed_word (*xor_)(const ScrutLaneCfg *args);      /**< Lane by lane difference of two words. */
    embed_word (*fam_eq)(const ScrutLaneCfg *args);    /**< Lanes matching a byte within a set of bits. */
    embed_word (*any_upper)(const ScrutLaneCfg *args); /**< Lanes whose MMGR_FAM_CS bits equal MMGR_FAM_CI. */
    embed_word (*any_digit)(const ScrutLaneCfg *args); /**< Lanes in the 0x30 to 0x3F block. */
    embed_word (*alpha)(const ScrutLaneCfg *args);     /**< Lanes holding an ASCII letter. */
    size_t (*count)(const ScrutLaneCfg *args);         /**< How many lanes a mask has set. */
    size_t (*first)(const ScrutLaneCfg *args);         /**< Index of the first set lane in memory order. */
    size_t (*last)(const ScrutLaneCfg *args);          /**< Index of the last set lane in memory order. */
} ScrutLaneNs;
EMBED_TABLE_LAYOUT(ScrutLaneNs, ge, le, sub7, has_zero, eq, xor_, fam_eq, any_upper, any_digit, alpha, count, first,
                   last);

/**
 * @brief Type of the mask dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the nine members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note drop_first, drop_last and before all mean memory order, which the endian binding below delivers.
 */
typedef struct
{
    embed_word (*spread)(const ScrutMaskCfg *args);      /**< Widens each set lane to a full byte of ones. */
    embed_word (*drop_first)(const ScrutMaskCfg *args);  /**< Clears the first set lane in memory order. */
    embed_word (*drop_last)(const ScrutMaskCfg *args);   /**< Clears the last set lane in memory order. */
    embed_word (*bytes_below)(const ScrutMaskCfg *args); /**< Full byte mask over the first bytes of a word. */
    embed_word (*lanes_below)(const ScrutMaskCfg *args); /**< Lane mask over the first lanes of a word. */
    embed_word (*before)(const ScrutMaskCfg *args);      /**< Lanes ahead of the first set one in memory order. */
    embed_word (*tail)(const ScrutMaskCfg *args);        /**< Lane mask for a scan's last partial word. */
    embed_word (*run)(const ScrutMaskCfg *args);         /**< Lanes that begin a run of set lanes. */
    embed_word (*run_edge)(const ScrutMaskCfg *args);    /**< Lanes too near the end for a run to fit. */
} ScrutMaskNs;
EMBED_TABLE_LAYOUT(ScrutMaskNs, spread, drop_first, drop_last, bytes_below, lanes_below, before, tail, run, run_edge);

/**
 * @brief Type of the word dispatch table.
 *
 * @note EMBED_TABLE_LAYOUT asserts the four members sit at consecutive EMBED_FUNCTION_POINTER_BYTES offsets, with
 * nothing else.
 * @note Its count member converts a byte count into a word count, where the lane table's count counts lanes.
 */
typedef struct
{
    embed_word (*load)(const ScrutWordCfg *args);       /**< Reads a word from any address. */
    embed_word (*load_al)(const ScrutWordCfg *args);    /**< Reads a word from an aligned address. */
    embed_word (*fold_lower)(const ScrutWordCfg *args); /**< Turns every letter lane to lower case. */
    size_t (*count)(const ScrutWordCfg *args);          /**< Words a scan of a byte count must read. */
} ScrutWordNs;
EMBED_TABLE_LAYOUT(ScrutWordNs, load, load_al, fold_lower, count);

/**
 * @brief Marks the lanes of args->word that are at or above args->byte.
 *
 * @param[in] args The word and the byte to compare against [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note Compares bytes as unsigned, so 0x80 and above are the largest values.
 */
embed_word mmgr_scrut_ge(const ScrutLaneCfg *args);

/**
 * @brief Marks the lanes of args->word that are at or below args->byte.
 *
 * @param[in] args The word and the byte to compare against [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note Compares bytes as unsigned, so 0x80 and above are the largest values.
 * @note And this with mmgr_scrut_ge to get a range test, as mmgr_scrut_alpha does.
 */
embed_word mmgr_scrut_le(const ScrutLaneCfg *args);

/**
 * @brief Subtracts args->byte from every lane of args->word and keeps the low seven bits of each result.
 *
 * @param[in] args The word and the byte to subtract [BORROWS].
 * @return         The seven low bits of each lane's difference, every lane's high bit clear.
 * @note Yields values rather than a lane mask, unlike every other lane entry but count, first and last.
 * @warning A lane below args->byte wraps, so its seven bits are the difference taken modulo 128.
 */
embed_word mmgr_scrut_sub7(const ScrutLaneCfg *args);

/**
 * @brief Marks the lanes of args->word that hold zero.
 *
 * @param[in] args The word to test [BORROWS].
 * @return         A lane mask holding the zero lanes.
 * @note Reads args->word alone, so byte, val, fam and ci take no part.
 * @note Apply this to the result of mmgr_scrut_xor to find where two words agreed.
 */
embed_word mmgr_scrut_has_zero(const ScrutLaneCfg *args);

/**
 * @brief Marks the lanes of args->word that equal args->byte.
 *
 * @param[in] args The word, the byte to find, and the case flag [BORROWS].
 * @return         A lane mask holding the matching lanes.
 * @note Broadcasts args->byte itself, so the caller passes a single byte rather than a whole word.
 * @note With args->ci set, a letter matches either case. Every other byte still compares exactly.
 */
embed_word mmgr_scrut_eq(const ScrutLaneCfg *args);

/**
 * @brief Returns the lane by lane difference of args->word and args->val.
 *
 * @param[in] args The two words and the case flag [BORROWS].
 * @return         A word whose lanes are zero exactly where the two agreed.
 * @note Takes a whole word in args->val, so the caller broadcasts a byte itself if that is what it wants.
 * @note With args->ci set, the case bit is cleared on letter lanes, so the two cases of a letter agree.
 * @note Pass the result to mmgr_scrut_has_zero to turn it into a lane mask.
 */
embed_word mmgr_scrut_xor(const ScrutLaneCfg *args);

/**
 * @brief Marks the lanes of args->word that match args->byte once both are reduced to the args->fam bits.
 *
 * @param[in] args The word, the byte to match, and the bits that count [BORROWS].
 * @return         A lane mask holding the matching lanes.
 * @note args->byte is reduced by args->fam first, so bits outside the family take no part on either side.
 * @note A args->fam of 0xFF makes this an exact match, and an args->fam of 0 marks every lane.
 */
embed_word mmgr_scrut_fam_eq(const ScrutLaneCfg *args);

/**
 * @brief Marks the lanes of args->word whose MMGR_FAM_CS bits equal MMGR_FAM_CI, which is the 0x40 to 0x5F block.
 *
 * @param[in] args The word to test [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note Reads args->word alone, since the family and the byte are both fixed.
 * @warning That block holds six bytes that are not capitals, the at sign and the five after Z, and
 *          bit seven takes no part, so 0xC0 to 0xDF is marked as well. And it with mmgr_scrut_alpha
 *          for letters alone.
 */
embed_word mmgr_scrut_any_upper(const ScrutLaneCfg *args);

/**
 * @brief Marks the lanes of args->word that fall in the 0x30 to 0x3F block.
 *
 * @param[in] args The word to test [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note Reads args->word alone, since the family and the byte are both fixed.
 * @warning That block holds six symbols after the nine, so this marks more than 0 through 9. And it
 *          with mmgr_scrut_le at the character nine when only the ten digits should count.
 */
embed_word mmgr_scrut_any_digit(const ScrutLaneCfg *args);

/**
 * @brief Marks the lanes of args->word holding an ASCII letter, of either case.
 *
 * @param[in] args The word to test [BORROWS].
 * @return         A lane mask holding the letter lanes.
 * @note Reads args->word alone, so byte, val, fam and ci take no part.
 * @note A byte at 0x80 or above is never marked, so this is exact where mmgr_scrut_any_upper is not.
 *       What mmgr_scrut_any_digit marks beyond the ten digits is the six symbols after the nine,
 *       not a high byte.
 */
embed_word mmgr_scrut_alpha(const ScrutLaneCfg *args);

/**
 * @brief Counts the set lanes of args->mask.
 *
 * @param[in] args The lane mask to count [BORROWS].
 * @return         How many lanes are set, 0 through MMGR_SWAR_BYTES.
 * @note Reads args->mask alone, so word, byte, val, fam and ci take no part.
 * @warning Expects a lane mask, one bit per lane in that lane's high bit. A spread mask counts wrong.
 */
size_t mmgr_scrut_lane_count(const ScrutLaneCfg *args);

/**
 * @brief Returns the index of the lowest set lane of args->mask.
 *
 * @param[in] args The lane mask to examine [BORROWS].
 * @return         The index, or MMGR_SWAR_BYTES when no lane is set.
 * @note The lane table reaches this as first on a little endian target and as last on a big endian one, so
 *       prefer lane.first or lane.last when memory order is what matters.
 * @note A return of MMGR_SWAR_BYTES is one past the last valid index, which is how an empty mask reports.
 */
size_t mmgr_scrut_lane_lo(const ScrutLaneCfg *args);

/**
 * @brief Returns the index of the highest set lane of args->mask.
 *
 * @param[in] args The lane mask to examine [BORROWS].
 * @return         The index, or MMGR_SWAR_BYTES when no lane is set.
 * @note The lane table reaches this as last on a little endian target and as first on a big endian one, so
 *       prefer lane.first or lane.last when memory order is what matters.
 * @note A return of MMGR_SWAR_BYTES is one past the last valid index, which is how an empty mask reports.
 */
size_t mmgr_scrut_lane_hi(const ScrutLaneCfg *args);

/**
 * @brief Widens every set lane of args->mask from its high bit to a full byte of ones.
 *
 * @param[in] args The lane mask to widen [BORROWS].
 * @return         A word holding 0xFF in each set lane and 0x00 in the rest.
 * @note Use the result to select between two words lane by lane, which a lane mask alone cannot do.
 * @warning The result is no longer a lane mask, so do not hand it to the counting or index entries.
 */
embed_word mmgr_scrut_spread(const ScrutMaskCfg *args);

/**
 * @brief Clears the lowest set lane of args->mask.
 *
 * @param[in] args The lane mask to reduce [BORROWS].
 * @return         The mask with that lane cleared, or 0 when it held only one.
 * @note An empty mask stays empty, so stepping a mask down repeatedly ends rather than wrapping.
 * @note The mask table reaches this as drop_first on a little endian target and drop_last on a big endian one.
 */
embed_word mmgr_scrut_drop_lo(const ScrutMaskCfg *args);

/**
 * @brief Clears the highest set lane of args->mask.
 *
 * @param[in] args The lane mask to reduce [BORROWS].
 * @return         The mask with that lane cleared, or 0 when it held only one.
 * @note An empty mask stays empty, so stepping a mask down repeatedly ends rather than wrapping.
 * @note The mask table reaches this as drop_last on a little endian target and drop_first on a big endian one.
 */
embed_word mmgr_scrut_drop_hi(const ScrutMaskCfg *args);

/**
 * @brief Builds a mask covering the first args->bytes bytes of a word, in memory order.
 *
 * @param[in] args The byte count to cover [BORROWS].
 * @return         A word of ones over those bytes and zeros over the rest.
 * @note Covers the bytes that come first in memory on either byte order.
 * @note A count of 0 gives an empty mask and a count of MMGR_SWAR_BYTES or more gives a full one.
 */
embed_word mmgr_scrut_bytes_below(const ScrutMaskCfg *args);

/**
 * @brief Builds a lane mask covering the first args->bytes lanes of a word, in memory order.
 *
 * @param[in] args The lane count to cover [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note mmgr_scrut_bytes_below reduced to lane bits, so this ands cleanly against another lane mask.
 * @note And a match mask with this to keep a scan from acting on bytes past its count.
 */
embed_word mmgr_scrut_lanes_below(const ScrutMaskCfg *args);

/**
 * @brief Returns the lanes that come before the first set lane of args->mask, in memory order.
 *
 * @param[in] args The lane mask to examine [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note An empty args->mask reports every lane, since nothing comes first.
 * @note Count the result to get the same index mmgr_scrut_lane_lo reports on a little endian target.
 */
embed_word mmgr_scrut_lanes_before(const ScrutMaskCfg *args);

/**
 * @brief Builds the lane mask for the last partial word of a scan of args->bytes bytes.
 *
 * @param[in] args The total byte count and the whole words already covered [BORROWS].
 * @return         A lane mask over the bytes still wanted, or 0 once the count is reached.
 * @note A word wanted in full gets a full mask, so this can be applied on every pass of a scan loop.
 * @note The only mask entry that reads args->wi.
 */
embed_word mmgr_scrut_tail_mask(const ScrutMaskCfg *args);

/**
 * @brief Marks the lanes of args->mask that begin a run of args->bytes set lanes.
 *
 * @param[in] args The lane mask and the run length wanted [BORROWS].
 * @return         A lane mask holding the lanes each run starts at.
 * @note A surviving lane is where a run begins, in memory order, on either byte order.
 * @note A args->bytes of 0 or 1 returns args->mask as it stands, since every set lane starts such a run.
 * @warning Returns 0 for an args->bytes above MMGR_SWAR_BYTES, since no run that long fits in one word.
 */
embed_word mmgr_scrut_run(const ScrutMaskCfg *args);

/**
 * @brief Marks the lanes too near the end of a word for a run of args->bytes to fit inside it.
 *
 * @param[in] args The run length wanted [BORROWS].
 * @return         A lane mask holding those lanes, or 0 when no lane is too near.
 * @note A run of args->bytes can begin at any of the first MMGR_SWAR_BYTES minus args->bytes plus one lanes.
 * @note A caller matching across a word boundary uses this to tell which starts must be tried again.
 * @note Returns 0 for an args->bytes of 0 or 1, since any lane can start such a run, and for any length
 *       above MMGR_SWAR_BYTES, since no lane can.
 */
embed_word mmgr_scrut_run_edge(const ScrutMaskCfg *args);

/**
 * @brief Loads one embed_word from args->at.
 *
 * @param[in] args Address to load from [BORROWS].
 * @return         The bytes at args->at, one per lane, in the target's own order.
 * @warning Reads MMGR_SWAR_BYTES bytes even when fewer are wanted, so args->at must be readable for all of them.
 * @note Any alignment will do. Use mmgr_scrut_load_al when the address is known to be aligned.
 */
embed_word mmgr_scrut_load(const ScrutWordCfg *args);

/**
 * @brief Loads one embed_word from an aligned args->at.
 *
 * @param[in] args Address to load from [BORROWS].
 * @return         The bytes at args->at, one per lane, in the target's own order.
 * @warning Reads MMGR_SWAR_BYTES bytes even when fewer are wanted, and args->at must be aligned for a word.
 * @note Use mmgr_scrut_load when the address may sit anywhere.
 */
embed_word mmgr_scrut_load_al(const ScrutWordCfg *args);

/**
 * @brief Returns args->word with every letter lane turned to lower case.
 *
 * @param[in] args The word to fold [BORROWS].
 * @return         The word with its letter lanes lowered and every other lane untouched.
 * @note Only letter lanes are changed, so a digit or a symbol keeps bit five exactly as it was.
 * @note Fold two words and compare them for a case insensitive test over whole words at once.
 */
embed_word mmgr_scrut_fold_lower(const ScrutWordCfg *args);

/**
 * @brief Returns how many whole words a scan of args->bytes bytes must read.
 *
 * @param[in] args The byte count to convert [BORROWS].
 * @return         The count rounded up, so a partial last word still counts as one.
 * @note A args->bytes of 0 gives 0, so a caller loops no times rather than reading one word.
 * @note Pair this with mask.tail, which supplies the lane mask for that partial last word.
 */
size_t mmgr_scrut_words(const ScrutWordCfg *args);

/**
 * @brief Dispatch table instance named lane.
 *
 * @note The first eleven members call the matching mmgr_scrut_ function on either byte order.
 * @note first and last are bound to lane_lo and lane_hi one way round on a little endian target and the
 *       other way on a big endian one, so both always mean memory order.
 */
EMBED_TABLE_STORAGE ScrutLaneNs lane EMBED_UNUSED = {
    .ge = mmgr_scrut_ge,
    .le = mmgr_scrut_le,
    .sub7 = mmgr_scrut_sub7,
    .has_zero = mmgr_scrut_has_zero,
    .eq = mmgr_scrut_eq,
    .xor_ = mmgr_scrut_xor,
    .fam_eq = mmgr_scrut_fam_eq,
    .any_upper = mmgr_scrut_any_upper,
    .any_digit = mmgr_scrut_any_digit,
    .alpha = mmgr_scrut_alpha,
    .count = mmgr_scrut_lane_count,
#if MMGR_HW_BIG_ENDIAN
    .first = mmgr_scrut_lane_hi,
    .last = mmgr_scrut_lane_lo,
#else
    .first = mmgr_scrut_lane_lo,
    .last = mmgr_scrut_lane_hi,
#endif
};

/**
 * @brief Dispatch table instance named mask.
 *
 * @note drop_first and drop_last are bound to drop_lo and drop_hi one way round on a little endian target
 *       and the other way on a big endian one, so both always mean memory order.
 * @note before reaches mmgr_scrut_lanes_before, which carries the same swap inside itself.
 */
EMBED_TABLE_STORAGE ScrutMaskNs mask EMBED_UNUSED = {
    .spread = mmgr_scrut_spread,
#if MMGR_HW_BIG_ENDIAN
    .drop_first = mmgr_scrut_drop_hi,
    .drop_last = mmgr_scrut_drop_lo,
#else
    .drop_first = mmgr_scrut_drop_lo,
    .drop_last = mmgr_scrut_drop_hi,
#endif
    .bytes_below = mmgr_scrut_bytes_below,
    .lanes_below = mmgr_scrut_lanes_below,
    .before = mmgr_scrut_lanes_before,
    .tail = mmgr_scrut_tail_mask,
    .run = mmgr_scrut_run,
    .run_edge = mmgr_scrut_run_edge,
};

/**
 * @brief Dispatch table instance named word, with each member set to its mmgr_scrut_ function.
 *
 * @note No member depends on byte order, unlike the lane and mask tables above.
 */
EMBED_TABLE_STORAGE ScrutWordNs word EMBED_UNUSED = {
    .load = mmgr_scrut_load,
    .load_al = mmgr_scrut_load_al,
    .fold_lower = mmgr_scrut_fold_lower,
    .count = mmgr_scrut_words,
};

EMBED_END_DECLS

#endif
