/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file cuda_miner.cu
 * @brief The same SHA-256 and the same anchor, one nonce per thread on the device.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note This arm has to agree with the two CPU arms exactly. It is validated against the same
 *       published blocks, so a disagreement is a defect and not a tradeoff.
 * @note The anchor is worth more here than on the CPU, for a reason that is about the machine and
 *       not about the mathematics. A warp is thirty-two threads on one instruction pointer, so a
 *       branch only costs what its taken lanes cost. The anchor clears every lane in a warp with
 *       probability near one, which turns the exact compare from a per-nonce cost into a per-warp
 *       one. Section 2.2 of anchor-sift.md still only promises soundness; the saving is the
 *       hardware's.
 */

#include "cuda_miner.h"

#include <cstdio>
#include <vector>

/** @brief Rounds of the first block that no nonce can reach, hoisted onto the host. */
#define SHARED_ROUNDS 3

/** @brief Schedule words of the first block that no nonce can reach. */
#define SHARED_SCHEDULE 18

/**
 * @brief The standard's round constants.
 *
 * @note One definition, copied to the device symbol at context creation. The host arm needs these
 *       to compute the shared rounds and a __constant__ array cannot be read from the host, so the
 *       alternative was a second copy of the table - which is the shape of thing that gets edited
 *       once and disagrees forever.
 */
static const uint32_t s_round_constant[64] = {
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

/** @brief The same constants on the device, filled from the host table at creation. */
__constant__ uint32_t d_round_constant[64];

/** @brief The standard's initial chaining value. */
__constant__ uint32_t d_initial_state[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                                            0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};

/** @brief Rotates right, which the device does in one instruction. */
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
#define DEVICE_ROUND(state_a_, state_b_, state_c_, state_d_, state_e_, state_f_, state_g_,       \
                     state_h_, round_, schedule_word_)                                           \
    do                                                                                           \
    {                                                                                            \
        const uint32_t mix_high = rotate_right(state_e_, 6u) ^ rotate_right(state_e_, 11u) ^     \
                                  rotate_right(state_e_, 25u);                                   \
        const uint32_t choose = state_g_ ^ (state_e_ & (state_f_ ^ state_g_));                   \
        const uint32_t carry_one =                                                               \
            state_h_ + mix_high + choose + d_round_constant[round_] + (schedule_word_);          \
        const uint32_t mix_low = rotate_right(state_a_, 2u) ^ rotate_right(state_a_, 13u) ^      \
                                 rotate_right(state_a_, 22u);                                    \
        const uint32_t majority = (state_a_ & state_b_) | (state_c_ & (state_a_ ^ state_b_));    \
        state_h_ = state_g_;                                                                     \
        state_g_ = state_f_;                                                                     \
        state_f_ = state_e_;                                                                     \
        state_e_ = state_d_ + carry_one;                                                         \
        state_d_ = state_c_;                                                                     \
        state_c_ = state_b_;                                                                     \
        state_b_ = state_a_;                                                                     \
        state_a_ = carry_one + mix_low + majority;                                               \
    } while (0)

/**
 * @brief Rounds of the second block that must run before the anchor word can be read.
 *
 * @note The round moves e to f to g to h, so the final word seven is the e of sixty-one rounds:
 *       S64[7] = S63[6] = S62[5] = S61[4]. The last three rounds cannot change what the anchor
 *       tests, so they are run only for a nonce that survives it - one in four billion.
 * @note Round r reads schedule[r], so the schedule is expanded to ANCHOR_ROUNDS-1 before the rounds
 *       and the rest only on the surviving path.
 */
#define ANCHOR_ROUNDS 61

/**
 * @brief Compresses one block into a chaining value held in registers.
 *
 * @param[in,out] state    Eight chaining words, advanced in place [BORROWS].
 * @param[in,out] schedule Sixteen message words on entry, expanded to sixty-four here [BORROWS].
 */
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

/**
 * @brief Scans a nonce range, one nonce per thread.
 *
 * @param[in]     parameters   Header tail, midstate and threshold [BORROWS].
 * @param[in]     nonce_base   First nonce this launch covers.
 * @param[in]     nonce_count  How many nonces this launch covers.
 * @param[in,out] found_count  Count of winners written so far [BORROWS].
 * @param[out]    found_nonces Where winners land [BORROWS].
 * @param[in]     found_limit  How many winners the buffer holds.
 */
