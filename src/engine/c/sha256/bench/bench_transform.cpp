/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_transform.cpp
 * @brief The state on its two dimensional boundary, and how many rounds it remembers a rotation.
 * @author dstroy0 (Douglas Quigg (dstroy0)) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The premise being tested is exact and correct in isolation. Lay the chaining value out as
 *       eight words by thirty-two bits and transform along the bit axis. A cyclic rotation by r is
 *       multiplication by exp(-2 pi i k r / 32): the magnitude spectrum does not move and the phase
 *       carries r. That is the same identity phase correlation registers images with. So the
 *       representation does know when it was rotated.
 * @note What is measured here is how far that knowledge travels. SHA-256 alternates three
 *       operations that no one transform diagonalises at once. Rotation is diagonal in the discrete
 *       Fourier transform over Z32. Exclusive or is diagonal in the Walsh Hadamard transform over
 *       GF(2)^32 and not in the Fourier one. Addition modulo two to the thirty-second is diagonal in
 *       neither, because carries cross bit positions. Rounds interleave all three.
 * @note Every number below is a measurement on the real function at a stated round count, not an
 *       argument about it. Where the signal dies, the round it died at is reported.
 */

#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <complex>
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

/** @brief Bits along the boundary's fast axis, which is a machine word. */
const unsigned BOUNDARY_WIDTH = 32u;

/** @brief Words along the boundary's slow axis, which is the chaining value. */
const unsigned BOUNDARY_HEIGHT = 8u;

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
 * @brief Rotates a word right, matching the kernel's own rotation.
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
 * @brief Projects one word onto the boundary's fast axis as a bipolar sequence.
 *
 * @param[in]  value    Word to project.
 * @param[out] boundary Thirty-two values, plus or minus one [BORROWS].
 * @note Bipolar instead of zero and one, so a flat spectrum has no constant term drowning the rest.
 */
void project_word(uint32_t value, double *boundary)
{
    for (unsigned bit = 0u; bit < BOUNDARY_WIDTH; bit += 1u)
    {
        boundary[bit] = (((value >> bit) & 1u) != 0u) ? 1.0 : -1.0;
    }
}

/**
 * @brief Transforms a boundary row along the bit axis.
 *
 * @param[in]  boundary Thirty-two projected values [BORROWS].
 * @param[out] spectrum Thirty-two complex coefficients [BORROWS].
 * @note Naive and exact. Thirty-two points does not need a fast transform and an exact one cannot
 *       be accused of hiding a signal in its own approximation.
 */
void transform_row(const double *boundary, std::complex<double> *spectrum)
{
    for (unsigned frequency = 0u; frequency < BOUNDARY_WIDTH; frequency += 1u)
    {
        std::complex<double> total(0.0, 0.0);

        for (unsigned position = 0u; position < BOUNDARY_WIDTH; position += 1u)
        {
            const double angle = -2.0 * 3.14159265358979323846 * (double)frequency *
                                 (double)position / (double)BOUNDARY_WIDTH;
            total += boundary[position] * std::complex<double>(std::cos(angle), std::sin(angle));
        }
        spectrum[frequency] = total;
    }
}

/**
 * @brief Confirms the premise on an unmixed word: the magnitude holds still and the phase moves.
 *
 * @note This is the control. If rotation did not show up cleanly here, every later measurement
 *       would be measuring the instrument instead of the function.
 */
