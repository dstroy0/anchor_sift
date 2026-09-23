/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_schedule.cpp
 * @brief The message schedule on its own: a linear code with carry corrections, and what it leaks.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Every projection tried in this tree so far attacked the compression function, and all of
 *       them died by round 10 of 128. The schedule is a different and weaker object and had not been
 *       touched. It is also where the one real structural win in Bitcoin mining lives: ASICBoost
 *       exploits the schedule's independence from the chaining value, not any property of the digest.
 * @note W[t] = W[t-16] + sigma0(W[t-15]) + W[t-7] + sigma1(W[t-2]) for t in [16,64). Both sigma
 *       functions are rotations, shifts and exclusive or, so both are GF(2)-linear. Only the three
 *       modular additions leave that basis. Replace them with exclusive or and the whole expansion
 *       becomes a linear map from 512 bits to 2048, which is a code with a weight distribution.
 * @note Four questions: is the linearity claim true; how much do the carries actually matter; what
 *       does a single input bit weigh on the output, which is what decides whether good differential
 *       characteristics exist; and in the mining case where twelve of sixteen input words are
 *       literal constants, how much of the expansion is free.
 */

#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <vector>

namespace
{

int g_checks_run = 0;
int g_checks_failed = 0;

/**
 * @brief Records one check and prints it.
 *
 * @param[in] name   What was checked.
 * @param[in] passed Whether it held.
 * @param[in] detail What was seen, printed on failure.
 */
void check(const std::string &name, bool passed, const std::string &detail = "")
{
    g_checks_run += 1;
    if (passed)
    {
        std::printf("  [PASS] %s\n", name.c_str());
    }
    else
    {
        g_checks_failed += 1;
        std::printf("  [FAIL] %s\n", name.c_str());
        if (!detail.empty())
        {
            std::printf("         %s\n", detail.c_str());
        }
    }
}

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

/** @brief The schedule's low spreading function. Rotations, a shift and exclusive or only. */
uint32_t spread_low(uint32_t value)
{
    return rotate_right(value, 7u) ^ rotate_right(value, 18u) ^ (value >> 3u);
}

/** @brief The schedule's high spreading function. Rotations, a shift and exclusive or only. */
uint32_t spread_high(uint32_t value)
{
    return rotate_right(value, 17u) ^ rotate_right(value, 19u) ^ (value >> 10u);
}

/**
 * @brief Expands sixteen words to sixty-four, the way the standard does.
 *
 * @param[in]  block    Sixteen words [BORROWS].
 * @param[out] schedule Sixty-four words [BORROWS].
 */
void expand_real(const uint32_t *block, uint32_t *schedule)
{
    for (unsigned slot = 0u; slot < 16u; slot += 1u)
    {
        schedule[slot] = block[slot];
    }
    for (unsigned slot = 16u; slot < 64u; slot += 1u)
    {
        schedule[slot] = spread_high(schedule[slot - 2u]) + schedule[slot - 7u] +
                         spread_low(schedule[slot - 15u]) + schedule[slot - 16u];
    }
}

/**
 * @brief Expands sixteen words to sixty-four with every addition replaced by exclusive or.
 *
 * @param[in]  block    Sixteen words [BORROWS].
 * @param[out] schedule Sixty-four words [BORROWS].
 * @note This is the GF(2)-linear approximation of the schedule. It is not SHA-256 and must never
 *       hash anything. It exists so the real expansion can be measured against a linear object.
 */
void expand_linear(const uint32_t *block, uint32_t *schedule)
{
    for (unsigned slot = 0u; slot < 16u; slot += 1u)
    {
        schedule[slot] = block[slot];
    }
    for (unsigned slot = 16u; slot < 64u; slot += 1u)
    {
        schedule[slot] = spread_high(schedule[slot - 2u]) ^ schedule[slot - 7u] ^
                         spread_low(schedule[slot - 15u]) ^ schedule[slot - 16u];
    }
}

/**
 * @brief Counts set bits across a schedule's expanded portion.
 *
 * @param[in] schedule Sixty-four words [BORROWS].
 * @return             Hamming weight of words 16 through 63.
 */
unsigned expanded_weight(const uint32_t *schedule)
{
    unsigned weight = 0u;

    for (unsigned slot = 16u; slot < 64u; slot += 1u)
    {
        weight += (unsigned)__builtin_popcount(schedule[slot]);
    }
    return weight;
}

/**
 * @brief Confirms the linearity claim the rest of the file depends on.
 */
void check_linearity()
{
    std::printf("\n================================================================\n");
    std::printf("  0. Control. Are sigma0 and sigma1 really GF(2)-linear?\n");
    std::printf("================================================================\n");

    std::mt19937 generator(20260908u);
    bool low_linear = true;
    bool high_linear = true;
    bool expansion_linear = true;

    for (unsigned trial = 0u; trial < 200000u; trial += 1u)
    {
        const uint32_t left = generator();
        const uint32_t right = generator();

        if (spread_low(left ^ right) != (spread_low(left) ^ spread_low(right)))
        {
            low_linear = false;
        }
        if (spread_high(left ^ right) != (spread_high(left) ^ spread_high(right)))
        {
            high_linear = false;
        }
    }

    // The linearised expansion must itself be linear as a whole map, not only in its parts.
    for (unsigned trial = 0u; trial < 20000u; trial += 1u)
    {
        uint32_t left_block[16];
        uint32_t right_block[16];
        uint32_t sum_block[16];

        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            left_block[slot] = generator();
            right_block[slot] = generator();
            sum_block[slot] = left_block[slot] ^ right_block[slot];
        }

        uint32_t left_schedule[64];
        uint32_t right_schedule[64];
        uint32_t sum_schedule[64];
        expand_linear(left_block, left_schedule);
        expand_linear(right_block, right_schedule);
        expand_linear(sum_block, sum_schedule);

        for (unsigned slot = 0u; slot < 64u; slot += 1u)
        {
            if (sum_schedule[slot] != (left_schedule[slot] ^ right_schedule[slot]))
            {
                expansion_linear = false;
            }
        }
    }

