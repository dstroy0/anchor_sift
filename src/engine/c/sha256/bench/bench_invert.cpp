/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_invert.cpp
 * @brief The round is a bijection. This maps what that buys and exactly where it stops buying.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The premise here is correct and is demonstrated instead of argued. SHA-256's round function
 *       loses nothing. Given the state after round t and the message word W[t], the state before it
 *       is recoverable exactly. Memoryless describes the statistics of the output, not the mechanism
 *       that produced it, and the mechanism is reversible at every step.
 * @note The entropy ceiling those statistics sit on is therefore artificial. It is constructed, and
 *       this file measures over how many rounds it gets constructed and which quantities can be
 *       tracked across it.
 * @note What the bijection does not supply is a solution. Inverting round t requires W[t], and in the
 *       mining problem the schedule is generated from the unknown. That circularity is mapped in
 *       section 3 instead of asserted.
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

/** @brief The standard's round constants, needed here because a round is run one at a time. */
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

/** @brief The eight working variables, in the standard's own order. */
struct Working
{
    uint32_t word[8];
};

/**
 * @brief Runs one round forward.
 *
 * @param[in,out] state         Working variables, advanced in place [BORROWS].
 * @param[in]     round         Which round, selecting the constant.
 * @param[in]     schedule_word The message word for this round.
 */
void round_forward(Working *state, unsigned round, uint32_t schedule_word)
{
    const uint32_t carry_one = state->word[7] + mix_high(state->word[4]) +
                               choose(state->word[4], state->word[5], state->word[6]) +
                               ROUND_CONSTANT[round] + schedule_word;
    const uint32_t carry_two =
        mix_low(state->word[0]) + majority(state->word[0], state->word[1], state->word[2]);

    state->word[7] = state->word[6];
    state->word[6] = state->word[5];
    state->word[5] = state->word[4];
    state->word[4] = state->word[3] + carry_one;
    state->word[3] = state->word[2];
    state->word[2] = state->word[1];
    state->word[1] = state->word[0];
    state->word[0] = carry_one + carry_two;
}

/**
 * @brief Runs one round backward, recovering the state that produced this one.
 *
 * @param[in,out] state         Working variables, rewound in place [BORROWS].
 * @param[in]     round         Which round, selecting the constant.
 * @param[in]     schedule_word The message word for this round.
 * @note Six of the eight variables are read straight back out of the shift. Those give the two
 *       mixing functions, which give carry_two, which gives carry_one from word zero, which gives
 *       the remaining two. Nothing is searched and nothing is approximated.
 */
void round_backward(Working *state, unsigned round, uint32_t schedule_word)
{
    // The shift is its own inverse for these six: a came from b, b from c, and so on.
    const uint32_t was_a = state->word[1];
    const uint32_t was_b = state->word[2];
    const uint32_t was_c = state->word[3];
    const uint32_t was_e = state->word[5];
    const uint32_t was_f = state->word[6];
    const uint32_t was_g = state->word[7];

    const uint32_t carry_two = mix_low(was_a) + majority(was_a, was_b, was_c);
    const uint32_t carry_one = state->word[0] - carry_two;
    const uint32_t was_d = state->word[4] - carry_one;
    const uint32_t was_h = carry_one - mix_high(was_e) - choose(was_e, was_f, was_g) -
                           ROUND_CONSTANT[round] - schedule_word;

    state->word[0] = was_a;
    state->word[1] = was_b;
    state->word[2] = was_c;
    state->word[3] = was_d;
    state->word[4] = was_e;
    state->word[5] = was_f;
    state->word[6] = was_g;
    state->word[7] = was_h;
}

/**
 * @brief Expands sixteen message words to the sixty-four the rounds consume.
 *
 * @param[in]  block    Sixteen words [BORROWS].
 * @param[out] schedule Sixty-four words [BORROWS].
 */
void expand_schedule(const uint32_t *block, uint32_t *schedule)
{
    for (unsigned slot = 0u; slot < 16u; slot += 1u)
    {
        schedule[slot] = block[slot];
    }
    for (unsigned slot = 16u; slot < 64u; slot += 1u)
    {
        const uint32_t back_fifteen = schedule[slot - 15u];
        const uint32_t back_two = schedule[slot - 2u];
        const uint32_t spread_low = rotate_right(back_fifteen, 7u) ^
                                    rotate_right(back_fifteen, 18u) ^ (back_fifteen >> 3u);
        const uint32_t spread_high =
            rotate_right(back_two, 17u) ^ rotate_right(back_two, 19u) ^ (back_two >> 10u);
        schedule[slot] = spread_high + schedule[slot - 7u] + spread_low + schedule[slot - 16u];
    }
}

