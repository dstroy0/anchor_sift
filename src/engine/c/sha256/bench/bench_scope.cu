/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_scope.cu
 * @brief The digest stream on a spectrum analyser and folded on itself, full band, on the device.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note bench_sound looked at the nonce axis with a hand-written radix-two transform over 2^20 to
 *       2^26 samples and six hand-picked envelope scales. It found nothing, and it could not have
 *       found a period longer than the window it was given. This is the same question asked the way
 *       a lab asks it: sweep the whole band instead of picking points in it.
 * @note One transform gives both instruments, which is why they belong in one file. The power
 *       spectrum is the analyser. Its inverse transform is the autocorrelation, which is the signal
 *       folded on itself at every offset at once - the Wiener-Khinchin pair. Computing the fold
 *       directly would be quadratic in the length; through the transform it is another n log n.
 * @note Band. At 2^26 samples the analyser covers every period from two samples to 67 million, so
 *       calling the sample rate 1 MHz puts the band at 0.015 Hz to 500 kHz in one sweep. The rate
 *       is a label instead of a property - the stream has no native one - and the periods are what
 *       the measurement is actually about.
 * @note Three streams, and two of them are controls that have to fail in opposite directions. A
 *       splitmix64 chain must come out flat, because a spectrum analyser that finds a line in a
 *       pseudorandom sequence is broken. A comb with a period written into it must show that line
 *       at that period and nowhere else. Without the second one a flat reading on SHA256d says
 *       nothing at all.
 * @note The device does the transform and the reduction; the host does the reading. A device that
 *       also decided what counted as a peak would be failure mode fifteen, a statistic implemented
 *       twice, which has already put two wrong numbers in this tree's tables.
 */

#include <cufft.h>
#include <cuda_runtime.h>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