    check("sigma0 is GF(2)-linear", low_linear);
    check("sigma1 is GF(2)-linear", high_linear);
    check("the xor-linearised expansion is linear as a whole map", expansion_linear);
    std::printf("\n  So the only thing standing between the schedule and a linear code is the\n");
    std::printf("  three modular additions per word. Section 2 measures what they are worth.\n");
}

/**
 * @brief Measures how far the real expansion departs from its linear approximation.
 */
void measure_carry_cost()
{
    std::printf("\n================================================================\n");
    std::printf("  1. How much do the carries actually matter?\n");
    std::printf("================================================================\n");
    std::printf("\n  Real expansion against the xor-linearised one, same input. Agreement per\n");
    std::printf("  expanded word, and the Hamming distance between the two full expansions.\n");

    std::mt19937 generator(20260908u);
    const unsigned trials = 100000u;
    std::vector<uint64_t> word_matches(64u, 0u);
    uint64_t distance_total = 0u;

    for (unsigned trial = 0u; trial < trials; trial += 1u)
    {
        uint32_t block[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            block[slot] = generator();
        }

        uint32_t real_schedule[64];
        uint32_t linear_schedule[64];
        expand_real(block, real_schedule);
        expand_linear(block, linear_schedule);

        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            if (real_schedule[slot] == linear_schedule[slot])
            {
                word_matches[slot] += 1u;
            }
            distance_total +=
                (uint64_t)__builtin_popcount(real_schedule[slot] ^ linear_schedule[slot]);
        }
    }

    std::printf("\n  %8s %18s\n", "word", "exact agreement");
    std::printf("  %8s %18s\n", "--------", "------------------");
    for (unsigned slot : {16u, 17u, 18u, 20u, 24u, 32u, 48u, 63u})
    {
        std::printf("  %8u %17.4f%%\n", slot,
                    100.0 * (double)word_matches[slot] / (double)trials);
    }

    const double mean_distance = (double)distance_total / (double)trials;
    std::printf("\n  mean Hamming distance over words 16-63 : %.1f of 1536 bits (%.1f%%)\n",
                mean_distance, 100.0 * mean_distance / 1536.0);
    std::printf("\n  Agreement is zero from the very first expanded word, and the mean distance\n");
    std::printf("  is 50%% of the bits, which is what two unrelated values give. W[16] already\n");
    std::printf("  sums four dense random words, and four random addends almost never sum\n");
    std::printf("  without a carry anywhere. So on dense inputs the linear approximation is\n");
    std::printf("  worth nothing, immediately, not gradually.\n");
    std::printf("\n  That is the wrong test for the question that matters, and section 1b is the\n");
    std::printf("  right one. Cryptanalysis does not approximate the schedule on dense values.\n");
    std::printf("  It tracks a sparse difference, and a modular sum carries a low-weight xor\n");
    std::printf("  difference far more faithfully than it carries a dense value.\n");
}

