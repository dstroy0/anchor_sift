/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_renyi_cuda.cu
 * @brief Counting the Renyi enumeration on the device, and nothing else.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Only counting lives here. Deficits, predictions, controls and reporting stay on the host
 *       and are written once, because a second implementation of a statistic is failure mode
 *       fifteen and it has already put two wrong numbers in this bench's headline table.
 * @note The three histograms are laid out to match where their traffic goes instead of to look
 *       tidy. Byte windows are 32 KB, so a block keeps them in shared memory and pays one global
 *       write per bin at the end. Sixteen-bit windows are four megabytes, which is the size of
 *       this part's level two cache, so their atomics are served without reaching memory. The
 *       wide window is four gigabytes and its atomics do reach memory, which is why it is optional.
 * @note There are no byte atomics on this architecture. Preimage counts here are Poisson about a
 *       mean of one and the largest over 2^32 draws sits near fourteen, so a byte cannot carry into
 *       its neighbor and an atomicAdd on the containing 32-bit word with a shifted increment is
 *       exact. That is an argument from the distribution, so the host checks the assumption instead
 *       of trusting it: if any count reaches 255 the run says so instead of reporting wrapped
 *       figures.
 */

#include "bench_renyi_cuda.h"

#include <cuda_runtime.h>

#include <cstdio>
#include <cstring>

namespace
{

/** @brief Bins in a byte window. */
const unsigned BYTE_BINS = 256u;

/** @brief Aligned byte windows over the 256-bit digest. */
const unsigned BYTE_WINDOWS = 32u;

/** @brief Bins in a sixteen-bit window. */
const unsigned WORD_BINS = 65536u;

/** @brief Aligned sixteen-bit windows over the 256-bit digest. */
const unsigned WORD_WINDOWS = 16u;

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

/** @brief Rotates a word right. */
__device__ __forceinline__ uint32_t rotate_right(uint32_t value, uint32_t distance)
{
    return __funnelshift_r(value, value, distance);
}

/** @brief The message schedule's low spreading function. */
__device__ __forceinline__ uint32_t spread_low(uint32_t value)
{
    return rotate_right(value, 7u) ^ rotate_right(value, 18u) ^ (value >> 3u);
}

/** @brief The message schedule's high spreading function. */
__device__ __forceinline__ uint32_t spread_high(uint32_t value)
{
    return rotate_right(value, 17u) ^ rotate_right(value, 19u) ^ (value >> 10u);
}

/** @brief One round of the compression function. */
#define DEVICE_ROUND(state_a_, state_b_, state_c_, state_d_, state_e_, state_f_, state_g_,         \
                     state_h_, round_, schedule_word_)                                             \
    do                                                                                             \
    {                                                                                              \
        const uint32_t mix_high = rotate_right(state_e_, 6u) ^ rotate_right(state_e_, 11u) ^       \
                                  rotate_right(state_e_, 25u);                                     \
        const uint32_t choose = state_g_ ^ (state_e_ & (state_f_ ^ state_g_));                     \
        const uint32_t carry_one =                                                                 \
            state_h_ + mix_high + choose + d_round_constant[round_] + (schedule_word_);            \
        const uint32_t mix_low = rotate_right(state_a_, 2u) ^ rotate_right(state_a_, 13u) ^        \
                                 rotate_right(state_a_, 22u);                                      \
        const uint32_t majority = (state_a_ & state_b_) | (state_c_ & (state_a_ ^ state_b_));      \
        state_h_ = state_g_;                                                                       \
        state_g_ = state_f_;                                                                       \
        state_f_ = state_e_;                                                                       \
        state_e_ = state_d_ + carry_one;                                                           \
        state_d_ = state_c_;                                                                       \
        state_c_ = state_b_;                                                                       \
        state_b_ = state_a_;                                                                       \
        state_a_ = carry_one + mix_low + majority;                                                 \
    } while (0)

/** @brief Compresses one block into a chaining value held in registers. */
__device__ __forceinline__ void compress_block(uint32_t *state, uint32_t *schedule)
{
#pragma unroll
    for (int slot = 16; slot < 64; slot += 1)
    {
        schedule[slot] = spread_high(schedule[slot - 2]) + schedule[slot - 7] +
                         spread_low(schedule[slot - 15]) + schedule[slot - 16];
    }

    uint32_t state_a = state[0];
    uint32_t state_b = state[1];
    uint32_t state_c = state[2];
    uint32_t state_d = state[3];
    uint32_t state_e = state[4];
    uint32_t state_f = state[5];
    uint32_t state_g = state[6];
    uint32_t state_h = state[7];

#pragma unroll
    for (int round = 0; round < 64; round += 1)
    {
        DEVICE_ROUND(state_a, state_b, state_c, state_d, state_e, state_f, state_g, state_h, round,
                     schedule[round]);
    }

    state[0] += state_a;
    state[1] += state_b;
    state[2] += state_c;
    state[3] += state_d;
    state[4] += state_e;
    state[5] += state_f;
    state[6] += state_g;
    state[7] += state_h;
}

