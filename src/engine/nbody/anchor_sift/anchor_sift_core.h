
// anchor_sift_core.h: counters, the sift's engines, plan and run, the census and steering (anchor_sift.h includes the
// parts in order)
#ifndef ANCHOR_SIFT_CORE_H
#define ANCHOR_SIFT_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

/* The dispatch rule reads the field's census directly. The plan carries one. Reading it directly
 * makes the rule exact: the census holds integer counts and the comparison clears its denominators into
 * integers. */

/** @brief Anchors a sift engine places. The cascade depth log2(N)/H2 sits near five on these corpora. */
#define ANCHOR_SIFT_ANCHORS 4u

/**
 * @brief Set to 1 to build the engines with probe and verification counters.
 *
 * @note Both arms of the gate defined. #if always has a value and an unset build is never a
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

/** @brief Distinct values a byte takes, the width of every census below. */
#define ANCHOR_STEER_SYMBOLS 256u

/**
 * @brief Most probes any planner here will place, defined as ANCHOR_SIFT_ANCHORS so the two cannot
 *        drift.
 *
 * @note THIS CONSTANT IS THE TERMINATION ARGUMENT. Every descent below places one probe per level
 *       and never revisits one. The depth is bounded by this value at compile time. It is
 *       declared in the header because it is part of the contract: a
 *       caller sizing a probe array needs it, and a reader asking whether a recursion
 *       terminates should find its bound in the header instead of having to open the source.
 * @note DEFINED FROM ANCHOR_SIFT_ANCHORS, NOT COPIED. Defining one from the other makes the compiler
 *       hold the invariant the termination argument rests on.
 */
