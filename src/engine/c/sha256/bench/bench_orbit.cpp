/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_orbit.cpp
 * @brief Do independent anchors stay independent, or do they collapse onto one orbit?
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note This exists because a conclusion recorded earlier in this tree does not follow from the
 *       measurement that was used to support it. H2 of the digest domain measured 7.999999 bits per
 *       byte and that was read as maximum entropy with nothing left to exploit.
 * @note anchor_sift/src/engine/c, bench_scaling, shows why that inference is unsound. A corpus of
 *       period sixteen is a single orbit under translation: position p carries p mod 16, so a needle
 *       taken at offset s matches an alignment at `at` exactly when (at + o) = (s + o) mod 16, and
 *       the offset cancels. Every anchor tests the same congruence whatever offset it sits at, so
 *       four probes ask one question four times and the predicted 2^-16 arrives as 1/16, wrong by
 *       4096. The histogram reads H2 exactly 4.0 throughout and cannot see any of it.
 * @note So H2 is blind to orbit structure, and a maximum-entropy reading rules out nothing. The
 *       question has to be asked directly: placed at independent positions, do anchors multiply?
 * @note H1 does not answer it. H1 used nested leading-zero prefixes, where k=16 implies k=8, and
 *       nested conditions scale as 2^-k whether or not the domain is an orbit. Independent positions
 *       are the test, and three placements are used because an orbit under word rotation would show
 *       in one of them and not the others.
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
#include <thread>
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

/** @brief Where the anchors are placed, which is the whole experiment. */
enum class Placement
{
    Scattered,   /**< Independent positions anywhere in the digest. */
    SameWord,    /**< All in one word, different bits. */
    SameBit,     /**< Same bit index across different words. An orbit under word rotation shows here. */
    Nested       /**< Leading-zero prefix, the control that scales trivially. */
};

/**
 * @brief Chooses k anchor positions under one placement rule.
 *
 * @param[in]     count     How many anchors.
 * @param[in]     placement Which rule.
 * @param[in,out] generator Random source [BORROWS].
 * @return                  The chosen bit positions, each in [0,256).
 */
std::vector<unsigned> choose_positions(unsigned count, Placement placement,
                                       std::mt19937 &generator)
{
    std::vector<unsigned> positions;

    if (placement == Placement::Nested)
    {
        for (unsigned at = 0u; at < count; at += 1u)
        {
            positions.push_back(at);
        }
        return positions;
    }
    if (placement == Placement::SameWord)
    {
        // One word carries 32 bits, so this rule caps at 32 anchors.
        const unsigned word = generator() % 8u;
        std::vector<unsigned> bits(32u);
        for (unsigned bit = 0u; bit < 32u; bit += 1u)
        {
            bits[bit] = bit;
        }
        std::shuffle(bits.begin(), bits.end(), generator);
        for (unsigned at = 0u; at < count; at += 1u)
        {
            positions.push_back((word * 32u) + bits[at]);
        }
        return positions;
    }
    if (placement == Placement::SameBit)
    {
        // Eight words, so this rule caps at 8 anchors. If the digest were an orbit under word
        // rotation, these would all test one condition, exactly as periodic16's offsets did.
        const unsigned bit = generator() % 32u;
        std::vector<unsigned> words(8u);
        for (unsigned word = 0u; word < 8u; word += 1u)
        {
            words[word] = word;
        }
        std::shuffle(words.begin(), words.end(), generator);
        for (unsigned at = 0u; at < count; at += 1u)
        {
            positions.push_back((words[at] * 32u) + bit);
        }
        return positions;
    }

    std::vector<unsigned> all(256u);
    for (unsigned at = 0u; at < 256u; at += 1u)
    {
        all[at] = at;
    }
    std::shuffle(all.begin(), all.end(), generator);
    for (unsigned at = 0u; at < count; at += 1u)
    {
        positions.push_back(all[at]);
    }
    return positions;
}

/**
 * @brief Counts nonces whose digest carries a zero at every anchor position.
 *
 * @param[in] positions Where the anchors sit [BORROWS].
 * @param[in] span      How many nonces to test.
 * @return              How many survived every anchor.
 */
