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

/**
 * @brief Chooses anchor offsets, one drawn inside each evenly sized cell of the needle.
 *
 * @param[out] offsets    Where the chosen offsets are written [BORROWS].
 * @param[in]  wanted     How many to choose.
 * @param[in]  needle_len Length of the needle they index.
 * @note One draw per cell keeps the spread and gives the anchor set no period of its own. An even
 *       comb shares a period with whatever the domain carries, which is the failure that rule avoids.
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
        if (memcmp(corpus + at, needle, needle_len) == 0)
        {
            found += 1u;
        }
    }
    return found;
}

size_t anchor_sift_horspool(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                            size_t needle_len)
{
    size_t shift[256];
    size_t found = 0u;
    size_t at = 0u;

    for (size_t slot = 0u; slot < 256u; slot += 1u)
    {
        shift[slot] = needle_len;
    }
    for (size_t step = 0u; (step + 1u) < needle_len; step += 1u)
    {
        shift[needle[step]] = needle_len - 1u - step;
    }

    while ((at + needle_len) <= corpus_len)
    {
        if (memcmp(corpus + at, needle, needle_len) == 0)
        {
            found += 1u;
        }
        at += shift[corpus[at + needle_len - 1u]];
    }
    return found;
}

size_t anchor_sift_inorder(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                           size_t needle_len)
{
    size_t offsets[ANCHOR_SIFT_ANCHORS];
    size_t found = 0u;

    choose_offsets(offsets, ANCHOR_SIFT_ANCHORS, needle_len);

    for (size_t at = 0u; (at + needle_len) <= corpus_len; at += 1u)
    {
        size_t slot = 0u;
        while (slot < ANCHOR_SIFT_ANCHORS)
        {
            if (corpus[at + offsets[slot]] != needle[offsets[slot]])
            {
                break;
            }
            slot += 1u;
        }
        if (slot == ANCHOR_SIFT_ANCHORS)
        {
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    return found;
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
        const unsigned agree = (unsigned)(corpus[at + offsets[0]] == wanted[0]) &
                               (unsigned)(corpus[at + offsets[1]] == wanted[1]) &
                               (unsigned)(corpus[at + offsets[2]] == wanted[2]) &
                               (unsigned)(corpus[at + offsets[3]] == wanted[3]);
        if (agree != 0u)
        {
            if (memcmp(corpus + at, needle, needle_len) == 0)
            {
                found += 1u;
            }
        }
    }
    return found;
}

/* Where the free order arm stops paying, measured on a skewed corpus at 65536 bytes. It wins at
 * needle lengths 4, 8 and 16 and loses from 32 upward, because Horspool's shift grows with the
 * needle while the sift pays a fixed cost per alignment. */
#define ANCHOR_SIFT_FREE_CEILING 16u

/* How close the effective alphabet has to sit to the symbols actually used before a corpus counts
 * as memoryless. A uniform corpus puts 2^H2 within a few percent of its distinct count; a skewed
 * one puts it far below. */
#define ANCHOR_SIFT_FLAT_SHARE 0.85

/**
 * @brief Two to the power of a small non-negative exponent, without <math.h>.
 *
 * @param[in] exponent Collision entropy in bits, at most 8 for a byte corpus.
 * @return             The effective alphabet size that exponent stands for.
 * @note The kernel stays free of libm so a driver on a part without one can still link it.
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
    const double used = (plan->distinct_symbols > 0u) ? (double)plan->distinct_symbols : 1.0;
    const int flat = (effective >= (ANCHOR_SIFT_FLAT_SHARE * used));

    /* A memoryless corpus rejects on the first probe almost every time, so short circuiting is
     * nearly free and issuing four loads is waste. Horspool beats both arms there outright once the
     * needle is long enough to give it a shift. */
    if (flat)
    {
        return (plan->needle_len <= 4u) ? anchor_sift_inorder : anchor_sift_horspool;
    }

    /* Structured. The free order arm wins while the needle is short and Horspool's shift is small. */
    if (plan->needle_len <= ANCHOR_SIFT_FREE_CEILING)
    {
        return anchor_sift_free;
    }
    return anchor_sift_horspool;
}

const char *anchor_sift_arm_name(AnchorSiftArm arm)
{
    if (arm == anchor_sift_naive)
    {
        return "naive";
    }
    if (arm == anchor_sift_horspool)
    {
        return "horspool";
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
