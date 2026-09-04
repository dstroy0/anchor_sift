/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file verbum_scrutor.c
 * @brief SWAR tests over the bytes of one embed_word, treating each byte as a lane.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-29
 *
 * @note A lane mask carries one set bit per matching lane, in that lane's high bit, and zero elsewhere.
 * @note scrut_spread widens such a mask to full 0xFF lanes when whole bytes are wanted instead.
 * @note The lane index calls count set high bits, so they report positions rather than masks.
 */
#include "verbum_scrutor/verbum_scrutor.h"

/**
 * @brief Arguments for the lane backends.
 *
 * @note Mirrors ScrutLaneCfg without its const qualifiers.
 * @note The comparison calls read word and byte. The index calls read mask alone.
 */
typedef struct
{
    embed_word word; /**< The eight or four bytes under test, one per lane. */
    embed_word val;  /**< Whole word scrut_xor compares against, already broadcast. */
    embed_word mask; /**< Lane mask the three index calls count. */
    uint8_t byte;    /**< Byte broadcast into every lane before the comparison. */
    uint8_t fam;     /**< Bits scrut_fam_eq keeps before comparing. */
    embed_bool ci;   /**< Non-zero to ignore case on alphabetic lanes. */
} ScrutLaneCtx;

/**
 * @brief Arguments for the mask backends.
 *
 * @note Mirrors ScrutMaskCfg without its const qualifiers.
 * @note spread, drop_lo, drop_hi and lanes_before read mask. bytes_below and lanes_below read bytes.
 * @note tail_mask is the only backend that reads wi.
 */
typedef struct
{
    embed_word mask; /**< Lane mask to reshape. */
    size_t bytes;    /**< Byte count the mask is built from, or the run length wanted. */
    size_t wi;       /**< Index of the word already reached, in whole words. */
} ScrutMaskCtx;

/**
 * @brief Arguments for the word backends.
 *
 * @note Mirrors ScrutWordCfg without its const qualifiers.
 * @note The two loads read at, fold_lower reads word, and words reads bytes.
 */
typedef struct
{
    embed_word word; /**< Word to fold. */
    const void *at;  /**< Address to load a word from [BORROWS]. */
    size_t bytes;    /**< Byte count to convert into a word count. */
} ScrutWordCtx;

/**
 * @brief Returns the lanes that sit below the lowest set lane of args->mask.
 *
 * @param[in] args The lane mask to examine [BORROWS].
 * @return         A lane mask holding those lanes and nothing else.
 * @note Subtracting one sets every bit below the lowest set one, and ~args->mask drops that lowest one again.
 * @note An empty args->mask gives every lane, which is what makes scrut_lane_lo report MMGR_SWAR_BYTES.
 */
EMBED_INLINE embed_word scrut_below_lo(const ScrutMaskCtx *args)
{
    return (args->mask - 1u) & ~args->mask & MMGR_VERBUM_SCRUTOR_HIGH;
}

/**
 * @brief Carries every set bit of args->mask down through all the lanes below it.
 *
 * @param[in] args The lane mask to smear [BORROWS].
 * @return         A mask set from the highest set lane down to lane zero.
 * @note Doubles the shift each pass, so it covers the whole word in three passes at 64 bits.
 * @note Smears downward only, so the highest set lane is what the result reaches up to.
 */
EMBED_INLINE embed_word scrut_smear(const ScrutMaskCtx *args)
{
    embed_word smeared = args->mask;

    // shift doubles from 8 rather than counting up, and the walk ends when it reaches
    // MMGR_SWAR_LANE_BITS: three passes on a 64 bit word, two on a 32 bit one. The step stays in the
    // header, so the body does one or and changes nothing else.
    for (uint32_t shift = 8u; shift < MMGR_SWAR_LANE_BITS; shift <<= 1)
    {
        smeared |= (smeared >> shift);
    }
    return smeared;
}

