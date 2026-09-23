/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_canary.cpp
 * @brief The vector walk through delta space, steered by tail error instead of by the peak.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note H13 tested a walk through nonce space steered by fitness and found no gradient to climb.
 *       That was the wrong space. The walk being proposed is through delta space, and the signal is
 *       not the fitness of a candidate but the tail error of the distribution it produces.
 * @note This matters because H30's chain failed in a specific way that a different objective might
 *       fix. That chain was greedy on probability: it took the most likely outgoing delta at each
 *       round and collapsed by a factor of 300 immediately after round zero. Following the peak is
 *       not the only option and there is no reason to think it is the right one.
 * @note The canary claim is that tail error moves first. If it does, it is a leading indicator: a
 *       delta whose distribution has low tail error should chain further than one chosen for its
 *       peak, and the tail error should show the collapse coming before the probability does.
 * @note Two strategies are run over identical candidate sets so the comparison is the objective and
 *       nothing else. Reporting both at every step also tests the canary claim directly, since a
 *       leading indicator has to lead.
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

/** @brief The standard's round constants. */
const uint32_t ROUND_CONSTANT[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u,
    0xab1c5ed5u, 0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu,
    0x9bdc06a7u, 0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu,
    0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
    0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u, 0xa2bfe8a1u, 0xa81a664bu,
    0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u,
    0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u,
    0xc67178f2u};

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
 * @brief Runs one real round.
 *
 * @param[in,out] state         Eight working variables [BORROWS].
 * @param[in]     round         Which round, selecting the constant.
 * @param[in]     schedule_word The message word.
 */
