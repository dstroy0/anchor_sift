/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_tail.cpp
 * @brief The tail as error, and hourly_supposition item 1: periodic disturbance on a co-arm.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Correction carried in from the review of bench_deltanull.cpp. That file called the sparse
 *       part of the delta distribution a sampling artifact, as though more samples would resolve it.
 *       That is the wrong frame. The tail is the error term, definitionally, and the move is not to
 *       sample it better but to drive it down. hourly_supposition item 10 puts it as a recursive
 *       function of the tail with a 10^-26 target.
 * @note The claim under test is item 1: introducing a periodic disturbance adjusts the joint error
 *       toward zero by several orders of magnitude on an undisturbed co-arm. It is the most concrete
 *       positive prediction available and nothing in this tree has tested it.
 * @note The mechanism it would work by, if it works, is decorrelation. Co-arms estimating one
 *       quantity from the same kind of sample carry correlated error, and correlated error does not
 *       average out across arms. A disturbance that is periodic instead of random decorrelates one
 *       arm from the others in a way the joint estimator can cancel. That is dither, and it is
 *       well founded in signal processing, so the prediction is not exotic.
 * @note Three conditions, because two would not separate the mechanism from the disturbance: no
 *       disturbance, periodic disturbance, and random disturbance of the same magnitude. If periodic
 *       beats random, the periodicity is doing the work. If both beat none equally, any dither does.
 *       If neither beats none, the claim does not hold here.
 */

#include "bench_seed.h"
#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{

/** @brief The frame the sweep selected. */
const unsigned FRAME = 31u;

/** @brief The standard's first round constant. */
const uint32_t ROUND_CONSTANT_ZERO = 0x428a2f98u;

/**
 * @brief Rotates a word right.
 *
 * @param[in] value    Word to rotate.
 * @param[in] distance How far.
 * @return             The rotated word.
 */
uint32_t rotate_right(uint32_t value, unsigned distance)
{
    distance &= 31u;
    return (distance == 0u) ? value : ((value >> distance) | (value << (32u - distance)));
}

/** @brief The round's high mixing function. */
uint32_t mix_high(uint32_t value)
{
    return rotate_right(value, 6u) ^ rotate_right(value, 11u) ^ rotate_right(value, 25u);
}

/** @brief The round's low mixing function. */
uint32_t mix_low(uint32_t value)
{
    return rotate_right(value, 2u) ^ rotate_right(value, 13u) ^ rotate_right(value, 22u);
}

/** @brief The round's choice function. */
uint32_t choose(uint32_t control, uint32_t when_set, uint32_t when_clear)
{
    return when_clear ^ (control & (when_set ^ when_clear));
}

/** @brief The round's majority function. */
uint32_t majority(uint32_t left, uint32_t middle, uint32_t right)
{
    return (left & middle) | (right & (left ^ middle));
}

/**
 * @brief Runs one real round, constant included.
 *
 * @param[in,out] state         Eight working variables [BORROWS].
 * @param[in]     schedule_word The message word.
 */
void run_round(uint32_t *state, uint32_t schedule_word)
{
    const uint32_t carry_one = state[7] + mix_high(state[4]) +
                               choose(state[4], state[5], state[6]) + ROUND_CONSTANT_ZERO +
                               schedule_word;
    const uint32_t carry_two = mix_low(state[0]) + majority(state[0], state[1], state[2]);

    state[7] = state[6];
    state[6] = state[5];
    state[5] = state[4];
    state[4] = state[3] + carry_one;
    state[3] = state[2];
    state[2] = state[1];
    state[1] = state[0];
    state[0] = carry_one + carry_two;
}

/**
 * @brief Draws one rotational-XOR delta.
 *
 * @param[in,out] generator  Random source [BORROWS].
 * @param[in]     disturbance Applied to the turned member's message word, zero for none.
 * @return                   The outgoing delta on word zero.
 */
uint32_t draw_delta(std::mt19937 &generator, uint32_t disturbance)
{
    uint32_t plain[8];
    uint32_t turned[8];

    for (unsigned slot = 0u; slot < 8u; slot += 1u)
    {
        const uint32_t value = generator();
        plain[slot] = value;
        turned[slot] = rotate_right(value, FRAME);
    }
    const uint32_t message = generator();

    run_round(plain, message);
    run_round(turned, rotate_right(message, FRAME) ^ disturbance);

    return turned[0] ^ rotate_right(plain[0], FRAME);
}