/**
 * @brief The differential form of the same question, which is the one attacks actually ask.
 *
 * @note Section 1 measured whether the real expansion equals its linear approximation on dense
 *       inputs. It does not, at any word. But a differential attack never needs that. It needs the
 *       real expansion's *difference* under a sparse input difference to match the linear code's
 *       difference, and a modular addition preserves a low-weight xor difference with probability
 *       far above chance. This measures where that stops being true, by difference weight.
 */
void measure_differential_fidelity()
{
    std::printf("\n================================================================\n");
    std::printf("  1b. Sparse differences: where the linear code still describes it\n");
    std::printf("================================================================\n");
    std::printf("\n  Input difference of weight w applied to W[3], the nonce word. How often does\n");
    std::printf("  the real expansion's difference equal the linear code's prediction, exactly,\n");
    std::printf("  across the expanded words? This is the probability a characteristic holds.\n");

    std::mt19937 generator(20260908u);
    const unsigned trials = 200000u;

    std::printf("\n  Measured from W[18], which is the first expanded word the nonce reaches.\n");
    std::printf("  W[16] and W[17] do not depend on W[3] at all, so their difference is zero on\n");
    std::printf("  both sides and any test including them reports a perfect 100%% that is really\n");
    std::printf("  zero equals zero. An earlier version of this table did exactly that.\n");

    std::printf("\n  %8s", "weight");
    for (unsigned slot = 18u; slot <= 24u; slot += 1u)
    {
        std::printf(" %8u", slot);
    }
    std::printf("\n  %8s", "--------");
    for (unsigned slot = 18u; slot <= 24u; slot += 1u)
    {
        std::printf(" %8s", "--------");
    }
    std::printf("\n");

    for (unsigned weight = 1u; weight <= 4u; weight += 1u)
    {
        std::vector<unsigned> held_at(25u, 0u);
        unsigned held_short = 0u;
        unsigned held_long = 0u;

        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            uint32_t difference = 0u;
            unsigned placed = 0u;
            while (placed < weight)
            {
                const uint32_t bit = (1u << (generator() % 32u));
                if ((difference & bit) == 0u)
                {
                    difference |= bit;
                    placed += 1u;
                }
            }

            uint32_t block_one[16];
            uint32_t block_two[16];
            for (unsigned slot = 0u; slot < 16u; slot += 1u)
            {
                block_one[slot] = generator();
                block_two[slot] = block_one[slot];
            }
            block_two[3] ^= difference;

            uint32_t real_one[64];
            uint32_t real_two[64];
            uint32_t linear_one[64];
            uint32_t linear_two[64];
            expand_real(block_one, real_one);
            expand_real(block_two, real_two);
            expand_linear(block_one, linear_one);
            expand_linear(block_two, linear_two);

            // Cumulative: the characteristic holds through slot only if it held at every word
            // up to it, which is what a multi-round characteristic actually requires.
            bool still_holding = true;
            for (unsigned slot = 18u; slot <= 24u; slot += 1u)
            {
                if ((real_one[slot] ^ real_two[slot]) != (linear_one[slot] ^ linear_two[slot]))
                {
                    still_holding = false;
                }
                if (still_holding)
                {
                    held_at[slot] += 1u;
                }
            }
        }

        std::printf("  %8u", weight);
        for (unsigned slot = 18u; slot <= 24u; slot += 1u)
        {
            std::printf(" %7.3f%%", 100.0 * (double)held_at[slot] / (double)trials);
        }
        std::printf("\n");
        (void)held_short;
        (void)held_long;
    }

    std::printf("\n  This is the real shape of the object. On dense values the linear code is\n");
    std::printf("  useless from word 16. On a sparse difference it describes the first couple of\n");
    std::printf("  expanded words with high probability and then decays. That decay rate is what\n");
    std::printf("  a characteristic search is fighting, and it is why published attacks reach the\n");
    std::printf("  round counts they do and no further.\n");
}

/**
 * @brief Measures what one input bit weighs on the expansion, which decides characteristic search.
 */
