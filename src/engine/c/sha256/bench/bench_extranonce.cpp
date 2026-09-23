/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_extranonce.cpp
 * @brief The extranonce2 dimension, which the workbook had flagged as claimed but never measured.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note H13 measured the nonce dimension only. Saying the extranonce2 dimension "should" behave the
 *       same is not a measurement, and the workbook said so. This file measures it.
 * @note The path is longer here and that is the point. extranonce2 sits inside the coinbase
 *       transaction, so moving it changes the coinbase double hash, then every merkle fold above it,
 *       then the merkle root, which lands across header bytes 36 to 67 and therefore moves both the
 *       midstate and W[0]. A step in this dimension costs far more than a nonce step and passes
 *       through strictly more mixing.
 * @note The job below is a real mining.notify captured from solo.ckpool.org, kept verbatim so the
 *       coinbase layout and the branch length are the ones a pool actually sends.
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

/** @brief A real job captured from solo.ckpool.org, kept exactly as it arrived. */
const char *const JOB_PREVHASH =
    "93ecd4d9238cf6d3bed217dfbbac02b29d3a25df0001ae4c0000000000000000";
const char *const JOB_COINBASE_HEAD =
    "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff3703ddbd0e"
    "0004b16da06a04d6b33e010c";
const char *const JOB_COINBASE_TAIL =
    "0a636b706f6f6c1375772f736f6c6f2e636b706f6f6c2e6f72672ffffffffe03b23d751200000000160014311564"
    "348890e005880a9bc834aaa5884f1b5932f96e60000000000016001451ed61d2f6aa260cc72cdf743e4e436a82c0"
    "10270000000000000000266a24aa21a9ede45edd24d65fd099839aa3c5b85f4f918edad43a1d624ab0d63bdcd42b"
    "9b209bdcbd0e00";
const char *const JOB_EXTRANONCE1 = "57fa1271";
const size_t JOB_EXTRANONCE2_BYTES = 8u;
const char *const JOB_VERSION = "20000000";
const char *const JOB_NBITS = "1702355e";
const char *const JOB_NTIME = "6aa06db1";

/** @brief The twelve merkle branch entries that job carried. */
const char *const JOB_MERKLE_BRANCH[] = {
    "c65dcc9396aac4afb85768b8664efea0c991eca2f460b23e61957f0529e69380",
    "e1eb803a0ae281ae5b99d6e387e360e0988a9e0197fc5fb2831aba85f34ec548",
    "4a5ab4fcf2c4ecac0347dc90b3841a56a87b667603d3013934dcec7d46c6fef5",
    "f1753595ef4233d4e574b6f9f830632c39b0bdf1c1100055a0c18dabacdf736a",
    "7399072c5bb671793fc1486d1821d3bed31cefe788fbc971fa9d050bf7e4dbca",
    "9067f4f5f922ffc2c709b9421e6c1a9f7027fad047872e6d371c963697a39680",
    "5f0427ca6431e1404daf8cdbb60d73621b3bc02f778e60f7a634cc905513468d",
    "91ad93d05608f6a499b89da4cbb49c522871b5abb3b4a54edc8cbb9895230e10",
    "ba29b13e83873ca2f401d0734ed47a5cadf069517887150911a80a94f88868c8",
    "6f72d0df69848416c0a2b14fd09e478b80559099b756315bcf9ac4df116ca42c",
    "1a9d605cf92cca60fedfc342c7548cbd29a36cb831869c5bd7257d3b8d3305f6",
    "a989f99005a9d16040d75c1c5faab0c69fd47618f5e7d715213a173b04319a8b"};
const size_t JOB_BRANCH_COUNT = sizeof(JOB_MERKLE_BRANCH) / sizeof(JOB_MERKLE_BRANCH[0]);

uint64_t g_coinbase_hashes = 0u;

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

std::vector<uint8_t> g_coinbase_head;
std::vector<uint8_t> g_coinbase_tail;
std::vector<uint8_t> g_extranonce1;
std::vector<uint8_t> g_prevhash;
std::vector<std::vector<uint8_t>> g_branch;
uint32_t g_version = 0u;
uint32_t g_nbits = 0u;
uint32_t g_ntime = 0u;