__global__ void scan_nonces(CudaScanParameters parameters, uint32_t nonce_base,
                            uint32_t nonce_count, uint32_t *found_count, uint32_t *found_nonces,
                            uint32_t found_limit, unsigned long long *anchor_survivors)
{
    const uint32_t index = (blockIdx.x * blockDim.x) + threadIdx.x;

    if (index >= nonce_count)
    {
        return;
    }
    const uint32_t nonce = nonce_base + index;

    uint32_t schedule[64];
    uint32_t state[8];

    schedule[0] = parameters.merkle_root_tail;
    schedule[1] = parameters.ntime;
    schedule[2] = parameters.nbits;
    // The header stores the nonce little-endian and SHA-256 reads its message big-endian, so the
    // scheduled word is the nonce byte-reversed. __byte_perm does that in one instruction.
    schedule[3] = __byte_perm(nonce, 0u, 0x0123u);
    schedule[4] = 0x80000000u;
#pragma unroll
    for (int slot = 5; slot < 15; slot += 1)
    {
        schedule[slot] = 0u;
    }
    schedule[15] = 0x00000280u;

    // The first block, resumed past the rounds and schedule words no nonce reaches. Those were
    // computed once on the host; every thread used to redo them identically.
    schedule[16] = parameters.shared_schedule[0];
    schedule[17] = parameters.shared_schedule[1];

#pragma unroll
    for (int slot = SHARED_SCHEDULE; slot < 64; slot += 1)
    {
        schedule[slot] = spread_high(schedule[slot - 2]) + schedule[slot - 7] +
                         spread_low(schedule[slot - 15]) + schedule[slot - 16];
    }

    uint32_t first_a = parameters.shared_state[0];
    uint32_t first_b = parameters.shared_state[1];
    uint32_t first_c = parameters.shared_state[2];
    uint32_t first_d = parameters.shared_state[3];
    uint32_t first_e = parameters.shared_state[4];
    uint32_t first_f = parameters.shared_state[5];
    uint32_t first_g = parameters.shared_state[6];
    uint32_t first_h = parameters.shared_state[7];

#pragma unroll
    for (int round = SHARED_ROUNDS; round < 64; round += 1)
    {
        DEVICE_ROUND(first_a, first_b, first_c, first_d, first_e, first_f, first_g, first_h, round,
                     schedule[round]);
    }

    // Davies-Meyer adds the value the block started from, which is the midstate and not the state
    // the shared rounds advanced to. Adding the advanced one would give a digest wrong for almost
    // every nonce equally, which the anchor could not see.
    state[0] = parameters.midstate[0] + first_a;
    state[1] = parameters.midstate[1] + first_b;
    state[2] = parameters.midstate[2] + first_c;
    state[3] = parameters.midstate[3] + first_d;
    state[4] = parameters.midstate[4] + first_e;
    state[5] = parameters.midstate[5] + first_f;
    state[6] = parameters.midstate[6] + first_g;
    state[7] = parameters.midstate[7] + first_h;

    // The first hash's chaining value becomes the second hash's message, in place.
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

    // The second block, stopped where the anchor can already be read. The round moves e to f to g
    // to h, so the final word seven is the e of ANCHOR_ROUNDS rounds and the last three rounds
    // cannot change it. They are run only for a nonce that survives, which is one in four billion.
    //
    // Round r reads schedule[r], so rounds 0 through ANCHOR_ROUNDS-1 want the schedule expanded to
    // ANCHOR_ROUNDS-1 and no further.
#pragma unroll
    for (int slot = 16; slot < ANCHOR_ROUNDS; slot += 1)
    {
        schedule[slot] = spread_high(schedule[slot - 2]) + schedule[slot - 7] +
                         spread_low(schedule[slot - 15]) + schedule[slot - 16];
    }

    uint32_t pass_a = state[0];
    uint32_t pass_b = state[1];
    uint32_t pass_c = state[2];
    uint32_t pass_d = state[3];
    uint32_t pass_e = state[4];
    uint32_t pass_f = state[5];
    uint32_t pass_g = state[6];
    uint32_t pass_h = state[7];

#pragma unroll
    for (int round = 0; round < ANCHOR_ROUNDS; round += 1)
    {
        DEVICE_ROUND(pass_a, pass_b, pass_c, pass_d, pass_e, pass_f, pass_g, pass_h, round,
                     schedule[round]);
    }

    // The anchor. Section 2.2 makes this refusal exact and final, and a warp whose thirty-two lanes
    // all refuse skips the compare entirely instead of serializing through it.
    if (parameters.anchor_is_sound != 0u)
    {
        if ((state[7] + pass_e) != 0u)
        {
            return;
        }

        // Counted so the device reports the same diagnostic the CPU arm does. Surviving is a one in
        // four billion event, so this atomic fires about once per four billion nonces and costs
        // nothing measurable. Without it the client had to report the winner count under the
        // anchor's name, which is a different quantity and made the device look as though it were
        // finding no survivors at all.
        if (anchor_survivors != nullptr)
        {
            atomicAdd(anchor_survivors, 1ull);
        }
    }

    // Only a survivor gets here, so the three rounds the anchor could not read are finished now
    // instead of for every nonce. The whole digest is wanted from here on, not one word of it.
#pragma unroll
    for (int slot = ANCHOR_ROUNDS; slot < 64; slot += 1)
    {
        schedule[slot] = spread_high(schedule[slot - 2]) + schedule[slot - 7] +
                         spread_low(schedule[slot - 15]) + schedule[slot - 16];
    }
#pragma unroll
    for (int round = ANCHOR_ROUNDS; round < 64; round += 1)
    {
        DEVICE_ROUND(pass_a, pass_b, pass_c, pass_d, pass_e, pass_f, pass_g, pass_h, round,
                     schedule[round]);
    }

    state[0] += pass_a;
    state[1] += pass_b;
    state[2] += pass_c;
    state[3] += pass_d;
    state[4] += pass_e;
    state[5] += pass_f;
    state[6] += pass_g;
    state[7] += pass_h;

    // Section 2.3: surviving proves nothing, so order the whole digest against the threshold.
#pragma unroll
    for (int rank = 0; rank < 8; rank += 1)
    {
        const uint32_t digest_word = __byte_perm(state[7 - rank], 0u, 0x0123u);

        if (digest_word != parameters.share_target[rank])
        {
            if (digest_word > parameters.share_target[rank])
            {
                return;
            }
            break;
        }
    }

    const uint32_t slot = atomicAdd(found_count, 1u);
    if (slot < found_limit)
    {
        found_nonces[slot] = nonce;
    }
}

