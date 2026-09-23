/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_keyhole.cpp
 * @brief Salt the nonce, sift the whole digest for keyholes, at a sample size with no floor under it.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The premise this file acts on: the digest field carries no background noise, because
 *       H(digest | input) is exactly zero. SHA-256 is deterministic, so nothing here is a noisy
 *       measurement of a random process. Every bound below is a sampling limit and there is no floor
 *       beneath it, which means more samples tighten it without end. That is why this runs on the
 *       device and not the processor.
 * @note Earlier revisions of the workbook quoted a detection floor of 4.9e-4 as though it were a
 *       property of the domain. It was a property of where the measurement stopped. This is the
 *       correction.
 * @note A keyhole is an output bit position whose difference, under a fixed input salt, is not a
 *       fair coin. If the construction gives anything away, it gives it away here.
 */

#include "cuda_miner.h"
#include "sha256_core.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace
{

/** @brief Block 125552, so the header under test is reproducible by anyone. */
const char *const HEADER_HEX =
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

/** @brief The worst departure found across a set of counters, in standard errors. */
struct WorstBit
{
    unsigned position;
    double bias;
    double score;
};

/**
 * @brief Finds the counter furthest from half the sample size.
 *
 * @param[in] counts  256 counters [BORROWS].
 * @param[in] samples How many samples each counter saw.
 * @return            Where and how far.
 */
WorstBit worst_departure(const unsigned long long *counts, double samples)
{
    // Under a fair coin the count of ones has standard error sqrt(N)/2.
    const double standard_error = std::sqrt(samples) / 2.0;
    WorstBit worst = {0u, 0.0, 0.0};

    for (unsigned position = 0u; position < 256u; position += 1u)
    {
        const double deviation = (double)counts[position] - (samples / 2.0);
        const double score = (standard_error > 0.0) ? (deviation / standard_error) : 0.0;

        if (std::fabs(score) > std::fabs(worst.score))
        {
            worst.position = position;
            worst.score = score;
            worst.bias = deviation / samples;
        }
    }
    return worst;
}

} // namespace

