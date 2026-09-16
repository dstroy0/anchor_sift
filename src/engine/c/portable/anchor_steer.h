/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_steer.h
 * @brief The engine reads the field it is about to search and orders its own probes from it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * THE MISSING TERM. theory/delta_null, "Ordering the anchors by rarity", states it: order the
 * evaluation of the anchor displacements by the rarity of the symbol each one tests, and the first
 * probe carries the most pruning power it can. Checking a common symbol against a background field
 * rarely rejects, because the noise floor keeps supplying that symbol. Checking a rare one rejects
 * almost every candidate on the first operation. The chapter names the mechanism directly: the
 * background field's entropy distribution is the steering wheel for the engine.
 *
 * WHAT STEERS IT IS ITS OWN READING OF THE FIELD. The census below is one pass of the engine over
 * the corpus it is about to search, and the order it produces is then the order the arms evaluate
 * in. The engine is turned onto itself: it measures the field, and the measurement decides where it
 * slices. Nothing outside the corpus supplies the ordering.
 *
 * THE MAGNITUDE IS THE INFORMATION WEIGHT AND IT IS AN INTEGER. An anchor's steering magnitude is
 * the rarity of the symbol it tests, which is -log P(symbol). ORDERING BY THAT NEEDS NO LOGARITHM.
 * -log is monotone decreasing in P, every P shares the denominator N, so ordering by rarity
 * descending is ordering by raw count ascending, exactly and for every input. The comparison is
 * between two integers the census already holds. No logarithm is evaluated, no probability is
 * formed, and no double is declared in this header or its implementation.
 *
 * EXACT LOGIC IS NOT TOUCHED, which is the whole reason this is free. The arms verify a survivor
 * with a full memcmp, and an alignment survives only when EVERY anchor agrees. A conjunction does
 * not depend on the order its terms are tested in, so reordering changes which probe rejects first
 * and never whether an alignment reaches verification. The count is identical for every ordering,
 * and anchor_steer_probe_order is graded on exactly that: same count as the unordered arm, bit for
 * bit, or the ordering has a defect.
 *
 * @note No <math.h>, no double, no float, and no library outside the C11 standard headers this file
 *       and its implementation include. The dispatch decision that used to be a floating point
 *       comparison is an exact integer one, carried in AnchorExactInteger where it outgrows 64 bits.
 * @see anchor_sift.h for the arms this steers.
 * @see exact_limbs.h for the fixed width integer the dispatch test is carried in.
 */