/** @brief Warps per survey block. Each keeps its own counter row so no atomic is needed inside. */
#define SURVEY_WARPS 8u

/** @brief Threads per survey block. */
#define SURVEY_THREADS (SURVEY_WARPS * 32u)

/**
 * @brief Hashes a nonce and returns the digest words in protocol order, most significant first.
 *
 * @param[in]  parameters Header tail and midstate [BORROWS].
 * @param[in]  nonce      The nonce to hash.
 * @param[out] ordered    Eight words, most significant first [BORROWS].
 */
__device__ __forceinline__ void digest_for_nonce(const CudaScanParameters &parameters,
                                                 uint32_t nonce, uint32_t *ordered)
{
    uint32_t schedule[64];
    uint32_t state[8];

#pragma unroll
    for (int slot = 0; slot < 8; slot += 1)
    {
        state[slot] = parameters.midstate[slot];
    }
    schedule[0] = parameters.merkle_root_tail;
    schedule[1] = parameters.ntime;
    schedule[2] = parameters.nbits;
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

    // The protocol reads the digest little-endian, so state word seven byte-reversed is the most
    // significant word of the number. Ordering here makes bit index zero the leading bit.
#pragma unroll
    for (int rank = 0; rank < 8; rank += 1)
    {
        ordered[rank] = __byte_perm(state[7 - rank], 0u, 0x0123u);
    }
}

/**
 * @brief Surveys a nonce range, counting every digest bit without early exit.
 *
 * @param[in]     parameters  Header tail and midstate [BORROWS].
 * @param[in]     nonce_base  First nonce.
 * @param[in]     nonce_count How many.
 * @param[in,out] bit_counts  256 global counters [BORROWS].
 * @param[in,out] zero_counts 33 global counters [BORROWS].
 * @note Counting is done with warp ballots instead of per-thread atomics. One ballot per bit
 *       position gives all 32 lanes at once, so a digest costs eight ballots per thread instead of
 *       256 atomic adds. Each warp owns a counter row, so nothing inside the block contends.
 */
