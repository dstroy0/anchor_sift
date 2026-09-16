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
 * @brief Most probes any planner here will place, matching ANCHOR_SIFT_ANCHORS in anchor_sift.h.
 *
 * @note THIS CONSTANT IS THE TERMINATION ARGUMENT. Every descent below places one probe per level
 *       and never revisits one, so the depth is bounded by this value at compile time. It is
 *       declared here rather than in the implementation because it is part of the contract: a
 *       caller sizing an array of probes needs it, and a reader asking whether a recursion
 *       terminates should find its bound in the header rather than having to open the source.
 */
#define ANCHOR_STEER_ANCHORS 4u

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

/**
 * @brief Orders the anchors by conditional pruning, one level per anchor, and reports the depth.
 *
 * @param[in,out] offsets       Anchor offsets, reordered in place into evaluation order [BORROWS].
 * @param[in]     count         How many offsets. At most ANCHOR_STEER_ANCHORS.
 * @param[in]     corpus        Bytes the search will run over [BORROWS].
 * @param[in]     corpus_len    How many.
 * @param[in]     needle        Bytes to find [BORROWS].
 * @param[in]     needle_len    How many.
 * @param[in]     sample_stride Plan on every Nth alignment. 1 reads them all. 0 is treated as 1.
 * @return                      Levels actually descended, which equals `count` on any valid call.
 *
 * WHY RECURSION BUYS ANYTHING OVER ONE PASS. anchor_steer_probe_order ranks the anchors once, by
 * the MARGINAL rarity of each symbol in the whole field. That is the right first question and the
 * wrong second one: once the first probe has rejected almost everything, the alignments still
 * standing are no longer a sample of the field. They are the subset that agreed with one specific
 * symbol, and within that subset the remaining anchors have different pruning power than they had
 * over the field. Ranking the second anchor by its marginal rarity ignores what the first one just
 * told you.
 *
 * This ranks each level against the alignments that actually survived the levels above it, which is
 * the CONDITIONAL distribution rather than the marginal one. It also measures survivors directly
 * instead of inferring them from symbol frequency, so correlation between positions is accounted
 * for rather than assumed away.
 *
 * IT CANNOT FAIL TO TERMINATE, AND NOT BECAUSE ANYBODY CHECKED. The halting problem is about
 * deciding termination for an ARBITRARY program. This recursion is not arbitrary:
 *
 *   - exactly one anchor is placed per level, and a placed anchor is never reconsidered
 *   - the unplaced set therefore shrinks by exactly one each level and never grows
 *   - the depth is `count`, which is bounded by ANCHOR_STEER_ANCHORS, a compile-time constant
 *   - no branch anywhere in the descent depends on corpus content for its DEPTH, only for its
 *     choice at a level
 *
 * So the depth is fixed before the program runs and is readable off the declaration. This is
 * primitive recursion over a finite set with a constant bound, which terminates by construction the
 * way a `for` loop over a fixed array does. There is no runtime guard, no iteration cap and no
 * watchdog here, because a bound enforced at compile time does not need one and a runtime check
 * would imply the bound were in doubt. The return value exists so a caller can ASSERT the depth
 * rather than trust this paragraph.
 *
 * @note THE PLANNER IS ALLOWED TO BE WRONG. Ordering cannot change which alignments survive, since
 *       an alignment survives only when every anchor agrees and a conjunction is order independent.
 *       So a planner that samples, guesses badly, or is outright defective costs speed and cannot
 *       cost correctness. That is what makes `sample_stride` safe: planning on a subset risks a
 *       worse order and never a wrong count.
 * @note Does nothing and returns 0 where any pointer is null, where `count` is zero, or where
 *       `needle_len` is zero. A zero length needle has no symbol to rank.
 */
size_t anchor_steer_plan_recursive(size_t *offsets, size_t count, const uint8_t *corpus,
                                   size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                   uint8_t *scratch, size_t scratch_len, size_t sample_stride);

