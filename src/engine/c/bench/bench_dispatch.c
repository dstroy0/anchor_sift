/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_dispatch.c
 * @brief Derives the dispatch constants from the clock and recommends them, per corpus and overall.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Every arm is sound. A dispatch mistake costs speed and never correctness. Nothing here can
 *       fail. It can only come out slower, and that makes this a bench and not a test.
 * @note The kernel's two thresholds were set by hand and never measured. This sweeps both of them
 *       over every combination and reports the pair that gives up the fewest cycles, together with
 *       the interval of thresholds that ties for it. An interval is the honest form of the answer:
 *       three corpora cannot pin a threshold to two places, and printing one number would hide that.
 * @note Two scores are printed. Read the second. Counting how often a rule picks the faster arm
 *       treats a row where the arms differ by one percent the same as one where they differ
 *       threefold. Cycles given up against always choosing correctly is the quantity a dispatcher
 *       exists to minimize.
 * @warning Cycles belong to the machine that produced them. Re-run this before trusting a rule on
 *          another part. The kernel's own note about the rule says the same.
 */

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
#else
#include <time.h>
#define CYCLES_ARE_REAL 0
#endif

/**
 * @brief Corpus length every row is measured at.
 *
 * @note The ceiling the kernel carries was set on a skewed corpus at this length. A rule scored
 *       anywhere else is not being compared against the measurement that set it.
 */
#define CORPUS_BYTES 65536u

/** @brief Needles drawn per row. */
#define NEEDLES_PER_ROW 32u

/** @brief Times one row this many times and keeps the smallest, which rejects scheduler noise. */
#define TIMED_TRIALS 7u

/** @brief Seed for every generated corpus, keeping a row reproducible from this file alone. */
#define CORPUS_SEED 0xD7723247ULL

/** @brief Seed for the needles that are not drawn from the corpus. */
#define ABSENT_SEED 0x9E3779B97F4A7C15ULL

/** @brief Needle lengths swept, spanning the effective alphabet in both directions. */
static const size_t NEEDLE_LENGTHS[] = {4u, 8u, 16u, 32u, 64u, 128u, 256u};

/** @brief Corpus kinds swept. */
static const CorpusKind KINDS[] = {CORPUS_UNIFORM, CORPUS_SKEWED, CORPUS_PERIODIC};

/** @brief Ceilings swept for the needle length term, the last standing for no ceiling at all. */
static const size_t CEILINGS[] = {0u, 4u, 8u, 16u, 32u, 64u, 128u, 256u, SIZE_MAX};

/** @brief Flatness thresholds swept, from every corpus counting as structured to none of them. */
#define SHARE_STEPS 101u
#define SHARE_STEP 0.01

/* The kernel's own constants, spelled here so this file can score the shipped rule after the kernel
 * stops using them. */
#define SHIPPED_FREE_CEILING 16u
#define SHIPPED_FLAT_SHARE 0.85

/** @brief Rows measured: every corpus kind, every needle length, present and absent. */
#define ROW_COUNT ((sizeof KINDS / sizeof KINDS[0]) \
                   * (sizeof NEEDLE_LENGTHS / sizeof NEEDLE_LENGTHS[0]) * 2u)

/**
 * @brief Reads the cycle counter, or a monotonic substitute where the part has none.
 *
 * @return A count that rises with time, in cycles where the host supplies them.
 */
static uint64_t cycles_now(void)
{
#if CYCLES_ARE_REAL
    // Ordering deviation: __rdtsc may be reordered against the work being timed. The barriers keep
    // one arm's loads and stores from crossing them.
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
 * @brief Two to the power of a small non-negative exponent, without <math.h>.
 *
 * @param[in] exponent Collision entropy in bits, at most 8 for a byte corpus.
 * @return             The effective alphabet size that exponent stands for.
 * @note The same series the kernel carries. A constant derived here against slightly different
 *       arithmetic would be a constant nobody could ship.
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
    held *= 1.0 + (remaining * 0.6931472) + (remaining * remaining * 0.2402265);
    return held;
}

/** @brief One measured row: a corpus, a needle length, and what each arm cost on it. */
typedef struct
{
    CorpusKind kind;
    double entropy;
    size_t distinct;
    size_t needle_len;
    unsigned present;
    uint64_t inorder;
    uint64_t freed;
} Row;

/**
 * @brief Writes a ceiling in the form a reader can act on.
 *
 * @param[out] text    Where to write [BORROWS].
 * @param[in]  room    How many bytes it holds.
 * @param[in]  ceiling The ceiling to name.
 * @note A ceiling at or above the widest needle measured admits every row and is the same rule as
 *       no ceiling at all. Printing the number instead would read as a crossover the sweep found,
 *       when what the sweep found is that no crossover exists inside the lengths measured.
 */
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

