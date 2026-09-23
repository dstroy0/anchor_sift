/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_deltanull.cpp
 * @brief The Sigma-delta null applied to this tree's own headline result.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note From anchor_sift/docs/research/terms.md and anchor-sift.md section 2.1. Let Pi_Sigma be the
 *       family of permutations preserving the observed carrier counts and stated partition. For a
 *       statistic M the residual is
 *
 *           Delta_Sigma[M] = M(x) - E_{pi ~ Pi_Sigma}[ M(pi(x)) ]
 *
 *       The delta null measures what remains after the carrier projects its structure and examines
 *       itself. It does not claim a hidden generator has been reconstructed and it does not invoke
 *       Laplace's demon.
 * @note This file exists because every error in this workbook has one shape: a measurement compared
 *       against an analytical null derived by hand, where the null was wrong. The nibble-geometric
 *       overshoot model, the K xor rotr(K,r) offset, and the expected-worst-of-3840 estimate were all
 *       hand-derived and all wrong, and each produced a result that looked like a finding. A
 *       permutation null cannot be wrong in that way, because it preserves the carrier's own counts
 *       by construction instead of by my arithmetic.
 * @note The statistic under test is the one this tree reported as its strongest positive: the
 *       concentration of the rotational-XOR delta, measured at 775,000 times uniform. The question
 *       the delta null asks is whether that concentration belongs to the *pairing* between the two
 *       members, which would be real structure, or to the marginal distribution of the outputs,
 *       which a permutation preserves and which would make it an artifact.
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

/** @brief The frame the earlier sweep selected. */
const unsigned FRAME = 31u;

/** @brief The standard's first round constant, the one the RX measurement used. */
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
 * @brief The statistic under test: how concentrated the most common delta is.
 *
 * @param[in] left  Word-0 outputs of the first member, one per pair [BORROWS].
 * @param[in] right Word-0 outputs of the second member, one per pair [BORROWS].
 * @param[in] order Which right element pairs with each left element [BORROWS].
 * @return          Frequency of the most common delta under that pairing.
 * @note The delta is right[order[i]] xor rotr(left[i], FRAME), which is the rotational-XOR
 *       difference. Passing the identity as order gives the real measurement; passing a permutation
 *       gives one draw from the null.
 */