/**
 * @brief Builds the eighty header bytes for one extranonce2 and one nonce.
 *
 * @param[in]  extranonce2 The extranonce2 value, widened to the pool's byte count.
 * @param[in]  nonce       The nonce to place.
 * @param[out] header      Eighty bytes to fill [BORROWS].
 * @note This is the whole path the workbook said was unmeasured: coinbase, double hash, twelve
 *       merkle folds, then the header. Each call costs 1 + 12 double hashes before any mining
 *       happens, which is counted so the cost of a step in this dimension is on the record.
 */
void build_header(uint64_t extranonce2, uint32_t nonce, uint8_t *header)
{
    std::vector<uint8_t> coinbase;

    coinbase.insert(coinbase.end(), g_coinbase_head.begin(), g_coinbase_head.end());
    coinbase.insert(coinbase.end(), g_extranonce1.begin(), g_extranonce1.end());
    for (size_t byte = 0u; byte < JOB_EXTRANONCE2_BYTES; byte += 1u)
    {
        // Big-endian, matching how the client renders its counter into the field.
        const unsigned shift = (unsigned)((JOB_EXTRANONCE2_BYTES - 1u - byte) * 8u);
        coinbase.push_back((uint8_t)((shift < 64u) ? (extranonce2 >> shift) : 0u));
    }
    coinbase.insert(coinbase.end(), g_coinbase_tail.begin(), g_coinbase_tail.end());

    uint8_t merkle_root[32];
    sha256_double_hash(coinbase.data(), coinbase.size(), merkle_root);
    g_coinbase_hashes += 1u;

    for (const std::vector<uint8_t> &entry : g_branch)
    {
        uint8_t joined[64];
        std::memcpy(joined, merkle_root, 32u);
        std::memcpy(joined + 32u, entry.data(), 32u);
        sha256_double_hash(joined, sizeof(joined), merkle_root);
        g_coinbase_hashes += 1u;
    }

    header[0] = (uint8_t)g_version;
    header[1] = (uint8_t)(g_version >> 8);
    header[2] = (uint8_t)(g_version >> 16);
    header[3] = (uint8_t)(g_version >> 24);
    for (size_t word = 0u; word < 8u; word += 1u)
    {
        for (size_t byte = 0u; byte < 4u; byte += 1u)
        {
            header[4u + (word * 4u) + byte] = g_prevhash[(word * 4u) + (3u - byte)];
        }
    }
    std::memcpy(header + 36u, merkle_root, 32u);
    header[68] = (uint8_t)g_ntime;
    header[69] = (uint8_t)(g_ntime >> 8);
    header[70] = (uint8_t)(g_ntime >> 16);
    header[71] = (uint8_t)(g_ntime >> 24);
    header[72] = (uint8_t)g_nbits;
    header[73] = (uint8_t)(g_nbits >> 8);
    header[74] = (uint8_t)(g_nbits >> 16);
    header[75] = (uint8_t)(g_nbits >> 24);
    header[76] = (uint8_t)nonce;
    header[77] = (uint8_t)(nonce >> 8);
    header[78] = (uint8_t)(nonce >> 16);
    header[79] = (uint8_t)(nonce >> 24);
}

/**
 * @brief Scores a candidate by leading zero bits of its doubled digest.
 *
 * @param[in] extranonce2 The extranonce2 value.
 * @param[in] nonce       The nonce.
 * @return                Leading zero bits, zero through 256.
 */
unsigned fitness(uint64_t extranonce2, uint32_t nonce)
{
    uint8_t header[BITCOIN_HEADER_BYTES];
    uint8_t digest[32];

    build_header(extranonce2, nonce, header);
    sha256_double_hash(header, BITCOIN_HEADER_BYTES, digest);

    unsigned leading = 0u;
    for (int byte = 31; byte >= 0; byte -= 1)
    {
        // The protocol reads the digest little-endian, so the last byte is the most significant.
        if (digest[byte] != 0u)
        {
            for (int bit = 7; bit >= 0; bit -= 1)
            {
                if (((digest[byte] >> bit) & 1u) != 0u)
                {
                    return leading + (unsigned)(7 - bit);
                }
            }
        }
        leading += 8u;
    }
    return leading;
}

/**
 * @brief Confirms the extranonce2 path is live before anything is concluded from it.
 */