/**
 * @brief Marks the lanes of args->word that are at or above args->byte.
 *
 * @param[in] args The word and the byte to compare against [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note The or sets each lane's high bit before the subtraction. A lane under 0x80 then has a bit the
 *       subtraction can borrow without reaching the next lane.
 * @note A lane at 0x80 or above already has that bit set as part of its value. The or changes
 *       nothing there. Its difference then has a high bit when the lane minus args->byte reaches
 *       0x80, which is a different test from the lane reaching args->byte.
 * @note The word's high bits are or-ed into the result for those lanes. A lane at 0x80 or above is
 *       greater than every args->byte under 0x80.
 * @note Neither case reaches the next lane. A lane under 0x80 has the added bit to borrow from, and a
 *       lane at 0x80 or above is already larger than args->byte.
 * @note Compares as unsigned bytes. 0x80 and above are the largest values.
 * @warning args->byte must be under 0x80. At or above it the lanes under 0x80 come out wrong and
 *          nothing diagnoses it. Every call inside the library passes a literal under 0x80.
 */
EMBED_INLINE embed_word scrut_ge(const ScrutLaneCtx *args)
{
    return (args->word & MMGR_VERBUM_SCRUTOR_HIGH) |
           ((((args->word | MMGR_VERBUM_SCRUTOR_HIGH) - MMGR_SWAR_ONES * args->byte) & MMGR_VERBUM_SCRUTOR_HIGH));
}

/**
 * @brief Marks the lanes of args->word that are at or below args->byte.
 *
 * @param[in] args The word and the byte to compare against [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note Subtracts the word from the broadcast byte, which is scrut_ge with the two operands swapped.
 * @note The word is the subtrahend. A lane at 0x80 or above exceeds the minuend lane, and the
 *       subtraction then reaches into the next lane.
 * @note The and clears the lanes' high bits before the subtraction. Each subtrahend lane is then at
 *       most 0x7F and each minuend lane at least 0x80.
 * @note The closing and-not removes the lanes whose high bit was set. A lane at 0x80 or above
 *       exceeds every args->byte under 0x80.
 * @note Compares as unsigned bytes. 0x80 and above are the largest values.
 * @warning args->byte must be under 0x80, for the reason given on scrut_ge.
 */
EMBED_INLINE embed_word scrut_le(const ScrutLaneCtx *args)
{
    return ~args->word &
           ((((MMGR_SWAR_ONES * args->byte) | MMGR_VERBUM_SCRUTOR_HIGH) - (args->word & ~MMGR_VERBUM_SCRUTOR_HIGH)) &
            MMGR_VERBUM_SCRUTOR_HIGH);
}

/**
 * @brief Subtracts args->byte from every lane of args->word and keeps the low seven bits of each result.
 *
 * @param[in] args The word and the byte to subtract [BORROWS].
 * @return         The seven low bits of each lane's difference, with every lane's high bit clear.
 * @note Runs the same subtraction as scrut_ge but keeps MMGR_SWAR_LOW7, so this yields values rather than a mask.
 * @note A lane below args->byte wraps, so its seven bits are the difference taken modulo 128.
 */
EMBED_INLINE embed_word scrut_sub7(const ScrutLaneCtx *args)
{
    return ((args->word | MMGR_VERBUM_SCRUTOR_HIGH) - MMGR_SWAR_ONES * args->byte) & MMGR_SWAR_LOW7;
}

/**
 * @brief Marks the lanes of args->word that hold zero.
 *
 * @param[in] args The word to test [BORROWS].
 * @return         A lane mask holding the zero lanes.
 * @note Adding MMGR_SWAR_LOW7 carries into a lane's high bit unless its low seven bits are all zero.
 * @note Or-ing args->word back in then covers the case where only the high bit was set.
 * @note scrut_eq and scrut_fam_eq both reach this after an exclusive or, which turns equality into a zero test.
 */
EMBED_INLINE embed_word scrut_has_zero(const ScrutLaneCtx *args)
{
    return ~(((args->word & MMGR_SWAR_LOW7) + MMGR_SWAR_LOW7) | args->word) & MMGR_VERBUM_SCRUTOR_HIGH;
}