double concentration(const std::vector<uint32_t> &left, const std::vector<uint32_t> &right,
                     const std::vector<uint32_t> &order)
{
    std::unordered_map<uint32_t, uint32_t> counts;
    counts.reserve(left.size() / 2u);

    for (size_t at = 0u; at < left.size(); at += 1u)
    {
        counts[right[order[at]] ^ rotate_right(left[at], FRAME)] += 1u;
    }

    uint32_t best = 0u;
    for (const auto &entry : counts)
    {
        best = std::max(best, entry.second);
    }
    return (double)best / (double)left.size();
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  The Sigma-delta null, applied to this tree's own result\n");
    std::printf("================================================================\n");
    std::printf("\n  Delta_Sigma[M] = M(x) - E_pi[ M(pi(x)) ], with Pi_Sigma the permutations that\n");
    std::printf("  preserve the observed carrier counts. Here M is the concentration of the most\n");
    std::printf("  common rotational-XOR delta, and pi re-pairs the two members while leaving both\n");
    std::printf("  output multisets exactly as measured.\n");
    std::printf("\n  If the concentration lives in the pairing, permuting destroys it and the\n");
    std::printf("  residual is large. If it lives in the marginals, the permutation preserves it\n");
    std::printf("  and the residual is near zero, which would make the 775,000-fold figure a\n");
    std::printf("  property of the output distribution instead of of the rotational relation.\n");

    const unsigned pairs = 2000000u;
    std::mt19937 generator(bench_seed(20260908u));

    std::vector<uint32_t> left;
    std::vector<uint32_t> right;
    left.reserve(pairs);
    right.reserve(pairs);

    for (unsigned trial = 0u; trial < pairs; trial += 1u)
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
        run_round(turned, rotate_right(message, FRAME));

        left.push_back(plain[0]);
        right.push_back(turned[0]);
    }

    std::vector<uint32_t> order(pairs);
    for (unsigned at = 0u; at < pairs; at += 1u)
    {
        order[at] = at;
    }

    const auto started = std::chrono::steady_clock::now();
    const double measured = concentration(left, right, order);

    std::printf("\n  M(x), the real pairing : %.8f%%\n", measured * 100.0);

    // Sample the null. Each draw re-pairs the members and leaves both multisets untouched.
    const unsigned draws = 12u;
    double null_total = 0.0;
    double null_low = 1.0;
    double null_high = 0.0;

    std::printf("\n  %8s %18s\n", "draw", "M(pi(x))");
    std::printf("  %8s %18s\n", "--------", "------------------");

    for (unsigned draw = 0u; draw < draws; draw += 1u)
    {
        std::shuffle(order.begin(), order.end(), generator);
        const double value = concentration(left, right, order);

        null_total += value;
        null_low = std::min(null_low, value);
        null_high = std::max(null_high, value);
        std::printf("  %8u %17.8f%%\n", draw, value * 100.0);
    }

    const double null_mean = null_total / (double)draws;
    const double residual = measured - null_mean;
    const auto finished = std::chrono::steady_clock::now();

    std::printf("\n================================================================\n");
    std::printf("  The residual\n");
    std::printf("================================================================\n");
    std::printf("\n  M(x)                  : %.8f%%\n", measured * 100.0);
    std::printf("  E_pi[M(pi(x))]        : %.8f%%   over %u draws, range %.8f%% to %.8f%%\n",
                null_mean * 100.0, draws, null_low * 100.0, null_high * 100.0);
    std::printf("  Delta_Sigma[M]        : %+.8f%%\n", residual * 100.0);
    std::printf("  ratio, measured / null: %.2f\n",
                (null_mean > 0.0) ? (measured / null_mean) : 0.0);

    std::printf("\n  uniform over 2^32     : %.3e%%\n", 100.0 / 4294967296.0);
    std::printf("  measured over uniform : %.3e\n", measured * 4294967296.0);
    std::printf("  null over uniform     : %.3e\n", null_mean * 4294967296.0);

    std::printf("\n  Reading it. The concentration over uniform was reported earlier as the\n");
    std::printf("  headline, and the uniform reference is a hand-derived analytical null. The\n");
    std::printf("  permutation null is the one that cannot be derived wrongly, and the residual\n");
    std::printf("  above is what survives it. A residual near zero would mean the earlier figure\n");
    std::printf("  measured the shape of the output distribution instead of the rotational\n");
    std::printf("  pairing, and the headline would have to be withdrawn to that extent.\n");

    // -------------------------------------------------------------------------------------
    // The peak is one statistic. The eddy is the whole distribution, and anchor-sift already
    // has the right currency for it: section 2.5 prices an anchor at q = 2^-H2, so the
    // collision entropy of the delta distribution is the cost of an anchor placed on it.
    // -------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  The eddy priced in anchor-sift's own currency\n");
    std::printf("================================================================\n");
    std::printf("\n  A peak is one number. The eddy is the distribution's shape, and section 2.5\n");
    std::printf("  prices an anchor at q = 2^-H2 where H2 is collision entropy. So H2 of the delta\n");
    std::printf("  distribution is exactly what an anchor placed on the delta would cost, and the\n");
    std::printf("  shortfall from 32 is how many bits of coherence the eddy actually carries.\n");

    for (int pass = 0; pass < 2; pass += 1)
    {
        const bool real_pairing = (pass == 0);
        if (real_pairing)
        {
            for (unsigned at = 0u; at < pairs; at += 1u)
            {
                order[at] = at;
            }
        }
        else
        {
            std::shuffle(order.begin(), order.end(), generator);
        }

        std::unordered_map<uint32_t, uint32_t> counts;
        counts.reserve(pairs / 2u);
        for (size_t at = 0u; at < pairs; at += 1u)
        {
            counts[right[order[at]] ^ rotate_right(left[at], FRAME)] += 1u;
        }

        // Unbiased estimator of the collision probability. The naive sum of squared frequencies
        // is biased upward at this sparsity and would invent structure that is not there.
        long double collision_pairs = 0.0L;
        for (const auto &entry : counts)
        {
            const long double count = (long double)entry.second;
            collision_pairs += count * (count - 1.0L);
        }
        const long double total_pairs = (long double)pairs * ((long double)pairs - 1.0L);
        const long double collision_probability = collision_pairs / total_pairs;
        const double entropy =
            (collision_probability > 0.0L) ? -std::log2((double)collision_probability) : 32.0;

        std::printf("\n  %s\n", real_pairing ? "real rotational pairing:" : "permuted pairing:");
        std::printf("    distinct deltas seen : %zu\n", counts.size());
        std::printf("    collision probability: %.6e\n", (double)collision_probability);
        std::printf("    H2                   : %.6f bits\n", entropy);
        std::printf("    shortfall from 32    : %.6f bits\n", 32.0 - entropy);
        std::printf("    anchor cost q = 2^-H2: %.6e\n", std::pow(2.0, -entropy));

        // Order two answers the collision question. Arikan's bound says search is governed by
        // order one half, which is a different number, and this workbook has been quoting the
        // first as though it answered the second.
        //
        // Order one half cannot be estimated from a sample this sparse, and the reason is worth
        // printing instead of hiding. The plug-in estimator is 2 log2(sum sqrt(p)), and where
        // every observed delta is a singleton that sum is exactly sqrt(n), so the estimate reads
        // log2(n) no matter what the truth is. The ceiling below is that artefact stated in
        // advance, so the estimate beside it is never mistaken for a measurement.
        long double root_mass = 0.0L;
        uint32_t largest = 0u;
        size_t singletons = 0u;
        for (const auto &entry : counts)
        {
            root_mass += std::sqrt((long double)entry.second / (long double)pairs);
            largest = (entry.second > largest) ? entry.second : largest;
            singletons += (entry.second == 1u) ? 1u : 0u;
        }

        const double plug_in_half = 2.0 * std::log2((double)root_mass);
        const double ceiling = std::log2((double)pairs);
        const double min_entropy = -std::log2((double)largest / (double)pairs);

        std::printf("    H_1/2 plug-in        : %.6f bits, against a ceiling of %.6f set by the\n",
                    plug_in_half, ceiling);
        std::printf("                           sample size alone. Not a measurement.\n");
        std::printf("    H_inf                : %.6f bits\n", min_entropy);
        std::printf("    unseen mass, f1 / n  : %.6f\n", (double)singletons / (double)pairs);
        std::printf("    H_1/2 bounded below  : %.6f bits, since H_alpha decreases in alpha and\n",
                    entropy);
        std::printf("                           H_2 is estimable here while H_1/2 is not.\n");
    }

    std::printf("\n  Reading it. A delta distribution at H2 = 32 is flat and an anchor on it costs\n");
    std::printf("  2^-32, which is what the digest itself already costs, so it buys nothing. Every\n");
    std::printf("  bit of shortfall is a bit the eddy carries and a bit the anchor is cheaper by.\n");
    std::printf("\n  The permuted row is the control. Its shortfall is whatever a finite sample of\n");
    std::printf("  this size produces against a flat distribution, and only the difference between\n");
    std::printf("  the two rows is coherence instead of sampling.\n");

    // -------------------------------------------------------------------------------------
    // Treat the mode as a center of gravity and map outward from it. If the mass is
    // concentrated, walking deltas in descending probability covers the distribution fastest,
    // and the profile below is exactly how many candidates a search has to carry.
    // -------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Mapping outward from the center of gravity\n");
    std::printf("================================================================\n");
    std::printf("\n  Order the deltas by mass and walk out from the densest. How many does it take\n");
    std::printf("  to cover a given share of the distribution? That count is what a characteristic\n");
    std::printf("  search must carry, and it is the operational form of the entropy above.\n");

    {
        for (unsigned at = 0u; at < pairs; at += 1u)
        {
            order[at] = at;
        }
        std::unordered_map<uint32_t, uint32_t> counts;
        counts.reserve(pairs / 2u);
        for (size_t at = 0u; at < pairs; at += 1u)
        {
            counts[right[order[at]] ^ rotate_right(left[at], FRAME)] += 1u;
        }

        std::vector<uint32_t> masses;
        masses.reserve(counts.size());
        for (const auto &entry : counts)
        {
            masses.push_back(entry.second);
        }
        std::sort(masses.rbegin(), masses.rend());

        std::printf("\n  %10s %16s %18s\n", "coverage", "deltas needed", "share of 2^32");
        std::printf("  %10s %16s %18s\n", "----------", "----------------",
                    "------------------");

        const double wanted[] = {0.10, 0.25, 0.50, 0.75, 0.90, 0.99};
        for (double share : wanted)
        {
            uint64_t running = 0u;
            size_t needed = 0u;
            while ((needed < masses.size()) &&
                   ((double)running < (share * (double)pairs)))
            {
                running += masses[needed];
                needed += 1u;
            }
            std::printf("  %9.0f%% %16zu %18.3e\n", share * 100.0, needed,
                        (double)needed / 4294967296.0);
        }

        std::printf("\n  A flat distribution would need %.3e deltas to cover half its mass, which\n",
                    0.5 * 4294967296.0);
        std::printf("  is 2^31. The real one needs the count in the 50%% row. The ratio between\n");
        std::printf("  them is the same 15.5 bits the entropy reported, seen as a candidate count\n");
        std::printf("  instead of as a rate, and it is the number a search actually pays.\n");

        std::printf("\n  Which rows to trust. %zu distinct deltas came out of %u samples, so the\n",
                    masses.size(), pairs);
        std::printf("  mean count per delta is %.1f and the tail is singletons. The 10%% and 25%%\n",
                    (double)pairs / (double)masses.size());
        std::printf("  rows sit in the well-sampled head and are measurements. The 90%% and 99%%\n");
        std::printf("  rows approach the distinct count itself, which means they are counting how\n");
        std::printf("  many deltas happened to be seen once, not how many the distribution holds.\n");
        std::printf("  Those two rows are sampling artifacts and should not be read as coverage.\n");
    }

    std::printf("\n  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return 0;
}