void run_round(uint32_t *state, unsigned round, uint32_t schedule_word)
{
    const uint32_t carry_one = state[7] + mix_high(state[4]) +
                               choose(state[4], state[5], state[6]) + ROUND_CONSTANT[round] +
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

/** @brief What one step through delta space reports back. */
struct Step
{
    double peak;        /**< Probability of the most common outgoing delta. */
    double tail_error;  /**< Good-Turing unseen mass, f1 over N. The canary. */
    uint32_t best_peak; /**< The delta the peak objective would follow. */
    uint32_t best_tail; /**< The delta the tail objective would follow. */
    size_t tied;        /**< How many deltas share the maximum count. */
};

/**
 * @brief Takes one step: apply an incoming delta, run a round, and read the outgoing distribution.
 *
 * @param[in,out] generator Random source [BORROWS].
 * @param[in]     incoming  The delta carried into this round.
 * @param[in]     round     Which round.
 * @param[in]     draws     How many pairs to sample.
 * @return                  Peak, tail error, and the delta each objective would follow.
 * @note The tail objective picks among the top candidates by peak, then follows whichever of them
 *       leaves the *next* distribution with the least unseen mass. That look-ahead is what makes it
 *       a different walk instead of a relabelling of the same one.
 */
Step take_step(std::mt19937 &generator, uint32_t incoming, unsigned round, unsigned draws)
{
    std::unordered_map<uint32_t, uint32_t> counts;
    counts.reserve(draws / 2u);

    for (unsigned draw = 0u; draw < draws; draw += 1u)
    {
        uint32_t plain[8];
        uint32_t turned[8];
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            const uint32_t value = generator();
            plain[slot] = value;
            turned[slot] = rotate_right(value, FRAME) ^ incoming;
        }
        const uint32_t message = generator();

        run_round(plain, round, message);
        run_round(turned, round, rotate_right(message, FRAME));

        counts[turned[0] ^ rotate_right(plain[0], FRAME)] += 1u;
    }

    Step step = {0.0, 0.0, 0u, 0u, 0u};
    size_t singletons = 0u;
    std::vector<std::pair<uint32_t, uint32_t>> ranked;

    for (const auto &entry : counts)
    {
        if (entry.second == 1u)
        {
            singletons += 1u;
        }
        ranked.push_back({entry.second, entry.first});
    }
    std::sort(ranked.rbegin(), ranked.rend());

    // How many deltas share the top count. At this sparsity the maximum is two or three
    // occurrences and a great many deltas reach it, so "the most common outgoing delta" is not a
    // thing the data identifies. Whichever one gets followed is then chosen by the sort's
    // tiebreak, which is the numeric value of the delta and is not a measurement of anything.
    // A walk steered by an argmax over a tied set is steered by its tiebreak.
    for (size_t rank = 0u; rank < ranked.size(); rank += 1u)
    {
        if (ranked[rank].first != ranked[0].first)
        {
            break;
        }
        step.tied += 1u;
    }

    step.peak = (double)ranked[0].first / (double)draws;
    step.best_peak = ranked[0].second;
    // Good-Turing unseen mass. Kept because it is the sensitive part, not discarded as noise.
    step.tail_error = (double)singletons / (double)draws;
    step.best_tail = ranked[0].second;

    // Look ahead over the top candidates and let the tail objective choose differently.
    const size_t considered = std::min<size_t>(6u, ranked.size());
    double least_tail = 1.0;

    for (size_t candidate = 0u; candidate < considered; candidate += 1u)
    {
        std::unordered_map<uint32_t, uint32_t> ahead;
        const unsigned probe = draws / 8u;
        ahead.reserve(probe / 2u);

        for (unsigned draw = 0u; draw < probe; draw += 1u)
        {
            uint32_t plain[8];
            uint32_t turned[8];
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                const uint32_t value = generator();
                plain[slot] = value;
                turned[slot] = rotate_right(value, FRAME) ^ ranked[candidate].second;
            }
            const uint32_t message = generator();

            run_round(plain, (round + 1u) & 63u, message);
            run_round(turned, (round + 1u) & 63u, rotate_right(message, FRAME));

            ahead[turned[0] ^ rotate_right(plain[0], FRAME)] += 1u;
        }

        size_t ahead_singletons = 0u;
        for (const auto &entry : ahead)
        {
            if (entry.second == 1u)
            {
                ahead_singletons += 1u;
            }
        }
        const double ahead_tail = (double)ahead_singletons / (double)probe;

        if (ahead_tail < least_tail)
        {
            least_tail = ahead_tail;
            step.best_tail = ranked[candidate].second;
        }
    }
    return step;
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  The vector walk through delta space, tail error as canary\n");
    std::printf("================================================================\n");
    std::printf("\n  H13 walked nonce space by fitness and found it flat. This walks delta space,\n");
    std::printf("  and the signal is the tail error of the distribution a step produces rather\n");
    std::printf("  than the height of its peak.\n");
    std::printf("\n  H30's chain was greedy on the peak and collapsed 300-fold right after round\n");
    std::printf("  zero. If the tail error leads, steering by it should chain further, and the\n");
    std::printf("  tail should show the collapse arriving before the probability does.\n");

    const unsigned draws = 400000u;
    const unsigned depth = 7u;

    for (int strategy = 0; strategy < 2; strategy += 1)
    {
        const bool by_tail = (strategy == 1);
        std::printf("\n================================================================\n");
        std::printf("  Walk steered by %s\n", by_tail ? "tail error" : "the peak");
        std::printf("================================================================\n");
        std::printf("\n  %6s %16s %18s %18s %14s\n", "round", "peak", "tail error", "compound",
                    "tied at peak");
        std::printf("  %6s %16s %18s %18s %14s\n", "------", "----------------",
                    "------------------", "------------------", "--------------");

        std::mt19937 generator(bench_seed(20260908u));
        uint32_t carried = 0u;
        double compound = 1.0;

        for (unsigned round = 0u; round < depth; round += 1u)
        {
            const Step step = take_step(generator, carried, round, draws);
            compound *= step.peak;

            std::printf("  %6u %16.8f %18.8f %18.6e %14zu\n", round, step.peak, step.tail_error,
                        compound, step.tied);

            carried = by_tail ? step.best_tail : step.best_peak;
        }

        std::printf("\n  compound over %u rounds : %.6e\n", depth, compound);
        std::printf("  geometric mean per round: %.8f  (2^%.2f)\n",
                    std::pow(compound, 1.0 / (double)depth),
                    std::log2(std::pow(compound, 1.0 / (double)depth)));
    }

    std::printf("\n================================================================\n");
    std::printf("  Reading it\n");
    std::printf("================================================================\n");
    std::printf("\n  Two things are being tested and they are separable.\n");
    std::printf("\n  Is the tail a canary? It leads if it moves before the peak does. Compare the\n");
    std::printf("  round where tail error jumps against the round where the peak falls, in the\n");
    std::printf("  peak-steered table. A canary that moves at the same time is a thermometer.\n");
    std::printf("\n  Is it a better objective? The two compound figures answer that directly, and\n");
    std::printf("  they were produced over identical candidate sets with the same seed, so the\n");
    std::printf("  only difference between the runs is which delta got followed.\n");
    std::printf("\n  Read the tied column before either of those. It counts how many deltas share\n");
    std::printf("  the top count. Where it is above one there is no single most common delta, and\n");
    std::printf("  whichever one gets followed is picked by the sort's tiebreak on numeric value\n");
    std::printf("  instead of by anything measured. A walk steered by an argmax over a tied set\n");
    std::printf("  is steered by its tiebreak, and comparing two such walks compares two\n");
    std::printf("  tiebreaks. The peak figure itself is unaffected, since a tie does not change\n");
    std::printf("  the height of the maximum, only which delta carries it.\n");
    return 0;
}
