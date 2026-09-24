// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "anchor_sift.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define BENCH_NEEDLE_LEN 16u
#define BENCH_CANDIDATES ANCHOR_STEER_ANCHORS
#define BENCH_MIN_MILLISECONDS 60.0
#define BENCH_MAX_RUNS 2000u

static const size_t candidate_offsets[BENCH_CANDIDATES] = {0u, 4u, 8u, 12u};

typedef struct
{
    const uint32_t *corpus;
    const uint32_t *needle;
} BenchSymbolField;

static int bench_same_symbol(const void *field, size_t corpus_at, size_t needle_at)
{
    const BenchSymbolField *const pair = (const BenchSymbolField *)field;
    return (pair->corpus[corpus_at] == pair->needle[needle_at]) ? 1 : 0;
}

static uint64_t bench_rng_state = 88172645463325252ull;

static uint32_t bench_next_random(void)
{
    bench_rng_state ^= bench_rng_state << 13;
    bench_rng_state ^= bench_rng_state >> 7;
    bench_rng_state ^= bench_rng_state << 17;
    return (uint32_t)(bench_rng_state >> 11);
}

static double bench_elapsed_milliseconds(clock_t since)
{
    return (double)(clock() - since) * 1000.0 / (double)CLOCKS_PER_SEC;
}

static int bench_table_once(const uint32_t *corpus, size_t corpus_len, const uint32_t *needle,
                            size_t sigma, size_t *order_out)
{
    uint32_t *const counts = (uint32_t *)calloc(sigma, sizeof(uint32_t));

    if (counts == NULL)
    {
        return 0;
    }
    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        counts[corpus[at]] += 1u;
    }

    int taken[BENCH_CANDIDATES];

    memset(taken, 0, sizeof taken);
    for (size_t place = 0u; place < BENCH_CANDIDATES; place += 1u)
    {
        size_t rarest = BENCH_CANDIDATES;

        for (size_t candidate = 0u; candidate < BENCH_CANDIDATES; candidate += 1u)
        {
            if (taken[candidate] != 0)
            {
                continue;
            }
            if ((rarest == BENCH_CANDIDATES) || (counts[needle[candidate_offsets[candidate]]] < counts[needle[candidate_offsets[rarest]]]))
            {
                rarest = candidate;
            }
        }
        taken[rarest] = 1;
        order_out[place] = candidate_offsets[rarest];
    }
    free(counts);
    return 1;
}

static size_t bench_oracle_once(const uint32_t *corpus, size_t corpus_len, const uint32_t *needle,
                                size_t *order_out, uint8_t *survivors)
{
    const size_t alignments = (corpus_len - BENCH_NEEDLE_LEN) + 1u;

    for (size_t candidate = 0u; candidate < BENCH_CANDIDATES; candidate += 1u)
    {
        order_out[candidate] = candidate_offsets[candidate];
    }

    const BenchSymbolField pair = {corpus, needle};
    const AnchorField any = {
        .same = bench_same_symbol,
        .field = &pair,
        .alignments = alignments,
        .needle_len = BENCH_NEEDLE_LEN};

    const AnchorSteerDescent args = {
        .offsets = order_out,
        .count = BENCH_CANDIDATES,
        .survivors = survivors,
        .survivors_length = alignments,
        .any = &any};

    return anchor_steer_plan_recursive(&args);
}

static double bench_time_table(const uint32_t *corpus, size_t corpus_len, const uint32_t *needle,
                               size_t sigma, size_t *order_out)
{
    const clock_t start = clock();
    size_t runs = 0u;

    while (bench_elapsed_milliseconds(start) < BENCH_MIN_MILLISECONDS)
    {
        if (bench_table_once(corpus, corpus_len, needle, sigma, order_out) == 0)
        {
            return -1.0;
        }
        runs += 1u;
        if (runs >= BENCH_MAX_RUNS)
        {
            break;
        }
    }
    return bench_elapsed_milliseconds(start) / (double)runs;
}

static double bench_time_oracle(const uint32_t *corpus, size_t corpus_len, const uint32_t *needle,
                                size_t *order_out, uint8_t *survivors, size_t *placed_out)
{
    const clock_t start = clock();
    size_t runs = 0u;

    while (bench_elapsed_milliseconds(start) < BENCH_MIN_MILLISECONDS)
    {
        *placed_out = bench_oracle_once(corpus, corpus_len, needle, order_out, survivors);
        runs += 1u;
        if (runs >= BENCH_MAX_RUNS)
        {
            break;
        }
    }
    return bench_elapsed_milliseconds(start) / (double)runs;
}

