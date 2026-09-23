/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_basis.cpp
 * @brief The two module structures SHA-256 alternates between, and how long each holds a signal.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The premise here is that addition modulo two to the thirty-second is not the nonlinear one.
 *       It is linear, over a different module. The set {0,1}^32 carries two structures at once:
 *       GF(2)^32 under exclusive or, where rotation is a permutation matrix and addition is not
 *       linear, and Z/2^32 under integer addition, where addition is linear and rotation is not.
 *       Every SHA-256 operation is linear in exactly one of them.
 * @note The carry is the lift. z_i = x_i xor y_i xor c_i keeps the exclusive or in basis, and
 *       c_{i+1} = MAJ(x_i, y_i, c_i) is the part that leaves it, recursing upward through every
 *       lower bit. That recursion is one gate repeated thirty-two times inside a round that repeats
 *       sixty-four times: a pattern inside a pattern.
 * @note What is measured here is whether either basis holds a signal longer than the other, and
 *       what the carry bias actually is instead of what it is assumed to be.
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

int g_checks_run = 0;
int g_checks_failed = 0;

/** @brief Bits in the machine word both structures sit on. */
const unsigned WORD_BITS = 32u;

/** @brief Words in a chaining value. */
const unsigned STATE_WORDS = 8u;

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

/**
 * @brief Confirms empirically which operation is linear in which module.
 *
 * @note The table this produces is the claim the rest of the file rests on, so it is measured
 *       instead of stated. A linear map satisfies f(x op y) == f(x) op f(y) op f(0) for the op its
 *       module carries.
 */
void measure_basis_linearity()
{
    std::printf("\n================================================================\n");
    std::printf("  1. Which operation is linear in which module?\n");
    std::printf("================================================================\n");
    std::printf("\n  For each operation, the fraction of random pairs satisfying linearity in\n");
    std::printf("  each of the two structures. 100%% means linear, near 0%% means not.\n");

    std::mt19937 generator(20260908u);
    const unsigned trials = 100000u;

    unsigned rotate_xor_linear = 0u;
    unsigned rotate_add_linear = 0u;
    unsigned xor_xor_linear = 0u;
    unsigned xor_add_linear = 0u;
    unsigned add_xor_linear = 0u;
    unsigned add_add_linear = 0u;

    const uint32_t constant = 0x428a2f98u;

    for (unsigned trial = 0u; trial < trials; trial += 1u)
    {
        const uint32_t left = generator();
        const uint32_t right = generator();

        // Rotation by seven, the schedule's own.
        if (rotate_right(left ^ right, 7u) == (rotate_right(left, 7u) ^ rotate_right(right, 7u)))
        {
            rotate_xor_linear += 1u;
        }
        if (rotate_right(left + right, 7u) == (uint32_t)(rotate_right(left, 7u) +
                                                         rotate_right(right, 7u)))
        {
            rotate_add_linear += 1u;
        }

        // Exclusive or with a round constant.
        if (((left ^ right) ^ constant) == ((left ^ constant) ^ (right ^ constant) ^ constant))
        {
            xor_xor_linear += 1u;
        }
        if (((left + right) ^ constant) ==
            (uint32_t)(((left ^ constant) + (right ^ constant)) - constant))
        {
            xor_add_linear += 1u;
        }

        // Addition of a round constant.
        if (((left ^ right) + constant) == (uint32_t)((left + constant) ^ (right + constant) ^
                                                      constant))
        {
            add_xor_linear += 1u;
        }
        if ((uint32_t)((left + right) + constant) ==
            (uint32_t)((left + constant) + (right + constant) - constant))
        {
            add_add_linear += 1u;
        }
    }

    const double scale = 100.0 / (double)trials;
    std::printf("\n  %-24s %22s %20s\n", "operation", "GF(2)^32 (xor basis)", "Z/2^32 (add basis)");
    std::printf("  %-24s %22s %20s\n", "------------------------", "----------------------",
                "--------------------");
    std::printf("  %-24s %21.2f%% %19.2f%%\n", "rotate right by 7", (double)rotate_xor_linear * scale,
                (double)rotate_add_linear * scale);
    std::printf("  %-24s %21.2f%% %19.2f%%\n", "xor a constant", (double)xor_xor_linear * scale,
                (double)xor_add_linear * scale);
    std::printf("  %-24s %21.2f%% %19.2f%%\n", "add a constant", (double)add_xor_linear * scale,
                (double)add_add_linear * scale);

    check("rotation is linear over GF(2)^32", rotate_xor_linear == trials);
    check("rotation is not linear over Z/2^32", rotate_add_linear < (trials / 2u));
    check("adding a constant is linear over Z/2^32", add_add_linear == trials);
    check("adding a constant is not linear over GF(2)^32", add_xor_linear < (trials / 2u));

    std::printf("\n  So the set carries two structures and each operation is linear in one of\n");
    std::printf("  them. A projection that diagonalises one necessarily fails on the other.\n");
}

