/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_ancorae_cycles.c
 * @brief Times every kernel arm on every corpus, and grades the dispatcher against the winner.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-04
 *
 * @note The driver. It builds corpora, reads the clock, calls the kernel and prints rows. No search
 *       happens in this file, so a change here cannot move a measurement.
 * @note The second table is the one the meta algorithm rests on. Choosing an arm is worth doing only
 *       where the choice agrees with what the clock says, and that agreement is measured here.
 * @note Corpora are SHA-256 in counter mode, mapped where a skewed distribution is wanted, so every
 *       byte is reproducible from the seed and no corpus file is needed.
 * @warning Cycle counts belong to the machine that produced them. The ratio between two arms travels
 *          and the absolute count does not.
 */

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

/** @brief Bytes in each corpus measured. */
#define CORPUS_BYTES 65536u

/** @brief Needle lengths swept, powers of two around the effective alphabet. */
static const size_t NEEDLE_LENGTHS[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

/** @brief Needles drawn per row. Each comes from the corpus, so each has a genuine occurrence. */
#define NEEDLES_PER_ROW 64u

/** @brief Times one row this many times and reports the smallest, which rejects scheduler noise. */
#define TIMED_TRIALS 7u

/**
 * @brief Reads the cycle counter, or a monotonic substitute where the part has none.
 *
 * @return A count that rises with time, in cycles where the host supplies them.
 */
static uint64_t cycles_now(void)
{
#if CYCLES_ARE_REAL
    /* Ordering deviation: __rdtsc may be reordered against the work being timed. The barriers keep
     * one arm's loads and stores from crossing them, which is what makes the difference between two
     * reads attributable to that arm. */
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

/**
 * @brief Fills a corpus with SHA-256 in counter mode.
 *
 * @param[out] corpus Where the bytes are written [BORROWS].
 * @param[in]  length How many to write.
 * @param[in]  seed   Counter start, which selects the corpus.
 */
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

/**
 * @brief Maps a uniform corpus onto a skewed alphabet, landing collision entropy near English.
 *
 * @param[in,out] corpus Bytes to remap in place [BORROWS].
 * @param[in]     length How many.
 * @note A geometric weighting over 27 symbols. It is a distribution and carries no arrangement, so
 *       an arm reading only the histogram cannot tell it from English.
 */
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

/**
 * @brief Fills a corpus with a period of sixteen.
 *
 * @param[out] corpus Where the bytes are written [BORROWS].
 * @param[in]  length How many to write.
 */
static void fill_periodic(uint8_t *corpus, size_t length)
{
    for (size_t at = 0u; at < length; at += 1u)
    {
        corpus[at] = (uint8_t)(at % 16u);
    }
}

/**
 * @brief Measures collision entropy and how many byte values a corpus uses.
 *
 * @param[in]  corpus   Bytes to measure [BORROWS].
 * @param[in]  length   How many.
 * @param[out] distinct Where the count of used byte values is written [BORROWS].
 * @return              H2 in bits.
 * @note One pass over a histogram, which is what makes the dispatch decision cheap enough to take.
 */
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

/** @brief One arm under test: what to call it and what to call. */
typedef struct
{
    const char *name;
    AnchorSiftArm run;
} Arm;

/** @brief One corpus under test: what to call it and how it is filled. */
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

            /* Every needle is drawn from the corpus, so every search confirms a genuine occurrence
             * and pays the needle_len read verification floor. That floor is why the arms converge
             * as the needle grows. */
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

            /* What the dispatcher picks, against what the clock says was quickest. The cost of a
             * wrong pick is the ratio between them, and a dispatcher that rarely picks the fastest
             * is not worth having however cheap its inputs are. */
            const AnchorSiftPlan plan = {
                .collision_entropy = entropy,
                .distinct_symbols = distinct,
                .needle_len = needle_len,
            };
            const AnchorSiftArm chosen = anchor_sift_choose(&plan);

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
                   needle_len, entropy, distinct, anchor_sift_arm_name(chosen), ARMS[fastest].name,
                   timed[picked], timed[fastest], timed[picked] / timed[fastest]);
        }
    }

    return disagreed;
}