/**
 * @brief Marks the lanes of args->word holding an ASCII letter, of either case.
 *
 * @param[in] args The word to test [BORROWS].
 * @return         A lane mask holding the letter lanes.
 * @note Setting bit five in every lane folds the two cases together, so one range test covers both.
 * @note The range tests take the lanes with their high bits cleared. scrut_ge and scrut_le are exact
 *       while both the lanes and the threshold are under 0x80, and a lane at or above it borrows out
 *       of its neighbor and answers for that lane instead. Both thresholds here are already under
 *       0x80, 'a' at 0x61 and 'z' at 0x7A, and clearing the lanes puts the other operand there too.
 * @note MMGR_SWAR_LOW7 is the complement of MMGR_VERBUM_SCRUTOR_HIGH and is built from
 *       MMGR_SWAR_ONES, so it stays an embed_word. Writing the complement out instead promotes to int
 *       and is narrowed on the way back, which is a diagnostic at a 16-bit word for no gain: the two
 *       measured the same on an ESP32-S3 and an ESP32-C6, over 8192 words with no disagreement.
 * @note The range test does not need that bit. The final and with the complement of the unmasked
 *       word still keeps only lanes whose high bit is clear, so a byte at 0x80 or above cannot pass
 *       by folding into the letter range.
 * @note scrut_xor and scrut_fold_lower both shift this result down two places to reach the case bit.
 */
EMBED_INLINE embed_word scrut_alpha(const ScrutLaneCtx *args)
{
    const embed_word lo = args->word | (MMGR_SWAR_ONES * 0x20u);
    const embed_word in_range = lo & MMGR_SWAR_LOW7;

    return EMBED_CALL(scrut_ge, ScrutLaneCtx, .word = in_range, .byte = 'a') &
           EMBED_CALL(scrut_le, ScrutLaneCtx, .word = in_range, .byte = 'z') & ~lo;
}

/**
 * @brief Returns the lane by lane difference of args->word and args->val, optionally ignoring case.
 *
 * @param[in] args The two words and the case flag [BORROWS].
 * @return         A word whose lanes are zero exactly where the two agreed.
 * @note With args->ci clear this is a plain exclusive or, and every bit of every lane counts.
 * @note With args->ci set, scrut_alpha shifted down two gives the case bit of each letter lane, and clearing
 *       it in the difference makes the two cases of a letter compare equal.
 * @note Only letter lanes are folded, so a difference in bit five of a digit or a symbol still counts.
 */
EMBED_INLINE embed_word scrut_xor(const ScrutLaneCtx *args)
{
    const embed_word diff = args->word ^ args->val;

    if (!args->ci)
    {
        return diff;
    }
    return diff & ~(EMBED_CALL(scrut_alpha, ScrutLaneCtx, .word = args->word) >> 2);
}

/**
 * @brief Marks the lanes of args->word that equal args->byte.
 *
 * @param[in] args The word, the byte to find, and the case flag [BORROWS].
 * @return         A lane mask holding the matching lanes.
 * @note Broadcasts args->byte into every lane, takes the difference through scrut_xor, then tests for zero.
 * @note args->ci is passed on to scrut_xor, so a letter matches either case when it is set.
 */
EMBED_INLINE embed_word scrut_eq(const ScrutLaneCtx *args)
{
    const embed_word broadcast = MMGR_SWAR_ONES * args->byte;
    const embed_word diff = EMBED_CALL(scrut_xor, ScrutLaneCtx, .word = args->word, .val = broadcast, .ci = args->ci);

    return EMBED_CALL(scrut_has_zero, ScrutLaneCtx, .word = diff);
}

/**
 * @brief Marks the lanes of args->word that match args->byte once both are reduced to the args->fam bits.
 *
 * @param[in] args The word, the byte to match, and the bits that count [BORROWS].
 * @return         A lane mask holding the matching lanes.
 * @note args->byte is itself reduced by args->fam first, so bits outside the family take no part on either side.
 * @note A args->fam of 0xFF makes this a plain equality test, and an args->fam of 0 marks every lane.
 */
EMBED_INLINE embed_word scrut_fam_eq(const ScrutLaneCtx *args)
{
    const embed_word bits = MMGR_SWAR_ONES * args->fam;
    const embed_word want = MMGR_SWAR_ONES * (args->byte & args->fam);

    return EMBED_CALL(scrut_has_zero, ScrutLaneCtx, .word = (args->word & bits) ^ want);
}