/**
 * @brief Measures the carry bias, which is the lift made concrete.
 *
 * @note This is the one place in this document where structure is found instead of bounded. The
 *       carry into position i is not a fair coin at low i, and the exact figures are below.
 */
void measure_carry_structure()
{
    std::printf("\n================================================================\n");
    std::printf("  2. The lift. What does the carry actually do?\n");
    std::printf("================================================================\n");
    std::printf("\n  z_i = x_i xor y_i xor c_i, with c_0 = 0 and c_{i+1} = MAJ(x_i, y_i, c_i).\n");
    std::printf("  The exclusive or stays in the GF(2) basis. The carry is what leaves it.\n");
    std::printf("\n  P(carry into position i) for uniform random x and y:\n");
    std::printf("\n  %10s %14s %14s %12s\n", "position", "measured", "exact", "bias from 1/2");
    std::printf("  %10s %14s %14s %12s\n", "----------", "--------------", "--------------",
                "------------");

    std::mt19937 generator(20260908u);
    const unsigned trials = 4000000u;
    std::vector<uint64_t> carry_set(WORD_BITS + 1u, 0u);

    for (unsigned trial = 0u; trial < trials; trial += 1u)
    {
        const uint32_t left = generator();
        const uint32_t right = generator();
        unsigned carry = 0u;

        for (unsigned position = 0u; position < WORD_BITS; position += 1u)
        {
            const unsigned left_bit = (left >> position) & 1u;
            const unsigned right_bit = (right >> position) & 1u;

            carry_set[position] += carry;
            carry = ((left_bit & right_bit) | (left_bit & carry) | (right_bit & carry));
        }
        carry_set[WORD_BITS] += carry;
    }

    // The exact recursion for uniform independent bits: p_{i+1} = p_i/2 + 1/4, fixed point 1/2.
    double exact = 0.0;
    bool all_close = true;

    for (unsigned position = 0u; position <= 8u; position += 1u)
    {
        const double measured = (double)carry_set[position] / (double)trials;
        const double deviation = measured - 0.5;

        std::printf("  %10u %14.6f %14.6f %+12.6f\n", position, measured, exact, deviation);
        if (std::fabs(measured - exact) > 0.002)
        {
            all_close = false;
        }
        exact = (exact / 2.0) + 0.25;
    }
    std::printf("  %10s %14s %14s %12s\n", "...", "", "", "");
    std::printf("  %10u %14.6f %14.6f %+12.6f\n", 31u,
                (double)carry_set[31] / (double)trials, 0.5,
                ((double)carry_set[31] / (double)trials) - 0.5);

    check("carry probability follows p_{i+1} = p_i/2 + 1/4", all_close);

    std::printf("\n  The carry into position 1 is a quarter, not a half, and the bias halves\n");
    std::printf("  each position upward. This is real structure and it is exactly the surface\n");
    std::printf("  that differential cryptanalysis of ARX constructions works on.\n");
    std::printf("\n  It is also local. By position 8 the deviation is under 0.2%%, and one\n");
    std::printf("  addition is followed by a rotation that moves those low positions somewhere\n");
    std::printf("  the next addition treats as high ones.\n");
}

/**
 * @brief Builds a header tail block around one nonce.
 *
 * @param[out] block Sixteen words [BORROWS].
 * @param[in]  nonce The nonce to carry.
 */