/** @brief Advances a splitmix64 state and returns its output. */
__device__ __forceinline__ uint64_t splitmix64(uint64_t &state)
{
    state += 0x9e3779b97f4a7c15ull;
    uint64_t mixed = state;
    mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
    mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
    return mixed ^ (mixed >> 31);
}

/**
 * @brief Fills the thirty-two digest bytes for one nonce, in the standard's own output order.
 *
 * @param[in]  job    Midstate and header tail [BORROWS].
 * @param[in]  source Which function to evaluate.
 * @param[in]  nonce  The nonce.
 * @param[out] digest Thirty-two bytes [BORROWS].
 * @note Byte order here has to match the host exactly or the two arms count different events and
 *       the acceptance test is meaningless. Standard order, most significant byte of state word
 *       zero first, which is what sha256_hash would emit.
 */
__device__ __forceinline__ void digest_bytes(const RenyiCudaJob &job, int source, uint32_t nonce,
                                             unsigned char *digest)
{
    if (source == 1)
    {
#pragma unroll
        for (int at = 0; at < 32; at += 1)
        {
            digest[at] = 0u;
        }
        return;
    }

    if (source == 2)
    {
#pragma unroll
        for (int copy = 0; copy < 8; copy += 1)
        {
            digest[(copy * 4) + 0] = (unsigned char)(nonce >> 24);
            digest[(copy * 4) + 1] = (unsigned char)(nonce >> 16);
            digest[(copy * 4) + 2] = (unsigned char)(nonce >> 8);
            digest[(copy * 4) + 3] = (unsigned char)nonce;
        }
        return;
    }

    if (source == 3)
    {
        uint64_t state = (uint64_t)nonce;
#pragma unroll
        for (int half = 0; half < 4; half += 1)
        {
            const uint64_t drawn = splitmix64(state);
#pragma unroll
            for (int byte = 0; byte < 8; byte += 1)
            {
                digest[(half * 8) + byte] = (unsigned char)(drawn >> (56 - (byte * 8)));
            }
        }
        return;
    }

    uint32_t schedule[64];
    uint32_t state[8];

#pragma unroll
    for (int slot = 0; slot < 8; slot += 1)
    {
        state[slot] = job.midstate[slot];
    }
    schedule[0] = job.merkle_root_tail;
    schedule[1] = job.ntime;
    schedule[2] = job.nbits;
    schedule[3] = __byte_perm(nonce, 0u, 0x0123u);
    schedule[4] = 0x80000000u;
#pragma unroll
    for (int slot = 5; slot < 15; slot += 1)
    {
        schedule[slot] = 0u;
    }
    schedule[15] = 0x00000280u;
    compress_block(state, schedule);

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
    compress_block(state, schedule);

#pragma unroll
    for (int word = 0; word < 8; word += 1)
    {
        digest[(word * 4) + 0] = (unsigned char)(state[word] >> 24);
        digest[(word * 4) + 1] = (unsigned char)(state[word] >> 16);
        digest[(word * 4) + 2] = (unsigned char)(state[word] >> 8);
        digest[(word * 4) + 3] = (unsigned char)state[word];
    }
}

/** @brief Reads a field of bits from the digest, treating it as a ring, as the host does. */
__device__ __forceinline__ uint32_t extract_bits(const unsigned char *digest, unsigned start,
                                                 unsigned width)
{
    uint32_t value = 0u;
    for (unsigned step = 0u; step < width; step += 1u)
    {
        const unsigned at = (start + step) & 255u;
        value = (value << 1) | (uint32_t)((digest[at >> 3] >> (7u - (at & 7u))) & 1u);
    }
    return value;
}

/** @brief Counts leading zero bits the way the protocol reads a digest, as the host does. */
__device__ __forceinline__ unsigned protocol_leading_zeros(const unsigned char *digest)
{
    unsigned leading = 0u;
    for (unsigned step = 0u; step < 32u; step += 1u)
    {
        const unsigned char value = digest[31u - step];
        if (value != 0u)
        {
            return leading + (unsigned)__clz((int)((unsigned)value << 24));
        }
        leading += 8u;
    }
    return 256u;
}

