/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_chainmap.cpp
 * @brief The chain as an iterated map. Long-range structure across blocks, not inside one header.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Every measurement in this tree so far lived inside a single header's nonce space. The chain
 *       is a different object: block N's hash is literally a field of block N+1's header, so the
 *       sequence of block hashes is an iterated map h(n+1) = F(h(n), rest(n)). Iterated maps have
 *       orbits, recurrences and periods, and none of that has been looked for here.
 * @note One structural fact is certain before any measurement and should be stated first, because it
 *       changes what "uniform" means. A block hash is not a uniform 256-bit value. It is a value
 *       conditioned on being at or below the target, so roughly the top 76 bits are forced to zero
 *       and only the remainder is free. Any test that ignores that will find structure across most
 *       of the digest width that is entirely the conditioning.
 * @note So the tests below run on the free bits only, which is the part that could carry something.
 *       Four questions: do consecutive block hashes correlate; is the excess beyond the target
 *       geometric as an unstructured source requires; do the nonces that solved consecutive blocks
 *       correlate; and does the sequence carry any period, which is the "longer patterns even if
 *       repeating" claim stated so it can fail.
 */

#include "json_value.h"
#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace
{

int g_checks_run = 0;
int g_checks_failed = 0;

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

/** @brief One block as the corpus records it, oldest first after sorting. */
struct ChainBlock
{
    uint32_t height;
    uint64_t free_bits;   /**< The low 64 bits of the hash, which the target does not constrain. */
    unsigned leading;     /**< Leading zero bits of the hash. */
    uint32_t nonce;
    uint32_t timestamp;
    uint32_t version;
    uint32_t nbits;
};

/**
 * @brief Reads the corpus and extracts the parts a chain test needs.
 *
 * @param[in]  path   Where the corpus is.
 * @param[out] blocks Where the blocks land, oldest first [BORROWS].
 * @return            True where the file parsed.
 */
bool load_chain(const std::string &path, std::vector<ChainBlock> &blocks)
{
    std::ifstream file(path);
    if (!file.is_open())
    {
        return false;
    }
    std::stringstream buffer;
    buffer << file.rdbuf();

    JsonValue document;
    if (!json_parse(buffer.str(), document) || (document.kind != JsonKind::Array))
    {
        return false;
    }

    for (const JsonValue &entry : document.elements)
    {
        const std::string identifier = entry.member("id").text;
        if (identifier.size() != 64u)
        {
            continue;
        }

        ChainBlock block;
        block.height = (uint32_t)entry.member("height").number;
        block.nonce = (uint32_t)entry.member("nonce").number;
        block.timestamp = (uint32_t)entry.member("timestamp").number;
        block.version = (uint32_t)entry.member("version").number;
        block.nbits = (uint32_t)entry.member("bits").number;

        // The explorer prints the hash most significant first, so leading zeros are leading
        // characters and the free bits are the trailing ones.
        unsigned zeros = 0u;
        while ((zeros < 64u) && (identifier[zeros] == '0'))
        {
            zeros += 1u;
        }
        block.leading = zeros * 4u;
        block.free_bits = std::stoull(identifier.substr(48u, 16u), nullptr, 16);
        blocks.push_back(block);
    }

    std::sort(blocks.begin(), blocks.end(),
              [](const ChainBlock &left, const ChainBlock &right)
              { return left.height < right.height; });
    return !blocks.empty();
}

/**
 * @brief Correlation of the free bits between blocks separated by a lag.
 *
 * @param[in] blocks The chain, oldest first [BORROWS].
 */
void measure_chain_autocorrelation(const std::vector<ChainBlock> &blocks)
{
    std::printf("\n================================================================\n");
    std::printf("  1. Do consecutive block hashes agree beyond chance?\n");
    std::printf("================================================================\n");
    std::printf("\n  Bit agreement between the free 64 bits of block n and block n+lag. Under an\n");
    std::printf("  unstructured chain this is 0.5. Block n's hash is an input field of block n+1,\n");
    std::printf("  so if that dependence leaves any trace it should show at lag 1 first.\n");

    std::printf("\n  %8s %16s %12s\n", "lag", "bit agreement", "z");
    std::printf("  %8s %16s %12s\n", "--------", "----------------", "------------");

    double worst = 0.0;
    unsigned worst_lag = 0u;

    for (unsigned lag : {1u, 2u, 3u, 5u, 8u, 13u, 21u, 34u, 55u, 89u, 144u, 233u})
    {
        if (lag >= blocks.size())
        {
            continue;
        }
        uint64_t agreeing = 0u;
        const size_t pairs = blocks.size() - lag;

        for (size_t at = 0u; at < pairs; at += 1u)
        {
            const uint64_t difference = blocks[at].free_bits ^ blocks[at + lag].free_bits;
            agreeing += (uint64_t)(64 - __builtin_popcountll(difference));
        }

        const double total_bits = (double)pairs * 64.0;
        const double agreement = (double)agreeing / total_bits;
        const double score = (agreement - 0.5) / (0.5 / std::sqrt(total_bits));

        if (std::fabs(score) > std::fabs(worst))
        {
            worst = score;
            worst_lag = lag;
        }
        std::printf("  %8u %16.8f %+12.2f\n", lag, agreement, score);
    }

    std::printf("\n  largest departure: lag %u at %+.2f sigma over %zu lags tested\n", worst_lag,
                worst, 12u);
    check("no lag shows agreement beyond chance", std::fabs(worst) < 4.0);
}

/**
 * @brief The excess beyond the target, which an unstructured source makes geometric.
 *
 * @param[in] blocks The chain [BORROWS].
 */
void measure_excess_zeros(const std::vector<ChainBlock> &blocks)
{
    std::printf("\n================================================================\n");
    std::printf("  2. Is the excess beyond the target geometric?\n");
    std::printf("================================================================\n");
    std::printf("\n  A block only needs to clear the target. How far it overshoots is free, and an\n");
    std::printf("  unstructured source overshoots geometrically: half the blocks by 0 extra bits,\n");
    std::printf("  a quarter by 1, an eighth by 2. Any other shape would be a finding.\n");

    // The target is not at a nibble boundary and pretending it is produces a spectacular fake
    // finding. nbits 0x1702355e gives a target near 2^177.14, so the probability of clearing 80
    // leading zero bits is 2^176 / 2^177.14 = 0.454, not one in sixteen. An earlier version of
    // this section used the nibble model, predicted 58.6 blocks where 426 appeared, and reported a
    // 7.27x excess. That excess was entirely the boundary.
    std::printf("\n  The target is not at a nibble boundary, so the overshoot is not geometric in\n");
    std::printf("  nibbles. Each block's own nbits gives its own target, and the probability of\n");
    std::printf("  clearing k leading zero bits is 2^(256-k) over that target, capped at one.\n");

    unsigned lowest = 256u;
    for (const ChainBlock &block : blocks)
    {
        lowest = std::min(lowest, block.leading);
    }

    std::printf("\n  %10s %12s %14s %10s\n", "zero bits", "blocks", "predicted", "ratio");
    std::printf("  %10s %12s %14s %10s\n", "----------", "------------", "--------------",
                "----------");

    double chi_square = 0.0;
    unsigned cells = 0u;

    for (unsigned bits = lowest; bits <= (lowest + 8u); bits += 4u)
    {
        unsigned measured = 0u;
        double predicted = 0.0;

        for (const ChainBlock &block : blocks)
        {
            if (block.leading >= bits)
            {
                measured += 1u;
            }

            // Expand the block's own target and read its position as a power of two, so the
            // probability accounts for where the threshold actually sits.
            uint32_t target[SHA256_STATE_WORDS];
            sha256_target_from_nbits(target, block.nbits);

            double target_log2 = 0.0;
            for (unsigned rank = 0u; rank < SHA256_STATE_WORDS; rank += 1u)
            {
                if (target[rank] != 0u)
                {
                    const unsigned high = 31u - (unsigned)__builtin_clz(target[rank]);
                    target_log2 = (double)((7u - rank) * 32u + high) +
                                  std::log2(1.0 + ((double)(target[rank] & ((1u << high) - 1u)) /
                                                   (double)(1u << high)));
                    break;
                }
            }

            const double clears = std::pow(2.0, (double)(256u - bits) - target_log2);
            predicted += (clears > 1.0) ? 1.0 : clears;
        }

        if (predicted >= 5.0)
        {
            chi_square += (((double)measured - predicted) * ((double)measured - predicted)) /
                          predicted;
            cells += 1u;
        }
        std::printf("  %10u %12u %14.1f %10.4f\n", bits, measured, predicted,
                    (predicted > 0.0) ? ((double)measured / predicted) : 0.0);
    }

    check("the overshoot matches uniform-below-target",
          (cells == 0u) || (chi_square < (double)cells * 8.0),
          "chi-square " + std::to_string(chi_square) + " on " + std::to_string(cells) + " cells");
}

/**
 * @brief Whether the nonces that solved consecutive blocks carry any relation.
 *
 * @param[in] blocks The chain [BORROWS].
 */
void measure_nonce_sequence(const std::vector<ChainBlock> &blocks)
{
    std::printf("\n================================================================\n");
    std::printf("  3. Do the nonces that solved consecutive blocks relate?\n");
    std::printf("================================================================\n");
    std::printf("\n  These are the answers other people's hardware found, in chain order. If the\n");
    std::printf("  search space carried a preferred direction, consecutive answers would drift\n");
    std::printf("  instead of scatter.\n");

    double sum_left = 0.0;
    double sum_right = 0.0;
    double sum_left_squared = 0.0;
    double sum_right_squared = 0.0;
    double sum_product = 0.0;
    const size_t pairs = blocks.size() - 1u;

    for (size_t at = 0u; at < pairs; at += 1u)
    {
        const double left = (double)blocks[at].nonce / 4294967296.0;
        const double right = (double)blocks[at + 1u].nonce / 4294967296.0;

        sum_left += left;
        sum_right += right;
        sum_left_squared += left * left;
        sum_right_squared += right * right;
        sum_product += left * right;
    }

    const double count = (double)pairs;
    const double covariance = (sum_product / count) - ((sum_left / count) * (sum_right / count));
    const double spread_left =
        std::sqrt((sum_left_squared / count) - ((sum_left / count) * (sum_left / count)));
    const double spread_right =
        std::sqrt((sum_right_squared / count) - ((sum_right / count) * (sum_right / count)));
    const double correlation = covariance / (spread_left * spread_right);

    std::printf("\n  consecutive nonce correlation : %+.6f\n", correlation);
    std::printf("  in standard errors            : %+.2f over %zu pairs\n",
                correlation * std::sqrt(count), pairs);
    check("consecutive winning nonces are uncorrelated",
          std::fabs(correlation * std::sqrt(count)) < 4.0);
}

/**
 * @brief The period search: longer patterns, even if repeating.
 *
 * @param[in] blocks The chain [BORROWS].
 * @note This is the claim stated so it can fail. A repeating pattern of any length up to half the
 *       corpus would show as a peak in the power spectrum of the sequence.
 */
void measure_chain_period(const std::vector<ChainBlock> &blocks)
{
    std::printf("\n================================================================\n");
    std::printf("  4. Longer patterns, even if repeating\n");
    std::printf("================================================================\n");
    std::printf("\n  Power spectrum of the free-bit sequence across %zu blocks. A repeat at any\n",
                blocks.size());
    std::printf("  period would stand up as a peak. Under no structure the spectrum is flat and\n");
    std::printf("  the largest peak of N/2 bins lands near 2*ln(N/2) times the mean.\n");

    // Map each block to a centred value so the constant bin does not dominate.
    std::vector<double> series;
    series.reserve(blocks.size());
    for (const ChainBlock &block : blocks)
    {
        series.push_back(((double)(block.free_bits >> 32) / 4294967296.0) - 0.5);
    }

    const size_t length = series.size();
    const size_t bins = length / 2u;
    double total_power = 0.0;
    double peak_power = 0.0;
    size_t peak_bin = 0u;

    for (size_t bin = 1u; bin < bins; bin += 1u)
    {
        std::complex<double> sum(0.0, 0.0);
        for (size_t at = 0u; at < length; at += 1u)
        {
            const double angle =
                -2.0 * 3.14159265358979323846 * (double)bin * (double)at / (double)length;
            sum += series[at] * std::complex<double>(std::cos(angle), std::sin(angle));
        }
        const double power = std::norm(sum);
        total_power += power;
        if (power > peak_power)
        {
            peak_power = power;
            peak_bin = bin;
        }
    }

    const double mean_power = total_power / (double)(bins - 1u);
    const double ratio = (mean_power > 0.0) ? (peak_power / mean_power) : 0.0;
    const double expected_peak = 2.0 * std::log((double)bins);

    std::printf("\n  strongest bin       : %zu, which is a period of %.1f blocks\n", peak_bin,
                (peak_bin > 0u) ? ((double)length / (double)peak_bin) : 0.0);
    std::printf("  its power over mean : %.3f\n", ratio);
    std::printf("  expected largest    : %.3f under no structure\n", expected_peak);
    check("no period stands above what chance produces over this many bins",
          ratio < (expected_peak * 1.5),
          "peak/mean " + std::to_string(ratio) + " against expected " +
              std::to_string(expected_peak));
}

} // namespace