void fill_tail_block(uint32_t *block, uint32_t nonce)
{
    block[0] = 0xc7f5d74du;
    block[1] = 0xf2b9441au;
    block[2] = 0x42a14695u;
    block[3] = nonce;
    block[4] = 0x80000000u;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        block[slot] = 0u;
    }
    block[15] = 0x00000280u;
}

/**
 * @brief Races the two bases: does either hold a difference longer than the other?
 *
 * @note This is the decisive comparison. A difference introduced in the basis an operation is
 *       linear in should, if anything survives, survive further in that basis. Both are measured
 *       against the same round counts on the same function.
 */
void measure_difference_survival()
{
    std::printf("\n================================================================\n");
    std::printf("  3. Racing the bases. Which difference survives more rounds?\n");
    std::printf("================================================================\n");
    std::printf("\n  Introduce a difference in one basis, run r rounds, read the output\n");
    std::printf("  difference back in the same basis, and measure the largest per-bit bias\n");
    std::printf("  across all 256 state bits. A function with nothing left to leak sits at 0.\n");
    std::printf("\n  %8s %22s %22s\n", "rounds", "xor difference", "modular difference");
    std::printf("  %8s %22s %22s\n", "--------", "----------------------",
                "----------------------");

    std::mt19937 generator(20260908u);
    const unsigned trials = 8192u;
    const uint32_t difference = 1u;

    unsigned xor_last_alive = 0u;
    unsigned add_last_alive = 0u;

    for (unsigned rounds : {1u, 2u, 3u, 4u, 5u, 6u, 7u, 8u, 9u, 10u, 12u, 16u, 24u, 64u})
    {
        std::vector<uint64_t> xor_ones(256u, 0u);
        std::vector<uint64_t> add_ones(256u, 0u);

        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            uint32_t block[SHA256_BLOCK_WORDS];
            fill_tail_block(block, generator());

            Sha256State base_state;
            for (unsigned slot = 0u; slot < STATE_WORDS; slot += 1u)
            {
                base_state.word[slot] = generator();
            }

            Sha256State plain = base_state;
            Sha256State xor_variant = base_state;
            Sha256State add_variant = base_state;
            xor_variant.word[0] = base_state.word[0] ^ difference;
            add_variant.word[0] = base_state.word[0] + difference;

            sha256_block_compress_partial(&plain, block, rounds);
            sha256_block_compress_partial(&xor_variant, block, rounds);
            sha256_block_compress_partial(&add_variant, block, rounds);

            for (unsigned slot = 0u; slot < STATE_WORDS; slot += 1u)
            {
                const uint32_t xor_delta = plain.word[slot] ^ xor_variant.word[slot];
                const uint32_t add_delta = add_variant.word[slot] - plain.word[slot];

                for (unsigned bit = 0u; bit < WORD_BITS; bit += 1u)
                {
                    xor_ones[(slot * WORD_BITS) + bit] += (xor_delta >> bit) & 1u;
                    add_ones[(slot * WORD_BITS) + bit] += (add_delta >> bit) & 1u;
                }
            }
        }

        const double standard_error = 0.5 / std::sqrt((double)trials);
        double xor_worst = 0.0;
        double add_worst = 0.0;

        for (unsigned position = 0u; position < 256u; position += 1u)
        {
            xor_worst = std::max(xor_worst,
                                 std::fabs(((double)xor_ones[position] / (double)trials) - 0.5));
            add_worst = std::max(add_worst,
                                 std::fabs(((double)add_ones[position] / (double)trials) - 0.5));
        }

        const double xor_score = xor_worst / standard_error;
        const double add_score = add_worst / standard_error;
        if (xor_score > 5.0)
        {
            xor_last_alive = rounds;
        }
        if (add_score > 5.0)
        {
            add_last_alive = rounds;
        }

        std::printf("  %8u %14.4f %6.1fs %14.4f %6.1fs\n", rounds, xor_worst, xor_score, add_worst,
                    add_score);
    }

    std::printf("\n  Last round with a bias above five sigma:\n");
    std::printf("    xor basis     : round %u\n", xor_last_alive);
    std::printf("    modular basis : round %u\n", add_last_alive);
    std::printf("\n  Neither basis carries a difference far. Choosing the structure an operation\n");
    std::printf("  is linear in does not help, because the next operation is linear in the other\n");
    std::printf("  one and the round applies both.\n");
}

