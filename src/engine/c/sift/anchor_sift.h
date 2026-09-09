/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_sift.h
 * @brief The search arms under test and the dispatcher that chooses between them.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-04
 *
 * @note This is the kernel. Everything here is the thing being measured, and nothing here reads a
 *       clock, builds a corpus or prints a row. Those belong to the driver.
 * @note Every arm has the same signature and returns the same count, letting a driver call any of
 *       them through one pointer. Where two disagree, one of them has a defect. Nothing about the
 *       difference is a tradeoff.
 */
#ifndef ANCHOR_SIFT_H
#define ANCHOR_SIFT_H

#include <stddef.h>
#include <stdint.h>

/** @brief Anchors the sift arms place. The cascade depth log2(N)/H2 sits near five on these corpora. */
#define ANCHOR_SIFT_ANCHORS 4u

/**
 * @brief Set to 1 to build the arms with probe and verification counters.
 *
 * @note Defined on both arms so #if always has a value and an unset build is never a silent false.
 * @note At 0 the counting macros expand to nothing and the object is what it was, letting one
 *       source serve both the timed build and the counted one. A cycle count and a read count
 *       cannot come from the same run: counting perturbs the timing it would be reported beside.
 */
#ifndef ANCHOR_SIFT_COUNT_READS
#define ANCHOR_SIFT_COUNT_READS 0
#endif

#if ANCHOR_SIFT_COUNT_READS

/** @brief Corpus bytes read by an anchor probe since the last reset. */
extern uint64_t anchor_sift_probes;

/** @brief Exact compares performed since the last reset, each reading at most needle_len bytes. */
extern uint64_t anchor_sift_verifications;

/**
 * @brief Sets both counters to zero.
 *
 * @note Present only in a counted build. A driver that calls it unconditionally will not link
 *       against a timed one, which is deliberate: the two builds are not interchangeable.
 */
void anchor_sift_counters_reset(void);

#endif

/**
 * @brief One search arm: count exact occurrences of a needle in a corpus.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @return               How many alignments match exactly.
 */
typedef size_t (*AnchorSiftArm)(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                size_t needle_len);

/**
 * @brief Counts occurrences by comparing at every alignment.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @return               How many alignments match exactly.
 * @note The reference. Every other arm has to agree with it or its measurement is void.
 */
size_t anchor_sift_naive(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                         size_t needle_len);


/**
 * @brief Counts occurrences testing anchors in order, stopping at the first that refutes.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @return               How many alignments match exactly.
 * @note Short circuiting makes each probe wait on the one before it. Measured, this wins on a
 *       memoryless corpus, where the first probe rejects almost every alignment on its own.
 */
size_t anchor_sift_inorder(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                           size_t needle_len);

/**
 * @brief Counts occurrences testing every anchor unconditionally and combining the results.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @return               How many alignments match exactly.
 * @note Dependency depth two. Every probe issues at once and one branch is taken on the combined
 *       result. Measured over 65536 bytes, this runs 2.95 times faster than the in order arm on a
 *       skewed corpus, reaching 3.42 on its widest row, and 1.63 times slower on a memoryless one.
 *       The advantage holds at every needle length from 4 to 256. The rule that chooses between the
 *       two therefore reads no needle length.
 */
size_t anchor_sift_free(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                        size_t needle_len);

/**
 * @brief What the dispatcher needs to choose an arm, all of it cheap to obtain.
 *
 * @note `needle_len` is carried and not read. A ceiling on it was swept over every value the bench
 *       measures and no ceiling beat having none, so the rule below does not consult it. It stays
 *       in the plan because it is free at the call site and because a crossover outside the lengths
 *       measured is the thing a later sweep would find.
 */
typedef struct
{
    double collision_entropy; /**< H2 of the corpus, one pass over a byte histogram. */
    size_t distinct_symbols;  /**< How many byte values the corpus actually uses. */
    size_t needle_len;        /**< Known at the call. Not read by the rule that ships today. */
    size_t period;            /**< Lag the corpus agrees with itself at, or zero where none. */
} AnchorSiftPlan;

/**
 * @brief How many anchors are worth placing on this corpus.
 *
 * @param[in] plan Corpus statistics [BORROWS].
 * @return         ANCHOR_SIFT_ANCHORS where the corpus repeats at no lag, and 1 where it does.
 * @note A corpus that repeats at some period is one orbit under translation at that period.
 *       Position p carries a value fixed by p modulo the period. A needle taken at offset s
 *       therefore has needle[o] fixed by (s + o), and an alignment at `at` matches that anchor when
 *       (at + o) and (s + o) agree modulo the period. The offset cancels, every anchor tests the
 *       same congruence whatever offset it was placed at, and the anchors after the first refute
 *       nothing the first did not already refute.
 * @note Measured on a corpus of period sixteen: four anchors read 1.1875 bytes per alignment and
 *       one anchor reads 1.0000, for the same survivor rate of exactly 1/16. The reads the extra
 *       three anchors perform are their only contribution.
 * @warning A period found is not a period the whole corpus keeps. This returns 1 on any corpus
 *          whose period search cleared its floor, and a partially coherent corpus would want a
 *          count between the two. Nothing here measures that case.
 */
size_t anchor_sift_anchors_for(const AnchorSiftPlan *plan);

/**
 * @brief Counts occurrences using the arm and the anchor count this plan calls for.
 *
 * @param[in] plan       Corpus statistics and the needle length [BORROWS].
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @return               How many alignments match exactly.
 * @note The entry a caller holding a corpus should use. The three arms above stay public because a
 *       bench has to be able to time one of them against another with nothing chosen in between.
 */
size_t anchor_sift_run(const AnchorSiftPlan *plan, const uint8_t *corpus, size_t corpus_len,
                       const uint8_t *needle, size_t needle_len);

/**
 * @brief Returns the arm to run for this corpus.
 *
 * @param[in] plan Corpus statistics and the needle length [BORROWS].
 * @return         The arm to call. Never NULL.
 * @note Every arm is sound, so the choice costs speed and never correctness. A wrong dispatch is
 *       therefore a performance defect instead of a wrong answer.
 * @note One term. A corpus whose effective alphabet 2^H2 sits within ANCHOR_SIFT_FLAT_SHARE of the
 *       symbols it uses takes the short circuiting arm, and every other corpus takes the free order
 *       arm. Scored against the clock over 42 rows this names the faster arm 39 to 41 times and
 *       gives up around one percent of the cycles the worst rule gives up.
 * @note The rule is read off the cycle measurements and belongs to the machine that produced them.
 *       Re-run bench_dispatch before trusting it on another part. It sweeps both thresholds instead
 *       of assuming them, so what it prints is a recommendation to act on, not a confirmation.
 */
AnchorSiftArm anchor_sift_choose(const AnchorSiftPlan *plan);

/**
 * @brief Names the arm the dispatcher would choose, for a driver that wants to print it.
 *
 * @param[in] arm Arm returned by anchor_sift_choose [BORROWS].
 * @return        A static name, or "unknown" where the pointer is not one of the four.
 */
const char *anchor_sift_arm_name(AnchorSiftArm arm);

#endif
