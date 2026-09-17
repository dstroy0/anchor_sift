/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_sift.h
 * @brief The engine: the search, the steering that places its probes, and the scan underneath both.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-04
 *
 * @note This is the kernel. Everything here is the thing being measured, and nothing here reads a
 *       clock, builds a corpus or prints a row. Those belong to the driver.
 * @note ONE PRIMITIVE, WRITTEN ONCE. Every loop below asks whether `corpus[at + offset]` equals
 *       `needle[offset]` and counts the positions where it does. The search counts matches, the
 *       steering counts survivors, and the scan counts the same survivors wider. They were three
 *       files until they were folded here, which is why a reader looking for the engine now opens
 *       one file instead of a directory.
 * @note Every engine has the same signature and returns the same count, letting a driver call any
 *       of them through one pointer. Where two disagree, one of them has a defect. Nothing about
 *       the difference is a tradeoff.
 */
#ifndef ANCHOR_SIFT_H
#define ANCHOR_SIFT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The dispatch rule reads the field's census directly, so the plan carries one. This is what makes
 * the rule exact: the census holds integer counts and the comparison clears its denominators into
 * integers, where the old form took a logarithm and approximated a power of two in double. */

/** @brief Anchors a sift engine places. The cascade depth log2(N)/H2 sits near five on these corpora. */
#define ANCHOR_SIFT_ANCHORS 4u

/**
 * @brief Set to 1 to build the engines with probe and verification counters.
 *
 * @note Both arms of the gate defined, so #if always has a value and an unset build is never a
 *       silent false.
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

/** @brief Distinct values a byte takes, which is the width of every census below. */
#define ANCHOR_STEER_SYMBOLS 256u

/**
 * @brief Most probes any planner here will place, defined as ANCHOR_SIFT_ANCHORS so the two cannot
 *        drift.
 *
 * @note THIS CONSTANT IS THE TERMINATION ARGUMENT. Every descent below places one probe per level
 *       and never revisits one, so the depth is bounded by this value at compile time. It is
 *       declared here rather than in the implementation because it is part of the contract: a
 *       caller sizing an array of probes needs it, and a reader asking whether a recursion
 *       terminates should find its bound in the header rather than having to open the source.
 * @note DEFINED FROM ANCHOR_SIFT_ANCHORS, NOT COPIED. An earlier form wrote `4u` here and a comment
 *       claiming it matched ANCHOR_SIFT_ANCHORS. Nothing held that: the two were independent
 *       literals, and changing ANCHOR_SIFT_ANCHORS would have left the comment false while every
 *       file still compiled. Defining one from the other makes the compiler hold the invariant the
 *       termination argument rests on.
 */
#define ANCHOR_STEER_ANCHORS ANCHOR_SIFT_ANCHORS

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
 * @brief One search engine: count exact occurrences of a needle in a corpus.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @return               How many alignments match exactly.
 */
typedef size_t (*AnchorSiftEngine)(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                   size_t needle_len);

/**
 * @brief Counts occurrences by comparing at every alignment.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @return               How many alignments match exactly.
 * @note The reference. Every other engine has to agree with it or its measurement is void.
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
 * @note Short circuiting makes each probe wait on the one before it. Measured, this is faster on a
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
 *       result. Measured over 65536 bytes, this runs 2.95 times faster than the in order engine on a
 *       skewed corpus, reaching 3.42 on its widest row, and 1.63 times slower on a memoryless one.
 *       The advantage holds at every needle length from 4 to 256. The rule that chooses between the
 *       two therefore reads no needle length.
 */
size_t anchor_sift_free(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                        size_t needle_len);

/**
 * @brief What the dispatcher needs to choose an engine, all of it cheap to obtain.
 *
 * THE FIELD'S CENSUS AND NOT A NUMBER DERIVED FROM IT. The rule this plan feeds asks whether the
 * effective alphabet reaches a share of the symbols actually used, and both quantities come out of
 * one pass over the corpus. Carrying the census means the rule reads them exactly, in integers, and
 * the engine holds no floating point value anywhere.
 *
 * @note `distinct_symbols` USED TO SIT HERE and was removed rather than left unread. The census
 *       computes the same number authoritatively, and a public structure carrying a second copy
 *       lets a caller hand over two values that disagree with nothing to catch it. An unread field
 *       is untidy; a field that can contradict the truth beside it is a defect waiting for someone
 *       to fill in both.
 * @note `needle_len` is carried and not read, and that is a different case. A ceiling on it was
 *       swept over every value the bench measures and no ceiling beat having none, so the rule does
 *       not consult it. It duplicates nothing, so it stays.
 * @warning `census` is BORROWED for the duration of every call taking this plan. It is a pointer
 *          rather than an embedded structure because AnchorFieldCensus is about two kilobytes and a
 *          plan is passed by pointer on a hot path.
 */