void measure_weight_profile()
{
    std::printf("\n================================================================\n");
    std::printf("  2. What does one input bit weigh on the output?\n");
    std::printf("================================================================\n");
    std::printf("\n  In the linearised code a single input bit produces a fixed output difference,\n");
    std::printf("  so its weight is exact instead of sampled. A low weight would be a usable\n");
    std::printf("  differential characteristic. Random would be about 768 of 1536.\n");

    unsigned lowest = 0xFFFFFFFFu;
    unsigned highest = 0u;
    unsigned lowest_word = 0u;
    unsigned lowest_bit = 0u;
    uint64_t weight_total = 0u;

    for (unsigned word = 0u; word < 16u; word += 1u)
    {
        for (unsigned bit = 0u; bit < 32u; bit += 1u)
        {
            uint32_t block[16];
            std::memset(block, 0, sizeof(block));
            block[word] = (1u << bit);

            uint32_t schedule[64];
            expand_linear(block, schedule);
            const unsigned weight = expanded_weight(schedule);

            weight_total += weight;
            if (weight < lowest)
            {
                lowest = weight;
                lowest_word = word;
                lowest_bit = bit;
            }
            highest = std::max(highest, weight);
        }
    }

    std::printf("\n  over all 512 single-bit input differences:\n");
    std::printf("    lowest weight  : %u bits, at word %u bit %u\n", lowest, lowest_word,
                lowest_bit);
    std::printf("    highest weight : %u bits\n", highest);
    std::printf("    mean weight    : %.1f bits of 1536\n", (double)weight_total / 512.0);
    std::printf("\n  The lowest-weight entry is the best single-bit characteristic this code\n");
    std::printf("  admits, and it is the seed a characteristic search would start from. Note\n");
    std::printf("  which word it sits in: the later input words feed fewer expansion steps, so\n");
    std::printf("  they weigh less, and that is a property of the recursion's shape instead of\n");
    std::printf("  of anything cryptographic.\n");
}

/**
 * @brief The mining case, where twelve of sixteen input words are literal constants.
 */
void measure_mining_schedule()
{
    std::printf("\n================================================================\n");
    std::printf("  3. The mining schedule. Twelve of sixteen words are constants.\n");
    std::printf("================================================================\n");
    std::printf("\n  The header's second block is merkle tail, ntime, nbits, nonce, then padding:\n");
    std::printf("  W[4] = 0x80000000, W[5..14] = 0, W[15] = 0x280. Only W[0..3] carry anything,\n");
    std::printf("  and within one job only W[3], the nonce, moves per candidate.\n");

    // Trace which expanded words depend on W[3] at all. Dependency is structural, so this is exact.
    bool depends[64];
    for (unsigned slot = 0u; slot < 64u; slot += 1u)
    {
        depends[slot] = (slot == 3u);
    }
    for (unsigned slot = 16u; slot < 64u; slot += 1u)
    {
        depends[slot] = depends[slot - 2u] || depends[slot - 7u] || depends[slot - 15u] ||
                        depends[slot - 16u];
    }

    unsigned independent = 0u;
    std::printf("\n  expanded words independent of the nonce: ");
    for (unsigned slot = 16u; slot < 64u; slot += 1u)
    {
        if (!depends[slot])
        {
            std::printf("%u ", slot);
            independent += 1u;
        }
    }
    if (independent == 0u)
    {
        std::printf("(none)");
    }
    std::printf("\n");

    unsigned first_dependent_round = 64u;
    for (unsigned slot = 0u; slot < 64u; slot += 1u)
    {
        if (depends[slot])
        {
            first_dependent_round = slot;
            break;
        }
    }

    std::printf("\n  rounds computable before the nonce is needed : %u of 64\n",
                first_dependent_round);
    std::printf("  expanded words precomputable per job         : %u of 48\n", independent);
    std::printf("  total schedule work saved per candidate      : %.1f%%\n",
                100.0 * (double)independent / 48.0);

    // Confirm the dependency trace against the real function instead of trusting the recursion.
    std::mt19937 generator(20260908u);
    bool trace_correct = true;

    for (unsigned trial = 0u; trial < 4096u; trial += 1u)
    {
        uint32_t block_one[16];
        uint32_t block_two[16];
        block_one[0] = generator();
        block_one[1] = generator();
        block_one[2] = generator();
        block_one[3] = generator();
        block_one[4] = 0x80000000u;
        for (unsigned slot = 5u; slot < 15u; slot += 1u)
        {
            block_one[slot] = 0u;
        }
        block_one[15] = 0x00000280u;
        std::memcpy(block_two, block_one, sizeof(block_one));
        block_two[3] = generator();

        uint32_t schedule_one[64];
        uint32_t schedule_two[64];
        expand_real(block_one, schedule_one);
        expand_real(block_two, schedule_two);

        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            if (!depends[slot] && (schedule_one[slot] != schedule_two[slot]))
            {
                trace_correct = false;
            }
        }
    }
    check("the dependency trace matches the real expansion", trace_correct);

    std::printf("\n  This is the same structural fact ASICBoost exploits, seen from the other\n");
    std::printf("  side. ASICBoost holds the whole second block fixed across candidates so the\n");
    std::printf("  entire expansion is shared. Holding only the nonce variable, as an ordinary\n");
    std::printf("  miner does, shares whatever the trace above says is independent of it.\n");
}

