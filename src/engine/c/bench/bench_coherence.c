/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_coherence.c
 * @brief Reads a corpus's coherence before searching it, and predicts what that costs the bound.
 * @author dstroy0 (Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note This is the ingestion reading. Everything the sift does downstream follows from it: how
 *       many anchors are worth placing, how far apart, and what share of alignments to expect
 *       through the filter. The histogram is read at the same moment and answers a different
 *       question, and the two together are what the plan carries.
 *
 * @note The failure the scaling bench found arrives here as a prediction. Collision entropy is
 *       permutation invariant. A corpus and its own shuffle carry identical H2, and a bound built
 *       from H2 alone cannot see arrangement. Where a corpus agrees with itself at some
 *       lag, anchors placed anywhere inside a needle test the same congruence, the cascade collapses
 *       to one independent probe, and the bound overstates the filter by exactly 2^((k-1) * H2).
 *
 * @note Worked for a period of sixteen and four anchors: 2^(3 * 4) = 4096. The scaling bench
 *       measures 4096. The point of this driver is that the number is available before the search
 *       from one pass over lags.
 *
 * @warning Corpora are generated. The periodic case here is a clean single orbit, the extreme end
 *          of it. A real corpus carries partial coherence and the collapse is partial with it,
 *          which this driver cannot show and does not claim.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "anchor_sift.h"
#include "bench_corpora.h"

#if !ANCHOR_SIFT_COUNT_READS
#error "bench_coherence counts probes and must link the counted kernel"
#endif

/** @brief Corpus length every reading is taken at. */
#define CORPUS_BYTES 262144u

/** @brief Needles drawn per row. */
#define NEEDLES_PER_ROW 32u

/** @brief Needle length the survivor rate is measured at, comfortably above the periods searched. */
#define NEEDLE_BYTES 64u

/** @brief Seed for every generated corpus. */
#define CORPUS_SEED 0xD7723247ULL

/** @brief Seed for the needles that are not drawn from the corpus. */
#define ABSENT_SEED 0x9E3779B97F4A7C15ULL

/** @brief Corpus kinds swept. */
static const CorpusKind KINDS[] = {CORPUS_UNIFORM, CORPUS_SKEWED, CORPUS_PERIODIC};

/**
 * @brief How many of the placed anchors ask independent questions.
 *
 * @param[in] found   What the period search returned [BORROWS].
 * @param[in] placed  How many anchors the arms place.
 * @return            The count that actually carries information.
 * @note A corpus that repeats at some period is one orbit under translation at that period.
 *       Position p carries a value fixed by p modulo the period. A needle taken at offset s has
 *       needle[o] fixed by (s + o), and an alignment at `at` matches that anchor exactly when
 *       (at + o) and (s + o) agree modulo the period. The offset cancels. Every anchor tests the
 *       same congruence whatever offset it was placed at, and the cascade is one probe deep.
 * @note Where no period is found every anchor is independent and the count is what was placed.
 */
static double independent_anchors(const BenchPeriod *found, double placed)
{
    return (found->period != 0u) ? 1.0 : placed;
}

/**
 * @brief The anchor spacing to use once the period is known.
 *
 * @param[in] found      What the period search returned [BORROWS].
 * @param[in] needle_len Length of the needle the anchors index.
 * @param[in] placed     How many anchors are being placed.
 * @return               A stride in bytes, chosen to land the anchors on distinct residues.
 * @note Reported and not yet acted on. On a clean single orbit no spacing helps, since the offset
 *       cancels out of the test entirely, and the three corpora here hold only that case. A stride
 *       coprime to the period is what a partially coherent corpus would want, and saying so here
 *       marks where the measurement to justify it is missing.
 */
static size_t spacing_for(const BenchPeriod *found, size_t needle_len, size_t placed)
{
    const size_t even = (placed != 0u) ? (needle_len / placed) : needle_len;

    if ((found->period == 0u) || (even == 0u))
    {
        return even;
    }
    // A stride sharing a factor with the period puts every anchor in one residue class, the comb
    // failure the offset rule already avoids by jitter. Stepping to the next coprime
    // stride is the cheapest repair that keeps the anchors spread across the needle.
    size_t stride = even;

    while ((stride < needle_len) && ((stride % found->period) == 0u))
    {
        stride += 1u;
    }
    return stride;
}

/**
 * @brief Two to the power of a real exponent of either sign, without <math.h>.
 *
 * @param[in] exponent The power to raise two to.
 * @return             Two raised to it.
 */
static double two_to_the(double exponent)
{
    double held = 1.0;
    double remaining = exponent;

    while (remaining >= 1.0)
    {
        held *= 2.0;
        remaining -= 1.0;
    }
    while (remaining < 0.0)
    {
        held *= 0.5;
        remaining += 1.0;
    }
    held *= 1.0 + (remaining * 0.6931472) + (remaining * remaining * 0.2402265);
    return held;
}

int main(void)
{
    const size_t kind_count = sizeof KINDS / sizeof KINDS[0];
    uint8_t *const corpus = (uint8_t *)malloc(CORPUS_BYTES);
    uint8_t *const absent = (uint8_t *)malloc(NEEDLE_BYTES * NEEDLES_PER_ROW);

    if ((corpus == NULL) || (absent == NULL))
    {
        // %zu is absent from the C runtime this builds against on Windows, so every size_t printed
        // here is widened and written as %llu.
        (void)fprintf(stderr, "  could not take %llu bytes\n", (unsigned long long)CORPUS_BYTES);
        free(corpus);
        free(absent);
        return 2;
    }

    printf("  Coherence read before the search, at N=%llu with %llu byte needles.\n",
           (unsigned long long)CORPUS_BYTES, (unsigned long long)NEEDLE_BYTES);
    printf("\n  %-12s %-7s %-8s %-9s %-9s %-8s %s\n", "corpus", "h2", "period", "agrees",
           "at chance", "margin", "spacing");

    double predicted_flat[3];
    double predicted_coherent[3];
    double independent[3];
    BenchPeriod held[3];

    for (size_t which = 0u; which < kind_count; which += 1u)
    {
        bench_build_bytes(corpus, CORPUS_BYTES, KINDS[which], CORPUS_SEED);

        size_t distinct = 0u;
        const double entropy = bench_collision_entropy(corpus, CORPUS_BYTES, &distinct);
        const BenchPeriod found = bench_recover_period(corpus, CORPUS_BYTES);
        const double placed = (double)ANCHOR_SIFT_ANCHORS;

        held[which] = found;
        independent[which] = independent_anchors(&found, placed);
        predicted_flat[which] = two_to_the(-placed * entropy);
        predicted_coherent[which] = two_to_the(-independent[which] * entropy);

        char period_text[24];

        if (found.period == 0u)
        {
            (void)snprintf(period_text, sizeof period_text, "none");
        }
        else
        {
            (void)snprintf(period_text, sizeof period_text, "%llu",
                           (unsigned long long)found.period);
        }

        printf("  %-12s %-7.3f %-8s %-9.4f %-9.4f %-8.4f %llu\n", bench_corpus_name(KINDS[which]),
               entropy, period_text, found.agreement, found.at_chance, found.margin,
               (unsigned long long)spacing_for(&found, NEEDLE_BYTES, ANCHOR_SIFT_ANCHORS));
    }

    printf("\n  %-12s %-9s %-15s %-15s %-15s %s\n", "corpus", "anchors", "histogram says",
           "coherence says", "measured", "which one was right");

    int disagreed = 0;

    for (size_t which = 0u; which < kind_count; which += 1u)
    {
        bench_build_bytes(corpus, CORPUS_BYTES, KINDS[which], CORPUS_SEED);
        bench_build_bytes(absent, NEEDLE_BYTES * NEEDLES_PER_ROW, KINDS[which], ABSENT_SEED);

        anchor_sift_counters_reset();

        size_t found_total = 0u;
        size_t reference = 0u;

        for (size_t draw = 0u; draw < NEEDLES_PER_ROW; draw += 1u)
        {
            const uint8_t *const needle = absent + (draw * NEEDLE_BYTES);

            found_total += anchor_sift_inorder(corpus, CORPUS_BYTES, needle, NEEDLE_BYTES);
        }

        // Read before the reference runs. The exact compare verifies at every alignment by
        // definition, so letting it run first adds one verification per alignment to the counter
        // and the survivor rates below come out one higher than they are.
        const uint64_t survivors = anchor_sift_verifications;

        for (size_t draw = 0u; draw < NEEDLES_PER_ROW; draw += 1u)
        {
            const uint8_t *const needle = absent + (draw * NEEDLE_BYTES);

            reference += anchor_sift_naive(corpus, CORPUS_BYTES, needle, NEEDLE_BYTES);
        }
        if (found_total != reference)
        {
            (void)fprintf(stderr, "  %s: %llu against %llu\n", bench_corpus_name(KINDS[which]),
                          (unsigned long long)found_total, (unsigned long long)reference);
            disagreed = 1;
        }

        const double alignments = (double)(CORPUS_BYTES - NEEDLE_BYTES + 1u)
                                  * (double)NEEDLES_PER_ROW;
        const double measured = (double)survivors / alignments;
        const double off_flat = (predicted_flat[which] > 0.0)
            ? (measured / predicted_flat[which]) : 0.0;
        const double off_coherent = (predicted_coherent[which] > 0.0)
            ? (measured / predicted_coherent[which]) : 0.0;

        printf("  %-12s %-9.0f %-15.9f %-15.9f %-15.9f %s\n", bench_corpus_name(KINDS[which]),
               independent[which], predicted_flat[which], predicted_coherent[which], measured,
               (held[which].period != 0u) ? "coherence" : "they agree");
        printf("  %-12s %-9s off the histogram by %.1f, off coherence by %.2f\n", "", "",
               off_flat, off_coherent);
    }

    printf("\n  Where a period is found the histogram overstates the filter by 2^((k-1) * H2),\n");
    printf("  which is what the ratio in the second line comes to. Coherence is one pass over\n");
    printf("  lags and is available before any search, so the miss is computed and not met.\n");

    printf("\n  What setting the anchor count from the recovered size is worth\n");
    printf("  %-12s %-9s %-15s %-15s %-9s %s\n", "corpus", "anchors", "probes/align 4",
           "probes/align k", "saved", "survivors move");

    for (size_t which = 0u; which < kind_count; which += 1u)
    {
        bench_build_bytes(corpus, CORPUS_BYTES, KINDS[which], CORPUS_SEED);
        bench_build_bytes(absent, NEEDLE_BYTES * NEEDLES_PER_ROW, KINDS[which], ABSENT_SEED);

        size_t distinct = 0u;
        const double entropy = bench_collision_entropy(corpus, CORPUS_BYTES, &distinct);
        const AnchorSiftPlan plan = {entropy, distinct, NEEDLE_BYTES, held[which].period};
        const AnchorSiftPlan flat_plan = {entropy, distinct, NEEDLE_BYTES, 0u};
        const double alignments = (double)(CORPUS_BYTES - NEEDLE_BYTES + 1u)
                                  * (double)NEEDLES_PER_ROW;

        anchor_sift_counters_reset();
        for (size_t draw = 0u; draw < NEEDLES_PER_ROW; draw += 1u)
        {
            (void)anchor_sift_run(&flat_plan, corpus, CORPUS_BYTES, absent + (draw * NEEDLE_BYTES),
                                  NEEDLE_BYTES);
        }
        const double probes_four = (double)anchor_sift_probes / alignments;
        const double survivors_four = (double)anchor_sift_verifications / alignments;

        anchor_sift_counters_reset();
        for (size_t draw = 0u; draw < NEEDLES_PER_ROW; draw += 1u)
        {
            (void)anchor_sift_run(&plan, corpus, CORPUS_BYTES, absent + (draw * NEEDLE_BYTES),
                                  NEEDLE_BYTES);
        }
        const double probes_chosen = (double)anchor_sift_probes / alignments;
        const double survivors_chosen = (double)anchor_sift_verifications / alignments;

        printf("  %-12s %-9llu %-15.6f %-15.6f %-9.1f%% %s\n", bench_corpus_name(KINDS[which]),
               (unsigned long long)anchor_sift_anchors_for(&plan), probes_four, probes_chosen,
               (probes_four > 0.0) ? (100.0 * (probes_four - probes_chosen) / probes_four) : 0.0,
               (survivors_four == survivors_chosen) ? "not at all" : "they moved");
    }

    printf("  Survivors have to stay put. The anchors dropped were refuting nothing, so dropping\n");
    printf("  them may not let one alignment through that four anchors held back.\n");

    free(corpus);
    free(absent);
    return disagreed;
}