void check_rotation_identity()
{
    std::printf("\n================================================================\n");
    std::printf("  0. Control. Does the boundary see a rotation at all?\n");
    std::printf("================================================================\n");

    std::mt19937 generator(20260908u);
    double worst_magnitude_drift = 0.0;
    double worst_phase_error = 0.0;

    for (unsigned trial = 0u; trial < 256u; trial += 1u)
    {
        const uint32_t value = generator();
        const unsigned shift = 1u + (generator() % 31u);
        const uint32_t rotated = rotate_right(value, shift);

        double plain_boundary[BOUNDARY_WIDTH];
        double rotated_boundary[BOUNDARY_WIDTH];
        std::complex<double> plain_spectrum[BOUNDARY_WIDTH];
        std::complex<double> rotated_spectrum[BOUNDARY_WIDTH];

        project_word(value, plain_boundary);
        project_word(rotated, rotated_boundary);
        transform_row(plain_boundary, plain_spectrum);
        transform_row(rotated_boundary, rotated_spectrum);

        for (unsigned frequency = 1u; frequency < BOUNDARY_WIDTH; frequency += 1u)
        {
            const double drift =
                std::fabs(std::abs(plain_spectrum[frequency]) - std::abs(rotated_spectrum[frequency]));
            worst_magnitude_drift = std::max(worst_magnitude_drift, drift);

            if (std::abs(plain_spectrum[frequency]) > 1e-6)
            {
                // A right rotation by s advances the phase by +2 pi k s / 32.
                const std::complex<double> ratio =
                    rotated_spectrum[frequency] / plain_spectrum[frequency];
                const double predicted = 2.0 * 3.14159265358979323846 * (double)frequency *
                                         (double)shift / (double)BOUNDARY_WIDTH;
                double error = std::arg(ratio) - predicted;

                while (error > 3.14159265358979323846)
                {
                    error -= 2.0 * 3.14159265358979323846;
                }
                while (error < -3.14159265358979323846)
                {
                    error += 2.0 * 3.14159265358979323846;
                }
                worst_phase_error = std::max(worst_phase_error, std::fabs(error));
            }
        }
    }

    std::printf("\n  Over 256 random words and random rotations:\n");
    std::printf("    largest magnitude drift : %.3e  (identity predicts 0)\n",
                worst_magnitude_drift);
    std::printf("    largest phase error     : %.3e rad  (identity predicts 0)\n",
                worst_phase_error);
    check("magnitude spectrum is rotation invariant", worst_magnitude_drift < 1e-9);
    check("phase advances exactly as 2*pi*k*r/32", worst_phase_error < 1e-9);
    std::printf("\n  So the representation does know when it was rotated. It reads r off the\n");
    std::printf("  phase to machine precision, and the magnitude never moves. Everything after\n");
    std::printf("  this asks how many rounds that survives.\n");
}

/**
 * @brief Recovers a rotation from two boundaries by circular cross correlation.
 *
 * @param[in] left  First word.
 * @param[in] right Second word.
 * @return          The shift whose alignment scores highest.
 * @note Cross correlation is the inverse transform of one spectrum times the conjugate of the
 *       other, so this is the phase reading of the premise, computed in the domain where it is
 *       cheapest. The convolution theorem makes the two identical.
 */
unsigned recover_rotation(uint32_t left, uint32_t right)
{
    double left_boundary[BOUNDARY_WIDTH];
    double right_boundary[BOUNDARY_WIDTH];

    project_word(left, left_boundary);
    project_word(right, right_boundary);

    unsigned best_shift = 0u;
    double best_score = -1e300;

    // right is left rotated right by s, so right[i] == left[(i + s) mod 32]. The correlation that
    // peaks at s is therefore right against left displaced, not left against right. Taking those in
    // the other order peaks at 32 - s and never matches the shift it was asked to find.
    for (unsigned shift = 0u; shift < BOUNDARY_WIDTH; shift += 1u)
    {
        double score = 0.0;

        for (unsigned position = 0u; position < BOUNDARY_WIDTH; position += 1u)
        {
            score += right_boundary[position] *
                     left_boundary[(position + shift) % BOUNDARY_WIDTH];
        }
        if (score > best_score)
        {
            best_score = score;
            best_shift = shift;
        }
    }
    return best_shift;
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
 * @brief Asks how many rounds a rotation in the input remains readable in the output.
 */
void measure_rotation_memory()
{
    std::printf("\n================================================================\n");
    std::printf("  1. How many rounds does it remember the rotation?\n");
    std::printf("================================================================\n");
    std::printf("\n  Two chaining values differing by a rotation of one word, same message block.\n");
    std::printf("  Run both through r rounds, then read the rotation back off the boundary.\n");
    std::printf("  Chance is 1/32 = 3.1%%. Round zero must read 100%% by construction, which is\n");
    std::printf("  what makes this a decay curve instead of an assertion.\n");
    std::printf("\n  The rotation is applied to the chaining value and not to the nonce. The\n");
    std::printf("  nonce sits at schedule word three and does not enter until round three, so\n");
    std::printf("  rotating it would report zero recovery for the first three rounds through\n");
    std::printf("  absence instead of through diffusion, and read as a decay that never was.\n");
    std::printf("\n  %8s %14s %12s\n", "rounds", "recovered", "vs chance");
    std::printf("  %8s %14s %12s\n", "--------", "--------------", "------------");

    std::mt19937 generator(20260908u);
    const unsigned trials = 4096u;
    unsigned last_informative_round = 0u;
    bool ever_informative = false;

    for (unsigned rounds : {0u, 1u, 2u, 3u, 4u, 5u, 6u, 8u, 10u, 12u, 16u, 20u, 24u, 32u, 48u, 64u})
    {
        unsigned recovered = 0u;

        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            const unsigned shift = 1u + (generator() % 31u);

            uint32_t block[SHA256_BLOCK_WORDS];
            fill_tail_block(block, generator());

            Sha256State plain_state;
            Sha256State rotated_state;
            for (unsigned slot = 0u; slot < BOUNDARY_HEIGHT; slot += 1u)
            {
                const uint32_t word = generator();
                plain_state.word[slot] = word;
                rotated_state.word[slot] = word;
            }
            rotated_state.word[0] = rotate_right(plain_state.word[0], shift);

            sha256_block_compress_partial(&plain_state, block, rounds);
            sha256_block_compress_partial(&rotated_state, block, rounds);

            // Read the shift off the word the rotation entered on, which is the most favourable
            // place for it to still be visible.
            if (recover_rotation(plain_state.word[0], rotated_state.word[0]) == shift)
            {
                recovered += 1u;
            }
        }

        const double rate = (double)recovered / (double)trials;
        const double chance = 1.0 / (double)BOUNDARY_WIDTH;
        const double standard_error = std::sqrt(chance * (1.0 - chance) / (double)trials);
        const double score = (rate - chance) / standard_error;

        if (score > 5.0)
        {
            last_informative_round = rounds;
            ever_informative = true;
        }
        std::printf("  %8u %13.2f%% %+11.1f sigma\n", rounds, rate * 100.0, score);
    }

    if (ever_informative)
    {
        std::printf("\n  Last round still above chance: %u.\n", last_informative_round);
    }
    else
    {
        std::printf("\n  Never above chance, which would mean the control itself is broken.\n");
    }
    std::printf("  SHA-256 runs 64 rounds and Bitcoin runs it twice, so a header hash is 128\n");
    std::printf("  rounds deep. Compare that against the round the signal died at.\n");
}

