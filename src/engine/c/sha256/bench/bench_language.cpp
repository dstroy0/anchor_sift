/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_language.cpp
 * @brief The two linear languages SHA-256 alternates between, measured against each other.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note SHA-256 is built on two module structures that are not bases for each other. Exclusive-or
 *       and rotation are linear over GF(2)^32. Addition is linear over the integers modulo 2^32.
 *       The round alternates between them on purpose, and that alternation is the whole trick.
 * @note This workbook has searched each language separately and exhaustively and found nothing in
 *       either. H35 walked all 4,294,967,295 Walsh masks, which is every GF(2)-linear direction.
 *       H37 swept the Fourier spectrum over 32 units and 12 scales, which is the integer-linear
 *       view. Two complete dictionaries, for two languages the function is not written in.
 * @note What has never been measured is the two against each other. Each language has a native
 *       notion of difference - exclusive-or for one, subtraction modulo 2^32 for the other - and
 *       the rate at which the function destroys each is the rate at which that language loses grip
 *       on it. The ratio of those two rates is the translation cost, in rounds.
 * @note The only place the two languages touch is the carry, since an addition is exactly an
 *       exclusive-or plus a carry. This workbook already has the carry law exactly, as
 *       `p_{i+1} = p_i / 2 + 1/4`, so the per-addition translation is known in closed form. What is
 *       not known is how it composes across rounds, which is what this measures.
 * @note Two controls, one for each language, and they must fail in opposite directions. A function
 *       built only from exclusive-or and rotation carries an exclusive-or difference through
 *       perfectly and scatters an additive one. A function built only from addition does the
 *       reverse. An instrument that reported the same thing for both would be measuring neither.
 */

#include "bench_load_limit.h"
#include "bench_seed.h"
#include "sha256_core.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <vector>