/**
 * @brief Spawns coarms at the positions that prune most, one per level, and places them in order.
 *
 * @param[out] offsets       Where the chosen offsets are written, in evaluation order [BORROWS].
 * @param[in]  wanted        How many coarms to spawn. At most ANCHOR_STEER_ANCHORS.
 * @param[in]  corpus        Bytes the search will run over [BORROWS].
 * @param[in]  corpus_len    How many.
 * @param[in]  needle        Bytes to find [BORROWS].
 * @param[in]  needle_len    How many.
 * @param[out] scratch       Survivor flags, one byte per alignment [BORROWS].
 * @param[in]  scratch_len   How many bytes of scratch. Must reach the alignment count.
 * @param[in]  sample_stride Plan on every Nth alignment. 1 reads them all. 0 is treated as 1.
 * @return                   Coarms actually placed, which equals `wanted` on any valid call.
 *
 * SPAWNING RATHER THAN REORDERING. anchor_steer_plan_recursive takes anchors somebody else placed
 * and decides the order to test them in. This decides WHERE THEY GO. At each level it asks every
 * position in the needle how many of the currently surviving alignments would still stand if a
 * coarm were placed there, and puts one at the position that leaves fewest. The arm is spawned at
 * the place the field says is worth reading, rather than at a place a spread rule chose before the
 * field was looked at.
 *
 * That is the same steering the rest of this file applies, moved from the order to the placement.
 * The spread rule in anchor_sift.c answers "where, knowing nothing" and this answers "where, given
 * the corpus and given what the coarms already placed have ruled out".
 *
 * TERMINATION IS THE SAME COMPILE TIME FACT. One coarm per level, a placed position never
 * reconsidered, depth exactly `wanted` and bounded by ANCHOR_STEER_ANCHORS. Nothing in the descent
 * lets corpus content change the DEPTH, only the choice made at a level. The return value is there
 * so a caller can assert the count rather than trust the prose.
 *
 * @note FAILS CLOSED ON SCRATCH. Returns 0 without writing `offsets` where `scratch_len` does not
 *       reach the alignment count. The kernel allocates nothing, so the buffer is the caller's and
 *       a buffer too small is refused rather than worked around. Size it at
 *       `corpus_len - needle_len + 1`.
 * @note A planner is free to be wrong here for the same reason it is free to be wrong anywhere else
 *       in this file: placement and order change which probe rejects first, never which alignments
 *       survive. The verification is a full compare either way.
 * @warning Costs `wanted * needle_len * alignments / sample_stride` byte comparisons to plan. On a
 *          long needle that exceeds the scan it is planning for. `sample_stride` is the control,
 *          and bench_steer measures where the trade turns over rather than asserting a default.
 */
size_t anchor_steer_spawn_coarms(size_t *offsets, size_t wanted, const uint8_t *corpus,
                                 size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 uint8_t *scratch, size_t scratch_len, size_t sample_stride);

/**
 * @brief One probe placed on the needle. An arm is a point, an eye is a line.
 *
 * ONE SHAPE SERVES BOTH, WHICH IS THE SAME STATEMENT arm-records.md MAKES ABOUT READINGS. An arm is
 * a region integral and an eye is a line integral, and the difference between them lives in the
 * shape of the support, not in the arithmetic applied to it. Here that means an arm is an eye whose
 * length is one, and the same test walks both.
 *
 * @note `step` is unread at `length` one, and is what makes a longer probe a LINE through the
 *       needle rather than a run of adjacent bytes. A step that shares a period with the needle
 *       reads the same residue repeatedly and prunes badly, which is a real failure mode and is why
 *       the sweep measures steps instead of assuming one.
 * @note Every position the probe touches must land inside the needle. anchor_steer_probe_fits is
 *       the test and the sweep applies it before a shape is ever scored.
 */
typedef struct
{
    size_t origin; /**< First position in the needle this probe reads. */
    size_t step;   /**< Distance between successive positions. Unread where length is one. */
    size_t length; /**< Positions read. One is an arm, more is an eye. */
} AnchorProbe;

/**
 * @brief Whether every position a probe reads lands inside the needle.
 *
 * @param[in] probe      Probe to test [BORROWS].
 * @param[in] needle_len Length it must fit inside.
 * @return               1 where it fits, 0 otherwise.
 * @note Computed without forming the last position as a sum, so a step and length that would
 *       overflow size_t are refused rather than wrapping into a position that looks valid.
 */
int anchor_steer_probe_fits(const AnchorProbe *probe, size_t needle_len);