void check_path_is_live()
{
    std::printf("\n================================================================\n");
    std::printf("  0. Control. Does moving extranonce2 actually move the header?\n");
    std::printf("================================================================\n");

    uint8_t header_one[BITCOIN_HEADER_BYTES];
    uint8_t header_two[BITCOIN_HEADER_BYTES];

    build_header(0u, 0u, header_one);
    build_header(1u, 0u, header_two);

    const bool root_moved = (std::memcmp(header_one + 36u, header_two + 36u, 32u) != 0);
    const bool rest_held = (std::memcmp(header_one, header_two, 36u) == 0) &&
                           (std::memcmp(header_one + 68u, header_two + 68u, 12u) == 0);

    check("extranonce2 moves the merkle root", root_moved);
    check("and moves nothing else in the header", rest_held);

    // The midstate covers header bytes 0-63, which includes 28 bytes of the merkle root, so it has
    // to move too. That is what makes this dimension more expensive than the nonce.
    Sha256State midstate_one;
    Sha256State midstate_two;
    sha256_header_midstate(&midstate_one, header_one);
    sha256_header_midstate(&midstate_two, header_two);
    check("and therefore moves the midstate",
          std::memcmp(midstate_one.word, midstate_two.word, sizeof(midstate_one.word)) != 0);

    std::printf("\n  So a step in this dimension is real and it is expensive: one coinbase double\n");
    std::printf("  hash plus %zu merkle folds, then the midstate is invalid and must be rebuilt.\n",
                JOB_BRANCH_COUNT);
}

/**
 * @brief Measures whether the extranonce2 dimension carries a landscape.
 */
void measure_extranonce_landscape()
{
    std::printf("\n================================================================\n");
    std::printf("  1. Does the extranonce2 dimension have neighbourhoods?\n");
    std::printf("================================================================\n");
    std::printf("\n  The same test H13 ran on the nonce, run here. Pearson correlation between\n");
    std::printf("  f(current) and f(neighbor) over 40000 pairs.\n");
    std::printf("\n  %-34s %14s %12s\n", "step", "correlation", "z");
    std::printf("  %-34s %14s %12s\n", "----------------------------------", "--------------",
                "------------");

    std::mt19937_64 generator(20260908u);
    const unsigned pairs = 40000u;

    for (int mode = 0; mode < 4; mode += 1)
    {
        double sum_here = 0.0;
        double sum_there = 0.0;
        double sum_here_squared = 0.0;
        double sum_there_squared = 0.0;
        double sum_product = 0.0;

        for (unsigned trial = 0u; trial < pairs; trial += 1u)
        {
            const uint64_t here = generator();
            uint64_t there = here;

            if (mode == 0)
            {
                there = here + 1u;
            }
            else if (mode == 1)
            {
                there = here ^ (1ull << (generator() % 64u));
            }
            else if (mode == 2)
            {
                there = here ^ 0xFFFFFFFFFFFFFFFFull;
            }
            else
            {
                there = generator();
            }

            const double left = (double)fitness(here, 0u);
            const double right = (double)fitness(there, 0u);

            sum_here += left;
            sum_there += right;
            sum_here_squared += left * left;
            sum_there_squared += right * right;
            sum_product += left * right;
        }

        const double count = (double)pairs;
        const double covariance = (sum_product / count) - ((sum_here / count) * (sum_there / count));
        const double spread_here =
            std::sqrt((sum_here_squared / count) - ((sum_here / count) * (sum_here / count)));
        const double spread_there =
            std::sqrt((sum_there_squared / count) - ((sum_there / count) * (sum_there / count)));
        const double correlation = covariance / (spread_here * spread_there);

        const char *name = (mode == 0)   ? "extranonce2 + 1"
                           : (mode == 1) ? "flip one extranonce2 bit"
                           : (mode == 2) ? "complement every bit"
                                         : "unrelated extranonce2 (control)";
        std::printf("  %-34s %14.6f %+12.2f\n", name, correlation, correlation * std::sqrt(count));
    }

    std::printf("\n  A row above the control would be a neighbourhood in a dimension the nonce\n");
    std::printf("  tests never reached.\n");
}

/**
 * @brief Compares the two dimensions on cost, which decides which one a search should spend on.
 */