__global__ void survey_nonces(CudaScanParameters parameters, uint32_t nonce_base,
                              uint32_t nonce_count, unsigned long long *bit_counts,
                              unsigned long long *zero_counts)
{
    __shared__ uint32_t warp_bits[SURVEY_WARPS][256];
    __shared__ uint32_t warp_zeros[SURVEY_WARPS][33];

    const unsigned lane = threadIdx.x & 31u;
    const unsigned warp = threadIdx.x >> 5;

    for (unsigned slot = lane; slot < 256u; slot += 32u)
    {
        warp_bits[warp][slot] = 0u;
    }
    for (unsigned slot = lane; slot < 33u; slot += 32u)
    {
        warp_zeros[warp][slot] = 0u;
    }
    __syncthreads();

    const uint32_t stride = gridDim.x * blockDim.x;
    const uint32_t start = (blockIdx.x * blockDim.x) + threadIdx.x;
    // The trip count is uniform across the warp on purpose. A grid-stride loop whose bound depends
    // on the lane leaves some lanes exited at the tail, and __ballot_sync with a full mask is
    // undefined once that happens. Every lane runs every iteration and an out-of-range lane simply
    // contributes a zero bit.
    // Rounding up is done in sixty-four bits on purpose. At a nonce_count near the top of the
    // range, nonce_count + stride - 1 wraps in thirty-two and the wrapped sum divided by the
    // stride is zero, so every lane exits before doing any work. The host still credits the full
    // nonce_count, so the run reports a bit map and a histogram of all zeros and looks, from
    // outside, exactly like one that completed. Measured: a survey of 4294967295 nonces returned
    // every counter at zero, while 2147483648 returned correct counts.
    const uint64_t iterations = (((uint64_t)nonce_count + (uint64_t)stride) - 1ull) / stride;

    for (uint64_t step = 0ull; step < iterations; step += 1ull)
    {
        const uint64_t reach = ((uint64_t)start) + (step * (uint64_t)stride);
        const bool active = (reach < (uint64_t)nonce_count);
        // Narrowing is safe only where the lane is active, and an inactive lane never reads index.
        const uint32_t index = (uint32_t)reach;
        uint32_t ordered[8] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};

        if (active)
        {
            digest_for_nonce(parameters, nonce_base + index, ordered);
        }

        // One ballot per bit position collects all 32 lanes, and only lane zero accumulates.
#pragma unroll
        for (int rank = 0; rank < 8; rank += 1)
        {
#pragma unroll
            for (int bit = 0; bit < 32; bit += 1)
            {
                const unsigned set = active ? ((ordered[rank] >> (31 - bit)) & 1u) : 0u;
                const unsigned mask = __ballot_sync(0xFFFFFFFFu, set != 0u);

                if (lane == 0u)
                {
                    warp_bits[warp][(rank * 32) + bit] += (uint32_t)__popc((int)mask);
                }
            }
        }

        if (active)
        {
            unsigned leading = 0u;
#pragma unroll
            for (int rank = 0; rank < 8; rank += 1)
            {
                if (ordered[rank] != 0u)
                {
                    leading += (unsigned)__clz((int)ordered[rank]);
                    break;
                }
                leading += 32u;
            }
            for (unsigned width = 0u; (width <= 32u) && (width <= leading); width += 1u)
            {
                atomicAdd(&warp_zeros[warp][width], 1u);
            }
        }
    }
    __syncthreads();

    // One flush per block, so the global counters see a few hundred adds instead of billions.
    for (unsigned slot = threadIdx.x; slot < 256u; slot += blockDim.x)
    {
        unsigned long long total = 0u;
        for (unsigned row = 0u; row < SURVEY_WARPS; row += 1u)
        {
            total += warp_bits[row][slot];
        }
        if (total != 0u)
        {
            atomicAdd(&bit_counts[slot], total);
        }
    }
    for (unsigned slot = threadIdx.x; slot < 33u; slot += blockDim.x)
    {
        unsigned long long total = 0u;
        for (unsigned row = 0u; row < SURVEY_WARPS; row += 1u)
        {
            total += warp_zeros[row][slot];
        }
        if (total != 0u)
        {
            atomicAdd(&zero_counts[slot], total);
        }
    }
}

/**
 * @brief Salts a nonce and measures which output bits respond, which is the keyhole scan.
 *
 * @param[in]     parameters   Header tail and midstate [BORROWS].
 * @param[in]     nonce_base   First nonce.
 * @param[in]     nonce_count  How many.
 * @param[in]     salt         The input difference applied to the nonce.
 * @param[in]     rounds_first Rounds to run in the first compression, 64 for the real function.
 * @param[in,out] bit_counts   256 counters, one per output bit, counting differences that were set.
 * @note A keyhole is an output position whose difference bit is not a fair coin under a fixed input
 *       salt. This counts exactly that, for one salt, over a whole range.
 */
