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

/* ------------------------------------------------------------------------------------------------
 * Truthy and falsy steering. The signal is the survivor vector, not the symbol histogram.
 *
 * EACH PERMUTATION OF THE ANCHORS IS A NULL, AND EACH NULL IS A STEER. An alignment survives only
 * when every anchor agrees, and a conjunction does not depend on the order of its terms, so every
 * ordering of a given anchor set returns the same count. The orderings therefore form a group of
 * moves that CANNOT change the answer, which is what this tree calls a null. Steering is choosing
 * which element of that group to apply.
 *
 * That is the whole safety argument for everything below, and it is structural rather than
 * defensive. A planner that samples badly, ranks wrongly, or is outright broken still lands on some
 * element of the null group, and every element yields the same count. The planner moves inside the
 * null and the null has one value. Correctness is therefore not something the planner can spend,
 * and speed is the only currency it holds.
 * ---------------------------------------------------------------------------------------------- */

/**
 * @brief How many currently truthy alignments stay truthy when `offset` is tested.
 *
 * @param[in] alive  One flag per alignment, non-zero for truthy [BORROWS].
 * @param[in] stride Sample every Nth alignment. The ranking is a comparison between candidates, so
 *                   a consistent sample ranks them consistently without reading them all.
 * @return           Count of survivors, in the sampled population.
 */
static size_t steer_truthy_after(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                 size_t needle_len, const uint8_t *alive, size_t offset,
                                 size_t stride)
{
    const size_t alignments = (corpus_len - needle_len) + 1u;
    const uint8_t wanted = needle[offset];
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
 * @note Sampled at the same stride the candidate scores use, so the comparison between "survivors
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
                             size_t needle_len, uint8_t *alive, size_t offset)
{
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

/** @brief Shared entry the two planners differ only in their candidate set. */
static size_t steer_descend(size_t *offsets, size_t count, const uint8_t *corpus,
                            size_t corpus_len, const uint8_t *needle, size_t needle_len,
                            uint8_t *scratch, size_t scratch_len, size_t sample_stride,
                            int spawning)
{
    if ((offsets == NULL) || (corpus == NULL) || (needle == NULL) || (scratch == NULL)
     || (count == 0u) || (needle_len == 0u) || (needle_len > corpus_len))
    {
        return 0u;
    }
    if (count > ANCHOR_STEER_ANCHORS)
    {
        return 0u;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    if (scratch_len < alignments)
    {
        /* FAILS CLOSED. The kernel allocates nothing, so a buffer that does not reach the alignment
         * count is refused rather than worked around by planning on part of the field. */
        return 0u;
    }

    const size_t stride = (sample_stride == 0u) ? 1u : sample_stride;

    for (size_t at = 0u; at < alignments; at += 1u)
    {
        scratch[at] = 1u;
    }

    size_t chosen[ANCHOR_STEER_ANCHORS];
    size_t placed = 0u;

    /* THE BOUNDED DESCENT. One coarm per level, the level count fixed at `count`, which the guard
     * above holds at or under ANCHOR_STEER_ANCHORS. No branch in here lets the corpus change how
     * many levels run, only which offset a level picks, so the depth is decided before the program
     * starts and this loop terminates for the same reason a for loop over a fixed array does. */
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
                                                       scratch, offset, stride);
            /* Strictly fewer survivors wins, so a tie keeps the earlier candidate and the descent
             * is deterministic on identical input. */
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

        /* DESTROY WHAT DOES NOT PRUNE. A probe that leaves the truthy population exactly as it
         * found it rejects nothing an earlier probe had not already rejected, so it would read a
         * byte per alignment and buy none. The descent stops rather than placing it, and every
         * level below it is destroyed with it. `placed` is returned, so the caller learns how many
         * probes survived rather than being handed dead ones to evaluate.
         *
         * This is the general form of what anchor_sift_anchors_for does in one special case. That
         * function returns a single anchor on a periodic corpus, because at a period every anchor
         * tests the same congruence and the ones after the first are pure cost. Here the judgment
         * is MEASURED per level against the field rather than inferred from a period, so it also
         * catches fields whose redundancy no period search would name. */
        if (best_standing >= steer_truthy_total(scratch, alignments, stride))
        {
            break;
        }

        chosen[placed] = best_offset;
        placed += 1u;
        steer_make_falsy(corpus, corpus_len, needle, needle_len, scratch, best_offset);
    }

    for (size_t slot = 0u; slot < placed; slot += 1u)
    {
        offsets[slot] = chosen[slot];
    }
    return placed;
}

