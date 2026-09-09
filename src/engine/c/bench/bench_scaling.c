/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_scaling.c
 * @brief Measures what the sift costs per alignment as the corpus grows, against the predicted rate.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The driver. It builds corpora, counts or times, calls the kernel and prints rows. No search
 *       happens in this file. A change here cannot move a measurement.
 * @note The bench this replaces compared the sift with Boyer-Moore-Horspool on a byte line.
 *       Horspool needs an ordered index set and a shift table the size of the alphabet, and the
 *       sift needs neither, so that comparison ran on Horspool's own ground in the one domain where
 *       discarding order buys nothing. It measured a case the construction is positioned to lose and
 *       left the case it exists for unmeasured. The only reference arm here is the exact compare,
 *       and it serves as the soundness oracle. It was not entered as a competitor.
 * @note Two questions are kept apart because their answers behave differently. A needle drawn from
 *       the corpus is present, so every search confirms a genuine occurrence and pays a verification
 *       whatever the filter did, and that floor is why arms converge as the needle grows. A needle
 *       drawn from an independent stream is almost never present. That case is the stated problem,
 *       a pattern of arbitrary width that the domain does not hold. With no occurrence there is no
 *       floor, and the filter is measured on its own.
 * @note Reads travel and cycles do not. A count of probes is a property of the algorithm and the
 *       distribution; a count of cycles belongs to the machine that produced it. Both are here and
 *       they come from separate builds, since counting perturbs the timing it would sit beside.
 * @warning Corpora are generated, not fetched. A generated corpus carries a distribution and no
 *          arrangement, so nothing here bears on a measure that reads arrangement.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "anchor_sift.h"
#include "bench_corpora.h"

#if !ANCHOR_SIFT_COUNT_READS
#if defined(__x86_64__) || defined(__i386__)
#include <x86intrin.h>
#define CYCLES_ARE_REAL 1
#else
#include <time.h>
#define CYCLES_ARE_REAL 0
#endif
#endif

/** @brief Corpus lengths swept, wide enough to watch the per alignment cost for drift as N grows. */
static const size_t CORPUS_LENGTHS[] = {
    4096u, 16384u, 65536u, 262144u, 1048576u, 4194304u
};

/**
 * @brief Needles drawn per row, the same count at every corpus length.
 *
 * @note An earlier arrangement scaled this down as N grew, to hold the work per row constant. That
 *       confounded the two things the sweep exists to separate. The quantity measured is per
 *       alignment and should not depend on N, and a drift in it is the finding. But the
 *       needle to needle spread on a skewed corpus is heavy tailed, and a row resting on four
 *       needles at the top of the sweep and sixty four at the bottom moves for that reason alone.
 *       It read as a factor of 2.5 fall in the candidate rate that was entirely the sample size.
 *       The count is fixed here and the runtime is paid instead.
 */
#define NEEDLES_PER_ROW 32u