/**
 * @brief Proves the round loses nothing, and that this file's forward round is the real one.
 */
void demonstrate_bijection()
{
    std::printf("\n================================================================\n");
    std::printf("  1. The round is a bijection. Nothing is lost.\n");
    std::printf("================================================================\n");

    std::mt19937 generator(20260908u);
    bool round_trip_holds = true;
    bool matches_core = true;

    for (unsigned trial = 0u; trial < 4096u; trial += 1u)
    {
        uint32_t block[16];
        uint32_t schedule[64];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            block[slot] = generator();
        }
        expand_schedule(block, schedule);

        Working start;
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            start.word[slot] = generator();
        }

        // Forward through all 64, then backward through all 64, and compare with where it began.
        Working walk = start;
        for (unsigned round = 0u; round < 64u; round += 1u)
        {
            round_forward(&walk, round, schedule[round]);
        }
        for (int round = 63; round >= 0; round -= 1)
        {
            round_backward(&walk, (unsigned)round, schedule[round]);
        }
        if (std::memcmp(walk.word, start.word, sizeof(start.word)) != 0)
        {
            round_trip_holds = false;
        }

        // And confirm this file's forward round is the kernel's, not a lookalike.
        Sha256State from_core;
        sha256_state_init(&from_core);
        Working from_here;
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            from_here.word[slot] = from_core.word[slot];
        }
        sha256_block_compress(&from_core, block);
        for (unsigned round = 0u; round < 64u; round += 1u)
        {
            round_forward(&from_here, round, schedule[round]);
        }
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            uint32_t initial;
            Sha256State fresh;
            sha256_state_init(&fresh);
            initial = fresh.word[slot];
            if ((uint32_t)(from_here.word[slot] + initial) != from_core.word[slot])
            {
                matches_core = false;
            }
        }
    }

    check("64 rounds forward then 64 backward returns the exact starting state", round_trip_holds);
    check("this file's forward round is the kernel's round", matches_core);

    std::printf("\n  So the mechanism is reversible end to end. The apparent randomness of the\n");
    std::printf("  output is a property of its statistics, not of the process. Every bit that\n");
    std::printf("  went in is still in there, exactly, and can be walked back out given the\n");
    std::printf("  message words.\n");
}

/**
 * @brief Maps how many rounds the ceiling takes to build, using the round-limited kernel.
 */
void map_ceiling_construction()
{
    std::printf("\n================================================================\n");
    std::printf("  2. Where the artificial ceiling gets built\n");
    std::printf("================================================================\n");
    std::printf("\n  The ceiling is constructed, so it is constructed over some number of rounds.\n");
    std::printf("  Flip one input bit, run r rounds, and count how much of the state moved. A\n");
    std::printf("  fully built ceiling sits at 50%% and holds.\n");
    std::printf("\n  %8s %14s %28s\n", "rounds", "state moved", "ceiling");
    std::printf("  %8s %14s %28s\n", "--------", "--------------",
                "----------------------------");

    std::mt19937 generator(20260908u);
    const unsigned trials = 4096u;

    for (unsigned rounds : {1u, 2u, 3u, 4u, 5u, 6u, 7u, 8u, 9u, 10u, 12u, 16u, 32u, 64u})
    {
        uint64_t moved = 0u;

        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            uint32_t block[16];
            for (unsigned slot = 0u; slot < 16u; slot += 1u)
            {
                block[slot] = generator();
            }

            Sha256State plain;
            Sha256State flipped;
            sha256_state_init(&plain);
            sha256_state_init(&flipped);

            uint32_t flipped_block[16];
            std::memcpy(flipped_block, block, sizeof(block));
            flipped_block[3] ^= (1u << (generator() % 32u));

            sha256_block_compress_partial(&plain, block, rounds);
            sha256_block_compress_partial(&flipped, flipped_block, rounds);

            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                moved += (uint64_t)__builtin_popcount(plain.word[slot] ^ flipped.word[slot]);
            }
        }

        const double fraction = (double)moved / ((double)trials * 256.0);
        const char *state = (fraction < 0.05)   ? "not started"
                            : (fraction < 0.45) ? "under construction"
                                                : "built";
        std::printf("  %8u %13.2f%% %28s\n", rounds, fraction * 100.0, state);
    }

    std::printf("\n  The ceiling is finished by round 10. A header hash runs 128 rounds, so it\n");
    std::printf("  spends 118 of them holding a ceiling that was already complete. That margin\n");
    std::printf("  is the design, and it is why reduced-round results do not extend.\n");
}

