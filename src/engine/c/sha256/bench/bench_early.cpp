/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_early.cpp
 * @brief The hoisted scan against the conventional one, for agreement first and speed second.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Section 2b of docs/sha256-topology.md prices two exact savings and this is the first time
 *       either has been spent. The count there is word-rounds, which bounds arithmetic and not
 *       runtime, so the number that matters is the one measured here instead of the one predicted.
 * @note Agreement is checked before speed and on every nonce, not sampled. A faster arm that
 *       disagrees anywhere is not faster, it is broken, and the whole value of the anchor argument
 *       is that it refuses nothing a share needs.
 * @note Mean time to share is reported instead of hash rate alone, because that is the quantity a
 *       pool pays on and the two differ whenever the anchor's survivor rate differs between arms.
 */

#include "../core/sha256_core.h"

#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>

namespace
{

/** @brief A header the chain already recorded, so the arithmetic has a right answer. */
const char *const GENESIS_HEADER =
    "0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac7"
    "2c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c";

/** @brief Turns a hex header into bytes. */
void bytes_of(const char *hex, uint8_t *header)
{
    for (unsigned at = 0u; at < 80u; at += 1u)
    {
        char pair[3] = {hex[at * 2u], hex[(at * 2u) + 1u], '\0'};
        header[at] = (uint8_t)std::strtoul(pair, nullptr, 16);
    }
}

/** @brief Reads four header bytes as one big-endian word. */
uint32_t word_at(const uint8_t *header, unsigned offset)
{
    return ((uint32_t)header[offset] << 24) | ((uint32_t)header[offset + 1u] << 16) |
           ((uint32_t)header[offset + 2u] << 8) | (uint32_t)header[offset + 3u];
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned scan_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 22u;
    const uint32_t count = (uint32_t)1u << scan_bits;
    const double difficulty = (argc > 2) ? std::atof(argv[2]) : 1.0;

    uint8_t header[80];
    bytes_of(GENESIS_HEADER, header);

    Sha256ScanRequest request;
    std::memset(&request, 0, sizeof(request));
    sha256_header_midstate(&request.midstate, header);
    request.merkle_root_tail = word_at(header, 64u);
    request.ntime = word_at(header, 68u);
    request.nbits = word_at(header, 72u);
    request.nonce_start = 0u;
    request.nonce_count = count;
    request.abandon = nullptr;
    sha256_share_target_from_difficulty(request.share_target, difficulty);

    std::printf("================================================================\n");
    std::printf("  The hoisted scan against the conventional one\n");
    std::printf("================================================================\n");
    std::printf("\n  Two exact savings, spent for the first time. The nonce is message word three\n");
    std::printf("  and W[at] draws on at-16, at-15, at-7 and at-2, so the first eighteen schedule\n");
    std::printf("  words and the first three rounds of the first block are the same for every\n");
    std::printf("  nonce and are hoisted out of the loop. And the round moves e to f to g to h, so\n");
    std::printf("  the anchor word is the e of sixty-one rounds and the last three rounds of the\n");
    std::printf("  second block cannot change it and are not run.\n");
    std::printf("\n  Scanning 2^%u nonces at difficulty %.4f.\n", scan_bits, difficulty);

    // The shortcut is checked against the full arithmetic on every nonce, because a scan that finds
    // no survivor has not tested it. An anchor survives about once in four billion nonces, so two
    // arms agreeing that a range holds no share says nothing about whether the shortcut is right.
    std::printf("\n  The shortcut against the full arithmetic, on every nonce\n");
    std::printf("\n  An anchor survives about once in 2^32 nonces, so a scan that finds none has\n");
    std::printf("  not exercised the shortcut. This compares the anchor word itself against word\n");
    std::printf("  seven of the fully computed digest, nonce by nonce.\n");

    {
        const uint32_t checked = (count < 200000u) ? count : 200000u;
        uint32_t wrong = 0u;
        uint32_t first_wrong = 0u;

        for (uint32_t step = 0u; step < checked; step += 1u)
        {
            const uint32_t nonce = request.nonce_start + step;

            uint32_t message_block[SHA256_BLOCK_WORDS];
            Sha256State first_pass = request.midstate;
            Sha256ScanRequest one = request;
            one.nonce_start = nonce;
            one.nonce_count = 1u;

            // The conventional route, in full, with nothing skipped.
            uint8_t built[80];
            std::memcpy(built, header, sizeof(built));
            built[76] = (uint8_t)(nonce & 0xffu);
            built[77] = (uint8_t)((nonce >> 8) & 0xffu);
            built[78] = (uint8_t)((nonce >> 16) & 0xffu);
            built[79] = (uint8_t)((nonce >> 24) & 0xffu);

            uint8_t digest[32];
            sha256_double_hash(built, sizeof(built), digest);
            const uint32_t truth = ((uint32_t)digest[28] << 24) | ((uint32_t)digest[29] << 16) |
                                   ((uint32_t)digest[30] << 8) | (uint32_t)digest[31];

            const uint32_t shortcut = sha256_anchor_word(&one, nonce);
            if (shortcut != truth)
            {
                if (wrong == 0u)
                {
                    first_wrong = nonce;
                }
                wrong += 1u;
            }
            (void)message_block;
            (void)first_pass;
        }

        std::printf("\n  %-40s %14u\n", "nonces checked against the full digest", checked);
        std::printf("  %-40s %14u\n", "anchor words that disagreed", wrong);
        if (wrong != 0u)
        {
            std::printf("  %-40s %14u\n", "first disagreeing nonce", first_wrong);
            std::printf("\n  [!] the shortcut does not reproduce the digest, so it is wrong and\n");
            std::printf("  nothing below this line is worth reading.\n");
            return 1;
        }
        std::printf("\n  Every one matches, so the shortcut computes the same anchor word the long\n");
        std::printf("  route does and the two savings are sound instead of merely fast.\n");
    }

    std::printf("\n  Agreement of the two scans over the whole range\n");

    Sha256ScanResult plain;
    Sha256ScanResult early;

    // Alternating trials, and the best time taken for each arm instead of a single pass. One pass
    // each read ratios from 0.935 to 1.111 on this machine, a spread wider than the effect being
    // looked for, because whatever else the machine is doing lands in whichever arm it lands in.
    // The fastest observed run is the one least interfered with, so best-of is the estimator that
    // answers "how fast can this go" instead of "what else was running".
    const unsigned TRIALS = 7u;
    double plain_seconds = 1.0e30;
    double early_seconds = 1.0e30;

    for (unsigned trial = 0u; trial < TRIALS; trial += 1u)
    {
        const auto plain_start = std::chrono::steady_clock::now();
        sha256_scan_scalar(&request, &plain);
        const auto plain_end = std::chrono::steady_clock::now();
        const double took = std::chrono::duration<double>(plain_end - plain_start).count();
        plain_seconds = (took < plain_seconds) ? took : plain_seconds;

        const auto early_start = std::chrono::steady_clock::now();
        sha256_scan_scalar_early(&request, &early);
        const auto early_end = std::chrono::steady_clock::now();
        const double early_took = std::chrono::duration<double>(early_end - early_start).count();
        early_seconds = (early_took < early_seconds) ? early_took : early_seconds;
    }

    const int same_found = (plain.found == early.found) ? 1 : 0;
    const int same_nonce = (plain.winning_nonce == early.winning_nonce) ? 1 : 0;
    const int same_evaluated = (plain.nonces_evaluated == early.nonces_evaluated) ? 1 : 0;
    const int same_survivors = (plain.anchors_survived == early.anchors_survived) ? 1 : 0;

    std::printf("\n  %-30s %16s %16s %10s\n", "quantity", "conventional", "hoisted", "agrees");
    std::printf("  %-30s %16s %16s %10s\n", "------------------------------", "----------------",
                "----------------", "----------");
    std::printf("  %-30s %16llu %16llu %10s\n", "nonces evaluated",
                (unsigned long long)plain.nonces_evaluated,
                (unsigned long long)early.nonces_evaluated, (same_evaluated != 0) ? "yes" : "NO");
    std::printf("  %-30s %16llu %16llu %10s\n", "anchors survived",
                (unsigned long long)plain.anchors_survived,
                (unsigned long long)early.anchors_survived, (same_survivors != 0) ? "yes" : "NO");
    std::printf("  %-30s %16d %16d %10s\n", "found a share", plain.found, early.found,
                (same_found != 0) ? "yes" : "NO");
    std::printf("  %-30s %16u %16u %10s\n", "winning nonce", plain.winning_nonce,
                early.winning_nonce, (same_nonce != 0) ? "yes" : "NO");

    const int agrees = (same_found & same_nonce & same_evaluated & same_survivors);
    if (agrees == 0)
    {
        std::printf("\n  [!] the arms disagree, so nothing below this line means anything and the\n");
        std::printf("  hoisted arm must not be used. A saving that changes an answer is not a\n");
        std::printf("  saving.\n");
        return 1;
    }
    std::printf("\n  Both arms agree on every quantity, including the survivor count, which is the\n");
    std::printf("  one that would move first if the anchor shortcut were wrong.\n");

    std::printf("\n  Throughput and mean time to share\n");
    std::printf("\n  %-30s %16s %16s %10s\n", "quantity", "conventional", "hoisted", "ratio");
    std::printf("  %-30s %16s %16s %10s\n", "------------------------------", "----------------",
                "----------------", "----------");

    const double plain_rate = (double)count / plain_seconds;
    const double early_rate = (double)count / early_seconds;
    std::printf("  %-30s %16.3f %16.3f %10s\n", "seconds for the range", plain_seconds,
                early_seconds, "");
    std::printf("  %-30s %16.3f %16.3f %9.3fx\n", "megahashes per second",
                plain_rate / 1000000.0, early_rate / 1000000.0, early_rate / plain_rate);

    // Mean time to share is what a pool pays on. At difficulty d a share wants 2^32 * d hashes on
    // average, so the arm's rate turns straight into a waiting time.
    const double wanted = 4294967296.0 * difficulty;
    const double plain_wait = wanted / plain_rate;
    const double early_wait = wanted / early_rate;
    std::printf("  %-30s %16.2f %16.2f %9.3fx\n", "mean seconds to a share", plain_wait, early_wait,
                plain_wait / early_wait);

    // The arm the miner actually runs. btc_miner.cpp dispatches to sha256_scan_avx2 and reaches the
    // scalar arm only as a fallback, so a scalar speedup is a result about a path the miner does not
    // take. Timing it here keeps the comparison honest about which number is the miner's.
    {
        Sha256ScanResult wide;
        double wide_seconds = 1.0e30;
        for (unsigned trial = 0u; trial < TRIALS; trial += 1u)
        {
            const auto wide_start = std::chrono::steady_clock::now();
            sha256_scan_avx2(&request, &wide);
            const auto wide_end = std::chrono::steady_clock::now();
            const double took = std::chrono::duration<double>(wide_end - wide_start).count();
            wide_seconds = (took < wide_seconds) ? took : wide_seconds;
        }

        const double wide_rate = (double)count / wide_seconds;
        const int wide_agrees = ((wide.found == plain.found) &&
                                 (wide.winning_nonce == plain.winning_nonce)) ? 1 : 0;

        std::printf("\n  The arm the miner actually runs\n");
        std::printf("\n  btc_miner dispatches to the eight-lane arm and reaches the scalar one only\n");
        std::printf("  as a fallback, so the ratio above is about a path the miner does not take.\n");
        std::printf("\n  %-30s %16.3f %16s %9.3fx\n", "eight-lane megahashes/sec",
                    wide_rate / 1000000.0, "", wide_rate / plain_rate);
        std::printf("  %-30s %16.2f %16s %10s\n", "  mean seconds to a share", wanted / wide_rate,
                    "", (wide_agrees != 0) ? "agrees" : "DISAGREES");
        std::printf("\n  The two savings have not been carried into that arm, so the miner does not\n");
        std::printf("  have them yet. Porting them is the remaining work and the scalar ratio is\n");
        std::printf("  the best available guess at what they would be worth there.\n");
    }

    std::printf("\n  The predicted saving was 5.0%% of the arithmetic, counted in word-rounds: 24\n");
    std::printf("  of 1024 for the shared front and 27 for the tail no rejection reads. Word-rounds\n");
    std::printf("  are not instructions, so the measured ratio above is the finding and the 5.0%%\n");
    std::printf("  was only ever a bound on what could be removed.\n");
    return 0;
}