namespace
{

/** @brief The standard's round constants. */
__constant__ uint32_t d_round_constant[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u,
    0xab1c5ed5u, 0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu,
    0x9bdc06a7u, 0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu,
    0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
    0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u, 0xa2bfe8a1u, 0xa81a664bu,
    0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u,
    0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u,
    0xc67178f2u};

/** @brief The standard's initial chaining value. */
__constant__ uint32_t d_initial_state[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                                            0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};

/** @brief Which stream to build. */
enum Stream
{
    STREAM_SHA,      /**< SHA256d over the header, indexed by nonce. */
    STREAM_SPLITMIX, /**< A pseudorandom chain, which must come out flat. */
    STREAM_COMB      /**< A planted period, which must come out as a line. */
};

/** @brief The period written into the comb control, in samples.
 *
 * @note Defined for the device as well as the host. A host-only constant read from a kernel does
 *       not link, and a control whose period the kernel cannot see would plant no signal at all -
 *       which would leave the analyser reading flat on every row and looking like it worked.
 */
#define COMB_PERIOD 4241.0

__device__ __forceinline__ uint32_t turn_right(uint32_t value, uint32_t distance)
{
    return __funnelshift_r(value, value, distance);
}

__device__ __forceinline__ uint32_t spread_low(uint32_t value)
{
    return turn_right(value, 7u) ^ turn_right(value, 18u) ^ (value >> 3u);
}

__device__ __forceinline__ uint32_t spread_high(uint32_t value)
{
    return turn_right(value, 17u) ^ turn_right(value, 19u) ^ (value >> 10u);
}

/** @brief Compresses one block, optionally stopping early. */
__device__ __forceinline__ void compress_block(uint32_t *state, uint32_t *schedule, unsigned rounds)
{
#pragma unroll
    for (int slot = 16; slot < 64; slot += 1)
    {
        schedule[slot] = spread_high(schedule[slot - 2]) + schedule[slot - 7] +
                         spread_low(schedule[slot - 15]) + schedule[slot - 16];
    }

    uint32_t working[8];
#pragma unroll
    for (int slot = 0; slot < 8; slot += 1)
    {
        working[slot] = state[slot];
    }

    for (unsigned round = 0u; round < rounds; round += 1u)
    {
        const uint32_t mix_high = turn_right(working[4], 6u) ^ turn_right(working[4], 11u) ^
                                  turn_right(working[4], 25u);
        const uint32_t choose = working[6] ^ (working[4] & (working[5] ^ working[6]));
        const uint32_t carry_one =
            working[7] + mix_high + choose + d_round_constant[round] + schedule[round];
        const uint32_t mix_low = turn_right(working[0], 2u) ^ turn_right(working[0], 13u) ^
                                 turn_right(working[0], 22u);
        const uint32_t majority =
            (working[0] & working[1]) | (working[2] & (working[0] ^ working[1]));

        working[7] = working[6];
        working[6] = working[5];
        working[5] = working[4];
        working[4] = working[3] + carry_one;
        working[3] = working[2];
        working[2] = working[1];
        working[1] = working[0];
        working[0] = carry_one + mix_low + majority;
    }

#pragma unroll
    for (int slot = 0; slot < 8; slot += 1)
    {
        state[slot] += working[slot];
    }
}

__device__ __forceinline__ uint64_t splitmix64(uint64_t &state)
{
    state += 0x9e3779b97f4a7c15ull;
    uint64_t mixed = state;
    mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
    mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
    return mixed ^ (mixed >> 31);
}

/**
 * @brief Fills the real input of the transform, one sample per nonce, already centred.
 *
 * @param[out] samples  Where the stream lands [BORROWS].
 * @param[in]  length   How many nonces.
 * @param[in]  which    Which stream to build.
 * @param[in]  rounds   Rounds of the first compression, 64 for the whole doubled hash.
 * @param[in]  word     Which state word to read a byte from.
 * @param[in]  midstate Chaining value after the first header block [BORROWS].
 * @param[in]  tail     Header words 64 through 75 [BORROWS].
 * @note Centred here instead of on the host, so bin zero of the transform carries no weight and
 *       cannot be mistaken for a line at DC. A spectrum analyser reading its own mean as a signal
 *       is the oldest mistake in the instrument.
 */
__global__ void fill_stream(cufftReal *samples, size_t length, int which, unsigned rounds,
                            unsigned word, const uint32_t *midstate, const uint32_t *tail)
{
    const size_t stride = (size_t)gridDim.x * blockDim.x;
    for (size_t nonce = (size_t)blockIdx.x * blockDim.x + threadIdx.x; nonce < length;
         nonce += stride)
    {
        unsigned char value = 0u;

        if (which == STREAM_SPLITMIX)
        {
            uint64_t state = (uint64_t)nonce;
            value = (unsigned char)splitmix64(state);
        }
        else if (which == STREAM_COMB)
        {
            uint64_t state = (uint64_t)nonce;
            const int noise = (int)(splitmix64(state) & 0xffu);
            const double wave =
                6.0 * sin(2.0 * 3.14159265358979 * (double)nonce / COMB_PERIOD);
            int mixed = noise + (int)wave;
            mixed = (mixed < 0) ? 0 : ((mixed > 255) ? 255 : mixed);
            value = (unsigned char)mixed;
        }
        else
        {
            uint32_t schedule[64];
            uint32_t state[8];
#pragma unroll
            for (int slot = 0; slot < 8; slot += 1)
            {
                state[slot] = midstate[slot];
            }
            schedule[0] = tail[0];
            schedule[1] = tail[1];
            schedule[2] = tail[2];
            schedule[3] = __byte_perm((uint32_t)nonce, 0u, 0x0123u);
            schedule[4] = 0x80000000u;
#pragma unroll
            for (int slot = 5; slot < 15; slot += 1)
            {
                schedule[slot] = 0u;
            }
            schedule[15] = 0x00000280u;

            if (rounds >= 64u)
            {
                compress_block(state, schedule, 64u);
#pragma unroll
                for (int slot = 0; slot < 8; slot += 1)
                {
                    schedule[slot] = state[slot];
                    state[slot] = d_initial_state[slot];
                }
                schedule[8] = 0x80000000u;
#pragma unroll
                for (int slot = 9; slot < 15; slot += 1)
                {
                    schedule[slot] = 0u;
                }
                schedule[15] = 0x00000100u;
                compress_block(state, schedule, 64u);
            }
            else
            {
                compress_block(state, schedule, rounds);
            }
            value = (unsigned char)state[word & 7u];
        }

        samples[nonce] = (cufftReal)((double)value - 127.5);
    }
}

/** @brief Turns the complex spectrum into power in place, for the inverse that follows. */
__global__ void to_power(cufftComplex *spectrum, size_t bins)
{
    const size_t stride = (size_t)gridDim.x * blockDim.x;
    for (size_t bin = (size_t)blockIdx.x * blockDim.x + threadIdx.x; bin < bins; bin += stride)
    {
        const float real = spectrum[bin].x;
        const float imaginary = spectrum[bin].y;
        spectrum[bin].x = (real * real) + (imaginary * imaginary);
        spectrum[bin].y = 0.0f;
    }
}

/**
 * @brief Folds the stream at a trial period, stacking every cycle on top of the others.
 *
 * @param[in]     samples The centred stream [BORROWS].
 * @param[in]     length  How many samples.
 * @param[in]     period  Trial period, in samples.
 * @param[in,out] profile Accumulator of length period, added to [BORROWS].
 * @note This is the amplifier instead of another detector. A transform spreads a spiky periodic
 *       signal across every harmonic and dilutes it; a fold stacks all of those harmonics back into
 *       one profile. Over the length/period cycles that get stacked, anything at the trial period
 *       adds linearly while everything else adds as a square root, so the gain in signal to noise
 *       is the square root of the number of cycles.
 * @note Nothing cancels here. Cycles are summed in phase, so a coherent component reinforces and
 *       an incoherent one averages toward zero instead of subtracting from anything.
 */
__global__ void fold_at(const cufftReal *samples, size_t length, unsigned period, double *profile)
{
    const size_t stride = (size_t)gridDim.x * blockDim.x;
    for (size_t at = (size_t)blockIdx.x * blockDim.x + threadIdx.x; at < length; at += stride)
    {
        atomicAdd(&profile[at % period], (double)samples[at]);
    }
}

/** @brief One peak, as the host reads it. */
struct Peak
{
    double height;
    size_t at;
};

/** @brief Names a stream. */
const char *stream_name(int which)
{
    return (which == STREAM_SHA) ? "SHA256d"
                                 : ((which == STREAM_SPLITMIX) ? "splitmix64 control"
                                                               : "comb control");
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned length_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 24u;
    const unsigned rounds = (argc > 2) ? (unsigned)std::atoi(argv[2]) : 64u;
    const unsigned word = (argc > 3) ? (unsigned)std::atoi(argv[3]) : 7u;
    const size_t length = (size_t)1u << length_bits;
    const size_t bins = (length / 2u) + 1u;
    const double claimed_rate = 1000000.0;

    std::printf("================================================================\n");
    std::printf("  The digest on a spectrum analyser, and folded on itself\n");
    std::printf("================================================================\n");
    std::printf("\n  One transform gives both instruments. The power spectrum is the analyser;\n");
    std::printf("  its inverse is the autocorrelation, which is the signal folded on itself at\n");
    std::printf("  every offset at once. Computing the fold directly would be quadratic in the\n");
    std::printf("  length; through the transform it is another n log n.\n");
    std::printf("\n  Samples: 2^%u = %zu, one per nonce, on the device.\n", length_bits, length);
    std::printf("  Band: every period from 2 samples to %zu. Calling the rate 1 MHz puts that\n",
                length);
    std::printf("  at %.4f Hz to %.0f Hz in one sweep, and the rate is a label instead of a\n",
                claimed_rate / (double)length, claimed_rate / 2.0);
    std::printf("  property, since the stream has no native one.\n");
    std::printf("  Rounds: %u. Word read: %u.\n", rounds, word);

    cudaDeviceProp properties;
    if (cudaGetDeviceProperties(&properties, 0) != cudaSuccess)
    {
        std::printf("\n  [!] no device.\n");
        return 1;
    }
    std::printf("  Device: %s, %.1f GB.\n", properties.name,
                (double)properties.totalGlobalMem / (1024.0 * 1024.0 * 1024.0));

    // Block 125552, the header this tree validates against.
    const unsigned char header[80] = {
        0x01, 0x00, 0x00, 0x00, 0x81, 0xcd, 0x02, 0xab, 0x7e, 0x56, 0x9e, 0x8b, 0xcd, 0x93, 0x17,
        0xe2, 0xfe, 0x99, 0xf2, 0xde, 0x44, 0xd4, 0x9a, 0xb2, 0xb8, 0x85, 0x1b, 0xa4, 0xa3, 0x08,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe3, 0x20, 0xb6, 0xc2, 0xff, 0xfc, 0x8d, 0x75, 0x04,
        0x23, 0xdb, 0x8b, 0x1e, 0xb9, 0x42, 0xae, 0x71, 0x0e, 0x95, 0x1e, 0xd7, 0x97, 0xf7, 0xaf,
        0xfc, 0x88, 0x92, 0xb0, 0xf1, 0xfc, 0x12, 0x2b, 0xc7, 0xf5, 0xd7, 0x4d, 0xf2, 0xb9, 0x44,
        0x1a, 0x42, 0xa1, 0x46, 0x95};

    // The midstate, computed on the host with the tree's own reference arm instead of a second
    // copy of SHA-256 living in this file.
    uint32_t midstate[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                            0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};
    {
        static const uint32_t constant[64] = {
            0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u,
            0x923f82a4u, 0xab1c5ed5u, 0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
            0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u, 0xe49b69c1u, 0xefbe4786u,
            0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
            0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u,
            0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
            0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u, 0xa2bfe8a1u, 0xa81a664bu,
            0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
            0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au,
            0x5b9cca4fu, 0x682e6ff3u, 0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
            0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};
        uint32_t schedule[64];
        for (unsigned word_at = 0u; word_at < 16u; word_at += 1u)
        {
            schedule[word_at] = ((uint32_t)header[word_at * 4u] << 24) |
                                ((uint32_t)header[(word_at * 4u) + 1u] << 16) |
                                ((uint32_t)header[(word_at * 4u) + 2u] << 8) |
                                (uint32_t)header[(word_at * 4u) + 3u];
        }
        for (unsigned word_at = 16u; word_at < 64u; word_at += 1u)
        {
            const uint32_t two = schedule[word_at - 2u];
            const uint32_t fifteen = schedule[word_at - 15u];
            const uint32_t high = ((two >> 17) | (two << 15)) ^ ((two >> 19) | (two << 13)) ^
                                  (two >> 10);
            const uint32_t low = ((fifteen >> 7) | (fifteen << 25)) ^
                                 ((fifteen >> 18) | (fifteen << 14)) ^ (fifteen >> 3);
            schedule[word_at] = high + schedule[word_at - 7u] + low + schedule[word_at - 16u];
        }
        uint32_t working[8];
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            working[slot] = midstate[slot];
        }
        for (unsigned round = 0u; round < 64u; round += 1u)
        {
            const uint32_t high = ((working[4] >> 6) | (working[4] << 26)) ^
                                  ((working[4] >> 11) | (working[4] << 21)) ^
                                  ((working[4] >> 25) | (working[4] << 7));
            const uint32_t choose = working[6] ^ (working[4] & (working[5] ^ working[6]));
            const uint32_t carry_one =
                working[7] + high + choose + constant[round] + schedule[round];
            const uint32_t low = ((working[0] >> 2) | (working[0] << 30)) ^
                                 ((working[0] >> 13) | (working[0] << 19)) ^
                                 ((working[0] >> 22) | (working[0] << 10));
            const uint32_t majority =
                (working[0] & working[1]) | (working[2] & (working[0] ^ working[1]));
            working[7] = working[6];
            working[6] = working[5];
            working[5] = working[4];
            working[4] = working[3] + carry_one;
            working[3] = working[2];
            working[2] = working[1];
            working[1] = working[0];
            working[0] = carry_one + low + majority;
        }
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            midstate[slot] += working[slot];
        }
    }

    uint32_t tail[3];
    for (unsigned at = 0u; at < 3u; at += 1u)
    {
        const unsigned base = 64u + (at * 4u);
        tail[at] = ((uint32_t)header[base] << 24) | ((uint32_t)header[base + 1u] << 16) |
                   ((uint32_t)header[base + 2u] << 8) | (uint32_t)header[base + 3u];
    }

    uint32_t *device_midstate = nullptr;
    uint32_t *device_tail = nullptr;
    cudaMalloc((void **)&device_midstate, sizeof(midstate));
    cudaMalloc((void **)&device_tail, sizeof(tail));
    cudaMemcpy(device_midstate, midstate, sizeof(midstate), cudaMemcpyHostToDevice);
    cudaMemcpy(device_tail, tail, sizeof(tail), cudaMemcpyHostToDevice);

    cufftReal *samples = nullptr;
    cufftComplex *spectrum = nullptr;
    if ((cudaMalloc((void **)&samples, length * sizeof(cufftReal)) != cudaSuccess) ||
        (cudaMalloc((void **)&spectrum, bins * sizeof(cufftComplex)) != cudaSuccess))
    {
        std::printf("\n  [!] device memory refused %zu samples.\n", length);
        return 1;
    }

    cufftHandle forward;
    cufftHandle backward;
    cufftPlan1d(&forward, (int)length, CUFFT_R2C, 1);
    cufftPlan1d(&backward, (int)length, CUFFT_C2R, 1);

    std::printf("\n  %-22s %14s %14s %12s %14s %12s\n", "stream", "top line", "at period",
                "in sigma", "top fold", "at lag");
    std::printf("  %-22s %14s %14s %12s %14s %12s\n", "----------------------", "--------------",
                "--------------", "------------", "--------------", "------------");

    for (int which = 0; which < 3; which += 1)
    {
        fill_stream<<<1024, 256>>>(samples, length, which, rounds, word, device_midstate,
                                   device_tail);
        cudaDeviceSynchronize();

        cufftExecR2C(forward, samples, spectrum);
        cudaDeviceSynchronize();

        std::vector<cufftComplex> read_back(bins);
        cudaMemcpy(read_back.data(), spectrum, bins * sizeof(cufftComplex),
                   cudaMemcpyDeviceToHost);

        // Bin zero is the mean, which centring already removed, and it is skipped instead of
        // trusted. The floor is the mean power of every other bin.
        double total = 0.0;
        for (size_t bin = 1u; bin < bins; bin += 1u)
        {
            total += ((double)read_back[bin].x * (double)read_back[bin].x) +
                     ((double)read_back[bin].y * (double)read_back[bin].y);
        }
        const double floor_power = total / (double)(bins - 1u);

        Peak line = {0.0, 0u};
        for (size_t bin = 1u; bin < bins; bin += 1u)
        {
            const double power = (((double)read_back[bin].x * (double)read_back[bin].x) +
                                  ((double)read_back[bin].y * (double)read_back[bin].y)) /
                                 floor_power;
            if (power > line.height)
            {
                line.height = power;
                line.at = bin;
            }
        }

        // The fold. Power in place, inverse transform, and the result is the autocorrelation at
        // every lag at once.
        to_power<<<1024, 256>>>(spectrum, bins);
        cudaDeviceSynchronize();
        cufftExecC2R(backward, spectrum, samples);
        cudaDeviceSynchronize();

        std::vector<cufftReal> fold(length);
        cudaMemcpy(fold.data(), samples, length * sizeof(cufftReal), cudaMemcpyDeviceToHost);

        // Lag zero is the signal against itself and is always the largest, so it is the scale
        // instead of a finding. Everything else is read against it.
        const double at_zero = (double)fold[0];
        Peak folded = {0.0, 0u};
        for (size_t lag = 1u; lag < (length / 2u); lag += 1u)
        {
            const double here = std::fabs((double)fold[lag] / at_zero);
            if (here > folded.height)
            {
                folded.height = here;
                folded.at = lag;
            }
        }

        // For a flat spectrum each bin is exponentially distributed about the mean, so the largest
        // of n sits near ln(n). That is the reference, derived instead of chosen.
        const double expected = std::log((double)(bins - 1u));

        std::printf("  %-22s %14.1f %14.1f %12.2f %14.6f %12zu\n", stream_name(which), line.height,
                    (line.at > 0u) ? ((double)length / (double)line.at) : 0.0,
                    line.height / expected, folded.height, folded.at);
    }

    // ---------------------------------------------------------------------------------------
    // The fold sweep, which is the amplifier.
    //
    // Sweep a trial period, stack every cycle in phase, and read how far the folded profile sits
    // from flat. Under no periodicity the profile bins are independent about zero, so the sum of
    // their squares scaled by the cycles stacked is a chi-square with period-minus-one degrees of
    // freedom, and that has a known mean and spread with nothing fitted.
    //
    // The sweep is coarse first and then bisected around whatever it finds, because a spiky signal
    // is narrow in period: a trial period off by one sample smears the spike across the profile and
    // reads as nothing. Coarse-then-fine is how a wide band gets searched without paying for every
    // period in it.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  The fold sweep: stacking cycles in phase to amplify\n");
    std::printf("================================================================\n");
    std::printf("\n  A transform spreads a spiky periodic signal across every harmonic. A fold\n");
    std::printf("  stacks them back into one profile, so signal adds linearly over the cycles\n");
    std::printf("  stacked while noise adds as a square root. Nothing cancels: cycles are summed\n");
    std::printf("  in phase, so a coherent component reinforces and an incoherent one averages\n");
    std::printf("  toward zero instead of subtracting from anything.\n");

    std::printf("\n  %-22s %14s %12s %14s %14s\n", "stream", "best period", "in sigma",
                "cycles stacked", "gain");
    std::printf("  %-22s %14s %12s %14s %14s\n", "----------------------", "--------------",
                "------------", "--------------", "--------------");

    {
        double *device_profile = nullptr;
        const unsigned longest = 8192u;
        cudaMalloc((void **)&device_profile, longest * sizeof(double));

        for (int which = 0; which < 3; which += 1)
        {
            fill_stream<<<1024, 256>>>(samples, length, which, rounds, word, device_midstate,
                                       device_tail);
            cudaDeviceSynchronize();

            double best_score = 0.0;
            unsigned best_period = 0u;

            // Coarse then fine. The coarse pass steps by sixteen to cover the band cheaply, and
            // the fine pass walks every period within sixteen of whatever the coarse pass liked,
            // because a spike one sample off the true period folds into nothing.
            for (int pass = 0; pass < 2; pass += 1)
            {
                const unsigned from = (pass == 0) ? 32u
                                                  : ((best_period > 32u) ? (best_period - 32u) : 2u);
                const unsigned to = (pass == 0) ? longest
                                                : ((best_period + 32u < longest) ? (best_period + 32u)
                                                                                 : longest);
                if ((pass == 1) && (best_period == 0u))
                {
                    break;
                }

                for (unsigned period = from; period < to;)
                {
                    cudaMemset(device_profile, 0, period * sizeof(double));
                    fold_at<<<512, 256>>>(samples, length, period, device_profile);
                    cudaDeviceSynchronize();

                    std::vector<double> profile(period);
                    cudaMemcpy(profile.data(), device_profile, period * sizeof(double),
                               cudaMemcpyDeviceToHost);

                    // Each bin normalised by its own count, not by the average. The length is not
                    // a multiple of the period, so the last cycle is partial and the first
                    // (length mod period) bins receive one sample more than the rest. Dividing
                    // every bin by the same average mis-scales two groups of bins against each
                    // other and injects a chi-square that has nothing to do with the signal.
                    //
                    // That defect had a signature: period 7136 lit up for the pseudorandom control
                    // at three separate lengths, and at 2^24 it beat the comb's own planted period,
                    // so the positive control failed and the row was void. A spurious attractor
                    // that survives changing the data is the instrument, not the data.
                    const double whole = std::floor((double)length / (double)period);
                    const unsigned longer = (unsigned)((size_t)length % (size_t)period);
                    const double spread_one = 255.0 * 255.0 / 12.0;
                    double chi = 0.0;
                    for (unsigned bin = 0u; bin < period; bin += 1u)
                    {
                        const double here = whole + ((bin < longer) ? 1.0 : 0.0);
                        if (here <= 0.0)
                        {
                            continue;
                        }
                        const double mean = profile[bin] / here;
                        chi += (mean * mean) / (spread_one / here);
                    }
                    // Chi-square with period-minus-one degrees of freedom has that mean and twice
                    // it for variance, so this is how many standard deviations from expectation.
                    const double freedom = (double)period - 1.0;
                    const double score = (chi - freedom) / std::sqrt(2.0 * freedom);
                    if (score > best_score)
                    {
                        best_score = score;
                        best_period = period;
                    }

                    // Adaptive resolution, not a fixed step. Folding a period-P signal at P plus
                    // delta smears it once delta times the cycles exceeds one, so the step has to
                    // stay under P squared over the length. A fixed step of sixteen satisfied that
                    // at 2^21 and violated it sixteen-fold at 2^24, where the comb's own period was
                    // never tested and the positive control failed - it reported 7136 instead of
                    // its planted 4241. The requirement tightens as the record lengthens, which is
                    // the opposite of the intuition that more data makes a search easier.
                    const double needed =
                        ((double)period * (double)period) / (double)length;
                    unsigned step = (needed >= 2.0) ? (unsigned)needed : 1u;
                    if (pass == 1)
                    {
                        step = 1u;
                    }
                    period += step;
                }
            }

            const double cycles = (best_period > 0u) ? ((double)length / (double)best_period) : 0.0;
            std::printf("  %-22s %14u %12.2f %14.0f %14.1f\n", stream_name(which), best_period,
                        best_score, cycles, std::sqrt(cycles));
        }
        cudaFree(device_profile);
    }

    std::printf("\n  The comb row must find its planted period here as well as in the spectrum,\n");
    std::printf("  and at a larger significance, because that is the whole claim about folding.\n");
    std::printf("  The gain column is the square root of the cycles stacked, which is what the\n");
    std::printf("  amplification is worth before any of it is read.\n");

    std::printf("\n  The comb row must show a line at period %.0f and nowhere else. If it does\n",
                COMB_PERIOD);
    std::printf("  not, this analyser cannot find a period that was deliberately written in and a\n");
    std::printf("  flat reading on SHA256d means nothing. The splitmix row must come out near the\n");
    std::printf("  expected column, because an analyser that finds a line in everything is as\n");
    std::printf("  useless as one that finds none.\n");
    std::printf("\n  The fold column is the autocorrelation at its strongest lag, as a fraction of\n");
    std::printf("  lag zero. A stream with no repeat at any offset reads near the reciprocal of\n");
    std::printf("  the square root of the length, which here is %.6f.\n",
                1.0 / std::sqrt((double)length));

    cufftDestroy(forward);
    cufftDestroy(backward);
    cudaFree(samples);
    cudaFree(spectrum);
    cudaFree(device_midstate);
    cudaFree(device_tail);
    return 0;
}