#ifndef ANCHOR_STEER_H
#define ANCHOR_STEER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
/* A device arm is compiled as C++ and calls straight into these, which are compiled as C. */
extern "C" {
#endif

/** @brief Distinct values a byte takes, which is the width of every census below. */
#define ANCHOR_STEER_SYMBOLS 256u

/**
 * @brief What one pass over a corpus records about the field it is.
 *
 * @note This is the whole of what steers the engine. It is read off the corpus and nothing else
 *       contributes to it, which is what makes the steering the field's own and not a parameter.
 * @note `total` is the byte count and not the alignment count. A census describes the field, not
 *       the search about to be run over it, so it does not know the needle length.
 */
typedef struct
{
    uint64_t occurrences[ANCHOR_STEER_SYMBOLS]; /**< How often each byte value appears. */
    uint64_t total;                             /**< Bytes counted, the sum of the row above. */
    uint32_t distinct;                          /**< Byte values with a non-zero count. */
} AnchorFieldCensus;

/**
 * @brief Counts what the corpus is made of, in one pass.
 *
 * @param[in]  corpus     Bytes to census [BORROWS].
 * @param[in]  corpus_len How many.
 * @param[out] census     Where the counts are written [BORROWS].
 * @note Safe on a zero length corpus and on a null pointer, both of which produce an empty census
 *       whose `total` and `distinct` are zero. Every function below is defined on an empty census.
 */
void anchor_field_census(const uint8_t *corpus, size_t corpus_len, AnchorFieldCensus *census);

/**
 * @brief Steering magnitude of one symbol, as an integer, larger meaning rarer.
 *
 * @param[in] census Field census [BORROWS].
 * @param[in] symbol Byte value to weigh.
 * @return           `census->total` minus the symbol's own count.
 *
 * @note THIS IS THE INFORMATION WEIGHT WITHOUT THE LOGARITHM. Rarity ordering is by P ascending,
 *       and P is count over a shared total, so `total - count` orders identically to -log P while
 *       staying an exact integer. It is a magnitude for ordering and comparison and it is not an
 *       entropy in bits; anything wanting bits has to take the logarithm itself and would be
 *       introducing a double this engine does not carry.
 * @note A symbol absent from the corpus returns the largest magnitude available, which is correct:
 *       an anchor testing a symbol the field never produces rejects every alignment immediately.
 */
uint64_t anchor_steer_magnitude(const AnchorFieldCensus *census, uint8_t symbol);

/**
 * @brief Orders anchor offsets so the rarest symbol the needle carries is tested first.
 *
 * @param[in,out] offsets    Anchor offsets into the needle, reordered in place [BORROWS].
 * @param[in]     count      How many offsets.
 * @param[in]     census     Field census that supplies the magnitudes [BORROWS].
 * @param[in]     needle     Bytes the offsets index [BORROWS].
 * @param[in]     needle_len How many.
 *
 * @note Insertion sort by descending magnitude. The count is at most ANCHOR_SIFT_ANCHORS, which is
 *       four, so an insertion sort is fewer instructions than setting up anything cleverer and is
 *       the right choice rather than a concession.
 * @note STABLE, and that is load bearing rather than incidental. Two anchors testing equally rare
 *       symbols keep the order choose_offsets placed them in, so the spatial spread that rule exists
 *       to produce survives wherever rarity does not distinguish. An unstable sort would quietly
 *       discard the spread on a flat corpus, which is the corpus where the spread is all there is.
 * @note Does nothing where any argument is null, where `count` is zero, or where the census is
 *       empty. An engine with nothing to steer by keeps the order it was given.
 */
void anchor_steer_probe_order(size_t *offsets, size_t count, const AnchorFieldCensus *census,
                              const uint8_t *needle, size_t needle_len);

/**
 * @brief Whether this field wants the free order arm, decided in exact integer arithmetic.
 *
 * @param[in] census Field census [BORROWS].
 * @return           1 for the free order arm, 0 for the short circuiting arm.
 *
 * @note THE SAME RULE THE ENGINE ALREADY SHIPPED, WITH THE FLOATING POINT REMOVED. The rule asks
 *       whether the effective alphabet 2^H2 sits within 85 percent of the symbols actually used.
 *       Writing H2 as the collision entropy, 2^H2 is exactly total^2 over the sum of the squared
 *       counts, so the test
 *
 *           total^2 / sum(count^2)  >=  (85/100) * distinct
 *
 *       clears its denominators into
 *
 *           100 * total^2  >=  85 * distinct * sum(count^2)
 *
 *       which is a comparison between two exact integers. No logarithm is taken, no power of two is
 *       approximated by a series, and the threshold is the exact rational 85/100 rather than the
 *       nearest double to 0.85.
 * @note Both sides outgrow 64 bits on a corpus of any size, since total^2 passes 2^64 at a four
 *       gigabyte corpus and the sum of squares is accumulated over 256 terms. Both are carried in
 *       AnchorExactInteger for that reason, which is the fixed width limb form the rest of the
 *       engine already measures in.
 * @note The threshold was swept rather than chosen, and the sweep is recorded against the constant
 *       in anchor_sift.c. Clearing the denominators does not re-open that: 85/100 is the same value
 *       the sweep scored, carried exactly instead of rounded.
 */
int anchor_steer_prefers_free(const AnchorFieldCensus *census);

/** @brief Corpus bytes read by an anchor probe since the last reset. */
extern uint64_t anchor_steer_probes;

/** @brief Sets the probe counter to zero. */
void anchor_steer_probes_reset(void);

/**
 * @brief Counts occurrences, steering the probe order off the corpus or leaving it alone.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @param[in] steered    1 to order the probes by rarity, 0 to leave the spatial order.
 * @return               How many alignments match exactly.
 *
 * @note ONE KERNEL AND ONE FLAG, so that the missing term is the only thing that differs between
 *       the two routes. Same offsets, same probe loop, same verification; `steered` decides only
 *       the ORDER the probes are evaluated in. A comparison between two separate implementations
 *       would measure the implementations. This measures the ordering.
 * @note The count is identical for both values of `steered` and that is a guarantee rather than an
 *       observation. An alignment survives only when every anchor agrees, a conjunction does not
 *       depend on the order of its terms, and the survivor is verified by a full memcmp either way.
 *       The bench grades it at a residual of exactly zero for that reason and not against a
 *       tolerance.
 * @note `anchor_steer_probes` counts the corpus bytes the probes read, which is where the ordering
 *       pays. Reset it before a run and read it after.
 * @warning Delegates to a full compare at `needle_len` zero rather than probing, because there is
 *          no symbol to probe and no offset that indexes one. That matches the reference arm, which
 *          reports an empty needle as occurring at every alignment.
 */
size_t anchor_steer_count(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                          size_t needle_len, int steered);

#ifdef __cplusplus
}
#endif

#endif /* ANCHOR_STEER_H */
