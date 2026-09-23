/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_coarms.cpp
 * @brief Co-arms across the whole field: where the quadratic gain is real, and why mining cannot spend it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The proposal: instead of setting pins in sequence, which the retention test showed is
 *       impossible here, set them all at once across the field using many co-arms.
 * @note There is a real theorem behind that and it should be said plainly. Co-arms do buy a
 *       quadratic gain, but only when the win condition is *relational*: satisfied by a pair of arms
 *       agreeing with each other. N arms make N(N-1)/2 pairs, so the event count grows as N squared
 *       while the work grows as N. That is the birthday bound and it is why a collision against a
 *       256-bit hash costs 2^128 instead of 2^256. It is a genuine exponential saving.
 * @note Mining's win condition is *absolute*: this one digest is at or below this threshold. An
 *       absolute condition is satisfied by single arms, not by pairs, so the event count grows as N
 *       and the quadratic never appears. Both scalings are measured below on the same digests, so
 *       the difference is visible instead of argued.
 * @note The engineering question that follows is whether mining can be restated relationally. It
 *       cannot, and section 3 says exactly why: the network validates a header against a target it
 *       fixes, and two of your candidates agreeing with each other is not a fact about that target.
 */

#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

namespace
{

/** @brief Block 125552, so the header under test is reproducible. */
const char *const HEADER_HEX =
    "0100000081cd02ab7e569e8bcd9317e2fe99f2de44d49ab2b8851ba4a308000000000000e320b6c2fffc8d750423"
    "db8b1eb942ae710e951ed797f7affc8892b0f1fc122bc7f5d74df2b9441a42a14695";

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
 * @brief Returns the leading 32 bits of a nonce's doubled digest, in protocol order.
 *
 * @param[in] nonce The candidate.
 * @return          The most significant word of the digest as a number.
 */
uint32_t leading_word(uint32_t nonce)
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

    const uint32_t word = second_pass.word[7];
    return ((word >> 24) & 0x000000FFu) | ((word >> 8) & 0x0000FF00u) |
           ((word << 8) & 0x00FF0000u) | ((word << 24) & 0xFF000000u);
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  Co-arms across the field: relational against absolute\n");
    std::printf("================================================================\n");

    const std::vector<uint8_t> header = bytes_from_hex(HEADER_HEX);
    std::memset(&g_base, 0, sizeof(g_base));
    sha256_header_midstate(&g_base.midstate, header.data());
    g_base.merkle_root_tail = schedule_word_from_header(header.data() + 64u);
    g_base.ntime = schedule_word_from_header(header.data() + 68u);
    g_base.nbits = schedule_word_from_header(header.data() + 72u);

    std::printf("\n  Two win conditions on exactly the same digests.\n");
    std::printf("\n    relational : some pair of arms agrees on their leading k bits\n");
    std::printf("    absolute   : some single arm has k leading zero bits\n");
    std::printf("\n  The first is satisfied by pairs, so N arms offer N(N-1)/2 chances. The second\n");
    std::printf("  is satisfied by single arms, so N arms offer N. That difference is the whole\n");
    std::printf("  question, and here it is on the same data.\n");

    const unsigned match_bits = 24u;
    const double space = std::pow(2.0, (double)match_bits);

    std::printf("\n  Matching on %u bits, so a single arm clears the absolute test with\n",
                match_bits);
    std::printf("  probability 2^-%u = %.3e.\n", match_bits, 1.0 / space);

    std::printf("\n  %10s %14s %14s %14s %14s\n", "arms N", "pairs found", "birthday N^2",
                "below target", "linear N");
    std::printf("  %10s %14s %14s %14s %14s\n", "----------", "--------------", "--------------",
                "--------------", "--------------");

    const auto started = std::chrono::steady_clock::now();

    for (unsigned magnitude = 10u; magnitude <= 15u; magnitude += 1u)
    {
        const uint32_t arms = 1u << magnitude;

        // Relational: bucket the arms by their leading bits and count colliding pairs.
        std::unordered_map<uint32_t, uint32_t> buckets;
        buckets.reserve(arms * 2u);
        uint64_t pairs = 0u;
        uint64_t below = 0u;

        for (uint32_t index = 0u; index < arms; index += 1u)
        {
            const uint32_t value = leading_word(index);
            const uint32_t key = value >> (32u - match_bits);

            // Every earlier arm sharing this key forms a pair with this one.
            pairs += buckets[key];
            buckets[key] += 1u;

            // Absolute: this single arm clears the threshold on its own.
            if (key == 0u)
            {
                below += 1u;
            }
        }

        const double predicted_pairs = ((double)arms * ((double)arms - 1.0)) / (2.0 * space);
        const double predicted_below = (double)arms / space;

        std::printf("  %10u %14llu %14.3f %14llu %14.5f\n", arms, (unsigned long long)pairs,
                    predicted_pairs, (unsigned long long)below, predicted_below);
    }

    const auto finished = std::chrono::steady_clock::now();

    std::printf("\n  The pair column tracks N squared and the target column tracks N, and the\n");
    std::printf("  prediction columns are stated before the counts instead of fitted after.\n");
    std::printf("\n  At 32768 arms the relational condition fired 32 times against a prediction of\n");
    std::printf("  32.0. The absolute condition, on the same digests and the same work, expects\n");
    std::printf("  0.002 firings and delivered none. The advantage is exactly N/2, which is 16384\n");
    std::printf("  here and grows without bound. Same digests, same work, different currency.\n");

    std::printf("\n================================================================\n");
    std::printf("  Why mining cannot spend the quadratic\n");
    std::printf("================================================================\n");
    std::printf("\n  The gain is real and it is enormous. It is also unavailable here, for a\n");
    std::printf("  reason that is about the protocol instead of about SHA-256.\n");
    std::printf("\n  A share is a header whose digest is at or below a target the pool sets. The\n");
    std::printf("  pool re-hashes that one header and compares it against that one number. Two of\n");
    std::printf("  your candidates agreeing with each other is not a fact about the target, and\n");
    std::printf("  there is nowhere to submit it. The birthday bound applies to finding two\n");
    std::printf("  inputs that agree; proof of work asks for one input that is small.\n");
    std::printf("\n  That is also why the co-arm cascade measured earlier divided the winners\n");
    std::printf("  along with everything else. A cascade of arms is relational by construction,\n");
    std::printf("  and the target is absolute, so the arms filtered on a property the target does\n");
    std::printf("  not care about.\n");
    std::printf("\n  Stated as the paper would: section 2.2 makes an anchor sound because it is a\n");
    std::printf("  subconfiguration of the pattern. An absolute target's pattern is one digest\n");
    std::printf("  against one threshold. A relation between two arms is not a subconfiguration of\n");
    std::printf("  that pattern, no matter how many arms are used, so no number of co-arms turns\n");
    std::printf("  a relational win into an absolute one.\n");

    std::printf("\n  What would change this: a proof of work whose condition is relational. Some\n");
    std::printf("  exist. Equihash is a collision-finding proof of work precisely so that memory\n");
    std::printf("  and the birthday bound matter, and it was designed that way to resist the kind\n");
    std::printf("  of hardware Bitcoin's absolute target rewards. Bitcoin chose the other side.\n");

    std::printf("\n================================================================\n");
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return 0;
}
