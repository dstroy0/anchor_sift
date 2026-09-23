/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_corpus.cpp
 * @brief The digest domain treated as a corpus and measured the way anchor-sift.md measures one.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note anchor-sift.md examined thirteen geometries and predicted candidate counts from collision
 *       entropy. This adds a fourteenth: the SHA-256 digest indexed by nonce. The questions are the
 *       ones section 2.5, section 4.7 and section 4.11 ask, applied here.
 * @note Four hypotheses are tested, each stated so it can fail:
 *         1. Corpus size. Survivors at a k-bit anchor should track N times two to the minus k.
 *         2. Entropy eddies. Some bit or byte position should carry a distribution away from flat.
 *         3. A repeating curve. Rotations are periodic, so some nonce lag should show digests
 *            agreeing more often than chance.
 *         4. Hitting time. First success should be geometric with mean one over q, by Kac's lemma.
 * @note Where a hypothesis is not supported, the result is reported as a bound at the sample size
 *       reached, never as proof of absence. An eddy smaller than the noise floor here would not have
 *       been seen, and the floor is printed alongside every verdict.
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

/** @brief Block 125552, used so the header under test is one anyone can reproduce. */
const char *const CORPUS_HEADER_HEX =
    "0100000081cd02ab7e569e8bcd9317e2fe99f2de44d49ab2b8851ba4a308000000000000e320b6c2fffc8d750423"
    "db8b1eb942ae710e951ed797f7affc8892b0f1fc122bc7f5d74df2b9441a42a14695";

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
 * @brief Builds a scan request from a header.
 *
 * @param[out] request Where it lands [BORROWS].
 * @param[in]  header  Eighty header bytes [BORROWS].
 */
void request_from_header(Sha256ScanRequest *request, const uint8_t *header)
{
    std::memset(request, 0, sizeof(*request));
    sha256_header_midstate(&request->midstate, header);
    request->merkle_root_tail = schedule_word_from_header(header + 64u);
    request->ntime = schedule_word_from_header(header + 68u);
    request->nbits = schedule_word_from_header(header + 72u);
}

/**
 * @brief Adds one survey into another.
 *
 * @param[in,out] into Destination [BORROWS].
 * @param[in]     from Source [BORROWS].
 */
void merge_survey(Sha256Survey &into, const Sha256Survey &from)
{
    into.nonces_evaluated += from.nonces_evaluated;
    for (size_t at = 0u; at <= 32u; at += 1u)
    {
        into.leading_zero_count[at] += from.leading_zero_count[at];
    }
    for (size_t at = 0u; at < 256u; at += 1u)
    {
        into.byte_histogram[at] += from.byte_histogram[at];
        into.bit_one_count[at] += from.bit_one_count[at];
    }
    for (size_t position = 0u; position < 32u; position += 1u)
    {
        for (size_t value = 0u; value < 256u; value += 1u)
        {
            into.position_histogram[position][value] +=
                from.position_histogram[position][value];
        }
    }
}

/**
 * @brief Surveys a nonce range across every core.
 *
 * @param[in]  base    Scan request carrying the header [BORROWS].
 * @param[in]  count   How many nonces to survey.
 * @param[out] survey  Where the counts land [BORROWS].
 */
void survey_threaded(const Sha256ScanRequest &base, uint32_t count, Sha256Survey &survey)
{
    const unsigned threads = (std::thread::hardware_concurrency() > 0u)
                                 ? std::thread::hardware_concurrency()
                                 : 8u;
    const uint32_t per_thread = (count / threads) & ~7u;
    std::vector<Sha256Survey> partials(threads);
    std::vector<std::thread> workers;

    for (unsigned index = 0u; index < threads; index += 1u)
    {
        std::memset(&partials[index], 0, sizeof(Sha256Survey));
        workers.emplace_back([&base, &partials, index, per_thread]() {
            Sha256ScanRequest request = base;
            request.nonce_start = base.nonce_start + (index * per_thread);
            request.nonce_count = per_thread;
            sha256_survey_avx2(&request, &partials[index]);
        });
    }
    for (std::thread &worker : workers)
    {
        worker.join();
    }
    for (const Sha256Survey &partial : partials)
    {
        merge_survey(survey, partial);
    }
}