/**
 * @brief Marks the lanes of args->word whose MMGR_FAM_CS bits equal MMGR_FAM_CI.
 *
 * @param[in] args The word to test [BORROWS].
 * @return         A lane mask holding those lanes.
 * @warning That covers the whole 0x40 to 0x5F block, so the at sign and the six symbols among the capitals
 *          are marked alongside A through Z.
 * @note Use scrut_alpha when only letters should count.
 */
EMBED_INLINE embed_word scrut_any_upper(const ScrutLaneCtx *args)
{
    return EMBED_CALL(scrut_fam_eq, ScrutLaneCtx, .word = args->word, .fam = MMGR_FAM_CS, .byte = MMGR_FAM_CI);
}

/**
 * @brief Marks the lanes of args->word whose top four bits are 0x30.
 *
 * @param[in] args The word to test [BORROWS].
 * @return         A lane mask holding those lanes.
 * @warning That covers the whole 0x30 to 0x3F block, so the seven symbols after the nine are marked as well.
 * @note A caller that needs only 0 through 9 can and this with scrut_le at the character nine.
 */
EMBED_INLINE embed_word scrut_any_digit(const ScrutLaneCtx *args)
{
    return EMBED_CALL(scrut_fam_eq, ScrutLaneCtx, .word = args->word, .fam = 0xF0u, .byte = 0x30u);
}

/**
 * @brief Counts the set lanes of args->mask.
 *
 * @param[in] args The lane mask to count [BORROWS].
 * @return         How many lanes are set, 0 through MMGR_SWAR_BYTES.
 * @note Shifting down seven puts each lane's bit at its own low position, and multiplying by MMGR_SWAR_ONES
 *       sums every one of them into the top lane, which the final shift then reads out.
 * @note The explicit embed_word cast holds the product at the word width, so the last shift reads the top lane
 *       out of a known size. The count is at most MMGR_SWAR_BYTES, so the size_t return loses nothing.
 * @note Reads args->mask alone, so the word and byte members take no part.
 */
EMBED_INLINE size_t scrut_lane_count(const ScrutLaneCtx *args)
{

    return (embed_word)((args->mask >> 7) * MMGR_SWAR_ONES) >> (MMGR_SWAR_LANE_BITS - 8u);
}

/**
 * @brief Returns the index of the lowest set lane of args->mask.
 *
 * @param[in] args The lane mask to examine [BORROWS].
 * @return         The index, or MMGR_SWAR_BYTES when no lane is set.
 * @note Built two ways. Where __builtin_ctzll is available the trailing zero count gives the index.
 *       Where it is not, the lanes below the lowest set one are counted, and that count is the index.
 * @note The builtin build tests the empty mask before calling, since the builtin leaves a zero argument
 *       undefined. The counting build needs no test, since scrut_below_lo reports every lane for it.
 * @note The lane table binds this to first on a little endian target and to last on a big endian one.
 */
EMBED_INLINE size_t scrut_lane_lo(const ScrutLaneCtx *args)
{
#if EMBED_HAS_BUILTIN(__builtin_ctzll)
    // A lane's flag sits in its high bit, so the trailing zero count of the mask is eight times the
    // index plus seven and the index is that shifted down three. The empty mask is answered first,
    // because the count below reports every lane for it and the builtin leaves it undefined.
    // Measured on an ESP32-S3 over sixty four masks: 24.2 cycles a mask to 17.3, which is 1.40x
    if (args->mask == 0u)
    {
        return MMGR_SWAR_BYTES;
    }
    // Three explicit casts on the one line: the mask widens to unsigned long long to match the builtin's
    // parameter, the builtin's int result becomes unsigned so the shift is an unsigned one, and the lane
    // index widens to the size_t return. Shifting down three divides the bit index by the bits in a lane.
    return (size_t)((unsigned)__builtin_ctzll((unsigned long long)args->mask) >> 3u);
#else
    return EMBED_CALL(scrut_lane_count, ScrutLaneCtx,
                      .mask = EMBED_CALL(scrut_below_lo, ScrutMaskCtx, .mask = args->mask));
#endif
}