/**
 * @brief Maps what is trackable in the actual mining problem, forward and backward.
 */
void map_trackable_quantities()
{
    std::printf("\n================================================================\n");
    std::printf("  3. What can actually be tracked in the mining problem\n");
    std::printf("================================================================\n");

    std::printf("\n  The unknown is one 32-bit word: the nonce at schedule position 3. Everything\n");
    std::printf("  else in the header is given by the job. So the map is:\n");

    std::printf("\n  %-42s %s\n", "quantity", "status");
    std::printf("  %-42s %s\n", "------------------------------------------",
                "----------------------------------");
    std::printf("  %-42s %s\n", "midstate H0 (header bytes 0-63)", "known, fixed per job");
    std::printf("  %-42s %s\n", "W[0] merkle tail, W[1] ntime, W[2] nbits", "known");
    std::printf("  %-42s %s\n", "W[3] nonce", "THE UNKNOWN, 32 bits");
    std::printf("  %-42s %s\n", "W[4..15] padding and length", "known, constant");
    std::printf("  %-42s %s\n", "W[16..63]", "generated from W[0..15], so unknown");
    std::printf("  %-42s %s\n", "rounds 0,1,2 of hash one", "computable without the nonce");
    std::printf("  %-42s %s\n", "round 3 onward", "needs W[3]");
    std::printf("  %-42s %s\n", "hash two's message", "is hash one's output, so needs it all");

    std::printf("\n  Forward frontier : 3 rounds of 128 computable before meeting the unknown.\n");
    std::printf("  Backward frontier: 0 rounds. Inverting round t needs W[t], and every W past\n");
    std::printf("                     15 is generated from the word being solved for.\n");

    std::printf("\n  That circularity is the whole obstruction, and it is worth stating exactly.\n");
    std::printf("  The bijection in section 1 is real: given the message, the state walks back\n");
    std::printf("  perfectly. The mining problem does not give the message. It asks for the\n");
    std::printf("  message that produces a wanted output, and the inverse needs that same\n");
    std::printf("  message to run. Invertible given the input is not the same as solvable for\n");
    std::printf("  the input.\n");

    std::printf("\n  Stated as algebra: 32 unknown bits, and a demand that 76 or so output bits\n");
    std::printf("  come out zero, through a system whose algebraic degree over GF(2) is driven\n");
    std::printf("  to saturation by round 10. Meet-in-the-middle and SAT attacks work this\n");
    std::printf("  exact surface. Published results reach roughly 52 of 64 rounds for preimages\n");
    std::printf("  at complexity near 2^255, and about 20 to 24 rounds for SAT. Bitcoin runs\n");
    std::printf("  128 rounds.\n");

    std::printf("\n  So the honest frontier: the seam is rounds 0 through 9, measured, and the\n");
    std::printf("  construction is complete for the remaining 118. Every projection tried in\n");
    std::printf("  this tree dies inside that seam.\n");
}

/**
 * @brief Measures how fast information travels, and how widely, per round.
 *
 * @note Propagation speed is a dimension in its own right, and it is a distribution instead of a
 *       number. A perturbation does not arrive everywhere at once: it has a front, and behind the
 *       front the positions it has reached carry a spread of probabilities. Both are measured here.
 * @note The quantity per position is P(this output bit differs), which is zero where the front has
 *       not arrived, near one half where it has fully arrived, and strictly between while it is
 *       arriving. Counting positions by which band they fall in gives the shape of the wave.
 */
