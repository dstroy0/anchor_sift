/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_sift.c
 * @brief The engine: search, steering and scan, with no clock and no output in any of them.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-04
 *
 * @note Every engine is sound: a subset of a pattern's points is a necessary condition. None of them
 *       can lose a true occurrence. What differs between them is how much they read and how much of
 *       that reading the machine can overlap.
 */

#include "anchor_sift.h"
#include "exact_integer.h"

#include <string.h>

/* The dispatch rule in anchor_steer_prefers_free compares 100 * total^2 against
 * 85 * distinct * sum(count^2) for a census whose total is a 64 bit count. The right side is below
 * 2^7 * 2^8 * 2^128 = 2^143: 85 is below 2^7, at most 256 symbols are distinct, and a sum of squared
 * counts is at most total^2. The narrowest power of two width holding 143 bits is 256, which is
 * 8 limbs. Narrower, the rule refuses on a large enough corpus, and which engine a corpus is given
 * would change with the width. The engine refuses the width here instead. The exact integer on its
 * own builds and grades down to 1 limb. Written in the three forms exact_integer.h uses for its
 * asserts: static_assert for C++, _Static_assert for C11, and a negative array size before C11. */
#if defined(__cplusplus)
static_assert(ANCHOR_EXACT_BITS >= 256u,
              "the steering rule needs 143 bits; build the engine at 8 exact limbs or more");
#elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)
_Static_assert(ANCHOR_EXACT_BITS >= 256u,
               "the steering rule needs 143 bits; build the engine at 8 exact limbs or more");
#else
typedef char anchor_sift_steering_rule_fits_the_width[(ANCHOR_EXACT_BITS >= 256u) ? 1 : -1];
#endif

#if ANCHOR_SIFT_COUNT_READS

uint64_t anchor_sift_probes = 0u;
uint64_t anchor_sift_verifications = 0u;

void anchor_sift_counters_reset(void)
{
    anchor_sift_probes = 0u;
    anchor_sift_verifications = 0u;
}

/* One corpus byte read by an anchor probe. */
#define ANCHOR_SIFT_PROBED() (anchor_sift_probes += 1u)
/* A fixed number of probe reads, for the engine that issues all of them whatever any one returns. */
#define ANCHOR_SIFT_PROBED_N(count_) (anchor_sift_probes += (uint64_t)(count_))
/* One exact compare, which reads at most needle_len bytes and usually far fewer, since a memcmp
 * stops at the first difference. The count is therefore a bound on the verification reads and not
 * a measurement of them, and the bench reports it as a bound. */
#define ANCHOR_SIFT_VERIFIED() (anchor_sift_verifications += 1u)

#else

#define ANCHOR_SIFT_PROBED() ((void)0)
#define ANCHOR_SIFT_PROBED_N(count_) ((void)(count_))
#define ANCHOR_SIFT_VERIFIED() ((void)0)

#endif

/**
 * @brief Chooses anchor offsets, one drawn inside each evenly sized cell of the needle.
 *
 * @param[out] offsets    Where the chosen offsets are written [BORROWS].
 * @param[in]  wanted     How many to choose, at least one.
 * @param[in]  needle_len Length of the needle they index.
 * @note One draw per cell keeps the spread and gives the anchor set no period of its own. An even
 *       comb shares a period with whatever the domain carries, the failure this avoids.
 * @warning A needle of length zero has no in-range offset to choose. The clamp below computes
 *          needle_len - 1u, and on size_t that wraps to SIZE_MAX instead of saturating. Every
 *          offset lands far outside both the corpus and the needle. The engines answer length zero
 *          before reaching here; this bounds it at the declaration as well, because the engines are
 *          exported and the clamp reads exactly like the guard that would have prevented it.
 */
static void choose_offsets(size_t *offsets, size_t wanted, size_t needle_len)
{
    if (needle_len == 0u)
    {
        for (size_t slot = 0u; slot < wanted; slot += 1u)
        {
            offsets[slot] = 0u;
        }
        return;
    }

    const size_t cell = needle_len / wanted;

    for (size_t slot = 0u; slot < wanted; slot += 1u)
    {
        const size_t inside = (cell > 1u) ? ((slot * 7u) % cell) : 0u;
        offsets[slot] = (slot * cell) + inside;
        if (offsets[slot] >= needle_len)
        {
            offsets[slot] = needle_len - 1u;
        }
    }
}

size_t anchor_sift_naive(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                         size_t needle_len)
{
    size_t found = 0u;

    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        ANCHOR_SIFT_VERIFIED();
        if (memcmp(corpus + at, needle, needle_len) == 0)
        {
            found += 1u;
        }
    }
    return found;
}

/**
 * @brief The in order engine with the anchor count supplied.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @param[in] anchors    How many anchors to place, at least one and at most ANCHOR_SIFT_ANCHORS.
 * @return               How many alignments match exactly.
 * @note Only this engine takes a count. The free order engine's advantage is that its comparisons
 *       are written out and fold into one value with one branch behind them, and a loop over a
 *       runtime count gives that back. A corpus whose count wants reducing is a coherent one, and
 *       a coherent corpus dispatches here anyway.
 * @note A needle of length zero occurs at every alignment, which is exactly what the naive engine
 *       returns. That case is handed to it. An anchor
 *       cannot be placed in a needle with no bytes, and bounding the offsets is not enough on its
 *       own: at length zero the alignment loop runs one further than the corpus. The last
 *       alignment reads one past its end, and the anchor reads element zero of a needle that has
 *       none. Both are reads outside memory the caller owns.
 */
