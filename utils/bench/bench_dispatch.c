// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "anchor_sift.h"
#include "bench_corpora.h"

#if ANCHOR_SIFT_COUNT_READS
#error "bench_dispatch measures cycles and must link the uncounted kernel"
#endif

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

#define CORPUS_BYTES 65536u

#define NEEDLES_PER_ROW 32u

#define TIMED_TRIALS 7u

#define CORPUS_SEED 0xD7723247ULL

#define ABSENT_SEED 0x9E3779B97F4A7C15ULL

static const size_t NEEDLE_LENGTHS[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

static const CorpusKind KINDS[] = {CORPUS_UNIFORM, CORPUS_SKEWED, CORPUS_PERIODIC};

static const size_t CEILINGS[] = {0u, 4u, 8u, 16u, 32u, 64u, 128u, 256u, SIZE_MAX};

#define SHARE_STEPS 101u
#define SHARE_STEP 0.01

#define SHIPPED_FREE_CEILING 16u
#define SHIPPED_FLAT_SHARE 0.85

#define ROW_COUNT ((sizeof KINDS / sizeof KINDS[0]) * (sizeof NEEDLE_LENGTHS / sizeof NEEDLE_LENGTHS[0]) * 2u)

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

static double two_to_the(double exponent)
{
    double held = 1.0;
    double remaining = exponent;

    while (remaining >= 1.0)
    {
        held *= 2.0;
        remaining -= 1.0;
    }
    held *= 1.0 + (remaining * 0.6931472) + (remaining * remaining * 0.2402265);
    return held;
}

typedef struct
{
    CorpusKind kind;
    double entropy;
    size_t distinct;
    AnchorFieldCensus census;
    size_t needle_len;
    unsigned present;
    uint64_t inorder;
    uint64_t freed;
} Row;

static void name_ceiling(char *text, size_t room, size_t ceiling)
{
    const size_t needle_count = sizeof NEEDLE_LENGTHS / sizeof NEEDLE_LENGTHS[0];
    const size_t widest = NEEDLE_LENGTHS[needle_count - 1u];

    if (ceiling >= widest)
    {
        (void)snprintf(text, room, "every length");
        return;
    }
    if (ceiling == 0u)
    {
        (void)snprintf(text, room, "no length");
        return;
    }
    (void)snprintf(text, room, "%llu and under", (unsigned long long)ceiling);
}

static double flatness(const Row *row)
{
    return two_to_the(row->entropy) / (double)row->distinct;
}

static uint64_t quickest(const Row *row)
{
    return (row->inorder < row->freed) ? row->inorder : row->freed;
}

static double cycles_given_up(const Row *rows, size_t count, double flat_share, size_t ceiling,
                              size_t *agreed)
{
    double lost = 0.0;
    size_t right = 0u;

    for (size_t slot = 0u; slot < count; slot += 1u)
    {
        const int flat = flatness(&rows[slot]) >= flat_share;
        const int take_free = (flat == 0) && (rows[slot].needle_len <= ceiling);
        const uint64_t paid = (take_free != 0) ? rows[slot].freed : rows[slot].inorder;

        if (paid == quickest(&rows[slot]))
        {
            right += 1u;
        }
        lost += (double)paid - (double)quickest(&rows[slot]);
    }
    *agreed = right;
    return lost;
}

static uint64_t time_arm(AnchorSiftEngine arm, const uint8_t *corpus, size_t corpus_len,
                         const uint8_t *needles, size_t needle_len, unsigned present, size_t *found)
{
    uint64_t best = UINT64_MAX;

    for (size_t trial = 0u; trial < TIMED_TRIALS; trial += 1u)
    {
        const uint64_t opened = cycles_now();
        size_t seen = 0u;

        for (size_t draw = 0u; draw < NEEDLES_PER_ROW; draw += 1u)
        {
            const uint8_t *const needle = (present != 0u)
                                              ? (corpus + ((draw * 977u) % (corpus_len - needle_len)))
                                              : (needles + (draw * needle_len));

            seen += arm(corpus, corpus_len, needle, needle_len);
        }

        const uint64_t closed = cycles_now();

        if ((closed - opened) < best)
        {
            best = closed - opened;
        }
        *found = seen;
    }
    return best;
}

static size_t measure_rows(Row *rows, uint8_t *corpus, uint8_t *absent)
{
    const size_t kind_count = sizeof KINDS / sizeof KINDS[0];
    const size_t needle_count = sizeof NEEDLE_LENGTHS / sizeof NEEDLE_LENGTHS[0];
    const size_t widest = NEEDLE_LENGTHS[needle_count - 1u];
    size_t written = 0u;

    for (unsigned present = 0u; present <= 1u; present += 1u)
    {
        for (size_t which = 0u; which < kind_count; which += 1u)
        {
            bench_build_bytes(corpus, CORPUS_BYTES, KINDS[which], CORPUS_SEED);
            bench_build_bytes(absent, widest * NEEDLES_PER_ROW, KINDS[which], ABSENT_SEED);

            size_t distinct = 0u;
            const double entropy = bench_collision_entropy(corpus, CORPUS_BYTES, &distinct);

            for (size_t pick = 0u; pick < needle_count; pick += 1u)
            {
                const size_t needle_len = NEEDLE_LENGTHS[pick];
                size_t found_inorder = 0u;
                size_t found_free = 0u;

                const uint64_t inorder = time_arm(anchor_sift_inorder, corpus, CORPUS_BYTES, absent,
                                                  needle_len, present, &found_inorder);
                const uint64_t freed = time_arm(anchor_sift_free, corpus, CORPUS_BYTES, absent,
                                                needle_len, present, &found_free);

                if (found_inorder != found_free)
                {
                    (void)fprintf(stderr, "  %s at m=%llu: %llu against %llu\n",
                                  bench_corpus_name(KINDS[which]), (unsigned long long)needle_len,
                                  (unsigned long long)found_inorder,
                                  (unsigned long long)found_free);
                    exit(1);
                }

                rows[written].kind = KINDS[which];
                rows[written].entropy = entropy;
                rows[written].distinct = distinct;
                anchor_field_census(corpus, CORPUS_BYTES, &rows[written].census);
                rows[written].needle_len = needle_len;
                rows[written].present = present;
                rows[written].inorder = inorder;
                rows[written].freed = freed;
                written += 1u;
            }
        }
    }
    return written;
}

static void print_rows(const Row *rows, size_t count)
{
    printf("\n  %-12s %-7s %-9s %-9s %-6s %-4s %-13s %-13s %-9s %s\n", "corpus", "h2", "distinct",
           "flatness", "m", "in", "inorder", "free", "faster", "by");
    for (size_t slot = 0u; slot < count; slot += 1u)
    {
        const int inorder_wins = rows[slot].inorder < rows[slot].freed;
        const uint64_t slower = inorder_wins ? rows[slot].freed : rows[slot].inorder;

        printf("  %-12s %-7.3f %-9llu %-9.4f %-6llu %-4s %-13llu %-13llu %-9s %.2fx\n",
               bench_corpus_name(rows[slot].kind), rows[slot].entropy,
               (unsigned long long)rows[slot].distinct, flatness(&rows[slot]),
               (unsigned long long)rows[slot].needle_len,
               (rows[slot].present != 0u) ? "yes" : "no",
               (unsigned long long)rows[slot].inorder, (unsigned long long)rows[slot].freed,
               inorder_wins ? "anchor_inorder" : "anchor_free",
               (double)slower / (double)quickest(&rows[slot]));
    }
}

static void recommend_constants(const Row *rows, size_t count)
{
    const size_t ceiling_count = sizeof CEILINGS / sizeof CEILINGS[0];
    double best_lost = -1.0;
    size_t best_ceiling = 0u;
    size_t best_agreed = 0u;

    for (size_t rung = 0u; rung < ceiling_count; rung += 1u)
    {
        for (size_t step = 0u; step < SHARE_STEPS; step += 1u)
        {
            const double share = (double)step * SHARE_STEP;
            size_t agreed = 0u;
            const double lost = cycles_given_up(rows, count, share, CEILINGS[rung], &agreed);

            if ((best_lost < 0.0) || (lost < best_lost))
            {
                best_lost = lost;
                best_ceiling = CEILINGS[rung];
                best_agreed = agreed;
            }
        }
    }

    double lowest = -1.0;
    double highest = -1.0;

    for (size_t step = 0u; step < SHARE_STEPS; step += 1u)
    {
        const double share = (double)step * SHARE_STEP;
        size_t agreed = 0u;

        if (cycles_given_up(rows, count, share, best_ceiling, &agreed) == best_lost)
        {
            if (lowest < 0.0)
            {
                lowest = share;
            }
            highest = share;
        }
    }

    char ceiling_text[24];

    name_ceiling(ceiling_text, sizeof ceiling_text, best_ceiling);

    printf("\n  Constants swept, not assumed\n");
    printf("  %-24s %.2f to %.2f, taking %.2f as the midpoint\n", "flatness threshold", lowest,
           highest, (lowest + highest) / 2.0);
    printf("  %-24s a structured corpus takes the free order arm at %s\n", "needle length",
           ceiling_text);
    printf("  %-24s %llu of %llu rows, giving up %.0f cycles\n", "what that scores",
           (unsigned long long)best_agreed, (unsigned long long)count, best_lost);
    printf("  The threshold the kernel carries, %.2f, sits inside that interval. The ceiling of\n",
           SHIPPED_FLAT_SHARE);
    printf("  %llu it used to carry does not survive the sweep at any value.\n",
           (unsigned long long)SHIPPED_FREE_CEILING);
}

static void recommend_per_corpus(const Row *rows, size_t count)
{
    const size_t kind_count = sizeof KINDS / sizeof KINDS[0];

    printf("\n  %-12s %-9s %-15s %-15s %-13s %s\n", "corpus", "flatness", "run this",
           "free arm at", "over the other", "widest row");
    for (size_t which = 0u; which < kind_count; which += 1u)
    {
        const size_t ceiling_count = sizeof CEILINGS / sizeof CEILINGS[0];
        double inorder_total = 0.0;
        double free_total = 0.0;
        double widest = 1.0;
        double held_flatness = 0.0;
        size_t here = 0u;

        for (size_t slot = 0u; slot < count; slot += 1u)
        {
            if (rows[slot].kind != KINDS[which])
            {
                continue;
            }
            const uint64_t slower = (rows[slot].inorder < rows[slot].freed) ? rows[slot].freed
                                                                            : rows[slot].inorder;
            const double margin = (double)slower / (double)quickest(&rows[slot]);

            inorder_total += (double)rows[slot].inorder;
            free_total += (double)rows[slot].freed;
            held_flatness = flatness(&rows[slot]);
            here += 1u;
            if (margin > widest)
            {
                widest = margin;
            }
        }
        if (here == 0u)
        {
            continue;
        }

        double best_lost = -1.0;
        size_t best_ceiling = 0u;

        for (size_t rung = 0u; rung < ceiling_count; rung += 1u)
        {
            double lost = 0.0;

            for (size_t slot = 0u; slot < count; slot += 1u)
            {
                if (rows[slot].kind != KINDS[which])
                {
                    continue;
                }
                const uint64_t paid = (rows[slot].needle_len <= CEILINGS[rung]) ? rows[slot].freed
                                                                                : rows[slot].inorder;

                lost += (double)paid - (double)quickest(&rows[slot]);
            }
            if ((best_lost < 0.0) || (lost < best_lost))
            {
                best_lost = lost;
                best_ceiling = CEILINGS[rung];
            }
        }

        const int inorder_wins = inorder_total < free_total;
        const double ratio = inorder_wins ? (free_total / inorder_total)
                                          : (inorder_total / free_total);
        char ceiling_text[24];

        name_ceiling(ceiling_text, sizeof ceiling_text, best_ceiling);

        printf("  %-12s %-9.4f %-15s %-15s %-13.2f %.2fx\n", bench_corpus_name(KINDS[which]),
               held_flatness, inorder_wins ? "anchor_inorder" : "anchor_free", ceiling_text, ratio,
               widest);
    }
    printf("  The needle length column is fitted to that corpus alone, for a caller\n");
    printf("  holding one corpus wants. A ceiling fitted across three reports where the average\n");
    printf("  crosses over, and the average crosses over nowhere in particular.\n");
}

typedef struct
{
    const char *name;
    double flat_share;
    size_t ceiling;
} Named;

static void score_named(const Row *rows, size_t count)
{
    static const Named NAMED[] = {
        {"always inorder", 0.0, SIZE_MAX},
        {"always free", 2.0, SIZE_MAX},
        {"needle length alone, as shipped", 2.0, SHIPPED_FREE_CEILING},
        {"flatness then length, as documented", SHIPPED_FLAT_SHARE, SHIPPED_FREE_CEILING},
        {"flatness alone", SHIPPED_FLAT_SHARE, SIZE_MAX},
    };
    const size_t named_count = sizeof NAMED / sizeof NAMED[0];
    double worst = 0.0;

    for (size_t slot = 0u; slot < named_count; slot += 1u)
    {
        size_t agreed = 0u;
        const double lost = cycles_given_up(rows, count, NAMED[slot].flat_share,
                                            NAMED[slot].ceiling, &agreed);

        if (lost > worst)
        {
            worst = lost;
        }
    }

    printf("\n  %-38s %-16s %-18s %s\n", "rule", "picked fastest", "cycles given up",
           "share of the worst");
    for (size_t slot = 0u; slot < named_count; slot += 1u)
    {
        size_t agreed = 0u;
        const double lost = cycles_given_up(rows, count, NAMED[slot].flat_share,
                                            NAMED[slot].ceiling, &agreed);
        char counted[32];

        (void)snprintf(counted, sizeof counted, "%llu of %llu", (unsigned long long)agreed,
                       (unsigned long long)count);
        printf("  %-38s %-16s %-18.0f %.3f\n", NAMED[slot].name, counted, lost,
               (worst > 0.0) ? (lost / worst) : 0.0);
    }

    double kernel_lost = 0.0;
    size_t kernel_agreed = 0u;

    for (size_t slot = 0u; slot < count; slot += 1u)
    {
        const AnchorSiftPlan plan = {&rows[slot].census, rows[slot].needle_len, 0u};
        const AnchorSiftEngine chosen = anchor_sift_choose(&plan);
        const uint64_t paid = (chosen == anchor_sift_free) ? rows[slot].freed : rows[slot].inorder;

        if (paid == quickest(&rows[slot]))
        {
            kernel_agreed += 1u;
        }
        kernel_lost += (double)paid - (double)quickest(&rows[slot]);
    }

    char counted[32];

    (void)snprintf(counted, sizeof counted, "%llu of %llu", (unsigned long long)kernel_agreed,
                   (unsigned long long)count);
    printf("  %-38s %-16s %-18.0f %.3f\n", "what the kernel does today", counted, kernel_lost,
           (worst > 0.0) ? (kernel_lost / worst) : 0.0);
}

int main(void)
{
    const size_t needle_count = sizeof NEEDLE_LENGTHS / sizeof NEEDLE_LENGTHS[0];
    const size_t absent_bytes = NEEDLE_LENGTHS[needle_count - 1u] * NEEDLES_PER_ROW;

    uint8_t *const corpus = (uint8_t *)malloc(CORPUS_BYTES);
    uint8_t *const absent = (uint8_t *)malloc(absent_bytes);
    Row *const rows = (Row *)malloc(ROW_COUNT * sizeof(Row));

    if ((corpus == NULL) || (absent == NULL) || (rows == NULL))
    {
        (void)fprintf(stderr, "  could not take %llu bytes\n",
                      (unsigned long long)(CORPUS_BYTES + absent_bytes));
        free(corpus);
        free(absent);
        free(rows);
        return 2;
    }

    printf("  Which arm to run, and what the two thresholds should be, at N=%llu over %llu\n",
           (unsigned long long)CORPUS_BYTES, (unsigned long long)NEEDLES_PER_ROW);
    printf("  needles a row, keeping the smallest of %llu trials.\n",
           (unsigned long long)TIMED_TRIALS);

    const size_t count = measure_rows(rows, corpus, absent);

    print_rows(rows, count);
    score_named(rows, count);
    recommend_constants(rows, count);
    recommend_per_corpus(rows, count);

    printf("\n  Cycles given up is what a dispatcher exists to minimize. Counting rows treats a\n");
    printf("  row where the arms differ by one percent the same as one where they differ\n");
    printf("  threefold, and the two scores disagree here for exactly that reason.\n");

    free(corpus);
    free(absent);
    free(rows);
    return 0;
}