/** @brief Needle lengths swept, spanning the effective alphabet in both directions. */
static const size_t NEEDLE_LENGTHS[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

/** @brief Times one row this many times and keeps the smallest, which rejects scheduler noise. */
#define TIMED_TRIALS 5u

/** @brief Seed for every generated corpus, keeping a row reproducible from this file alone. */
#define CORPUS_SEED 0xD7723247ULL

/** @brief Seed for the needles that are not drawn from the corpus. */
#define ABSENT_SEED 0x9E3779B97F4A7C15ULL

#if !ANCHOR_SIFT_COUNT_READS
/**
 * @brief Reads the cycle counter, or a monotonic substitute where the part has none.
 *
 * @return A count that rises with time, in cycles where the host supplies them.
 */
static uint64_t cycles_now(void)
{
#if CYCLES_ARE_REAL
    // Ordering deviation: __rdtsc may be reordered relative to the work being timed. The barriers
    // keep one arm's loads and stores from crossing them.
    __asm__ __volatile__("" ::: "memory");
    const uint64_t taken = (uint64_t)__rdtsc();
    __asm__ __volatile__("" ::: "memory");
    return taken;
#else
    struct timespec taken;

    (void)clock_gettime(CLOCK_MONOTONIC, &taken);
    return ((uint64_t)taken.tv_sec * 1000000000ULL) + (uint64_t)taken.tv_nsec;
#endif
}
#endif

/** @brief One arm under test. */
typedef struct
{
    const char *name;
    AnchorSiftArm run;
} Arm;

int main(void)
{
    static const Arm ARMS[] = {
        {"exact_compare", anchor_sift_naive},
        {"anchor_inorder", anchor_sift_inorder},
        {"anchor_free", anchor_sift_free},
    };
    static const CorpusKind KINDS[] = {CORPUS_UNIFORM, CORPUS_SKEWED, CORPUS_PERIODIC};

    const size_t arm_count = sizeof ARMS / sizeof ARMS[0];
    const size_t kind_count = sizeof KINDS / sizeof KINDS[0];
    const size_t length_count = sizeof CORPUS_LENGTHS / sizeof CORPUS_LENGTHS[0];
    const size_t needle_count = sizeof NEEDLE_LENGTHS / sizeof NEEDLE_LENGTHS[0];
    const size_t longest = CORPUS_LENGTHS[length_count - 1u];

    uint8_t *const corpus = (uint8_t *)malloc(longest);
    uint8_t *const absent = (uint8_t *)malloc(NEEDLE_LENGTHS[needle_count - 1u] * NEEDLES_PER_ROW);
    int disagreed = 0;

    if ((corpus == NULL) || (absent == NULL))
    {
        // %zu is absent from the C runtime this builds against on Windows, so every size_t printed
        // here is widened and written as %llu. The cast is to the type the format names.
        (void)fprintf(stderr, "  could not take %llu bytes for the longest corpus\n",
                      (unsigned long long)longest);
        free(corpus);
        free(absent);
        return 2;
    }
    const size_t absent_bytes = NEEDLE_LENGTHS[needle_count - 1u] * NEEDLES_PER_ROW;

#if ANCHOR_SIFT_COUNT_READS
    printf("bench,corpus,corpus_bytes,needle_len,present,arm,h2,distinct,"
           "probes_per_alignment,verifications_per_alignment,predicted_rate,found\n");
#else
    printf("bench,corpus,corpus_bytes,needle_len,present,arm,h2,distinct,"
           "cycles_per_alignment,predicted_rate,found\n");
#endif

    for (size_t which = 0u; which < kind_count; which += 1u)
    {
        for (size_t step = 0u; step < length_count; step += 1u)
        {
            const size_t corpus_len = CORPUS_LENGTHS[step];

            bench_build_bytes(corpus, corpus_len, KINDS[which], CORPUS_SEED);
            // The same distribution from another stream. A periodic corpus is the case where this
            // cannot produce an absent needle, since a corpus of period sixteen holds every
            // window its own distribution can make, and the occurrence count printed on the row
            // shows it.
            bench_build_bytes(absent, absent_bytes, KINDS[which], ABSENT_SEED);

            size_t distinct = 0u;
            const double entropy = bench_collision_entropy(corpus, corpus_len, &distinct);
            const double rate = bench_predicted_rate(entropy, (double)ANCHOR_SIFT_ANCHORS);

            for (size_t pick = 0u; pick < needle_count; pick += 1u)
            {
                const size_t needle_len = NEEDLE_LENGTHS[pick];

                if (needle_len >= (corpus_len / 4u))
                {
                    // A needle that is a noticeable share of the corpus admits no reading of how the
                    // cost behaves as the corpus grows, and that is the only question here.
                    continue;
                }

                const size_t alignments = corpus_len - needle_len + 1u;

                const size_t needles = NEEDLES_PER_ROW;

                for (unsigned present = 0u; present <= 1u; present += 1u)
                {
                    size_t reference = 0u;

                    for (size_t draw = 0u; draw < needles; draw += 1u)
                    {
                        const uint8_t *const needle = (present != 0u)
                            ? (corpus + ((draw * 977u) % (corpus_len - needle_len)))
                            : (absent + (draw * needle_len));

                        reference += anchor_sift_naive(corpus, corpus_len, needle, needle_len);
                    }

                    for (size_t slot = 0u; slot < arm_count; slot += 1u)
                    {
                        size_t found = 0u;

#if ANCHOR_SIFT_COUNT_READS
                        anchor_sift_counters_reset();
                        for (size_t draw = 0u; draw < needles; draw += 1u)
                        {
                            const uint8_t *const needle = (present != 0u)
                                ? (corpus + ((draw * 977u) % (corpus_len - needle_len)))
                                : (absent + (draw * needle_len));

                            found += ARMS[slot].run(corpus, corpus_len, needle, needle_len);
                        }
                        const double spread = (double)alignments * (double)needles;

                        printf("sift_scaling,%s,%llu,%llu,%u,%s,%.4f,%llu,%.6f,%.6f,%.9f,%llu\n",
                               bench_corpus_name(KINDS[which]), (unsigned long long)corpus_len,
                               (unsigned long long)needle_len, present, ARMS[slot].name, entropy,
                               (unsigned long long)distinct,
                               (double)anchor_sift_probes / spread,
                               (double)anchor_sift_verifications / spread, rate,
                               (unsigned long long)found);
#else
                        uint64_t best = UINT64_MAX;

                        for (size_t trial = 0u; trial < TIMED_TRIALS; trial += 1u)
                        {
                            const uint64_t opened = cycles_now();
                            size_t seen = 0u;

                            for (size_t draw = 0u; draw < needles; draw += 1u)
                            {
                                const uint8_t *const needle = (present != 0u)
                                    ? (corpus + ((draw * 977u) % (corpus_len - needle_len)))
                                    : (absent + (draw * needle_len));

                                seen += ARMS[slot].run(corpus, corpus_len, needle, needle_len);
                            }

                            const uint64_t closed = cycles_now();

                            if ((closed - opened) < best)
                            {
                                best = closed - opened;
                            }
                            found = seen;
                        }
                        const double spread = (double)alignments * (double)needles;

                        printf("sift_scaling,%s,%llu,%llu,%u,%s,%.4f,%llu,%.6f,%.9f,%llu\n",
                               bench_corpus_name(KINDS[which]), (unsigned long long)corpus_len,
                               (unsigned long long)needle_len, present, ARMS[slot].name, entropy,
                               (unsigned long long)distinct, (double)best / spread, rate,
                               (unsigned long long)found);
#endif

                        if (found != reference)
                        {
                            // Soundness says no arm can lose a true occurrence. A disagreement is
                            // therefore a defect and not a tradeoff. The run fails here instead of
                            // printing a row somebody might quote.
                            (void)fprintf(stderr,
                                          "  %s on %s at N=%llu m=%llu present=%u: "
                                          "%llu against %llu\n",
                                          ARMS[slot].name, bench_corpus_name(KINDS[which]),
                                          (unsigned long long)corpus_len,
                                          (unsigned long long)needle_len, present,
                                          (unsigned long long)found,
                                          (unsigned long long)reference);
                            disagreed = 1;
                        }
                    }
                }
            }
        }
    }

    free(corpus);
    free(absent);
    return disagreed;
}
