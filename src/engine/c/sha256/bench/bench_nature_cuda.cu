/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_nature_cuda.cu
 * @brief The two-language lag sweep on the device, every lag at once.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The host sweep took nearly three minutes for a handful of corpora at four thousand lags,
 *       and the work is one 256-bin histogram per lag per language over a couple of million bytes -
 *       which is a block of threads each, and nothing about it wants a CPU.
 * @note One block per lag, both languages in shared memory at once, so the corpus is read once for
 *       both instead of twice. Two histograms is two kilobytes of shared memory per block, which
 *       leaves occupancy alone.
 * @note The statistics stay on the host, in bench_nature_score.h, included by both arms. A device
 *       that computed its own grip would be a second implementation of the same statistic, which is
 *       failure mode fifteen and has already cost this tree two wrong numbers.
 */

#include "bench_nature_score.h"

#include <cuda_runtime.h>

#include <cstdio>
#include <string>
#include <vector>

namespace
{

/** @brief Longest lag examined. */
const unsigned LAG_LIMIT = 4096u;

/** @brief Bytes read from each corpus. */
const size_t SAMPLE_CAP = 2000000u;

/**
 * @brief Histograms both languages' differences at one lag per block.
 *
 * @param[in]  seats  The corpus bytes on the device [BORROWS].
 * @param[in]  length How many bytes.
 * @param[out] counts Room for LAG_LIMIT by 2 by 256 counters [BORROWS].
 * @note Shared memory first and global once at the end, because a global atomic per byte over two
 *       million bytes and four thousand lags is sixteen billion round trips to memory and a shared
 *       one is not.
 */
__global__ void histogram_lags(const unsigned char *seats, size_t length, unsigned *counts)
{
    __shared__ unsigned by_xor[256];
    __shared__ unsigned by_add[256];

    const unsigned lag = blockIdx.x + 1u;
    for (unsigned bin = threadIdx.x; bin < 256u; bin += blockDim.x)
    {
        by_xor[bin] = 0u;
        by_add[bin] = 0u;
    }
    __syncthreads();

    if ((size_t)lag < length)
    {
        const size_t pairs = length - lag;
        for (size_t at = threadIdx.x; at < pairs; at += blockDim.x)
        {
            const unsigned char left = seats[at];
            const unsigned char right = seats[at + lag];
            atomicAdd(&by_xor[left ^ right], 1u);
            atomicAdd(&by_add[(unsigned char)(left - right)], 1u);
        }
    }
    __syncthreads();

    unsigned *const out = &counts[(size_t)blockIdx.x * 512u];
    for (unsigned bin = threadIdx.x; bin < 256u; bin += blockDim.x)
    {
        out[bin] = by_xor[bin];
        out[256u + bin] = by_add[bin];
    }
}

/** @brief What one corpus reported. */
struct Reading
{
    double best_xor;
    double best_add;
    unsigned xor_lag;
    unsigned add_lag;
};

/**
 * @brief Sweeps every lag on the device and reads the best grip each language found.
 *
 * @param[in] seats  The corpus bytes [BORROWS].
 * @param[in] length How many bytes.
 * @return           Best grip and where it sat, per language.
 */
Reading sweep(const unsigned char *seats, size_t length)
{
    uint64_t marginal[256];
    std::memset(marginal, 0, sizeof(marginal));
    for (size_t at = 0u; at < length; at += 1u)
    {
        marginal[seats[at]] += 1u;
    }
    const double xor_baseline = bench_nature_baseline(marginal, (uint64_t)length, 0);
    const double add_baseline = bench_nature_baseline(marginal, (uint64_t)length, 1);

    unsigned char *device_seats = nullptr;
    unsigned *device_counts = nullptr;
    cudaMalloc((void **)&device_seats, length);
    cudaMalloc((void **)&device_counts, (size_t)LAG_LIMIT * 512u * sizeof(unsigned));
    cudaMemcpy(device_seats, seats, length, cudaMemcpyHostToDevice);
    cudaMemset(device_counts, 0, (size_t)LAG_LIMIT * 512u * sizeof(unsigned));

    histogram_lags<<<LAG_LIMIT, 256>>>(device_seats, length, device_counts);
    cudaDeviceSynchronize();

    std::vector<unsigned> counts((size_t)LAG_LIMIT * 512u);
    cudaMemcpy(counts.data(), device_counts, counts.size() * sizeof(unsigned),
               cudaMemcpyDeviceToHost);
    cudaFree(device_seats);
    cudaFree(device_counts);

    Reading out = {0.0, 0.0, 0u, 0u};
    for (unsigned lag = 1u; lag <= LAG_LIMIT; lag += 1u)
    {
        if ((size_t)lag >= length)
        {
            break;
        }
        const unsigned *const row = &counts[(size_t)(lag - 1u) * 512u];
        uint64_t wide_xor[256];
        uint64_t wide_add[256];
        for (unsigned bin = 0u; bin < 256u; bin += 1u)
        {
            wide_xor[bin] = (uint64_t)row[bin];
            wide_add[bin] = (uint64_t)row[256u + bin];
        }
        const uint64_t pairs = (uint64_t)(length - lag);

        const double by_xor = bench_nature_shortfall(wide_xor, pairs) - xor_baseline;
        const double by_add = bench_nature_shortfall(wide_add, pairs) - add_baseline;
        if (by_xor > out.best_xor)
        {
            out.best_xor = by_xor;
            out.xor_lag = lag;
        }
        if (by_add > out.best_add)
        {
            out.best_add = by_add;
            out.add_lag = lag;
        }
    }
    return out;
}

/** @brief Builds a sequence one language reads exactly and the other cannot. */
std::vector<unsigned char> built_control(int additive, size_t length, unsigned period)
{
    std::vector<unsigned char> out;
    out.reserve(length);

    unsigned char block[64];
    uint32_t state = 20260908u;
    for (unsigned at = 0u; at < period; at += 1u)
    {
        state = (state * 1103515245u) + 12345u;
        block[at] = (unsigned char)(state >> 16);
    }

    const unsigned char offset = 0x5au;
    while (out.size() < length)
    {
        for (unsigned at = 0u; at < period; at += 1u)
        {
            out.push_back(block[at]);
        }
        for (unsigned at = 0u; at < period; at += 1u)
        {
            block[at] = (additive != 0) ? (unsigned char)(block[at] + offset)
                                        : (unsigned char)(block[at] ^ offset);
        }
    }
    out.resize(length);
    return out;
}

} // namespace

