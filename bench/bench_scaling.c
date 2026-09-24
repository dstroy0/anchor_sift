// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
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
#elif defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
#include <intrin.h>
#define CYCLES_ARE_REAL 1
#else
#include <time.h>
#define CYCLES_ARE_REAL 0
#endif
#endif

static const size_t CORPUS_LENGTHS[] = {
    4096u, 16384u, 65536u, 262144u, 1048576u, 4194304u};

#define NEEDLES_PER_ROW 32u

static const size_t NEEDLE_LENGTHS[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

#define TIMED_TRIALS 5u

#define CORPUS_SEED 0xD7723247ULL

#define ABSENT_SEED 0x9E3779B97F4A7C15ULL

#if !ANCHOR_SIFT_COUNT_READS
static uint64_t cycles_now(void)
{
#if CYCLES_ARE_REAL
#if defined(_MSC_VER)
    _ReadWriteBarrier();
    const uint64_t taken = (uint64_t)__rdtsc();
    _ReadWriteBarrier();
    return taken;
#else
    __asm__ __volatile__("" ::: "memory");
    const uint64_t taken = (uint64_t)__rdtsc();
    __asm__ __volatile__("" ::: "memory");
    return taken;
#endif
#else
    struct timespec taken;

    (void)clock_gettime(CLOCK_MONOTONIC, &taken);
    return ((uint64_t)taken.tv_sec * 1000000000ULL) + (uint64_t)taken.tv_nsec;
#endif
}
#endif

typedef struct
{
    const char *name;
    AnchorSiftEngine run;
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
            bench_build_bytes(absent, absent_bytes, KINDS[which], ABSENT_SEED);

            size_t distinct = 0u;
            const double entropy = bench_collision_entropy(corpus, corpus_len, &distinct);
            const double rate = bench_predicted_rate(entropy, (double)ANCHOR_SIFT_ANCHORS);

            for (size_t pick = 0u; pick < needle_count; pick += 1u)
            {
                const size_t needle_len = NEEDLE_LENGTHS[pick];

                if (needle_len >= (corpus_len / 4u))
                {
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