uint64_t count_survivors(const std::vector<unsigned> &positions, uint32_t span)
{
    const unsigned workers = (std::thread::hardware_concurrency() > 1u)
                                 ? (std::thread::hardware_concurrency() - 1u)
                                 : 1u;
    std::vector<uint64_t> tallies(workers, 0u);
    std::vector<std::thread> threads;
    const uint32_t share = span / workers;

    for (unsigned index = 0u; index < workers; index += 1u)
    {
        threads.emplace_back(
            [&positions, &tallies, index, share]()
            {
                uint64_t found = 0u;
                for (uint32_t step = 0u; step < share; step += 1u)
                {
                    uint32_t ordered[8];
                    digest_for_nonce((index * share) + step, ordered);

                    bool held = true;
                    for (unsigned position : positions)
                    {
                        // Position zero is the most significant bit of the number the target reads.
                        const uint32_t word = ordered[position / 32u];
                        if (((word >> (31u - (position % 32u))) & 1u) != 0u)
                        {
                            held = false;
                            break;
                        }
                    }
                    found += held ? 1u : 0u;
                }
                tallies[index] = found;
            });
    }
    for (std::thread &thread : threads)
    {
        thread.join();
    }

    uint64_t total = 0u;
    for (uint64_t tally : tallies)
    {
        total += tally;
    }
    return total;
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  The orbit test: do independent anchors multiply?\n");
    std::printf("================================================================\n");
    std::printf("\n  anchor_sift's bench_scaling found the probe bound failing by 4096x on a\n");
    std::printf("  periodic corpus, because every anchor offset cancels and four probes ask one\n");
    std::printf("  question four times. H2 read exactly 4.0 throughout and could not see it.\n");
    std::printf("\n  So H2 = 7.999999 on this domain rules out nothing, and the question has to be\n");
    std::printf("  asked directly. k anchors, each demanding a zero bit. Independent anchors leave\n");
    std::printf("  2^-k survivors. Anchors collapsed onto one orbit leave far more.\n");

    const std::vector<uint8_t> header = bytes_from_hex(HEADER_HEX);
    std::memset(&g_base, 0, sizeof(g_base));
    sha256_header_midstate(&g_base.midstate, header.data());
    g_base.merkle_root_tail = schedule_word_from_header(header.data() + 64u);
    g_base.ntime = schedule_word_from_header(header.data() + 68u);
    g_base.nbits = schedule_word_from_header(header.data() + 72u);

    const uint32_t span = 1u << 24;
    std::mt19937 generator(bench_seed(20260908u));
    const auto started = std::chrono::steady_clock::now();

    const struct
    {
        Placement placement;
        const char *name;
        unsigned ceiling;
    } rules[] = {
        {Placement::Nested, "nested prefix (control, must scale)", 16u},
        {Placement::Scattered, "scattered, independent positions", 16u},
        {Placement::SameWord, "all in one word, different bits", 16u},
        {Placement::SameBit, "same bit index across words", 8u},
    };

    for (const auto &rule : rules)
    {
        std::printf("\n================================================================\n");
        std::printf("  %s\n", rule.name);
        std::printf("================================================================\n");
        std::printf("\n  %8s %16s %16s %12s\n", "anchors", "predicted", "survivors", "ratio");
        std::printf("  %8s %16s %16s %12s\n", "--------", "----------------",
                    "----------------", "------------");

        for (unsigned count = 1u; count <= rule.ceiling; count += (count < 4u) ? 1u : 4u)
        {
            const std::vector<unsigned> positions =
                choose_positions(count, rule.placement, generator);
            const uint64_t survivors = count_survivors(positions, span);
            const double predicted = (double)span * std::pow(0.5, (double)count);

            std::printf("  %8u %16.1f %16llu %12.4f\n", count, predicted,
                        (unsigned long long)survivors,
                        (predicted > 0.0) ? ((double)survivors / predicted) : 0.0);
        }
    }

    const auto finished = std::chrono::steady_clock::now();

    std::printf("\n================================================================\n");
    std::printf("  Reading it\n");
    std::printf("================================================================\n");
    std::printf("\n  A ratio near 1.0 in every row means the anchors are independent and no orbit\n");
    std::printf("  collapse is present at this placement. A ratio far above 1.0 in one placement\n");
    std::printf("  and not the others names the group the orbit sits under, exactly as periodic16\n");
    std::printf("  named translation.\n");
    std::printf("\n  The nested row is the control. It must scale, because k=16 implies k=8 there,\n");
    std::printf("  and it would scale on an orbit too. That is precisely why H1 could not answer\n");
    std::printf("  this question and why the other three rows exist.\n");
    std::printf("\n  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return 0;
}