/**
 * @brief Measures diffusion directly: one flipped input bit against output bits moved.
 */
void measure_avalanche()
{
    std::printf("\n================================================================\n");
    std::printf("  2. Diffusion. When does one flipped bit reach half the state?\n");
    std::printf("================================================================\n");
    std::printf("\n  Flip one bit of the nonce, run r rounds, count state bits that moved.\n");
    std::printf("  A function with nothing left to leak sits at 50%% and stays there.\n");
    std::printf("\n  %8s %14s\n", "rounds", "bits moved");
    std::printf("  %8s %14s\n", "--------", "--------------");

    std::mt19937 generator(20260908u);
    const unsigned trials = 2048u;
    unsigned saturation_round = 0u;
    bool saturated = false;

    for (unsigned rounds : {1u, 2u, 3u, 4u, 5u, 6u, 7u, 8u, 10u, 12u, 14u, 16u, 20u, 24u, 32u, 64u})
    {
        uint64_t moved_total = 0u;

        for (unsigned trial = 0u; trial < trials; trial += 1u)
        {
            const uint32_t nonce = generator();
            const unsigned bit = generator() % 32u;

            uint32_t plain_block[SHA256_BLOCK_WORDS];
            uint32_t flipped_block[SHA256_BLOCK_WORDS];
            fill_tail_block(plain_block, nonce);
            fill_tail_block(flipped_block, nonce ^ (1u << bit));

            Sha256State plain_state;
            Sha256State flipped_state;
            sha256_state_init(&plain_state);
            sha256_state_init(&flipped_state);
            sha256_block_compress_partial(&plain_state, plain_block, rounds);
            sha256_block_compress_partial(&flipped_state, flipped_block, rounds);

            for (unsigned slot = 0u; slot < BOUNDARY_HEIGHT; slot += 1u)
            {
                moved_total += (uint64_t)__builtin_popcount(plain_state.word[slot] ^
                                                            flipped_state.word[slot]);
            }
        }

        const double fraction = (double)moved_total / ((double)trials * 256.0);
        if (!saturated && (fraction > 0.49) && (fraction < 0.51))
        {
            saturation_round = rounds;
            saturated = true;
        }
        std::printf("  %8u %13.2f%%\n", rounds, fraction * 100.0);
    }

    std::printf("\n  Half the state moves by round %u, and the header hash runs 128 rounds.\n",
                saturation_round);
    std::printf("  Past saturation the output carries no readable trace of which bit moved.\n");
}

/**
 * @brief Measures how flat the boundary spectrum is, round by round.
 */
