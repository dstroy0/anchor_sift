/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_cosalt.cpp
 * @brief Many salts at once. Do they combine independently, and does the tail fall as predicted?
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note This is the anchor cascade of anchor-sift.md section 2.5 applied to salts instead of to
 *       corpus positions. k anchors at rate q leave q^k survivors, so a cascade drives the tail to
 *       zero exponentially. That part is arithmetic and is not in question.
 * @note What is in question, and what this measures, is independence. The exponential fall assumes
 *       the anchors are independent. Where two salts' responses are correlated the product rule
 *       fails, the tail departs from q^k, and that departure is structure. Section 4.6 of the paper
 *       measures exactly this for corpus anchors under the name dependence in anchor cascades.
 * @note So a tail that falls exactly as predicted is a null result, and a tail that falls faster or
 *       slower than predicted is a finding. The prediction is stated before the measurement in every
 *       table below.
 */

#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace
{

/** @brief Block 125552, so the header under test is reproducible. */
const char *const HEADER_HEX =
    "0100000081cd02ab7e569e8bcd9317e2fe99f2de44d49ab2b8851ba4a308000000000000e320b6c2fffc8d750423"
    "db8b1eb942ae710e951ed797f7affc8892b0f1fc122bc7f5d74df2b9441a42a14695";

/** @brief Salts drawn from the algorithm's own structure, as co-arms of one cascade. */
const uint32_t CO_SALTS[] = {
    0x00000001u,                        // single bit
    (1u << 2) | (1u << 13) | (1u << 22),  // Sigma0 rotation set
    (1u << 6) | (1u << 11) | (1u << 25),  // Sigma1 rotation set
    (1u << 7) | (1u << 18) | (1u << 3),   // sigma0 set with its shift
    (1u << 17) | (1u << 19) | (1u << 10), // sigma1 set with its shift
    0x428a2f98u,                          // round constant K[0]
};
const unsigned SALT_COUNT = (unsigned)(sizeof(CO_SALTS) / sizeof(CO_SALTS[0]));

Sha256ScanRequest g_base;

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
 * @brief Hashes one nonce and returns the digest words in protocol order.
 *
 * @param[in]  nonce   The candidate.
 * @param[out] ordered Eight words, most significant first [BORROWS].
 */
void digest_for_nonce(uint32_t nonce, uint32_t *ordered)
{
    uint32_t block[SHA256_BLOCK_WORDS];
    Sha256State first_pass = g_base.midstate;

    block[0] = g_base.merkle_root_tail;
    block[1] = g_base.ntime;
    block[2] = g_base.nbits;
    block[3] = ((nonce >> 24) & 0xFFu) | ((nonce >> 8) & 0xFF00u) | ((nonce << 8) & 0xFF0000u) |
               ((nonce << 24) & 0xFF000000u);
    block[4] = 0x80000000u;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        block[slot] = 0u;
    }
    block[15] = 0x00000280u;
    sha256_block_compress(&first_pass, block);

    Sha256State second_pass;
    sha256_state_init(&second_pass);
    for (unsigned slot = 0u; slot < 8u; slot += 1u)
    {
        block[slot] = first_pass.word[slot];
    }
    block[8] = 0x80000000u;
    for (unsigned slot = 9u; slot < 15u; slot += 1u)
    {
        block[slot] = 0u;
    }
    block[15] = 0x00000100u;
    sha256_block_compress(&second_pass, block);

    for (unsigned rank = 0u; rank < 8u; rank += 1u)
    {
        const uint32_t word = second_pass.word[7u - rank];
        ordered[rank] = ((word >> 24) & 0x000000FFu) | ((word >> 8) & 0x0000FF00u) |
                        ((word << 8) & 0x00FF0000u) | ((word << 24) & 0xFF000000u);
    }
}

/** @brief What one worker accumulates. */
struct Tally
{
    // Joint occupancy of the k-salt response pattern at the leading bit, 2^SALT_COUNT cells.
    std::vector<uint64_t> joint;
    // Pairwise agreement between salt i and salt j at the leading bit.
    std::vector<uint64_t> pair_agree;
    // How many candidates survived a cascade of the first k salts requiring all differences clear.
    std::vector<uint64_t> cascade;
    uint64_t evaluated;