size_t anchor_steer_plan_recursive(size_t *offsets, size_t count, const uint8_t *corpus,
                                   size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                   uint8_t *scratch, size_t scratch_len, size_t sample_stride)
{
    return steer_descend(offsets, count, corpus, corpus_len, needle, needle_len, scratch,
                         scratch_len, sample_stride, 0);
}

size_t anchor_steer_spawn_coarms(size_t *offsets, size_t wanted, const uint8_t *corpus,
                                 size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 uint8_t *scratch, size_t scratch_len, size_t sample_stride)
{
    return steer_descend(offsets, wanted, corpus, corpus_len, needle, needle_len, scratch,
                         scratch_len, sample_stride, 1);
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
        /* A line of length greater than one with no step reads one position repeatedly. That is an
         * arm wearing an eye's shape and it is refused rather than silently collapsed. */
        return 0;
    }

    /* The last position is origin + step*(length-1). Formed by division against the room actually
     * left, so a step and length whose product would wrap size_t are refused instead of wrapping
     * into a position that passes a bounds test. */
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

size_t anchor_steer_sweep_probes(AnchorProbe *probes, size_t wanted, const uint8_t *corpus,
                                 size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 size_t max_length, uint8_t *scratch, size_t scratch_len,
                                 size_t sample_stride)
{
    if ((probes == NULL) || (corpus == NULL) || (needle == NULL) || (scratch == NULL)
     || (wanted == 0u) || (wanted > ANCHOR_STEER_ANCHORS) || (needle_len == 0u)
     || (needle_len > corpus_len) || (max_length == 0u))
    {
        return 0u;
    }

    const size_t alignments = (corpus_len - needle_len) + 1u;
    if (scratch_len < alignments)
    {
        return 0u;
    }

    const size_t stride = (sample_stride == 0u) ? 1u : sample_stride;
    for (size_t at = 0u; at < alignments; at += 1u)
    {
        scratch[at] = 1u;
    }

    size_t placed = 0u;

    /* THREE BOUNDED LOOPS INSIDE A BOUNDED DESCENT. Origins run to needle_len, steps run to
     * needle_len, lengths run to max_length, and the descent runs to `wanted`. Every bound is an
     * argument or a compile time constant and none of them is read from the corpus, so the extent
     * of this search is fixed before the first byte is examined. */
    while (placed < wanted)
    {
        AnchorProbe best = { 0u, 1u, 1u };
        size_t best_standing = 0u;
        int found = 0;

        for (size_t origin = 0u; origin < needle_len; origin += 1u)
        {
            for (size_t length = 1u; length <= max_length; length += 1u)
            {
                const size_t step_limit = (length == 1u) ? 2u : (needle_len + 1u);
                for (size_t step = 1u; step < step_limit; step += 1u)
                {
                    const AnchorProbe candidate = { origin, step, length };
                    if (anchor_steer_probe_fits(&candidate, needle_len) == 0)
                    {
                        continue;
                    }

                    const size_t standing = steer_truthy_after_probe(corpus, corpus_len, needle,
                                                                     needle_len, scratch,
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
        if (best_standing >= steer_truthy_total(scratch, alignments, stride))
        {
            /* Destroyed for the same reason a coarm is: it prunes nothing and would only read. */
            break;
        }

        probes[placed] = best;
        placed += 1u;
        steer_make_falsy_probe(corpus, corpus_len, needle, needle_len, scratch, &best);
    }
    return placed;
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

size_t anchor_steer_count_with_probes(const uint8_t *corpus, size_t corpus_len,
                                      const uint8_t *needle, size_t needle_len,
                                      const AnchorProbe *probes, size_t count)
{
    if ((corpus == NULL) || (needle == NULL) || (needle_len > corpus_len) || (needle_len == 0u))
    {
        return 0u;
    }
    if ((probes == NULL) && (count != 0u))
    {
        return 0u;
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