/**
 * @brief Returns the index of the highest set lane of args->mask.
 *
 * @param[in] args The lane mask to examine [BORROWS].
 * @return         The index, or MMGR_SWAR_BYTES when no lane is set.
 * @note Smearing down from the highest set lane and counting gives that lane's index once one is taken off.
 * @note The empty mask is caught first, since the smear of an empty mask would count zero and then wrap.
 * @note The lane table binds this to last on a little endian target and to first on a big endian one.
 */
EMBED_INLINE size_t scrut_lane_hi(const ScrutLaneCtx *args)
{
    if (args->mask == 0u)
    {
        return MMGR_SWAR_BYTES;
    }
    return EMBED_CALL(scrut_lane_count, ScrutLaneCtx,
                      .mask = EMBED_CALL(scrut_smear, ScrutMaskCtx, .mask = args->mask)) -
           1u;
}

/**
 * @brief Widens every set lane of args->mask from its high bit to a full byte of ones.
 *
 * @param[in] args The lane mask to widen [BORROWS].
 * @return         A word holding 0xFF in each set lane and 0x00 in the rest.
 * @note A set lane holds 0x80, and adding 0x7F to it fills the lane. A clear lane contributes nothing.
 * @note The explicit embed_word cast pins the sum back to the word width, so neither addition can leave a
 *       promoted wider type behind on a target whose int is wider than embed_word.
 * @note Use this when whole bytes are wanted, such as for selecting between two words lane by lane.
 */
EMBED_INLINE embed_word scrut_spread(const ScrutMaskCtx *args)
{
    return (embed_word)(args->mask + (args->mask - (args->mask >> 7)));
}

/**
 * @brief Clears the lowest set lane of args->mask.
 *
 * @param[in] args The lane mask to reduce [BORROWS].
 * @return         The mask with that lane cleared, or 0 when it held only one.
 * @note Subtracting one turns the lowest set bit into zeros below it, so the and clears just that bit.
 * @note The explicit embed_word cast pins the result to the word width, since the subtraction against 1u can
 *       promote on a target whose int is wider than embed_word.
 * @note An empty mask stays empty, so stepping a mask down repeatedly ends rather than wrapping.
 * @note The mask table binds this to drop_first on a little endian target and to drop_last on a big endian one.
 */
EMBED_INLINE embed_word scrut_drop_lo(const ScrutMaskCtx *args)
{
    return (embed_word)(args->mask & (args->mask - 1u));
}

/**
 * @brief Clears the highest set lane of args->mask.
 *
 * @param[in] args The lane mask to reduce [BORROWS].
 * @return         The mask with that lane cleared, or 0 when it held only one.
 * @note The smear runs from the highest set lane down, so exclusive or-ing it with itself shifted one lane
 *       down leaves just that top lane, which the and then removes.
 * @note The mask table binds this to drop_last on a little endian target and to drop_first on a big endian one.
 */
EMBED_INLINE embed_word scrut_drop_hi(const ScrutMaskCtx *args)
{
    const embed_word smeared = EMBED_CALL(scrut_smear, ScrutMaskCtx, .mask = args->mask);

    return args->mask & ~(smeared ^ (smeared >> 8));
}

/**
 * @brief Builds a mask covering the first args->bytes bytes of a word, in memory order.
 *
 * @param[in] args The byte count to cover [BORROWS].
 * @return         A word of ones over those bytes and zeros over the rest.
 * @note Shifts one way on a little endian target and the other on a big endian one, so the bytes covered are
 *       always the ones that come first in memory.
 * @note The inner cast types the zero as an embed_word before the complement, and the outer one pins the
 *       complement back to the word width, so all holds set bits over exactly one word and none above it.
 * @note A count of 0 gives an empty mask and a count of MMGR_SWAR_BYTES or more gives a full one, which is
 *       also what keeps the shift count below the word width.
 */
