/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_frame.cpp
 * @brief Ride the rotating frame. Every possible frame, swept, with nothing assumed in advance.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The thought experiment: stop treating rotr as a thing done to the data and treat it as the
 *       field turning beneath the observer. Sit in the turning frame and rotr becomes the identity,
 *       because you are turning with it. Everything else must then be re-expressed in that frame.
 * @note This file assumes nothing about which frame is best or whether any is. It sweeps all
 *       thirty-two of them and reports the spectrum. A frame in which the construction is cheaper
 *       would appear as a peak, and the sweep is what decides whether one exists.
 * @note Three passes. What an addition costs in each frame. What a full round costs in each frame,
 *       with the constants present and absent, since an earlier ablation showed both the additions
 *       and the constants matter. Then how many rounds survive in whichever frame the sweep picks,
 *       instead of in a frame chosen by hand.
 */

#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
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
 * @brief Runs one round, optionally without its constant.
 *
 * @param[in,out] state         Eight working variables [BORROWS].
 * @param[in]     round         Which round.
 * @param[in]     schedule_word The message word.
 * @param[in]     use_constant  False zeroes the round constant.
 */
void run_round(uint32_t *state, unsigned round, uint32_t schedule_word, bool use_constant)
{
    const uint32_t constant = use_constant ? ROUND_CONSTANT[round] : 0u;
    const uint32_t carry_one = state[7] + mix_high(state[4]) +
                               choose(state[4], state[5], state[6]) + constant + schedule_word;
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
 * @brief Sweeps every frame and reports what an addition costs in each.
 *
 * @param[out] best_frame Where the strongest frame lands [BORROWS].
 * @return                The probability in that frame.
 */
double sweep_addition_frames(unsigned *best_frame)
{
    std::printf("\n================================================================\n");
    std::printf("  1. Every frame, one addition\n");
    std::printf("================================================================\n");
    std::printf("\n  In a frame turning by r, does a sum still look like a sum? Measured for all\n");
    std::printf("  thirty-one non-trivial frames, 2,000,000 pairs each. Nothing assumed.\n");

    std::mt19937 generator(20260908u);
    const unsigned trials = 2000000u;
    double best = 0.0;

    std::printf("\n  %6s %14s   %6s %14s\n", "frame", "holds", "frame", "holds");
    std::printf("  %6s %14s   %6s %14s\n", "------", "--------------", "------",
                "--------------");

    std::vector<double> rates(32u, 0.0);
    for (unsigned frame = 1u; frame < 32u; frame += 1u)
    {
        unsigned held = 0u;
        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            const uint32_t left = generator();
            const uint32_t right = generator();

            if (rotate_right(left + right, frame) ==
                (uint32_t)(rotate_right(left, frame) + rotate_right(right, frame)))
            {
                held += 1u;
            }
        }
        rates[frame] = (double)held / (double)trials;
        if (rates[frame] > best)
        {
            best = rates[frame];
            *best_frame = frame;
        }
    }

    for (unsigned frame = 1u; frame <= 16u; frame += 1u)
    {
        std::printf("  %6u %13.6f", frame, rates[frame]);
        if ((frame + 16u) < 32u)
        {
            std::printf("   %6u %13.6f", frame + 16u, rates[frame + 16u]);
        }
        std::printf("\n");
    }

    std::printf("\n  strongest frame: %u at %.6f\n", *best_frame, best);
    std::printf("  weakest        : %.6f\n", *std::min_element(rates.begin() + 1, rates.end()));
    std::printf("  ratio          : %.4f\n",
                best / *std::min_element(rates.begin() + 1, rates.end()));
    return best;
}

/**
 * @brief Sweeps every frame and reports what a full round costs in each.
 *
 * @param[in]  use_constant Whether the round constant is present.
 * @param[out] best_frame   Where the strongest frame lands [BORROWS].
 * @return                  The probability in that frame.
 */
