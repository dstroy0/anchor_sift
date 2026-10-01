
// orior_steer_count.c: sweeping the probes and counting
#include "orior_internal.h"

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
 *       every check the contract states happens here and not in the entry.
 */
static size_t steer_sweep_probes(AnchorProbe *probes, size_t wanted, const uint8_t *corpus, size_t corpus_len,
                                 const uint8_t *needle, size_t needle_len, size_t max_length, uint8_t *survivors,
                                 size_t survivors_length, size_t sample_stride)
{
    if ((probes == NULL) || (corpus == NULL) || (needle == NULL) || (survivors == NULL) || (wanted == 0u) ||
        (wanted > ANCHOR_STEER_ANCHORS) || (needle_len == 0u) || (needle_len > corpus_len) || (max_length == 0u))
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

                    const size_t standing =
                        steer_truthy_after_probe(corpus, corpus_len, needle, needle_len, survivors, &candidate, stride);
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

    // The entry tests only what the backend cannot: whether it was handed arguments at all.
    // Everything else the contract states is checked in steer_sweep_probes, against the values it
    // is going to use. No check exists in two places to drift apart.
    return steer_sweep_probes(args->probes, args->count, args->corpus, args->corpus_len, args->needle, args->needle_len,
                              args->max_length, args->survivors, args->survivors_length, args->sample_stride);
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
 * @note Returns every offset zero at `needle_len` zero instead of computing `needle_len - 1u`,
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

size_t anchor_steer_count_with_probes(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle,
                                      size_t needle_len, const AnchorProbe *probes, size_t count)
{
    if ((corpus == NULL) || (needle == NULL) || (needle_len > corpus_len))
    {
        return 0u;
    }
    // An empty needle occurs at every alignment. orior_naive and anchor_steer_count both report
    // corpus_len + 1 for it, and the reference fixes that answer. This returns the same before the
    // loop instead of reading needle[offset] off a needle with no positions. Returning 0 here
    // disagreed with the reference and with the two counting entries beside it.
    if (needle_len == 0u)
    {
        return corpus_len + 1u;
    }
    if ((probes == NULL) && (count != 0u))
    {
        return 0u;
    }

    // Every probe reads within the needle or the whole call errors. A probe whose origin plus its
    // stepped reach lands at or past needle_len would read needle[offset], and corpus[at + offset],
    // out of bounds. anchor_steer_probe_fits is the same test the sweep applies before it emits a
    // probe, checked here once before the alignment loop because this is a public entry a caller can
    // hand a probe the sweep never made. A probe that does not fit gets 0, the error a null probe
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

size_t anchor_steer_count(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len,
                          int steered)
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