EMBED_INLINE embed_word scrut_bytes_below(const ScrutMaskCtx *args)
{
    const embed_word all = (embed_word) ~(embed_word)0;

    if (args->bytes == 0u)
    {
        return 0;
    }
    if (args->bytes >= MMGR_SWAR_BYTES)
    {
        return all;
    }
#if MMGR_HW_BIG_ENDIAN
    return all << ((MMGR_SWAR_BYTES - args->bytes) * 8u);
#else
    return all >> ((MMGR_SWAR_BYTES - args->bytes) * 8u);
#endif
}

/**
 * @brief Builds a lane mask covering the first args->bytes lanes of a word, in memory order.
 *
 * @param[in] args The lane count to cover [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note scrut_bytes_below reduced to lane bits, so this suits and-ing against another lane mask.
 * @note This is what keeps a scan from reading past its count when the last word is only partly wanted.
 */
EMBED_INLINE embed_word scrut_lanes_below(const ScrutMaskCtx *args)
{
    return EMBED_CALL(scrut_bytes_below, ScrutMaskCtx, .bytes = args->bytes) & MMGR_VERBUM_SCRUTOR_HIGH;
}

/**
 * @brief Builds the lane mask for the last partial word of a scan of args->bytes bytes.
 *
 * @param[in] args The total byte count and the whole words already done [BORROWS].
 * @return         A lane mask over the bytes still wanted, or 0 once the count is reached.
 * @note Takes the words already done off the total, then hands what is left to scrut_lanes_below.
 * @note A word that is wanted in full gets a full mask, so this can be applied on every pass of a loop.
 * @note The only backend that reads args->wi.
 */
EMBED_INLINE embed_word scrut_tail_mask(const ScrutMaskCtx *args)
{
    const size_t done = args->wi * MMGR_SWAR_BYTES;

    if (done >= args->bytes)
    {
        return 0;
    }
    return EMBED_CALL(scrut_lanes_below, ScrutMaskCtx, .bytes = args->bytes - done);
}

/**
 * @brief Returns the lanes that come before the first set lane of args->mask, in memory order.
 *
 * @param[in] args The lane mask to examine [BORROWS].
 * @return         A lane mask holding those lanes.
 * @note On a little endian target the earlier bytes are the lower lanes, so scrut_below_lo gives them.
 * @note On a big endian target they are the higher lanes, so the complement of the smear gives them instead.
 * @note An empty args->mask reports every lane on either branch, since nothing comes first.
 */
EMBED_INLINE embed_word scrut_lanes_before(const ScrutMaskCtx *args)
{
#if MMGR_HW_BIG_ENDIAN
    return ~EMBED_CALL(scrut_smear, ScrutMaskCtx, .mask = args->mask) & MMGR_VERBUM_SCRUTOR_HIGH;
#else
    return EMBED_CALL(scrut_below_lo, ScrutMaskCtx, .mask = args->mask);
#endif
}

/**
 * @brief Marks the lanes of args->mask that begin a run of args->bytes set lanes.
 *
 * @param[in] args The lane mask and the run length wanted [BORROWS].
 * @return         A lane mask holding the lanes each run starts at, or 0 when args->bytes exceeds
 *                 one word.
 * @note Ands the mask with itself shifted along, doubling the reach each pass, so a run of eight takes
 *       three passes rather than seven.
 * @note The step is held to what is still wanted, so a run length that is not a power of two lands exactly.
 * @note Shifts toward the earlier bytes on either byte order, so a surviving lane is where a run begins.
 * @note A args->bytes of 0 or 1 returns args->mask as it stands, since the loop runs no passes.
 */
EMBED_INLINE embed_word scrut_run(const ScrutMaskCtx *args)
{
    embed_word starts = args->mask;
    size_t have = 1u;

    if (args->bytes > MMGR_SWAR_BYTES)
    {
        return 0;
    }
    while (have < args->bytes)
    {
        // step is the smaller of the run length already covered and the length still wanted, so the last
        // pass lands exactly on args->bytes instead of overshooting it. have advances on its own line
        // below, so nothing in the test changes it.
        const size_t step = (have < args->bytes - have) ? have : args->bytes - have;
#if MMGR_HW_BIG_ENDIAN
        starts &= (starts << (step * 8u));
#else
        starts &= (starts >> (step * 8u));
#endif
        have += step;
    }
    return starts;
}