namespace
{

/** @brief Bins in the window the difference is read through. */
const unsigned BINS = 65536u;

/** @brief The deepest round this walks to. */
const unsigned DEEPEST = 10u;

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

/** @brief Which function is being measured. */
enum Machine
{
    MACHINE_SHA,      /**< The real round. */
    MACHINE_XOR_ONLY, /**< Exclusive-or and rotation only, linear over GF(2). */
    MACHINE_ADD_ONLY  /**< Addition and rotation only, linear over the integers. */
};

/** @brief Which language's notion of difference is being tracked. */
enum Language
{
    LANGUAGE_XOR, /**< Difference is exclusive-or, native to GF(2). */
    LANGUAGE_ADD  /**< Difference is subtraction modulo 2^32, native to the integers. */
};

/** @brief Rotates a word right. */
uint32_t turn_right(uint32_t value, unsigned distance)
{
    distance &= 31u;
    return (distance == 0u) ? value : ((value >> distance) | (value << (32u - distance)));
}

/** @brief The round's high mixing function. */
uint32_t mix_high(uint32_t value)
{
    return turn_right(value, 6u) ^ turn_right(value, 11u) ^ turn_right(value, 25u);
}

/** @brief The round's low mixing function. */
uint32_t mix_low(uint32_t value)
{
    return turn_right(value, 2u) ^ turn_right(value, 13u) ^ turn_right(value, 22u);
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
 * @brief Runs one round of the chosen machine.
 *
 * @param[in,out] state         Eight working variables [BORROWS].
 * @param[in]     machine       Which function.
 * @param[in]     round         Which round, selecting the constant.
 * @param[in]     schedule_word The message word.
 * @note The two controls keep the real round's shape - same rotations, same shift pattern, same
 *       constants - and change only which operation joins the terms. That is what makes them
 *       controls on the language instead of on the shape, since a control that also changed the
 *       structure would not say which of the two differences it was answering.
 */
void step(uint32_t *state, Machine machine, unsigned round, uint32_t schedule_word)
{
    uint32_t carry_one = 0u;
    uint32_t carry_two = 0u;

    if (machine == MACHINE_XOR_ONLY)
    {
        // Everything joined by exclusive-or, so the whole map is GF(2)-linear.
        carry_one = state[7] ^ mix_high(state[4]) ^ state[5] ^ ROUND_CONSTANT[round] ^
                    schedule_word;
        carry_two = mix_low(state[0]) ^ state[1];
        state[7] = state[6];
        state[6] = state[5];
        state[5] = state[4];
        state[4] = state[3] ^ carry_one;
        state[3] = state[2];
        state[2] = state[1];
        state[1] = state[0];
        state[0] = carry_one ^ carry_two;
        return;
    }

    if (machine == MACHINE_ADD_ONLY)
    {
        // Everything joined by addition, and the rotations replaced by nothing, so the map is
        // linear over the integers modulo 2^32. A rotation is not integer-linear, so keeping it
        // would make this control neither language.
        carry_one = state[7] + state[4] + state[5] + ROUND_CONSTANT[round] + schedule_word;
        carry_two = state[0] + state[1];
        state[7] = state[6];
        state[6] = state[5];
        state[5] = state[4];
        state[4] = state[3] + carry_one;
        state[3] = state[2];
        state[2] = state[1];
        state[1] = state[0];
        state[0] = carry_one + carry_two;
        return;
    }

    carry_one = state[7] + mix_high(state[4]) + choose(state[4], state[5], state[6]) +
                ROUND_CONSTANT[round] + schedule_word;
    carry_two = mix_low(state[0]) + majority(state[0], state[1], state[2]);
    state[7] = state[6];
    state[6] = state[5];
    state[5] = state[4];
    state[4] = state[3] + carry_one;
    state[3] = state[2];
    state[2] = state[1];
    state[1] = state[0];
    state[0] = carry_one + carry_two;
}

/** @brief Names a machine for printing. */
const char *machine_name(Machine machine)
{
    return (machine == MACHINE_SHA)
               ? "SHA-256 round"
               : ((machine == MACHINE_XOR_ONLY) ? "xor only, GF(2)-linear"
                                                : "add only, integer-linear");
}

/**
 * @brief How many bits of grip a language has on a machine after a given number of rounds.
 *
 * @param[in]     machine  Which function.
 * @param[in]     language Which notion of difference to track.
 * @param[in]     rounds   How many rounds to run.
 * @param[in]     draws    How many pairs to sample.
 * @param[in,out] generator Random source [BORROWS].
 * @return                 Bits by which the output difference distribution falls short of flat.
 * @note The input difference is fixed across every pair, which is what makes this a measurement of
 *       the language instead of of the difference. A language keeps grip when one input difference
 *       produces a concentrated output difference; it has lost grip when the output difference is
 *       spread over the whole window whatever the input was.
 * @note Collision entropy is the right reading here instead of a peak, because a peak is one bin
 *       and this is a question about the whole distribution. The unbiased estimator is used, since
 *       the naive sum of squared frequencies is biased upward at this sparsity and would report
 *       grip that is not there.
 */
double grip_bits(Machine machine, Language language, unsigned rounds, unsigned draws,
                 std::mt19937 *generator)
{
    std::vector<uint32_t> counts(BINS, 0u);

    // One fixed input difference for the whole run, placed on the word a round reads first.
    const uint32_t difference = (*generator)() | 1u;

    for (unsigned draw = 0u; draw < draws; draw += 1u)
    {
        uint32_t left[8];
        uint32_t right[8];
        uint32_t words[DEEPEST];

        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            left[slot] = (*generator)();
            right[slot] = left[slot];
        }
        for (unsigned slot = 0u; slot < DEEPEST; slot += 1u)
        {
            words[slot] = (*generator)();
        }

        if (language == LANGUAGE_XOR)
        {
            right[7] = left[7] ^ difference;
        }
        else
        {
            right[7] = left[7] + difference;
        }

        for (unsigned at = 0u; at < rounds; at += 1u)
        {
            step(left, machine, at, words[at]);
            step(right, machine, at, words[at]);
        }

        const uint32_t seen = (language == LANGUAGE_XOR) ? (right[0] ^ left[0])
                                                         : (right[0] - left[0]);
        counts[seen & (BINS - 1u)] += 1u;
    }

    long double collisions = 0.0L;
    for (unsigned bin = 0u; bin < BINS; bin += 1u)
    {
        const long double here = (long double)counts[bin];
        collisions += here * (here - 1.0L);
    }
    const long double possible = (long double)draws * ((long double)draws - 1.0L);
    const long double rate = collisions / possible;

    // Sixteen bits is flat. Anything above zero is grip the language still has.
    const double flat = 16.0;
    return (rate > 0.0L) ? (flat + std::log2((double)rate)) : 0.0;
}

} // namespace