int main(int argument_count, char **arguments)
{
    // Default to 2^32, the whole nonce space for one header. Override for a quicker pass.
    unsigned long long wanted = 4294967296ull;
    if (argument_count > 1)
    {
        wanted = std::stoull(arguments[1]);
    }

    char device_text[256];
    const int multiprocessors = cuda_miner_device_report(device_text, sizeof(device_text));

    std::printf("================================================================\n");
    std::printf("  Keyhole scan\n");
    std::printf("  device: %s\n", device_text);
    std::printf("================================================================\n");
    if (multiprocessors == 0)
    {
        std::printf("\nNo CUDA device.\n");
        return 1;
    }

    const std::vector<uint8_t> header = bytes_from_hex(HEADER_HEX);
    CudaScanParameters parameters;
    Sha256State midstate;

    std::memset(&parameters, 0, sizeof(parameters));
    sha256_header_midstate(&midstate, header.data());
    std::memcpy(parameters.midstate, midstate.word, sizeof(parameters.midstate));
    parameters.merkle_root_tail = schedule_word_from_header(header.data() + 64u);
    parameters.ntime = schedule_word_from_header(header.data() + 68u);
    parameters.nbits = schedule_word_from_header(header.data() + 72u);
    parameters.anchor_is_sound = 0u;

    CudaMinerContext *const context = cuda_miner_create(16u);
    if (context == nullptr)
    {
        std::printf("\nCould not allocate device buffers.\n");
        return 1;
    }

    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  1. Deep survey. Is any digest bit not a fair coin?\n");
    std::printf("================================================================\n");
    std::printf("\n  target sample: %llu digests\n", wanted);

    CudaSurvey survey;
    std::memset(&survey, 0, sizeof(survey));

    const uint32_t chunk = 1u << 28;
    auto started = std::chrono::steady_clock::now();
    unsigned long long done = 0u;

    while (done < wanted)
    {
        const unsigned long long remaining = wanted - done;
        const uint32_t take = (remaining < (unsigned long long)chunk) ? (uint32_t)remaining : chunk;

        if (cuda_miner_survey(context, &parameters, (uint32_t)done, take, &survey) == 0)
        {
            std::printf("  survey launch failed\n");
            cuda_miner_destroy(context);
            return 1;
        }
        done += take;
        std::printf("\r  %llu of %llu ...", done, wanted);
        std::fflush(stdout);
    }
    auto finished = std::chrono::steady_clock::now();
    const double survey_seconds = std::chrono::duration<double>(finished - started).count();

    const double samples = (double)survey.nonces_evaluated;
    const WorstBit worst = worst_departure(survey.bit_one_count, samples);

    std::printf("\r  %llu digests in %.1f s (%.2f GH/s)          \n",
                (unsigned long long)survey.nonces_evaluated, survey_seconds,
                (survey_seconds > 0.0) ? (samples / survey_seconds / 1.0e9) : 0.0);
    std::printf("\n  worst bit position   : %u\n", worst.position);
    std::printf("  its bias             : %+.3e\n", worst.bias);
    std::printf("  in standard errors   : %+.2f\n", worst.score);
    std::printf("  expected worst of 256: about 3.0\n");
    std::printf("  detection floor now  : %.3e at four sigma\n",
                4.0 / (2.0 * std::sqrt(samples)));
    std::printf("\n  verdict: %s\n",
                (std::fabs(worst.score) < 5.0) ? "no digest bit departs from a fair coin"
                                               : "A BIT DEPARTS. Investigate this position.");

    // The leading-zero counts are the anchor rate, and they price the filter directly.
    std::printf("\n  Anchor survivors against the section 2.5 prediction:\n");
    std::printf("  %8s %18s %18s %10s\n", "k bits", "predicted", "measured", "ratio");
    for (unsigned width : {8u, 16u, 24u, 32u})
    {
        const double predicted = samples / std::pow(2.0, (double)width);
        const double measured = (double)survey.leading_zero_count[width];
        std::printf("  %8u %18.1f %18.0f %10.5f\n", width, predicted, measured,
                    (predicted > 0.0) ? (measured / predicted) : 0.0);
    }

    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  2. Keyhole scan. Salt the nonce, watch every output bit.\n");
    std::printf("================================================================\n");
    std::printf("\n  For each salt, the difference at each of 256 output bits should be a fair\n");
    std::printf("  coin. A keyhole is a position where it is not.\n");

    // A flagged row is retested here instead of reported. Pass a salt and a sample size to run
    // that one salt deep: a real bias grows as the square root of the sample, and an artifact of
    // multiple comparisons regresses. There is no noise floor to stop this converging.
    if (argument_count > 3)
    {
        const uint32_t confirm_salt = (uint32_t)std::stoul(arguments[2], nullptr, 16);
        const unsigned long long confirm_total = std::stoull(arguments[3]);

        std::printf("\n================================================================\n");
        std::printf("  Confirmation run: salt 0x%08x over %llu pairs\n", confirm_salt,
                    confirm_total);
        std::printf("================================================================\n");

        std::vector<unsigned long long> counts(256u, 0u);
        unsigned long long seen = 0u;

        while (seen < confirm_total)
        {
            const unsigned long long remaining = confirm_total - seen;
            const uint32_t take =
                (remaining < (unsigned long long)chunk) ? (uint32_t)remaining : chunk;

            if (cuda_miner_keyhole(context, &parameters, (uint32_t)seen, take, confirm_salt,
                                   counts.data()) == 0)
            {
                std::printf("  launch failed\n");
                cuda_miner_destroy(context);
                return 1;
            }
            seen += take;
            std::printf("\r  %llu of %llu ...", seen, confirm_total);
            std::fflush(stdout);
        }

        const WorstBit confirmed = worst_departure(counts.data(), (double)seen);
        std::printf("\r  %llu pairs                              \n", seen);
        std::printf("\n  worst bit position : %u\n", confirmed.position);
        std::printf("  its bias           : %+.4e\n", confirmed.bias);
        std::printf("  in standard errors : %+.2f\n", confirmed.score);
        std::printf("  four sigma here is : %.4e\n", 4.0 / (2.0 * std::sqrt((double)seen)));

        std::printf("\n  A bias that was real at the smaller sample grows as sqrt(N): the sigma\n");
        std::printf("  should rise by the square root of the sample ratio. One that was an\n");
        std::printf("  artifact of testing 3840 positions at once falls back toward zero.\n");

        cuda_miner_destroy(context);
        return 0;
    }

    const uint32_t keyhole_sample = 1u << 26;

    /** @brief A salt to try, and why it is worth trying. */
    struct Salt
    {
        uint32_t value;
        const char *reason;
    };

    // The salts are not arbitrary. Most are read off the algorithm's own structure, because a
    // topology hole, if there is one, should sit where the construction repeats itself. The
    // single-bit and random salts are the controls that the structured ones are read against.
    const Salt salts[] = {
        {0x00000001u, "single bit, lowest"},
        {0x80000000u, "single bit, highest"},
        {0xA5A5A5A5u, "alternating, no relation to the algorithm"},
        {(1u << 2) | (1u << 13) | (1u << 22), "Sigma0 rotation set 2,13,22"},
        {(1u << 6) | (1u << 11) | (1u << 25), "Sigma1 rotation set 6,11,25"},
        {(1u << 7) | (1u << 18) | (1u << 3), "sigma0 set 7,18 and shift 3"},
        {(1u << 17) | (1u << 19) | (1u << 10), "sigma1 set 17,19 and shift 10"},
        {(1u << 2) ^ (1u << 13), "difference of two Sigma0 rotations"},
        {(1u << 6) ^ (1u << 25), "difference of two Sigma1 rotations"},
        {0x428a2f98u, "round constant K[0]"},
        {0x6a09e667u, "initial value word 0"},
        {0x9e3779b9u, "golden ratio, a constant the algorithm never uses"},
        {0x11111111u, "period 4 across the word"},
        {0x0000FFFFu, "half the word"},
        {0xFFFFFFFFu, "every bit"},
    };

    std::printf("\n  %12s %10s %14s %10s %-9s %s\n", "salt", "worst bit", "bias", "sigma",
                "verdict", "why this salt");
    std::printf("  %12s %10s %14s %10s %-9s %s\n", "------------", "----------", "--------------",
                "----------", "---------", "-------------");

    double overall_worst = 0.0;
    uint32_t overall_salt = 0u;

    for (const Salt &entry : salts)
    {
        const uint32_t salt = entry.value;
        std::vector<unsigned long long> difference_counts(256u, 0u);

        if (cuda_miner_keyhole(context, &parameters, 0u, keyhole_sample, salt,
                               difference_counts.data()) == 0)
        {
            std::printf("  keyhole launch failed for salt %08x\n", salt);
            continue;
        }

        const WorstBit found = worst_departure(difference_counts.data(), (double)keyhole_sample);
        if (std::fabs(found.score) > std::fabs(overall_worst))
        {
            overall_worst = found.score;
            overall_salt = salt;
        }
        std::printf("    0x%08x %10u %+14.3e %+10.2f %-9s %s\n", salt, found.position, found.bias,
                    found.score, (std::fabs(found.score) < 5.0) ? "closed" : "KEYHOLE",
                    entry.reason);
    }

    const unsigned salt_count = (unsigned)(sizeof(salts) / sizeof(salts[0]));
    const unsigned tests = salt_count * 256u;
    std::printf("\n  Each row is %u pairs, so a four sigma bias is %.3e.\n", keyhole_sample,
                4.0 / (2.0 * std::sqrt((double)keyhole_sample)));
    std::printf("  Largest departure anywhere: salt 0x%08x at %+.2f sigma.\n", overall_salt,
                overall_worst);
    std::printf("\n  That is %u salts times 256 positions, %u tests. The expected worst by chance\n",
                salt_count, tests);
    std::printf("  alone over that many is near %.1f sigma, so the table is read against that\n",
                std::sqrt(2.0 * std::log((double)tests)));
    std::printf("  and not against zero. Calling a 3 sigma result a keyhole here would be\n");
    std::printf("  finding structure in the multiple comparisons instead of in the function.\n");

    cuda_miner_destroy(context);

    finished = std::chrono::steady_clock::now();
    std::printf("\n================================================================\n");
    std::printf("  There is no noise floor under any of these numbers. They are\n");
    std::printf("  sampling limits, and they move with more samples.\n");
    std::printf("================================================================\n");
    return 0;
}