/**
 * @brief Marks the lanes too near the end of a word for a run of args->bytes to fit inside it.
 *
 * @param[in] args The run length wanted [BORROWS].
 * @return         A lane mask holding those lanes, or 0 when no lane is too near.
 * @note A run of args->bytes can start at any of the first MMGR_SWAR_BYTES minus args->bytes plus one lanes, and
 *       this reports the rest.
 * @note Returns 0 for an args->bytes of 0 or 1, since any lane can start such a run, and for one past a word.
 * @note A caller matching across a word boundary uses this to tell which starts must be checked again.
 */
EMBED_INLINE embed_word scrut_run_edge(const ScrutMaskCtx *args)
{
    // Two cases hold no lane: a run of 0 or 1 starts at any lane, and a run past one word starts at none.
    // The second half is also what keeps MMGR_SWAR_BYTES - args->bytes below from wrapping on a size_t.
    if ((args->bytes <= 1u) || (args->bytes > MMGR_SWAR_BYTES))
    {
        return 0;
    }
    return MMGR_VERBUM_SCRUTOR_HIGH &
           ~EMBED_CALL(scrut_lanes_below, ScrutMaskCtx, .bytes = MMGR_SWAR_BYTES - args->bytes + 1u);
}

/**
 * @brief Loads one embed_word from args->at.
 *
 * @param[in] args Address to load from [BORROWS].
 * @return         The bytes at args->at, one per lane, in the target's own order.
 * @note Goes through proxim.load, so args->at needs no particular alignment.
 * @warning args->at must be readable for MMGR_SWAR_BYTES bytes, even when fewer are wanted.
 */
EMBED_INLINE embed_word scrut_load(const ScrutWordCtx *args)
{
    return EMBED_CALL(proxim.load, ProximusCfg, .at = args->at);
}

/**
 * @brief Loads one embed_word from an aligned args->at.
 *
 * @param[in] args Address to load from [BORROWS].
 * @return         The bytes at args->at, one per lane, in the target's own order.
 * @note Goes through proxim.al_load, which keeps the word type's own alignment, unlike scrut_load.
 * @warning args->at must be readable for MMGR_SWAR_BYTES bytes and aligned for an embed_word.
 */
EMBED_INLINE embed_word scrut_load_al(const ScrutWordCtx *args)
{
    return EMBED_CALL(proxim.al_load, ProximusCfg, .at = args->at);
}

/**
 * @brief Returns args->word with every letter lane turned to lower case.
 *
 * @param[in] args The word to fold [BORROWS].
 * @return         The word with the case bit set on its letter lanes and every other lane untouched.
 * @note scrut_alpha shifted down two gives the case bit of each letter lane, and or-ing it in forces lower case.
 * @note Only letter lanes are touched, so a digit or a symbol keeps bit five exactly as it was.
 * @note scrut_xor uses the same shifted mask, but clears the bit rather than setting it.
 */
EMBED_INLINE embed_word scrut_fold_lower(const ScrutWordCtx *args)
{
    return args->word | (EMBED_CALL(scrut_alpha, ScrutLaneCtx, .word = args->word) >> 2);
}

/**
 * @brief Returns how many whole words a scan of args->bytes bytes must read.
 *
 * @param[in] args The byte count to convert [BORROWS].
 * @return         The count rounded up, so a partial last word still counts as one.
 * @note Written as a divide plus a test of the low bits rather than adding before dividing, so a very large
 *       byte count cannot wrap on the way in.
 * @note The and against MMGR_SWAR_BYTES - 1u stands in for the remainder of that divide, which holds only
 *       because a word is a power of two bytes wide. Its arms are typed 1u and 0u to match what they add to.
 * @note A args->bytes of 0 gives 0, so a caller loops no times rather than reading one word.
 */
EMBED_INLINE size_t scrut_words(const ScrutWordCtx *args)
{
    return (args->bytes / MMGR_SWAR_BYTES) + (((args->bytes & (MMGR_SWAR_BYTES - 1u)) != 0u) ? 1u : 0u);
}