#define ANCHOR_STEER_ANCHORS ANCHOR_SIFT_ANCHORS

    /**
     * @brief What one pass over a corpus records about the field it is.
     *
     * @note Only this steers the engine. It is read off the corpus alone, and the steering is therefore
     *       the field's own and not a parameter.
     * @note `total` is the byte count and not the alignment count. A census describes the field, not
     *       the search about to be run over it. It does not know the needle length.
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
    size_t anchor_sift_naive(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len);

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
    size_t anchor_sift_inorder(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len);

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
    size_t anchor_sift_free(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len);

    /**
     * @brief What the dispatcher needs to choose an engine, all of it cheap to obtain.
     *
     * THE FIELD'S CENSUS AND NOT A NUMBER DERIVED FROM IT. The rule this plan feeds asks whether the
     * effective alphabet reaches a share of the symbols actually used, and both quantities come out of
     * one pass over the corpus. Carrying the census means the rule reads them exactly, in integers, and
     * the engine holds no floating point value anywhere.
     *
     * @note `distinct_symbols` IS NOT A FIELD HERE. The census computes that number authoritatively,
     *       and a public structure carrying a second copy lets a caller hand over two values that
     *       disagree with nothing to catch it. An unread field is untidy; a field that can contradict
     *       the truth beside it is a defect waiting for someone to fill in both.
     * @note `needle_len` is carried and not read, and that is a different case. No ceiling on it beats
     *       having none over the values the bench measures. The rule does not consult it. It
     *       duplicates nothing. It stays.
     * @warning `census` is BORROWED for the duration of every call taking this plan. A plan holds a
     *          pointer to it because AnchorFieldCensus is about two kilobytes
     *          and a plan is passed by pointer on a hot path.
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
    size_t anchor_sift_run(const AnchorSiftPlan *plan, const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                           size_t needle_len);

    /**
     * @brief Returns the engine to run for this corpus.
     *
     * @param[in] plan Corpus statistics and the needle length [BORROWS].
     * @return         The engine to call. Never NULL.
     * @note Every engine is sound. The choice costs speed and never correctness. A wrong dispatch is
     *       therefore a performance defect instead of a wrong answer.
     * @note One term, decided by anchor_steer_prefers_free in exact integer arithmetic. A corpus whose
     *       effective alphabet 2^H2 reaches 85 percent of the symbols it uses, a flat corpus, takes the
     *       short circuiting engine, and every other corpus takes the free order one. Since 2^H2 is
     *       total squared over the sum of squared counts, the comparison clears its denominators into
     *       100*total^2 >= 85*distinct*sum(count^2), which holds for the short circuiting engine, and
     *       holds no floating point value anywhere.
     *       Scored against the clock over 42 rows by bench_dispatch: 39 of 42 giving up 9131790 cycles
     *       at a share of 0.035 on x64 MSVC 19.44 Release, and 41 of 42 giving up 86511 at 0.000 under
     *       gcc. A hundredfold gap in cycles between two real runs. The figure belongs to the
     *       toolchain that produced it. Re-run the bench before quoting either.
     * @note THE NEEDLE LENGTH TERM CHANGES NO ANSWER ON THIS DATA. Scoring flatness alone ties this rule
     *       exactly, same rows and same cycles, across all 42. It is kept because a
     *       tunable with no reader is an integration point, and it is named here so nobody concludes
     *       from the code that it is carrying weight. Find a row where it pays or leave it inert.
     * @note The rule is read off the cycle measurements and belongs to the machine that produced them.
     *       Re-run bench_dispatch before trusting it on another part. It sweeps both thresholds instead
     *       of assuming them. What it prints is a recommendation to act on, not a confirmation.
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
     *       and P is count over a shared total. `total - count` orders identically to -log P while
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
     *       four. An insertion sort is fewer instructions than setting up anything cleverer and is
     *       the right choice and not a concession.
     * @note STABLE, and that is load bearing and not incidental. Two anchors testing equally rare
     *       symbols keep the order choose_offsets placed them in. The spatial spread that rule exists
     *       to produce survives wherever rarity does not distinguish. An unstable sort would quietly
     *       discard the spread on a flat corpus, the corpus where the spread is all there is.
     * @note Does nothing where any argument is null, where `count` is zero, or where the census is
     *       empty. An engine with nothing to steer by keeps the order it was given.
     */
    void anchor_steer_probe_order(size_t *offsets, size_t count, const AnchorFieldCensus *census, const uint8_t *needle,
                                  size_t needle_len);

    /**
     * @brief Whether this field wants the free order engine, decided in exact integer arithmetic.
     *
     * @param[in] census Field census [BORROWS].
     * @return           1 for the free order engine, 0 for the short circuiting engine.
     *
     * @note THE SAME RULE THE ENGINE ALREADY SHIPPED, WITH THE FLOATING POINT REMOVED. The rule asks
     *       whether the effective alphabet 2^H2 sits within 85 percent of the symbols actually used.
     *       Writing H2 as the collision entropy, 2^H2 is exactly total^2 over the sum of the squared
     *       counts. The test
     *
     *           total^2 / sum(count^2)  >=  (85/100) * distinct
     *
     *       clears its denominators into
     *
     *           100 * total^2  >=  85 * distinct * sum(count^2)
     *
     *       which is a comparison between two exact integers; where it holds, the corpus is flat and
     *       takes the short circuiting engine (0), and where it fails, the free order engine (1). No
     *       logarithm is taken, no power of two is
     *       approximated by a series, and the threshold is the exact rational 85/100 and not the
     *       nearest double to 0.85.
     * @note Both sides outgrow 64 bits on a corpus of any size, since total^2 passes 2^64 at a four
     *       gigabyte corpus and the sum of squares is accumulated over 256 terms. Both are carried in
     *       AnchorExactInteger for that reason, the fixed width limb form the rest of the
     *       engine already measures in.
     * @note The threshold was swept and not chosen, and the sweep is recorded against the constant
     *       in anchor_sift_core.c. Clearing the denominators does not re-open that: 85/100 is the same value
     *       the sweep scored, carried exactly instead of rounded.
     */
    int anchor_steer_prefers_free(const AnchorFieldCensus *census);

#ifdef __cplusplus
}
#endif

#endif