/**
 * @brief Enumerates a slice of the nonce domain and counts it.
 *
 * @param[in]     job          Midstate and header tail.
 * @param[in]     source       Which function to evaluate.
 * @param[in]     first        First nonce of this launch.
 * @param[in]     count        How many nonces this launch covers.
 * @param[in]     phase        Bit offset every window starts at.
 * @param[in,out] byte_window  32 by 256 device counters [BORROWS].
 * @param[in,out] word_window  16 by 65536 device counters [BORROWS].
 * @param[in,out] leading_zero 257 device counters [BORROWS].
 * @param[in,out] wide_window  2^32 packed byte counters, or null [BORROWS].
 * @note Byte windows go through shared memory because 32 KB fits and the traffic is heavy. The
 *       sixteen-bit windows are four megabytes, which is this part's level two cache, so their
 *       atomics stay on chip without any help from here.
 */
__global__ void count_nonces(RenyiCudaJob job, int source, uint64_t first, uint64_t count,
                             unsigned phase, unsigned long long *byte_window,
                             unsigned long long *word_window, unsigned long long *leading_zero,
                             unsigned int *wide_window)
{
    __shared__ unsigned int local_byte[BYTE_WINDOWS * BYTE_BINS];
    __shared__ unsigned int local_zero[257];

    for (unsigned slot = threadIdx.x; slot < (BYTE_WINDOWS * BYTE_BINS); slot += blockDim.x)
    {
        local_byte[slot] = 0u;
    }
    for (unsigned slot = threadIdx.x; slot < 257u; slot += blockDim.x)
    {
        local_zero[slot] = 0u;
    }
    __syncthreads();

    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    for (uint64_t step = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; step < count;
         step += stride)
    {
        unsigned char digest[32];
        const uint32_t nonce = (uint32_t)(first + step);
        digest_bytes(job, source, nonce, digest);

        if (phase == 0u)
        {
#pragma unroll
            for (unsigned window = 0u; window < BYTE_WINDOWS; window += 1u)
            {
                atomicAdd(&local_byte[(window * BYTE_BINS) + digest[window]], 1u);
            }
            for (unsigned window = 0u; window < WORD_WINDOWS; window += 1u)
            {
                const unsigned value =
                    ((unsigned)digest[window * 2u] << 8) | (unsigned)digest[(window * 2u) + 1u];
                atomicAdd(&word_window[(window * WORD_BINS) + value], 1ull);
            }
        }
        else
        {
            for (unsigned window = 0u; window < BYTE_WINDOWS; window += 1u)
            {
                const unsigned value = extract_bits(digest, (window * 8u) + phase, 8u);
                atomicAdd(&local_byte[(window * BYTE_BINS) + value], 1u);
            }
            for (unsigned window = 0u; window < WORD_WINDOWS; window += 1u)
            {
                const unsigned value = extract_bits(digest, (window * 16u) + phase, 16u);
                atomicAdd(&word_window[(window * WORD_BINS) + value], 1ull);
            }
        }

        atomicAdd(&local_zero[protocol_leading_zeros(digest)], 1u);

        if (wide_window != nullptr)
        {
            const uint32_t value = ((uint32_t)digest[0] << 24) | ((uint32_t)digest[1] << 16) |
                                   ((uint32_t)digest[2] << 8) | (uint32_t)digest[3];
            // No byte atomics exist here. The counts are Poisson about one and the largest over
            // 2^32 draws sits near fourteen, so a byte cannot carry into its neighbor and adding
            // a shifted one to the containing word is exact. The host checks that assumption
            // afterwards instead of trusting it.
            atomicAdd(&wide_window[value >> 2], 1u << ((value & 3u) * 8u));
        }
    }
    __syncthreads();

    for (unsigned slot = threadIdx.x; slot < (BYTE_WINDOWS * BYTE_BINS); slot += blockDim.x)
    {
        if (local_byte[slot] != 0u)
        {
            atomicAdd(&byte_window[slot], (unsigned long long)local_byte[slot]);
        }
    }
    for (unsigned slot = threadIdx.x; slot < 257u; slot += blockDim.x)
    {
        if (local_zero[slot] != 0u)
        {
            atomicAdd(&leading_zero[slot], (unsigned long long)local_zero[slot]);
        }
    }
}

/** @brief Reports a CUDA failure once, with the call that produced it. */
int complain(const char *what, cudaError_t status)
{
    std::fprintf(stderr, "  [!] %s: %s\n", what, cudaGetErrorString(status));
    return 0;
}

} // namespace

