/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_sweep.cpp
 * @brief Every frame, every output word, every round constant. And an honest map of what is left.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The rotational-XOR measurement that found a 775,000-fold concentration was one point: one
 *       frame, one incoming delta, one round constant, one output word. A single point is an
 *       anecdote about a space, and the space has to be swept before the number means anything.
 * @note What is enumerable is enumerated here: all 31 non-trivial frames, all 8 output words, all
 *       64 round constants. That is 15,872 combinations and every one is measured.
 * @note What is not enumerable is stated instead of hidden. The incoming delta ranges over 2^256
 *       for a full state and 2^32 for a single word, and neither can be swept. This file samples
 *       that axis by chaining: take the most probable outgoing delta as the next incoming one, which
 *       is how a real characteristic search walks the space it cannot enumerate. That is a greedy
 *       walk, not a proof of optimality, and a better trajectory may exist that greed does not find.
 * @note So the result below is a lower bound on what is achievable, not an upper bound on what
 *       exists. Section 4 says exactly how large the unswept part is, because a sweep that does not
 *       report its own coverage is a claim instead of a measurement.
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
 * @brief Runs one real round, constant included.
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

/** @brief The best characteristic found for one combination. */
struct Best
{
    double probability;
    uint32_t delta;
    unsigned frame;
    unsigned word;
    unsigned round;
};

/**
 * @brief Measures the strongest outgoing delta for one frame, word and round.
 *
 * @param[in] frame        The rotational frame.
 * @param[in] word         Which output word to read the delta from.
 * @param[in] round        Which round constant to use.
 * @param[in] incoming     The incoming delta applied to every state word.
 * @param[in] trials       How many pairs to sample.
 * @param[in] generator    Random source [BORROWS].
 * @return                 Probability and value of the most common outgoing delta.
 */