void measure_propagation_speed()
{
    std::printf("\n================================================================\n");
    std::printf("  4. Speed of information propagation, as a distribution\n");
    std::printf("================================================================\n");
    std::printf("\n  Flip one input bit and watch the front move. For each of 256 state\n");
    std::printf("  positions, P(this bit differs) after r rounds. Reached means the position\n");
    std::printf("  has moved at all; saturated means it has reached a fair coin.\n");
    std::printf("\n  %6s %10s %12s %14s %14s\n", "rounds", "reached", "saturated", "mean P",
                "front width");
    std::printf("  %6s %10s %12s %14s %14s\n", "------", "----------", "------------",
                "--------------", "--------------");

    std::mt19937 generator(20260908u);
    const unsigned trials = 8192u;
    unsigned previous_reached = 0u;

    for (unsigned rounds = 1u; rounds <= 16u; rounds += 1u)
    {
        std::vector<uint64_t> differing(256u, 0u);

        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            uint32_t block[16];
            for (unsigned slot = 0u; slot < 16u; slot += 1u)
            {
                block[slot] = generator();
            }
            uint32_t flipped_block[16];
            std::memcpy(flipped_block, block, sizeof(block));
            flipped_block[3] ^= (1u << (generator() % 32u));

            Sha256State plain;
            Sha256State flipped;
            sha256_state_init(&plain);
            sha256_state_init(&flipped);
            sha256_block_compress_partial(&plain, block, rounds);
            sha256_block_compress_partial(&flipped, flipped_block, rounds);

            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                const uint32_t difference = plain.word[slot] ^ flipped.word[slot];
                for (unsigned bit = 0u; bit < 32u; bit += 1u)
                {
                    differing[(slot * 32u) + bit] += (difference >> bit) & 1u;
                }
            }
        }

        unsigned reached = 0u;
        unsigned saturated = 0u;
        double probability_total = 0.0;

        for (unsigned position = 0u; position < 256u; position += 1u)
        {
            const double probability = (double)differing[position] / (double)trials;

            probability_total += probability;
            if (probability > 0.0)
            {
                reached += 1u;
            }
            // Within four standard errors of a fair coin counts as arrived.
            if (std::fabs(probability - 0.5) < (4.0 * 0.5 / std::sqrt((double)trials)))
            {
                saturated += 1u;
            }
        }

        // The front is the band that has been reached but has not yet settled: the wave itself.
        const unsigned front = (reached > saturated) ? (reached - saturated) : 0u;
        std::printf("  %6u %10u %12u %14.6f %14u\n", rounds, reached, saturated,
                    probability_total / 256.0, front);
        previous_reached = reached;
    }
    (void)previous_reached;

    std::printf("\n  There are two speeds here and they are not the same.\n");
    std::printf("\n  Reach is linear and exactly 64 bits per round: 64, 128, 192, 256 across\n");
    std::printf("  rounds 4 through 7. That is two words a round, and it is structural rather\n");
    std::printf("  than statistical. The eight working variables are a shift register in two\n");
    std::printf("  chains, a to b to c to d and e to f to g to h, so a disturbance walks one\n");
    std::printf("  word along each chain per round. Two words is sixty four bits. There is a\n");
    std::printf("  real finite propagation speed and this is its value.\n");
    std::printf("\n  Saturation is the second speed and it lags: 0, 32, 96, 159, 222, 256 over\n");
    std::printf("  rounds 5 to 10. The gap between the two is the wave, and its width peaks near\n");
    std::printf("  160 positions around rounds 6 and 7 before collapsing.\n");
    std::printf("\n  So there is a light cone. It is just small compared to the state. Reach\n");
    std::printf("  covers all 256 bits four rounds after the input enters, because 256 divided\n");
    std::printf("  by 64 is 4, and a header hash runs 128 rounds. A cone is a constraint worth\n");
    std::printf("  solving against only while something sits outside it, and nothing does after\n");
    std::printf("  round 7 of 128.\n");
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  Invertibility, the artificial ceiling, and what is trackable\n");
    std::printf("================================================================\n");

    const auto started = std::chrono::steady_clock::now();

    demonstrate_bijection();
    map_ceiling_construction();
    map_trackable_quantities();
    measure_propagation_speed();

    const auto finished = std::chrono::steady_clock::now();
    std::printf("\n================================================================\n");
    std::printf("  %d checks run, %d failed\n", g_checks_run, g_checks_failed);
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return (g_checks_failed == 0) ? 0 : 1;
}
