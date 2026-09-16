/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_steer.c
 * @brief The census, the rarity ordering, and the dispatch test carried in exact integers.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @note No double and no float is declared anywhere in this file, and <math.h> is not included.
 *       That is the point of the file and not a side effect of it: the engine's only two remaining
 *       floating point decisions were the rarity ordering and the dispatch threshold, and both are
 *       exact integer comparisons here.
 */

#include "anchor_steer.h"

#include "exact_limbs.h"

#include <string.h>

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
    if ((offsets == NULL) || (census == NULL) || (needle == NULL) || (count == 0u)
     || (needle_len == 0u) || (census->total == 0u))
    {
        return;
    }

    /* Insertion sort, descending by magnitude, and STABLE. The strict greater-than in the shift
     * test is what keeps it stable: an equal magnitude does not displace the entry already placed,
     * so anchors testing equally rare symbols keep the spatial spread choose_offsets gave them. */
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
        /* An empty field distinguishes nothing, so it takes the short circuiting arm, which is what
         * the engine ran before any of this and is the cheaper of the two on a field with no
         * structure to exploit. */
        return 0;
    }

    AnchorExactInteger total;
    AnchorExactInteger left;
    AnchorExactInteger right;
    AnchorExactInteger sum_of_squares;
    AnchorExactInteger term;
    AnchorExactInteger scratch;

    steer_exact_from_u64(&total, census->total);

    /* left = 100 * total^2 */
    if (anchor_exact_multiply(&total, &total, &left) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    steer_exact_from_u64(&scratch, 100u);
    if (anchor_exact_multiply(&left, &scratch, &left) != ANCHOR_EXACT_OK)
    {
        return 0;
    }

    /* sum_of_squares = sum over symbols of count^2, accumulated in the limb form rather than in a
     * 64 bit counter. A single count squares to at most total^2, which already passes 2^64 on a
     * four gigabyte corpus, and 256 of them are summed on top of that. */
    anchor_exact_zero(&sum_of_squares);
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
        if (anchor_exact_add(&sum_of_squares, &term, &sum_of_squares) != ANCHOR_EXACT_OK)
        {
            return 0;
        }
    }

    /* right = 85 * distinct * sum_of_squares */
    steer_exact_from_u64(&scratch, 85u);
    if (anchor_exact_multiply(&sum_of_squares, &scratch, &right) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    steer_exact_from_u64(&scratch, (uint64_t)census->distinct);
    if (anchor_exact_multiply(&right, &scratch, &right) != ANCHOR_EXACT_OK)
    {
        return 0;
    }

    /* The rule reads "flat corpora take the short circuiting arm", so the free order arm is the
     * branch taken when the effective alphabet does NOT reach the threshold. */
    return (anchor_exact_compare(&left, &right) < 0) ? 1 : 0;
}

uint64_t anchor_steer_probes = 0u;

void anchor_steer_probes_reset(void)
{
    anchor_steer_probes = 0u;
}

/** @brief Anchors the steered arm places, matching ANCHOR_SIFT_ANCHORS in anchor_sift.h. */
#define ANCHOR_STEER_ANCHORS 4u

/**
 * @brief Places anchor offsets by spatial spread, one drawn inside each evenly sized cell.
 *
 * @param[out] offsets    Where the chosen offsets are written [BORROWS].
 * @param[in]  wanted     How many to choose.
 * @param[in]  needle_len Length of the needle they index.
 *
 * @note The same placement rule anchor_sift.c uses, carried here so the steered arm chooses where
 *       to probe the same way the arms it is compared against do. Only the ORDER of evaluation is
 *       this file's contribution, and placing differently would confound the two.
 * @note Returns every offset zero at `needle_len` zero rather than computing `needle_len - 1u`,
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

size_t anchor_steer_count(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                          size_t needle_len, int steered)
{
    if ((corpus == NULL) || (needle == NULL) || (needle_len > corpus_len))
    {
        return 0u;
    }

    size_t found = 0u;

    /* An empty needle has no symbol to probe. The reference arm reports it at every alignment, so
     * this one does too rather than inventing a different answer for the same question. */
    if (needle_len == 0u)
    {
        return corpus_len + 1u;
    }

    size_t offsets[ANCHOR_STEER_ANCHORS];
    steer_choose_offsets(offsets, ANCHOR_STEER_ANCHORS, needle_len);

    if (steered != 0)
    {
        /* THE ENGINE TURNED ONTO ITSELF. One pass over the corpus it is about to search produces
         * the census, and the census decides the order this same corpus is then probed in. */
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
