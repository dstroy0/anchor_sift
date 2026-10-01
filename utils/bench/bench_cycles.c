// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "anchor_sift.h"
#include "mmgr_sha256.h"

#if defined(__x86_64__) || defined(__i386__)
#include <x86intrin.h>
#define CYCLES_ARE_REAL 1
#else
#include <time.h>
#define CYCLES_ARE_REAL 0
#endif

#define CORPUS_BYTES 65536u

static const size_t NEEDLE_LENGTHS[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

#define NEEDLES_PER_ROW 64u

#define TIMED_TRIALS 7u

static uint64_t cycles_now(void)
{
#if CYCLES_ARE_REAL
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

static void fill_uniform(uint8_t *corpus, size_t length, uint32_t seed)
{
    uint8_t digest[MMGR_SHA256_BYTES];
    uint8_t counter[8];
    size_t written = 0u;
    uint32_t step = 0u;

    while (written < length)
    {
        for (size_t slot = 0u; slot < 4u; slot += 1u)
        {
            counter[slot] = (uint8_t)((seed >> (8u * slot)) & 0xFFu);
            counter[slot + 4u] = (uint8_t)((step >> (8u * slot)) & 0xFFu);
        }
        mmgr_sha256(counter, sizeof counter, digest);

        size_t taking = length - written;
        if (taking > MMGR_SHA256_BYTES)
        {
            taking = MMGR_SHA256_BYTES;
        }
        memcpy(corpus + written, digest, taking);
        written += taking;
        step += 1u;
    }
}

static void fill_skewed(uint8_t *corpus, size_t length)
{
    uint8_t table[256];
    size_t filled = 0u;
    uint8_t symbol = 0u;

    while ((filled < sizeof table) && (symbol < 27u))
    {
        size_t width = (sizeof table - filled) / 2u;
        if (width == 0u)
        {
            width = 1u;
        }
        if ((filled + width) > sizeof table)
        {
            width = sizeof table - filled;
        }
        memset(table + filled, (int)('a' + symbol), width);
        filled += width;
        symbol += 1u;
    }
    while (filled < sizeof table)
    {
        table[filled] = (uint8_t)' ';
        filled += 1u;
    }
    for (size_t at = 0u; at < length; at += 1u)
    {
        corpus[at] = table[corpus[at]];
    }
}

static void fill_periodic(uint8_t *corpus, size_t length)
{
    for (size_t at = 0u; at < length; at += 1u)
    {
        corpus[at] = (uint8_t)(at % 16u);
    }
}

static double collision_entropy(const uint8_t *corpus, size_t length, size_t *distinct)
{
    size_t counts[256] = {0};
    double squared = 0.0;
    size_t used = 0u;

    for (size_t at = 0u; at < length; at += 1u)
    {
        counts[corpus[at]] += 1u;
    }
    for (size_t slot = 0u; slot < 256u; slot += 1u)
    {
        if (counts[slot] != 0u)
        {
            const double share = (double)counts[slot] / (double)length;
            squared += share * share;
            used += 1u;
        }
    }
    *distinct = used;
    return -log2(squared);
}

typedef struct
{
    const char *name;
    AnchorSiftEngine run;
} Arm;

typedef struct
{
    const char *name;
    void (*fill)(uint8_t *corpus, size_t length);
} Corpus;

static void corpus_uniform(uint8_t *corpus, size_t length)
{
    fill_uniform(corpus, length, 0xD7723247u);
}

static void corpus_skewed(uint8_t *corpus, size_t length)
{
    fill_uniform(corpus, length, 0xD7723247u);
    fill_skewed(corpus, length);
}

static void corpus_periodic(uint8_t *corpus, size_t length)
{
    fill_periodic(corpus, length);
}

int main(void)
{
    static uint8_t corpus[CORPUS_BYTES];
    static const Arm ARMS[] = {
        {"naive", anchor_sift_naive},
        {"horspool", anchor_sift_horspool},
        {"anchor_inorder", anchor_sift_inorder},
        {"anchor_free", anchor_sift_free},
    };
    static const Corpus CORPORA[] = {
        {"skewed", corpus_skewed},
        {"uniform", corpus_uniform},
        {"periodic16", corpus_periodic},
    };
    const size_t arm_count = sizeof ARMS / sizeof ARMS[0];
    const size_t corpus_count = sizeof CORPORA / sizeof CORPORA[0];
    const size_t length_count = sizeof NEEDLE_LENGTHS / sizeof NEEDLE_LENGTHS[0];
    double timed[sizeof ARMS / sizeof ARMS[0]];
    int disagreed = 0;

    printf("bench,corpus,needle_len,corpus_bytes,arm,cycles_per_search,cycles_per_byte,found,agree\n");
    printf("bench,corpus,needle_len,h2,distinct,chosen,fastest,chosen_cycles,fastest_cycles,cost\n");

    for (size_t which = 0u; which < corpus_count; which += 1u)
    {
        CORPORA[which].fill(corpus, CORPUS_BYTES);

        size_t distinct = 0u;
        const double entropy = collision_entropy(corpus, CORPUS_BYTES, &distinct);

        for (size_t step = 0u; step < length_count; step += 1u)
        {
            const size_t needle_len = NEEDLE_LENGTHS[step];
            size_t starts[NEEDLES_PER_ROW];
            size_t reference = 0u;

            for (size_t pick = 0u; pick < NEEDLES_PER_ROW; pick += 1u)
            {
                starts[pick] = (pick * 977u) % (CORPUS_BYTES - needle_len);
                reference += anchor_sift_naive(corpus, CORPUS_BYTES, corpus + starts[pick], needle_len);
            }

            for (size_t slot = 0u; slot < arm_count; slot += 1u)
            {
                uint64_t best = UINT64_MAX;
                size_t total_found = 0u;

                for (size_t trial = 0u; trial < TIMED_TRIALS; trial += 1u)
                {
                    const uint64_t opened = cycles_now();
                    size_t seen = 0u;

                    for (size_t pick = 0u; pick < NEEDLES_PER_ROW; pick += 1u)
                    {
                        seen += ARMS[slot].run(corpus, CORPUS_BYTES, corpus + starts[pick], needle_len);
                    }

                    const uint64_t closed = cycles_now();
                    if ((closed - opened) < best)
                    {
                        best = closed - opened;
                    }
                    total_found = seen;
                }

                const int matched = (total_found == reference);
                if (!matched)
                {
                    disagreed = 1;
                }

                timed[slot] = (double)best / (double)NEEDLES_PER_ROW;
                printf("ancorae_cycles,%s,%zu,%u,%s,%.1f,%.4f,%zu,%s\n", CORPORA[which].name,
                       needle_len, (unsigned)CORPUS_BYTES, ARMS[slot].name, timed[slot],
                       timed[slot] / (double)CORPUS_BYTES, total_found,
                       matched ? "agree" : "DIFFER");
            }

            AnchorFieldCensus census;
            anchor_field_census(corpus, CORPUS_BYTES, &census);
            const AnchorSiftPlan plan = {
                .census = &census,
                .needle_len = needle_len,
            };
            const AnchorSiftEngine chosen = anchor_sift_choose(&plan);

            size_t fastest = 0u;
            size_t picked = 0u;
            for (size_t slot = 1u; slot < arm_count; slot += 1u)
            {
                if (timed[slot] < timed[fastest])
                {
                    fastest = slot;
                }
            }
            for (size_t slot = 0u; slot < arm_count; slot += 1u)
            {
                if (ARMS[slot].run == chosen)
                {
                    picked = slot;
                }
            }

            printf("ancorae_dispatch,%s,%zu,%.4f,%zu,%s,%s,%.1f,%.1f,%.3f\n", CORPORA[which].name,
                   needle_len, entropy, distinct, anchor_sift_engine_name(chosen), ARMS[fastest].name,
                   timed[picked], timed[fastest], timed[picked] / timed[fastest]);
        }
    }

    return disagreed;
}