/**
 * @brief The quantity being estimated: collision probability of the delta distribution.
 *
 * @param[in] counts How often each delta appeared [BORROWS].
 * @param[in] drawn  How many draws produced them.
 * @return           The unbiased collision probability.
 * @note Unbiased form, because the naive sum of squared frequencies runs high at this sparsity and
 *       would report structure that is not there.
 */
double collision_probability(const std::unordered_map<uint32_t, uint32_t> &counts, uint64_t drawn)
{
    long double colliding = 0.0L;

    for (const auto &entry : counts)
    {
        const long double count = (long double)entry.second;
        colliding += count * (count - 1.0L);
    }
    const long double total = (long double)drawn * ((long double)drawn - 1.0L);
    return (total > 0.0L) ? (double)(colliding / total) : 0.0;
}

/** @brief How a co-arm is disturbed. */
enum class Disturbance
{
    None,
    Periodic,
    Random
};

/**
 * @brief Estimates the target from co-arms, one of which may be disturbed.
 *
 * @param[in,out] generator Random source [BORROWS].
 * @param[in]     arms      How many co-arms.
 * @param[in]     per_arm   Draws per arm.
 * @param[in]     kind      Which disturbance the first arm carries.
 * @param[in]     period    Period of the disturbance where it is periodic.
 * @param[in]     magnitude The disturbance value.
 * @return                  The joint estimate, which is the mean across arms.
 */