int main(int argc, char **argv)
{
    std::printf("================================================================\n");
    std::printf("  The two-language lag sweep, on the device\n");
    std::printf("================================================================\n");
    std::printf("\n  One block per lag, both languages histogrammed in shared memory at once, so\n");
    std::printf("  the corpus is read once for both instead of twice and the sixteen billion\n");
    std::printf("  global round trips a naive version would make never happen.\n");
    std::printf("\n  Every statistic is the host's own, from bench_nature_score.h, included by both\n");
    std::printf("  arms. A device computing its own grip would be the same statistic implemented\n");
    std::printf("  twice, which has already cost this tree two wrong numbers.\n");

    std::printf("\n  %-34s %10s %10s %8s %8s %8s\n", "corpus", "xor", "add", "xor lag", "add lag",
                "which");
    std::printf("  %-34s %10s %10s %8s %8s %8s\n", "----------------------------------",
                "----------", "----------", "--------", "--------", "--------");

    // The built controls first, read at their own period, because every row below them is only
    // readable if they behave and they must fail in opposite directions.
    for (int additive = 0; additive < 2; additive += 1)
    {
        const unsigned designed = 8u;
        const std::vector<unsigned char> made = built_control(additive, SAMPLE_CAP, designed);

        uint64_t marginal[256];
        std::memset(marginal, 0, sizeof(marginal));
        for (size_t at = 0u; at < made.size(); at += 1u)
        {
            marginal[made[at]] += 1u;
        }

        uint64_t by_xor[256];
        uint64_t by_add[256];
        std::memset(by_xor, 0, sizeof(by_xor));
        std::memset(by_add, 0, sizeof(by_add));
        const size_t pairs = made.size() - designed;
        for (size_t at = 0u; at < pairs; at += 1u)
        {
            by_xor[made[at] ^ made[at + designed]] += 1u;
            by_add[(unsigned char)(made[at] - made[at + designed])] += 1u;
        }

        const double at_xor = bench_nature_shortfall(by_xor, (uint64_t)pairs) -
                              bench_nature_baseline(marginal, (uint64_t)made.size(), 0);
        const double at_add = bench_nature_shortfall(by_add, (uint64_t)pairs) -
                              bench_nature_baseline(marginal, (uint64_t)made.size(), 1);

        std::printf("  %-34s %10.4f %10.4f %8u %8u %8s\n",
                    (additive != 0) ? "[built] add at its own lag" : "[built] xor at its own lag",
                    at_xor, at_add, designed, designed,
                    (at_xor > (at_add + 0.02)) ? "xor"
                                               : ((at_add > (at_xor + 0.02)) ? "add" : "level"));
    }

    for (int at = 1; at < argc; at += 1)
    {
        std::FILE *const handle = std::fopen(argv[at], "rb");
        if (handle == nullptr)
        {
            continue;
        }
        std::vector<unsigned char> body(SAMPLE_CAP, 0u);
        const size_t read = std::fread(body.data(), 1u, SAMPLE_CAP, handle);
        std::fclose(handle);
        if (read < 100000u)
        {
            continue;
        }
        body.resize(read);

        std::string label(argv[at]);
        const size_t slash = label.find_last_of("/\\");
        if (slash != std::string::npos)
        {
            label = label.substr(slash + 1u);
        }
        const size_t dot = label.find_last_of('.');
        if (dot != std::string::npos)
        {
            label = label.substr(0u, dot);
        }

        const Reading found = sweep(body.data(), body.size());
        std::printf("  %-34s %10.4f %10.4f %8u %8u %8s\n", label.substr(0u, 34u).c_str(),
                    found.best_xor, found.best_add, found.xor_lag, found.add_lag,
                    (found.best_xor > (found.best_add + 0.02))
                        ? "xor"
                        : ((found.best_add > (found.best_xor + 0.02)) ? "add" : "level"));
    }

    std::printf("\n  The two built rows must come out lopsided in opposite directions, and they are\n");
    std::printf("  lopsided by different amounts because each saturates its own ceiling: a grip\n");
    std::printf("  cannot exceed eight bits less that corpus's baseline, and the two controls have\n");
    std::printf("  different alphabets. That is scarcity setting what can be measured at all.\n");
    return 0;
}