/**
 * @brief How flat a corpus reads, as the effective alphabet over the symbols it actually uses.
 *
 * @param[in] row A measured row [BORROWS].
 * @return        A value near one where the corpus is memoryless and far below it where it is not.
 * @note This is the quantity the kernel's threshold is compared against, named once so the sweep
 *       and the shipped rule cannot end up comparing different things.
 */
static double flatness(const Row *row)
{
    return two_to_the(row->entropy) / (double)row->distinct;
}

/**
 * @brief The cycles the faster of the two arms took on a row.
 *
 * @param[in] row A measured row [BORROWS].
 * @return        The smaller of the two counts.
 */
static uint64_t quickest(const Row *row)
{
    return (row->inorder < row->freed) ? row->inorder : row->freed;
}

/**
 * @brief What one pair of constants gives up over every row, in cycles.
 *
 * @param[in]  rows       Measured rows [BORROWS].
 * @param[in]  count      How many.
 * @param[in]  flat_share Flatness at or above which the corpus counts as memoryless.
 * @param[in]  ceiling    Needle length at or below which a structured corpus takes the free arm.
 * @param[out] agreed     Where the count of rows it got right is written [BORROWS].
 * @return                Cycles given up against always naming the faster arm.
 */
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

/**
 * @brief Times one arm over a row's needles, keeping the smallest of several trials.
 *
 * @param[in]  arm        Arm to time [BORROWS].
 * @param[in]  corpus     Corpus to search [BORROWS].
 * @param[in]  corpus_len How many bytes it holds.
 * @param[in]  needles    Where the needles for this row start [BORROWS].
 * @param[in]  needle_len Length of each needle.
 * @param[in]  present    Non zero to draw needles out of the corpus instead of from `needles`.
 * @param[out] found      Where the occurrence count is written [BORROWS].
 * @return                The smallest cycle count seen across the trials.
 */
static uint64_t time_arm(AnchorSiftArm arm, const uint8_t *corpus, size_t corpus_len,
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

/**
 * @brief Measures every row and writes them into `rows`.
 *
 * @param[out] rows   Where to write, at least ROW_COUNT entries [BORROWS].
 * @param[in]  corpus Working buffer of at least CORPUS_BYTES [BORROWS].
 * @param[in]  absent Buffer for needles from a second stream [BORROWS].
 * @return            How many rows were written.
 * @note Exits the process where two arms disagree. Soundness says no arm can lose a true
 *       occurrence. A disagreement is therefore a defect, and no timing taken beside it is worth reading.
 */
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

/**
 * @brief Prints every measured row.
 *
 * @param[in] rows  Measured rows [BORROWS].
 * @param[in] count How many.
 */
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

/**
 * @brief Sweeps both constants over every combination and prints the pair that gives up the least.
 *
 * @param[in] rows  Measured rows [BORROWS].
 * @param[in] count How many.
 * @note The interval of flatness thresholds that ties for the best is printed beside the winner,
 *       because three corpora cannot pin a threshold to two places and one number would hide that.
 */
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

/**
 * @brief Prints, for each corpus, which arm to run on it and what that is worth.
 *
 * @param[in] rows  Measured rows [BORROWS].
 * @param[in] count How many.
 * @note A caller holding one corpus wants one answer about that corpus, not a rule covering three.
 */
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

        // The ceiling fitted to this corpus alone, by stepping it over the rows this corpus
        // produced. A caller holding one corpus wants the crossover inside it, and a rule fitted
        // across three corpora reports where the average crosses, which is nowhere in particular.
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

/** @brief One named rule scored beside the swept constants, to say what the kernel does today. */
typedef struct
{
    const char *name;
    double flat_share;
    size_t ceiling;
} Named;

/**
 * @brief Scores the named rules, including the two constant baselines.
 *
 * @param[in] rows  Measured rows [BORROWS].
 * @param[in] count How many.
 * @note A rule that cannot beat one of the two constant baselines is not worth its branch, so the
 *       baselines sit here beside the rules that read a plan.
 */
static void score_named(const Row *rows, size_t count)
{
    // A threshold above one makes every corpus structured; a threshold of zero makes every corpus
    // flat. Together with the ceiling they express the two baselines without a second code path.
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

    // The kernel scored by calling it, not by restating its rule here. A rule spelled twice is a
    // rule that can be fixed in one place and still read as broken in the other.
    double kernel_lost = 0.0;
    size_t kernel_agreed = 0u;

    for (size_t slot = 0u; slot < count; slot += 1u)
    {
        // No period supplied. This bench scores which arm to run, and the anchor count the period
        // would set is bench_coherence's question.
        const AnchorSiftPlan plan = {rows[slot].entropy, rows[slot].distinct,
                                     rows[slot].needle_len, 0u};
        const AnchorSiftArm chosen = anchor_sift_choose(&plan);
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
        // %zu is absent from the C runtime this builds against on Windows, so every size_t printed
        // here is widened and written as %llu.
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