/**
 * @brief Binds this module's fixed arguments to EMBED_ENTRY, with the two types per entry.
 *
 * @param[in] ReturnType_ Return type of the entry point.
 * @param[in] CtxType_    Context type this entry's backend takes.
 * @param[in] CfgType_    Argument type the caller passes.
 * @param[in] name_       Name after the mmgr_scrut_ and scrut_ prefixes, which the two share.
 * @param[in] ...         Initializers for the CtxType_ literal, forwarded from the entry's CfgType_
 *                        as args.
 * @warning The arguments are pasted into the expansion rather than evaluated as call arguments, so none of
 *          them may carry a side effect.
 * @note Both types are parameters. The module carries three of each, one per view. A lane view covers
 *       the bytes of a word, a mask view covers the bits a lane test produced, and a word view covers
 *       the memory a scan walks. The three dispatch tables in verbum_scrutor.h divide the same way.
 */
#define SCRUT_ENTRY(ReturnType_, CtxType_, CfgType_, name_, ...)                                                       \
    EMBED_ENTRY(mmgr_scrut_, scrut_, CtxType_, CfgType_, ReturnType_, name_, __VA_ARGS__)

/**
 * @brief The lane view, one line per entry point.
 *
 * @note Each is documented at its declaration in verbum_scrutor.h.
 * @note The fields each line forwards are the ones that entry reads; EMBED_CALL zeroes the rest. Only
 *       eq and xor forward ci, and only fam_eq forwards fam.
 */
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, ge, .word = args->word, .byte = args->byte)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, le, .word = args->word, .byte = args->byte)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, sub7, .word = args->word, .byte = args->byte)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, has_zero, .word = args->word)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, eq, .word = args->word, .byte = args->byte, .ci = args->ci)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, xor, .word = args->word, .val = args->val, .ci = args->ci)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, fam_eq, .word = args->word, .fam = args->fam, .byte = args->byte)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, any_upper, .word = args->word)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, any_digit, .word = args->word)
SCRUT_ENTRY(embed_word, ScrutLaneCtx, ScrutLaneCfg, alpha, .word = args->word)
SCRUT_ENTRY(size_t, ScrutLaneCtx, ScrutLaneCfg, lane_count, .mask = args->mask)
SCRUT_ENTRY(size_t, ScrutLaneCtx, ScrutLaneCfg, lane_lo, .mask = args->mask)
SCRUT_ENTRY(size_t, ScrutLaneCtx, ScrutLaneCfg, lane_hi, .mask = args->mask)

/**
 * @brief The mask view, one line per entry point.
 *
 * @note Each is documented at its declaration in verbum_scrutor.h.
 * @note tail_mask is the only entry that forwards wi, and run the only one that forwards both a mask
 *       and a byte count.
 */
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, spread, .mask = args->mask)
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, drop_lo, .mask = args->mask)
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, drop_hi, .mask = args->mask)
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, bytes_below, .bytes = args->bytes)
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, lanes_below, .bytes = args->bytes)
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, lanes_before, .mask = args->mask)
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, tail_mask, .bytes = args->bytes, .wi = args->wi)
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, run, .mask = args->mask, .bytes = args->bytes)
SCRUT_ENTRY(embed_word, ScrutMaskCtx, ScrutMaskCfg, run_edge, .bytes = args->bytes)

/**
 * @brief The word view, one line per entry point.
 *
 * @note Each is documented at its declaration in verbum_scrutor.h.
 * @note load and load_al differ in the alignment each promises, not in what they forward.
 */
SCRUT_ENTRY(embed_word, ScrutWordCtx, ScrutWordCfg, load, .at = args->at)
SCRUT_ENTRY(embed_word, ScrutWordCtx, ScrutWordCfg, load_al, .at = args->at)
SCRUT_ENTRY(embed_word, ScrutWordCtx, ScrutWordCfg, fold_lower, .word = args->word)
SCRUT_ENTRY(size_t, ScrutWordCtx, ScrutWordCfg, words, .bytes = args->bytes)