/**
 * @brief Hypothesis one: survivor counts against the section 2.5 prediction, as the range grows.
 *
 * @param[in] base Scan request carrying the header [BORROWS].
 */
void test_corpus_size(const Sha256ScanRequest &base)
{
    std::printf("\n================================================================\n");
    std::printf("  1. Corpus size. Does survivor count track N * 2^-k?\n");
    std::printf("================================================================\n");
    std::printf("\n  Section 2.5 prices an anchor at q = 2^-H2 per symbol. For a flat digest a\n");
    std::printf("  k-bit anchor has q = 2^-k, so a range of N should leave N*2^-k survivors.\n");
    std::printf("\n  %10s %6s %14s %14s %10s\n", "N", "k bits", "predicted", "measured", "ratio");
    std::printf("  %10s %6s %14s %14s %10s\n", "----------", "------", "--------------",
                "--------------", "----------");

    for (unsigned magnitude = 20u; magnitude <= 26u; magnitude += 2u)
    {
        const uint32_t count = 1u << magnitude;
        Sha256Survey survey;
        std::memset(&survey, 0, sizeof(survey));
        survey_threaded(base, count, survey);

        for (unsigned width : {8u, 12u, 16u, 20u})
        {
            const double predicted =
                (double)survey.nonces_evaluated / std::pow(2.0, (double)width);
            const double measured = (double)survey.leading_zero_count[width];
            const double ratio = (predicted > 0.0) ? (measured / predicted) : 0.0;

            std::printf("  %10llu %6u %14.1f %14.0f %10.4f\n",
                        (unsigned long long)survey.nonces_evaluated, width, predicted, measured,
                        ratio);
        }
        std::printf("\n");
    }
    std::printf("  A ratio near one means the anchor behaves exactly as a flat domain predicts.\n");
    std::printf("  A ratio persistently away from one at some k would be structure worth mining.\n");
}

/**
 * @brief Hypothesis two: entropy eddies anywhere in the full digest.
 *
 * @param[in] survey Accumulated counts [BORROWS].
 */