    Tally()
        : joint((size_t)1u << SALT_COUNT, 0u), pair_agree(SALT_COUNT * SALT_COUNT, 0u),
          cascade(SALT_COUNT + 1u, 0u), evaluated(0u)
    {
    }
};

/**
 * @brief Runs one worker's share of the range.
 *
 * @param[in]  start  First nonce.
 * @param[in]  count  How many.
 * @param[out] tally  Where the counts land [BORROWS].
 */
void run_share(uint32_t start, uint32_t count, Tally &tally)
{
    for (uint32_t step = 0u; step < count; step += 1u)
    {
        const uint32_t nonce = start + step;
        uint32_t plain[8];
        digest_for_nonce(nonce, plain);

        unsigned pattern = 0u;
        unsigned response[16];

        for (unsigned index = 0u; index < SALT_COUNT; index += 1u)
        {
            uint32_t salted[8];
            digest_for_nonce(nonce ^ CO_SALTS[index], salted);

            // The leading bit of the difference is the one the target cares about first.
            const unsigned bit = ((plain[0] ^ salted[0]) >> 31) & 1u;
            response[index] = bit;
            pattern |= (bit << index);
        }

        tally.joint[pattern] += 1u;
        for (unsigned left = 0u; left < SALT_COUNT; left += 1u)
        {
            for (unsigned right = 0u; right < SALT_COUNT; right += 1u)
            {
                if (response[left] == response[right])
                {
                    tally.pair_agree[(left * SALT_COUNT) + right] += 1u;
                }
            }
        }

        // The cascade: require the first k responses all clear. Section 2.5 predicts the survivor
        // count falls by a factor of two per arm added, if the arms are independent.
        unsigned depth = 0u;
        while ((depth < SALT_COUNT) && (response[depth] == 0u))
        {
            depth += 1u;
        }
        for (unsigned width = 0u; width <= depth; width += 1u)
        {
            tally.cascade[width] += 1u;
        }
        tally.evaluated += 1u;
    }
}

} // namespace