static size_t sift_inorder_n(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                             size_t needle_len, size_t anchors)
{
    if (needle_len == 0u)
    {
        return anchor_sift_naive(corpus, corpus_len, needle, needle_len);
    }

    size_t offsets[ANCHOR_SIFT_ANCHORS];
    size_t found = 0u;

    choose_offsets(offsets, anchors, needle_len);

    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        size_t slot = 0u;
        while (slot < anchors)
        {
            ANCHOR_SIFT_PROBED();
            if (corpus[at + offsets[slot]] != needle[offsets[slot]])
            {
                break;
            }
            slot += 1u;
        }
        if (slot == anchors)
        {
            ANCHOR_SIFT_VERIFIED();
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    return found;
}

size_t anchor_sift_inorder(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                           size_t needle_len)
{
    return sift_inorder_n(corpus, corpus_len, needle, needle_len, ANCHOR_SIFT_ANCHORS);
}

size_t anchor_sift_free(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                        size_t needle_len)
{
    // Length zero goes to the naive engine, for the reason recorded on sift_inorder_n. This engine
    // carries the test separately because it is exported and a caller reaches it without passing
    // through the dispatcher. It is also the engine where bounding the offsets alone would not have
    // been enough: the read below happens before the alignment loop. A zeroed offset still
    // takes element zero of a needle that has none.
    if (needle_len == 0u)
    {
        return anchor_sift_naive(corpus, corpus_len, needle, needle_len);
    }

    size_t offsets[ANCHOR_SIFT_ANCHORS];
    uint8_t wanted[ANCHOR_SIFT_ANCHORS];
    size_t found = 0u;

    choose_offsets(offsets, ANCHOR_SIFT_ANCHORS, needle_len);
    for (size_t slot = 0u; slot < ANCHOR_SIFT_ANCHORS; slot += 1u)
    {
        wanted[slot] = needle[offsets[slot]];
    }

    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        // No short circuit. Four loads issue together, the comparisons fold into one value, and the
        // branch is taken once. This is the dependency depth two arrangement.
        ANCHOR_SIFT_PROBED_N(ANCHOR_SIFT_ANCHORS);
        const unsigned agree = (unsigned)(corpus[at + offsets[0]] == wanted[0]) &
                               (unsigned)(corpus[at + offsets[1]] == wanted[1]) &
                               (unsigned)(corpus[at + offsets[2]] == wanted[2]) &
                               (unsigned)(corpus[at + offsets[3]] == wanted[3]);
        if (agree != 0u)
        {
            ANCHOR_SIFT_VERIFIED();
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    return found;
}

/* The threshold that used to live here, ANCHOR_SIFT_FLAT_SHARE at 0.85, moved into
 * anchor_steer_prefers_free as the exact rational 85/100 and is gone from this file. It is not left
 * defined and unread: a constant nobody reads is how a rule that has been removed goes on looking
 * like a rule that is still enforced.
 *
 * What it meant is unchanged. It is how close the effective alphabet has to sit to the symbols
 * actually used before a corpus counts as memoryless, and it was swept by bench_dispatch.96 scores identically on the corpora measured, since the
 * three of them read 0.96, 0.33 and 1.00 and nothing sits between. Clearing the denominators did not
 * re-open that sweep; 85/100 is the same value carried exactly instead of rounded. */

AnchorSiftEngine anchor_sift_choose(const AnchorSiftPlan *plan)
{
    // No plan is no statistics, and the engine that needs none is the naive one. BOTH POINTERS ARE
    // TESTED HERE and neither test is delegated to the callee. anchor_steer_prefers_free returns 0
    // on a null census. Delegating would work and would leave this function reading as though it
    // dereferences an unchecked pointer. The next person to read it could not tell it is safe
    // without opening another file.
    if ((plan == NULL) || (plan->census == NULL))
    {
        return anchor_sift_naive;
    }

    // A flat corpus refutes almost every alignment on the first probe. Short circuiting reads one
    // byte where the free order engine reads four. A structured one refutes on the first probe often
    // enough to make the loop trip count vary, and a varying trip count costs a mispredicted branch
    // per alignment. The branchless engine exists to avoid that.
    //
    // THE RULE IS THE SAME ONE AND THE ARITHMETIC IS NOT. It asked whether the effective alphabet
    // 2^H2 reaches ANCHOR_SIFT_FLAT_SHARE of the symbols used, computed by taking a logarithm and
    // approximating a power of two with three terms of a series. That constant no longer exists;
    // it is named here because this paragraph records what was replaced. Writing 2^H2 as total^2
    // over the sum of squared counts clears both denominators and leaves
    //
    //     100 * total^2  >=  85 * distinct * sum(count^2)
    //
    // which is a comparison between two exact integers, carried in the limb form where it outgrows
    // 64 bits. No logarithm is taken, no series is evaluated, and the threshold is the exact
    // rational 85/100 instead of the nearest double to 0.85. anchor_steer_prefers_free holds that
    // comparison and the sweep in test_steer grades it against the double form it replaced.
    return anchor_steer_prefers_free(plan->census) ? anchor_sift_free : anchor_sift_inorder;
}

size_t anchor_sift_anchors_for(const AnchorSiftPlan *plan)
{
    // No plan is no known period, and an unknown period is the case the full anchor set is for.
    // Returning the maximum reads more than a known period would need and can lose nothing.
    if (plan == NULL)
    {
        return ANCHOR_SIFT_ANCHORS;
    }

    // Every anchor after the first tests the congruence the first one already tested. The reads
    // they perform are their only contribution.
    if (plan->period != 0u)
    {
        return 1u;
    }
    return ANCHOR_SIFT_ANCHORS;
}

size_t anchor_sift_run(const AnchorSiftPlan *plan, const uint8_t *corpus, size_t corpus_len,
                       const uint8_t *needle, size_t needle_len)
{
    const AnchorSiftEngine chosen = anchor_sift_choose(plan);

    // Held and dispatched.
    // Reaching the tail on a null plan would have run the in order engine with the full anchor set,
    // the outcome the guard in anchor_sift_choose was added to prevent.
    if (chosen == anchor_sift_naive)
    {
        return anchor_sift_naive(corpus, corpus_len, needle, needle_len);
    }
    if (chosen == anchor_sift_free)
    {
        return anchor_sift_free(corpus, corpus_len, needle, needle_len);
    }
    return sift_inorder_n(corpus, corpus_len, needle, needle_len, anchor_sift_anchors_for(plan));
}

const char *anchor_sift_engine_name(AnchorSiftEngine engine)
{
    if (engine == anchor_sift_naive)
    {
        return "naive";
    }
    if (engine == anchor_sift_inorder)
    {
        return "anchor_inorder";
    }
    if (engine == anchor_sift_free)
    {
        return "anchor_free";
    }
    return "unknown";
}

/* ---- the steering, folded in ---- */

void anchor_field_census(const uint8_t *corpus, size_t corpus_len, AnchorFieldCensus *census)
{
    if (census == NULL)
    {
        return;
    }

    memset(census, 0, sizeof(*census));
    if ((corpus == NULL) || (corpus_len == 0u))
    {
        return;
    }

    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        census->occurrences[corpus[at]] += 1u;
    }
    census->total = (uint64_t)corpus_len;

    for (unsigned int symbol = 0u; symbol < ANCHOR_STEER_SYMBOLS; symbol += 1u)
    {
        if (census->occurrences[symbol] != 0u)
        {
            census->distinct += 1u;
        }
    }
}

uint64_t anchor_steer_magnitude(const AnchorFieldCensus *census, uint8_t symbol)
{
    if (census == NULL)
    {
        return 0u;
    }
    return census->total - census->occurrences[symbol];
}

void anchor_steer_probe_order(size_t *offsets, size_t count, const AnchorFieldCensus *census,
                              const uint8_t *needle, size_t needle_len)
{
    if ((offsets == NULL) || (census == NULL) || (needle == NULL) || (count == 0u) || (needle_len == 0u) || (census->total == 0u))
    {
        return;
    }

    // Insertion sort, descending by magnitude, and STABLE. The strict greater-than in the shift
    // test keeps it stable: an equal magnitude does not displace the entry already placed, and
    // anchors testing equally rare symbols keep the spatial spread choose_offsets gave them.
    for (size_t placed = 1u; placed < count; placed += 1u)
    {
        const size_t moving_offset = offsets[placed];
        if (moving_offset >= needle_len)
        {
            continue;
        }
        const uint64_t moving = anchor_steer_magnitude(census, needle[moving_offset]);

        size_t slot = placed;
        while (slot > 0u)
        {
            const size_t settled_offset = offsets[slot - 1u];
            const uint64_t settled = (settled_offset < needle_len)
                                         ? anchor_steer_magnitude(census, needle[settled_offset])
                                         : 0u;
            if (settled > moving)
            {
                break;
            }
            if (settled == moving)
            {
                break;
            }
            offsets[slot] = offsets[slot - 1u];
            slot -= 1u;
        }
        offsets[slot] = moving_offset;
    }
}

/**
 * @brief Loads a 64 bit value into the fixed width limb form.
 *
 * @param[out] value Where the limbs are written [BORROWS].
 * @param[in]  from  The value to carry.
 * @note Base 2^32 least significant limb first, which is what exact_limbs.h declares the layout to
 *       be. Writing the two limbs directly is reading that declaration, not reaching around it;
 *       there is no decimal text here to route through anchor_exact_from_decimal and converting a
 *       counter to text to parse it back would be slower and no more exact.
 * @note limb[1] exists because the assert at the top of this file holds the engine to 8 limbs or
 *       more.
 */
static void steer_exact_from_u64(AnchorExactInteger *value, uint64_t from)
{
    anchor_exact_zero(value);
    if (from == 0u)
    {
        return;
    }
    value->limb[0] = (uint32_t)(from & 0xFFFFFFFFu);
    value->limb[1] = (uint32_t)(from >> 32);
    value->sign = 1;
}

int anchor_steer_prefers_free(const AnchorFieldCensus *census)
{
    if ((census == NULL) || (census->total == 0u) || (census->distinct == 0u))
    {
        // An empty field distinguishes nothing. It takes the short circuiting engine. That is
        // what ran before any of this and it is the cheaper of the two on a field with no
        // structure to exploit.
        return 0;
    }

    // Three integers, each built in place, since every exact operation accepts its result aliasing
    // an input. The six this held before came to 768 KiB at 32768 limbs, and with the multiply's
    // accumulator that passes the 1 MiB stack the MSVC linker gives a main thread.
    AnchorExactInteger left;
    AnchorExactInteger right;
    AnchorExactInteger term;

    // left = 100 * total^2
    steer_exact_from_u64(&left, census->total);
    if (anchor_exact_multiply(&left, &left, &left) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    steer_exact_from_u64(&term, 100u);
    if (anchor_exact_multiply(&left, &term, &left) != ANCHOR_EXACT_OK)
    {
        return 0;
    }

    // right = sum over symbols of count^2, accumulated in the limb form and not in a 64 bit
    // counter. A single count squares to at most total^2, which already passes 2^64 on a four
    // gigabyte corpus, and 256 of them are summed on top of that.
    anchor_exact_zero(&right);
    for (unsigned int symbol = 0u; symbol < ANCHOR_STEER_SYMBOLS; symbol += 1u)
    {
        if (census->occurrences[symbol] == 0u)
        {
            continue;
        }
        steer_exact_from_u64(&term, census->occurrences[symbol]);
        if (anchor_exact_multiply(&term, &term, &term) != ANCHOR_EXACT_OK)
        {
            return 0;
        }
        if (anchor_exact_add(&right, &term, &right) != ANCHOR_EXACT_OK)
        {
            return 0;
        }
    }

    // right = 85 * distinct * right
    steer_exact_from_u64(&term, 85u);
    if (anchor_exact_multiply(&right, &term, &right) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    steer_exact_from_u64(&term, (uint64_t)census->distinct);
    if (anchor_exact_multiply(&right, &term, &right) != ANCHOR_EXACT_OK)
    {
        return 0;
    }

    // The rule reads "flat corpora take the short circuiting engine". The free order one is
    // therefore the branch taken when the effective alphabet does NOT reach the threshold.
    return (anchor_exact_compare(&left, &right) < 0) ? 1 : 0;
}

/* ------------------------------------------------------------------------------------------------
 * Truthy and falsy steering. The signal is the survivor vector, not the symbol histogram.
 *
 * EACH PERMUTATION OF THE ANCHORS IS A NULL, AND EACH NULL IS A STEER. An alignment survives only
 * when every anchor agrees, and a conjunction does not depend on the order of its terms. Every
 * ordering of a given anchor set returns the same count. The orderings therefore form a group of
 * moves that CANNOT change the answer, which is what this tree calls a null. Steering is choosing
 * which element of that group to apply.
 *
 * That is the whole safety argument for everything below, and it is structural. A planner that samples badly, ranks wrongly, or is outright broken still lands on some
 * element of the null group, and every element yields the same count. The planner moves inside the
 * null and the null has one value. Correctness is therefore not something the planner can spend,
 * and speed is the only currency it holds.
 * ---------------------------------------------------------------------------------------------- */

/**
 * @brief How many currently truthy alignments stay truthy when `offset` is tested.
 *
 * @param[in] alive  One flag per alignment, non-zero for truthy [BORROWS].
 * @param[in] stride Sample every Nth alignment. The ranking is a comparison between candidates.
 * @return           Count of survivors, in the sampled population.
 */
static size_t steer_truthy_after(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                 size_t needle_len, const uint8_t *alive, size_t offset,
                                 size_t stride, const AnchorField *any)
{
    // ANY SYMBOL TYPE TAKES THE SCALAR LOOP AND CANNOT TAKE A WIDE ONE. A vectorized scan compares
    // bytes against a broadcast byte, which is a statement about the representation. The oracle is
    // a statement about equality and the engine never learns what it is comparing. There is
    // nothing to broadcast. This path is slower and it is the one the theory describes; the byte
    // path below is the specialization that can be made wide.
    if (any != NULL)
    {
        size_t standing_any = 0u;

        for (size_t at = 0u; at < any->alignments; at += stride)
        {
            if (alive[at] == 0u)
            {
                continue;
            }
            if (any->same(any->field, at + offset, offset) != 0)
            {
                standing_any += 1u;
            }
        }
        return standing_any;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    const uint8_t wanted = needle[offset];

    // THE WIDEST ENGINE THIS MACHINE CARRIES, ASKED ONCE. The scan is where a planner spends its
    // time, and an engine graded against the portable one but never called is a measurement instead
    // of a speedup. The engine is resolved once and held, because asking the processor on every
    // candidate would cost more than the candidates do.
    //
    // Only at stride one. A sampled scan walks every Nth alignment and the engines count every one,
    // so handing a sampled sweep to one would change what is being counted. Sampling falls through
    // to the loop below, the same code the portable engine runs.
    if (stride == 1u)
    {
        // Resolved through anchor_steer_best_engine, which holds the one dispatch every arm is added
        // to. Reproducing the #if ladder here would be a second copy that a new arm could miss, and a
        // scan that keeps running the old widest arm while a wider one reports itself present is
        // exactly the unused-implementation defect the scan counters exist to catch.
        static const AnchorSteerEngine *chosen = NULL;
        static int resolved = 0;
        if (resolved == 0)
        {
            chosen = anchor_steer_best_engine();
            resolved = 1;
        }
        if (chosen != NULL)
        {
            return chosen->count(corpus, alignments, alive, wanted, offset);
        }
    }

    size_t standing = 0u;
    for (size_t at = 0u; at < alignments; at += stride)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (corpus[at + offset] == wanted)
        {
            standing += 1u;
        }
    }
    return standing;
}

/**
 * @brief How many alignments are truthy right now, in the sampled population.
 *
 * @note Sampled at the same stride the candidate scores use. The comparison between "survivors
 *       after this probe" and "survivors before it" is between two counts of the same population.
 *       Mixing a full count with a sampled one would make every probe look like it pruned.
 */
static size_t steer_truthy_total(const uint8_t *alive, size_t alignments, size_t stride)
{
    size_t standing = 0u;

    for (size_t at = 0u; at < alignments; at += stride)
    {
        if (alive[at] != 0u)
        {
            standing += 1u;
        }
    }
    return standing;
}

/**
 * @brief Turns falsy every alignment that disagrees at `offset`, over the whole population.
 *
 * @note Applied at stride one even where the ranking was sampled. The ranking is allowed to be
 *       approximate because it only picks between nulls; the survivor set is not, because the next
 *       level ranks against it and an approximate survivor set would compound.
 */
static void steer_make_falsy(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                             size_t needle_len, uint8_t *alive, size_t offset,
                             const AnchorField *any)
{
    if (any != NULL)
    {
        for (size_t at = 0u; at < any->alignments; at += 1u)
        {
            if (alive[at] == 0u)
            {
                continue;
            }
            if (any->same(any->field, at + offset, offset) == 0)
            {
                alive[at] = 0u;
            }
        }
        return;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    const uint8_t wanted = needle[offset];

    for (size_t at = 0u; at < alignments; at += 1u)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (corpus[at + offset] != wanted)
        {
            alive[at] = 0u;
        }
    }
}

/**
 * @brief Numbers one population into classes and puts those classes in rarity order.
 *
 * @param[in]  same_in_field         Equality between two positions of the population [BORROWS].
 * @param[in]  field                 Passed to the oracle untouched [BORROWS].
 * @param[in]  length                Positions in the population.
 * @param[out] class_of_position     Which class each position fell in [BORROWS].
 * @param[out] members_in_class      How many positions each class holds [BORROWS].
 * @param[out] rarity_place_of_class Where each class sits in the rarity order [BORROWS].
 * @return                           Classes surviving the merges.
 *
 * @note Static and positional, which is where a long parameter list is allowed to live, and the
 *       same shape steer_descend uses for the same reason. The public entries take one const
 *       argument pointer each and both call this.
 * @note THE POPULATION IS THE ARGUMENT. One call numbers one
 *       population. Every rank it produces is comparable with every other rank it produced and
 *       with none produced elsewhere. anchor_field_pair_project hands it a corpus and a needle
 *       together for exactly that reason.
 */
static size_t field_number_classes(AnchorSameAt same_in_field, const void *field, size_t length,
                                   uint32_t *class_of_position, uint32_t *members_in_class,
                                   uint32_t *rarity_place_of_class)
{
    for (size_t at = 0u; at < length; at += 1u)
    {
        class_of_position[at] = (uint32_t)at;
        members_in_class[at] = 0u;
        rarity_place_of_class[at] = 0u;
    }

    // CLASSES ARE CONNECTED COMPONENTS AND NOT FIRST MATCHES, WHICH IS WHAT MAKES THIS SOUND FOR A
    // PREDICATE THAT IS NOT TRANSITIVE. Soundness needs agreement to imply a shared rank. It does
    // NOT need a shared rank to imply agreement. The labelling must be a superset of the
    // relation, and the smallest superset that is an equivalence is the transitive closure.
    //
    // EVERY PAIR, NOT EVERY REPRESENTATIVE. Comparing a position against one member of each class is
    // correct only where agreement is transitive. Over 0 1 2 3 4 at a tolerance of two, position 3
    // agrees with 2 and not with 0. Comparing against class zero's representative opens a second
    // class while 2 and 3 agree, and two agreeing positions in different classes breaks the
    // necessary condition outright. The closure of a graph reachable only through a pairwise probe
    // needs the pairs.
    for (size_t at = 0u; at < length; at += 1u)
    {
        for (size_t before = 0u; before < at; before += 1u)
        {
            size_t mine = at;
            size_t theirs = before;

            while (class_of_position[mine] != mine)
            {
                mine = class_of_position[mine];
            }
            while (class_of_position[theirs] != theirs)
            {
                theirs = class_of_position[theirs];
            }

            // Already one class. The predicate can say nothing new about this pair. The only
            // saving available, and a real one on a chained field.
            if (mine == theirs)
            {
                continue;
            }
            if (same_in_field(field, at, before) == 0)
            {
                continue;
            }
            class_of_position[theirs] = (uint32_t)mine;
        }
    }

    // Resolve every position onto its class, then count the members of each.
    for (size_t at = 0u; at < length; at += 1u)
    {
        size_t root = at;

        while (class_of_position[root] != root)
        {
            root = class_of_position[root];
        }
        class_of_position[at] = (uint32_t)root;
        members_in_class[root] += 1u;
    }

    size_t classes = 0u;
    for (size_t which = 0u; which < length; which += 1u)
    {
        if (members_in_class[which] != 0u)
        {
            classes += 1u;
        }
    }

    // THE CLASS COUNT IS UNBOUNDED AND ONLY THE OUTPUT RANK IS CLAMPED, the whole point of
    // carrying these buffers. Classes are ordered by rarity across every one of them and the clamp
    // is applied at relabel time. A field of a thousand classes keeps its 255 rarest apart and
    // merges the commonest into rank 255.
    //
    // The form this replaced capped the class count during DISCOVERY. The merged set was chosen
    // by arrival order. A class occurring once has one chance to arrive
    // early and a class occurring nine times has nine. The rarest arrived last and were merged
    // first. Two fields with identical frequency multisets and opposite arrangements merged sets
    // whose mean occupancies were 1.06 and 9.00, which no histogram can tell apart. The rarest class
    // is the best probe the steering has. That form spent exactly what the projection exists to
    // find, and worst on the most natural arrangement.
    //
    // A class's place is the number of classes strictly rarer than it, with the class index breaking
    // ties so the order is total and does not depend on the arrangement. THE TIE BREAK IS WHY TWO
    // POPULATIONS CANNOT SHARE AN ORDER: two singletons tie, the index decides, and the indices come
    // from where the positions sat in whichever field was numbered. Number the two together and
    // there is one index space and one answer.
    for (size_t which = 0u; which < length; which += 1u)
    {
        if (members_in_class[which] == 0u)
        {
            continue;
        }

        size_t rarer = 0u;
        for (size_t other = 0u; other < length; other += 1u)
        {
            if (members_in_class[other] == 0u)
            {
                continue;
            }
            if (members_in_class[other] < members_in_class[which])
            {
                rarer += 1u;
            }
            else if ((members_in_class[other] == members_in_class[which]) && (other < which))
            {
                rarer += 1u;
            }
        }
        rarity_place_of_class[which] = (uint32_t)rarer;
    }
    return classes;
}

/**
 * @brief Clamps one class's rarity place into a byte rank.
 *
 * @param[in] place Where the class sits in the rarity order.
 * @return          The place, or 255 where it sits past the last rank a byte can hold.
 *
 * @note Merging costs discrimination and never soundness. One class takes one place across the
 *       whole population. Symbol agreement still implies rank agreement after the clamp, and
 *       that is the direction the filter needs. The alignments a merge admits are rejected by the
 *       full compare.
 */
static uint8_t field_rank_from_place(uint32_t place)
{
    return (uint8_t)((place < 255u) ? place : 255u);
}

int anchor_field_project(const AnchorFieldProjection *args)
{
    if (args == NULL)
    {
        return 0;
    }
    if ((args->same_in_field == NULL) || (args->ranks == NULL) || (args->length == 0u) || (args->class_of_position == NULL) || (args->members_in_class == NULL) || (args->rarity_place_of_class == NULL))
    {
        return 0;
    }

    // Class labels are stored as uint32_t positions. A field wider than that would alias two
    // positions onto one label and merge classes the oracle never joined. It is refused. The cast
    // widens a 32 bit constant into size_t, which holds it on every target this builds for.
    if (args->length > (size_t)UINT32_MAX)
    {
        return 0;
    }

    // FAILS CLOSED ON A SHORT BUFFER. Every position can be its own class. The three arrays have
    // to reach `length` or a field of singletons writes past their end. The previous form capped
    // the arrays, and what that cost is recorded below.
    if (args->classes_length < args->length)
    {
        // WRITES NOTHING, LIKE EVERY OTHER REFUSAL HERE. This path used to set `distinct` to zero
        // while the null and zero-length refusals left it alone, which meant a caller could not tell
        // a refused zero from a measured zero. Fail closed says a request that cannot be met changes
        // no state. No refusal touches it and the return value is the only thing to read.
        return 0;
    }

    const size_t length = args->length;
    const size_t classes = field_number_classes(args->same_in_field, args->field, length,
                                                args->class_of_position, args->members_in_class,
                                                args->rarity_place_of_class);

    for (size_t at = 0u; at < length; at += 1u)
    {
        args->ranks[at] =
            field_rank_from_place(args->rarity_place_of_class[args->class_of_position[at]]);
    }

    if (args->distinct != NULL)
    {
        // CLASSES AND NOT SLOTS EVER OPENED. A chained field once reported 18 while every position
        // carried one rank, because the count returned was the number of labels discovery had
        // opened. A caller reads this to decide whether
        // a projection is worth running. A healthy number on a collapsed field sends them onto a
        // projection that refutes nothing.
        *args->distinct = classes;
    }
    return 1;
}

int anchor_field_pair_project(const AnchorFieldPairProjection *args)
{
    if (args == NULL)
    {
        return 0;
    }
    if ((args->same_in_field == NULL) || (args->corpus_ranks == NULL) || (args->needle_ranks == NULL) || (args->class_of_position == NULL) || (args->members_in_class == NULL) || (args->rarity_place_of_class == NULL) || (args->corpus_length == 0u) || (args->needle_length == 0u) || (args->needle_length > args->corpus_length))
    {
        return 0;
    }

    // THE JOINT LENGTH IS A SUM. IT IS CHECKED BEFORE IT IS FORMED. Past this point the addition
    // would wrap to a small length, pass the buffer check below, and project a field far shorter than
    // the one the caller described.
    if (args->corpus_length > (SIZE_MAX - args->needle_length))
    {
        return 0;
    }
    const size_t length = args->corpus_length + args->needle_length;

    // Class labels are stored as uint32_t positions. A joint field wider than that would alias two
    // positions onto one label and merge classes the oracle never joined. It is refused. The cast
    // widens a 32 bit constant into size_t, which holds it on every target this builds for.
    if (length > (size_t)UINT32_MAX)
    {
        return 0;
    }
    if (args->classes_length < length)
    {
        return 0;
    }

    const size_t classes = field_number_classes(args->same_in_field, args->field, length,
                                                args->class_of_position, args->members_in_class,
                                                args->rarity_place_of_class);

    // ONE POPULATION READ TWO WAYS. Both loops look up the same rarity order. A class present on both
    // sides takes one rank on both, and rank disagreement between a corpus position and a needle
    // position proves the two fell in different classes. Two separate projections cannot give that
    // necessary condition.
    for (size_t at = 0u; at < args->corpus_length; at += 1u)
    {
        args->corpus_ranks[at] =
            field_rank_from_place(args->rarity_place_of_class[args->class_of_position[at]]);
    }
    for (size_t at = 0u; at < args->needle_length; at += 1u)
    {
        const size_t joint = args->corpus_length + at;

        args->needle_ranks[at] =
            field_rank_from_place(args->rarity_place_of_class[args->class_of_position[joint]]);
    }

    if (args->distinct != NULL)
    {
        *args->distinct = classes;
    }
    return 1;
}

/** @brief Shared entry the two planners differ only in their candidate set. */
static size_t steer_descend(size_t *offsets, size_t count, const uint8_t *corpus,
                            size_t corpus_len, const uint8_t *needle, size_t needle_len,
                            uint8_t *survivors, size_t survivors_length, size_t sample_stride,
                            int spawning, int force_full_depth, const AnchorField *any,
                            int resume)
{
    // A field of any symbol type supplies its own extents and its own validity, and the byte
    // pointers go unread. Checked separately.
    if (any != NULL)
    {
        if ((offsets == NULL) || (survivors == NULL) || (count == 0u) || (any->same == NULL) || (any->alignments == 0u) || (any->needle_len == 0u))
        {
            return 0u;
        }
        needle_len = any->needle_len;
        corpus_len = (any->alignments + any->needle_len) - 1u;
    }
    else if ((offsets == NULL) || (corpus == NULL) || (needle == NULL) || (survivors == NULL) || (count == 0u) || (needle_len == 0u) || (needle_len > corpus_len))
    {
        return 0u;
    }
    if (count > ANCHOR_STEER_ANCHORS)
    {
        return 0u;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    if (survivors_length < alignments)
    {
        // FAILS CLOSED. The kernel allocates nothing. A buffer that does not reach the alignment
        // count is refused, and never worked around by planning on part of the field.
        return 0u;
    }

    const size_t stride = (sample_stride == 0u) ? 1u : sample_stride;

    // Every alignment starts standing and a probe can only ever take one down. That direction is
    // what makes the descent safe to stop at any level: the set shrinks and never grows back.
    //
    // ON RESUME THE SURVIVORS ARE THE INPUT, NOT RESET. A caller composes a recursive spawn by
    // running one descent, then running the next over the survivors the last one left. The child
    // reads only what the parent kept standing and its cost is the survivor count and not the whole
    // field. The engine cannot check that an incoming survivor set is a valid superset of the true
    // occurrences; that obligation is the caller's, and it holds when the set came from an earlier
    // descent on this field. A lone survivor is still not an answer: it has passed only the probes
    // placed so far, and the caller verifies it against the conditions not yet asked with a full
    // compare before calling it found.
    if (resume == 0)
    {
        for (size_t at = 0u; at < alignments; at += 1u)
        {
            survivors[at] = 1u;
        }
    }

    size_t chosen[ANCHOR_STEER_ANCHORS];
    size_t placed = 0u;

    // THE BOUNDED DESCENT. One coarm per level, the level count fixed at `count`, which the guard
    // above holds at or under ANCHOR_STEER_ANCHORS. No branch in here lets the corpus change how
    // many levels run, only which offset a level picks. The depth is decided before the program
    // starts and this loop terminates for the same reason a for loop over a fixed array does.
    while (placed < count)
    {
        size_t best_offset = 0u;
        size_t best_standing = (size_t)-1;
        int found = 0;

        const size_t candidates = spawning ? needle_len : count;
        for (size_t which = 0u; which < candidates; which += 1u)
        {
            const size_t offset = spawning ? which : offsets[which];
            if (offset >= needle_len)
            {
                continue;
            }

            int already = 0;
            for (size_t seen = 0u; seen < placed; seen += 1u)
            {
                if (chosen[seen] == offset)
                {
                    already = 1;
                    break;
                }
            }
            if (already != 0)
            {
                continue;
            }

            const size_t standing = steer_truthy_after(corpus, corpus_len, needle, needle_len,
                                                       survivors, offset, stride, any);
            // Strictly fewer survivors wins. A tie keeps the earlier candidate, which is what makes
            // the descent deterministic on identical input.
            if ((found == 0) || (standing < best_standing))
            {
                best_standing = standing;
                best_offset = offset;
                found = 1;
            }
        }

        if (found == 0)
        {
            break;
        }

        // DESTROY WHAT DOES NOT PRUNE. A probe that leaves the truthy population exactly as it
        // found it rejects nothing an earlier probe had not already rejected. Placing it would read
        // a byte per alignment and buy none. The descent stops instead, and every level below it is
        // destroyed with it. `placed` is returned. The caller learns how many probes survived
        // and is never handed dead ones to evaluate.
        //
        // This is the general form of what anchor_sift_anchors_for does in one special case. That
        // function returns a single anchor on a periodic corpus, because at a period every anchor
        // tests the same congruence and the ones after the first are pure cost. Here the judgment
        // is MEASURED per level against the field instead of inferred from a period, which also
        // catches fields whose redundancy no period search would name.
        if ((force_full_depth == 0) && (best_standing >= steer_truthy_total(survivors, alignments, stride)))
        {
            break;
        }

        chosen[placed] = best_offset;
        placed += 1u;
        steer_make_falsy(corpus, corpus_len, needle, needle_len, survivors, best_offset, any);
    }

    for (size_t slot = 0u; slot < placed; slot += 1u)
    {
        offsets[slot] = chosen[slot];
    }
    return placed;
}

size_t anchor_steer_plan_recursive(const AnchorSteerDescent *args)
{
    if (args == NULL)
    {
        return 0u;
    }

    // Reordering. `spawning` is 0 and the candidates are the offsets the caller already placed.
    // force_full_depth is read from the argument even here: a caller checking that stopping equals
    // continuing has to be able to force the reordering descent too, not only the spawning one.
    return steer_descend(args->offsets, args->count, args->corpus, args->corpus_len, args->needle,
                         args->needle_len, args->survivors, args->survivors_length,
                         args->sample_stride, 0, args->force_full_depth, args->any,
                         args->resume);
}

size_t anchor_steer_spawn_coarms(const AnchorSteerDescent *args)
{
    if (args == NULL)
    {
        return 0u;
    }

    // Spawning. `spawning` is 1 and the candidates are every position in the needle.
    return steer_descend(args->offsets, args->count, args->corpus, args->corpus_len, args->needle,
                         args->needle_len, args->survivors, args->survivors_length,
                         args->sample_stride, 1, args->force_full_depth, args->any,
                         args->resume);
}

int anchor_steer_probe_fits(const AnchorProbe *probe, size_t needle_len)
{
    if ((probe == NULL) || (probe->length == 0u) || (needle_len == 0u))
    {
        return 0;
    }
    if (probe->origin >= needle_len)
    {
        return 0;
    }
    if (probe->length == 1u)
    {
        return 1;
    }
    if (probe->step == 0u)
    {
        // A line of length greater than one with no step reads one position repeatedly. That is an
        // arm wearing an eye's shape. It is refused here and never silently collapsed.
        return 0;
    }

    // The last position is origin + step*(length-1). Formed by division against the room actually
    // left, which refuses a step and length whose product would wrap size_t instead of letting it
    // wrap into a position that passes a bounds test.
    const size_t reach = needle_len - 1u - probe->origin;
    return ((probe->length - 1u) <= (reach / probe->step)) ? 1 : 0;
}

/** @brief Whether one alignment agrees with the needle at every position a probe reads. */
static int steer_probe_agrees(const uint8_t *corpus, const uint8_t *needle,
                              const AnchorProbe *probe, size_t at)
{
    for (size_t step = 0u; step < probe->length; step += 1u)
    {
        const size_t offset = probe->origin + (step * probe->step);
        if (corpus[at + offset] != needle[offset])
        {
            return 0;
        }
    }
    return 1;
}

/** @brief Truthy alignments remaining if `probe` were placed, in the sampled population. */
static size_t steer_truthy_after_probe(const uint8_t *corpus, size_t corpus_len,
                                       const uint8_t *needle, size_t needle_len,
                                       const uint8_t *alive, const AnchorProbe *probe,
                                       size_t stride)
{
    const size_t alignments = (corpus_len - needle_len) + 1u;
    size_t standing = 0u;

    for (size_t at = 0u; at < alignments; at += stride)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (steer_probe_agrees(corpus, needle, probe, at) != 0)
        {
            standing += 1u;
        }
    }
    return standing;
}

/** @brief Turns falsy every alignment a probe rejects, over the whole population. */
static void steer_make_falsy_probe(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                   size_t needle_len, uint8_t *alive, const AnchorProbe *probe)
{
    const size_t alignments = (corpus_len - needle_len) + 1u;

    for (size_t at = 0u; at < alignments; at += 1u)
    {
        if (alive[at] == 0u)
        {
            continue;
        }
        if (steer_probe_agrees(corpus, needle, probe, at) == 0)
        {
            alive[at] = 0u;
        }
    }
}

/**
 * @brief The sweep itself, which the public entry names.
 *
 * @param[out] probes           Chosen probes, in evaluation order [BORROWS].
 * @param[in]  wanted           How many to place. At most ANCHOR_STEER_ANCHORS.
 * @param[in]  corpus           Bytes the search will run over [BORROWS].
 * @param[in]  corpus_len       How many.
 * @param[in]  needle           Bytes to find [BORROWS].
 * @param[in]  needle_len       How many.
 * @param[in]  max_length       Longest eye to consider.
 * @param[out] survivors        Which alignments the probes left standing, one byte each [BORROWS].
 * @param[in]  survivors_length How many. Must reach the alignment count.
 * @param[in]  sample_stride    Plan on every Nth alignment. 0 is treated as 1.
 * @return                      Probes actually placed.
 * @note Static and positional, which is where a long parameter list is allowed to live. The public
 *       surface takes one pointer to a const argument structure; this is the backend it names, and
 *       every check the contract states happens here.
 */
static size_t steer_sweep_probes(AnchorProbe *probes, size_t wanted, const uint8_t *corpus,
                                 size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 size_t max_length, uint8_t *survivors, size_t survivors_length,
                                 size_t sample_stride)
{
    if ((probes == NULL) || (corpus == NULL) || (needle == NULL) || (survivors == NULL) || (wanted == 0u) || (wanted > ANCHOR_STEER_ANCHORS) || (needle_len == 0u) || (needle_len > corpus_len) || (max_length == 0u))
    {
        return 0u;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    if (survivors_length < alignments)
    {
        return 0u;
    }

    const size_t stride = (sample_stride == 0u) ? 1u : sample_stride;
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        survivors[at] = 1u;
    }

    size_t placed = 0u;

    // THREE BOUNDED LOOPS INSIDE A BOUNDED DESCENT. Origins run to needle_len, steps run to
    // needle_len, lengths run to max_length, and the descent runs to `wanted`. Every bound is an
    // argument or a compile time constant and none of them is read from the corpus. The extent of
    // this search is fixed before the first byte is examined.
    while (placed < wanted)
    {
        AnchorProbe best = {0u, 1u, 1u};
        size_t best_standing = 0u;
        int found = 0;

        for (size_t origin = 0u; origin < needle_len; origin += 1u)
        {
            for (size_t length = 1u; length <= max_length; length += 1u)
            {
                const size_t step_limit = (length == 1u) ? 2u : (needle_len + 1u);
                for (size_t step = 1u; step < step_limit; step += 1u)
                {
                    const AnchorProbe candidate = {origin, step, length};
                    if (anchor_steer_probe_fits(&candidate, needle_len) == 0)
                    {
                        continue;
                    }

                    const size_t standing = steer_truthy_after_probe(corpus, corpus_len, needle,
                                                                     needle_len, survivors,
                                                                     &candidate, stride);
                    if ((found == 0) || (standing < best_standing))
                    {
                        best_standing = standing;
                        best = candidate;
                        found = 1;
                    }
                }
            }
        }

        if (found == 0)
        {
            break;
        }
        if (best_standing >= steer_truthy_total(survivors, alignments, stride))
        {
            // Destroyed for the same reason a coarm is. It prunes nothing and would only read.
            break;
        }

        probes[placed] = best;
        placed += 1u;
        steer_make_falsy_probe(corpus, corpus_len, needle, needle_len, survivors, &best);
    }
    return placed;
}

size_t anchor_steer_sweep_probes(const AnchorSteerSweep *args)
{
    if (args == NULL)
    {
        return 0u;
    }

    // The entry tests the one thing the backend cannot: whether it was handed arguments at all.
    // Everything else the contract states is checked in steer_sweep_probes, against the values it
    // is going to use. No check exists in two places to drift apart.
    return steer_sweep_probes(args->probes, args->count, args->corpus, args->corpus_len,
                              args->needle, args->needle_len, args->max_length, args->survivors,
                              args->survivors_length, args->sample_stride);
}

uint64_t anchor_steer_probes = 0u;

void anchor_steer_probes_reset(void)
{
    anchor_steer_probes = 0u;
}

/**
 * @brief Places anchor offsets by spatial spread, one drawn inside each evenly sized cell.
 *
 * @param[out] offsets    Where the chosen offsets are written [BORROWS].
 * @param[in]  wanted     How many to choose.
 * @param[in]  needle_len Length of the needle they index.
 *
 * @note The same placement rule the search above uses, carried here so the steered route chooses where
 *       to probe the same way the engines it is compared against do. Only the ORDER of evaluation is
 *       this file's contribution, and placing differently would confound the two.
 * @note Returns every offset zero at `needle_len` zero
 *       which on size_t wraps to SIZE_MAX. The caller does not probe at that length in any case.
 */
static void steer_choose_offsets(size_t *offsets, size_t wanted, size_t needle_len)
{
    if (needle_len == 0u)
    {
        for (size_t slot = 0u; slot < wanted; slot += 1u)
        {
            offsets[slot] = 0u;
        }
        return;
    }

    const size_t cell = needle_len / wanted;
    for (size_t slot = 0u; slot < wanted; slot += 1u)
    {
        const size_t inside = (cell > 1u) ? ((slot * 7u) % cell) : 0u;
        offsets[slot] = (slot * cell) + inside;
        if (offsets[slot] >= needle_len)
        {
            offsets[slot] = needle_len - 1u;
        }
    }
}

size_t anchor_steer_count_with_probes(const uint8_t *corpus, size_t corpus_len,
                                      const uint8_t *needle, size_t needle_len,
                                      const AnchorProbe *probes, size_t count)
{
    if ((corpus == NULL) || (needle == NULL) || (needle_len > corpus_len))
    {
        return 0u;
    }
    // An empty needle occurs at every alignment. anchor_sift_naive and anchor_steer_count both report
    // corpus_len + 1 for it, and the reference fixes that answer. This returns the same before the
    // loop. Returning 0 here
    // disagreed with the reference and with the two counting entries beside it.
    if (needle_len == 0u)
    {
        return corpus_len + 1u;
    }
    if ((probes == NULL) && (count != 0u))
    {
        return 0u;
    }

    // Every probe reads within the needle or the whole call refuses. A probe whose origin plus its
    // stepped reach lands at or past needle_len would read needle[offset], and corpus[at + offset],
    // out of bounds. anchor_steer_probe_fits is the same test the sweep applies before it emits a
    // probe, checked here once before the alignment loop because this is a public entry a caller can
    // hand a probe the sweep never made. A probe that does not fit gets 0, the refusal a null probe
    // array with a nonzero count gets above.
    for (size_t slot = 0u; slot < count; slot += 1u)
    {
        if (anchor_steer_probe_fits(&probes[slot], needle_len) == 0)
        {
            return 0u;
        }
    }

    size_t found = 0u;
    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        size_t slot = 0u;
        while (slot < count)
        {
            int agrees = 1;
            for (size_t step = 0u; step < probes[slot].length; step += 1u)
            {
                const size_t offset = probes[slot].origin + (step * probes[slot].step);
                anchor_steer_probes += 1u;
                if (corpus[at + offset] != needle[offset])
                {
                    agrees = 0;
                    break;
                }
            }
            if (agrees == 0)
            {
                break;
            }
            slot += 1u;
        }
        if (slot == count)
        {
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    return found;
}

size_t anchor_steer_count(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                          size_t needle_len, int steered)
{
    if ((corpus == NULL) || (needle == NULL) || (needle_len > corpus_len))
    {
        return 0u;
    }

    size_t found = 0u;

    // An empty needle has no symbol to probe. The reference engine reports it at every alignment
    // and this one answers the same, instead of inventing a different answer to one question.
    if (needle_len == 0u)
    {
        return corpus_len + 1u;
    }

    size_t offsets[ANCHOR_STEER_ANCHORS];
    steer_choose_offsets(offsets, ANCHOR_STEER_ANCHORS, needle_len);

    if (steered != 0)
    {
        // THE ENGINE TURNED ONTO ITSELF. One pass over the corpus it is about to search produces
        // the census, and the census decides the order this same corpus is then probed in.
        AnchorFieldCensus census;
        anchor_field_census(corpus, corpus_len, &census);
        anchor_steer_probe_order(offsets, ANCHOR_STEER_ANCHORS, &census, needle, needle_len);
    }

    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        size_t slot = 0u;
        while (slot < ANCHOR_STEER_ANCHORS)
        {
            anchor_steer_probes += 1u;
            if (corpus[at + offsets[slot]] != needle[offsets[slot]])
            {
                break;
            }
            slot += 1u;
        }
        if (slot == ANCHOR_STEER_ANCHORS)
        {
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    return found;
}

/* ---- the scan: shared counters and the arm dispatch; each arm is its own scan_<set>.c ---- */

uint64_t anchor_steer_scan_calls = 0u;
uint64_t anchor_steer_wide_calls = 0u;

void anchor_steer_scan_counters_reset(void)
{
    anchor_steer_scan_calls = 0u;
    anchor_steer_wide_calls = 0u;
}

const AnchorSteerEngine *anchor_steer_best_engine(void)
{
    // Widest first, and each arm asks the processor before it is taken. The x86 arms and the ARM arms
    // are gated by mutually exclusive build macros. At most one architecture's ladder is compiled
    // in and the rest fold away. A present arm returning NULL means the build carried it but the
    // running part does not, and the next arm down is tried.
#if defined(ANCHOR_STEER_HAVE_AVX512) && ANCHOR_STEER_HAVE_AVX512
    {
        const AnchorSteerEngine *wide = anchor_steer_avx512_engine();
        if (wide != NULL)
        {
            return wide;
        }
    }
#endif
#if defined(ANCHOR_STEER_HAVE_AVX2) && ANCHOR_STEER_HAVE_AVX2
    {
        const AnchorSteerEngine *wide = anchor_steer_avx2_engine();
        if (wide != NULL)
        {
            return wide;
        }
    }
#endif
#if defined(ANCHOR_STEER_HAVE_SVE) && ANCHOR_STEER_HAVE_SVE
    {
        const AnchorSteerEngine *wide = anchor_steer_sve_engine();
        if (wide != NULL)
        {
            return wide;
        }
    }
#endif
#if defined(ANCHOR_STEER_HAVE_NEON) && ANCHOR_STEER_HAVE_NEON
    {
        const AnchorSteerEngine *wide = anchor_steer_neon_engine();
        if (wide != NULL)
        {
            return wide;
        }
    }
#endif
    return anchor_steer_portable_engine();
}