__global__ void keyhole_scan(CudaScanParameters parameters, uint32_t nonce_base,
                             uint32_t nonce_count, uint32_t salt,
                             unsigned long long *bit_counts)
{
    __shared__ uint32_t warp_bits[SURVEY_WARPS][256];

    const unsigned lane = threadIdx.x & 31u;
    const unsigned warp = threadIdx.x >> 5;

    for (unsigned slot = lane; slot < 256u; slot += 32u)
    {
        warp_bits[warp][slot] = 0u;
    }
    __syncthreads();

    const uint32_t stride = gridDim.x * blockDim.x;
    const uint32_t start = (blockIdx.x * blockDim.x) + threadIdx.x;
    // Uniform trip count, for the reason survey_nonces states: a ballot needs every lane present.
    // Rounding up is done in sixty-four bits on purpose. At a nonce_count near the top of the
    // range, nonce_count + stride - 1 wraps in thirty-two and the wrapped sum divided by the
    // stride is zero, so every lane exits before doing any work. The host still credits the full
    // nonce_count, so the run reports a bit map and a histogram of all zeros and looks, from
    // outside, exactly like one that completed. Measured: a survey of 4294967295 nonces returned
    // every counter at zero, while 2147483648 returned correct counts.
    const uint64_t iterations = (((uint64_t)nonce_count + (uint64_t)stride) - 1ull) / stride;

    for (uint64_t step = 0ull; step < iterations; step += 1ull)
    {
        const uint64_t reach = ((uint64_t)start) + (step * (uint64_t)stride);
        const bool active = (reach < (uint64_t)nonce_count);
        // Narrowing is safe only where the lane is active, and an inactive lane never reads index.
        const uint32_t index = (uint32_t)reach;
        uint32_t plain[8] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
        uint32_t salted[8] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};

        if (active)
        {
            const uint32_t nonce = nonce_base + index;
            digest_for_nonce(parameters, nonce, plain);
            digest_for_nonce(parameters, nonce ^ salt, salted);
        }

#pragma unroll
        for (int rank = 0; rank < 8; rank += 1)
        {
            const uint32_t difference = plain[rank] ^ salted[rank];
#pragma unroll
            for (int bit = 0; bit < 32; bit += 1)
            {
                const unsigned set = active ? ((difference >> (31 - bit)) & 1u) : 0u;
                const unsigned mask = __ballot_sync(0xFFFFFFFFu, set != 0u);

                if (lane == 0u)
                {
                    warp_bits[warp][(rank * 32) + bit] += (uint32_t)__popc((int)mask);
                }
            }
        }
    }
    __syncthreads();

    for (unsigned slot = threadIdx.x; slot < 256u; slot += blockDim.x)
    {
        unsigned long long total = 0u;
        for (unsigned row = 0u; row < SURVEY_WARPS; row += 1u)
        {
            total += warp_bits[row][slot];
        }
        if (total != 0u)
        {
            atomicAdd(&bit_counts[slot], total);
        }
    }
}

// -------------------------------------------------------------------------------------------
// Host side
// -------------------------------------------------------------------------------------------

/** @brief Device allocations reused across launches. */
struct CudaMinerContext
{
    uint32_t *found_count = nullptr;
    uint32_t *found_nonces = nullptr;
    uint32_t found_limit = 0u;
    cudaStream_t stream = nullptr;

    /** @brief Device counter for nonces that cleared the anchor in the last scan. */
    unsigned long long *anchor_survivors = nullptr;

    /** @brief What that counter read after the last scan, on the host. */
    unsigned long long last_anchor_survivors = 0u;
};

/** @brief Rotates right on the host, matching the device's funnel shift. */
static uint32_t host_rotate_right(uint32_t value, unsigned distance)
{
    return (value >> distance) | (value << (32u - distance));
}

/**
 * @brief Computes the part of the first block that is the same for every nonce.
 *
 * @param[in,out] parameters The launch parameters, whose shared fields are filled [BORROWS].
 * @note Done once per launch instead of once per thread. Every thread was computing these three
 *       rounds and two schedule words identically, which at fifteen hundred threads per SM is the
 *       same work repeated across the whole device.
 * @note The nonce is message word three, so rounds zero through two read only words no nonce
 *       touches, and schedule words sixteen and seventeen draw on none of it either. Word eighteen
 *       is the first that does.
 */