void compare_dimension_cost()
{
    std::printf("\n================================================================\n");
    std::printf("  2. What a step costs in each dimension\n");
    std::printf("================================================================\n");

    const unsigned samples = 20000u;

    g_coinbase_hashes = 0u;
    auto started = std::chrono::steady_clock::now();
    for (unsigned trial = 0u; trial < samples; trial += 1u)
    {
        (void)fitness((uint64_t)trial, 0u);
    }
    auto finished = std::chrono::steady_clock::now();
    const double extranonce_seconds = std::chrono::duration<double>(finished - started).count();
    const uint64_t extranonce_side_hashes = g_coinbase_hashes;

    // The nonce arm has to use the path a miner actually uses, which is the whole point of the
    // comparison. Calling fitness() here would rebuild the coinbase and every merkle fold for a
    // nonce step, which no miner does, and would report the two dimensions as equally expensive.
    uint8_t header[BITCOIN_HEADER_BYTES];
    build_header(0u, 0u, header);

    Sha256ScanRequest request;
    std::memset(&request, 0, sizeof(request));
    sha256_header_midstate(&request.midstate, header);
    request.merkle_root_tail = ((uint32_t)header[64] << 24) | ((uint32_t)header[65] << 16) |
                               ((uint32_t)header[66] << 8) | (uint32_t)header[67];
    request.ntime = ((uint32_t)header[68] << 24) | ((uint32_t)header[69] << 16) |
                    ((uint32_t)header[70] << 8) | (uint32_t)header[71];
    request.nbits = ((uint32_t)header[72] << 24) | ((uint32_t)header[73] << 16) |
                    ((uint32_t)header[74] << 8) | (uint32_t)header[75];
    std::memset(request.share_target, 0, sizeof(request.share_target));

    started = std::chrono::steady_clock::now();
    request.nonce_start = 0u;
    request.nonce_count = samples;
    Sha256ScanResult scan_result;
    sha256_scan_scalar(&request, &scan_result);
    finished = std::chrono::steady_clock::now();
    const double nonce_seconds = std::chrono::duration<double>(finished - started).count();

    std::printf("\n  %-40s %16s\n", "dimension", "candidates/s");
    std::printf("  %-40s %16s\n", "----------------------------------------", "----------------");
    std::printf("  %-40s %16.0f\n", "nonce, midstate reused",
                (nonce_seconds > 0.0) ? ((double)samples / nonce_seconds) : 0.0);
    std::printf("  %-40s %16.0f\n", "extranonce2, coinbase and merkle rebuilt",
                (extranonce_seconds > 0.0) ? ((double)samples / extranonce_seconds) : 0.0);
    std::printf("\n  extranonce2 costs %.1fx a nonce step, and spends %llu extra double hashes\n",
                (nonce_seconds > 0.0) ? (extranonce_seconds / nonce_seconds) : 0.0,
                (unsigned long long)(extranonce_side_hashes / samples));
    std::printf("  per candidate on the coinbase and merkle path alone.\n");
    std::printf("\n  So even if this dimension carried a landscape, a search would want to spend\n");
    std::printf("  its budget on the cheap dimension unless the landscape paid for the cost.\n");
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  The extranonce2 dimension\n");
    std::printf("  Measuring what the workbook had only asserted\n");
    std::printf("================================================================\n");

    g_coinbase_head = bytes_from_hex(JOB_COINBASE_HEAD);
    g_coinbase_tail = bytes_from_hex(JOB_COINBASE_TAIL);
    g_extranonce1 = bytes_from_hex(JOB_EXTRANONCE1);
    g_prevhash = bytes_from_hex(JOB_PREVHASH);
    for (size_t at = 0u; at < JOB_BRANCH_COUNT; at += 1u)
    {
        g_branch.push_back(bytes_from_hex(JOB_MERKLE_BRANCH[at]));
    }
    g_version = (uint32_t)std::stoul(JOB_VERSION, nullptr, 16);
    g_nbits = (uint32_t)std::stoul(JOB_NBITS, nullptr, 16);
    g_ntime = (uint32_t)std::stoul(JOB_NTIME, nullptr, 16);

    const auto started = std::chrono::steady_clock::now();

    check_path_is_live();
    measure_extranonce_landscape();
    compare_dimension_cost();

    const auto finished = std::chrono::steady_clock::now();
    std::printf("\n================================================================\n");
    std::printf("  %d checks run, %d failed\n", g_checks_run, g_checks_failed);
    std::printf("  elapsed %.1f s\n", std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return (g_checks_failed == 0) ? 0 : 1;
}
