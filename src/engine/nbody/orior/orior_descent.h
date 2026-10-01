
// orior_descent.h: descent, the recursive plan, probes and counting (orior.h includes the parts in order)
#ifndef ORIOR_DESCENT_H
#define ORIOR_DESCENT_H

#include "orior_field.h"

#ifdef __cplusplus
extern "C"
{
#endif

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
     *       path, and `resume` of zero resets the survivors to all standing. A caller that omits all four
     *       gets the full sweep, the destroy rule, bytes, and a fresh survivor set, as almost every
     *       caller wants.
     *
     * ANY SYMBOL TYPE, THROUGH `any`. Set it and the engine reads the field only through an equality
     * oracle, never touching `corpus` or `needle`. That is not a convenience wrapper over the byte path;
     * it is the path the theory describes, and the byte members are the specialization. Soundness uses
     * equality alone and reads no order, no dimension and no alphabet. An engine that demands a
     * `uint8_t *` is narrower than its own proof. The byte path stays because it is faster and because
     * every existing caller passes bytes.
     *
     * WHAT `force_full_depth` EXISTS TO MAKE TESTABLE. The descent normally stops at a level whose best
     * candidate leaves the truthy population unchanged, and destroys every level below it. Stopping and
     * continuing are therefore claimed to be equivalent, and this member lets a caller check the claim
     * instead of believing it. Set it, and THE COUNT PRODUCED BY THE RESULTING PROBE SET MUST BE
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
        size_t *offsets;         /**< Where the chosen offsets are written [BORROWS]. */
        size_t count;            /**< Offsets to place. At most ANCHOR_STEER_ANCHORS. */
        const uint8_t *corpus;   /**< Bytes the search will run over [BORROWS]. Unread where `any` is set. */
        size_t corpus_len;       /**< How many. Unread where `any` is set. */
        const uint8_t *needle;   /**< Bytes to find [BORROWS]. Unread where `any` is set. */
        size_t needle_len;       /**< How many. Unread where `any` is set. */
        uint8_t *survivors;      /**< One byte per alignment, written during the call [BORROWS]. THE
                                  *   DESCENT'S OUTPUT AND NOT A TEMPORARY: it records, per alignment,
                                  *   whether the probes left that alignment standing. A caller wanting
                                  *   only the depth may discard it; a caller wanting to know WHICH
                                  *   alignments survived has no other way to learn it. */
        size_t survivors_length; /**< How many. Must reach the alignment count or the call errors. */
        size_t sample_stride;    /**< Plan on every Nth alignment. Zero is read as one. */
        int force_full_depth;    /**< Non-zero descends every level, ignoring the destroy rule. */
        const AnchorField *any;  /**< A field of any symbol type [BORROWS]. Null takes the byte path. */
        int resume;              /**< Non-zero starts the descent from the survivors already in the buffer
                                  *   instead of resetting them to all standing. A caller uses it to
                                  *   compose a recursive spawn: descend, then descend again over the
                                  *   survivors the last descent left. Each child reads only what its
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
 *       not name is zero, the contract each structure above states. `__VA_ARGS__` is
 *       mentioned once. An argument carrying a side effect is evaluated once.
 */
#define ANCHOR_STEER_CALL(entry_, type_, ...) entry_(&(type_){__VA_ARGS__})

    /**
     * @brief Orders the anchors by conditional pruning, one level per anchor, and reports the depth.
     *
     * @warning THIS REORDERS OFFSETS THE CALLER HAS ALREADY PLACED. IT DOES NOT CHOOSE THEM. `offsets`
     *          is read on the way in. A caller who leaves the array uninitialized expecting the
     *          descent to fill it gets whatever was in that memory ranked, and gets it silently.
     *          anchor_steer_spawn_coarms is the entry that chooses the positions itself.
     * @warning `count` ABOVE ANCHOR_STEER_ANCHORS RETURNS ZERO AND SAYS NOTHING. The zero is the
     *          only report: zero is also what a null pointer and a zero needle length return. A caller
     *          reading the return value alone cannot tell which guard errored. Check the bound before
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
     * This ranks each level against the alignments that actually survived the levels above it: the
     * CONDITIONAL distribution and not the marginal one. It also measures survivors directly
     * instead of inferring them from symbol frequency. Correlation between positions is accounted
     * for and not assumed away.
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
     * corpus and breaks. The field routinely ends the descent early, and an omitted member is zero so
     * that is the default path. Depth is a truthy and falsy steer bounded above by a constant, and the
     * return value exists for a caller to read the depth actually reached instead of assuming `count`.
     *
     * @note THE PLANNER IS ALLOWED TO BE WRONG. Ordering cannot change which alignments survive, since
     *       an alignment survives only when every anchor agrees and a conjunction is order independent.
     *       A planner that samples, guesses badly, or is outright defective therefore costs speed and
     *       cannot cost correctness, and `sample_stride` is safe for the same reason: planning on a subset risks a
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
     * SPAWNING. anchor_steer_plan_recursive takes anchors somebody else placed
     * and decides the order to test them in. This decides WHERE THEY GO. At each level it asks every
     * position in the needle how many of the currently surviving alignments would still stand if a
     * coarm were placed there, and puts one at the position that leaves fewest. The arm is spawned at
     * the place the field says is worth reading, and not at a place a spread rule chose before the
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
     * set of the same size. The probes placed here reject at least about 63 percent of what the
     * optimal `wanted` probes would reject.
     *
     * @warning THE GUARANTEE IS ON ALIGNMENTS REJECTED AND NOT ON READS. Rejecting an alignment early
     *          saves the reads a later probe would spend on it. Two probe sets covering the same
     *          alignments can cost different numbers of reads. It alassumes marginal gains are
     *          scored exactly, which holds only at `sample_stride` of one. Above one the scoring is
     *          taken on a sample, the oracle is approximate, and the ratio no longer holds as stated.
     *
     * TERMINATION IS A BOUND FROM ABOVE AND NOT A FIXED DEPTH. One coarm per level, a placed position
     * never reconsidered, and depth AT MOST `wanted`, which the guard holds at or under
     * ANCHOR_STEER_ANCHORS. The loop cannot run longer than that whatever the corpus holds, and
     * it therefore terminates.
     *
     * IT CAN RUN SHORTER, AND CORPUS CONTENT DECIDES WHEN. The destroy test compares the best
     * candidate's surviving population against the current one, and that count is read off the corpus.
     * Where nothing prunes, the descent breaks early. `force_full_depth` exists precisely to override
     * that, and an omitted member is zero. On the DEFAULT path the field ends the
     * descent. bench_sigma measures it: with `wanted` fixed at 4 on every row, `placed` comes back 2 at
     * an alphabet of 2^8 and 1 from 2^16 up, because a larger alphabet lets the first probe cut far
     * enough that a second buys nothing.
     *
     * Depth is a truthy and falsy steer like everything else here, bounded above by a constant and
     * free to come in under it.
     *
     * The return value is there for a caller to read the depth actually reached instead of assuming
     * `wanted`, which matters where the two can differ.
     *
     * @note FAILS CLOSED ON THE SURVIVOR BUFFER. Returns 0 without writing `offsets` where
     *       `survivors_length` does not reach the alignment count. The kernel allocates nothing. The
     *       buffer is the caller's and a buffer too small errors and not worked around. Size it
     *       at `corpus_len - needle_len + 1`.
     * @note A planner is free to be wrong here for the same reason it is free to be wrong anywhere else
     *       in this file: placement and order change which probe rejects first, never which alignments
     *       survive. The verification is a full compare either way.
     * @warning Costs `wanted * needle_len * alignments / sample_stride` byte comparisons to plan. On a
     *          long needle that exceeds the scan it is planning for. `sample_stride` is the control,
     *          and test_steer measures where the trade turns over instead of asserting a default.
     */
    size_t anchor_steer_spawn_coarms(const AnchorSteerDescent *args);

    /**
     * @brief One probe placed on the needle. An arm is a point, an eye is a line.
     *
     * ONE SHAPE SERVES BOTH, the SAME STATEMENT arm-records.md MAKES ABOUT READINGS. An arm is
     * a region integral and an eye is a line integral, and the difference between them lives in the
     * shape of the support, not in the arithmetic applied to it. Here that means an arm is an eye whose
     * length is one, and the same test walks both.
     *
     * @note `step` is unread at `length` one, and makes a longer probe a LINE through the
     *       needle and not a run of adjacent bytes. A step that shares a period with the needle
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
     *       as one, and `max_length` of zero errors and not read as one, because a sweep that
     *       considers no probe shape is a caller error and not a default worth inventing.
     */
    typedef struct
    {
        AnchorProbe *probes;     /**< Where the chosen probes are written [BORROWS]. */
        size_t count;            /**< Probes to place. At most ANCHOR_STEER_ANCHORS. */
        const uint8_t *corpus;   /**< Bytes the search will run over [BORROWS]. */
        size_t corpus_len;       /**< How many. */
        const uint8_t *needle;   /**< Bytes to find [BORROWS]. */
        size_t needle_len;       /**< How many. */
        size_t max_length;       /**< Longest eye to consider. One restricts the sweep to arms. */
        uint8_t *survivors;      /**< One byte per alignment, written during the call [BORROWS]. THE
                                  *   SWEEP'S OUTPUT AND NOT A TEMPORARY, exactly as it is for
                                  *   AnchorSteerDescent: it records which alignments the probes left
                                  *   standing. */
        size_t survivors_length; /**< How many. Must reach the alignment count or the call errors. */
        size_t sample_stride;    /**< Plan on every Nth alignment. Zero is read as one. */
    } AnchorSteerSweep;

    /**
     * @brief Whether every position a probe reads lands inside the needle.
     *
     * @param[in] probe      Probe to test [BORROWS].
     * @param[in] needle_len Length it must fit inside.
     * @return               1 where it fits, 0 otherwise.
     * @note Computed without forming the last position as a sum. A step and length that would
     *       overflow size_t error instead of wrapping into a position that looks valid.
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
     * where an arm reads one. An eye has to prune more than L times as hard to be worth spawning.
     * The score here is survivors, which does not carry that cost. The caller comparing an eye
     * against an arm has to compare READS and not survivors. test_steer does exactly that and reports
     * both, and the guide recommends measuring instead of reaching for the longest eye.
     *
     * TERMINATION, unchanged and for the same reason. One probe per level, `wanted` levels, bounded by
     * ANCHOR_STEER_ANCHORS at compile time. The sweep inside a level is three nested bounded loops over
     * needle_len, needle_len and max_length. Nothing in it is data dependent in its EXTENT.
     *
     * @note Every shape the sweep can spawn leaves the count unchanged. The whole sweep moves inside
     *       the null group and can be as wrong as it likes without costing an answer.
     * @note Fails closed on the survivor buffer exactly as anchor_steer_spawn_coarms does.
     * @warning The sweep is `wanted * needle_len^2 * max_length^2 * alignments / sample_stride` byte
     *          comparisons at worst. One factor of max_length counts the lengths enumerated. The second
     *          comes from scoring: a candidate of length L costs up to L comparisons, and summing L
     *          from 1 to max_length averages about max_length/2.
     *          anchor_steer_probe_fits rejects shapes that do not fit. The real count sits below
     *          this figure. It is still far more than the scan it plans on any but a tiny needle, and
     *          it is a planner for a search run many times against one needle and not for a
     *          single shot. `sample_stride` makes it affordable.
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
     * @note ONE KERNEL AND ONE FLAG. That the missing term is the only thing that differs between
     *       the two routes. Same offsets, same probe loop, same verification; `steered` decides only
     *       the ORDER the probes are evaluated in. A comparison between two separate implementations
     *       would measure the implementations. This measures the ordering.
     * @note The count is identical for both values of `steered` by construction; no run is
     *       needed to show it. An alignment survives only when every anchor agrees, a conjunction does not
     *       depend on the order of its terms, and the survivor is verified by a full memcmp either way.
     *       The bench grades it at a residual of exactly zero for that reason and not against a
     *       tolerance.
     * @note `anchor_steer_probes` counts the corpus bytes the probes read, which is where the ordering
     *       pays. Reset it before a run and read it after.
     * @warning Delegates to a full compare at `needle_len` zero instead of probing, because there is
     *          no symbol to probe and no offset that indexes one. That matches the reference engine,
     *          which reports an empty needle as occurring at every alignment.
     */
    size_t anchor_steer_count(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                              int steered);

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
     *       probes, the point of a steering engine and is also what makes the guarantee hard
     *       to attack from outside. This takes the probe set as an argument. A caller can hand over
     *       a permutation of one set and check the count is unchanged, hand over a probe built from the
     *       census instead of the needle and watch the count break, or hand over none at all.
     * @note The empty probe set is the identity. Every alignment reaches the full compare, the answer
     *       is exactly right, and the cost is maximal. That is the cheapest total check of the whole
     *       guarantee and it is why `count` of zero is accepted and not errored.
     * @note `anchor_steer_probes` counts the corpus bytes the probes read, as it does for
     *       anchor_steer_count. Reset it before a run and read it after.
     */
    size_t anchor_steer_count_with_probes(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                          size_t needle_len, const AnchorProbe *probes, size_t count);

#ifdef __cplusplus
}
#endif

#endif