int main(int argument_count, char **arguments)
{
    const std::string path = (argument_count > 1) ? arguments[1] : "../../maint/chain/blocks.json";

    std::printf("================================================================\n");
    std::printf("  The chain as an iterated map\n");
    std::printf("================================================================\n");

    std::vector<ChainBlock> blocks;
    if (!load_chain(path, blocks))
    {
        std::printf("\nCould not read %s. Run maint/chain/fetch_blocks.py first.\n", path.c_str());
        return 1;
    }
    std::printf("\n  %zu blocks, heights %u to %u\n", blocks.size(), blocks.front().height,
                blocks.back().height);
    std::printf("\n  Stated before any measurement: a block hash is not a uniform 256-bit value.\n");
    std::printf("  It is conditioned on clearing the target, so its top bits are forced to zero\n");
    std::printf("  and only the remainder is free. Every test below uses the free bits, because a\n");
    std::printf("  test on the whole hash would find enormous structure that is entirely the\n");
    std::printf("  conditioning and nothing to do with the chain.\n");

    measure_chain_autocorrelation(blocks);
    measure_excess_zeros(blocks);
    measure_nonce_sequence(blocks);
    measure_chain_period(blocks);

    std::printf("\n================================================================\n");
    std::printf("  %d checks run, %d failed\n", g_checks_run, g_checks_failed);
    std::printf("================================================================\n");
    return (g_checks_failed == 0) ? 0 : 1;
}