void test_entropy_eddies(const Sha256Survey &survey)
{
    std::printf("\n================================================================\n");
    std::printf("  2. Entropy eddies. Is any position in the whole digest not flat?\n");
    std::printf("================================================================\n");

    const double samples = (double)survey.nonces_evaluated;
    std::printf("\n  Sample size: %llu digests, %llu bits per position.\n",
                (unsigned long long)survey.nonces_evaluated,
                (unsigned long long)survey.nonces_evaluated);

    // Bit bias. Under a flat model each position is a fair coin, so the count of ones has standard
    // error sqrt(N)/2 and the z score below is directly comparable across positions.
    const double bit_standard_error = std::sqrt(samples) / 2.0;
    double worst_bit_z = 0.0;
    unsigned worst_bit_position = 0u;

    for (unsigned position = 0u; position < 256u; position += 1u)
    {
        const double ones = (double)survey.bit_one_count[position];
        const double deviation = ones - (samples / 2.0);
        const double score = (bit_standard_error > 0.0) ? (deviation / bit_standard_error) : 0.0;

        if (std::fabs(score) > std::fabs(worst_bit_z))
        {
            worst_bit_z = score;
            worst_bit_position = position;
        }
    }

    std::printf("\n  Per-bit bias across all 256 positions:\n");
    std::printf("    largest deviation : bit %u, z = %+.2f\n", worst_bit_position, worst_bit_z);
    std::printf("    detection floor   : a bias of %.2e would show at 4 sigma\n",
                4.0 / (2.0 * std::sqrt(samples)));
    std::printf("    expected worst |z| over 256 fair coins is about 3.0\n");
    std::printf("    verdict           : %s\n",
                (std::fabs(worst_bit_z) < 5.0)
                    ? "no bit position departs from flat"
                    : "A BIT POSITION IS BIASED, worth investigating");

    // Byte distribution per position, by chi-square against uniform over 256 values.
    double worst_chi = 0.0;
    unsigned worst_chi_position = 0u;

    for (unsigned position = 0u; position < 32u; position += 1u)
    {
        double total = 0.0;
        for (unsigned value = 0u; value < 256u; value += 1u)
        {
            total += (double)survey.position_histogram[position][value];
        }
        const double expected = total / 256.0;
        double chi_square = 0.0;

        for (unsigned value = 0u; value < 256u; value += 1u)
        {
            const double observed = (double)survey.position_histogram[position][value];
            const double residual = observed - expected;
            chi_square += (expected > 0.0) ? ((residual * residual) / expected) : 0.0;
        }
        if (chi_square > worst_chi)
        {
            worst_chi = chi_square;
            worst_chi_position = position;
        }
    }

    // Chi-square with 255 degrees of freedom has mean 255 and standard deviation sqrt(510).
    const double chi_z = (worst_chi - 255.0) / std::sqrt(510.0);
    std::printf("\n  Per-byte-position distribution, chi-square against uniform (255 df):\n");
    std::printf("    largest           : position %u, X2 = %.1f (z = %+.2f)\n", worst_chi_position,
                worst_chi, chi_z);
    std::printf("    expected under flat: X2 near 255\n");
    std::printf("    verdict           : %s\n",
                (chi_z < 5.0) ? "no byte position departs from flat"
                              : "A BYTE POSITION IS SKEWED, worth investigating");

    // Global collision entropy, the quantity section 2.5 prices anchors with.
    double total_bytes = 0.0;
    for (unsigned value = 0u; value < 256u; value += 1u)
    {
        total_bytes += (double)survey.byte_histogram[value];
    }
    double collision_probability = 0.0;
    for (unsigned value = 0u; value < 256u; value += 1u)
    {
        const double share = (double)survey.byte_histogram[value] / total_bytes;
        collision_probability += share * share;
    }
    const double collision_entropy = -std::log2(collision_probability);

    std::printf("\n  Collision entropy of the digest byte stream:\n");
    std::printf("    H2 measured       : %.6f bits per byte\n", collision_entropy);
    std::printf("    H2 maximum        : 8.000000 bits per byte\n");
    std::printf("    shortfall         : %.2e bits\n", 8.0 - collision_entropy);
    std::printf("\n  Section 2.4 calls maximum entropy the base case for this construction. The\n");
    std::printf("  digest domain sits on it. That is the case where an informed anchor measure\n");
    std::printf("  can buy nothing over an uninformed one, because there is nothing to be\n");
    std::printf("  informed about.\n");
}

/**
 * @brief Hypothesis three: a repeating curve from the rotations, tested as lag autocorrelation.
 *
 * @param[in] base Scan request carrying the header [BORROWS].
 */