static void fill_shared_front(CudaScanParameters *parameters)
{
    uint32_t schedule[SHARED_SCHEDULE];

    schedule[0] = parameters->merkle_root_tail;
    schedule[1] = parameters->ntime;
    schedule[2] = parameters->nbits;
    schedule[3] = 0u;   // The nonce, which no shared quantity depends on.
    schedule[4] = 0x80000000u;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        schedule[slot] = 0u;
    }
    schedule[15] = 0x00000280u;

    for (unsigned slot = 16u; slot < SHARED_SCHEDULE; slot += 1u)
    {
        const uint32_t back_fifteen = schedule[slot - 15u];
        const uint32_t back_two = schedule[slot - 2u];
        const uint32_t low = host_rotate_right(back_fifteen, 7u) ^
                             host_rotate_right(back_fifteen, 18u) ^ (back_fifteen >> 3u);
        const uint32_t high = host_rotate_right(back_two, 17u) ^
                              host_rotate_right(back_two, 19u) ^ (back_two >> 10u);
        schedule[slot] = high + schedule[slot - 7u] + low + schedule[slot - 16u];
    }
    parameters->shared_schedule[0] = schedule[16];
    parameters->shared_schedule[1] = schedule[17];

    uint32_t state_a = parameters->midstate[0];
    uint32_t state_b = parameters->midstate[1];
    uint32_t state_c = parameters->midstate[2];
    uint32_t state_d = parameters->midstate[3];
    uint32_t state_e = parameters->midstate[4];
    uint32_t state_f = parameters->midstate[5];
    uint32_t state_g = parameters->midstate[6];
    uint32_t state_h = parameters->midstate[7];

    for (unsigned round = 0u; round < SHARED_ROUNDS; round += 1u)
    {
        const uint32_t mix_high = host_rotate_right(state_e, 6u) ^
                                  host_rotate_right(state_e, 11u) ^
                                  host_rotate_right(state_e, 25u);
        const uint32_t choose = state_g ^ (state_e & (state_f ^ state_g));
        const uint32_t carry_one =
            state_h + mix_high + choose + s_round_constant[round] + schedule[round];
        const uint32_t mix_low = host_rotate_right(state_a, 2u) ^
                                 host_rotate_right(state_a, 13u) ^
                                 host_rotate_right(state_a, 22u);
        const uint32_t majority = (state_a & state_b) | (state_c & (state_a ^ state_b));

        state_h = state_g;
        state_g = state_f;
        state_f = state_e;
        state_e = state_d + carry_one;
        state_d = state_c;
        state_c = state_b;
        state_b = state_a;
        state_a = carry_one + mix_low + majority;
    }

    parameters->shared_state[0] = state_a;
    parameters->shared_state[1] = state_b;
    parameters->shared_state[2] = state_c;
    parameters->shared_state[3] = state_d;
    parameters->shared_state[4] = state_e;
    parameters->shared_state[5] = state_f;
    parameters->shared_state[6] = state_g;
    parameters->shared_state[7] = state_h;
}

CudaMinerContext *cuda_miner_create(uint32_t found_limit)
{
    CudaMinerContext *context = new CudaMinerContext();

    // One definition of the table, uploaded here, because the host arm needs to read it too and a
    // __constant__ array cannot be read from the host.
    if (cudaMemcpyToSymbol(d_round_constant, s_round_constant, sizeof(s_round_constant)) !=
        cudaSuccess)
    {
        delete context;
        return nullptr;
    }

    context->found_limit = found_limit;
    if (cudaMalloc(&context->found_count, sizeof(uint32_t)) != cudaSuccess)
    {
        delete context;
        return nullptr;
    }
    if (cudaMalloc(&context->found_nonces, found_limit * sizeof(uint32_t)) != cudaSuccess)
    {
        cudaFree(context->found_count);
        delete context;
        return nullptr;
    }
    if (cudaMalloc(&context->anchor_survivors, sizeof(unsigned long long)) != cudaSuccess)
    {
        cudaFree(context->found_nonces);
        cudaFree(context->found_count);
        delete context;
        return nullptr;
    }
    if (cudaStreamCreate(&context->stream) != cudaSuccess)
    {
        cudaFree(context->anchor_survivors);
        cudaFree(context->found_nonces);
        cudaFree(context->found_count);
        delete context;
        return nullptr;
    }
    return context;
}

void cuda_miner_destroy(CudaMinerContext *context)
{
    if (context == nullptr)
    {
        return;
    }
    cudaStreamDestroy(context->stream);
    cudaFree(context->anchor_survivors);
    cudaFree(context->found_nonces);
    cudaFree(context->found_count);
    delete context;
}

unsigned long long cuda_miner_anchor_survivors(const CudaMinerContext *context)
{
    return (context != nullptr) ? context->last_anchor_survivors : 0ull;
}