static void bench_fill(uint32_t *corpus, size_t corpus_len, size_t sigma, uint32_t *needle,
                       size_t needle_from)
{
    for (size_t at = 0u; at < corpus_len; at += 1u)
    {
        corpus[at] = bench_next_random() % (uint32_t)sigma;
    }
    for (size_t offset = 0u; offset < BENCH_NEEDLE_LEN; offset += 1u)
    {
        needle[offset] = corpus[needle_from + offset];
    }
}

int main(void)
{
    const size_t corpus_cap = 1u << 17;
    uint32_t *const corpus = (uint32_t *)malloc(corpus_cap * sizeof(uint32_t));
    uint8_t *const survivors = (uint8_t *)malloc(corpus_cap);
    uint32_t needle[BENCH_NEEDLE_LEN];
    size_t order[BENCH_CANDIDATES];

    if ((corpus == NULL) || (survivors == NULL))
    {
        printf("  allocation refused, nothing measured\n");
        free(corpus);
        free(survivors);
        return 1;
    }

    printf("  corpus %zu symbols of 4 bytes, needle %u, %u candidates ordered by rarity on both\n",
           corpus_cap, BENCH_NEEDLE_LEN, BENCH_CANDIDATES);
    printf("  routes. Milliseconds are per iteration, repeated to at least %.0fms.\n\n",
           BENCH_MIN_MILLISECONDS);

    printf("  alphabet grows, corpus fixed at %zu\n", corpus_cap);
    printf("  %-10s %-12s %-14s %-12s %-14s %s\n",
           "sigma", "table ms", "table bytes", "oracle ms", "oracle bytes", "placed");

    static const unsigned int shifts[] = {8u, 12u, 16u, 20u, 22u, 24u};

    for (size_t which = 0u; which < sizeof shifts / sizeof shifts[0]; which += 1u)
    {
        const size_t sigma = (size_t)1u << shifts[which];

        bench_fill(corpus, corpus_cap, sigma, needle, 1000u);

        const double table_ms = bench_time_table(corpus, corpus_cap, needle, sigma, order);
        size_t placed = 0u;
        const double oracle_ms = bench_time_oracle(corpus, corpus_cap, needle, order, survivors,
                                                   &placed);

        printf("  2^%-8u %-12.3f %-14zu %-12.3f %-14zu %zu\n",
               shifts[which], table_ms, sigma * sizeof(uint32_t), oracle_ms,
               (corpus_cap - BENCH_NEEDLE_LEN) + 1u, placed);
    }

    printf("\n  A four byte symbol over its whole range is NOT MEASURED here. The table would want\n");
    printf("  %.1f GB of counters at four bytes a slot. The oracle column does not move, because\n",
           (double)(1ull << 32) * 4.0 / 1073741824.0);
    printf("  nothing in it is indexed by a symbol.\n\n");

    printf("  corpus grows, alphabet fixed at 2^16\n");
    printf("  %-10s %-12s %-14s %-12s %-14s %s\n",
           "corpus", "table ms", "table bytes", "oracle ms", "oracle bytes", "placed");

    static const size_t lengths[] = {4096u, 16384u, 65536u, 131072u};
    const size_t sigma_fixed = 1u << 16;

    for (size_t which = 0u; which < sizeof lengths / sizeof lengths[0]; which += 1u)
    {
        const size_t corpus_len = lengths[which];

        bench_fill(corpus, corpus_len, sigma_fixed, needle, 100u);

        const double table_ms = bench_time_table(corpus, corpus_len, needle, sigma_fixed, order);
        size_t placed = 0u;
        const double oracle_ms = bench_time_oracle(corpus, corpus_len, needle, order, survivors,
                                                   &placed);

        printf("  %-10zu %-12.3f %-14zu %-12.3f %-14zu %zu\n",
               corpus_len, table_ms, sigma_fixed * sizeof(uint32_t), oracle_ms,
               (corpus_len - BENCH_NEEDLE_LEN) + 1u, placed);
    }

    free(corpus);
    free(survivors);
    return 0;
}
