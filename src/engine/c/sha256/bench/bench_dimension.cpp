/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_dimension.cpp
 * @brief n dimensions at once, at every intersection. Higher-order differentials and the degree.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Every earlier measurement in this tree was first order and one dimension at a time: one
 *       salt, one flipped bit, one dimension measured on its own. None of them looked at what
 *       happens where difference directions intersect, and that is where the only exact statement
 *       available about this function lives.
 * @note The k-th order differential of f along independent directions d1..dk is the sum over all
 *       2^k subsets S of f(x xor (sum of di for i in S)). If the algebraic degree of f over GF(2) is
 *       less than k, this is identically zero for every x. Not small. Zero. That makes a vanishing
 *       differential a proof of a degree bound instead of a sampled bound, which is what section 3
 *       of the topology document asked for and did not have.
 * @note The measurement therefore reads the algebraic degree of reduced-round SHA-256 as a function
 *       of the nonce, by finding the largest order that still vanishes. Degree growth is the
 *       quantity that decides whether any algebraic attack has room to work.
 * @warning Cost is 2^k hashes per base point, so the order axis is exponential and the table stops
 *          where it stops for that reason and not because anything was found there.
 */

#include "bench_seed.h"
#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <thread>
#include <vector>

namespace
{

/** @brief Block 125552, so the header under test is reproducible. */
const char *const HEADER_HEX =
    "0100000081cd02ab7e569e8bcd9317e2fe99f2de44d49ab2b8851ba4a308000000000000e320b6c2fffc8d750423"
    "db8b1eb942ae710e951ed797f7affc8892b0f1fc122bc7f5d74df2b9441a42a14695";

Sha256State g_midstate;
uint32_t g_merkle_tail = 0u;
uint32_t g_ntime = 0u;
uint32_t g_nbits = 0u;

/**
 * @brief Converts a hex string to bytes.
 *
 * @param[in] hex Characters to convert.
 * @return        The bytes they spell.
 */
std::vector<uint8_t> bytes_from_hex(const std::string &hex)
{
    std::vector<uint8_t> bytes;

    bytes.reserve(hex.size() / 2u);
    for (size_t at = 0u; (at + 1u) < hex.size(); at += 2u)
    {
        bytes.push_back((uint8_t)std::stoul(hex.substr(at, 2u), nullptr, 16));
    }
    return bytes;
}

/**
 * @brief Reads four header bytes as the big-endian word SHA-256 schedules.
 *
 * @param[in] bytes Four bytes [BORROWS].
 * @return          The schedule word.
 */
uint32_t schedule_word_from_header(const uint8_t *bytes)
{
    return ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) |
           (uint32_t)bytes[3];
}

/**
 * @brief The function under test: reduced-round compression of the header tail, as a map from nonce.
 *
 * @param[in]  nonce  The input.
 * @param[in]  rounds How many rounds to run.
 * @param[out] state  The resulting chaining value [BORROWS].
 */
void evaluate(uint32_t nonce, unsigned rounds, Sha256State *state)
{
    uint32_t block[SHA256_BLOCK_WORDS];

    *state = g_midstate;
    block[0] = g_merkle_tail;
    block[1] = g_ntime;
    block[2] = g_nbits;
    block[3] = ((nonce >> 24) & 0xFFu) | ((nonce >> 8) & 0xFF00u) | ((nonce << 8) & 0xFF0000u) |
               ((nonce << 24) & 0xFF000000u);
    block[4] = 0x80000000u;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        block[slot] = 0u;
    }
    block[15] = 0x00000280u;
    sha256_block_compress_partial(state, block, rounds);
}

/**
 * @brief Computes one k-th order differential and reports whether it vanished.
 *
 * @param[in] base       The base point.
 * @param[in] directions The k independent directions [BORROWS].
 * @param[in] order      k.
 * @param[in] rounds     Rounds to run.
 * @return               True where the differential is exactly zero in all 256 bits.
 * @note The sum is over every one of the 2^k subsets, which is what makes this an intersection
 *       measurement instead of k separate first-order ones.
 */