/**
 * @brief Spawns probes anywhere on the needle, sweeping shapes, and orders them by pruning.
 *
 * @param[out] probes        Where the chosen probes are written, in evaluation order [BORROWS].
 * @param[in]  wanted        How many to spawn. At most ANCHOR_STEER_ANCHORS.
 * @param[in]  corpus        Bytes the search will run over [BORROWS].
 * @param[in]  corpus_len    How many.
 * @param[in]  needle        Bytes to find [BORROWS].
 * @param[in]  needle_len    How many.
 * @param[in]  max_length    Longest eye to consider. One restricts the sweep to arms.
 * @param[out] scratch       Survivor flags, one byte per alignment [BORROWS].
 * @param[in]  scratch_len   How many bytes of scratch. Must reach the alignment count.
 * @param[in]  sample_stride Plan on every Nth alignment. 1 reads them all. 0 is treated as 1.
 * @return                   Probes actually placed.
 *
 * THE SWEEP TOUCHES EVERYTHING IT IS ALLOWED TO REACH. At each level it considers every origin in
 * the needle, every step that keeps the probe inside it, and every length up to `max_length`, scores
 * each shape by how many currently truthy alignments would still stand, and spawns the one that
 * leaves fewest. Nothing about the placement is inherited from a spread rule and nothing about the
 * shape is assumed; a point probe wins where a point probe is best, and a line wins where a line is.
 *
 * AN EYE IS NOT FREE AND THE SWEEP KNOWS IT. A probe of length L reads up to L bytes per alignment
 * where an arm reads one, so an eye has to prune more than L times as hard to be worth spawning.
 * The score here is survivors, which does not carry that cost, so the caller comparing an eye
 * against an arm has to compare READS and not survivors. bench_steer does exactly that and reports
 * both, which is why the guide recommends measuring rather than reaching for the longest eye.
 *
 * TERMINATION, unchanged and for the same reason. One probe per level, `wanted` levels, bounded by
 * ANCHOR_STEER_ANCHORS at compile time. The sweep inside a level is three nested bounded loops over
 * needle_len, needle_len and max_length. Nothing in it is data dependent in its EXTENT.
 *
 * @note Every shape the sweep can spawn leaves the count unchanged, so the whole sweep moves inside
 *       the null group and can be as wrong as it likes without costing an answer.
 * @note Fails closed on scratch exactly as anchor_steer_spawn_coarms does.
 * @warning The sweep is `wanted * needle_len^2 * max_length^2 * alignments / sample_stride` byte
 *          comparisons at worst. One factor of max_length counts the lengths enumerated. The second
 *          comes from scoring: a candidate of length L costs up to L comparisons, and summing L
 *          from 1 to max_length averages about max_length/2. An earlier form of this note charged
 *          one comparison per candidate and understated the bound in the unsafe direction.
 *          anchor_steer_probe_fits rejects shapes that do not fit, so the real count sits below
 *          this figure. It is still far more than the scan it plans on any but a tiny needle, and
 *          it is a planner for a search run many times against one needle rather than for a single
 *          shot. `sample_stride` is what makes it affordable.
 */
size_t anchor_steer_sweep_probes(AnchorProbe *probes, size_t wanted, const uint8_t *corpus,
                                 size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 size_t max_length, uint8_t *scratch, size_t scratch_len,
                                 size_t sample_stride);

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

/**
 * @brief Counts occurrences using a probe set the caller supplies, in the order given.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @param[in] probes     Probes in evaluation order [BORROWS].
 * @param[in] count      How many probes. Zero sends every alignment to the full compare.
 * @return               How many alignments match exactly.
 *
 * @note THE ENTRY A TEST NEEDS AND A CALLER RARELY DOES. Everything else here chooses its own
 *       probes, which is the point of a steering engine and is also what makes the guarantee hard
 *       to attack from outside. This takes the probe set as an argument, so a caller can hand over
 *       a permutation of one set and check the count is unchanged, hand over a probe built from the
 *       census instead of the needle and watch the count break, or hand over none at all.
 * @note The empty probe set is the identity. Every alignment reaches the full compare, the answer
 *       is exactly right, and the cost is maximal. That is the cheapest total check of the whole
 *       guarantee and it is why `count` of zero is accepted rather than refused.
 * @note `anchor_steer_probes` counts the corpus bytes the probes read, as it does for
 *       anchor_steer_count. Reset it before a run and read it after.
 */
size_t anchor_steer_count_with_probes(const uint8_t *corpus, size_t corpus_len,
                                      const uint8_t *needle, size_t needle_len,
                                      const AnchorProbe *probes, size_t count);

#ifdef __cplusplus
}
#endif

#endif /* ANCHOR_STEER_H */