double sweep_round_frames(bool use_constant, unsigned *best_frame)
{
    std::printf("\n  %s\n", use_constant ? "with the round constants present:"
                                         : "with the round constants removed:");

    std::mt19937 generator(20260908u);
    const unsigned trials = 400000u;
    double best = 0.0;
    *best_frame = 0u;

    std::vector<double> rates(32u, 0.0);
    for (unsigned frame = 1u; frame < 32u; frame += 1u)
    {
        unsigned held = 0u;
        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            uint32_t plain[8];
            uint32_t turned[8];
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                const uint32_t word = generator();
                plain[slot] = word;
                turned[slot] = rotate_right(word, frame);
            }
            const uint32_t word = generator();

            run_round(plain, 0u, word, use_constant);
            run_round(turned, 0u, rotate_right(word, frame), use_constant);

            bool matches = true;
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                if (turned[slot] != rotate_right(plain[slot], frame))
                {
                    matches = false;
                }
            }
            held += matches ? 1u : 0u;
        }
        rates[frame] = (double)held / (double)trials;
        if (rates[frame] > best)
        {
            best = rates[frame];
            *best_frame = frame;
        }
    }

    std::printf("    %6s %14s   %6s %14s\n", "frame", "holds", "frame", "holds");
    for (unsigned frame = 1u; frame <= 16u; frame += 1u)
    {
        std::printf("    %6u %13.6f", frame, rates[frame]);
        if ((frame + 16u) < 32u)
        {
            std::printf("   %6u %13.6f", frame + 16u, rates[frame + 16u]);
        }
        std::printf("\n");
    }
    std::printf("\n    strongest frame: %u at %.6f\n", *best_frame, best);
    return best;
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  Riding the rotating frame\n");
    std::printf("================================================================\n");
    std::printf("\n  Treat rotr not as an operation on the data but as the field turning under\n");
    std::printf("  the observer. Sit in the turning frame and rotr is the identity. The question\n");
    std::printf("  is what the rest of the construction costs once expressed there, and whether\n");
    std::printf("  any of the thirty-two available frames is cheaper than the others.\n");

    unsigned best_addition_frame = 0u;
    const double best_addition = sweep_addition_frames(&best_addition_frame);

    std::printf("\n================================================================\n");
    std::printf("  2. Every frame, one full round\n");
    std::printf("================================================================\n");

    unsigned best_open_frame = 0u;
    unsigned best_real_frame = 0u;
    const double best_open = sweep_round_frames(false, &best_open_frame);
    const double best_real = sweep_round_frames(true, &best_real_frame);

    std::printf("\n================================================================\n");
    std::printf("  3. Riding the strongest frame, round by round\n");
    std::printf("================================================================\n");

    if (best_open <= 0.0)
    {
        std::printf("\n  No frame survives even one round without constants, so there is nothing\n");
        std::printf("  to ride and section 3 does not apply.\n");
    }
    else
    {
        std::printf("\n  The sweep picked frame %u, not a frame chosen by hand. Ride it and count\n",
                    best_open_frame);
        std::printf("  how far the relation holds, constants removed so the ride is given every\n");
        std::printf("  advantage the construction allows.\n");

        std::mt19937 generator(4242u);
        const unsigned trials = 2000000u;

        std::printf("\n  %8s %16s %18s\n", "rounds", "holds", "predicted p^n");
        std::printf("  %8s %16s %18s\n", "--------", "----------------", "------------------");

        for (unsigned rounds : {1u, 2u, 3u, 4u, 5u, 6u})
        {
            unsigned held = 0u;
            for (unsigned trial = 0u; trial < trials; trial += 1u)
            {
                uint32_t plain[8];
                uint32_t turned[8];
                for (unsigned slot = 0u; slot < 8u; slot += 1u)
                {
                    const uint32_t word = generator();
                    plain[slot] = word;
                    turned[slot] = rotate_right(word, best_open_frame);
                }

                bool matches = true;
                for (unsigned round = 0u; round < rounds; round += 1u)
                {
                    const uint32_t word = generator();
                    run_round(plain, round, word, false);
                    run_round(turned, round, rotate_right(word, best_open_frame), false);
                }
                for (unsigned slot = 0u; slot < 8u; slot += 1u)
                {
                    if (turned[slot] != rotate_right(plain[slot], best_open_frame))
                    {
                        matches = false;
                    }
                }
                held += matches ? 1u : 0u;
            }

            std::printf("  %8u %15.6f%% %17.6f%%\n", rounds,
                        100.0 * (double)held / (double)trials,
                        100.0 * std::pow(best_open, (double)rounds));
        }

        std::printf("\n  Extrapolating the measured per-round rate to the depth a header hash\n");
        std::printf("  actually runs:\n");
        std::printf("    per round      : %.6f\n", best_open);
        std::printf("    over 64 rounds : %.3e\n", std::pow(best_open, 64.0));
        std::printf("    over 128       : %.3e\n", std::pow(best_open, 128.0));
        std::printf("    brute force    : %.3e   (2^-256)\n", std::pow(2.0, -256.0));
        std::printf("\n  And with the constants present, which is the real function, the strongest\n");
        std::printf("  frame holds at %.6f per round.\n", best_real);
    }

    std::printf("\n  best addition frame %u at %.6f, best round frame %u\n", best_addition_frame,
                best_addition, best_open_frame);
    std::printf("\n================================================================\n");
    return 0;
}
