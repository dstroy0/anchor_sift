// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "anchor_sift.h"
#include "bench_corpora.h"

#if !ANCHOR_SIFT_COUNT_READS
#error "bench_coherence counts probes and must link the counted kernel"
#endif

#define CORPUS_BYTES 262144u

#define NEEDLES_PER_ROW 32u

#define NEEDLE_BYTES 64u

#define CORPUS_SEED 0xD7723247ULL

#define ABSENT_SEED 0x9E3779B97F4A7C15ULL

static const CorpusKind KINDS[] = {CORPUS_UNIFORM, CORPUS_SKEWED, CORPUS_PERIODIC};

static double independent_anchors(const BenchPeriod *found, double placed)
{
    return (found->period != 0u) ? 1.0 : placed;
}

static size_t spacing_for(const BenchPeriod *found, size_t needle_len, size_t placed)
{
    const size_t even = (placed != 0u) ? (needle_len / placed) : needle_len;

    if ((found->period == 0u) || (even == 0u))
    {
        return even;
    }
    size_t stride = even;

    while ((stride < needle_len) && ((stride % found->period) == 0u))
    {
        stride += 1u;
    }
    return stride;
}

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
    printf("  lags and is available before any search. The miss is computed and not met.\n");

    printf("\n  What setting the anchor count from the recovered size is worth\n");
    printf("  %-12s %-9s %-15s %-15s %-9s %s\n", "corpus", "anchors", "probes/align 4",
           "probes/align k", "saved", "survivors move");

    for (size_t which = 0u; which < kind_count; which += 1u)
    {
        bench_build_bytes(corpus, CORPUS_BYTES, KINDS[which], CORPUS_SEED);
        bench_build_bytes(absent, NEEDLE_BYTES * NEEDLES_PER_ROW, KINDS[which], ABSENT_SEED);

        AnchorFieldCensus census;
        anchor_field_census(corpus, CORPUS_BYTES, &census);
        const AnchorSiftPlan plan = {&census, NEEDLE_BYTES, held[which].period};
        const AnchorSiftPlan flat_plan = {&census, NEEDLE_BYTES, 0u};
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

    printf("  Survivors have to stay put. The anchors dropped were refuting nothing. Dropping\n");
    printf("  them may not let one alignment through that four anchors held back.\n");

    free(corpus);
    free(absent);
    return disagreed;
}