int main(int argc, char **argv)
{
    bench_lower_priority();

    const unsigned draws = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 300000u;

    std::printf("================================================================\n");
    std::printf("  The two languages, measured against each other\n");
    std::printf("================================================================\n");
    std::printf("\n  SHA-256 is built on two module structures that are not bases for each other.\n");
    std::printf("  Exclusive-or and rotation are linear over GF(2)^32. Addition is linear over the\n");
    std::printf("  integers modulo 2^32. The round alternates between them, and that is the trick.\n");
    std::printf("\n  This workbook has searched each language separately and exhaustively. H35\n");
    std::printf("  walked all 4,294,967,295 Walsh masks, every GF(2)-linear direction there is.\n");
    std::printf("  H37 swept the Fourier view over 32 units and 12 scales. Two complete\n");
    std::printf("  dictionaries, for two languages the function is not written in.\n");
    std::printf("\n  Each language has a native difference: exclusive-or for one, subtraction for\n");
    std::printf("  the other. How fast the function destroys each is how fast that language loses\n");
    std::printf("  grip, and the gap between the two rates is the translation cost in rounds.\n");
    std::printf("\n  Grip is bits by which the output difference falls short of flat over a\n");
    std::printf("  sixteen-bit window. Zero is no grip at all. Pairs per cell: %u.\n", draws);

    const Machine machines[3] = {MACHINE_SHA, MACHINE_XOR_ONLY, MACHINE_ADD_ONLY};

    for (unsigned which = 0u; which < 3u; which += 1u)
    {
        std::printf("\n  %s\n", machine_name(machines[which]));
        std::printf("\n  %8s %16s %16s %14s\n", "rounds", "xor grip", "add grip", "which leads");
        std::printf("  %8s %16s %16s %14s\n", "--------", "----------------", "----------------",
                    "--------------");

        for (unsigned rounds = 1u; rounds <= DEEPEST; rounds += 1u)
        {
            std::mt19937 xor_generator(bench_seed(20260908u) + rounds);
            std::mt19937 add_generator(bench_seed(20260908u) + rounds);

            const double by_xor =
                grip_bits(machines[which], LANGUAGE_XOR, rounds, draws, &xor_generator);
            const double by_add =
                grip_bits(machines[which], LANGUAGE_ADD, rounds, draws, &add_generator);

            const char *leader = "neither";
            if ((by_xor > 0.05) || (by_add > 0.05))
            {
                leader = (by_xor > (by_add + 0.05))
                             ? "xor"
                             : ((by_add > (by_xor + 0.05)) ? "add" : "level");
            }

            std::printf("  %8u %16.4f %16.4f %14s\n", rounds, by_xor, by_add, leader);
        }
    }

    std::printf("\n================================================================\n");
    std::printf("  Reading it\n");
    std::printf("================================================================\n");
    std::printf("\n  The two controls have to fail in opposite directions, and that is the whole\n");
    std::printf("  reason they are here. A machine built only from exclusive-or carries an\n");
    std::printf("  exclusive-or difference through every round untouched, so its xor column must\n");
    std::printf("  stay at sixteen bits forever while its add column collapses. A machine built\n");
    std::printf("  only from addition must do exactly the reverse. If both columns behave the\n");
    std::printf("  same way on both controls, this instrument is measuring neither language and\n");
    std::printf("  the SHA rows mean nothing.\n");
    std::printf("\n  On the real round, the gap between the two columns at a given depth is what\n");
    std::printf("  the alternation costs. Where one language holds on longer than the other, that\n");
    std::printf("  is the language the function is closer to being written in, and the round it\n");
    std::printf("  stops holding is where that closeness runs out.\n");
    return 0;
}