double joint_estimate(std::mt19937 &generator, unsigned arms, unsigned per_arm, Disturbance kind,
                      unsigned period, uint32_t magnitude)
{
    double total = 0.0;

    for (unsigned arm = 0u; arm < arms; arm += 1u)
    {
        std::unordered_map<uint32_t, uint32_t> counts;
        counts.reserve(per_arm / 2u);

        for (unsigned draw = 0u; draw < per_arm; draw += 1u)
        {
            uint32_t disturbance = 0u;

            // Only the first arm is ever disturbed. The rest are the undisturbed co-arms whose
            // joint error the claim is about.
            if (arm == 0u)
            {
                if (kind == Disturbance::Periodic)
                {
                    disturbance = ((draw % period) == 0u) ? magnitude : 0u;
                }
                else if (kind == Disturbance::Random)
                {
                    // Same expected rate as the periodic case, so magnitude is not the variable.
                    disturbance = ((generator() % period) == 0u) ? magnitude : 0u;
                }
            }
            counts[draw_delta(generator, disturbance)] += 1u;
        }
        total += collision_probability(counts, per_arm);
    }
    return total / (double)arms;
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  The tail as error, and periodic disturbance on a co-arm\n");
    std::printf("================================================================\n");

    std::mt19937 generator(bench_seed(20260908u));
    const auto started = std::chrono::steady_clock::now();

    // -------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  1. Head and tail, separated\n");
    std::printf("================================================================\n");
    std::printf("\n  The tail is the error term instead of an undersampled part of the signal, so\n");
    std::printf("  it gets separated and measured instead of apologised for.\n");

    {
        const unsigned drawn = 4000000u;
        std::unordered_map<uint32_t, uint32_t> counts;
        counts.reserve(drawn / 2u);
        for (unsigned draw = 0u; draw < drawn; draw += 1u)
        {
            counts[draw_delta(generator, 0u)] += 1u;
        }

        uint64_t singleton_mass = 0u;
        uint64_t head_mass = 0u;
        size_t singletons = 0u;
        size_t doubletons = 0u;
        size_t head = 0u;

        for (const auto &entry : counts)
        {
            if (entry.second == 1u)
            {
                singletons += 1u;
            }
            if (entry.second == 2u)
            {
                doubletons += 1u;
            }
            if (entry.second <= 2u)
            {
                singleton_mass += entry.second;
            }
            else
            {
                head_mass += entry.second;
                head += 1u;
            }
        }

        std::printf("\n  %-34s %14s %14s\n", "", "deltas", "mass");
        std::printf("  %-34s %14s %14s\n", "----------------------------------", "--------------",
                    "--------------");
        std::printf("  %-34s %14zu %13.4f%%\n", "head, count above two", head,
                    100.0 * (double)head_mass / (double)drawn);
        std::printf("  %-34s %14zu %13.4f%%\n", "tail, count at or below two",
                    singletons + doubletons, 100.0 * (double)singleton_mass / (double)drawn);

        // The tail is not discarded here, and it must not be. The unbiased collision estimator
        // used later weights a delta by c(c-1), which is exactly zero for a singleton, so that
        // estimator throws the whole tail away by construction. The tail is the most sensitive
        // part of the distribution: the singleton and doubleton counts are what carry information
        // about the part that has not been seen at all, and no other part of the sample does.
        const double coverage =
            1.0 - ((double)singletons / (double)drawn); // Good-Turing coverage.
        const double unseen_mass = (double)singletons / (double)drawn;
        const double chao_total =
            (double)counts.size() +
            ((doubletons > 0u) ? (((double)singletons * (double)singletons) /
                                  (2.0 * (double)doubletons))
                               : 0.0);

        std::printf("\n  Read through the tail instead of past it:\n");
        std::printf("    singletons f1              : %zu\n", singletons);
        std::printf("    doubletons f2              : %zu\n", doubletons);
        std::printf("    Good-Turing coverage       : %.8f\n", coverage);
        std::printf("    unseen mass, f1/N          : %.8e\n", unseen_mass);
        std::printf("    distinct deltas observed   : %zu\n", counts.size());
        std::printf("    Chao1 estimate of the total: %.0f\n", chao_total);
        std::printf("    never observed             : %.0f\n",
                    chao_total - (double)counts.size());

        std::printf("\n  Those last four lines exist only because the tail was kept. f1 and f2 are\n");
        std::printf("  the sole part of a sample that says anything about what the sample missed,\n");
        std::printf("  and an estimator that zeroes them can report a distribution it has barely\n");
        std::printf("  seen as though it had seen all of it.\n");
    }

    // -------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  2. hourly_supposition item 1, tested\n");
    std::printf("================================================================\n");
    std::printf("\n  Claim: introducing a periodic disturbance adjusts the joint error toward zero\n");
    std::printf("  by several orders of magnitude on an undisturbed co-arm.\n");
    std::printf("\n  Eight co-arms estimate the collision probability of the delta distribution.\n");
    std::printf("  Only arm zero is ever disturbed. The reference is a single large run, and the\n");
    std::printf("  error is the distance from it. Three conditions, so periodicity is separable\n");
    std::printf("  from the mere presence of a disturbance.\n");

    // The reference, from one large undisturbed run.
    double reference = 0.0;
    {
        const unsigned drawn = 8000000u;
        std::unordered_map<uint32_t, uint32_t> counts;
        counts.reserve(drawn / 2u);
        for (unsigned draw = 0u; draw < drawn; draw += 1u)
        {
            counts[draw_delta(generator, 0u)] += 1u;
        }
        reference = collision_probability(counts, drawn);
    }
    std::printf("\n  reference collision probability : %.8e   (8,000,000 draws)\n", reference);

    const unsigned repeats = 24u;
    const unsigned arms = 8u;
    const unsigned per_arm = 60000u;
    const unsigned period = 64u;
    const uint32_t magnitude = 0x00000001u;

    std::printf("\n  %-24s %18s %18s\n", "condition", "mean |error|", "vs undisturbed");
    std::printf("  %-24s %18s %18s\n", "------------------------", "------------------",
                "------------------");

    double baseline = 0.0;

    for (int condition = 0; condition < 3; condition += 1)
    {
        const Disturbance kind = (condition == 0)   ? Disturbance::None
                                 : (condition == 1) ? Disturbance::Periodic
                                                    : Disturbance::Random;
        const char *name = (condition == 0)   ? "no disturbance"
                           : (condition == 1) ? "periodic, period 64"
                                              : "random, same rate";

        double error_total = 0.0;
        for (unsigned repeat = 0u; repeat < repeats; repeat += 1u)
        {
            const double estimate =
                joint_estimate(generator, arms, per_arm, kind, period, magnitude);
            error_total += std::fabs(estimate - reference);
        }
        const double mean_error = error_total / (double)repeats;
        if (condition == 0)
        {
            baseline = mean_error;
        }

        std::printf("  %-24s %18.8e %17.4fx\n", name, mean_error,
                    (mean_error > 0.0) ? (baseline / mean_error) : 0.0);
    }

    std::printf("\n  Reading it. A ratio above one means the disturbance reduced the joint error,\n");
    std::printf("  which is the claim. Several orders of magnitude would be a ratio in the\n");
    std::printf("  thousands. A ratio near one means the disturbance did nothing here, and a\n");
    std::printf("  ratio below one means it hurt.\n");
    std::printf("\n  If periodic and random come out together, any dither is doing the work and\n");
    std::printf("  the periodicity is not the mechanism. If periodic wins alone, the period is.\n");

    const auto finished = std::chrono::steady_clock::now();
    std::printf("\n================================================================\n");
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return 0;
}