void measure_spectral_flatness()
{
    std::printf("\n================================================================\n");
    std::printf("  3. The boundary spectrum. Does any frequency stand up?\n");
    std::printf("================================================================\n");
    std::printf("\n  Mean power per frequency across the 8 by 32 boundary. A structured state\n");
    std::printf("  concentrates power in a few bins. Flat spectral flatness is 1.0.\n");
    std::printf("\n  %8s %18s %14s\n", "rounds", "spectral flatness", "peak / mean");
    std::printf("  %8s %18s %14s\n", "--------", "------------------", "--------------");

    std::mt19937 generator(20260908u);
    const unsigned trials = 4096u;

    for (unsigned rounds : {0u, 1u, 2u, 4u, 8u, 16u, 32u, 64u})
    {
        double power[BOUNDARY_WIDTH];
        for (unsigned frequency = 0u; frequency < BOUNDARY_WIDTH; frequency += 1u)
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

            for (unsigned row = 0u; row < BOUNDARY_HEIGHT; row += 1u)
            {
                double boundary[BOUNDARY_WIDTH];
                std::complex<double> spectrum[BOUNDARY_WIDTH];

                project_word(state.word[row], boundary);
                transform_row(boundary, spectrum);
                for (unsigned frequency = 0u; frequency < BOUNDARY_WIDTH; frequency += 1u)
                {
                    power[frequency] += std::norm(spectrum[frequency]);
                }
            }
        }

        // Spectral flatness is the geometric mean over the arithmetic mean, excluding the constant
        // bin, which only reports the state's bit balance instead of any periodicity.
        double log_sum = 0.0;
        double linear_sum = 0.0;
        double peak = 0.0;
        for (unsigned frequency = 1u; frequency < BOUNDARY_WIDTH; frequency += 1u)
        {
            const double value = power[frequency];
            log_sum += std::log(std::max(value, 1e-300));
            linear_sum += value;
            peak = std::max(peak, value);
        }
        const double count = (double)(BOUNDARY_WIDTH - 1u);
        const double geometric = std::exp(log_sum / count);
        const double arithmetic = linear_sum / count;
        const double flatness = (arithmetic > 0.0) ? (geometric / arithmetic) : 0.0;

        std::printf("  %8u %17.6f %14.4f\n", rounds, flatness,
                    (arithmetic > 0.0) ? (peak / arithmetic) : 0.0);
    }

    std::printf("\n  The nonce enters at word three and the state starts on the fixed initial\n");
    std::printf("  value, so round zero is highly structured and its flatness is far from one.\n");
    std::printf("  By the round count a real hash uses there is no bin left standing up.\n");
}

/**
 * @brief Confirms the reduced-round instrument agrees with the real function at full depth.
 */
void check_instrument()
{
    std::printf("\n================================================================\n");
    std::printf("  Instrument check\n");
    std::printf("================================================================\n");

    std::mt19937 generator(1u);
    bool all_matched = true;

    for (unsigned trial = 0u; trial < 512u; trial += 1u)
    {
        uint32_t block[SHA256_BLOCK_WORDS];
        for (unsigned slot = 0u; slot < SHA256_BLOCK_WORDS; slot += 1u)
        {
            block[slot] = generator();
        }

        Sha256State full;
        Sha256State partial;
        sha256_state_init(&full);
        sha256_state_init(&partial);
        sha256_block_compress(&full, block);
        sha256_block_compress_partial(&partial, block, 64u);

        if (std::memcmp(full.word, partial.word, sizeof(full.word)) != 0)
        {
            all_matched = false;
        }
    }
    check("reduced-round instrument at 64 rounds equals the real compression", all_matched,
          "the instrument has drifted from the function it measures");

    uint8_t digest[32];
    sha256_hash((const uint8_t *)"abc", 3u, digest);
    const bool reference_holds =
        (digest[0] == 0xbau) && (digest[1] == 0x78u) && (digest[30] == 0x15u) &&
        (digest[31] == 0xadu);
    check("SHA-256 still matches FIPS 180-4 B.1", reference_holds);
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  SHA-256 on its two dimensional boundary\n");
    std::printf("  Rotation is a phase ramp. How far does the phase travel?\n");
    std::printf("================================================================\n");

    const auto started = std::chrono::steady_clock::now();

    check_instrument();
    check_rotation_identity();
    measure_rotation_memory();
    measure_avalanche();
    measure_spectral_flatness();

    const auto finished = std::chrono::steady_clock::now();

    std::printf("\n================================================================\n");
    std::printf("  %d checks run, %d failed\n", g_checks_run, g_checks_failed);
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return (g_checks_failed == 0) ? 0 : 1;
}