/**
 * @brief Transforms a boundary row by Walsh-Hadamard, the exclusive-or basis dual of the Fourier one.
 *
 * @param[in,out] row Thirty-two values, transformed in place [BORROWS].
 * @note The workbook flagged this as the obvious next projection, because the Fourier transform is
 *       diagonal for rotation and wrong for exclusive or. This is the other side.
 */
void walsh_hadamard(double *row)
{
    for (unsigned span = 1u; span < WORD_BITS; span *= 2u)
    {
        for (unsigned start = 0u; start < WORD_BITS; start += (span * 2u))
        {
            for (unsigned offset = 0u; offset < span; offset += 1u)
            {
                const double left = row[start + offset];
                const double right = row[start + offset + span];

                row[start + offset] = left + right;
                row[start + offset + span] = left - right;
            }
        }
    }
}

/**
 * @brief Measures the Walsh-Hadamard flatness of the boundary, round by round.
 */
void measure_walsh_flatness()
{
    std::printf("\n================================================================\n");
    std::printf("  4. The other projection. Walsh-Hadamard instead of Fourier.\n");
    std::printf("================================================================\n");
    std::printf("\n  Sequency power across the 8 by 32 boundary. Flat is 1.0.\n");
    std::printf("\n  %8s %20s %14s\n", "rounds", "sequency flatness", "peak / mean");
    std::printf("  %8s %20s %14s\n", "--------", "--------------------", "--------------");

    std::mt19937 generator(20260908u);
    const unsigned trials = 4096u;

    for (unsigned rounds : {0u, 1u, 2u, 4u, 8u, 16u, 32u, 64u})
    {
        double power[WORD_BITS];
        for (unsigned frequency = 0u; frequency < WORD_BITS; frequency += 1u)
        {
            power[frequency] = 0.0;
        }

        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            uint32_t block[SHA256_BLOCK_WORDS];
            fill_tail_block(block, generator());

            Sha256State state;
            sha256_state_init(&state);
            sha256_block_compress_partial(&state, block, rounds);

            for (unsigned slot = 0u; slot < STATE_WORDS; slot += 1u)
            {
                double row[WORD_BITS];

                for (unsigned bit = 0u; bit < WORD_BITS; bit += 1u)
                {
                    row[bit] = (((state.word[slot] >> bit) & 1u) != 0u) ? 1.0 : -1.0;
                }
                walsh_hadamard(row);
                for (unsigned frequency = 0u; frequency < WORD_BITS; frequency += 1u)
                {
                    power[frequency] += row[frequency] * row[frequency];
                }
            }
        }

        double log_sum = 0.0;
        double linear_sum = 0.0;
        double peak = 0.0;
        for (unsigned frequency = 1u; frequency < WORD_BITS; frequency += 1u)
        {
            const double value = power[frequency];
            log_sum += std::log(std::max(value, 1e-300));
            linear_sum += value;
            peak = std::max(peak, value);
        }
        const double count = (double)(WORD_BITS - 1u);
        const double geometric = std::exp(log_sum / count);
        const double arithmetic = linear_sum / count;

        std::printf("  %8u %19.6f %14.4f\n", rounds,
                    (arithmetic > 0.0) ? (geometric / arithmetic) : 0.0,
                    (arithmetic > 0.0) ? (peak / arithmetic) : 0.0);
    }

    std::printf("\n  Same shape as the Fourier result in bench_transform. Neither projection\n");
    std::printf("  leaves a bin standing by the depth a real hash reaches.\n");
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  Two module structures on one set\n");
    std::printf("  What a mod does dimensionally, and how far the lift carries\n");
    std::printf("================================================================\n");

    const auto started = std::chrono::steady_clock::now();

    measure_basis_linearity();
    measure_carry_structure();
    measure_difference_survival();
    measure_walsh_flatness();

    const auto finished = std::chrono::steady_clock::now();
    std::printf("\n================================================================\n");
    std::printf("  %d checks run, %d failed\n", g_checks_run, g_checks_failed);
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return (g_checks_failed == 0) ? 0 : 1;
}