void test_repeating_curve(const Sha256ScanRequest &base)
{
    std::printf("\n================================================================\n");
    std::printf("  3. A repeating curve. Do the rotations leave a period in the nonce?\n");
    std::printf("================================================================\n");
    std::printf("\n  SHA-256 rotates by 2, 6, 7, 10, 11, 13, 17, 18, 19, 22 and 25. Each is\n");
    std::printf("  periodic on its own. If that periodicity survived composition, digests at\n");
    std::printf("  some nonce lag would agree on more than half their bits.\n");

    const uint32_t sample_count = 1u << 22;
    std::vector<uint64_t> digest_prefix(sample_count);

    // Take the leading 64 bits of each digest, which is where a share is decided anyway.
    const unsigned threads = (std::thread::hardware_concurrency() > 0u)
                                 ? std::thread::hardware_concurrency()
                                 : 8u;
    std::vector<std::thread> workers;
    const uint32_t per_thread = sample_count / threads;

    for (unsigned index = 0u; index < threads; index += 1u)
    {
        workers.emplace_back([&base, &digest_prefix, index, per_thread]() {
            for (uint32_t at = 0u; at < per_thread; at += 1u)
            {
                const uint32_t nonce = (index * per_thread) + at;

                // Take the digest directly instead of through the scan, which early-exits and so
                // would leave gaps in a stream that has to be contiguous to correlate.
                Sha256State first_pass = base.midstate;
                uint32_t block[16];
                block[0] = base.merkle_root_tail;
                block[1] = base.ntime;
                block[2] = base.nbits;
                block[3] = ((nonce >> 24) & 0xFFu) | ((nonce >> 8) & 0xFF00u) |
                           ((nonce << 8) & 0xFF0000u) | ((nonce << 24) & 0xFF000000u);
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

                digest_prefix[nonce] = ((uint64_t)second_pass.word[0] << 32) |
                                       (uint64_t)second_pass.word[1];
            }
        });
    }
    for (std::thread &worker : workers)
    {
        worker.join();
    }

    std::printf("\n  Bit agreement between digest(n) and digest(n+lag), over %u pairs.\n",
                sample_count / 2u);
    std::printf("  Under independence this is 0.5 with standard error %.2e.\n",
                0.5 / std::sqrt((double)(sample_count / 2u) * 64.0));
    std::printf("\n  %8s %14s %10s\n", "lag", "agreement", "z");
    std::printf("  %8s %14s %10s\n", "--------", "--------------", "----------");

    const uint32_t lags[] = {1u,  2u,   3u,    6u,    7u,     10u,    11u,    13u,
                            17u, 18u,  19u,   22u,   25u,    32u,    64u,    256u,
                            1024u, 4096u, 65536u, 1048576u};
    double worst_z = 0.0;
    uint32_t worst_lag = 0u;

    for (uint32_t lag : lags)
    {
        if (lag >= (sample_count / 2u))
        {
            continue;
        }
        uint64_t agreeing_bits = 0u;
        const uint32_t pairs = (sample_count / 2u);

        for (uint32_t at = 0u; at < pairs; at += 1u)
        {
            // Agreement is 64 minus the Hamming distance of the two prefixes.
            const uint64_t difference = digest_prefix[at] ^ digest_prefix[at + lag];
            agreeing_bits += (uint64_t)(64 - __builtin_popcountll(difference));
        }

        const double total_bits = (double)pairs * 64.0;
        const double agreement = (double)agreeing_bits / total_bits;
        const double standard_error = 0.5 / std::sqrt(total_bits);
        const double score = (agreement - 0.5) / standard_error;

        if (std::fabs(score) > std::fabs(worst_z))
        {
            worst_z = score;
            worst_lag = lag;
        }
        std::printf("  %8u %14.8f %+10.2f\n", lag, agreement, score);
    }

    std::printf("\n  largest deviation: lag %u at z = %+.2f\n", worst_lag, worst_z);
    std::printf("  verdict          : %s\n",
                (std::fabs(worst_z) < 5.0)
                    ? "no lag shows a repeating curve"
                    : "A LAG REPEATS, worth investigating");
    std::printf("\n  Why the rotations do not survive. Each round mixes rotation with addition\n");
    std::printf("  mod 2^32, whose carries do not commute with rotation, and adds a round\n");
    std::printf("  constant that differs every round. A period would have to survive 64 such\n");
    std::printf("  rounds twice. The measurement above is what that costs in practice.\n");
}

/**
 * @brief Hypothesis four: first success time against Kac's lemma.
 *
 * @param[in] base Scan request carrying the header [BORROWS].
 */