typedef struct
{
    const AnchorFieldCensus *census; /**< The field's own census, which the rule reads [BORROWS]. */
    size_t needle_len;               /**< Known at the call. Not read by the rule that ships today. */
    size_t period;                   /**< Lag the corpus agrees with itself at, or zero where none. */
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
 * @brief Counts occurrences using the engine and the anchor count this plan calls for.
 *
 * @param[in] plan       Corpus statistics and the needle length [BORROWS].
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @return               How many alignments match exactly.
 * @note The entry a caller holding a corpus should use. The three engines above stay public because a
 *       bench has to be able to time one of them against another with nothing chosen in between.
 */
size_t anchor_sift_run(const AnchorSiftPlan *plan, const uint8_t *corpus, size_t corpus_len,
                       const uint8_t *needle, size_t needle_len);

/**
 * @brief Returns the engine to run for this corpus.
 *
 * @param[in] plan Corpus statistics and the needle length [BORROWS].
 * @return         The engine to call. Never NULL.
 * @note Every engine is sound, so the choice costs speed and never correctness. A wrong dispatch is
 *       therefore a performance defect instead of a wrong answer.
 * @note One term, decided by anchor_steer_prefers_free in exact integer arithmetic. A corpus whose
 *       effective alphabet 2^H2 reaches 85 percent of the symbols it uses takes the free order
 *       engine, and every other corpus takes the short circuiting one. Since 2^H2 is total squared
 *       over the sum of squared counts, the comparison clears its denominators into
 *       100*total^2 >= 85*distinct*sum(count^2) and holds no floating point value anywhere.
 *       Scored against the clock over 42 rows by bench_dispatch: 39 of 42 giving up 9131790 cycles
 *       at a share of 0.035 on x64 MSVC 19.44 Release, and 41 of 42 giving up 86511 at 0.000 under
 *       gcc. A hundredfold gap in cycles between two real runs, so the figure belongs to the
 *       toolchain that produced it. Re-run the bench before quoting either. An earlier form of this
 *       note said "around one percent", which no recorded run produced.
 * @note THE NEEDLE LENGTH TERM CHANGES NO ANSWER ON THIS DATA. Scoring flatness alone ties this rule
 *       exactly, same rows and same cycles, across all 42. It is kept rather than removed because a
 *       tunable with no reader is an integration point, and it is named here so nobody concludes
 *       from the code that it is carrying weight. Find a row where it pays or leave it inert.
 * @note The rule is read off the cycle measurements and belongs to the machine that produced them.
 *       Re-run bench_dispatch before trusting it on another part. It sweeps both thresholds instead
 *       of assuming them, so what it prints is a recommendation to act on, not a confirmation.
 */
AnchorSiftEngine anchor_sift_choose(const AnchorSiftPlan *plan);

/**
 * @brief Names the engine the dispatcher would choose, for a driver that wants to print it.
 *
 * @param[in] engine Engine returned by anchor_sift_choose [BORROWS].
 * @return           A static name, or "unknown" where the pointer is not one of the four.
 */
const char *anchor_sift_engine_name(AnchorSiftEngine engine);


/* ---- the steering, folded in ---- */



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
 * @brief Whether this field wants the free order engine, decided in exact integer arithmetic.
 *
 * @param[in] census Field census [BORROWS].
 * @return           1 for the free order engine, 0 for the short circuiting engine.
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
 * @brief Answers whether two positions carry the same symbol.
 *
 * @param[in] field     Whatever the caller is searching, opaque to the engine [BORROWS].
 * @param[in] corpus_at Position in the field.
 * @param[in] needle_at Position in the pattern.
 * @return              Non-zero where the two positions carry the same symbol, zero otherwise.
 *
 * @note THIS IS THE WHOLE INTERFACE THE ENGINE NEEDS TO A SYMBOL. Not an order, not a hash, not a
 *       size, not an enumeration of the alphabet. Equality at two positions and nothing else, which
 *       is exactly what the soundness proof uses: a subset of a pattern's points is a necessary
 *       condition, and the proof reads no order, no dimension and no alphabet.
 * @note A symbol may therefore be a byte, a 32 bit sample, an exact rational, a point in eight
 *       dimensions, a pointer compared by identity, or a value only its owner can compare. The
 *       engine never learns which, so an alphabet that cannot be enumerated or hashed costs it
 *       nothing.
 * @note THIS ENGINE WAS THE NARROW ONE AND THE REST OF THE TREE WAS NOT. bench_lattice has taken a
 *       callback since it was written, and the python cascade has never needed bytes either: its
 *       `survivors` indexes a dict by symbol and `positions_by_symbol` builds that dict from any
 *       iterable of values, so it requires equality and hashability and nothing else. A
 *       crystallography example feeds it element strings and has done so for longer than this note
 *       has existed. The C entries demanded a `uint8_t *` and were therefore narrower both than the
 *       proof they implement and than the python engine they are checked against.
 * @note The two are STILL not equivalent and the difference runs the other way now. A dict key must
 *       be hashable; this oracle asks only whether two positions are equal. A value that cannot be
 *       hashed, or whose equality is expensive and whose hash would be a lie, can be searched here
 *       and cannot be searched there. Anyone grading the two engines against each other should know
 *       which fields only one of them can accept.
 * @warning Must be a pure function of the two positions for the duration of a call. The engine
 *          reads the same position more than once and assumes the answer does not move under it.
 */
typedef int (*AnchorSameAt)(const void *field, size_t corpus_at, size_t needle_at);

/**
 * @brief A field of any symbol type, reached only through equality.
 *
 * @note Carries no element size and no element pointer. The engine indexes positions and asks the
 *       oracle about them, so where the symbols live and how wide they are belong to the caller.
 * @warning `alignments` is the number of positions that can host a pattern, which for a linear field
 *          of `n` symbols is `n - needle_len + 1`. The engine cannot compute it, because it does not
 *          know the field's shape, and a caller that supplies it wrongly gets a wrong sweep rather
 *          than a refusal.
 */
typedef struct
{
    AnchorSameAt same;  /**< Equality oracle. Never null. */
    const void *field;  /**< Passed to the oracle untouched, never dereferenced here [BORROWS]. May
                         *   be null ONLY where the ORACLE does not dereference it either, which
                         *   means an oracle reaching its data some other way. The engine never uses
                         *   it, so "if unused" read as a condition always satisfied; the condition
                         *   is on the oracle. Passing null to an oracle that reads it faults inside
                         *   the oracle, where the engine cannot see it coming. */
    size_t alignments;  /**< Positions that can host the pattern. Non-zero. */
    size_t needle_len;  /**< Positions the pattern holds. Non-zero. */
} AnchorField;

/**
 * @brief Projects a field of any symbol type onto a field of rarity ranks.
 *
 * @param[in] args What to project and where to put it [BORROWS].
 * @return         1 where the projection was written, 0 where it was refused.
 *
 * @warning RANKS FROM TWO CALLS ARE NOT COMPARABLE, AND COMPARING THEM LOSES TRUE OCCURRENCES.
 *          A rank is not a property of a symbol. It is a property of a symbol WITHIN THE POPULATION
 *          THIS CALL SAW, and the population is part of the answer. The class a position falls in
 *          comes from the oracle, which the CALLER supplies, so it is the same relation whatever
 *          field it is applied to. The rarity place comes from counting THIS field, so it is not.
 *          The rank fuses the two and only the first half survives the trip to another field.
 *
 *          It is a hash and a nonce. The class is the digest and the population is the nonce, and a
 *          digest computed under one nonce cannot be checked against a digest computed under
 *          another however identical the input was.
 *
 *          THE FAILURE IS SILENT AND IT IS IN THE UNSAFE DIRECTION. Take symbols where A occurs
 *          once, B ten times and C a hundred times, and search for the needle C C B A. Projected
 *          alone, the corpus ranks A below B because one is rarer than ten. Projected alone, the
 *          needle holds one A and one B, they TIE, and the tie breaks on class index the other way
 *          round. Rank disagreement then reports symbol disagreement where the symbols agree, a
 *          probe refutes an alignment that truly matches, and the count comes back one short with
 *          nothing in the return value to say so.
 *
 *          That inverts the necessary condition this construction rests on. Everywhere else in this
 *          file an ordering decision is a null: a wrong order costs reads and leaves the count
 *          unchanged. Here a wrong order loses a true occurrence.
 *
 *          Use anchor_field_pair_project to search one field for another. It numbers both in one
 *          call, which gives one population and one rarity order, and the ranks it writes are
 *          comparable by construction. This entry remains the one to call for describing a single
 *          field.
 *
 * @note THE COMPONENT COUNT IS UNBOUNDED AND ONLY THE OUTPUT IS CLAMPED. Classes are discovered
 *       with no ceiling, ordered by rarity across every one of them, and the byte rank is clamped
 *       at relabel time, so a field with a thousand classes keeps its 255 rarest apart and merges
 *       the commonest into rank 255. That is the direction the steering needs, because a probe's
 *       survivor count is its class frequency and the rarest class is the best probe available.
 *       The class buffers exist to carry those components; the kernel allocates nothing.
 *
 * @note `same_in_field` NEED NOT BE TRANSITIVE, AND THE CLASSES ARE ITS TRANSITIVE CLOSURE. This
 *       matters because the predicate that motivates having an oracle at all is not transitive: a
 *       tolerance match over real valued coordinates is meaningful, and `a` within tolerance of `b`
 *       and `b` of `c` does not put `a` within tolerance of `c`.
 *       `examples/proteins/5_sift/protein_domain.py:66-74` is exactly that, and states why exact
 *       equality is the wrong test on a continuous domain.
 *
 *       Soundness needs agreement to imply a shared rank. It does NOT need a shared rank to imply
 *       agreement, so the labelling has to be a superset of the relation, and the smallest superset
 *       that is an equivalence is the transitive closure. Classes are therefore connected
 *       components: a position joins every class it matches and merges them.
 *
 *       An earlier form stopped at the first matching representative, which is neither the relation
 *       nor its closure, and under a non-transitive predicate it put agreeing positions in different
 *       classes, broke the necessary condition, and would have rejected alignments holding true
 *       occurrences silently. That is fixed rather than documented as a precondition.
 * @warning THE COST OF TAKING THE CLOSURE IS CHAINING. A loose tolerance can walk the whole field
 *          into one component through a path of near neighbours, none of which agree with the ends.
 *          One class ranks everything alike, every rank probe then refutes nothing, and the search
 *          falls back to the exact compare at every alignment. That is useless and it is exactly
 *          sound, since a probe that rejects nothing is still a necessary condition. Tighten the
 *          predicate where it happens; the symptom is `distinct` coming back as one on a field the
 *          caller expects to be varied.
 * @warning TAKES A DIFFERENT ORACLE FROM AnchorField's, AND THE DISTINCTION IS NOT COSMETIC.
 *          AnchorSameAt as used by a descent answers about a CORPUS position against a NEEDLE
 *          position, which are two index spaces. Grouping a field into classes compares two
 *          positions of the FIELD. Passing a descent's oracle here indexes the needle with a field
 *          position and reads off the end of it, which is exactly the fault this signature was
 *          changed to prevent after it segfaulted the suite.
 *
 * WHY PROJECT AT ALL. A probe only has to be a necessary condition of an occurrence. Within one
 * projection, two positions in one class carry one rank, so rank disagreement proves symbol
 * disagreement and a rank probe refutes a subset of what a symbol probe refutes. Rank agreement does
 * not prove symbol agreement, and a filter does not need it to. The engine's construction is that a
 * necessary condition may be weaker than the thing it screens for.
 *
 * What that buys is the wide path. An equality oracle cannot be vectorized, because a wide compare
 * is a statement about a representation and the oracle deliberately hides one. Ranks are bytes, so
 * a field of any symbol type becomes a field the existing byte engine reads at full speed, AVX2
 * scan included. A real valued alphabet, a point in eight dimensions and an opaque handle all
 * project to the same shape and all run on the same loop.
 *
 * @note Ranks are ORDERED BY RARITY, rarest first, which is the order the steering already wants.
 *       The rank is therefore not an arbitrary label: rank zero is the class that refutes most
 *       alignments, and a planner reading the projected field gets the entropy ordering for free.
 * @note A SEARCH OVER RANK FIELDS COUNTS RANK MATCHES, AND THAT EQUALS THE SYMBOL COUNT ONLY AT 256
 *       CLASSES OR FEWER. Places then run from 0 to 255 and none is clamped, so one rank names one
 *       class and the two counts are the same integer. Past 256 classes every class at place 255 or
 *       later takes rank 255, alignments whose symbols differ can agree on every rank, and the byte
 *       engine's full compare cannot remove them, because on rank fields it compares ranks. The
 *       count is then an upper bound. It never falls below the symbol count, and case 13 in
 *       test/engine/test_adversarial.c measures it above: 44 against 1 on a 300-class field. For an
 *       exact count past 256 classes, check the rank survivors against the symbols through the
 *       oracle, or give the oracle to a descent directly.
 * @warning COSTS UP TO `length` SQUARED ORACLE CALLS AND THAT IS NOT A LOOSE BOUND. Computing the
 *          transitive closure of a graph reachable only through a pairwise probe needs the pairs,
 *          and the predicate may be one the caller chose for being approximate, so there is no
 *          correct shortcut. The only saving taken is skipping a pair already in one component,
 *          which is real on a chained field and nothing on a field of singletons.
 *
 *          An earlier form compared each position against one representative per class, which is
 *          `length` times `distinct` and is correct ONLY for a transitive predicate. It is not
 *          offered as a fast path, because selecting it would be asserting transitivity and the
 *          cost of being wrong is a silently wrong answer.
 *
 *          A field of a few thousand positions projects in a moment; one of a hundred thousand does
 *          not. Project a representative slice, or do not project at all and pass the oracle
 *          straight to a descent, which needs no closure and no projection and costs nothing extra.
 */
typedef struct
{
    AnchorSameAt same_in_field;      /**< Equality between two positions OF THE FIELD. Never null. */
    const void *field;               /**< Passed to the oracle untouched, never dereferenced here
                                      *   [BORROWS]. May be null ONLY where the oracle does not
                                      *   dereference it either, which means an oracle reaching its
                                      *   data some other way. Passing null to an oracle that reads
                                      *   it faults inside the oracle, and the engine cannot see
                                      *   that coming. */
    size_t length;                   /**< Positions to project. Non-zero. */
    uint8_t *ranks;                  /**< One rarity rank per position, written whole [BORROWS]. */
    uint32_t *class_of_position;     /**< Which class each position fell in, one entry per position,
                                      *   written during the call [BORROWS]. */
    uint32_t *members_in_class;      /**< How many positions each class holds, indexed by the class,
                                      *   written during the call [BORROWS]. */
    uint32_t *rarity_place_of_class; /**< Where each class sits in the rarity order, indexed by the
                                      *   class, written during the call [BORROWS]. */
    size_t classes_length;           /**< Entries each of the three above holds. Must reach
                                      *   `length`, since every position can be its own class. */
    size_t *distinct;                /**< Where the class count is written, or NULL [BORROWS]. */
} AnchorFieldProjection;

int anchor_field_project(const AnchorFieldProjection *args);

/**
 * @brief Numbers a corpus and a needle in ONE population, so their ranks can be compared.
 *
 * @note WHY THIS EXISTS AT ALL. anchor_field_project projects one field and its ranks mean something
 *       only inside it. Two separate calls produce two rarity orders over two populations, and a
 *       rank probe run across them refutes alignments whose symbols agree. The other ordering
 *       decisions in this file cost reads when they are wrong. This one loses true occurrences. A
 *       warning on the single-field entry can be read past. A caller of this entry cannot reach the
 *       broken construction at all, because the entry numbers both sides in one call.
 *
 * @note THE JOINT INDEX SPACE, which the caller's oracle must answer over. Positions `0` through
 *       `corpus_length - 1` are the corpus. Positions `corpus_length` through
 *       `corpus_length + needle_length - 1` are the needle. `same_in_field` is asked about two
 *       JOINT positions and has to reach whichever side each one names. Concatenation is the
 *       obvious way to hold that and it is not the only one; the engine never dereferences the
 *       field and does not care.
 *
 * @note THE ORACLE HERE IS FIELD AGAINST FIELD, NOT CORPUS AGAINST NEEDLE. It takes two joint
 *       positions drawn from one space. `AnchorField.same` in a descent takes a CORPUS position and
 *       a NEEDLE position, which are two spaces. The two have the same C type and different
 *       meanings, so the compiler cannot catch the swap and passing one where the other belongs
 *       reads off the end of something.
 */
typedef struct
{
    AnchorSameAt same_in_field;      /**< Equality between two positions of the JOINT field. Never
                                      *   null. Asked about joint positions, never about a corpus
                                      *   position paired with a needle position. */
    const void *field;               /**< Passed to the oracle untouched, never dereferenced here
                                      *   [BORROWS]. May be null ONLY where the oracle reaches its
                                      *   data some other way. */
    size_t corpus_length;            /**< Corpus positions, at joint `0` onward. Non-zero. */
    size_t needle_length;            /**< Needle positions, at joint `corpus_length` onward.
                                      *   Non-zero, and no longer than `corpus_length`. */
    uint8_t *corpus_ranks;           /**< `corpus_length` ranks for the corpus side [BORROWS]. */
    uint8_t *needle_ranks;           /**< `needle_length` ranks for the needle side [BORROWS]. */
    uint32_t *class_of_position;     /**< Which class each joint position fell in, one entry per
                                      *   joint position, written during the call [BORROWS]. */
    uint32_t *members_in_class;      /**< How many joint positions each class holds, indexed by the
                                      *   class, written during the call [BORROWS]. */
    uint32_t *rarity_place_of_class; /**< Where each class sits in the one rarity order, indexed by
                                      *   the class, written during the call [BORROWS]. */
    size_t classes_length;           /**< Entries each of the three above holds. Must reach
                                      *   `corpus_length + needle_length`, since every joint
                                      *   position can be its own class. */
    size_t *distinct;                /**< Where the class count over the JOINT field is written, or
                                      *   NULL [BORROWS]. */
} AnchorFieldPairProjection;

/**
 * @brief Projects a corpus and a needle onto one rarity order, writing each side its own ranks.
 *
 * @param[in] args What to project and where to put it [BORROWS].
 * @return         1 where both rank arrays were written, 0 where the call was refused.
 *
 * @note WHAT THE CALLER DOES WITH THE RESULT. `corpus_ranks` and `needle_ranks` are byte fields
 *       numbered by one rule, so they can go to anchor_steer_count or to any entry here that takes
 *       bytes. What the count means depends on how many classes the joint field holds, and
 *       `distinct` tells the caller which case applies.
 *
 * @note AT 256 CLASSES OR FEWER THE RANK COUNT IS THE EXACT COUNT. Places run from 0 to 255 and
 *       none is clamped, so one rank names one class, rank agreement is class agreement, and a
 *       search over the rank fields returns the integer a search over the symbols would.
 *
 * @note PAST 256 CLASSES THE RANK COUNT IS AN UPPER BOUND. Every class at
 *       place 255 or later takes rank 255, so two different classes can agree on rank. A search
 *       over the rank fields counts those alignments too, and its full compare cannot remove them,
 *       because on rank fields the full compare compares ranks. The direction the filter needs
 *       still holds: one class takes one rank across the whole joint field, so symbol agreement
 *       implies rank agreement and no true occurrence is lost. For an exact count past 256 classes,
 *       check the rank survivors against the symbols through the oracle, or run the descent on the
 *       oracle directly.
 *
 * @note Refuses, writing nothing, where `args` or any pointer but `distinct` is null, where either
 *       length is zero, where `needle_length` exceeds `corpus_length`, where the joint length
 *       `corpus_length + needle_length` would wrap `size_t`, where that joint length exceeds
 *       `UINT32_MAX` (class labels are stored as 32 bit positions and a wider field would alias two
 *       of them onto one label), or where `classes_length` does not reach the joint length. The
 *       return value is the whole report, as it is for anchor_field_project.
 *
 * @warning COSTS THE SAME CLOSURE THE SINGLE FIELD ENTRY DOES, over a longer field. The pairwise
 *          closure is quadratic in `corpus_length + needle_length`, so this is for fields small
 *          enough to project at all. A descent takes the oracle directly, needs no closure, and
 *          costs nothing extra.
 */
int anchor_field_pair_project(const AnchorFieldPairProjection *args);

/**
 * @brief Everything a descent reads, as one argument.
 *
 * ONE STRUCT FOR THE WHOLE FAMILY. The reordering descent and the spawning descent ask the same
 * question of the same field and differ only in where their candidates come from. They took nine
 * and ten positional parameters before this, four of them `size_t` in a row, which is a call a
 * reader cannot check and a caller can transpose silently.
 *
 * @note AN OMITTED MEMBER IS ZERO AND THAT IS PART OF THE CONTRACT. `sample_stride` of zero is read
 *       as one, `force_full_depth` of zero honors the destroy rule, `any` of zero takes the byte
 *       path, and `resume` of zero resets the survivors to all standing. A caller that names none of
 *       them gets the full sweep, the destroy rule, bytes, and a fresh survivor set, which is what
 *       almost every caller wants.
 *
 * ANY SYMBOL TYPE, THROUGH `any`. Set it and the engine reads the field only through an equality
 * oracle, never touching `corpus` or `needle`. That is not a convenience wrapper over the byte path;
 * it is the path the theory describes, and the byte members are the specialization. Soundness uses
 * equality alone and reads no order, no dimension and no alphabet, so an engine that demands a
 * `uint8_t *` is narrower than its own proof. The byte path stays because it is faster and because
 * every existing caller passes bytes.
 *
 * WHAT `force_full_depth` EXISTS TO MAKE TESTABLE. The descent normally stops at a level whose best
 * candidate leaves the truthy population unchanged, and destroys every level below it. Stopping and
 * continuing are therefore claimed to be equivalent, and this member is what lets a caller check the
 * claim instead of believing it. Set it, and THE COUNT PRODUCED BY THE RESULTING PROBE SET MUST BE
 * IDENTICAL while the placed probe count MAY be larger. A test comparing the two runs gets two
 * separable failures: if the counts ever differ the necessary-condition guarantee broke, and if the
 * probes placed before the stop point ever differ the induction broke. One member, two meanings a
 * reader can tell apart.
 *
 * @note It was a separate entry, anchor_steer_spawn_coarms_deep, taking ten positional parameters.
 *       A member an omitted initializer leaves zero does the same work, and two entries sharing one
 *       descent is the drift this structure was adopted to remove.
 * @warning Every pointer here is BORROWED for the duration of the call. `survivors` is written and
 *          `corpus` and `needle` are only read.
 */
typedef struct
{
    size_t *offsets;       /**< Where the chosen offsets are written [BORROWS]. */
    size_t count;          /**< Offsets to place. At most ANCHOR_STEER_ANCHORS. */
    const uint8_t *corpus; /**< Bytes the search will run over [BORROWS]. Unread where `any` is set. */
    size_t corpus_len;     /**< How many. Unread where `any` is set. */
    const uint8_t *needle; /**< Bytes to find [BORROWS]. Unread where `any` is set. */
    size_t needle_len;     /**< How many. Unread where `any` is set. */
    uint8_t *survivors;    /**< One byte per alignment, written during the call [BORROWS]. THE
                            *   DESCENT'S OUTPUT AND NOT A TEMPORARY: it records, per alignment,
                            *   whether the probes left that alignment standing. A caller wanting
                            *   only the depth may discard it; a caller wanting to know WHICH
                            *   alignments survived has no other way to learn it. */
    size_t survivors_length; /**< How many. Must reach the alignment count or the call is refused. */
    size_t sample_stride;  /**< Plan on every Nth alignment. Zero is read as one. */
    int force_full_depth;  /**< Non-zero descends every level, ignoring the destroy rule. */
    const AnchorField *any; /**< A field of any symbol type [BORROWS]. Null takes the byte path. */
    int resume;            /**< Non-zero starts the descent from the survivors already in the buffer
                            *   instead of resetting them to all standing, which is how a caller
                            *   composes a recursive spawn: descend, then descend again over the
                            *   survivors the last descent left, so each child reads only what its
                            *   parent kept standing. Zero, the default, resets the buffer and is what
                            *   every existing caller gets. The engine does not check the incoming set
                            *   is a valid superset; that is the caller's, and a lone survivor is
                            *   verified against the conditions not yet asked before it is found. */
} AnchorSteerDescent;

/**
 * @brief Calls an entry with its arguments built at the call site.
 *
 * @param entry_ The entry to call.
 * @param type_  Its argument structure.
 * @note The literal has automatic storage and lives for the whole call. Every member the caller does
 *       not name is zero, which is the contract each structure above states. `__VA_ARGS__` is
 *       mentioned once, so an argument carrying a side effect is evaluated once.
 */
#define ANCHOR_STEER_CALL(entry_, type_, ...) entry_(&(type_){__VA_ARGS__})

/**
 * @brief Orders the anchors by conditional pruning, one level per anchor, and reports the depth.
 *
 * @warning THIS REORDERS OFFSETS THE CALLER HAS ALREADY PLACED. IT DOES NOT CHOOSE THEM. `offsets`
 *          is read on the way in, so a caller who leaves the array uninitialized expecting the
 *          descent to fill it gets whatever was in that memory ranked, and gets it silently.
 *          anchor_steer_spawn_coarms is the entry that chooses the positions itself.
 * @warning `count` ABOVE ANCHOR_STEER_ANCHORS RETURNS ZERO AND SAYS NOTHING. That is the whole
 *          report: zero is also what a null pointer and a zero needle length return, so a caller
 *          reading the return value alone cannot tell which guard refused. Check the bound before
 *          the call, because the call will not tell you.
 *
 * @param[in,out] offsets       Anchor offsets, reordered in place into evaluation order [BORROWS].
 * @param[in]     count         How many offsets. At most ANCHOR_STEER_ANCHORS.
 * @param[in]     corpus        Bytes the search will run over [BORROWS].
 * @param[in]     corpus_len    How many.
 * @param[in]     needle        Bytes to find [BORROWS].
 * @param[in]     needle_len    How many.
 * @param[in]     sample_stride Plan on every Nth alignment. 1 reads them all. 0 is treated as 1.
 * @return                      Levels actually descended, which is AT MOST `count` and is fewer
 *                              when the destroy rule ends the descent early. `count` on a valid call
 *                              is the ceiling the depth cannot exceed. Read the return to learn the
 *                              depth reached, and see the note below on `force_full_depth`.
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
 *   - the depth is AT MOST `count`, which is bounded by ANCHOR_STEER_ANCHORS, a compile-time
 *     constant, and the loop cannot run past it whatever the corpus holds
 *
 * So the depth is bounded from ABOVE before the program runs, and that bound is what terminates it:
 * a strictly shrinking unplaced set under a constant ceiling, the way a `for` loop over a fixed
 * array does. There is no runtime guard, no iteration cap and no watchdog, because a bound enforced
 * at compile time does not need one.
 *
 * THE DEPTH IS NOT FIXED, THOUGH, AND AN EARLIER FORM OF THIS LIST SAID IT WAS. It read "no branch
 * anywhere in the descent depends on corpus content for its DEPTH, only for its choice at a level",
 * which is false unless `force_full_depth` is set. The destroy test reads a survivor count off the
 * corpus and breaks, so the field routinely ends the descent early, and an omitted member is zero so
 * that is the default path. Depth is a truthy and falsy steer bounded above by a constant, and the
 * return value exists so a caller can read the depth actually reached rather than assume `count`.
 *
 * @note THE PLANNER IS ALLOWED TO BE WRONG. Ordering cannot change which alignments survive, since
 *       an alignment survives only when every anchor agrees and a conjunction is order independent.
 *       So a planner that samples, guesses badly, or is outright defective costs speed and cannot
 *       cost correctness. That is what makes `sample_stride` safe: planning on a subset risks a
 *       worse order and never a wrong count.
 * @note Does nothing and returns 0 where any pointer is null, where `count` is zero, or where
 *       `needle_len` is zero. A zero length needle has no symbol to rank.
 */
size_t anchor_steer_plan_recursive(const AnchorSteerDescent *args);

/**
 * @brief Spawns coarms at the positions that prune most, one per level, and places them in order.
 *
 * @param[out] offsets          Where the chosen offsets are written, in evaluation order [BORROWS].
 * @param[in]  wanted           How many coarms to spawn. At most ANCHOR_STEER_ANCHORS.
 * @param[in]  corpus           Bytes the search will run over [BORROWS].
 * @param[in]  corpus_len       How many.
 * @param[in]  needle           Bytes to find [BORROWS].
 * @param[in]  needle_len       How many.
 * @param[out] survivors        Which alignments the probes left standing, one byte each [BORROWS].
 * @param[in]  survivors_length How many. Must reach the alignment count.
 * @param[in]  sample_stride    Plan on every Nth alignment. 1 reads them all. 0 is treated as 1.
 * @return                      Coarms actually placed, which is AT MOST `wanted` and is fewer when
 *                              the destroy rule ends the descent early. `wanted` on a valid call is
 *                              the ceiling the count cannot exceed. Read the return to learn how many
 *                              were placed, and size any read of `offsets` by the return itself.
 *
 * SPAWNING RATHER THAN REORDERING. anchor_steer_plan_recursive takes anchors somebody else placed
 * and decides the order to test them in. This decides WHERE THEY GO. At each level it asks every
 * position in the needle how many of the currently surviving alignments would still stand if a
 * coarm were placed there, and puts one at the position that leaves fewest. The arm is spawned at
 * the place the field says is worth reading, rather than at a place a spread rule chose before the
 * field was looked at.
 *
 * That is the same steering the rest of this file applies, moved from the order to the placement.
 * The spread rule above answers "where, knowing nothing" and this answers "where, given the corpus
 * and given what the coarms already placed have ruled out".
 *
 * THIS DESCENT IS GREEDY COVERAGE MAXIMIZATION AND CARRIES ITS GUARANTEE. Each probe rejects a
 * definite set of alignments, and the alignments a probe SET rejects is the union of those sets.
 * A union of sets is monotone and submodular, because an alignment already rejected contributes
 * nothing when rejected again. Choosing the candidate that leaves fewest survivors is choosing the
 * largest marginal gain on that union. By Nemhauser, Wolsey and Fisher 1978, greedy maximization of
 * a monotone submodular function under a cardinality constraint reaches at least 1 - 1/e of the best
 * set of the same size, so the probes placed here reject at least about 63 percent of what the
 * optimal `wanted` probes would reject.
 *
 * @warning THE GUARANTEE IS ON ALIGNMENTS REJECTED AND NOT ON READS. Rejecting an alignment early
 *          saves the reads a later probe would spend on it, so two probe sets covering the same
 *          alignments can cost different numbers of reads. It also assumes marginal gains are
 *          scored exactly, which holds only at `sample_stride` of one. Above one the scoring is
 *          taken on a sample, the oracle is approximate, and the ratio no longer holds as stated.
 *
 * TERMINATION IS A BOUND FROM ABOVE AND NOT A FIXED DEPTH. One coarm per level, a placed position
 * never reconsidered, and depth AT MOST `wanted`, which the guard holds at or under
 * ANCHOR_STEER_ANCHORS. The loop cannot run longer than that whatever the corpus holds, which is
 * what makes it terminate.
 *
 * IT CAN RUN SHORTER, AND CORPUS CONTENT IS WHAT DECIDES. The destroy test compares the best
 * candidate's surviving population against the current one, and that count is read off the corpus.
 * Where nothing prunes, the descent breaks early. `force_full_depth` exists precisely to override
 * that, and an omitted member is zero, so the DEFAULT path is the one where the field ends the
 * descent. bench_sigma measures it: with `wanted` fixed at 4 on every row, `placed` comes back 2 at
 * an alphabet of 2^8 and 1 from 2^16 up, because a larger alphabet lets the first probe cut far
 * enough that a second buys nothing.
 *
 * An earlier form of this block said "nothing in the descent lets corpus content change the DEPTH".
 * That is true only under `force_full_depth`, it was written as though it were unconditional, and it
 * contradicted the comment at the break site in the same tree. Depth is a truthy and falsy steer
 * like everything else here, bounded above by a constant and free to come in under it.
 *
 * The return value is there so a caller can read the depth actually reached rather than assume
 * `wanted`, which matters more now that the two can differ.
 *
 * @note FAILS CLOSED ON THE SURVIVOR BUFFER. Returns 0 without writing `offsets` where
 *       `survivors_length` does not reach the alignment count. The kernel allocates nothing, so the
 *       buffer is the caller's and a buffer too small is refused rather than worked around. Size it
 *       at `corpus_len - needle_len + 1`.
 * @note A planner is free to be wrong here for the same reason it is free to be wrong anywhere else
 *       in this file: placement and order change which probe rejects first, never which alignments
 *       survive. The verification is a full compare either way.
 * @warning Costs `wanted * needle_len * alignments / sample_stride` byte comparisons to plan. On a
 *          long needle that exceeds the scan it is planning for. `sample_stride` is the control,
 *          and test_steer measures where the trade turns over rather than asserting a default.
 */
size_t anchor_steer_spawn_coarms(const AnchorSteerDescent *args);

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
 * @brief What the probe sweep reads, as one argument.
 *
 * @note Separate from AnchorSteerDescent because it writes probes and not offsets, and carries a
 *       length ceiling the offset descents have no use for. Sharing one struct would put a member
 *       in it that half the callers must leave zero and the other half must set.
 * @note Declared here and not beside AnchorSteerDescent because it holds an AnchorProbe, which is
 *       declared just above. A structure cannot name a type the compiler has not seen.
 * @note An omitted member is zero, as it is for AnchorSteerDescent. `sample_stride` of zero is read
 *       as one, and `max_length` of zero is refused rather than read as one, because a sweep that
 *       considers no probe shape is a caller error and not a default worth inventing.
 */
typedef struct
{
    AnchorProbe *probes;   /**< Where the chosen probes are written [BORROWS]. */
    size_t count;          /**< Probes to place. At most ANCHOR_STEER_ANCHORS. */
    const uint8_t *corpus; /**< Bytes the search will run over [BORROWS]. */
    size_t corpus_len;     /**< How many. */
    const uint8_t *needle; /**< Bytes to find [BORROWS]. */
    size_t needle_len;     /**< How many. */
    size_t max_length;     /**< Longest eye to consider. One restricts the sweep to arms. */
    uint8_t *survivors;    /**< One byte per alignment, written during the call [BORROWS]. THE
                            *   SWEEP'S OUTPUT AND NOT A TEMPORARY, exactly as it is for
                            *   AnchorSteerDescent: it records which alignments the probes left
                            *   standing. */
    size_t survivors_length; /**< How many. Must reach the alignment count or the call is refused. */
    size_t sample_stride;  /**< Plan on every Nth alignment. Zero is read as one. */
} AnchorSteerSweep;

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
 * @param[out] probes           Where the chosen probes are written, in evaluation order [BORROWS].
 * @param[in]  wanted           How many to spawn. At most ANCHOR_STEER_ANCHORS.
 * @param[in]  corpus           Bytes the search will run over [BORROWS].
 * @param[in]  corpus_len       How many.
 * @param[in]  needle           Bytes to find [BORROWS].
 * @param[in]  needle_len       How many.
 * @param[in]  max_length       Longest eye to consider. One restricts the sweep to arms.
 * @param[out] survivors        Which alignments the probes left standing, one byte each [BORROWS].
 * @param[in]  survivors_length How many. Must reach the alignment count.
 * @param[in]  sample_stride    Plan on every Nth alignment. 1 reads them all. 0 is treated as 1.
 * @return                      Probes actually placed.
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
 * against an arm has to compare READS and not survivors. test_steer does exactly that and reports
 * both, which is why the guide recommends measuring rather than reaching for the longest eye.
 *
 * TERMINATION, unchanged and for the same reason. One probe per level, `wanted` levels, bounded by
 * ANCHOR_STEER_ANCHORS at compile time. The sweep inside a level is three nested bounded loops over
 * needle_len, needle_len and max_length. Nothing in it is data dependent in its EXTENT.
 *
 * @note Every shape the sweep can spawn leaves the count unchanged, so the whole sweep moves inside
 *       the null group and can be as wrong as it likes without costing an answer.
 * @note Fails closed on the survivor buffer exactly as anchor_steer_spawn_coarms does.
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
size_t anchor_steer_sweep_probes(const AnchorSteerSweep *args);

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
 *          no symbol to probe and no offset that indexes one. That matches the reference engine,
 *          which reports an empty needle as occurring at every alignment.
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



/* ---- the scan: the engine interface, the shared counters, the dispatch, one arm per set ---- */


/**
 * @brief One implementation of the steering scan.
 *
 * @note `count` takes the corpus, the alignment count, the survivor flags, the needle byte being
 *       tested and the offset it sits at, and returns how many still-standing alignments agree.
 *       That is the whole operation a planner asks of a scan engine.
 */
typedef struct
{
    const char *name; /**< What to print in a row. Never null. */
    size_t (*count)(const uint8_t *corpus, size_t alignments, const uint8_t *alive, uint8_t wanted,
                    size_t offset);
} AnchorSteerEngine;

/**
 * @brief Scans served by any engine since the last reset.
 *
 * A CORRECTNESS SUITE CANNOT DETECT AN UNUSED IMPLEMENTATION. An engine that is compiled, graded
 * and never called produces no wrong answer, so every count stays identical and every test keeps
 * passing. That is not a hypothetical: the AVX2 engine here was built, graded against portable and
 * benched at 33 times its rate while the planner went on running its own scalar loop, and nothing in
 * the suite said so.
 *
 * These two counters make the wiring assertable. The claim is not that the engines agree, which the
 * differential already covers, but that the engine the machine carries actually RAN. A test reads
 * them after a planner run and requires the wide count to be non-zero wherever a wide engine
 * reports itself present.
 */
extern uint64_t anchor_steer_scan_calls;

/** @brief Scans served by a vectorized engine since the last reset. */
extern uint64_t anchor_steer_wide_calls;

/** @brief Sets both scan counters to zero. */
void anchor_steer_scan_counters_reset(void);

/**
 * @brief The widest engine this machine carries, which is what the planner calls.
 *
 * @return The engine. Never null, since the portable one is always present.
 * @note Resolved on every call. A caller in a hot path holds the result rather than asking again,
 *       because the processor query costs more than a scan does.
 */
const AnchorSteerEngine *anchor_steer_best_engine(void);

/**
 * @brief The portable C11 engine, the reference every other engine is graded against.
 *
 * @return A pointer to the engine. Never null, since it runs anywhere a C11 compiler built it.
 */
const AnchorSteerEngine *anchor_steer_portable_engine(void);

/**
 * @brief The scan in portable C11.
 *
 * @param[in] corpus     Bytes under examination [BORROWS].
 * @param[in] alignments How many alignments the object has.
 * @param[in] alive      One flag per alignment, non-zero where still standing [BORROWS].
 * @param[in] wanted     The needle byte being tested.
 * @param[in] offset     Needle offset the probe sits at.
 * @return               How many still-standing alignments agree.
 */
size_t anchor_steer_truthy_after_portable(const uint8_t *corpus, size_t alignments,
                                          const uint8_t *alive, uint8_t wanted, size_t offset);

#if defined(ANCHOR_STEER_HAVE_AVX2) && ANCHOR_STEER_HAVE_AVX2

/**
 * @brief The AVX2 engine, answering thirty-two alignments per compare.
 *
 * @return A pointer to the engine, or NULL where this processor does not carry AVX2.
 * @note Asks the processor instead of trusting the build.
 */
const AnchorSteerEngine *anchor_steer_avx2_engine(void);

/** @brief The scan under AVX2. Same contract as the portable one, same count. */
size_t anchor_steer_truthy_after_avx2(const uint8_t *corpus, size_t alignments,
                                      const uint8_t *alive, uint8_t wanted, size_t offset);

#endif

#if defined(ANCHOR_STEER_HAVE_AVX512) && ANCHOR_STEER_HAVE_AVX512

/**
 * @brief The AVX-512 engine, answering sixty-four alignments per compare.
 *
 * @return A pointer to the engine, or NULL where this processor does not carry AVX-512.
 * @note Asks the processor instead of trusting the build. No machine here runs it, so the name it
 *       carries reads avx512-unrun.
 */
const AnchorSteerEngine *anchor_steer_avx512_engine(void);

/** @brief The scan under AVX-512. Same contract as the portable one, same count. */
size_t anchor_steer_truthy_after_avx512(const uint8_t *corpus, size_t alignments,
                                        const uint8_t *alive, uint8_t wanted, size_t offset);

#endif

#if defined(ANCHOR_STEER_HAVE_NEON) && ANCHOR_STEER_HAVE_NEON

/**
 * @brief The NEON engine, answering sixteen alignments per compare.
 *
 * @return A pointer to the engine. Never null on a build that reached it, since NEON is part of the
 *         base aarch64 architecture.
 */
const AnchorSteerEngine *anchor_steer_neon_engine(void);

/** @brief The scan under NEON. Same contract as the portable one, same count. */
size_t anchor_steer_truthy_after_neon(const uint8_t *corpus, size_t alignments,
                                      const uint8_t *alive, uint8_t wanted, size_t offset);

#endif

#if defined(ANCHOR_STEER_HAVE_SVE) && ANCHOR_STEER_HAVE_SVE

/**
 * @brief The SVE engine, answering a vector's worth of alignments per compare.
 *
 * @return A pointer to the engine, or NULL where the kernel does not report SVE. No machine here
 *         runs it, so the name it carries reads sve-unrun.
 * @note Detection reads the kernel capability word, since ARM has no cpuid.
 */
const AnchorSteerEngine *anchor_steer_sve_engine(void);

/** @brief The scan under SVE. Same contract as the portable one, same count. */
size_t anchor_steer_truthy_after_sve(const uint8_t *corpus, size_t alignments,
                                     const uint8_t *alive, uint8_t wanted, size_t offset);

#endif

#if defined(ANCHOR_STEER_HAVE_CUDA) && ANCHOR_STEER_HAVE_CUDA

/**
 * @brief Whether a usable CUDA device is present.
 *
 * @return 1 where at least one device answered, 0 otherwise.
 * @note Asked at run time. A binary built with CUDA still runs on a machine with no device, and the
 *       arm reports itself absent there instead of failing inside a launch.
 */
int anchor_steer_cuda_available(void);

/**
 * @brief The name and compute capability of the device this arm would use.
 *
 * @param[out] text Where the description is written [BORROWS].
 * @param[in]  room How many bytes `text` holds.
 * @return          1 where a description was written, 0 where no device answered.
 */
int anchor_steer_cuda_describe(char *text, size_t room);

/**
 * @brief The CUDA engine, one alignment per thread over the whole object.
 *
 * @return A pointer to the engine, or NULL where no device answered.
 * @note Not in anchor_steer_best_engine. The scan is called once per candidate in a descent and the
 *       survivor vector changes each level, so a per-call host to device copy would cost more than
 *       the scan saves on all but the largest objects. The arm is graded against portable and timed
 *       by the GPU build, and a caller that has already put the object on the device calls it
 *       directly.
 */
const AnchorSteerEngine *anchor_steer_cuda_engine(void);

/**
 * @brief The scan on a CUDA device. Same contract as the portable one, same count.
 *
 * @note Falls back to a host count where the device refuses the work, so a driver comparing arms
 *       reads a count and never a sentinel it would misread as a disagreement.
 */
size_t anchor_steer_truthy_after_cuda(const uint8_t *corpus, size_t alignments,
                                      const uint8_t *alive, uint8_t wanted, size_t offset);

#endif

#ifdef __cplusplus
}
#endif

#endif /* ANCHOR_SIFT_H */