int main(int argument_count, char **arguments)
{
    uint32_t total = (argument_count > 1) ? (uint32_t)std::stoul(arguments[1]) : (1u << 21);

    std::printf("================================================================\n");
    std::printf("  Co-arm salts: do they combine independently?\n");
    std::printf("================================================================\n");
    std::printf("\n  %u salts, most read off the algorithm's own rotation sets.\n", SALT_COUNT);
    std::printf("  Each candidate costs %u hashes, so %u candidates is %u hashes.\n",
                SALT_COUNT + 1u, total, total * (SALT_COUNT + 1u));

    const std::vector<uint8_t> header = bytes_from_hex(HEADER_HEX);
    std::memset(&g_base, 0, sizeof(g_base));
    sha256_header_midstate(&g_base.midstate, header.data());
    g_base.merkle_root_tail = schedule_word_from_header(header.data() + 64u);
    g_base.ntime = schedule_word_from_header(header.data() + 68u);
    g_base.nbits = schedule_word_from_header(header.data() + 72u);

    const unsigned available = (std::thread::hardware_concurrency() > 1u)
                                   ? (std::thread::hardware_concurrency() - 1u)
                                   : 1u;
    std::vector<Tally> tallies(available);
    std::vector<std::thread> workers;
    const uint32_t share = total / available;

    const auto started = std::chrono::steady_clock::now();
    for (unsigned index = 0u; index < available; index += 1u)
    {
        workers.emplace_back(
            [index, share, &tallies]() { run_share(index * share, share, tallies[index]); });
    }
    for (std::thread &worker : workers)
    {
        worker.join();
    }
    const auto finished = std::chrono::steady_clock::now();

    Tally combined;
    for (const Tally &partial : tallies)
    {
        combined.evaluated += partial.evaluated;
        for (size_t at = 0u; at < combined.joint.size(); at += 1u)
        {
            combined.joint[at] += partial.joint[at];
        }
        for (size_t at = 0u; at < combined.pair_agree.size(); at += 1u)
        {
            combined.pair_agree[at] += partial.pair_agree[at];
        }
        for (size_t at = 0u; at < combined.cascade.size(); at += 1u)
        {
            combined.cascade[at] += partial.cascade[at];
        }
    }

    const double samples = (double)combined.evaluated;
    std::printf("\n  %llu candidates in %.1f s\n", (unsigned long long)combined.evaluated,
                std::chrono::duration<double>(finished - started).count());

    // --- The cascade tail -------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  1. The cascade tail. Does it fall as 2^-k?\n");
    std::printf("================================================================\n");
    std::printf("\n  Requiring the first k salt responses all clear. Independent arms halve the\n");
    std::printf("  survivor count per arm, so the prediction is stated before the measurement.\n");
    std::printf("\n  %6s %16s %16s %10s %10s\n", "arms", "predicted", "measured", "ratio",
                "sigma");
    std::printf("  %6s %16s %16s %10s %10s\n", "------", "----------------", "----------------",
                "----------", "----------");

    for (unsigned width = 0u; width <= SALT_COUNT; width += 1u)
    {
        const double rate = std::pow(0.5, (double)width);
        const double predicted = samples * rate;
        const double measured = (double)combined.cascade[width];
        const double standard_error = std::sqrt(samples * rate * (1.0 - rate));
        const double score =
            (standard_error > 0.0) ? ((measured - predicted) / standard_error) : 0.0;

        std::printf("  %6u %16.1f %16.0f %10.5f %+10.2f\n", width, predicted, measured,
                    (predicted > 0.0) ? (measured / predicted) : 0.0, score);
    }
    std::printf("\n  The tail does fall to zero, and that is arithmetic instead of a finding.\n");
    std::printf("  What would be a finding is a ratio away from one, meaning the arms are not\n");
    std::printf("  independent and the product rule does not hold.\n");

    // --- Pairwise independence --------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  2. Are the arms independent of each other?\n");
    std::printf("================================================================\n");
    std::printf("\n  Agreement between each pair of salt responses. Independent arms agree half\n");
    std::printf("  the time. Standard error is %.2e.\n", 0.5 / std::sqrt(samples));

    double worst_pair = 0.0;
    unsigned worst_left = 0u;
    unsigned worst_right = 0u;

    for (unsigned left = 0u; left < SALT_COUNT; left += 1u)
    {
        for (unsigned right = left + 1u; right < SALT_COUNT; right += 1u)
        {
            const double agreement =
                (double)combined.pair_agree[(left * SALT_COUNT) + right] / samples;
            const double score = (agreement - 0.5) / (0.5 / std::sqrt(samples));

            if (std::fabs(score) > std::fabs(worst_pair))
            {
                worst_pair = score;
                worst_left = left;
                worst_right = right;
            }
        }
    }
    std::printf("\n  largest departure: salts %u and %u at %+.2f sigma\n", worst_left, worst_right,
                worst_pair);
    std::printf("  pairs tested     : %u, so the expected worst by chance is near %.1f sigma\n",
                (SALT_COUNT * (SALT_COUNT - 1u)) / 2u,
                std::sqrt(2.0 * std::log((double)((SALT_COUNT * (SALT_COUNT - 1u)) / 2u))));
    std::printf("  verdict          : %s\n",
                (std::fabs(worst_pair) < 5.0) ? "arms are independent"
                                              : "ARMS ARE COUPLED, worth investigating");

    // --- Joint occupancy --------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  3. Joint occupancy of the response pattern\n");
    std::printf("================================================================\n");
    std::printf("\n  All %zu response patterns should be equally likely. Chi-square against that.\n",
                combined.joint.size());

    const double expected = samples / (double)combined.joint.size();
    double chi_square = 0.0;
    for (size_t cell = 0u; cell < combined.joint.size(); cell += 1u)
    {
        const double residual = (double)combined.joint[cell] - expected;
        chi_square += (residual * residual) / expected;
    }
    const double degrees = (double)combined.joint.size() - 1.0;
    const double chi_score = (chi_square - degrees) / std::sqrt(2.0 * degrees);

    std::printf("\n  chi-square %.1f on %.0f df (expected %.0f), z = %+.2f\n", chi_square, degrees,
                degrees, chi_score);
    std::printf("  verdict   : %s\n",
                (std::fabs(chi_score) < 5.0) ? "no response pattern is preferred"
                                             : "A PATTERN IS PREFERRED, worth investigating");

    // --- Does the sieve keep the winners? ---------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  4. The survivor divider. Does it divide the winners too?\n");
    std::printf("================================================================\n");
    std::printf("\n  A cascade halves the survivor count per arm, which sections 1 to 3 confirm.\n");
    std::printf("  The question that decides whether it is worth anything is whether the\n");
    std::printf("  candidates it keeps are enriched in winners, or merely fewer.\n");
    std::printf("\n  Section 2.2 of anchor-sift.md is the test. An anchor is sound because it is\n");
    std::printf("  a subconfiguration of the pattern, so an occurrence must satisfy it and no\n");
    std::printf("  occurrence can be lost. A salt response is not a member of that set: it is a\n");
    std::printf("  property of a difference between two candidates, not a condition the target\n");
    std::printf("  imposes on one. So the theorem does not cover it, and whether it keeps\n");
    std::printf("  winners has to be measured.\n");

    // An easy target so winners are common enough to count: 12 leading zero bits, about 1 in 4096.
    const unsigned target_bits = 12u;
    std::vector<uint64_t> survivors(SALT_COUNT + 1u, 0u);
    std::vector<uint64_t> winners(SALT_COUNT + 1u, 0u);
    const uint32_t audit = total;

    for (uint32_t step = 0u; step < audit; step += 1u)
    {
        uint32_t plain[8];
        digest_for_nonce(step, plain);

        unsigned leading = 0u;
        for (unsigned rank = 0u; rank < 8u; rank += 1u)
        {
            if (plain[rank] != 0u)
            {
                unsigned bit = 31u;
                while ((bit < 32u) && (((plain[rank] >> bit) & 1u) == 0u))
                {
                    leading += 1u;
                    bit -= 1u;
                }
                break;
            }
            leading += 32u;
        }
        const bool is_winner = (leading >= target_bits);

        unsigned depth = 0u;
        while (depth < SALT_COUNT)
        {
            uint32_t salted[8];
            digest_for_nonce(step ^ CO_SALTS[depth], salted);
            if ((((plain[0] ^ salted[0]) >> 31) & 1u) != 0u)
            {
                break;
            }
            depth += 1u;
        }
        for (unsigned width = 0u; width <= depth; width += 1u)
        {
            survivors[width] += 1u;
            if (is_winner)
            {
                winners[width] += 1u;
            }
        }
    }

    std::printf("\n  Target is %u leading zero bits, about one candidate in %.0f.\n", target_bits,
                std::pow(2.0, (double)target_bits));
    std::printf("\n  %6s %14s %12s %16s %10s\n", "arms", "survivors", "winners", "winner rate",
                "enriched");
    std::printf("  %6s %14s %12s %16s %10s\n", "------", "--------------", "------------",
                "----------------", "----------");

    const double base_rate =
        (survivors[0] > 0u) ? ((double)winners[0] / (double)survivors[0]) : 0.0;

    for (unsigned width = 0u; width <= SALT_COUNT; width += 1u)
    {
        const double rate =
            (survivors[width] > 0u) ? ((double)winners[width] / (double)survivors[width]) : 0.0;
        std::printf("  %6u %14llu %12llu %16.8f %10.4f\n", width,
                    (unsigned long long)survivors[width], (unsigned long long)winners[width], rate,
                    (base_rate > 0.0) ? (rate / base_rate) : 0.0);
    }

    std::printf("\n  Enrichment near 1.0 at every depth means the cascade threw away winners at\n");
    std::printf("  exactly the rate it threw away everything else. It is a survivor divider that\n");
    std::printf("  divides the survivors you want along with the rest, so it costs %u extra\n",
                SALT_COUNT);
    std::printf("  hashes per candidate and buys no concentration.\n");
    std::printf("\n  Enrichment rising with depth would be the finding: a filter that keeps\n");
    std::printf("  winners preferentially, which is what a sound anchor does by construction and\n");
    std::printf("  what a salt response would have to be shown to do by measurement.\n");

    std::printf("\n================================================================\n");
    return 0;
}