void test_hitting_time(const Sha256ScanRequest &base)
{
    std::printf("\n================================================================\n");
    std::printf("  4. Hitting time. Is first success geometric with mean 1/q?\n");
    std::printf("================================================================\n");
    std::printf("\n  Section 2.5 reads E[S] = 1/q as Kac's lemma, the expected return time to a\n");
    std::printf("  set of measure q. Here q = 2^-16, so first success should average 65536.\n");

    const unsigned trials = 512u;
    std::vector<uint32_t> first_success;
    first_success.reserve(trials);

    // Each trial uses a different ntime, which gives an independent digest stream from the same
    // header, the way a different corpus would in the paper's byte-string experiments.
    for (unsigned trial = 0u; trial < trials; trial += 1u)
    {
        Sha256ScanRequest request = base;
        request.ntime = base.ntime + trial;
        request.nonce_start = 0u;
        request.nonce_count = 1u << 22;
        std::memset(request.share_target, 0xFF, sizeof(request.share_target));
        request.share_target[0] = 0x0000FFFFu;

        Sha256ScanResult result;
        sha256_scan_avx2(&request, &result);
        if (result.found != 0)
        {
            first_success.push_back(result.winning_nonce);
        }
    }

    if (first_success.empty())
    {
        std::printf("\n  No trial succeeded, which itself contradicts the model.\n");
        return;
    }

    double sum = 0.0;
    for (uint32_t value : first_success)
    {
        sum += (double)value;
    }
    const double mean = sum / (double)first_success.size();

    double variance_sum = 0.0;
    for (uint32_t value : first_success)
    {
        const double deviation = (double)value - mean;
        variance_sum += deviation * deviation;
    }
    const double standard_deviation = std::sqrt(variance_sum / (double)first_success.size());

    std::vector<uint32_t> sorted = first_success;
    std::sort(sorted.begin(), sorted.end());
    const double median = (double)sorted[sorted.size() / 2u];

    std::printf("\n  trials succeeding : %zu of %u\n", first_success.size(), trials);
    std::printf("  mean first success: %.0f   (predicted 65536)\n", mean);
    std::printf("  ratio to predicted: %.4f\n", mean / 65536.0);
    std::printf("  std deviation     : %.0f   (geometric predicts ~mean, 65536)\n",
                standard_deviation);
    std::printf("  median            : %.0f   (geometric predicts %.0f)\n", median,
                65536.0 * std::log(2.0));
    std::printf("\n  A geometric distribution has standard deviation equal to its mean and a\n");
    std::printf("  median at ln(2) times the mean. Both hold here, which is what a memoryless\n");
    std::printf("  source looks like. It also means the search cannot be shortened: every nonce\n");
    std::printf("  is a fresh draw and no history predicts the next one.\n");
}

} // namespace

int main()
{
    std::printf("================================================================\n");
    std::printf("  The digest domain as a corpus\n");
    std::printf("  Testing four hypotheses about structure in SHA256d over nonces\n");
    std::printf("================================================================\n");

    const std::vector<uint8_t> header = bytes_from_hex(CORPUS_HEADER_HEX);
    Sha256ScanRequest base;
    request_from_header(&base, header.data());
    base.nonce_start = 0u;

    const auto started = std::chrono::steady_clock::now();

    test_corpus_size(base);

    std::printf("\n  Surveying the full digest for the eddy test...\n");
    Sha256Survey survey;
    std::memset(&survey, 0, sizeof(survey));
    survey_threaded(base, 1u << 24, survey);
    test_entropy_eddies(survey);

    test_repeating_curve(base);
    test_hitting_time(base);

    const auto finished = std::chrono::steady_clock::now();
    std::printf("\n================================================================\n");
    std::printf("  total elapsed %.1f s\n",
                std::chrono::duration<double>(finished - started).count());
    std::printf("================================================================\n");
    return 0;
}