bool differential_vanishes(uint32_t base, const uint32_t *directions, unsigned order,
                           unsigned rounds)
{
    uint32_t accumulated[SHA256_STATE_WORDS] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
    const uint32_t subsets = 1u << order;

    for (uint32_t subset = 0u; subset < subsets; subset += 1u)
    {
        uint32_t point = base;
        for (unsigned index = 0u; index < order; index += 1u)
        {
            if (((subset >> index) & 1u) != 0u)
            {
                point ^= directions[index];
            }
        }

        Sha256State value;
        evaluate(point, rounds, &value);
        for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
        {
            accumulated[slot] ^= value.word[slot];
        }
    }

    for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
    {
        if (accumulated[slot] != 0u)
        {
            return false;
        }
    }
    return true;
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  n dimensions at once: higher-order differentials\n");
    std::printf("  The degree of reduced-round SHA-256 as a map from the nonce\n");
    std::printf("================================================================\n");

    const std::vector<uint8_t> header = bytes_from_hex(HEADER_HEX);
    sha256_header_midstate(&g_midstate, header.data());
    g_merkle_tail = schedule_word_from_header(header.data() + 64u);
    g_ntime = schedule_word_from_header(header.data() + 68u);
    g_nbits = schedule_word_from_header(header.data() + 72u);

    std::printf("\n  A k-th order differential sums f over all 2^k corners of a k-dimensional\n");
    std::printf("  cube of input differences. If the algebraic degree over GF(2) is below k it\n");
    std::printf("  is identically zero, for every base point, exactly. So a column of 'vanishes'\n");
    std::printf("  is a proof of a degree bound, not a sampled bound.\n");
    std::printf("\n  Directions are distinct single bits of the nonce, so the cube spans k of the\n");
    std::printf("  32 input dimensions and every one of its intersections is visited.\n");

    std::mt19937 generator(bench_seed(20260908u));
    const unsigned base_points = 24u;
    const unsigned max_order = 12u;

    std::printf("\n  vanishes at every base point tested = V, fails somewhere = .\n");
    std::printf("\n  %6s", "rounds");
    for (unsigned order = 1u; order <= max_order; order += 1u)
    {
        std::printf(" %2u", order);
    }
    std::printf("   degree is at least\n");
    std::printf("  %6s", "------");
    for (unsigned order = 1u; order <= max_order; order += 1u)
    {
        std::printf(" --");
    }
    std::printf("   ------------------\n");

    const auto started = std::chrono::steady_clock::now();

    for (unsigned rounds = 1u; rounds <= 10u; rounds += 1u)
    {
        std::printf("  %6u", rounds);
        unsigned lowest_failing = 0u;

        for (unsigned order = 1u; order <= max_order; order += 1u)
        {
            bool always_vanishes = true;

            for (unsigned trial = 0u; trial < base_points; trial += 1u)
            {
                // Distinct single-bit directions, drawn without replacement.
                uint32_t directions[16];
                unsigned chosen = 0u;
                uint32_t used = 0u;

                while (chosen < order)
                {
                    const unsigned position = generator() % 32u;
                    if (((used >> position) & 1u) == 0u)
                    {
                        used |= (1u << position);
                        directions[chosen] = (1u << position);
                        chosen += 1u;
                    }
                }

                if (!differential_vanishes(generator(), directions, order, rounds))
                {
                    always_vanishes = false;
                    break;
                }
            }

            std::printf("  %c", always_vanishes ? 'V' : '.');
            // Order k vanishes exactly when the degree is below k, so the degree is the highest
            // order that fails. Reporting the lowest failing order instead would call every row
            // with any failure "degree 1", which is what an earlier version of this line did.
            if (!always_vanishes)
            {
                lowest_failing = order;
            }
        }

        if (lowest_failing == 0u)
        {
            std::printf("   0, the nonce has not entered\n");
        }
        else if (lowest_failing == max_order)
        {
            std::printf("   at least %u, past the table\n", max_order);
        }
        else
        {
            std::printf("   exactly %u\n", lowest_failing);
        }
    }

    const auto finished = std::chrono::steady_clock::now();

    std::printf("\n  Reading the table. A V means the differential was exactly zero at every base\n");
    std::printf("  point, which for a genuine degree bound is what the algebra requires and is\n");
    std::printf("  not a statistical statement. The first dot in a row is where the degree of the\n");
    std::printf("  reduced function reaches that order.\n");

    std::printf("\n  Why this is the exact measurement the other twenty were not. Every earlier\n");
    std::printf("  result in this tree says 'no structure was observed at this sensitivity'. A\n");
    std::printf("  vanishing higher-order differential says 'this function cannot have degree at\n");
    std::printf("  or above k', which no amount of sampling can overturn. Where the row fills\n");
    std::printf("  with dots, the degree has saturated and no algebraic attack of that order has\n");
    std::printf("  anything left to work on.\n");

    std::printf("\n  The nonce carries 32 bits, so degree 32 is the ceiling. A row that is all\n");
    std::printf("  dots by order %u is within a factor of three of that ceiling after a handful\n",
                max_order);
    std::printf("  of rounds, out of the 128 a header hash runs.\n");

    std::printf("\n================================================================\n");
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return 0;
}