/**
 * @brief What the finding is worth to the engine in this tree, measured instead of asserted.
 */
void measure_engine_value()
{
    std::printf("\n================================================================\n");
    std::printf("  4. What this is worth to the engine here\n");
    std::printf("================================================================\n");

    const unsigned trials = 200000u;
    uint32_t block[16];
    block[0] = 0xc7f5d74du;
    block[1] = 0xf2b9441au;
    block[2] = 0x42a14695u;
    block[4] = 0x80000000u;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        block[slot] = 0u;
    }
    block[15] = 0x00000280u;

    uint32_t schedule[64];
    volatile uint32_t sink = 0u;

    auto started = std::chrono::steady_clock::now();
    for (unsigned trial = 0u; trial < trials; trial += 1u)
    {
        block[3] = trial;
        expand_real(block, schedule);
        sink ^= schedule[63];
    }
    auto finished = std::chrono::steady_clock::now();
    const double full_seconds = std::chrono::duration<double>(finished - started).count();

    // Now the same work with the nonce-independent prefix hoisted out of the loop.
    block[3] = 0u;
    expand_real(block, schedule);
    uint32_t cached[64];
    std::memcpy(cached, schedule, sizeof(cached));

    started = std::chrono::steady_clock::now();
    for (unsigned trial = 0u; trial < trials; trial += 1u)
    {
        uint32_t working[64];
        std::memcpy(working, cached, 18u * sizeof(uint32_t));
        working[3] = trial;
        // Words 16 and 17 are already correct; recompute from 18 onward.
        for (unsigned slot = 18u; slot < 64u; slot += 1u)
        {
            working[slot] = spread_high(working[slot - 2u]) + working[slot - 7u] +
                            spread_low(working[slot - 15u]) + working[slot - 16u];
        }
        sink ^= working[63];
    }
    finished = std::chrono::steady_clock::now();
    const double hoisted_seconds = std::chrono::duration<double>(finished - started).count();

    std::printf("\n  full expansion per candidate   : %.0f per second\n",
                (full_seconds > 0.0) ? ((double)trials / full_seconds) : 0.0);
    std::printf("  with the free prefix hoisted   : %.0f per second\n",
                (hoisted_seconds > 0.0) ? ((double)trials / hoisted_seconds) : 0.0);
    std::printf("  speedup on the expansion alone : %.3fx\n",
                (hoisted_seconds > 0.0) ? (full_seconds / hoisted_seconds) : 0.0);
    std::printf("\n  The expansion is roughly half of one compression, and a candidate costs two\n");
    std::printf("  compressions, so this is worth about a quarter of that speedup end to end.\n");
    std::printf("  Small, real, and already partly taken by the midstate. It is reported here\n");
    std::printf("  because a measured small number is worth more than an unmeasured large one.\n");
    (void)sink;
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  The message schedule as an object in its own right\n");
    std::printf("================================================================\n");

    check_linearity();
    measure_carry_cost();
    measure_differential_fidelity();
    measure_weight_profile();
    measure_mining_schedule();
    measure_engine_value();

    std::printf("\n================================================================\n");
    std::printf("  %d checks run, %d failed\n", g_checks_run, g_checks_failed);
    std::printf("================================================================\n");
    return (g_checks_failed == 0) ? 0 : 1;
}
