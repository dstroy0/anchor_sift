/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_sift.c
 * @brief The four search arms and the dispatcher, with no clock and no output in any of them.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-04
 *
 * @note Every arm is sound: a subset of a pattern's points is a necessary condition, so none of them
 *       can lose a true occurrence. What differs between them is how much they read and how much of
 *       that reading the machine can overlap.
 */

#include "anchor_sift.h"

#include <string.h>

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
/* A fixed number of probe reads, for the arm that issues all of them whatever any one returns. */
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
 * @param[in]  wanted     How many to choose.
 * @param[in]  needle_len Length of the needle they index.
 * @note One draw per cell keeps the spread and gives the anchor set no period of its own. An even
 *       comb shares a period with whatever the domain carries, the failure this avoids.
 */
static void choose_offsets(size_t *offsets, size_t wanted, size_t needle_len)
{
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
 * @brief The in order arm with the anchor count supplied.
 *
 * @param[in] corpus     Bytes to search [BORROWS].
 * @param[in] corpus_len How many.
 * @param[in] needle     Bytes to find [BORROWS].
 * @param[in] needle_len How many.
 * @param[in] anchors    How many anchors to place, at least one and at most ANCHOR_SIFT_ANCHORS.
 * @return               How many alignments match exactly.
 * @note Only this arm takes a count. The free order arm's advantage is that its four comparisons
 *       are written out and fold into one value with one branch behind them, and a loop over a
 *       runtime count gives that back. A corpus whose count wants reducing is a coherent one, and
 *       a coherent corpus dispatches here anyway.
 */
static size_t sift_inorder_n(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                             size_t needle_len, size_t anchors)
{
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
        /* No short circuit. Four loads issue together, the comparisons fold into one value, and the
         * branch is taken once. This is the dependency depth two arrangement. */
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

/* How close the effective alphabet has to sit to the symbols actually used before a corpus counts
 * as memoryless. A uniform corpus puts 2^H2 within a few percent of its distinct count; a skewed
 * one puts it far below.
 *
 * Swept by bench_dispatch, not chosen. Every threshold from 0.34 to 0.96 scores identically
 * on the corpora measured, since the three of them read 0.96, 0.33 and 1.00 and nothing sits in
 * between. This value is inside that interval and stays where it was; a fourth corpus landing
 * between 0.34 and 0.96 is what would decide it, and none has. */
#define ANCHOR_SIFT_FLAT_SHARE 0.85

/**
 * @brief Two to the power of a small non-negative exponent, without <math.h>.
 *
 * @param[in] exponent Collision entropy in bits, at most 8 for a byte corpus.
 * @return             The effective alphabet size that exponent stands for.
 * @note The kernel stays free of libm, letting a driver on a part without one still link it.
 */
static double two_to_the(double exponent)
{
    double held = 1.0;

    while (exponent >= 1.0)
    {
        held *= 2.0;
        exponent -= 1.0;
    }
    /* The remaining fraction, to the accuracy a dispatch decision needs. Three terms of the series
     * for 2^x on [0,1) keep the error under one percent, which cannot move a threshold set at 0.85. */
    held *= 1.0 + (exponent * 0.6931472) + (exponent * exponent * 0.2402265);
    return held;
}

AnchorSiftArm anchor_sift_choose(const AnchorSiftPlan *plan)
{
    const double effective = two_to_the(plan->collision_entropy);

    /* A flat corpus refutes almost every alignment on the first probe, so short circuiting reads one
     * byte where the free order arm reads four. A structured one refutes on the first probe often
     * enough to make the loop trip count vary, and a varying trip count costs a mispredicted branch
     * per alignment. The branchless arm exists to avoid that. */
    if (effective >= (ANCHOR_SIFT_FLAT_SHARE * (double)plan->distinct_symbols))
    {
        return anchor_sift_inorder;
    }
    return anchor_sift_free;
}

size_t anchor_sift_anchors_for(const AnchorSiftPlan *plan)
{
    /* Every anchor after the first tests the congruence the first one already tested, so the reads
     * they perform are their only contribution. */
    if (plan->period != 0u)
    {
        return 1u;
    }
    return ANCHOR_SIFT_ANCHORS;
}

size_t anchor_sift_run(const AnchorSiftPlan *plan, const uint8_t *corpus, size_t corpus_len,
                       const uint8_t *needle, size_t needle_len)
{
    if (anchor_sift_choose(plan) == anchor_sift_free)
    {
        return anchor_sift_free(corpus, corpus_len, needle, needle_len);
    }
    return sift_inorder_n(corpus, corpus_len, needle, needle_len, anchor_sift_anchors_for(plan));
}

const char *anchor_sift_arm_name(AnchorSiftArm arm)
{
    if (arm == anchor_sift_naive)
    {
        return "naive";
    }
    if (arm == anchor_sift_inorder)
    {
        return "anchor_inorder";
    }
    if (arm == anchor_sift_free)
    {
        return "anchor_free";
    }
    return "unknown";
}