int cuda_miner_scan(CudaMinerContext *context, const CudaScanParameters *parameters,
                    uint32_t nonce_base, uint32_t nonce_count, uint32_t *found_nonces,
                    uint32_t *found_count)
{
    if ((context == nullptr) || (parameters == nullptr))
    {
        return 0;
    }

    const uint32_t threads_per_block = 256u;
    const uint32_t blocks = (nonce_count + threads_per_block - 1u) / threads_per_block;

    if (cudaMemsetAsync(context->found_count, 0, sizeof(uint32_t), context->stream) != cudaSuccess)
    {
        return 0;
    }

    if (cudaMemsetAsync(context->anchor_survivors, 0, sizeof(unsigned long long),
                        context->stream) != cudaSuccess)
    {
        return 0;
    }

    // Filled here instead of by the caller, so every existing call site gets the saving without
    // knowing about it and none of them can forget to.
    CudaScanParameters launched = *parameters;
    fill_shared_front(&launched);

    scan_nonces<<<blocks, threads_per_block, 0, context->stream>>>(
        launched, nonce_base, nonce_count, context->found_count, context->found_nonces,
        context->found_limit, context->anchor_survivors);

    uint32_t host_count = 0u;
    if (cudaMemcpyAsync(&host_count, context->found_count, sizeof(uint32_t),
                        cudaMemcpyDeviceToHost, context->stream) != cudaSuccess)
    {
        return 0;
    }
    context->last_anchor_survivors = 0u;
    if (cudaMemcpyAsync(&context->last_anchor_survivors, context->anchor_survivors,
                        sizeof(unsigned long long), cudaMemcpyDeviceToHost,
                        context->stream) != cudaSuccess)
    {
        return 0;
    }
    if (cudaStreamSynchronize(context->stream) != cudaSuccess)
    {
        return 0;
    }

    const cudaError_t status = cudaGetLastError();
    if (status != cudaSuccess)
    {
        std::printf("[cuda] kernel failed: %s\n", cudaGetErrorString(status));
        return 0;
    }

    const uint32_t copied = (host_count < context->found_limit) ? host_count : context->found_limit;
    if (copied > 0u)
    {
        if (cudaMemcpy(found_nonces, context->found_nonces, copied * sizeof(uint32_t),
                       cudaMemcpyDeviceToHost) != cudaSuccess)
        {
            return 0;
        }
    }
    *found_count = copied;
    return 1;
}

/**
 * @brief A stream owned by the survey paths, so they never synchronise the whole device.
 *
 * @note WHY THIS EXISTS. These paths previously launched on the DEFAULT stream and then called
 *       cudaDeviceSynchronize, and both of those serialise against every other consumer of the
 *       card. The default stream has implicit synchronising semantics with all blocking streams,
 *       and a device-wide synchronise waits on every stream in every context, so a survey running
 *       here would stall an unrelated kernel belonging to somebody else. The hot mining path was
 *       always correct: it owns context->stream and waits with cudaStreamSynchronize.
 * @note Created once on first use and never destroyed, which is deliberate. A stream is a handle
 *       and the process holds one for its lifetime; tearing it down per survey would cost an
 *       implicit synchronise and reintroduce exactly what this removes.
 */
static cudaStream_t survey_stream()
{
    static cudaStream_t held = nullptr;
    if (held == nullptr)
    {
        if (cudaStreamCreate(&held) != cudaSuccess)
        {
            // Falling back to the default stream keeps the survey CORRECT and merely serialising,
            // which is the right direction to fail: a wrong count would be worse than a slow one.
            held = nullptr;
        }
    }
    return held;
}

/**
 * @brief Runs one accumulating kernel and folds its counters into a host array.
 *
 * @param[in]     counter_count How many counters the kernel writes.
 * @param[in,out] destination   Host counters, added to [BORROWS].
 * @param[in]     launch        Callable that launches the kernel given the device pointer and the
 *                              stream it must launch on.
 * @return                      Nonzero on success.
 */
template <typename Launch>
static int accumulate_counters(unsigned counter_count, unsigned long long *destination,
                               Launch launch)
{
    unsigned long long *device_counters = nullptr;
    const cudaStream_t stream = survey_stream();

    if (cudaMalloc(&device_counters, counter_count * sizeof(unsigned long long)) != cudaSuccess)
    {
        return 0;
    }
    // Async on the survey's own stream. The synchronous cudaMemset synchronises the device on some
    // drivers, which is the same stall this change exists to remove.
    if (cudaMemsetAsync(device_counters, 0, counter_count * sizeof(unsigned long long),
                        stream) != cudaSuccess)
    {
        cudaFree(device_counters);
        return 0;
    }

    launch(device_counters, stream);

    // STREAM SCOPED AND NOT DEVICE WIDE. cudaDeviceSynchronize waits on every stream in every
    // context, so calling it here stalled any unrelated work sharing the card. Waiting on this
    // stream alone is the same guarantee for this kernel and no guarantee about anybody else's,
    // which is what allows the interleaving.
    if (cudaStreamSynchronize(stream) != cudaSuccess)
    {
        cudaFree(device_counters);
        return 0;
    }
    const cudaError_t status = cudaGetLastError();
    if (status != cudaSuccess)
    {
        std::printf("[cuda] kernel failed: %s\n", cudaGetErrorString(status));
        cudaFree(device_counters);
        return 0;
    }

    std::vector<unsigned long long> host_counters(counter_count, 0u);
    if (cudaMemcpy(host_counters.data(), device_counters,
                   counter_count * sizeof(unsigned long long),
                   cudaMemcpyDeviceToHost) != cudaSuccess)
    {
        cudaFree(device_counters);
        return 0;
    }
    cudaFree(device_counters);

    for (unsigned slot = 0u; slot < counter_count; slot += 1u)
    {
        destination[slot] += host_counters[slot];
    }
    return 1;
}