extern "C" int renyi_cuda_available(char *text, size_t text_size)
{
    int devices = 0;
    if ((cudaGetDeviceCount(&devices) != cudaSuccess) || (devices < 1))
    {
        return 0;
    }

    cudaDeviceProp properties;
    if (cudaGetDeviceProperties(&properties, 0) != cudaSuccess)
    {
        return 0;
    }

    if (text != nullptr)
    {
        std::snprintf(text, text_size, "%s, compute %d.%d, %.1f GB", properties.name,
                      properties.major, properties.minor,
                      (double)properties.totalGlobalMem / (1024.0 * 1024.0 * 1024.0));
    }
    return 1;
}

extern "C" int renyi_cuda_count(const RenyiCudaJob *job, int source, uint64_t domain,
                                unsigned phase, uint64_t *byte_window, uint64_t *word_window,
                                uint64_t *leading_zero, unsigned char *wide_window)
{
    const size_t byte_bytes = (size_t)BYTE_WINDOWS * BYTE_BINS * sizeof(unsigned long long);
    const size_t word_bytes = (size_t)WORD_WINDOWS * WORD_BINS * sizeof(unsigned long long);
    const size_t zero_bytes = 257u * sizeof(unsigned long long);
    const size_t wide_bytes = (size_t)1u << 32;

    unsigned long long *device_byte = nullptr;
    unsigned long long *device_word = nullptr;
    unsigned long long *device_zero = nullptr;
    unsigned int *device_wide = nullptr;
    cudaError_t status = cudaSuccess;

    status = cudaMalloc((void **)&device_byte, byte_bytes);
    if (status != cudaSuccess)
    {
        return complain("byte window allocation", status);
    }
    status = cudaMalloc((void **)&device_word, word_bytes);
    if (status != cudaSuccess)
    {
        cudaFree(device_byte);
        return complain("word window allocation", status);
    }
    status = cudaMalloc((void **)&device_zero, zero_bytes);
    if (status != cudaSuccess)
    {
        cudaFree(device_byte);
        cudaFree(device_word);
        return complain("leading zero allocation", status);
    }

    cudaMemset(device_byte, 0, byte_bytes);
    cudaMemset(device_word, 0, word_bytes);
    cudaMemset(device_zero, 0, zero_bytes);

    if (wide_window != nullptr)
    {
        status = cudaMalloc((void **)&device_wide, wide_bytes);
        if (status != cudaSuccess)
        {
            cudaFree(device_byte);
            cudaFree(device_word);
            cudaFree(device_zero);
            // Failing loudly instead of carrying on without the family, because a family that is
            // silently absent reads exactly like a family that measured nothing.
            return complain("four gigabyte wide window allocation", status);
        }
        cudaMemset(device_wide, 0, wide_bytes);
    }

    const unsigned threads = 256u;
    const unsigned blocks = 4096u;
    count_nonces<<<blocks, threads>>>(*job, source, 0ull, domain, phase, device_byte, device_word,
                                      device_zero, device_wide);

    status = cudaDeviceSynchronize();
    if (status != cudaSuccess)
    {
        cudaFree(device_byte);
        cudaFree(device_word);
        cudaFree(device_zero);
        cudaFree(device_wide);
        return complain("kernel", status);
    }

    // Read back into scratch and add, because the contract says these counters accumulate.
    unsigned long long *scratch = new unsigned long long[(size_t)WORD_WINDOWS * WORD_BINS];

    cudaMemcpy(scratch, device_byte, byte_bytes, cudaMemcpyDeviceToHost);
    for (size_t slot = 0u; slot < ((size_t)BYTE_WINDOWS * BYTE_BINS); slot += 1u)
    {
        byte_window[slot] += (uint64_t)scratch[slot];
    }

    cudaMemcpy(scratch, device_word, word_bytes, cudaMemcpyDeviceToHost);
    for (size_t slot = 0u; slot < ((size_t)WORD_WINDOWS * WORD_BINS); slot += 1u)
    {
        word_window[slot] += (uint64_t)scratch[slot];
    }

    cudaMemcpy(scratch, device_zero, zero_bytes, cudaMemcpyDeviceToHost);
    for (size_t slot = 0u; slot < 257u; slot += 1u)
    {
        leading_zero[slot] += (uint64_t)scratch[slot];
    }

    delete[] scratch;

    if (wide_window != nullptr)
    {
        status = cudaMemcpy(wide_window, device_wide, wide_bytes, cudaMemcpyDeviceToHost);
        if (status != cudaSuccess)
        {
            cudaFree(device_byte);
            cudaFree(device_word);
            cudaFree(device_zero);
            cudaFree(device_wide);
            return complain("wide window read back", status);
        }
    }

    cudaFree(device_byte);
    cudaFree(device_word);
    cudaFree(device_zero);
    cudaFree(device_wide);
    return 1;
}