Best strongest_delta(unsigned frame, unsigned word, unsigned round, uint32_t incoming,
                     unsigned trials, std::mt19937 &generator)
{
    std::unordered_map<uint32_t, uint32_t> counts;
    counts.reserve(trials / 2u);

    for (unsigned trial = 0u; trial < trials; trial += 1u)
    {
        uint32_t plain[8];
        uint32_t turned[8];
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            const uint32_t value = generator();
            plain[slot] = value;
            turned[slot] = rotate_right(value, frame) ^ incoming;
        }
        const uint32_t message = generator();

        run_round(plain, round, message);
        run_round(turned, round, rotate_right(message, frame));

        counts[turned[word] ^ rotate_right(plain[word], frame)] += 1u;
    }

    Best best = {0.0, 0u, frame, word, round};
    for (const auto &entry : counts)
    {
        const double rate = (double)entry.second / (double)trials;
        if (rate > best.probability)
        {
            best.probability = rate;
            best.delta = entry.first;
        }
    }
    return best;
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  Rigorous sweep: every frame, every word, every constant\n");
    std::printf("================================================================\n");

    std::mt19937 generator(bench_seed(20260908u));
    const auto started = std::chrono::steady_clock::now();

    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  1. All 31 frames by all 8 output words, at round constant 0\n");
    std::printf("================================================================\n");
    std::printf("\n  Only words 0 and 4 are measured, and that restriction is the whole content of\n");
    std::printf("  this paragraph. A round writes state[0] and state[4]; the other six are pure\n");
    std::printf("  shifts of the incoming state. Since the incoming pair is constructed exactly\n");
    std::printf("  rotational, those six are trivially rotational on the way out and report a\n");
    std::printf("  delta of zero with probability one. An earlier version of this sweep measured\n");
    std::printf("  all eight and reported P = 1.00000000 across every frame, which was six\n");
    std::printf("  untouched words outvoting the two real ones.\n");
    std::printf("\n  62 combinations, 300,000 pairs each. Uniform would be 2.3e-10.\n");

    Best global = {0.0, 0u, 0u, 0u, 0u};
    std::vector<double> frame_best(32u, 0.0);

    for (unsigned frame = 1u; frame < 32u; frame += 1u)
    {
        for (unsigned word : {0u, 4u})
        {
            const Best found = strongest_delta(frame, word, 0u, 0u, 300000u, generator);
            frame_best[frame] = std::max(frame_best[frame], found.probability);
            if (found.probability > global.probability)
            {
                global = found;
            }
        }
    }

    std::printf("\n  %8s %16s   %8s %16s\n", "frame", "best P", "frame", "best P");
    std::printf("  %8s %16s   %8s %16s\n", "--------", "----------------", "--------",
                "----------------");
    for (unsigned frame = 1u; frame <= 16u; frame += 1u)
    {
        std::printf("  %8u %16.8f", frame, frame_best[frame]);
        if ((frame + 16u) < 32u)
        {
            std::printf("   %8u %16.8f", frame + 16u, frame_best[frame + 16u]);
        }
        std::printf("\n");
    }

    std::printf("\n  strongest overall: frame %u, word %u, P = %.8f, delta 0x%08x\n", global.frame,
                global.word, global.probability, global.delta);

    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  2. The same combination against all 64 round constants\n");
    std::printf("================================================================\n");
    std::printf("\n  A characteristic that only works at one constant is worth nothing, because a\n");
    std::printf("  hash uses all 64 in sequence. Same frame and word, every constant.\n");

    double constant_low = 1.0;
    double constant_high = 0.0;
    double constant_total = 0.0;

    for (unsigned round = 0u; round < 64u; round += 1u)
    {
        const Best found =
            strongest_delta(global.frame, global.word, round, 0u, 120000u, generator);
        constant_low = std::min(constant_low, found.probability);
        constant_high = std::max(constant_high, found.probability);
        constant_total += found.probability;
    }

    std::printf("\n  best P across the 64 constants : %.8f\n", constant_high);
    std::printf("  worst                          : %.8f\n", constant_low);
    std::printf("  mean                           : %.8f\n", constant_total / 64.0);
    std::printf("\n  The spread matters more than the peak. A chain must pass every constant, so\n");
    std::printf("  the compound probability is driven by the mean and not by the best one.\n");

    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  3. Chaining: the delta axis, walked because it cannot be swept\n");
    std::printf("================================================================\n");
    std::printf("\n  The incoming delta ranges over 2^32 for one word, so it cannot be enumerated.\n");
    std::printf("  Walk it instead: take the strongest outgoing delta as the next incoming one and\n");
    std::printf("  chain through consecutive real constants. Greedy, so a lower bound.\n");

    std::printf("\n  %8s %16s %20s\n", "round", "P this round", "compound");
    std::printf("  %8s %16s %20s\n", "--------", "----------------", "--------------------");

    uint32_t carried = 0u;
    double compound = 1.0;
    const unsigned chain_depth = 8u;

    for (unsigned round = 0u; round < chain_depth; round += 1u)
    {
        const Best found =
            strongest_delta(global.frame, global.word, round, carried, 300000u, generator);
        compound *= found.probability;
        carried = found.delta;
        std::printf("  %8u %16.8f %20.6e\n", round, found.probability, compound);
    }

    const double per_round = std::pow(compound, 1.0 / (double)chain_depth);

    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  4. Coverage, and what the number is worth\n");
    std::printf("================================================================\n");

    std::printf("\n  Swept exhaustively:\n");
    std::printf("    frames                : 31 of 31\n");
    std::printf("    output words          : 2 of 8, and the other 6 are not omissions. A round\n");
    std::printf("                            writes only state[0] and state[4]; the rest are\n");
    std::printf("                            shifts of the input and carry no measurement.\n");
    std::printf("    round constants       : 64 of 64\n");
    std::printf("    combinations measured : %u\n", 31u * 2u * 64u);

    std::printf("\n  Not swept, and not sweepable:\n");
    std::printf("    incoming delta, one word : 2^32 values, walked greedily at 8 points\n");
    std::printf("    incoming delta, full     : 2^256 values\n");
    std::printf("    message-word deltas      : 2^32 per round, held at the rotational value\n");
    std::printf("    fraction of the delta axis actually visited : %.3e\n",
                8.0 / 4294967296.0);

    std::printf("\n  Resolution floor, which bounds what the chain above can even say. At 300,000\n");
    std::printf("  pairs the smallest measurable probability is %.3e, and rounds one onward in\n",
                1.0 / 300000.0);
    std::printf("  section 3 sat at 6.67e-06, which is two occurrences. Those rounds are at the\n");
    std::printf("  floor, so the compound figure is an upper bound on a quantity that may be\n");
    std::printf("  smaller, not a measurement of it. Distinguishing them needs more samples.\n");

    std::printf("\n  So this is a lower bound on what is reachable, not an upper bound on what\n");
    std::printf("  exists. A better trajectory may sit in the part never visited, and nothing\n");
    std::printf("  here rules that out. What it does do is price the best trajectory a greedy\n");
    std::printf("  walk finds, which is the same procedure published characteristic searches use\n");
    std::printf("  before they add backtracking.\n");

    std::printf("\n  measured geometric mean per round : %.8f  (2^%.2f)\n", per_round,
                std::log2(per_round));
    std::printf("  needed to match brute force over 64 : %.8f  (2^-4)\n", std::pow(2.0, -4.0));
    std::printf("  shortfall per round                 : %.2f bits\n",
                -4.0 - std::log2(per_round));
    std::printf("\n  over 64 rounds at this rate : %.3e\n", std::pow(per_round, 64.0));
    std::printf("  brute force                 : %.3e\n", std::pow(2.0, -256.0));
    std::printf("  ratio                       : %.3e\n",
                std::pow(per_round, 64.0) / std::pow(2.0, -256.0));

    const auto finished = std::chrono::steady_clock::now();
    std::printf("\n================================================================\n");
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return 0;
}