/** @brief Blocks to launch for the accumulating kernels, sized to the device. */
static unsigned survey_block_count()
{
    cudaDeviceProp properties;

    if (cudaGetDeviceProperties(&properties, 0) != cudaSuccess)
    {
        return 256u;
    }
    // Enough blocks to fill every multiprocessor several times over, and few enough that the final
    // flush is a few hundred atomic adds instead of millions.
    return (unsigned)properties.multiProcessorCount * 8u;
}

int cuda_miner_survey(CudaMinerContext *context, const CudaScanParameters *parameters,
                      uint32_t nonce_base, uint32_t nonce_count, CudaSurvey *survey)
{
    (void)context;
    if ((parameters == nullptr) || (survey == nullptr))
    {
        return 0;
    }

    const unsigned blocks = survey_block_count();
    unsigned long long bit_counts[256] = {0u};
    unsigned long long zero_counts[33] = {0u};

    if (accumulate_counters(256u, bit_counts,
                            [&](unsigned long long *device_bits, cudaStream_t stream) {
            unsigned long long *device_zeros = nullptr;
            cudaMalloc(&device_zeros, 33u * sizeof(unsigned long long));
            cudaMemsetAsync(device_zeros, 0, 33u * sizeof(unsigned long long), stream);
            survey_nonces<<<blocks, SURVEY_THREADS, 0, stream>>>(*parameters, nonce_base,
                                                                 nonce_count, device_bits,
                                                                 device_zeros);
            cudaMemcpyAsync(zero_counts, device_zeros, 33u * sizeof(unsigned long long),
                            cudaMemcpyDeviceToHost, stream);
            // This lambda frees device_zeros, so it must wait for its own work before doing so.
            // Stream scoped: waiting on the device here would defeat the whole change.
            cudaStreamSynchronize(stream);
            cudaFree(device_zeros);
        }) == 0)
    {
        return 0;
    }

    survey->nonces_evaluated += (unsigned long long)nonce_count;
    for (unsigned slot = 0u; slot < 256u; slot += 1u)
    {
        survey->bit_one_count[slot] += bit_counts[slot];
    }
    for (unsigned slot = 0u; slot < 33u; slot += 1u)
    {
        survey->leading_zero_count[slot] += zero_counts[slot];
    }
    return 1;
}

int cuda_miner_keyhole(CudaMinerContext *context, const CudaScanParameters *parameters,
                       uint32_t nonce_base, uint32_t nonce_count, uint32_t salt,
                       unsigned long long *difference_one_count)
{
    (void)context;
    if ((parameters == nullptr) || (difference_one_count == nullptr))
    {
        return 0;
    }

    const unsigned blocks = survey_block_count();
    return accumulate_counters(256u, difference_one_count,
                               [&](unsigned long long *device_bits, cudaStream_t stream) {
        keyhole_scan<<<blocks, SURVEY_THREADS, 0, stream>>>(*parameters, nonce_base, nonce_count,
                                                            salt, device_bits);
    });
}

int cuda_miner_device_report(char *text, size_t text_size)
{
    int device_count = 0;

    if ((cudaGetDeviceCount(&device_count) != cudaSuccess) || (device_count == 0))
    {
        std::snprintf(text, text_size, "no CUDA device");
        return 0;
    }

    cudaDeviceProp properties;
    cudaGetDeviceProperties(&properties, 0);

    int clock_khz = 0;
    cudaDeviceGetAttribute(&clock_khz, cudaDevAttrClockRate, 0);

    std::snprintf(text, text_size, "%s, compute %d.%d, %d SMs, %.2f GHz", properties.name,
                  properties.major, properties.minor, properties.multiProcessorCount,
                  clock_khz / 1.0e6);
    return properties.multiProcessorCount;
}
