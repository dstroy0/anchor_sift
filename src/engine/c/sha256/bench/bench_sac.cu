/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_sac.cu
 * @brief The strict avalanche criterion per round, at a sample deep enough to settle a thin margin.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Vaughn and Borowczak (Cryptography 2026, 10(3), 32) report that SHA-256 satisfies the
 *       strict avalanche criterion from round 23 through 53, *fails it from 54 through 57*, and
 *       satisfies it again from 58. They call the late failure unexpected and attribute it to a
 *       diffusion-dampening effect between sub-functions. A published, measured non-monotonicity in
 *       the diffusion of a function this studied is worth reproducing before it is believed.
 * @note Their margin is thin. The reported SAC value across rounds 54 to 57 is 0.49728 against a
 *       Bonferroni threshold of 0.49734 - six parts in a hundred thousand - at k = 1,000,000 trials
 *       where one standard deviation is 0.0005. That deviation is 5.44 standard deviations at their
 *       sample and would be 54 at a hundred times the trials. So the question is answerable by
 *       sampling harder, which is what a device is for.
 * @note The statistic is theirs, not a near relative of it: a 512 by 256 matrix counting how often
 *       output bit j flips when input bit i of the message block is flipped, and the SAC value is
 *       whichever entry sits furthest from one half. Every other bench in this tree reads per-word
 *       Hamming means instead, which is a different question and would not reproduce their number
 *       whatever SHA-256 does.
 * @note The feedforward is irrelevant here and is not computed. Both members of a pair add the same
 *       chaining value at the end, so it cancels in the exclusive-or exactly.
 */

#include <cuda_runtime.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <vector>

namespace
{

/** @brief Bits in the message block, which is the input side of the SAC matrix. */
const unsigned INPUT_BITS = 512u;

/** @brief Bits in the chaining value, which is the output side. */
const unsigned OUTPUT_BITS = 256u;

__constant__ uint32_t d_constant[64] = {
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

__constant__ uint32_t d_start[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                                    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};

// The same table on the host. The miner arm runs its comparison in ordinary C++ because it is a
// few thousand hashes instead of a few billion, and __constant__ is not reachable from there.
static const uint32_t host_constant[64] = {
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

__device__ __forceinline__ uint32_t turn(uint32_t value, uint32_t by)
{
    return __funnelshift_r(value, value, by);
}

__device__ __forceinline__ uint64_t splitmix(uint64_t &state)
{
    state += 0x9e3779b97f4a7c15ull;
    uint64_t mixed = state;
    mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
    mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
    return mixed ^ (mixed >> 31);
}

/**
 * @brief Runs the compression rounds and leaves the state, without the feedforward.
 *
 * @param[in]  message Sixteen message words [BORROWS].
 * @param[in]  rounds  How many rounds to run.
 * @param[out] state   Eight state words [BORROWS].
 * @note No feedforward, because both members of a SAC pair add the same chaining value and it
 *       cancels in the exclusive-or exactly. Computing it would change nothing and cost eight adds.
 */
/** @brief Which sub-functions a variant keeps, as the published work varies them. */
#define KEEP_SCHEDULE 1u
#define KEEP_MAJORITY 2u
#define KEEP_CHOOSE 4u
#define KEEP_BIG_ZERO 8u
#define KEEP_BIG_ONE 16u
#define KEEP_ADDITION 32u
#define KEEP_CONSTANT 64u
#define KEEP_EVERYTHING 127u

__device__ __forceinline__ void compress_to(const uint32_t *message, unsigned rounds,
                                            uint32_t *state, unsigned keep)
{
    uint32_t schedule[64];
    for (unsigned slot = 0u; slot < 16u; slot += 1u)
    {
        schedule[slot] = message[slot];
    }

    // Without the scheduler the block is simply repeated, which is the substitution the published
    // work uses instead of dropping the expansion and leaving nothing to feed the later rounds.
    if ((keep & KEEP_SCHEDULE) != 0u)
    {
        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            const uint32_t fifteen = schedule[slot - 15u];
            const uint32_t two = schedule[slot - 2u];
            const uint32_t low = turn(fifteen, 7u) ^ turn(fifteen, 18u) ^ (fifteen >> 3u);
            const uint32_t high = turn(two, 17u) ^ turn(two, 19u) ^ (two >> 10u);
            schedule[slot] = ((keep & KEEP_ADDITION) != 0u)
                                 ? (high + schedule[slot - 7u] + low + schedule[slot - 16u])
                                 : (high ^ schedule[slot - 7u] ^ low ^ schedule[slot - 16u]);
        }
    }
    else
    {
        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            schedule[slot] = schedule[slot - 16u];
        }
    }

    uint32_t a = d_start[0], b = d_start[1], c = d_start[2], d = d_start[3];
    uint32_t e = d_start[4], f = d_start[5], g = d_start[6], h = d_start[7];

    for (unsigned round = 0u; round < rounds; round += 1u)
    {
        // Integer addition carries and exclusive-or does not, which is the whole of the difference
        // between them here. Every other sub-function is simply present or absent.
        const uint32_t big_one =
            ((keep & KEEP_BIG_ONE) != 0u) ? (turn(e, 6u) ^ turn(e, 11u) ^ turn(e, 25u)) : 0u;
        const uint32_t choose = ((keep & KEEP_CHOOSE) != 0u) ? (g ^ (e & (f ^ g))) : 0u;
        const uint32_t big_zero =
            ((keep & KEEP_BIG_ZERO) != 0u) ? (turn(a, 2u) ^ turn(a, 13u) ^ turn(a, 22u)) : 0u;
        const uint32_t many = ((keep & KEEP_MAJORITY) != 0u) ? ((a & b) | (c & (a ^ b))) : 0u;
        const uint32_t rounder = ((keep & KEEP_CONSTANT) != 0u) ? d_constant[round] : 0u;

        uint32_t first;
        uint32_t next_e;
        uint32_t next_a;
        if ((keep & KEEP_ADDITION) != 0u)
        {
            first = h + big_one + choose + rounder + schedule[round];
            next_e = d + first;
            next_a = first + big_zero + many;
        }
        else
        {
            first = h ^ big_one ^ choose ^ rounder ^ schedule[round];
            next_e = d ^ first;
            next_a = first ^ big_zero ^ many;
        }

        h = g; g = f; f = e; e = next_e;
        d = c; c = b; b = a; a = next_a;
    }

    state[0] = a; state[1] = b; state[2] = c; state[3] = d;
    state[4] = e; state[5] = f; state[6] = g; state[7] = h;
}

/**
 * @brief Fills one row of the SAC matrix: how often each output bit flips for one input bit.
 *
 * @param[in]     trials How many plaintexts to draw.
 * @param[in]     seed   Stream seed.
 * @param[in]     rounds How many rounds to run.
 * @param[in,out] matrix 512 by 256 counters [BORROWS].
 * @note One block per input bit, so the block's whole working set is the 256 counters of its own
 *       row and they live in shared memory. A thread per (trial, bit) pair over the whole matrix
 *       would need half a megabyte of counters and would make every increment a global atomic.
 */
__global__ void fill_sac_row(uint64_t trials, uint64_t seed, unsigned rounds,
                             unsigned long long *matrix, unsigned keep)
{
    __shared__ unsigned long long tally[OUTPUT_BITS];
    for (unsigned at = threadIdx.x; at < OUTPUT_BITS; at += blockDim.x)
    {
        tally[at] = 0u;
    }
    __syncthreads();

    const unsigned input_bit = blockIdx.x;

    for (uint64_t trial = threadIdx.x; trial < trials; trial += blockDim.x)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull);

        uint32_t message[16];
        uint32_t flipped[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            message[slot] = (uint32_t)splitmix(generator);
            flipped[slot] = message[slot];
        }
        flipped[input_bit / 32u] ^= (1u << (input_bit % 32u));

        uint32_t plain[8];
        uint32_t other[8];
        compress_to(message, rounds, plain, keep);
        compress_to(flipped, rounds, other, keep);

        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            uint32_t apart = plain[slot] ^ other[slot];
            while (apart != 0u)
            {
                const unsigned bit = (unsigned)__ffs((int)apart) - 1u;
                atomicAdd(&tally[(slot * 32u) + bit], 1ull);
                apart &= apart - 1u;
            }
        }
    }
    __syncthreads();

    unsigned long long *const row = &matrix[(size_t)input_bit * OUTPUT_BITS];
    for (unsigned at = threadIdx.x; at < OUTPUT_BITS; at += blockDim.x)
    {
        atomicAdd(&row[at], tally[at]);
    }
}

/**
 * @brief Fills the matrix from randomness instead of from SHA-256, as the chi-square's own null.
 *
 * @param[in]     trials How many draws, matching the real arm.
 * @param[in]     seed   Stream seed.
 * @param[in,out] matrix 512 by 256 counters [BORROWS].
 * @note Same loop, same shared tally, same atomics and the same denominator as fill_sac_row, with
 *       the compression replaced by eight random words. Every cell is then binomial by
 *       construction, so this reads the sum of squared z that the instrument produces when the
 *       answer is known to be zero. A deficit appearing here is the sampler's, not the function's.
 */
__global__ void fill_null_row(uint64_t trials, uint64_t seed, unsigned long long *matrix,
                              unsigned shape)
{
    __shared__ unsigned long long tally[OUTPUT_BITS];
    for (unsigned at = threadIdx.x; at < OUTPUT_BITS; at += blockDim.x)
    {
        tally[at] = 0u;
    }
    __syncthreads();

    const unsigned input_bit = blockIdx.x;

    for (uint64_t trial = threadIdx.x; trial < trials; trial += blockDim.x)
    {
        // Not 0x9e3779b97f4a7c15 for the row offset: that is splitmix's own increment, and using it
        // here makes row b's slot j+1 the identical draw to row b+1's slot j. Adjacent rows then
        // share seven words of eight, which inflated the measured spread of this control to 6.93
        // times the analytic variance and made it useless as a null.
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull)
                             + ((uint64_t)input_bit * 0xd1b54a32d192ed03ull);

        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            // Shape 1 gives every word its own stream instead of taking eight in a row from one.
            // If the harness's own chi-square deficit is the sequential draw it goes away here, and
            // if it survives both shapes it is not the access pattern.
            uint64_t apart_from = generator;
            if (shape == 1u)
            {
                apart_from = seed + (trial * 0x2545f4914f6cdd1dull)
                             + ((uint64_t)input_bit * 0xd1b54a32d192ed03ull)
                             + ((uint64_t)slot * 0xa24baed4963ee407ull);
            }
            uint32_t apart = (uint32_t)splitmix(apart_from);
            if (shape == 0u)
            {
                generator = apart_from;
            }
            while (apart != 0u)
            {
                const unsigned bit = (unsigned)__ffs((int)apart) - 1u;
                atomicAdd(&tally[(slot * 32u) + bit], 1ull);
                apart &= apart - 1u;
            }
        }
    }
    __syncthreads();

    unsigned long long *const row = &matrix[(size_t)input_bit * OUTPUT_BITS];
    for (unsigned at = threadIdx.x; at < OUTPUT_BITS; at += blockDim.x)
    {
        atomicAdd(&row[at], tally[at]);
    }
}

/**
 * @brief Runs the rounds with Sigma1's three rotation amounts supplied instead of fixed.
 *
 * @param[in]  message Sixteen message words [BORROWS].
 * @param[in]  rounds  How many rounds to run.
 * @param[in]  turns   The three amounts to use in place of 6, 11 and 25 [BORROWS].
 * @param[out] state   Eight words [BORROWS].
 * @note Every certain cell that is not on the diagonal sits at residue 25, and none at 6 or 11, at
 *       every depth measured. Two readings of that are available and they differ in what they
 *       predict of a function nobody built: that the largest amount always wins, or that 25 wins
 *       because it is 25. Changing the amounts separates them.
 * @note The rest of the function is untouched. Only Sigma1 is parameterised, so a difference in the
 *       result belongs to the rotation amounts and to nothing else.
 */
__global__ void fill_rotated_row(uint64_t trials, uint64_t seed, unsigned rounds, unsigned turn_a,
                                 unsigned turn_b, unsigned turn_c, unsigned long long *matrix)
{
    const unsigned input_bit = blockIdx.x;

    for (uint64_t trial = threadIdx.x; trial < trials; trial += blockDim.x)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull);

        uint32_t message[16];
        uint32_t flipped[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            message[slot] = (uint32_t)splitmix(generator);
            flipped[slot] = message[slot];
        }
        flipped[input_bit / 32u] ^= (1u << (input_bit % 32u));

        uint32_t plain[8];
        uint32_t other[8];

        for (unsigned side = 0u; side < 2u; side += 1u)
        {
            const uint32_t *source = (side == 0u) ? message : flipped;
            uint32_t schedule[64];
            for (unsigned slot = 0u; slot < 16u; slot += 1u)
            {
                schedule[slot] = source[slot];
            }
            for (unsigned slot = 16u; slot < 64u; slot += 1u)
            {
                const uint32_t two = schedule[slot - 2u];
                const uint32_t fifteen = schedule[slot - 15u];
                const uint32_t low = turn(fifteen, 7u) ^ turn(fifteen, 18u) ^ (fifteen >> 3u);
                const uint32_t high = turn(two, 17u) ^ turn(two, 19u) ^ (two >> 10u);
                schedule[slot] = schedule[slot - 16u] + low + schedule[slot - 7u] + high;
            }

            uint32_t a = d_start[0], b = d_start[1], c = d_start[2], d = d_start[3];
            uint32_t e = d_start[4], f = d_start[5], g = d_start[6], h = d_start[7];

            for (unsigned round = 0u; round < rounds; round += 1u)
            {
                const uint32_t big_one = turn(e, turn_a) ^ turn(e, turn_b) ^ turn(e, turn_c);
                const uint32_t choose = g ^ (e & (f ^ g));
                const uint32_t big_zero = turn(a, 2u) ^ turn(a, 13u) ^ turn(a, 22u);
                const uint32_t many = (a & b) | (c & (a ^ b));
                const uint32_t one = h + big_one + choose + d_constant[round] + schedule[round];
                const uint32_t two = big_zero + many;
                h = g; g = f; f = e; e = d + one;
                d = c; c = b; b = a; a = one + two;
            }

            uint32_t *const into = (side == 0u) ? plain : other;
            into[0] = a; into[1] = b; into[2] = c; into[3] = d;
            into[4] = e; into[5] = f; into[6] = g; into[7] = h;
        }

        unsigned long long *const row = &matrix[(size_t)input_bit * OUTPUT_BITS];
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            uint32_t apart = plain[slot] ^ other[slot];
            while (apart != 0u)
            {
                const unsigned bit = (unsigned)__ffs((int)apart) - 1u;
                atomicAdd(&row[(slot * 32u) + bit], 1ull);
                apart &= apart - 1u;
            }
        }
    }
}

/** @brief What the coherent reference keeps: only the parts that are linear over GF(2). */
#define REFERENCE_KEEP (KEEP_SCHEDULE | KEEP_BIG_ZERO | KEEP_BIG_ONE)

/**
 * @brief Propagates one input difference through the linear round function, exactly.
 *
 * @param[in]  rounds How many rounds to run.
 * @param[in]  where  Which input bit carries the difference.
 * @param[out] out    Eight words of difference [BORROWS].
 * @note With addition, Choose and Majority removed the map is linear over GF(2), so the difference
 *       it sends forward depends on the input difference alone and not on the message. That is what
 *       makes this a reference instead of another measurement: it has no sampling error at all.
 * @note One thread. It runs once per depth and computing it on the device avoids a second copy of
 *       the round function on the host, where the rotation intrinsic is unavailable anyway.
 */
__global__ void make_reference(unsigned rounds, unsigned where, uint32_t *out)
{
    uint32_t clear[16];
    uint32_t marked[16];
    for (unsigned slot = 0u; slot < 16u; slot += 1u)
    {
        clear[slot] = 0u;
        marked[slot] = 0u;
    }
    marked[where / 32u] ^= (1u << (where % 32u));

    uint32_t base_state[8];
    uint32_t marked_state[8];
    compress_to(clear, rounds, base_state, REFERENCE_KEEP);
    compress_to(marked, rounds, marked_state, REFERENCE_KEEP);

    for (unsigned slot = 0u; slot < 8u; slot += 1u)
    {
        out[slot] = base_state[slot] ^ marked_state[slot];
    }
}

/**
 * @brief Builds two residue folds, split by the value of one state bit at a chosen round.
 *
 * @param[in]     trials    How many messages to draw.
 * @param[in]     seed      Stream seed.
 * @param[in]     rounds    How many rounds to run for the measurement.
 * @param[in]     gate_at   Which round to read the selector at.
 * @param[in]     gate_bit  Which bit of e to use as the selector.
 * @param[in,out] matrix    Two 512 by 256 matrices laid end to end [BORROWS].
 * @note Every reading in this file averages over the message, which makes them all blind in the
 *       same way: they see where bits go and never what values sent them there. SHA-256's
 *       nonlinearity is entirely value-gated - Choose is a selector driven by e, Majority by the
 *       a chain, and carries by everything - so an average over messages mixes two transport
 *       regimes and reports their mean. A structure present in both halves with opposite sign
 *       vanishes completely from that average.
 * @note The gate is read from the *base* message only, so both members of a pair land in the same
 *       half. Gating on each member separately would split pairs across the two matrices and
 *       measure nothing.
 */
__global__ void fill_conditional_row(uint64_t trials, uint64_t seed, unsigned rounds,
                                     unsigned gate_at, unsigned gate_bit,
                                     unsigned long long *matrix)
{
    const unsigned input_bit = blockIdx.x;
    const size_t plane = (size_t)INPUT_BITS * OUTPUT_BITS;

    for (uint64_t trial = threadIdx.x; trial < trials; trial += blockDim.x)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull);

        uint32_t message[16];
        uint32_t flipped[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            message[slot] = (uint32_t)splitmix(generator);
            flipped[slot] = message[slot];
        }
        flipped[input_bit / 32u] ^= (1u << (input_bit % 32u));

        // The selector: bit gate_bit of e, the word Choose reads, at the gating round.
        uint32_t gate_state[8];
        compress_to(message, gate_at, gate_state, KEEP_EVERYTHING);
        const unsigned which = (unsigned)((gate_state[4] >> gate_bit) & 1u);

        uint32_t plain[8];
        uint32_t other[8];
        compress_to(message, rounds, plain, KEEP_EVERYTHING);
        compress_to(flipped, rounds, other, KEEP_EVERYTHING);

        unsigned long long *const row =
            &matrix[(which * plane) + ((size_t)input_bit * OUTPUT_BITS)];
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            uint32_t apart = plain[slot] ^ other[slot];
            while (apart != 0u)
            {
                const unsigned bit = (unsigned)__ffs((int)apart) - 1u;
                atomicAdd(&row[(slot * 32u) + bit], 1ull);
                apart &= apart - 1u;
            }
        }
    }
}

/**
 * @brief Counts how many messages fell each side of the gate, so the halves can be normalised.
 */
__global__ void count_gate(uint64_t trials, uint64_t seed, unsigned gate_at, unsigned gate_bit,
                           unsigned long long *counts)
{
    unsigned long long mine = 0ull;
    for (uint64_t trial = ((uint64_t)blockIdx.x * blockDim.x) + threadIdx.x; trial < trials;
         trial += (uint64_t)gridDim.x * blockDim.x)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull);
        uint32_t message[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            message[slot] = (uint32_t)splitmix(generator);
        }
        uint32_t gate_state[8];
        compress_to(message, gate_at, gate_state, KEEP_EVERYTHING);
        mine += (unsigned long long)((gate_state[4] >> gate_bit) & 1u);
    }
    atomicAdd(&counts[0], mine);
}

/**
 * @brief Sweeps message differences and records the sparsest one the linear model carries to depth.
 *
 * @param[in]     rounds  How many rounds to run.
 * @param[in]     pairs   Zero to sweep single bits, one to sweep pairs of bits.
 * @param[in]     total   How many candidates the index space holds.
 * @param[in,out] best    Packed best: weight in the high half, candidate index in the low [BORROWS].
 * @note This is a search instead of a measurement. The linearised function is deterministic, so
 *       every candidate is evaluated exactly once and exactly, and the answer is a true minimum
 *       over the swept set instead of the smallest thing sampling happened to find.
 * @note Linearising by replacing addition with exclusive-or is the standard first step of a
 *       differential attack on SHA-2: a characteristic is found in the linear model and its real
 *       probability is then bounded against it. The schedule is linearised with the state, since
 *       the expansion is additive too.
 * @note The pack keeps weight and index in one 64-bit word so a single atomicMin orders by weight
 *       and carries the winner with it, with no second pass to find which candidate won.
 */
__global__ void sweep_linear_weight(unsigned rounds, unsigned pairs, unsigned long long total,
                                    unsigned long long *best)
{
    const unsigned long long stride = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long at = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
         at < total; at += stride)
    {
        uint32_t clear[16];
        uint32_t marked[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            clear[slot] = 0u;
            marked[slot] = 0u;
        }

        if (pairs == 0u)
        {
            const unsigned where = (unsigned)at;
            marked[where / 32u] ^= (1u << (where % 32u));
        }
        else
        {
            // Unrank the index into an unordered pair without a division, by walking the triangle.
            unsigned long long left = at;
            unsigned first = 0u;
            while (left >= (unsigned long long)(INPUT_BITS - 1u - first))
            {
                left -= (unsigned long long)(INPUT_BITS - 1u - first);
                first += 1u;
            }
            const unsigned second = first + 1u + (unsigned)left;
            marked[first / 32u] ^= (1u << (first % 32u));
            marked[second / 32u] ^= (1u << (second % 32u));
        }

        uint32_t base_state[8];
        uint32_t marked_state[8];
        compress_to(clear, rounds, base_state, REFERENCE_KEEP);
        compress_to(marked, rounds, marked_state, REFERENCE_KEEP);

        unsigned weight = 0u;
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            weight += (unsigned)__popc(base_state[slot] ^ marked_state[slot]);
        }

        const unsigned long long packed = ((unsigned long long)weight << 40) | at;
        atomicMin(best, packed);
    }
}

/**
 * @brief Mixes the true difference against every rotation of the reference and tallies agreement.
 *
 * @param[in]     trials    How many messages to draw.
 * @param[in]     seed      Stream seed.
 * @param[in]     rounds    How many rounds to run.
 * @param[in]     where     Which input bit carries the difference.
 * @param[in]     reference Eight words from make_reference [BORROWS].
 * @param[in,out] tally     Thirty-two counters, one per rotation [BORROWS].
 * @note Agreement is counted over the reference's own set bits only. A bit the reference does not
 *       reach carries no phase, and including it would pull every rotation toward one half.
 * @note Rotation preserves population count, so all thirty-two rotations share one denominator and
 *       are directly comparable without renormalising.
 */
__global__ void lock_against_reference(uint64_t trials, uint64_t seed, unsigned rounds,
                                       unsigned where, const uint32_t *reference,
                                       unsigned long long *tally)
{
    __shared__ unsigned long long agree[32];
    for (unsigned at = threadIdx.x; at < 32u; at += blockDim.x)
    {
        agree[at] = 0ull;
    }
    __syncthreads();

    uint32_t held[8];
    for (unsigned slot = 0u; slot < 8u; slot += 1u)
    {
        held[slot] = reference[slot];
    }

    const uint64_t stride = (uint64_t)gridDim.x * (uint64_t)blockDim.x;
    for (uint64_t trial = ((uint64_t)blockIdx.x * blockDim.x) + threadIdx.x; trial < trials;
         trial += stride)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull);

        uint32_t message[16];
        uint32_t flipped[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            message[slot] = (uint32_t)splitmix(generator);
            flipped[slot] = message[slot];
        }
        flipped[where / 32u] ^= (1u << (where % 32u));

        uint32_t plain[8];
        uint32_t other[8];
        compress_to(message, rounds, plain, KEEP_EVERYTHING);
        compress_to(flipped, rounds, other, KEEP_EVERYTHING);

        uint32_t truth[8];
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            truth[slot] = plain[slot] ^ other[slot];
        }

        for (unsigned by = 0u; by < 32u; by += 1u)
        {
            unsigned matched = 0u;
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                matched += (unsigned)__popc(turn(held[slot], by) & truth[slot]);
            }
            atomicAdd(&agree[by], (unsigned long long)matched);
        }
    }
    __syncthreads();

    for (unsigned at = threadIdx.x; at < 32u; at += blockDim.x)
    {
        atomicAdd(&tally[at], agree[at]);
    }
}

/**
 * @brief Fills the matrix from randomness carrying a known plane wave, to calibrate the readout.
 *
 * @param[in]     trials    How many draws.
 * @param[in]     seed      Stream seed.
 * @param[in,out] matrix    512 by 256 counters [BORROWS].
 * @param[in]     frequency Cycles of the wave across the thirty-two residues.
 * @param[in]     strength  Bias amplitude is 2^-(strength+1), so a larger number is a fainter wave.
 * @note A cell's flip rate is driven to 0.5 +/- 2^-(strength+1) according to the sign of the wave
 *       at its residue. The bias is built without arithmetic on probabilities: a base bit at one
 *       half is or-ed with a rare bit at 2^-strength to push the rate up, and and-ed with its
 *       complement to push it down, which lands on 0.5 +/- 2^-(strength+1) exactly.
 * @note The rare bit is the and of `strength` draws, and the loop leaves early once all eight words
 *       have gone to zero. Without that a faint wave would cost the most, which is backwards: at
 *       large strength the words are almost always zero after four or five ands.
 */
__global__ void fill_wave_row(uint64_t trials, uint64_t seed, unsigned long long *matrix,
                              unsigned frequency, unsigned strength, unsigned shift)
{
    __shared__ unsigned long long tally[OUTPUT_BITS];
    for (unsigned at = threadIdx.x; at < OUTPUT_BITS; at += blockDim.x)
    {
        tally[at] = 0u;
    }
    __syncthreads();

    const unsigned input_bit = blockIdx.x;

    // Which output bits the wave pushes up, as eight words of thirty-two, built once per block.
    uint32_t upward[8];
    for (unsigned slot = 0u; slot < 8u; slot += 1u)
    {
        uint32_t word = 0u;
        for (unsigned bit = 0u; bit < 32u; bit += 1u)
        {
            const unsigned out_bit = (slot * 32u) + bit;
            const unsigned residue =
                (((input_bit % 32u) + 32u - (out_bit % 32u)) + 32u - (shift % 32u)) % 32u;
            if (((residue * frequency) % 32u) < 16u)
            {
                word |= (1u << bit);
            }
        }
        upward[slot] = word;
    }

    for (uint64_t trial = threadIdx.x; trial < trials; trial += blockDim.x)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull)
                             + ((uint64_t)input_bit * 0xd1b54a32d192ed03ull);

        uint32_t base[8];
        uint32_t rare[8];
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            base[slot] = (uint32_t)splitmix(generator);
            rare[slot] = (uint32_t)splitmix(generator);
        }

        for (unsigned step = 1u; step < strength; step += 1u)
        {
            uint32_t standing = 0u;
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                rare[slot] &= (uint32_t)splitmix(generator);
                standing |= rare[slot];
            }
            if (standing == 0u)
            {
                break;
            }
        }

        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            const uint32_t pushed_up = base[slot] | rare[slot];
            const uint32_t pushed_down = base[slot] & ~rare[slot];
            uint32_t apart = (pushed_up & upward[slot]) | (pushed_down & ~upward[slot]);
            while (apart != 0u)
            {
                const unsigned bit = (unsigned)__ffs((int)apart) - 1u;
                atomicAdd(&tally[(slot * 32u) + bit], 1ull);
                apart &= apart - 1u;
            }
        }
    }
    __syncthreads();

    unsigned long long *const row = &matrix[(size_t)input_bit * OUTPUT_BITS];
    for (unsigned at = threadIdx.x; at < OUTPUT_BITS; at += blockDim.x)
    {
        atomicAdd(&row[at], tally[at]);
    }
}

/**
 * @brief Exclusive-ors the output over every corner of a d-dimensional input cube.
 *
 * @param[in]     base      Sixteen message words to build the cube around [BORROWS].
 * @param[in]     positions Which d message bits the cube varies [BORROWS].
 * @param[in]     dimension How many bits, so the cube has 2^dimension corners.
 * @param[in]     rounds    How many rounds to run.
 * @param[in]     keep      Which sub-functions the variant keeps.
 * @param[in,out] folded    Eight words the corners are exclusive-ored into [BORROWS].
 * @note A Boolean function of algebraic degree below d has every d-th order derivative identically
 *       zero, and that derivative is exactly this sum. So a fold that comes out zero proves the
 *       degree is under d, and one that does not proves it is at least d. This is a proof instead
 *       of a statistic: no sampling, no threshold, and a single nonzero fold settles it.
 * @note One thread per corner, exclusive-ored together with atomics, instead of one thread walking
 *       the whole cube. At dimension twenty that is a million corners and no thread should walk
 *       them alone.
 */
__global__ void fold_cube(const uint32_t *base, const unsigned *positions, unsigned dimension,
                          unsigned rounds, unsigned keep, uint32_t *folded)
{
    const uint64_t corners = (uint64_t)1u << dimension;
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;

    for (uint64_t corner = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; corner < corners;
         corner += stride)
    {
        uint32_t message[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            message[slot] = base[slot];
        }
        for (unsigned bit = 0u; bit < dimension; bit += 1u)
        {
            if (((corner >> bit) & 1ull) != 0ull)
            {
                const unsigned where = positions[bit];
                message[where / 32u] ^= (1u << (where % 32u));
            }
        }

        uint32_t state[8];
        compress_to(message, rounds, state, keep);
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            atomicXor(&folded[slot], state[slot]);
        }
    }
}

/**
 * @brief Counts how often an output bit agrees with an input bit, for one input bit per block.
 *
 * @param[in]     trials How many messages to draw.
 * @param[in]     seed   Stream seed.
 * @param[in]     rounds How many rounds to run.
 * @param[in]     keep   Which sub-functions the variant keeps.
 * @param[in,out] agree  256 counters for this block's input bit [BORROWS].
 * @note A different axis from everything above. The SAC matrix is differential - it asks what a
 *       *change* in the input does to the output. This is linear - it asks whether the output value
 *       *equals* the input value more often than chance. The two resist different attacks and a
 *       function can be strong in one and weak in the other, so a bucket labeled "nonlinear" that
 *       has only been probed differentially is half unexamined.
 * @note Every block rehashes the same messages, which is 512 times redundant and simplest. The hash
 *       is cheap next to the alternative, which is 131072 global counters touched per trial.
 */
__global__ void fill_linear_row(uint64_t trials, uint64_t seed, unsigned rounds, unsigned keep,
                                unsigned long long *agree)
{
    __shared__ unsigned long long tally[OUTPUT_BITS];
    for (unsigned at = threadIdx.x; at < OUTPUT_BITS; at += blockDim.x)
    {
        tally[at] = 0u;
    }
    __syncthreads();

    const unsigned input_bit = blockIdx.x;

    for (uint64_t trial = threadIdx.x; trial < trials; trial += blockDim.x)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull);
        uint32_t message[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            message[slot] = (uint32_t)splitmix(generator);
        }

        uint32_t state[8];
        compress_to(message, rounds, state, keep);

        const unsigned carried = (message[input_bit / 32u] >> (input_bit % 32u)) & 1u;
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            uint32_t word = state[slot];
            for (unsigned bit = 0u; bit < 32u; bit += 1u)
            {
                if (((word >> bit) & 1u) == carried)
                {
                    atomicAdd(&tally[(slot * 32u) + bit], 1ull);
                }
            }
        }
    }
    __syncthreads();

    unsigned long long *const row = &agree[(size_t)input_bit * OUTPUT_BITS];
    for (unsigned at = threadIdx.x; at < OUTPUT_BITS; at += blockDim.x)
    {
        atomicAdd(&row[at], tally[at]);
    }
}

/**
 * @brief The same rounds run backwards, so a direction can be compared against its own reverse.
 *
 * @param[in]     start  Eight state words to unwind [BORROWS].
 * @param[in]     words  One message word per round [BORROWS].
 * @param[in]     rounds How many rounds to undo.
 * @param[in]     keep   Which sub-functions the variant keeps.
 * @param[out]    state  Eight state words [BORROWS].
 * @note The round is a bijection, so undoing it is arithmetic instead of a search. The shift runs
 *       the other way, choice and majority are recomputed from words the shift has already
 *       restored, and the two additions become subtractions - or stay exclusive-ors, which are
 *       their own inverse, in the carry-free variant.
 * @note Written so the forward and backward describability can be measured with one statistic. The
 *       two directions are known to differ in depth and in shape; whether they differ in how long a
 *       polynomial describes them is the question.
 */
__device__ __forceinline__ void decompress_to(const uint32_t *start, const uint32_t *message,
                                              unsigned rounds, unsigned keep, uint32_t *state)
{
    // The schedule is expanded here instead of taken from the caller. Passing the sixteen-word
    // message instead worked for rounds up to fifteen, where the schedule and the message coincide,
    // and read past the array from round sixteen on. The round trip check caught it at round
    // twenty-two with every trip failing.
    uint32_t schedule[64];
    for (unsigned slot = 0u; slot < 16u; slot += 1u)
    {
        schedule[slot] = message[slot];
    }
    if ((keep & KEEP_SCHEDULE) != 0u)
    {
        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            const uint32_t fifteen = schedule[slot - 15u];
            const uint32_t two = schedule[slot - 2u];
            const uint32_t low = turn(fifteen, 7u) ^ turn(fifteen, 18u) ^ (fifteen >> 3u);
            const uint32_t high = turn(two, 17u) ^ turn(two, 19u) ^ (two >> 10u);
            schedule[slot] = ((keep & KEEP_ADDITION) != 0u)
                                 ? (high + schedule[slot - 7u] + low + schedule[slot - 16u])
                                 : (high ^ schedule[slot - 7u] ^ low ^ schedule[slot - 16u]);
        }
    }
    else
    {
        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            schedule[slot] = schedule[slot - 16u];
        }
    }

    uint32_t a = start[0], b = start[1], c = start[2], d = start[3];
    uint32_t e = start[4], f = start[5], g = start[6], h = start[7];

    for (int round = (int)rounds - 1; round >= 0; round -= 1)
    {
        // The shift runs backwards first, so the words choice and majority read are the ones they
        // were computed from on the way forward.
        const uint32_t was_a = b;
        const uint32_t was_b = c;
        const uint32_t was_c = d;
        const uint32_t was_e = f;
        const uint32_t was_f = g;
        const uint32_t was_g = h;

        const uint32_t big_zero =
            ((keep & KEEP_BIG_ZERO) != 0u)
                ? (turn(was_a, 2u) ^ turn(was_a, 13u) ^ turn(was_a, 22u))
                : 0u;
        const uint32_t many =
            ((keep & KEEP_MAJORITY) != 0u) ? ((was_a & was_b) | (was_c & (was_a ^ was_b))) : 0u;
        const uint32_t big_one =
            ((keep & KEEP_BIG_ONE) != 0u)
                ? (turn(was_e, 6u) ^ turn(was_e, 11u) ^ turn(was_e, 25u))
                : 0u;
        const uint32_t choose =
            ((keep & KEEP_CHOOSE) != 0u) ? (was_g ^ (was_e & (was_f ^ was_g))) : 0u;
        const uint32_t rounder = ((keep & KEEP_CONSTANT) != 0u) ? d_constant[round] : 0u;

        uint32_t first;
        uint32_t was_d;
        uint32_t was_h;
        if ((keep & KEEP_ADDITION) != 0u)
        {
            first = a - big_zero - many;
            was_d = e - first;
            was_h = first - big_one - choose - rounder - schedule[round];
        }
        else
        {
            // Exclusive-or is its own inverse, so the carry-free arm undoes itself exactly.
            first = a ^ big_zero ^ many;
            was_d = e ^ first;
            was_h = first ^ big_one ^ choose ^ rounder ^ schedule[round];
        }

        a = was_a; b = was_b; c = was_c; d = was_d;
        e = was_e; f = was_f; g = was_g; h = was_h;
    }

    state[0] = a; state[1] = b; state[2] = c; state[3] = d;
    state[4] = e; state[5] = f; state[6] = g; state[7] = h;
}

/**
 * @brief Checks that the inverse actually inverts, for both variants.
 *
 * @param[in]     trials  How many states to round-trip.
 * @param[in]     seed    Stream seed.
 * @param[in]     rounds  How many rounds to go forward and back.
 * @param[in,out] failed  Counts round trips that did not return the input [BORROWS].
 * @note The direction results rest entirely on decompress_to being the inverse of compress_to, and
 *       that was asserted instead of measured. An inverse that is subtly wrong produces a clean
 *       anti-correlation and reads as a discovery, which is the shape of every error this document
 *       has already recorded.
 * @note Both variants are checked. Exclusive-or is its own inverse so the carry-free arm should be
 *       exact trivially, and the full arm should be exact because the round is a bijection.
 */
__global__ void round_trip_check(uint64_t trials, uint64_t seed, unsigned rounds,
                                 unsigned long long *failed)
{
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;

    for (uint64_t trial = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; trial < trials;
         trial += stride)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull);

        uint32_t message[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            message[slot] = (uint32_t)splitmix(generator);
        }

        for (unsigned arm = 0u; arm < 2u; arm += 1u)
        {
            const unsigned keep =
                (arm == 0u) ? KEEP_EVERYTHING : (KEEP_EVERYTHING & ~KEEP_ADDITION);

            uint32_t went[8];
            uint32_t came[8];
            compress_to(message, rounds, went, keep);
            decompress_to(went, message, rounds, keep, came);

            // compress_to starts from the standard's initial value, so that is what coming back
            // must produce.
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                if (came[slot] != d_start[slot])
                {
                    atomicAdd(failed, 1ull);
                    break;
                }
            }
        }
    }
}

/**
 * @brief How far the carry-free prediction still describes the real difference.
 *
 * @param[in]     trials  How many messages to draw.
 * @param[in]     seed    Stream seed.
 * @param[in]     rounds  How many rounds to run.
 * @param[in,out] agreed  Accumulates matching bits [BORROWS].
 * @param[in,out] counted Accumulates compared bits [BORROWS].
 * @note The polynomial part of SHA-256 - the sigmas, the schedule, the constants - is exact and
 *       permanent. It is a property of the function and cannot decay. What decays is whether a
 *       prediction built from it still describes the real thing, and the difference between those
 *       two statements is the whole question of whether structure is destroyed or only buried.
 * @note The prediction runs the same rounds with addition replaced by exclusive-or, which is the
 *       standard linearisation and is exact whenever no carry fires. Agreement starts at one and
 *       falls to one half, which is chance for a bit. Where it reaches one half is where the
 *       polynomial description stops working, not where the polynomial stops being true.
 */
__global__ void carry_free_agreement(uint64_t trials, uint64_t seed, unsigned rounds,
                                     unsigned long long *agreed, unsigned long long *counted,
                                     int backward, unsigned long long *by_position)
{
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    unsigned long long matched = 0u;
    unsigned long long compared = 0u;

    for (uint64_t trial = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; trial < trials;
         trial += stride)
    {
        uint64_t generator = seed + (trial * 0x2545f4914f6cdd1dull);

        uint32_t plain[16];
        uint32_t flipped[16];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            plain[slot] = (uint32_t)splitmix(generator);
            flipped[slot] = plain[slot];
        }
        const unsigned where = (unsigned)(splitmix(generator) % 512ull);
        flipped[where / 32u] ^= (1u << (where % 32u));

        // The real function, and the same pair through the carry-free one.
        uint32_t real_a[8];
        uint32_t real_b[8];
        uint32_t free_a[8];
        uint32_t free_b[8];

        if (backward == 0)
        {
            compress_to(plain, rounds, real_a, KEEP_EVERYTHING);
            compress_to(flipped, rounds, real_b, KEEP_EVERYTHING);
            compress_to(plain, rounds, free_a, KEEP_EVERYTHING & ~KEEP_ADDITION);
            compress_to(flipped, rounds, free_b, KEEP_EVERYTHING & ~KEEP_ADDITION);
        }
        else
        {
            // Backwards the difference goes in the state instead of the message, because that is
            // the input of the inverse. The message words are shared by both members exactly as
            // they are forwards.
            uint32_t state_a[8];
            uint32_t state_b[8];
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                state_a[slot] = plain[slot];
                state_b[slot] = plain[slot];
            }
            state_b[(where / 32u) % 8u] ^= (1u << (where % 32u));

            decompress_to(state_a, plain, rounds, KEEP_EVERYTHING, real_a);
            decompress_to(state_b, plain, rounds, KEEP_EVERYTHING, real_b);
            decompress_to(state_a, plain, rounds, KEEP_EVERYTHING & ~KEEP_ADDITION, free_a);
            decompress_to(state_b, plain, rounds, KEEP_EVERYTHING & ~KEEP_ADDITION, free_b);
        }

        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            const uint32_t real_difference = real_a[slot] ^ real_b[slot];
            const uint32_t free_difference = free_a[slot] ^ free_b[slot];

            // Bits where the two differences agree. Complement of the exclusive-or, counted.
            const uint32_t same = ~(real_difference ^ free_difference);
            matched += (unsigned long long)__popc(same);
            compared += 32u;

            // Kept per bit position as well, because a carry propagates upward from bit zero and
            // dies at bit thirty-one. Bit zero has no carry-in and must be described exactly; bit
            // thirty-one carries the most accumulated uncertainty and wraps into nothing. If the
            // wrap is what makes the two directions differ, the profile across positions differs
            // between them, and if it is not, both directions wear the same profile.
            for (unsigned bit = 0u; bit < 32u; bit += 1u)
            {
                if (((same >> bit) & 1u) != 0u)
                {
                    atomicAdd(&by_position[bit], 1ull);
                }
            }
        }
    }

    atomicAdd(agreed, matched);
    atomicAdd(counted, compared);
}

/**
 * @brief Turns the counter matrix into the field of per-cell deviations in standard errors.
 *
 * @param[in]  matrix 512 by 256 counters [BORROWS].
 * @param[in]  trials Draws behind each counter.
 * @param[out] field  One z per cell, same order [BORROWS].
 * @note Under the null each z is standard normal, so the field is white noise. Everything below
 *       asks whether it is, and a hash has no business producing anything else.
 */
static void fill_deviation_field(const std::vector<unsigned long long> &matrix, uint64_t trials,
                                 std::vector<double> &field)
{
    const double per_cell = 0.5 / std::sqrt((double)trials);
    for (size_t at = 0u; at < matrix.size(); at += 1u)
    {
        const double rate = (double)matrix[at] / (double)trials;
        field[at] = (rate - 0.5) / per_cell;
    }
}

/**
 * @brief Correlation of the field with itself shifted along the output axis.
 *
 * @param[in] field One z per cell [BORROWS].
 * @param[in] lag   How many output bits to shift, wrapping within the row.
 * @return Correlation coefficient, zero under a white null.
 * @note Wrapping instead of truncating keeps every lag on the same 131072 pairs, so the lags are
 *       comparable to each other and to the analytic error of one over the square root of that.
 */
static double correlate_along_output(const std::vector<double> &field, unsigned lag)
{
    double product = 0.0;
    double power = 0.0;
    for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
    {
        const double *const here = &field[(size_t)row * OUTPUT_BITS];
        for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
        {
            product += here[column] * here[(column + lag) % OUTPUT_BITS];
            power += here[column] * here[column];
        }
    }
    return (power > 0.0) ? (product / power) : 0.0;
}

/**
 * @brief Correlation of the field with itself shifted along the input axis.
 *
 * @param[in] field One z per cell [BORROWS].
 * @param[in] lag   How many input bits to shift, wrapping within the column.
 * @return Correlation coefficient, zero under a white null.
 */
static double correlate_along_input(const std::vector<double> &field, unsigned lag)
{
    double product = 0.0;
    double power = 0.0;
    for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
    {
        const double *const here = &field[(size_t)row * OUTPUT_BITS];
        const double *const there = &field[(size_t)((row + lag) % INPUT_BITS) * OUTPUT_BITS];
        for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
        {
            product += here[column] * there[column];
            power += here[column] * here[column];
        }
    }
    return (power > 0.0) ? (product / power) : 0.0;
}

/**
 * @brief Folds the field onto the thirty-two residue classes and reports the amplitude of each.
 *
 * @param[in]  field  One z per cell [BORROWS].
 * @param[out] folded Thirty-two sums, each divided by the square root of its count so a class
 *                    reads in standard errors like a cell does [BORROWS].
 */
static void fold_onto_residue(const std::vector<double> &field, double *folded)
{
    double counted[32];
    for (unsigned at = 0u; at < 32u; at += 1u)
    {
        folded[at] = 0.0;
        counted[at] = 0.0;
    }
    for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
    {
        for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
        {
            const unsigned residue = ((row % 32u) + 32u - (column % 32u)) % 32u;
            folded[residue] += field[((size_t)row * OUTPUT_BITS) + column];
            counted[residue] += 1.0;
        }
    }
    for (unsigned at = 0u; at < 32u; at += 1u)
    {
        if (counted[at] > 0.0)
        {
            folded[at] /= std::sqrt(counted[at]);
        }
    }
}

/**
 * @brief One complex line of the residue spectrum, normalised so each part is standard normal.
 *
 * @param[in]  folded    Thirty-two residue amplitudes [BORROWS].
 * @param[in]  frequency Which line.
 * @param[out] real_part Cosine component [BORROWS].
 * @param[out] imaginary Sine component [BORROWS].
 * @note Each folded amplitude is already one standard error, so the raw sum has variance sixteen
 *       and the divide by four makes both parts unit normal under the null. The phase is kept
 *       instead of discarded, because phase is what carries motion.
 */
static void residue_spectrum_line(const double *folded, unsigned frequency, double *real_part,
                                  double *imaginary)
{
    double summed_real = 0.0;
    double summed_imaginary = 0.0;
    for (unsigned at = 0u; at < 32u; at += 1u)
    {
        const double angle = 6.283185307179586 * (double)(frequency * at) / 32.0;
        summed_real += folded[at] * std::cos(angle);
        summed_imaginary -= folded[at] * std::sin(angle);
    }
    *real_part = summed_real / 4.0;
    *imaginary = summed_imaginary / 4.0;
}

/**
 * @brief Largest discrete-transform magnitude of the residue profile, and where it sits.
 *
 * @param[in]  folded  Thirty-two residue amplitudes [BORROWS].
 * @param[out] at_what Which frequency carried it [BORROWS].
 * @return The magnitude, normalised so a white profile gives about one.
 */
static double loudest_residue_tone(const double *folded, unsigned *at_what)
{
    double loudest = 0.0;
    *at_what = 0u;
    for (unsigned frequency = 1u; frequency < 16u; frequency += 1u)
    {
        double real_part = 0.0;
        double imaginary = 0.0;
        for (unsigned at = 0u; at < 32u; at += 1u)
        {
            const double angle = 6.283185307179586 * (double)(frequency * at) / 32.0;
            real_part += folded[at] * std::cos(angle);
            imaginary -= folded[at] * std::sin(angle);
        }
        const double magnitude =
            std::sqrt(((real_part * real_part) + (imaginary * imaginary)) / 16.0);
        if (magnitude > loudest)
        {
            loudest = magnitude;
            *at_what = frequency;
        }
    }
    return loudest;
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned trial_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 20u;
    const unsigned first_round = (argc > 2) ? (unsigned)std::atoi(argv[2]) : 45u;
    const unsigned last_round = (argc > 3) ? (unsigned)std::atoi(argv[3]) : 64u;
    const uint64_t trials = (uint64_t)1u << trial_bits;

    // "waves" runs the spatial arm alone. Every other arm here is settled and re-running them to
    // reach the last one costs ten minutes a look, which is the difference between an instrument
    // that gets iterated on and one that gets guessed at.
    const bool waves_only = (argc > 4) && (std::strcmp(argv[4], "waves") == 0);
    const bool dispersion_only = (argc > 4) && (std::strcmp(argv[4], "dispersion") == 0);
    const bool shadow_only = (argc > 4) && (std::strcmp(argv[4], "shadow") == 0);
    const bool assay_only = (argc > 4) && (std::strcmp(argv[4], "assay") == 0);
    const bool coherent_only = (argc > 4) && (std::strcmp(argv[4], "coherent") == 0);
    const bool construct_only = (argc > 4) && (std::strcmp(argv[4], "construct") == 0);
    const bool conditional_only = (argc > 4) && (std::strcmp(argv[4], "conditional") == 0);
    const bool sources_only = (argc > 4) && (std::strcmp(argv[4], "sources") == 0);
    const bool signed_only = (argc > 4) && (std::strcmp(argv[4], "signed") == 0);
    const bool cells_only = (argc > 4) && (std::strcmp(argv[4], "cells") == 0);
    const bool miner_only = (argc > 4) && (std::strcmp(argv[4], "miner") == 0);
    const bool rotations_only = (argc > 4) && (std::strcmp(argv[4], "rotations") == 0);

    std::printf("================================================================\n");
    std::printf("  The strict avalanche criterion, sampled hard\n");
    std::printf("================================================================\n");
    std::printf("\n  Vaughn and Borowczak report SHA-256 satisfying the SAC from round 23 to 53,\n");
    std::printf("  failing it from 54 to 57, and satisfying it again from 58. A measured\n");
    std::printf("  non-monotonicity in the diffusion of a function this studied is worth\n");
    std::printf("  reproducing before it is believed.\n");
    std::printf("\n  Their margin is thin: 0.49728 against a threshold of 0.49734, six parts in a\n");
    std::printf("  hundred thousand, at a million trials where one standard deviation is 0.0005.\n");
    std::printf("  That is 5.44 standard deviations at their sample and would be far more at ours,\n");
    std::printf("  so the question is answerable by sampling harder.\n");

    const double deviation = 0.5 / std::sqrt((double)trials);
    std::printf("\n  Trials per cell: 2^%u = %llu. One standard deviation is %.8f, against their\n",
                trial_bits, (unsigned long long)trials, deviation);
    std::printf("  0.00050000. Their reported dip of 0.00272 below one half would read %.1f\n",
                0.00272 / deviation);
    std::printf("  standard deviations here if it is real.\n");

    unsigned long long *device_matrix = nullptr;
    cudaMalloc((void **)&device_matrix,
               (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
    std::vector<unsigned long long> matrix((size_t)INPUT_BITS * OUTPUT_BITS);

    if (conditional_only)
    {
        // ---------------------------------------------------------------------------------------
        // The blindness every other arm here shares.
        //
        // Each reading in this file averages over the message. That makes them all blind the same
        // way: they see where bits go and never what values sent them there. It is the same failure
        // as reading a word by its token and never its letters - the index is visible and the
        // content is not.
        //
        // SHA-256's nonlinearity is entirely value-gated. Choose is a selector: bit k of e decides
        // whether bit k of the result comes from f or from g, so there are two transport regimes
        // and which one runs depends on a value. Majority is gated by the a chain, and the carries
        // by everything. An average over messages mixes those regimes and reports their mean, and
        // a structure present in both halves with opposite sign cancels out of that mean entirely.
        //
        // So: split the messages by the selector and build the two folds separately. If they agree
        // the averaging cost nothing and every earlier reading stands. If they differ, the
        // unconditional matrix has been reporting the mean of two different objects all along.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  Conditioned on the selector, not averaged over it\n");
        std::printf("================================================================\n");

        const unsigned GATE_AT = 8u;
        const unsigned GATE_BIT = 16u;

        std::printf("\n  Gate: bit %u of e at round %u, which is the bit Choose reads to decide\n",
                    GATE_BIT, GATE_AT);
        std::printf("  whether that position passes f or g. Both members of a pair are gated on\n");
        std::printf("  the base message, so a pair never splits across the two halves.\n");

        const size_t plane = (size_t)INPUT_BITS * OUTPUT_BITS;
        unsigned long long *device_pair = nullptr;
        cudaMalloc((void **)&device_pair, 2u * plane * sizeof(unsigned long long));
        std::vector<unsigned long long> both(2u * plane);

        unsigned long long *device_counts = nullptr;
        cudaMalloc((void **)&device_counts, sizeof(unsigned long long));

        std::printf("\n  %6s %12s %12s %12s %12s %10s\n", "round", "fold |0", "fold |1",
                    "difference", "error", "sigmas");
        std::printf("  %6s %12s %12s %12s %12s %10s\n", "------", "------------", "------------",
                    "------------", "------------", "----------");

        for (unsigned at_round = 10u; at_round <= 30u; at_round += 2u)
        {
            const uint64_t seed = 353535001ull + ((uint64_t)at_round * 1000003ull);

            unsigned long long ones = 0ull;
            cudaMemset(device_counts, 0, sizeof(unsigned long long));
            count_gate<<<256, 256>>>(trials, seed, GATE_AT, GATE_BIT, device_counts);
            cudaDeviceSynchronize();
            cudaMemcpy(&ones, device_counts, sizeof(unsigned long long), cudaMemcpyDeviceToHost);
            const double high = (double)ones;
            const double low = (double)trials - high;

            cudaMemset(device_pair, 0, 2u * plane * sizeof(unsigned long long));
            fill_conditional_row<<<INPUT_BITS, 256>>>(trials, seed, at_round, GATE_AT, GATE_BIT,
                                                      device_pair);
            cudaDeviceSynchronize();
            cudaMemcpy(both.data(), device_pair, 2u * plane * sizeof(unsigned long long),
                       cudaMemcpyDeviceToHost);

            // Each half folded onto the residues, then the halves subtracted. Anything the two
            // regimes share cancels, which is exactly the point: the common mode goes with it.
            double folded_low[32];
            double folded_high[32];
            double counted[32];
            for (unsigned at = 0u; at < 32u; at += 1u)
            {
                folded_low[at] = 0.0;
                folded_high[at] = 0.0;
                counted[at] = 0.0;
            }
            for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
            {
                for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
                {
                    const unsigned residue = ((row % 32u) + 32u - (column % 32u)) % 32u;
                    const size_t at = ((size_t)row * OUTPUT_BITS) + column;
                    if (low > 0.0)
                    {
                        folded_low[residue] += ((double)both[at] / low) - 0.5;
                    }
                    if (high > 0.0)
                    {
                        folded_high[residue] += ((double)both[plane + at] / high) - 0.5;
                    }
                    counted[residue] += 1.0;
                }
            }

            double loudest = 0.0;
            for (unsigned at = 0u; at < 32u; at += 1u)
            {
                if (counted[at] <= 0.0)
                {
                    continue;
                }
                const double gap = (folded_low[at] - folded_high[at]) / std::sqrt(counted[at]);
                if (std::fabs(gap) > std::fabs(loudest))
                {
                    loudest = gap;
                }
            }

            // A difference of two independent rates has the variance of both, so the error is the
            // per-cell error of each half added in quadrature.
            const double error =
                0.5 * std::sqrt((1.0 / (low > 0.0 ? low : 1.0)) + (1.0 / (high > 0.0 ? high : 1.0)));
            const double sigmas = loudest / error;

            std::printf("  %6u %12.0f %12.0f %12.6f %12.6f %10.2f\n", at_round, low, high,
                        loudest, error, sigmas);
        }

        cudaFree(device_pair);
        cudaFree(device_counts);
        cudaFree(device_matrix);

        std::printf("\n  The largest of 32 residue classes peaks near %.2f sigmas under a null,\n",
                    std::sqrt(2.0 * std::log(32.0)));
        std::printf("  and 11 depths were read, so the union peaks near %.2f.\n",
                    std::sqrt(2.0 * std::log(32.0 * 11.0)));
        std::printf("\n  A difference standing above that says the unconditional matrix has been\n");
        std::printf("  reporting the mean of two different objects, and every reading built on it\n");
        std::printf("  is an average across a regime boundary. A difference at zero says the\n");
        std::printf("  averaging cost nothing and the earlier readings stand as they are.\n");
        return 0;
    }

    if (construct_only)
    {
        // ---------------------------------------------------------------------------------------
        // Constructing instead of sampling.
        //
        // Every instrument before this one asks what deviates from chance over random messages, and
        // all of them go flat by round 23. The published attacks reach 39 steps, and the gap is not
        // sensitivity: a 39-step characteristic has a probability near 2^-100, and no amount of
        // sampling finds an event that rare. They do not detect it. They *construct* it, by
        // choosing the input instead of drawing it.
        //
        // The first step of that construction is already built here. Linearising the function -
        // addition replaced by exclusive-or, in the schedule as well as the state - makes
        // difference propagation deterministic, so a difference can be *searched* instead of
        // measured. That is what published differential work on SHA-2 does first: find a
        // low-weight characteristic in the linear model, then bound the real probability against
        // it.
        //
        // This sweep is exhaustive over its set instead of sampled, so the answer is a true
        // minimum and not the smallest thing a sample happened to contain.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  Constructed differences: the sparsest the linear model carries\n");
        std::printf("================================================================\n");

        std::printf("\n  Sampling asks what deviates from chance and stops at round 23. This asks\n");
        std::printf("  what an attacker could choose, which is a different question and the one the\n");
        std::printf("  published attacks answer. The linearised function is deterministic, so every\n");
        std::printf("  candidate is evaluated exactly and the minimum is a true minimum.\n");

        std::printf("\n  Weight of the output difference, over all 512 single-bit message\n");
        std::printf("  differences and all %llu pairs.\n",
                    (unsigned long long)((INPUT_BITS * (INPUT_BITS - 1u)) / 2u));

        unsigned long long *device_best = nullptr;
        cudaMalloc((void **)&device_best, sizeof(unsigned long long));

        std::printf("\n  %6s %10s %10s %12s %10s %12s\n", "round", "best 1", "at bit", "best 2",
                    "at pair", "random 1");
        std::printf("  %6s %10s %10s %12s %10s %12s\n", "------", "----------", "----------",
                    "------------", "----------", "------------");

        const unsigned long long SINGLES = INPUT_BITS;
        const unsigned long long PAIRS =
            ((unsigned long long)INPUT_BITS * (INPUT_BITS - 1u)) / 2u;

        for (unsigned at_round = 8u; at_round <= 40u; at_round += 2u)
        {
            const unsigned long long empty = ~0ull;

            cudaMemcpy(device_best, &empty, sizeof(unsigned long long), cudaMemcpyHostToDevice);
            sweep_linear_weight<<<256, 256>>>(at_round, 0u, SINGLES, device_best);
            cudaDeviceSynchronize();
            unsigned long long one_best = 0ull;
            cudaMemcpy(&one_best, device_best, sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            cudaMemcpy(device_best, &empty, sizeof(unsigned long long), cudaMemcpyHostToDevice);
            sweep_linear_weight<<<1024, 256>>>(at_round, 1u, PAIRS, device_best);
            cudaDeviceSynchronize();
            unsigned long long two_best = 0ull;
            cudaMemcpy(&two_best, device_best, sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            const unsigned one_weight = (unsigned)(one_best >> 40);
            const unsigned long long one_where = one_best & 0xffffffffffull;
            const unsigned two_weight = (unsigned)(two_best >> 40);
            const unsigned long long two_where = two_best & 0xffffffffffull;

            // A random 256-bit difference has weight 128. That is what a characteristic has to beat
            // to be worth anything, and the column is here so the comparison is on the page.
            std::printf("  %6u %10u %10llu %12u %10llu %12u\n", at_round, one_weight, one_where,
                        two_weight, two_where, 128u);
        }

        cudaFree(device_best);
        cudaFree(device_matrix);

        std::printf("\n  A weight far below 128 is a characteristic worth having: the difference\n");
        std::printf("  stays sparse, so the conditions an attacker must force are few. A weight at\n");
        std::printf("  128 means the linear model has diffused completely and offers nothing to\n");
        std::printf("  build on at that depth.\n");
        std::printf("\n  This is the linear model only. The real function's probability of following\n");
        std::printf("  any of these is a separate and much smaller number, which is exactly the\n");
        std::printf("  'low-probability uncontrolled part' the published work names as its wall.\n");
        return 0;
    }

    if (coherent_only)
    {
        // ---------------------------------------------------------------------------------------
        // A coherent receiver, with the local oscillator generated instead of tracked.
        //
        // Every reading in this work estimates the structure from the data alone, which is what a
        // receiver does when it has no reference. But this receiver is also the transmitter: the
        // input difference is chosen, so a reference can be *generated* instead of locked to.
        //
        // Propagating the same difference through the GF(2)-linear version of the round function -
        // no addition, no Choose, no Majority, so the map is linear and the difference depends only
        // on the difference - gives an exact phase reference. Not a tracked one with loop noise: an
        // exact one, which is better than any real radar gets.
        //
        // Mixing the true difference against that reference at every rotation and taking the
        // rotation that agrees best is a phase-locked loop, and the rotation it locks to is the
        // loop phase. A lock that sits at zero says the difference is linearly polarised and the
        // carries only add magnitude. A lock that walks with depth says the difference vector is
        // rotating in the plane spanned by its linear part and its carry part, which is circular
        // polarisation, and the direction of the walk is a handedness of the round function.
        //
        // What is left after de-rotating - the true difference exclusive-ored with the rotated
        // reference - is everything the carries contributed and nothing else.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  Coherent detection against a generated reference\n");
        std::printf("================================================================\n");

        // The reference keeps only what is linear over GF(2): the rotations and the schedule. With
        // addition, Choose and Majority removed the map is linear, so the propagated difference is
        // a function of the input difference alone and carries no dependence on the message.
        const unsigned DEEPEST = 26u;
        const unsigned WHERE = 0u;

        std::printf("\n  Reference: the same difference through the GF(2)-linear round function,\n");
        std::printf("  which is exact because a linear map sends a difference to a difference\n");
        std::printf("  whatever the message is. Input difference is bit %u.\n", WHERE);
        std::printf("\n  Lock is the rotation of the reference that agrees best with the true\n");
        std::printf("  difference. The largest of 32 agreements peaks near %.2f sigmas under a\n",
                    std::sqrt(2.0 * std::log(32.0)));
        std::printf("  null whatever the data does, so a lock is only a lock above that.\n");

        std::printf("\n  %6s %8s %10s %12s %10s %12s\n", "round", "lock", "agreement", "sigmas",
                    "ref weight", "walked");
        std::printf("  %6s %8s %10s %12s %10s %12s\n", "------", "--------", "----------",
                    "------------", "----------", "------------");

        unsigned long long *device_tally = nullptr;
        cudaMalloc((void **)&device_tally, 32u * sizeof(unsigned long long));
        std::vector<unsigned long long> tally(32u);

        int last_lock = -1;
        for (unsigned at_round = 2u; at_round <= DEEPEST; at_round += 1u)
        {
            // The reference, computed on the device once per depth: linear, so the base message is
            // irrelevant and this carries no sampling error at all.
            uint32_t *device_reference = nullptr;
            cudaMalloc((void **)&device_reference, 8u * sizeof(uint32_t));
            make_reference<<<1, 1>>>(at_round, WHERE, device_reference);
            cudaDeviceSynchronize();

            uint32_t reference[8];
            cudaMemcpy(reference, device_reference, 8u * sizeof(uint32_t), cudaMemcpyDeviceToHost);

            unsigned reference_weight = 0u;
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                uint32_t left = reference[slot];
                while (left != 0u)
                {
                    reference_weight += 1u;
                    left &= left - 1u;
                }
            }

            cudaMemset(device_tally, 0, 32u * sizeof(unsigned long long));
            lock_against_reference<<<256, 256>>>(trials, 242424001ull + (at_round * 1000003ull),
                                                 at_round, WHERE, device_reference, device_tally);
            cudaDeviceSynchronize();
            cudaMemcpy(tally.data(), device_tally, 32u * sizeof(unsigned long long),
                       cudaMemcpyDeviceToHost);
            cudaFree(device_reference);

            // Agreement is counted over the reference's own set bits only, because a bit the
            // reference does not reach carries no phase information and would dilute the lock
            // toward one half whatever the truth is.
            const double compared = (double)trials * (double)reference_weight;
            // Seeded at one half, which is zero distance, so the first real rate displaces it.
            // Seeding at zero would make the initial value the furthest from one half that exists
            // and nothing would ever beat it - the whole column then prints the seed.
            unsigned best = 0u;
            double best_rate = 0.5;
            for (unsigned turn_by = 0u; turn_by < 32u; turn_by += 1u)
            {
                const double rate = (compared > 0.0) ? ((double)tally[turn_by] / compared) : 0.5;
                if (std::fabs(rate - 0.5) > std::fabs(best_rate - 0.5))
                {
                    best_rate = rate;
                    best = turn_by;
                }
            }
            const double spread = 0.5 / std::sqrt(compared > 0.0 ? compared : 1.0);
            const double sigmas = (best_rate - 0.5) / spread;

            const char *walked = "";
            if (last_lock >= 0)
            {
                const int step = ((int)best - last_lock + 32) % 32;
                walked = (step == 0) ? "" : "walked";
            }
            last_lock = (int)best;

            std::printf("  %6u %8u %10.5f %12.1f %10u %12s\n", at_round, best, best_rate, sigmas,
                        reference_weight, walked);
        }

        cudaFree(device_tally);
        cudaFree(device_matrix);

        std::printf("\n  A lock that stays at one rotation is a difference that keeps its linear\n");
        std::printf("  part's orientation: linear polarisation, the carries adding magnitude only.\n");
        std::printf("  A lock that walks with depth is the difference vector rotating in the plane\n");
        std::printf("  its linear part and its carry part span, and the direction is a handedness.\n");
        std::printf("\n  The reference weight is the linear part's own growth, which is exact and\n");
        std::printf("  owes nothing to sampling. Where it saturates the reference stops carrying\n");
        std::printf("  phase and the lock below it means nothing.\n");
        return 0;
    }

    if (assay_only)
    {
        // ---------------------------------------------------------------------------------------
        // A compositional assay.
        //
        // A radar that has measured a library of known materials can say what an unknown return is
        // made of, not merely that something is there. Here the library does not have to be
        // collected, because any variant of the function can be built on demand: the same residue
        // spectrum is taken from SHA-256 with one sub-function removed at a time, and what changes
        // says which channel that sub-function was carrying.
        //
        // The predictions are stated before the run instead of read off it:
        //
        //   without Sigma1     classes 6, 11 and 25 go, because those are its rotation amounts
        //   without Sigma0     classes 2, 13 and 22 go, and they were weak to begin with
        //   without addition   class 31 goes, because -1 mod 32 is the carry and there are no
        //                      carries without addition. This is the sharpest of the three
        //   without Choose     a large change, because Choose is in T1
        //   without Majority   little change, because Majority is in T2 and T2 is the weak side
        //
        // A variant that removes a named rotation and leaves its residue standing would refute the
        // reading of the spectrum entirely, which is what makes this worth running.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  Compositional assay: the spectrum of known variants\n");
        std::printf("================================================================\n");

        std::vector<double> field((size_t)INPUT_BITS * OUTPUT_BITS);
        double folded[32];

        const unsigned FROM = 4u;
        const unsigned UNTIL = 22u;

        struct Variant
        {
            const char *name;
            unsigned keep;
        };
        const Variant variants[] = {
            { "full",           KEEP_EVERYTHING },
            { "no_majority",    KEEP_EVERYTHING & ~KEEP_MAJORITY },
            { "no_choose",      KEEP_EVERYTHING & ~KEEP_CHOOSE },
            { "no_sigma0",      KEEP_EVERYTHING & ~KEEP_BIG_ZERO },
            { "no_sigma1",      KEEP_EVERYTHING & ~KEEP_BIG_ONE },
            { "no_addition",    KEEP_EVERYTHING & ~KEEP_ADDITION },
            { "no_schedule",    KEEP_EVERYTHING & ~KEEP_SCHEDULE },
            { "no_constant",    KEEP_EVERYTHING & ~KEEP_CONSTANT },
        };
        const unsigned HOW_MANY = (unsigned)(sizeof(variants) / sizeof(variants[0]));

        std::FILE *const handle = std::fopen("assay.csv", "w");
        if (handle == nullptr)
        {
            std::printf("\n  could not open assay.csv\n");
            cudaFree(device_matrix);
            return 1;
        }
        std::fprintf(handle, "variant,residue,round,value\n");

        std::printf("\n  %u variants across rounds %u to %u, each round on its own seed.\n",
                    HOW_MANY, FROM, UNTIL);

        for (unsigned which = 0u; which < HOW_MANY; which += 1u)
        {
            for (unsigned at_round = FROM; at_round <= UNTIL; at_round += 1u)
            {
                cudaMemset(device_matrix, 0,
                           (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
                fill_sac_row<<<INPUT_BITS, 256>>>(
                    trials, 616161001ull + ((uint64_t)at_round * 1000003ull), at_round,
                    device_matrix, variants[which].keep);
                cudaDeviceSynchronize();
                cudaMemcpy(matrix.data(), device_matrix,
                           matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);
                fill_deviation_field(matrix, trials, field);
                fold_onto_residue(field, folded);

                for (unsigned at = 0u; at < 32u; at += 1u)
                {
                    std::fprintf(handle, "%s,%u,%u,%.4f\n", variants[which].name, at, at_round,
                                 folded[at]);
                }
            }
            std::printf("  %-14s done\n", variants[which].name);
        }
        std::fclose(handle);
        cudaFree(device_matrix);

        std::printf("\n  Written to assay.csv. Process with maint/radar/radar_assay.py\n");
        return 0;
    }

    if (rotations_only)
    {
        // ---------------------------------------------------------------------------------------
        // Why residue twenty-five and not six or eleven.
        //
        // Every certain cell off the diagonal sits at residue 25, and none at Sigma1's other two
        // amounts, at rounds eight, ten and twelve alike. The carry-contamination account fails
        // its own prediction, so the mechanism is unknown, and the published record does not help:
        // the K constants have a derivation but the rotation amounts are stated without one.
        //
        // Two readings differ in what they say about a function nobody built.
        //
        //   largest wins   the surviving residue is whichever amount is greatest, and 25 is
        //                  incidental. A variant with different amounts moves the certain cells to
        //                  its own largest.
        //   twenty-five    something about 25 against the word width or the other two amounts. A
        //                  variant keeps its cells near 25 or scatters them.
        //
        // Only Sigma1 changes. A difference in the result belongs to the rotation amounts alone.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  Sigma1's rotation amounts, varied\n");
        std::printf("================================================================\n");

        struct Variant
        {
            unsigned a;
            unsigned b;
            unsigned c;
            const char *note;
        };
        const Variant tried[] = {
            {  6u, 11u, 25u, "SHA-256 as specified" },
            {  6u, 11u, 19u, "largest lowered to 19" },
            {  6u, 11u, 30u, "largest raised to 30" },
            {  3u,  7u, 25u, "others lowered, 25 kept" },
            { 13u, 20u, 25u, "others raised, 25 kept" },
            {  2u, 13u, 22u, "Sigma0's amounts" },
            {  7u, 18u, 25u, "small sigma0's, 25 kept" },
        };
        const unsigned HOW_MANY = (unsigned)(sizeof(tried) / sizeof(tried[0]));
        const unsigned AT_ROUND = 12u;

        std::printf("\n  Certain cells at round %u, by where they sit. The diagonal at residue 0 is\n",
                    AT_ROUND);
        std::printf("  addition and is expected in every row; the question is the rest.\n");

        std::printf("\n  %-26s %8s %8s %10s %s\n", "Sigma1", "certain", "aligned", "skewed",
                    "skewed residues");
        std::printf("  %-26s %8s %8s %10s %s\n", "--------------------------", "--------",
                    "--------", "----------", "----------------");

        for (unsigned which = 0u; which < HOW_MANY; which += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_rotated_row<<<INPUT_BITS, 256>>>(trials, 979797001ull, AT_ROUND, tried[which].a,
                                                  tried[which].b, tried[which].c, device_matrix);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            unsigned by_residue[32];
            for (unsigned at = 0u; at < 32u; at += 1u)
            {
                by_residue[at] = 0u;
            }
            unsigned total = 0u;
            unsigned aligned = 0u;

            for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
            {
                for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
                {
                    if (matrix[((size_t)row * OUTPUT_BITS) + column] != trials)
                    {
                        continue;
                    }
                    total += 1u;
                    const unsigned residue = ((row % 32u) + 32u - (column % 32u)) % 32u;
                    by_residue[residue] += 1u;
                    if (residue == 0u)
                    {
                        aligned += 1u;
                    }
                }
            }

            char where[128];
            unsigned used = 0u;
            for (unsigned at = 1u; at < 32u; at += 1u)
            {
                if ((by_residue[at] != 0u) && (used < 100u))
                {
                    used += (unsigned)std::snprintf(&where[used], sizeof(where) - used, "%u:%u ",
                                                    at, by_residue[at]);
                }
            }
            if (used == 0u)
            {
                std::snprintf(where, sizeof(where), "none");
            }

            char label[40];
            std::snprintf(label, sizeof(label), "%u,%u,%u  %s", tried[which].a, tried[which].b,
                          tried[which].c, tried[which].note);
            std::printf("  %-26s %8u %8u %10u %s\n", label, total, aligned, total - aligned, where);
        }

        cudaFree(device_matrix);

        std::printf("\n  If the skewed residue follows the largest amount in every row, the reading\n");
        std::printf("  is that the largest wins and 25 is incidental. If it stays near 25 while the\n");
        std::printf("  amounts move, it is not. A row where the skew vanishes says the effect needs\n");
        std::printf("  a relation between the three and not any one of them.\n");
        return 0;
    }

    if (miner_only)
    {
        // ---------------------------------------------------------------------------------------
        // The miner's two shared-work constants, measured instead of derived.
        //
        // btc_miner precomputes the part of the second block that cannot depend on the nonce, and
        // two constants say how much: SHARED_ROUNDS = 3 and SHARED_SCHEDULE = 18. They were reached
        // by reading the recurrences. An off-by-one either way is not a slow miner, it is a miner
        // that submits wrong shares, so they are worth measuring by the same light-cone argument
        // used on the dependency field.
        //
        // A Bitcoin header is eighty bytes, so the second block holds bytes 64 to 79 and its
        // padding. The nonce is bytes 76 to 79, which is W[3] of that block.
        //
        //   rounds    word w cannot reach the state before round w+1, so W[3] leaves rounds 0, 1
        //             and 2 untouched and SHARED_ROUNDS should measure 3
        //   schedule  W[t] reads W[t-2], W[t-7], W[t-15] and W[t-16], so the first expanded word
        //             touching W[3] is t = 18 and SHARED_SCHEDULE should measure 18
        //
        // Both are checked by varying only the nonce and finding the first word and the first round
        // that ever moves.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  The miner's shared work, measured\n");
        std::printf("================================================================\n");

        // Block 125552's header tail, so the numbers below are about a real header and not a
        // pattern that happens to be convenient.
        const uint32_t TAIL[4] = { 0x9d10aa52u, 0x4dcc1dd0u, 0x1b04864cu, 0x9895d4b1u };

        const unsigned TRIES = 4096u;
        unsigned first_schedule_move = 64u;
        unsigned first_round_move = 64u;

        uint32_t base_schedule[64];
        uint32_t base_state[8];

        for (unsigned attempt = 0u; attempt <= TRIES; attempt += 1u)
        {
            uint32_t message[16];
            for (unsigned slot = 0u; slot < 16u; slot += 1u)
            {
                message[slot] = 0u;
            }
            message[0] = TAIL[0];
            message[1] = TAIL[1];
            message[2] = TAIL[2];
            // The nonce. Attempt zero is the header's own, the rest are drawn.
            message[3] = (attempt == 0u) ? TAIL[3] : (0x9895d4b1u ^ (attempt * 2654435761u));
            message[4] = 0x80000000u;
            message[15] = 640u;

            uint32_t schedule[64];
            for (unsigned slot = 0u; slot < 16u; slot += 1u)
            {
                schedule[slot] = message[slot];
            }
            for (unsigned slot = 16u; slot < 64u; slot += 1u)
            {
                const uint32_t two = schedule[slot - 2u];
                const uint32_t fifteen = schedule[slot - 15u];
                const uint32_t low = ((fifteen >> 7u) | (fifteen << 25u))
                                     ^ ((fifteen >> 18u) | (fifteen << 14u)) ^ (fifteen >> 3u);
                const uint32_t high = ((two >> 17u) | (two << 15u))
                                      ^ ((two >> 19u) | (two << 13u)) ^ (two >> 10u);
                schedule[slot] = schedule[slot - 16u] + low + schedule[slot - 7u] + high;
            }

            // The chaining value from the first block is irrelevant to which words move, so the
            // standard initial value stands in for it.
            uint32_t state[8] = { 0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                                  0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u };
            uint32_t rounds_seen[64][8];

            for (unsigned round = 0u; round < 64u; round += 1u)
            {
                const uint32_t e = state[4];
                const uint32_t a = state[0];
                const uint32_t big_one = ((e >> 6u) | (e << 26u)) ^ ((e >> 11u) | (e << 21u))
                                         ^ ((e >> 25u) | (e << 7u));
                const uint32_t choose = state[6] ^ (e & (state[5] ^ state[6]));
                const uint32_t big_zero = ((a >> 2u) | (a << 30u)) ^ ((a >> 13u) | (a << 19u))
                                          ^ ((a >> 22u) | (a << 10u));
                const uint32_t many = (a & state[1]) | (state[2] & (a ^ state[1]));
                const uint32_t one = state[7] + big_one + choose + host_constant[round]
                                     + schedule[round];
                const uint32_t two = big_zero + many;

                state[7] = state[6];
                state[6] = state[5];
                state[5] = state[4];
                state[4] = state[3] + one;
                state[3] = state[2];
                state[2] = state[1];
                state[1] = state[0];
                state[0] = one + two;

                for (unsigned slot = 0u; slot < 8u; slot += 1u)
                {
                    rounds_seen[round][slot] = state[slot];
                }
            }

            if (attempt == 0u)
            {
                for (unsigned slot = 0u; slot < 64u; slot += 1u)
                {
                    base_schedule[slot] = schedule[slot];
                }
                for (unsigned slot = 0u; slot < 8u; slot += 1u)
                {
                    base_state[slot] = rounds_seen[0][slot];
                }
                continue;
            }

            // Only the expanded words. W[0] to W[15] are the message and W[3] is the nonce itself,
            // so asking whether they move asks nothing: the miner rewrites those per nonce and
            // shares only the expansion above them.
            for (unsigned slot = 16u; slot < 64u; slot += 1u)
            {
                if ((schedule[slot] != base_schedule[slot]) && (slot < first_schedule_move))
                {
                    first_schedule_move = slot;
                }
            }

            // A round has moved when any of its eight state words differs from the same round of
            // the reference nonce. Recomputed against the reference each attempt.
            uint32_t reference[8] = { 0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                                      0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u };
            for (unsigned round = 0u; round < 64u; round += 1u)
            {
                const uint32_t e = reference[4];
                const uint32_t a = reference[0];
                const uint32_t big_one = ((e >> 6u) | (e << 26u)) ^ ((e >> 11u) | (e << 21u))
                                         ^ ((e >> 25u) | (e << 7u));
                const uint32_t choose = reference[6] ^ (e & (reference[5] ^ reference[6]));
                const uint32_t big_zero = ((a >> 2u) | (a << 30u)) ^ ((a >> 13u) | (a << 19u))
                                          ^ ((a >> 22u) | (a << 10u));
                const uint32_t many = (a & reference[1]) | (reference[2] & (a ^ reference[1]));
                const uint32_t one = reference[7] + big_one + choose + host_constant[round]
                                     + base_schedule[round];
                const uint32_t two = big_zero + many;
                reference[7] = reference[6];
                reference[6] = reference[5];
                reference[5] = reference[4];
                reference[4] = reference[3] + one;
                reference[3] = reference[2];
                reference[2] = reference[1];
                reference[1] = reference[0];
                reference[0] = one + two;

                bool moved = false;
                for (unsigned slot = 0u; slot < 8u; slot += 1u)
                {
                    if (rounds_seen[round][slot] != reference[slot])
                    {
                        moved = true;
                    }
                }
                if (moved && (round < first_round_move))
                {
                    first_round_move = round;
                }
            }
        }

        std::printf("\n  Header: block 125552, nonce varied over %u draws, everything else fixed.\n",
                    TRIES);
        std::printf("  The nonce is W[3] of the second block.\n");

        std::printf("\n  %-34s %10s %10s %8s\n", "quantity", "measured", "in miner", "verdict");
        std::printf("  %-34s %10s %10s %8s\n", "----------------------------------", "----------",
                    "----------", "--------");
        std::printf("  %-34s %10u %10u %8s\n", "first schedule word that moves", first_schedule_move,
                    18u, (first_schedule_move == 18u) ? "match" : "MISMATCH");
        std::printf("  %-34s %10u %10u %8s\n", "first round that moves", first_round_move, 3u,
                    (first_round_move == 3u) ? "match" : "MISMATCH");

        std::printf("\n  Words 0 to %u and rounds 0 to %u cannot see the nonce, so a miner may\n",
                    first_schedule_move - 1u, first_round_move - 1u);
        std::printf("  compute them once per header. SHARED_SCHEDULE and SHARED_ROUNDS in\n");
        std::printf("  src/engine/c/sha256/core/sha256_core.c claim exactly that. A mismatch above is a miner\n");
        std::printf("  reusing work the nonce does change, which submits wrong shares instead of\n");
        std::printf("  slow ones.\n");

        cudaFree(device_matrix);
        return 0;
    }

    if (cells_only)
    {
        // ---------------------------------------------------------------------------------------
        // The identities behind the soliton.
        //
        // The signed projection found 312 cells that flip with probability one, 135 input bits
        // wide, translating at exactly 32 bits per round without changing form. It sums over the
        // output axis, so it cannot say *which* output bits those are, and the numbers 312 and 135
        // are unexplained.
        //
        // A model worth testing: flipping bit k of an addend always flips bit k of the sum, since
        // carries only propagate upward. So bit k of a message word deterministically flips bit k
        // of T1, and therefore bit k of a and of e - exactly two cells. Those then ride the copy
        // chain, a to b to c to d and e to f to g to h, for three further rounds while nothing
        // mixes them.
        //
        // That model predicts four words of thirty-two bits contributing two cells each: 256 cells
        // over 128 bits. The measurement says 312 over 135. The model is close and wrong by a
        // stated amount, which is the useful kind of wrong, and the identities settle it.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  Which cells are certain, and where they sit\n");
        std::printf("================================================================\n");

        const unsigned LOOKS[] = { 8u, 10u, 12u };
        const unsigned HOW_MANY = 3u;

        for (unsigned which = 0u; which < HOW_MANY; which += 1u)
        {
            const unsigned at_round = LOOKS[which];
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 686868001ull + ((uint64_t)at_round * 1000003ull),
                                              at_round, device_matrix, KEEP_EVERYTHING);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            // Which state words receive them, and whether the input and output bit positions match
            // within their words - the model says they must, since bit k drives bit k.
            unsigned by_state[8];
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                by_state[slot] = 0u;
            }
            unsigned aligned = 0u;
            unsigned skewed = 0u;
            unsigned total = 0u;
            unsigned per_word[16];
            for (unsigned slot = 0u; slot < 16u; slot += 1u)
            {
                per_word[slot] = 0u;
            }

            for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
            {
                for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
                {
                    if (matrix[((size_t)row * OUTPUT_BITS) + column] != trials)
                    {
                        continue;
                    }
                    total += 1u;
                    by_state[column / 32u] += 1u;
                    per_word[row / 32u] += 1u;
                    if ((row % 32u) == (column % 32u))
                    {
                        aligned += 1u;
                    }
                    else
                    {
                        skewed += 1u;
                    }
                }
            }

            std::printf("\n  Round %u: %u certain cells\n", at_round, total);
            std::printf("    by state word   ");
            for (unsigned slot = 0u; slot < 8u; slot += 1u)
            {
                std::printf("%c:%-5u", (char)('a' + slot), by_state[slot]);
            }
            std::printf("\n");
            std::printf("    positions       %u aligned (bit k drives bit k), %u skewed\n",
                        aligned, skewed);
            std::printf("    by message word ");
            for (unsigned slot = 0u; slot < 16u; slot += 1u)
            {
                if (per_word[slot] != 0u)
                {
                    std::printf("W%u:%u ", slot, per_word[slot]);
                }
            }
            std::printf("\n");

            // Every skewed cell by its residue, because Sigma1 has three rotation amounts and a
            // sample of eight would not distinguish one of them from all three. Sigma0's amounts
            // are counted too, so the answer is not assumed.
            if (skewed != 0u)
            {
                unsigned by_residue[32];
                unsigned by_word_out[8];
                for (unsigned slot = 0u; slot < 32u; slot += 1u)
                {
                    by_residue[slot] = 0u;
                }
                for (unsigned slot = 0u; slot < 8u; slot += 1u)
                {
                    by_word_out[slot] = 0u;
                }
                for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
                {
                    for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
                    {
                        if ((matrix[((size_t)row * OUTPUT_BITS) + column] != trials)
                            || ((row % 32u) == (column % 32u)))
                        {
                            continue;
                        }
                        by_residue[((row % 32u) + 32u - (column % 32u)) % 32u] += 1u;
                        by_word_out[column / 32u] += 1u;
                    }
                }
                std::printf("    skewed by residue  ");
                for (unsigned slot = 0u; slot < 32u; slot += 1u)
                {
                    if (by_residue[slot] != 0u)
                    {
                        const char *what = "";
                        if ((slot == 6u) || (slot == 11u) || (slot == 25u)) { what = "=S1"; }
                        if ((slot == 2u) || (slot == 13u) || (slot == 22u)) { what = "=S0"; }
                        if (slot == 31u) { what = "=carry"; }
                        std::printf("%u%s:%u  ", slot, what, by_residue[slot]);
                    }
                }
                std::printf("\n    skewed land in     ");
                for (unsigned slot = 0u; slot < 8u; slot += 1u)
                {
                    if (by_word_out[slot] != 0u)
                    {
                        std::printf("%c:%u  ", (char)('a' + slot), by_word_out[slot]);
                    }
                }
                std::printf("\n");
            }
        }

        cudaFree(device_matrix);
        std::printf("\n  The model predicts every certain cell is aligned and lands in a or e and\n");
        std::printf("  their copies, two per input bit over four words. Anything skewed, or in a\n");
        std::printf("  word the copy chain cannot reach, is the model being wrong somewhere\n");
        std::printf("  specific.\n");
        return 0;
    }

    if (signed_only)
    {
        // ---------------------------------------------------------------------------------------
        // The projection that does not throw the sign away.
        //
        // Every earlier projection sums z squared, and z squared cannot tell a rate of zero from a
        // rate of one: both give z = -/+ sqrt(n) and the same square. A bit that changes nothing
        // and a bit that flips its outputs every single time land on the same plateau and draw as
        // the same color at the same height. Two physically opposite states, one pixel.
        //
        // The naive repair - summing signed z instead - has its own conflation, and a worse one: a
        // row half never-flipping and half always-flipping sums to zero, which is exactly what a
        // fully mixed row gives. That would hide the same distinction somewhere else.
        //
        // So the three states are counted instead of summed. A cell is *never* if its count is
        // zero, *always* if its count is every trial, and *mixed* otherwise. Those are exclusive
        // and exhaustive, nothing cancels, and each becomes its own surface.
        //
        //   never   256 across the whole row is outside the causal cone
        //   always  nonzero marks a bit whose effect is still deterministic
        //   mixed   rises as the function stops being predictable, and is the real frontier
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  The signed projection: never, always, and mixed counted apart\n");
        std::printf("================================================================\n");

        const unsigned DEEPEST = 40u;

        std::FILE *const handle = std::fopen("signed.csv", "w");
        if (handle == nullptr)
        {
            std::printf("\n  could not open signed.csv\n");
            cudaFree(device_matrix);
            return 1;
        }
        std::fprintf(handle, "kind,axis,index,round,value\n");

        std::printf("\n  %u rounds, each on its own seed. A cell is never, always or mixed, and\n",
                    DEEPEST);
        std::printf("  those are exclusive, so nothing cancels the way a signed sum would.\n");
        std::printf("\n  %6s %10s %10s %10s %10s\n", "round", "never", "always", "mixed",
                    "det. bits");
        std::printf("  %6s %10s %10s %10s %10s\n", "------", "----------", "----------",
                    "----------", "----------");

        for (unsigned at_round = 1u; at_round <= DEEPEST; at_round += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 575757001ull + ((uint64_t)at_round * 1000003ull),
                                              at_round, device_matrix, KEEP_EVERYTHING);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            unsigned long long never_all = 0ull;
            unsigned long long always_all = 0ull;
            unsigned long long mixed_all = 0ull;
            unsigned deterministic_rows = 0u;

            for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
            {
                unsigned never_here = 0u;
                unsigned always_here = 0u;
                for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
                {
                    const unsigned long long count =
                        matrix[((size_t)row * OUTPUT_BITS) + column];
                    if (count == 0ull)
                    {
                        never_here += 1u;
                    }
                    else if (count == trials)
                    {
                        always_here += 1u;
                    }
                }
                const unsigned mixed_here = OUTPUT_BITS - never_here - always_here;

                std::fprintf(handle, "never,inbit,%u,%u,%u\n", row, at_round, never_here);
                std::fprintf(handle, "always,inbit,%u,%u,%u\n", row, at_round, always_here);
                std::fprintf(handle, "mixed,inbit,%u,%u,%u\n", row, at_round, mixed_here);

                never_all += never_here;
                always_all += always_here;
                mixed_all += mixed_here;
                if (mixed_here == 0u)
                {
                    deterministic_rows += 1u;
                }
            }

            // The same three counts down the other axis, so a state bit can be read as well.
            for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
            {
                unsigned never_here = 0u;
                unsigned always_here = 0u;
                for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
                {
                    const unsigned long long count =
                        matrix[((size_t)row * OUTPUT_BITS) + column];
                    if (count == 0ull)
                    {
                        never_here += 1u;
                    }
                    else if (count == trials)
                    {
                        always_here += 1u;
                    }
                }
                std::fprintf(handle, "never,outbit,%u,%u,%u\n", column, at_round, never_here);
                std::fprintf(handle, "always,outbit,%u,%u,%u\n", column, at_round, always_here);
                std::fprintf(handle, "mixed,outbit,%u,%u,%u\n", column, at_round,
                             INPUT_BITS - never_here - always_here);
            }

            std::printf("  %6u %10llu %10llu %10llu %10u\n", at_round, never_all, always_all,
                        mixed_all, deterministic_rows);
        }

        std::fclose(handle);
        cudaFree(device_matrix);

        std::printf("\n  'det. bits' counts input bits whose every output cell is still at an\n");
        std::printf("  extreme, so the bit's whole effect is predictable. That is the bedrock, and\n");
        std::printf("  it is now split into the part that changes nothing and the part that\n");
        std::printf("  changes something every time.\n");
        std::printf("\n  Written to signed.csv.\n");
        return 0;
    }

    if (sources_only)
    {
        // ---------------------------------------------------------------------------------------
        // The same projections from several sources, so the eye can do the comparison.
        //
        // Every null in this file is a number. This dumps the fields themselves - SHA-256 beside a
        // matrix that is pseudorandom by construction, and beside two ablations - through identical
        // projection code, so the question "does this look like noise" can be answered by looking
        // instead of only by a statistic.
        //
        // The pseudorandom source runs the same kernel shape, the same shared tally, the same
        // atomics and the same denominator, with the compression replaced by eight random words.
        // Anything the two have in common is the harness. Anything only SHA-256 has is SHA-256.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  The same field from several sources\n");
        std::printf("================================================================\n");

        std::vector<double> field((size_t)INPUT_BITS * OUTPUT_BITS);
        double folded[32];

        const unsigned DEEPEST = 48u;

        struct Source
        {
            const char *name;
            unsigned keep;
            bool random;
        };
        const Source sources[] = {
            { "sha256",      KEEP_EVERYTHING,                     false },
            { "psrand",      0u,                                  true  },
            { "no_addition", KEEP_EVERYTHING & ~KEEP_ADDITION,    false },
            { "no_sigma1",   KEEP_EVERYTHING & ~KEEP_BIG_ONE,     false },
        };
        const unsigned HOW_MANY = (unsigned)(sizeof(sources) / sizeof(sources[0]));

        std::FILE *const handle = std::fopen("sources.csv", "w");
        if (handle == nullptr)
        {
            std::printf("\n  could not open sources.csv\n");
            cudaFree(device_matrix);
            return 1;
        }
        std::fprintf(handle, "source,kind,a,b,round,value\n");

        std::printf("\n  %u sources across %u rounds, each round on its own seed.\n",
                    HOW_MANY, DEEPEST);

        for (unsigned which = 0u; which < HOW_MANY; which += 1u)
        {
            for (unsigned at_round = 1u; at_round <= DEEPEST; at_round += 1u)
            {
                const uint64_t seed = 464646001ull + ((uint64_t)at_round * 1000003ull);
                cudaMemset(device_matrix, 0,
                           (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
                if (sources[which].random)
                {
                    fill_null_row<<<INPUT_BITS, 256>>>(trials, seed, device_matrix, 0u);
                }
                else
                {
                    fill_sac_row<<<INPUT_BITS, 256>>>(trials, seed, at_round, device_matrix,
                                                      sources[which].keep);
                }
                cudaDeviceSynchronize();
                cudaMemcpy(matrix.data(), device_matrix,
                           matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);
                fill_deviation_field(matrix, trials, field);

                fold_onto_residue(field, folded);
                for (unsigned at = 0u; at < 32u; at += 1u)
                {
                    std::fprintf(handle, "%s,residue,%u,0,%u,%.4f\n", sources[which].name, at,
                                 at_round, folded[at]);
                }

                for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
                {
                    double along = 0.0;
                    for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
                    {
                        const double here = field[((size_t)row * OUTPUT_BITS) + column];
                        along += here * here;
                    }
                    std::fprintf(handle, "%s,inbit,%u,0,%u,%.2f\n", sources[which].name, row,
                                 at_round, along - (double)OUTPUT_BITS);
                }

                for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
                {
                    double along = 0.0;
                    for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
                    {
                        const double here = field[((size_t)row * OUTPUT_BITS) + column];
                        along += here * here;
                    }
                    std::fprintf(handle, "%s,outbit,%u,0,%u,%.2f\n", sources[which].name, column,
                                 at_round, along - (double)INPUT_BITS);
                }
            }
            std::printf("  %-14s done\n", sources[which].name);
        }
        std::fclose(handle);
        cudaFree(device_matrix);

        std::printf("\n  Written to sources.csv. Render with examples/00_blob_viz_tools/build_sources_view.py\n");
        return 0;
    }

    if (shadow_only)
    {
        // ---------------------------------------------------------------------------------------
        // The object, and its shadows.
        //
        // Everything in this file is a projection. The fold onto residue is the object flattened
        // along one axis; the chi-square is it flattened all the way to a scalar. Both are shadows,
        // and a shadow is only ever cast from one angle. Nothing here has looked at the thing from
        // a second one.
        //
        // The object is three-dimensional: 512 input bits by 256 output bits by 64 rounds, which is
        // 8.4 million cells and not something anyone holds in their head. So it is dumped as its
        // projections instead of whole, and the projections are what a viewer can be built on.
        //
        // Four shadows are written, each the object collapsed along a different axis:
        //
        //   residue by round   the signed fold, which is where the ridge lives
        //   inbit by round     every input bit against depth, unfolded
        //   outbit by round    every output bit against depth
        //   word by word       input word against output word against depth, the coarse block view
        //
        // Signed where a sign exists, because taking magnitudes first folds noise into a positive
        // bias and manufactures a shape in every cell.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  The object, dumped as its shadows\n");
        std::printf("================================================================\n");

        std::vector<double> field((size_t)INPUT_BITS * OUTPUT_BITS);
        double folded[32];

        const unsigned DEEPEST = 64u;
        std::vector<double> residue_by_round((size_t)32u * DEEPEST, 0.0);
        std::vector<double> inbit_by_round((size_t)INPUT_BITS * DEEPEST, 0.0);
        std::vector<double> outbit_by_round((size_t)OUTPUT_BITS * DEEPEST, 0.0);
        std::vector<double> word_by_word((size_t)16u * 8u * DEEPEST, 0.0);

        std::printf("\n  Filling %u rounds. Each is its own seed, so the noise between rounds is\n",
                    DEEPEST);
        std::printf("  independent and any shape that crosses rounds is the object instead of a\n");
        std::printf("  fluctuation carried along.\n");

        for (unsigned at_round = 1u; at_round <= DEEPEST; at_round += 1u)
        {
            const unsigned slot = at_round - 1u;
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 929292001ull + ((uint64_t)at_round * 1000003ull),
                                              at_round, device_matrix, KEEP_EVERYTHING);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);
            fill_deviation_field(matrix, trials, field);

            fold_onto_residue(field, folded);
            for (unsigned at = 0u; at < 32u; at += 1u)
            {
                residue_by_round[((size_t)at * DEEPEST) + slot] = folded[at];
            }

            for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
            {
                double along = 0.0;
                for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
                {
                    const double here = field[((size_t)row * OUTPUT_BITS) + column];
                    along += here * here;
                }
                // Excess over the expected one per cell, so a flat row reads zero instead of 256.
                inbit_by_round[((size_t)row * DEEPEST) + slot] = along - (double)OUTPUT_BITS;
            }

            for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
            {
                double along = 0.0;
                for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
                {
                    const double here = field[((size_t)row * OUTPUT_BITS) + column];
                    along += here * here;
                }
                outbit_by_round[((size_t)column * DEEPEST) + slot] = along - (double)INPUT_BITS;
            }

            for (unsigned in_word = 0u; in_word < 16u; in_word += 1u)
            {
                for (unsigned out_word = 0u; out_word < 8u; out_word += 1u)
                {
                    double along = 0.0;
                    for (unsigned bit = 0u; bit < 32u; bit += 1u)
                    {
                        const unsigned row = (in_word * 32u) + bit;
                        for (unsigned other = 0u; other < 32u; other += 1u)
                        {
                            const unsigned column = (out_word * 32u) + other;
                            const double here = field[((size_t)row * OUTPUT_BITS) + column];
                            along += here * here;
                        }
                    }
                    const size_t where = ((((size_t)in_word * 8u) + out_word) * DEEPEST) + slot;
                    word_by_word[where] = along - 1024.0;
                }
            }
        }

        cudaFree(device_matrix);

        std::FILE *const handle = std::fopen("shadows.csv", "w");
        if (handle == nullptr)
        {
            std::printf("\n  could not open shadows.csv\n");
            return 1;
        }
        std::fprintf(handle, "kind,a,b,round,value\n");
        for (unsigned at = 0u; at < 32u; at += 1u)
        {
            for (unsigned slot = 0u; slot < DEEPEST; slot += 1u)
            {
                std::fprintf(handle, "residue,%u,0,%u,%.4f\n", at, slot + 1u,
                             residue_by_round[((size_t)at * DEEPEST) + slot]);
            }
        }
        for (unsigned row = 0u; row < INPUT_BITS; row += 1u)
        {
            for (unsigned slot = 0u; slot < DEEPEST; slot += 1u)
            {
                std::fprintf(handle, "inbit,%u,0,%u,%.2f\n", row, slot + 1u,
                             inbit_by_round[((size_t)row * DEEPEST) + slot]);
            }
        }
        for (unsigned column = 0u; column < OUTPUT_BITS; column += 1u)
        {
            for (unsigned slot = 0u; slot < DEEPEST; slot += 1u)
            {
                std::fprintf(handle, "outbit,%u,0,%u,%.2f\n", column, slot + 1u,
                             outbit_by_round[((size_t)column * DEEPEST) + slot]);
            }
        }
        for (unsigned in_word = 0u; in_word < 16u; in_word += 1u)
        {
            for (unsigned out_word = 0u; out_word < 8u; out_word += 1u)
            {
                for (unsigned slot = 0u; slot < DEEPEST; slot += 1u)
                {
                    const size_t where = ((((size_t)in_word * 8u) + out_word) * DEEPEST) + slot;
                    std::fprintf(handle, "word,%u,%u,%u,%.2f\n", in_word, out_word, slot + 1u,
                                 word_by_word[where]);
                }
            }
        }
        std::fclose(handle);

        std::printf("\n  Written to shadows.csv: %u residue rows, %u input bits, %u output bits\n",
                    32u, INPUT_BITS, OUTPUT_BITS);
        std::printf("  and %u word pairs, each across %u rounds.\n", 16u * 8u, DEEPEST);
        return 0;
    }

    if (dispersion_only)
    {
        // ---------------------------------------------------------------------------------------
        // The dispersion relation, where there is still something to measure.
        //
        // The Doppler scan asks one question of the whole field: is anything moving. This asks a
        // finer one of each frequency separately, and it is asked at rounds 10 to 23 instead of
        // past 23, because that is the only place this function still has structure to fingerprint.
        //
        // Fitting a complex exponential to Z_f(r) gives two numbers per frequency:
        //
        //   drift   the phase advance per round, which is where that component is going
        //   decay   the amplitude fall per round, which is how fast it is being elided
        //
        // Together they are a complex frequency, and the shape of drift against frequency is what
        // identifies a mechanism instead of merely detecting one. A rigid rotation drifts at the
        // same velocity at every frequency. A shear drifts as one over frequency. A diffusive
        // process does not hold a drift at all as frequency rises. The known 1/32 amplitude law is
        // one point on this curve and the rest of it has never been measured.
        //
        // What it can carry is position, not value. The phase of a component is the residue offset
        // it sits at, so this locates structure; nothing here recovers the value of any bit, and
        // the table below should not be read as if it could.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  The dispersion relation, rounds 10 to 23\n");
        std::printf("================================================================\n");

        std::vector<double> field((size_t)INPUT_BITS * OUTPUT_BITS);
        double folded[32];

        const unsigned FROM = 10u;
        const unsigned WALK = 14u;
        const unsigned TONES = 16u;

        // Ten standard errors. Under the null a spectrum line has unit-normal parts, so this is far
        // enough above the floor that the log of the amplitude is still the log of a signal.
        const double FLOOR_AT = 10.0;

        std::printf("\n  Fitting Z_f(r) across %u rounds, each on its own seed. Drift is the phase\n",
                    WALK);
        std::printf("  advance per round turned into residues per round; decay is the amplitude\n");
        std::printf("  fall per round. Position is where the component sits, which phase carries\n");
        std::printf("  and magnitude does not.\n");

        for (unsigned source = 0u; source < 2u; source += 1u)
        {
            std::vector<double> line_real((size_t)TONES * WALK, 0.0);
            std::vector<double> line_imaginary((size_t)TONES * WALK, 0.0);
            const char *label = (source == 0u) ? "walking wave, control" : "SHA-256";

            for (unsigned step = 0u; step < WALK; step += 1u)
            {
                const unsigned at_round = FROM + step;
                const uint64_t seed = 818181001ull + ((uint64_t)at_round * 1000003ull);

                cudaMemset(device_matrix, 0,
                           (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
                if (source == 0u)
                {
                    // A wave of fixed amplitude walking one residue per round: the fit must return
                    // drift 1 and decay 0, or the fit is wrong and the SHA-256 row means nothing.
                    fill_wave_row<<<INPUT_BITS, 256>>>(trials, seed, device_matrix, 3u, 9u,
                                                       step % 32u);
                }
                else
                {
                    fill_sac_row<<<INPUT_BITS, 256>>>(trials, seed, at_round, device_matrix,
                                                      KEEP_EVERYTHING);
                }
                cudaDeviceSynchronize();
                cudaMemcpy(matrix.data(), device_matrix,
                           matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);
                fill_deviation_field(matrix, trials, field);
                fold_onto_residue(field, folded);

                for (unsigned tone = 1u; tone < TONES; tone += 1u)
                {
                    double real_part = 0.0;
                    double imaginary = 0.0;
                    residue_spectrum_line(folded, tone, &real_part, &imaginary);
                    line_real[((size_t)tone * WALK) + step] = real_part;
                    line_imaginary[((size_t)tone * WALK) + step] = imaginary;
                }
            }

            std::printf("\n  %s\n", label);
            std::printf("  %6s %12s %12s %12s %12s %8s %8s\n", "freq", "amplitude", "position",
                        "drift", "decay/round", "fitted", "holds");
            std::printf("  %6s %12s %12s %12s %12s %8s %8s\n", "------", "------------",
                        "------------", "------------", "------------", "--------", "--------");

            for (unsigned tone = 1u; tone < TONES; tone += 1u)
            {
                // Phase advance without unwrapping: the argument of the sum of each round against
                // the conjugate of the one before it. Amplitude-weighted by construction, which is
                // what should happen when the later rounds are fainter.
                double turned_real = 0.0;
                double turned_imaginary = 0.0;
                for (unsigned at = 0u; (at + 1u) < WALK; at += 1u)
                {
                    const double next_real = line_real[((size_t)tone * WALK) + at + 1u];
                    const double next_imaginary = line_imaginary[((size_t)tone * WALK) + at + 1u];
                    const double here_real = line_real[((size_t)tone * WALK) + at];
                    const double here_imaginary = line_imaginary[((size_t)tone * WALK) + at];
                    turned_real += (next_real * here_real) + (next_imaginary * here_imaginary);
                    turned_imaginary += (next_imaginary * here_real) - (next_real * here_imaginary);
                }
                const double advance = std::atan2(turned_imaginary, turned_real);
                const double drift = (advance * 32.0) / (6.283185307179586 * (double)tone);

                // Decay from a straight-line fit of the log amplitude, and the amplitude itself
                // reported at the first round so the reader can see whether the fit had anything
                // to work with.
                double sum_at = 0.0;
                double sum_log = 0.0;
                double sum_at_log = 0.0;
                double sum_at_at = 0.0;
                double counted = 0.0;
                double first_size = 0.0;
                for (unsigned at = 0u; at < WALK; at += 1u)
                {
                    const double here_real = line_real[((size_t)tone * WALK) + at];
                    const double here_imaginary = line_imaginary[((size_t)tone * WALK) + at];
                    const double size = std::sqrt((here_real * here_real)
                                                  + (here_imaginary * here_imaginary));
                    if (at == 0u)
                    {
                        first_size = size;
                    }
                    // Only points clear of the noise floor. A component that has fallen into the
                    // noise stops falling, so including those rounds measures where the floor is
                    // instead of how fast the thing decayed - and it does so worst for the
                    // faintest components, which had least room to fall.
                    //
                    // Without this the fitted decay correlates with the starting amplitude at
                    // r = 0.76 over fifteen frequencies, which is the confound wearing a lab coat:
                    // it reads as "every scale dies at the same rate" and is really "everything
                    // ends up at the same floor".
                    if (size <= FLOOR_AT)
                    {
                        continue;
                    }
                    const double when = (double)at;
                    sum_at += when;
                    sum_log += std::log(size);
                    sum_at_log += when * std::log(size);
                    sum_at_at += when * when;
                    counted += 1.0;
                }
                double decay = 0.0;
                if (counted > 1.0)
                {
                    const double spread = (counted * sum_at_at) - (sum_at * sum_at);
                    if (spread != 0.0)
                    {
                        decay = ((counted * sum_at_log) - (sum_at * sum_log)) / spread;
                    }
                }

                const double where = line_imaginary[((size_t)tone * WALK)];
                const double whence = line_real[((size_t)tone * WALK)];
                double position = (std::atan2(where, whence) * 32.0)
                                  / (6.283185307179586 * (double)tone);
                const double wrap = 32.0 / (double)tone;
                while (position < 0.0)
                {
                    position += wrap;
                }

                // A drift is only a measurement where the component was loud enough to carry a
                // phase. Below that the argument of noise is uniform and the number is furniture.
                // A decay wants points to fit, and a drift wants amplitude to carry a phase. Both
                // are reported so a row that says nothing can be seen to say nothing.
                const char *holds = ((first_size > 20.0) && (counted >= 4.0)) ? "yes" : "-";
                std::printf("  %6u %12.1f %12.3f %12.3f %12.4f %8.0f %8s\n", tone, first_size,
                            position, drift, decay, counted, holds);
            }
        }

        std::printf("\n  The control must read drift 1.000 and decay near zero at frequency 3, or\n");
        std::printf("  the fit is wrong and the SHA-256 table above means nothing. Where a row is\n");
        std::printf("  marked '-' the component was too faint to carry a phase and its drift is the\n");
        std::printf("  argument of noise, which is uniform.\n");

        cudaFree(device_matrix);
        return 0;
    }

    if (waves_only)
    {
        // ---------------------------------------------------------------------------------------
        // Waves in, and whether the field is smooth.
        //
        // Every reading before this one collapses 131072 cells to a scalar, which throws away
        // where the cells are. Two fields with the same sum of squares can be white noise or a
        // smooth landscape, and only the second is interesting: a hash has no business producing a
        // spatially correlated residual, because correlation between neighboring cells is
        // structure that survived the mixing.
        //
        // The claim needs a null the same way every other claim here did, so three fields go
        // through identical code:
        //
        //   the harness alone   a matrix binomial by construction, which is whatever the random
        //                       stream, the atomics and the arithmetic contribute by themselves
        //   a known wave        the same harness with a plane wave of stated amplitude pushed in,
        //                       which says what the readout does when there is something to find
        //   SHA-256             the real matrix past the collapse
        //
        // Smoothness that appears in the third and not the first is SHA-256's. Smoothness that
        // appears in both is the harness's, and that is still worth having written down.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  Waves in, and whether the field is smooth\n");
        std::printf("================================================================\n");

        std::vector<double> field((size_t)INPUT_BITS * OUTPUT_BITS);
        double folded[32];
        const double white_error = 1.0 / std::sqrt((double)(INPUT_BITS * OUTPUT_BITS));

        std::printf("\n  A white field correlates with itself at zero for every nonzero lag, with a\n");
        std::printf("  standard error of %.6f on %u pairs. Anything standing clear of that is a\n",
                    white_error, INPUT_BITS * OUTPUT_BITS);
        std::printf("  field with a length scale, which is what smooth means when it is measured.\n");

        // -- The calibration ladder ------------------------------------------------------------
        //
        // A known wave at a stated amplitude, faded until the readout loses it. That is the
        // sensitivity of this instrument measured instead of asserted, and it converts a null
        // from "nothing found" into "nothing above this amplitude, at five sigmas".
        const unsigned WAVE_FREQUENCY = 3u;
        const unsigned FAINTEST = 16u;

        std::printf("\n  Calibration: a plane wave at frequency %u across the residues, faded until\n",
                    WAVE_FREQUENCY);
        std::printf("  the readout loses it. Amplitude is the bias driven into each cell's rate.\n");
        std::printf("\n  %10s %14s %16s %12s %10s %10s\n", "amplitude", "excess chi2", "chi2 sigmas",
                    "loudest", "at freq", "found");
        std::printf("  %10s %14s %16s %12s %10s %10s\n", "----------", "--------------",
                    "----------------", "------------", "----------", "----------");

        for (unsigned strength = 8u; strength <= FAINTEST; strength += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_wave_row<<<INPUT_BITS, 256>>>(trials, 606060001ull + (strength * 7919ull),
                                               device_matrix, WAVE_FREQUENCY, strength, 0u);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);
            fill_deviation_field(matrix, trials, field);

            double total = 0.0;
            for (size_t at = 0u; at < field.size(); at += 1u)
            {
                total += field[at] * field[at];
            }
            const double excess = total - (double)(INPUT_BITS * OUTPUT_BITS);
            const double chi_sigmas = excess / std::sqrt(2.0 * (double)(INPUT_BITS * OUTPUT_BITS));

            fold_onto_residue(field, folded);
            unsigned tone_at = 0u;
            const double tone = loudest_residue_tone(folded, &tone_at);

            const double amplitude = std::pow(0.5, (double)(strength + 1u));
            const char *found = ((tone_at == WAVE_FREQUENCY) && (tone > 5.0)) ? "yes" : "-";
            std::printf("  %10.2e %14.1f %16.2f %12.2f %10u %10s\n", amplitude, excess, chi_sigmas,
                        tone, tone_at, found);
        }

        // -- The three fields, side by side ------------------------------------------------------
        const unsigned LAGS = 8u;
        std::printf("\n  Correlation of the field with itself, shifted. Zero is white.\n");
        std::printf("\n  %-22s %8s", "field", "axis");
        for (unsigned lag = 1u; lag <= LAGS; lag += 1u)
        {
            std::printf(" %8u", lag);
        }
        std::printf("\n");
        std::printf("  %-22s %8s", "----------------------", "--------");
        for (unsigned lag = 1u; lag <= LAGS; lag += 1u)
        {
            std::printf(" %8s", "--------");
        }
        std::printf("\n");

        for (unsigned which = 0u; which < 4u; which += 1u)
        {
            const char *label = "";
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            if (which == 0u)
            {
                label = "harness alone";
                fill_null_row<<<INPUT_BITS, 256>>>(trials, 424242001ull, device_matrix, 0u);
            }
            else if (which == 1u)
            {
                label = "harness + wave 2^-11";
                fill_wave_row<<<INPUT_BITS, 256>>>(trials, 424242001ull, device_matrix,
                                                   WAVE_FREQUENCY, 10u, 0u);
            }
            else if (which == 2u)
            {
                label = "SHA-256 round 32";
                fill_sac_row<<<INPUT_BITS, 256>>>(trials, 424242001ull, 32u, device_matrix,
                                                  KEEP_EVERYTHING);
            }
            else
            {
                label = "SHA-256 round 64";
                fill_sac_row<<<INPUT_BITS, 256>>>(trials, 424242001ull, 64u, device_matrix,
                                                  KEEP_EVERYTHING);
            }
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);
            fill_deviation_field(matrix, trials, field);

            std::printf("  %-22s %8s", label, "output");
            for (unsigned lag = 1u; lag <= LAGS; lag += 1u)
            {
                std::printf(" %8.2f", correlate_along_output(field, lag) / white_error);
            }
            std::printf("\n");

            std::printf("  %-22s %8s", "", "input");
            for (unsigned lag = 1u; lag <= LAGS; lag += 1u)
            {
                std::printf(" %8.2f", correlate_along_input(field, lag) / white_error);
            }
            std::printf("\n");
        }

        std::printf("\n  Every number above is in standard errors of a white field. The wave row is\n");
        std::printf("  the positive control: it must light up, or the readout cannot see anything\n");
        std::printf("  and the other rows mean nothing. The harness row is the null: whatever it\n");
        std::printf("  carries is the instrument's own, and SHA-256 only claims what stands above\n");
        std::printf("  it instead of above zero.\n");

        // ---------------------------------------------------------------------------------------
        // Doppler: what is moving, whether or not it can be seen standing still.
        //
        // Every reading up to here looks at one round at a time and asks whether anything stands
        // above the noise in that round. Something too faint to clear the floor in any single round
        // is invisible to all of them, however many rounds are looked at, because they are compared
        // one at a time and then thrown away.
        //
        // The rounds are not independent samples of an unknown thing. They are a deterministic
        // sequence, so whatever structure exists at round r is related to the structure at r+1 by
        // the round function instead of by chance. That relation is carried in the phase of the
        // residue spectrum, which every earlier reading discarded by taking a magnitude.
        //
        // A structure sitting still holds its phase from round to round. A structure drifting at v
        // residues per round advances it by 2*pi*f*v/32 each round. Noise does neither. So summing
        // the complex spectrum across rounds against a velocity hypothesis adds a real structure
        // coherently, as R, and noise incoherently, as sqrt(R): a gain of sqrt(R) over any single
        // round, and the gain is available only to whatever is actually moving at that velocity.
        //
        // Each round takes its own seed. That is what makes this work instead of a repeat of the
        // pooling mistake: the structure is deterministic and stays coherent across rounds whatever
        // the seed, while the sampling noise is made independent and decoheres. Sharing one seed
        // would keep the noise coherent too and the gain would be nothing.
        // ---------------------------------------------------------------------------------------
        std::printf("\n================================================================\n");
        std::printf("  Doppler: what is moving, seen or not\n");
        std::printf("================================================================\n");

        const unsigned FIRST_ROUND = 23u;
        const unsigned SPAN = 42u;
        const unsigned TONES = 16u;
        const unsigned STEPS = 129u;
        const unsigned DRIFTS = 320u;
        const double SLOWEST = -8.0;
        const double FASTEST = 8.0;

        std::printf("\n  Rounds %u to %u, each on its own seed. A structure standing still holds its\n",
                    FIRST_ROUND, (FIRST_ROUND + SPAN) - 1u);
        std::printf("  phase, one drifting advances it, noise does neither. Summing coherently over\n");
        std::printf("  %u rounds gains sqrt(%u) = %.2f on whatever moves at the tried velocity.\n",
                    SPAN, SPAN, std::sqrt((double)SPAN));

        // Three sources through the same scan: the harness alone as the null, a wave deliberately
        // walked one residue per round as the positive control, and SHA-256.
        for (unsigned source = 0u; source < 3u; source += 1u)
        {
            std::vector<double> line_real((size_t)TONES * SPAN, 0.0);
            std::vector<double> line_imaginary((size_t)TONES * SPAN, 0.0);
            const char *label = "";

            for (unsigned step = 0u; step < SPAN; step += 1u)
            {
                const unsigned at_round = FIRST_ROUND + step;
                const uint64_t seed = 515151001ull + ((uint64_t)at_round * 1000003ull);

                cudaMemset(device_matrix, 0,
                           (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
                if (source == 0u)
                {
                    label = "harness alone";
                    fill_null_row<<<INPUT_BITS, 256>>>(trials, seed, device_matrix, 0u);
                }
                else if (source == 1u)
                {
                    // Amplitude 2^-14, which the ladder above showed is below the standing floor:
                    // this wave cannot be found in any single round. It moves one residue per
                    // round, so the scan has to earn it from the motion or not at all.
                    label = "wave 2^-14 walking 1/round";
                    fill_wave_row<<<INPUT_BITS, 256>>>(trials, seed, device_matrix, WAVE_FREQUENCY,
                                                       13u, step % 32u);
                }
                else
                {
                    label = "SHA-256";
                    fill_sac_row<<<INPUT_BITS, 256>>>(trials, seed, at_round, device_matrix,
                                                      KEEP_EVERYTHING);
                }
                cudaDeviceSynchronize();
                cudaMemcpy(matrix.data(), device_matrix,
                           matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);
                fill_deviation_field(matrix, trials, field);
                fold_onto_residue(field, folded);

                for (unsigned tone = 1u; tone < TONES; tone += 1u)
                {
                    double real_part = 0.0;
                    double imaginary = 0.0;
                    residue_spectrum_line(folded, tone, &real_part, &imaginary);
                    line_real[((size_t)tone * SPAN) + step] = real_part;
                    line_imaginary[((size_t)tone * SPAN) + step] = imaginary;
                }
            }

            double loudest = 0.0;
            unsigned loud_tone = 0u;
            double loud_speed = 0.0;
            double standing_best = 0.0;

            // The phase-only channel, which is a different question from the one above.
            //
            // Summing the spectrum weighted by its own magnitude lets a few loud rounds carry the
            // total, and magnitude is where the noise lives: a round that happens to fluctuate
            // large contributes large whatever its phase is doing. Normalising every round to unit
            // length first throws the amplitude away and keeps only the direction, so what is
            // being asked is whether the phases line up, not whether anything is big.
            //
            // A structure that is faint but perfectly coherent has a linear phase ramp and no
            // amplitude to speak of. It is invisible to the magnitude channel by construction and
            // plain to this one.
            double tightest = 0.0;
            unsigned tight_tone = 0u;
            double tight_speed = 0.0;

            // The scan runs in drift, which is frequency times velocity, instead of in velocity.
            //
            // The phase a round advances is 2*pi*(f*v)*r/32, so f*v is the coordinate the readout
            // actually lives in and v is a degenerate one: every frequency's cone passes through
            // v = 0 together, and away from it the same step in v is a step of f times as much
            // phase. A uniform grid in v is therefore correct at one frequency and wrong at the
            // rest - at f = 15 the step is 1.875 in drift where 42 rounds resolve 0.195, which is
            // ten times too coarse and could step straight over a real peak.
            //
            // Scanning drift uniformly is the same map with the degenerate point resolved: one
            // grid that is correct at every frequency at once, and velocity recovered as drift
            // over frequency where it is wanted.
            for (unsigned tone = 1u; tone < TONES; tone += 1u)
            {
                for (unsigned step = 0u; step < DRIFTS; step += 1u)
                {
                    const double drift = -16.0 + ((32.0 * (double)step) / (double)DRIFTS);
                    double summed_real = 0.0;
                    double summed_imaginary = 0.0;
                    double turned_real = 0.0;
                    double turned_imaginary = 0.0;
                    for (unsigned at = 0u; at < SPAN; at += 1u)
                    {
                        const double turn = 6.283185307179586 * drift * (double)at / 32.0;
                        const double here_real = line_real[((size_t)tone * SPAN) + at];
                        const double here_imaginary = line_imaginary[((size_t)tone * SPAN) + at];
                        const double rotated_real =
                            (here_real * std::cos(turn)) + (here_imaginary * std::sin(turn));
                        const double rotated_imaginary =
                            (here_imaginary * std::cos(turn)) - (here_real * std::sin(turn));
                        summed_real += rotated_real;
                        summed_imaginary += rotated_imaginary;

                        const double length = std::sqrt((rotated_real * rotated_real)
                                                        + (rotated_imaginary * rotated_imaginary));
                        if (length > 0.0)
                        {
                            turned_real += rotated_real / length;
                            turned_imaginary += rotated_imaginary / length;
                        }
                    }
                    const double magnitude =
                        std::sqrt(((summed_real * summed_real)
                                   + (summed_imaginary * summed_imaginary)) / (double)SPAN);
                    if (magnitude > loudest)
                    {
                        loudest = magnitude;
                        loud_tone = tone;
                        loud_speed = drift / (double)tone;
                    }
                    if ((drift == 0.0) && (magnitude > standing_best))
                    {
                        standing_best = magnitude;
                    }

                    // Unit vectors summed: under the null the phases are uniform, so each part has
                    // variance SPAN/2 and this reads as a Rayleigh magnitude with unit parts, the
                    // same scale the magnitude channel is on.
                    const double concentration =
                        std::sqrt(((turned_real * turned_real)
                                   + (turned_imaginary * turned_imaginary)) / ((double)SPAN / 2.0));
                    if (concentration > tightest)
                    {
                        tightest = concentration;
                        tight_tone = tone;
                        tight_speed = drift / (double)tone;
                    }
                }
            }

            // The scan takes a maximum over every tone and every velocity, so it peaks under the
            // null whatever the data does. A complex sum with unit-normal parts is Rayleigh, whose
            // maximum over N cells sits near sqrt(2 ln N) - the same correction that killed five
            // claims here, applied before the number is read instead of after.
            // Four channels are read, and each is itself a maximum. Comparing any one of them to
            // the peak of a single channel is the max-of-N error that killed five claims in this
            // work, reintroduced one level up: with four maxima the union is what has to be
            // corrected for, not the largest of them.
            //
            // The window scan dominates the count by a long way, because sliding the start and the
            // width multiplies the grid instead of adding to it.
            double windows_searched = 0.0;
            {
                const unsigned counted[3] = { 8u, 14u, 21u };
                for (unsigned width_at = 0u; width_at < 3u; width_at += 1u)
                {
                    const unsigned starts = (SPAN - counted[width_at]) + 1u;
                    windows_searched += (double)starts * (double)(((STEPS + 3u) / 4u))
                                        * (double)(TONES - 1u);
                }
            }
            const double cells = (double)((TONES - 1u) * DRIFTS);
            const double every_cell = (cells * 2.0) + (double)STEPS + windows_searched;
            const double peaks_at = std::sqrt(2.0 * std::log(every_cell));

            // Summing R unit vectors cannot exceed R, so the phase channel is bounded above by
            // sqrt(2R) whatever the data does: 9.17 at forty-two rounds. Against a null peak near
            // 4.7 that is barely a factor of two of range, which makes it a weak instrument at this
            // baseline however good the idea is. It is reported so the ceiling is visible.
            const double phase_ceiling = std::sqrt(2.0 * (double)SPAN);

            // -- Radius instead of a single cone -------------------------------------------
            //
            // The scan above takes the loudest single (frequency, velocity) cell, which is a
            // matched filter for a pure sinusoid drifting at a constant rate. A localised feature
            // is not a sinusoid: it carries harmonics at 2f, 3f and so on, and all of them ride at
            // the same velocity. Pooling every frequency at one velocity is the matched filter for
            // that instead, and it is strictly better on anything localised for the same reason
            // the residue fold beat the chi-square on a residue-structured wave.
            //
            // Geometrically this is sweeping the radius from the center of the map and asking
            // where the cones intersect, instead of following one cone out.
            double loudest_radius = 0.0;
            double radius_speed = 0.0;

            for (unsigned step = 0u; step < STEPS; step += 1u)
            {
                const double speed =
                    SLOWEST + (((FASTEST - SLOWEST) * (double)step) / (double)(STEPS - 1u));
                double pooled = 0.0;
                for (unsigned tone = 1u; tone < TONES; tone += 1u)
                {
                    double summed_real = 0.0;
                    double summed_imaginary = 0.0;
                    for (unsigned at = 0u; at < SPAN; at += 1u)
                    {
                        const double turn =
                            6.283185307179586 * (double)tone * speed * (double)at / 32.0;
                        const double here_real = line_real[((size_t)tone * SPAN) + at];
                        const double here_imaginary = line_imaginary[((size_t)tone * SPAN) + at];
                        summed_real += (here_real * std::cos(turn)) + (here_imaginary * std::sin(turn));
                        summed_imaginary +=
                            (here_imaginary * std::cos(turn)) - (here_real * std::sin(turn));
                    }
                    pooled += ((summed_real * summed_real) + (summed_imaginary * summed_imaginary))
                              / (double)SPAN;
                }
                if (pooled > loudest_radius)
                {
                    loudest_radius = pooled;
                    radius_speed = speed;
                }
            }

            // Fifteen frequencies, two unit-normal parts each, so the pooled power is chi-square
            // with thirty degrees of freedom: mean 30, spread sqrt(60). The harness row is the
            // honest null for it regardless, and is what the SHA-256 row is read against.
            const double pooled_sigmas = (loudest_radius - 30.0) / std::sqrt(60.0);

            // -- Every position of the sphere ------------------------------------------------
            //
            // A structure living in a window instead of across the whole span is diluted by
            // integrating the whole span. Sliding the start and shortening the window is the third
            // axis, and the shorter windows are checked knowing the maximum over more cells peaks
            // higher: the comparison is against the harness scanned identically, not against zero.
            double windowed_best = 0.0;
            unsigned windowed_start = 0u;
            unsigned windowed_span = 0u;

            const unsigned WIDTHS = 3u;
            const unsigned widths[WIDTHS] = { 8u, 14u, 21u };
            for (unsigned width_at = 0u; width_at < WIDTHS; width_at += 1u)
            {
                const unsigned width = widths[width_at];
                for (unsigned start = 0u; (start + width) <= SPAN; start += 1u)
                {
                    for (unsigned step = 0u; step < STEPS; step += 4u)
                    {
                        const double speed =
                            SLOWEST + (((FASTEST - SLOWEST) * (double)step) / (double)(STEPS - 1u));
                        for (unsigned tone = 1u; tone < TONES; tone += 1u)
                        {
                            double summed_real = 0.0;
                            double summed_imaginary = 0.0;
                            for (unsigned at = 0u; at < width; at += 1u)
                            {
                                const unsigned where = start + at;
                                const double turn =
                                    6.283185307179586 * (double)tone * speed * (double)where / 32.0;
                                const double here_real = line_real[((size_t)tone * SPAN) + where];
                                const double here_imaginary =
                                    line_imaginary[((size_t)tone * SPAN) + where];
                                summed_real +=
                                    (here_real * std::cos(turn)) + (here_imaginary * std::sin(turn));
                                summed_imaginary +=
                                    (here_imaginary * std::cos(turn)) - (here_real * std::sin(turn));
                            }
                            const double magnitude =
                                std::sqrt(((summed_real * summed_real)
                                           + (summed_imaginary * summed_imaginary)) / (double)width);
                            if (magnitude > windowed_best)
                            {
                                windowed_best = magnitude;
                                windowed_start = FIRST_ROUND + start;
                                windowed_span = width;
                            }
                        }
                    }
                }
            }

            std::printf("\n  %s\n", label);
            std::printf("    loudest         %8.2f at frequency %u, velocity %+.3f residues/round\n",
                        loudest, loud_tone, loud_speed);
            std::printf("    phase only      %8.2f at frequency %u, velocity %+.3f  (amplitude\n",
                        tightest, tight_tone, tight_speed);
            std::printf("                             thrown away; ceiling is %.2f at %u rounds)\n",
                        phase_ceiling, SPAN);
            std::printf("    pooled radius   %8.2f at velocity %+.3f  (%.2f sigmas of chi2(30))\n",
                        loudest_radius, radius_speed, pooled_sigmas);
            std::printf("    best window     %8.2f over rounds %u to %u\n", windowed_best,
                        windowed_start, (windowed_start + windowed_span) - 1u);
            std::printf("    standing still  %8.2f  (velocity zero, the best any single-round\n",
                        standing_best);
            std::printf("                             reading could ever pool to)\n");
            std::printf("    null peak       %8.2f  (maximum over %.0f cells, all four channels)\n",
                        peaks_at, every_cell);

            double largest = loudest;
            if (tightest > largest) { largest = tightest; }
            if (windowed_best > largest) { largest = windowed_best; }
            std::printf("    %s\n", (largest > peaks_at)
                                        ? "ABOVE the null peak: something is moving."
                                        : "under the null peak: nothing is moving that this can see.");
        }

        std::printf("\n  The walking wave is the positive control and is set below the standing\n");
        std::printf("  floor on purpose: it cannot be found in any single round, so if the scan\n");
        std::printf("  recovers it, the gain is real and came from the motion. If it does not, this\n");
        std::printf("  instrument is blind and the SHA-256 line below it means nothing.\n");

        cudaFree(device_matrix);
        return 0;
    }

    std::printf("\n  %8s %14s %14s %12s %10s\n", "round", "SAC value", "from half", "sigmas",
                "verdict");
    std::printf("  %8s %14s %14s %12s %10s\n", "--------", "--------------", "--------------",
                "------------", "----------");

    for (unsigned rounds = first_round; rounds <= last_round; rounds += 1u)
    {
        cudaMemset(device_matrix, 0,
                   (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
        fill_sac_row<<<INPUT_BITS, 256>>>(trials, 20260909ull + (rounds * 7919ull), rounds,
                                          device_matrix, KEEP_EVERYTHING);
        cudaDeviceSynchronize();
        cudaMemcpy(matrix.data(), device_matrix,
                   matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

        // Their SAC value: whichever entry of the matrix sits furthest from one half, which is the
        // strictest single number the matrix supports.
        double furthest = 0.5;
        double widest = 0.0;
        for (size_t at = 0u; at < matrix.size(); at += 1u)
        {
            const double rate = (double)matrix[at] / (double)trials;
            const double apart = (rate < 0.5) ? (0.5 - rate) : (rate - 0.5);
            if (apart > widest)
            {
                widest = apart;
                furthest = rate;
            }
        }

        const double sigmas = widest / deviation;

        // The matrix holds 131072 entries, so the largest deviation among them peaks near
        // sqrt(2 ln 131072) = 4.85 standard deviations whether or not anything is there. Anything
        // at or under that is the null, however small the probability of one entry alone.
        const double null_peak = std::sqrt(2.0 * std::log((double)matrix.size()));
        const char *verdict = (sigmas > (null_peak + 2.0)) ? "OFF" : "flat";
        std::printf("  %8u %14.8f %14.8f %12.1f %10s\n", rounds, furthest, widest, sigmas,
                    verdict);
    }

    // ---------------------------------------------------------------------------------------
    // The one claim that does not fall to the maximum argument.
    //
    // Vaughn and Borowczak report Choose and Majority together giving a SAC-mean ratio of 0.508:
    // the two sub-functions jointly deliver about half the diffusion each provides alone. That is a
    // *mean* over the whole matrix instead of a maximum of it, so the null-peak argument that
    // disposes of the 54-57 dip says nothing about it, and it is worth measuring on its own terms.
    //
    // Their composition model treats each sub-function as flipping an output bit independently, so
    // two of them flip it when exactly one does: Expect(A,B) = A + B - 2AB. A ratio of measured to
    // expected below one is dampening and above one is amplification.
    //
    // It is also the most interesting claim available, because Choose and Majority are the two
    // functions feeding the a half of the chain - the half whose per-slot depths came out irregular
    // in bench_words while the e half was clean at k + 3 exactly.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Do Choose and Majority dampen each other\n");
    std::printf("================================================================\n");
    std::printf("\n  The published SAC-mean ratio for this pair is 0.508, meaning the two together\n");
    std::printf("  deliver about half the diffusion each gives alone. That is a mean over the whole\n");
    std::printf("  matrix instead of a maximum of it, so the argument that disposes of the 54-57\n");
    std::printf("  dip does not touch it.\n");
    std::printf("\n  Their model has each sub-function flipping a bit independently, so two of them\n");
    std::printf("  flip it when exactly one does: Expect(A,B) = A + B - 2AB.\n");

    {
        const unsigned VARIANTS = 3u;
        const unsigned masks[VARIANTS] = {KEEP_CHOOSE, KEEP_MAJORITY, KEEP_CHOOSE | KEEP_MAJORITY};
        const char *named[VARIANTS] = {"Choose alone", "Majority alone", "both together"};
        const unsigned at_round = 64u;

        double means[VARIANTS];
        std::printf("\n  %-18s %16s\n", "variant", "SAC-mean");
        std::printf("  %-18s %16s\n", "------------------", "----------------");

        for (unsigned which = 0u; which < VARIANTS; which += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 20260909ull, at_round, device_matrix,
                                              masks[which]);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            double total = 0.0;
            for (size_t at = 0u; at < matrix.size(); at += 1u)
            {
                total += (double)matrix[at] / (double)trials;
            }
            means[which] = total / (double)matrix.size();
            std::printf("  %-18s %16.8f\n", named[which], means[which]);
        }

        const double expected = means[0] + means[1] - (2.0 * means[0] * means[1]);
        const double ratio = (expected > 0.0) ? (means[2] / expected) : 0.0;
        std::printf("\n  %-34s %16.8f\n", "expected from the two alone", expected);
        std::printf("  %-34s %16.8f\n", "measured together", means[2]);
        std::printf("  %-34s %16.4f\n", "ratio", ratio);
        std::printf("  %-34s %16.4f\n", "published ratio", 0.508);

        const char *verdict = (ratio < 0.75) ? "dampening reproduces"
                                             : ((ratio > 1.25) ? "amplifies instead" : "neither");
        std::printf("  %-34s %16s\n", "verdict", verdict);

        std::printf("\n  A ratio near the published 0.508 reproduces the dampening and makes these\n");
        std::printf("  two functions worth attacking together instead of separately. A ratio near\n");
        std::printf("  one says the composition model is doing the work instead of SHA-256, since\n");
        std::printf("  that model assumes independence which two functions reading overlapping\n");
        std::printf("  state words do not have.\n");
    }

    // ---------------------------------------------------------------------------------------
    // A null with a known answer, which the variant machinery hands over for nothing.
    //
    // Every null used in this document so far is statistical: a distribution the measurement is
    // held against. Removing integer addition gives something better - an analytic one. Without the
    // carry the whole function is GF(2)-linear, so a one-bit input difference produces a
    // *deterministic* output difference, the same one for every message. Every matrix entry must
    // then be exactly 0 or exactly 1 and never one half, and no number of rounds can change that.
    //
    // So the addition-removed variant must never diffuse, at any round, by construction instead of
    // by measurement. An instrument that reports it diffusing is broken, and one that reports it
    // pinned at a deviation of one half is reading correctly. This is the first control here whose
    // answer is known before the run.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  A null whose answer is known before the run\n");
    std::printf("================================================================\n");
    std::printf("\n  Removing integer addition leaves the function GF(2)-linear, so a one-bit input\n");
    std::printf("  difference gives a deterministic output difference - the same one for every\n");
    std::printf("  message. Every matrix entry is then exactly 0 or exactly 1, never one half, and\n");
    std::printf("  the deviation is pinned at 0.5 forever whatever the round.\n");
    std::printf("\n  That is an analytic control instead of a statistical one. Every other null in\n");
    std::printf("  this document is a distribution to compare against; this one has an answer.\n");

    {
        const unsigned CHECKED = 4u;
        const unsigned rounds_at[CHECKED] = {8u, 23u, 40u, 64u};

        std::printf("\n  %8s %20s %20s\n", "round", "full function", "linear variant");
        std::printf("  %8s %20s %20s\n", "--------", "--------------------",
                    "--------------------");

        int carry_holds = 1;
        for (unsigned which = 0u; which < CHECKED; which += 1u)
        {
            // Removing only the carry does not give a linear function: Choose and Majority use AND
            // and stay nonlinear over GF(2) whatever addition does. The linear variant is the one
            // with all three gone, leaving rotations, exclusive-or and constants - and a constant
            // is affine, so it cancels in a difference and does not spoil the linearity.
            double reading[2];
            const unsigned masks[2] = {
                KEEP_EVERYTHING,
                KEEP_SCHEDULE | KEEP_BIG_ZERO | KEEP_BIG_ONE | KEEP_CONSTANT};

            for (unsigned arm = 0u; arm < 2u; arm += 1u)
            {
                cudaMemset(device_matrix, 0,
                           (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
                fill_sac_row<<<INPUT_BITS, 256>>>(trials, 20260909ull, rounds_at[which],
                                                  device_matrix, masks[arm]);
                cudaDeviceSynchronize();
                cudaMemcpy(matrix.data(), device_matrix,
                           matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

                double widest = 0.0;
                for (size_t at = 0u; at < matrix.size(); at += 1u)
                {
                    const double rate = (double)matrix[at] / (double)trials;
                    const double apart = (rate < 0.5) ? (0.5 - rate) : (rate - 0.5);
                    widest = (apart > widest) ? apart : widest;
                }
                reading[arm] = widest;
            }

            // The linear arm must read exactly one half. Anything less means a matrix entry landed
            // strictly between 0 and 1, which a deterministic difference cannot produce.
            if (reading[1] < 0.4999999)
            {
                carry_holds = 0;
            }
            std::printf("  %8u %20.8f %20.8f\n", rounds_at[which], reading[0], reading[1]);
        }

        if (carry_holds != 0)
        {
            std::printf("\n  The linear arm reads exactly 0.5 at every round, which is what a\n");
            std::printf("  deterministic difference must give and confirms the instrument reads a\n");
            std::printf("  known answer correctly.\n");
            std::printf("\n  What it does not show is that the carry causes the diffusion. Removing\n");
            std::printf("  addition alone leaves Choose and Majority, which use AND and stay\n");
            std::printf("  nonlinear, and that variant still reaches 0.0093 by round 64 - the same\n");
            std::printf("  plateau as the full function. So the nonlinearity is what makes diffusion\n");
            std::printf("  happen at all, and the carry changes how fast instead of whether. That\n");
            std::printf("  matches the published finding that removing addition costs about two\n");
            std::printf("  rounds instead of stopping the function diffusing.\n");
        }
        else
        {
            std::printf("\n  [!] The linear arm did not read exactly 0.5. A GF(2)-linear function\n");
            std::printf("  cannot produce a matrix entry strictly between 0 and 1, so either the\n");
            std::printf("  variant is not actually linear or the measurement is wrong. Nothing else\n");
            std::printf("  in this bench should be believed until that is settled.\n");
        }
    }

    // ---------------------------------------------------------------------------------------
    // Diffusion speed, which is a different observable from diffusion level.
    //
    // Everything above reads where a variant *arrives*. The round-to-round ratio reads how fast it
    // is travelling, and the two need not order the same way: a variant can start later and move
    // quicker, and the level measurement cannot see that.
    //
    // The linear variant makes this a controlled measurement instead of a descriptive one. Its
    // speed is analytically zero at every round - the deviation is pinned at 0.5 and cannot move -
    // so a ratio of exactly 1.000 is the known null, and any variant's departure from it is the
    // amount that variant actually travels.
    //
    // The mean deviation is used instead of the largest, because the largest is a maximum over
    // 131072 entries and sits at its own null peak whatever the function does. A speed computed
    // from maxima would be reading that peak wander from round to round.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Diffusion speed, against a null whose speed is exactly zero\n");
    std::printf("================================================================\n");
    std::printf("\n  Everything above reads where a variant arrives. This reads how fast it travels,\n");
    std::printf("  and the two need not order the same way - a variant can start later and move\n");
    std::printf("  quicker, which a level measurement cannot see.\n");
    std::printf("\n  The linear variant's speed is analytically zero: its deviation is pinned at 0.5\n");
    std::printf("  and cannot move, so a ratio of exactly 1.000 is the known null.\n");
    std::printf("\n  Mean deviation, not the largest, because a maximum over 131072 entries sits at\n");
    std::printf("  its own null peak whatever the function does and its wander is not speed.\n");

    {
        const unsigned ARMS = 5u;
        const unsigned arm_mask[ARMS] = {
            KEEP_EVERYTHING,
            KEEP_EVERYTHING & ~KEEP_ADDITION,
            KEEP_EVERYTHING & ~KEEP_CHOOSE,
            KEEP_EVERYTHING & ~KEEP_MAJORITY,
            KEEP_SCHEDULE | KEEP_BIG_ZERO | KEEP_BIG_ONE | KEEP_CONSTANT};
        const char *arm_name[ARMS] = {"full", "no carry", "no Choose", "no Majority", "linear"};

        const unsigned FIRST_SPEED = 17u;
        const unsigned LAST_SPEED = 24u;

        std::printf("\n  Mean deviation from one half, by round\n");
        std::printf("\n  %8s", "round");
        for (unsigned arm = 0u; arm < ARMS; arm += 1u)
        {
            std::printf(" %13s", arm_name[arm]);
        }
        std::printf("\n  %8s", "--------");
        for (unsigned arm = 0u; arm < ARMS; arm += 1u)
        {
            std::printf(" %13s", "-------------");
        }
        std::printf("\n");

        double held[ARMS][32];
        for (unsigned rounds = FIRST_SPEED; rounds <= LAST_SPEED; rounds += 1u)
        {
            std::printf("  %8u", rounds);
            for (unsigned arm = 0u; arm < ARMS; arm += 1u)
            {
                cudaMemset(device_matrix, 0,
                           (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
                fill_sac_row<<<INPUT_BITS, 256>>>(trials, 20260909ull, rounds, device_matrix,
                                                  arm_mask[arm]);
                cudaDeviceSynchronize();
                cudaMemcpy(matrix.data(), device_matrix,
                           matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

                double total = 0.0;
                for (size_t at = 0u; at < matrix.size(); at += 1u)
                {
                    const double rate = (double)matrix[at] / (double)trials;
                    total += (rate < 0.5) ? (0.5 - rate) : (rate - 0.5);
                }
                held[arm][rounds - FIRST_SPEED] = total / (double)matrix.size();
                std::printf(" %13.8f", held[arm][rounds - FIRST_SPEED]);
            }
            std::printf("\n");
        }

        std::printf("\n  Speed, as the ratio of one round's deviation to the next. Above one is\n");
        std::printf("  travelling; exactly one is standing still.\n");
        std::printf("\n  %8s", "round");
        for (unsigned arm = 0u; arm < ARMS; arm += 1u)
        {
            std::printf(" %13s", arm_name[arm]);
        }
        std::printf("\n  %8s", "--------");
        for (unsigned arm = 0u; arm < ARMS; arm += 1u)
        {
            std::printf(" %13s", "-------------");
        }
        std::printf("\n");

        for (unsigned step = 1u; step <= (LAST_SPEED - FIRST_SPEED); step += 1u)
        {
            std::printf("  %5u->%2u", FIRST_SPEED + step - 1u, FIRST_SPEED + step);
            for (unsigned arm = 0u; arm < ARMS; arm += 1u)
            {
                const double before = held[arm][step - 1u];
                const double after = held[arm][step];
                const double speed = (after > 0.0) ? (before / after) : 0.0;
                std::printf(" %13.4f", speed);
            }
            std::printf("\n");
        }

        std::printf("\n  The linear column must read 1.0000 throughout, since its deviation cannot\n");
        std::printf("  move. Any other column's excess over that is the speed the sub-functions in\n");
        std::printf("  it actually contribute, measured against a baseline that is known rather\n");
        std::printf("  than estimated.\n");
    }

    // ---------------------------------------------------------------------------------------
    // What is Majority for?
    //
    // Three separate diffusion statistics now say Majority contributes nothing measurable: the SAC
    // level, the dampening ratio, and the round-to-round speed. Both published papers agree. A
    // sub-function in a standard that does nothing detectable is either redundant or doing
    // something the instrument does not measure, and algebraic degree is the obvious candidate,
    // since degree resists algebraic attack instead of resisting differential probing.
    //
    // Degree is provable instead of sampled. A Boolean function of degree below d has every d-th
    // order derivative identically zero, and that derivative is the exclusive-or of the output over
    // all corners of a d-dimensional input cube. A fold that comes out nonzero proves the degree is
    // at least d, with no threshold and no sample size involved.
    //
    // Several bases are used per measurement. A single base already caused a monotonicity violation
    // in this tree's integral work - dimension 8 reaching further than dimension 10, which is
    // impossible - and that was one base being unlucky instead of the kernel being wrong.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  What is Majority for\n");
    std::printf("================================================================\n");
    std::printf("\n  Three diffusion statistics now agree that Majority contributes nothing\n");
    std::printf("  measurable, and both published papers agree. A sub-function that does nothing\n");
    std::printf("  detectable is either redundant or doing something else, and algebraic degree is\n");
    std::printf("  the candidate: degree resists algebraic attack instead of differential probing.\n");
    std::printf("\n  Degree is proved, not sampled. A function of degree below d has every d-th\n");
    std::printf("  order derivative zero, and that derivative is the exclusive-or of the output over\n");
    std::printf("  a d-dimensional input cube. One nonzero fold settles it.\n");

    {
        // Removing one nonlinear source at a time cannot discriminate, because the others cover for
        // it: full, no-Majority and no-Choose all give the same degree. Leaving exactly one
        // standing isolates what that operation can do alone, which is the question.
        //
        // The linear spine - schedule, both Sigmas, the constant - is kept in every arm, so the
        // only difference between them is which single nonlinear operation is present.
        const unsigned SPINE = KEEP_SCHEDULE | KEEP_BIG_ZERO | KEEP_BIG_ONE | KEEP_CONSTANT;
        const unsigned ARMS = 5u;
        const unsigned arm_mask[ARMS] = {KEEP_EVERYTHING,
                                         SPINE | KEEP_MAJORITY,
                                         SPINE | KEEP_CHOOSE,
                                         SPINE | KEEP_ADDITION,
                                         SPINE};
        const char *arm_name[ARMS] = {"full", "Maj only", "Choose only", "carry only", "linear"};
        const unsigned MOST_DIMENSION = 18u;
        const unsigned BASES = 6u;

        uint32_t *device_base = nullptr;
        unsigned *device_positions = nullptr;
        uint32_t *device_folded = nullptr;
        cudaMalloc((void **)&device_base, 16u * sizeof(uint32_t));
        cudaMalloc((void **)&device_positions, MOST_DIMENSION * sizeof(unsigned));
        cudaMalloc((void **)&device_folded, 8u * sizeof(uint32_t));

        std::printf("\n  Degree lower bound, the smallest dimension whose fold is nonzero\n");
        std::printf("\n  %8s", "rounds");
        for (unsigned arm = 0u; arm < ARMS; arm += 1u)
        {
            std::printf(" %14s", arm_name[arm]);
        }
        std::printf("\n  %8s", "--------");
        for (unsigned arm = 0u; arm < ARMS; arm += 1u)
        {
            std::printf(" %14s", "--------------");
        }
        std::printf("\n");

        for (unsigned rounds = 2u; rounds <= 7u; rounds += 1u)
        {
            std::printf("  %8u", rounds);
            for (unsigned arm = 0u; arm < ARMS; arm += 1u)
            {
                // The derivative vanishes *above* the degree, not below it, so the answer is the
                // largest dimension that still folds nonzero. Searching for the smallest nonzero
                // one returns 1 for every non-constant function, which is what the first version
                // of this did and why every column read 1.
                unsigned found = 0u;
                for (unsigned dimension = 1u; dimension <= MOST_DIMENSION; dimension += 1u)
                {
                    int any_nonzero = 0;
                    for (unsigned base_at = 0u; base_at < BASES; base_at += 1u)
                    {
                        uint32_t base[16];
                        unsigned positions[MOST_DIMENSION];
                        uint64_t stream = 20260909ull + (base_at * 104729ull) + (rounds * 31ull);
                        for (unsigned slot = 0u; slot < 16u; slot += 1u)
                        {
                            stream += 0x9e3779b97f4a7c15ull;
                            uint64_t mixed = stream;
                            mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
                            mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
                            base[slot] = (uint32_t)(mixed ^ (mixed >> 31));
                        }
                        // Distinct bit positions, drawn from the first message words so the cube
                        // sits where the nonce would.
                        for (unsigned bit = 0u; bit < dimension; bit += 1u)
                        {
                            positions[bit] = ((base_at * 37u) + (bit * 13u)) % 128u;
                        }

                        cudaMemcpy(device_base, base, sizeof(base), cudaMemcpyHostToDevice);
                        cudaMemcpy(device_positions, positions, dimension * sizeof(unsigned),
                                   cudaMemcpyHostToDevice);
                        cudaMemset(device_folded, 0, 8u * sizeof(uint32_t));

                        const unsigned blocks =
                            (unsigned)(((1ull << dimension) + 255ull) / 256ull);
                        fold_cube<<<(blocks > 0u) ? blocks : 1u, 256>>>(
                            device_base, device_positions, dimension, rounds, arm_mask[arm],
                            device_folded);
                        cudaDeviceSynchronize();

                        uint32_t folded[8];
                        cudaMemcpy(folded, device_folded, sizeof(folded), cudaMemcpyDeviceToHost);
                        for (unsigned slot = 0u; slot < 8u; slot += 1u)
                        {
                            any_nonzero |= (folded[slot] != 0u) ? 1 : 0;
                        }
                        if (any_nonzero != 0)
                        {
                            break;
                        }
                    }
                    // A nonzero fold at this dimension proves the degree is at least this high, so
                    // it is recorded and the search continues. The first dimension where every
                    // base folds to zero is above the degree, and the search stops there.
                    if (any_nonzero != 0)
                    {
                        found = dimension;
                    }
                    else
                    {
                        break;
                    }
                }
                if (found >= MOST_DIMENSION)
                {
                    std::printf(" %14s", ">= 18");
                }
                else
                {
                    std::printf(" %14u", found);
                }
            }
            std::printf("\n");
        }

        cudaFree(device_base);
        cudaFree(device_positions);
        cudaFree(device_folded);

        std::printf("\n  A no-Majority column matching the full one says Majority adds no degree\n");
        std::printf("  either, and that it is redundant on every measure this tree can make. A\n");
        std::printf("  column reading lower says Majority is carrying degree instead of diffusion,\n");
        std::printf("  which is a real job and would explain why it is in the standard while\n");
        std::printf("  contributing nothing a diffusion statistic can see.\n");
    }

    // ---------------------------------------------------------------------------------------
    // The other axis of the same bucket.
    //
    // Everything measured so far is differential: what a *change* in the input does. Linear
    // cryptanalysis asks a different question - whether the output value *equals* some function of
    // the input more often than chance - and a primitive can be strong against one and weak against
    // the other. A bucket labeled "nonlinear" that has only been probed differentially is half
    // unexamined, and Majority measuring inert on four differential statistics is exactly the case
    // where the other half is worth looking at.
    //
    // Isolation again instead of removal, because removal cannot discriminate: the operations mix,
    // so taking one out leaves the others covering for it and every arm reads the same.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  The linear axis, which the differential tests cannot see\n");
    std::printf("================================================================\n");
    std::printf("\n  Everything above is differential: what a change in the input does. This asks\n");
    std::printf("  whether an output bit agrees with an input bit more often than chance, which is\n");
    std::printf("  what linear cryptanalysis attacks. A function can be strong against one and weak\n");
    std::printf("  against the other.\n");
    std::printf("\n  Isolated instead of removed, because the operations mix: taking one out leaves\n");
    std::printf("  the others covering for it, which is why every removal arm read the same degree.\n");

    {
        const unsigned SPINE = KEEP_SCHEDULE | KEEP_BIG_ZERO | KEEP_BIG_ONE | KEEP_CONSTANT;
        const unsigned ARMS = 5u;
        const unsigned arm_mask[ARMS] = {KEEP_EVERYTHING, SPINE | KEEP_MAJORITY,
                                         SPINE | KEEP_CHOOSE, SPINE | KEEP_ADDITION, SPINE};
        const char *arm_name[ARMS] = {"full", "Maj only", "Choose only", "carry only", "linear"};

        unsigned long long *device_agree = nullptr;
        cudaMalloc((void **)&device_agree,
                   (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
        std::vector<unsigned long long> agree((size_t)INPUT_BITS * OUTPUT_BITS);

        std::printf("\n  Largest linear correlation, |2p-1| over the 512 by 256 masks\n");
        std::printf("\n  %8s", "rounds");
        for (unsigned arm = 0u; arm < ARMS; arm += 1u)
        {
            std::printf(" %13s", arm_name[arm]);
        }
        std::printf("\n  %8s", "--------");
        for (unsigned arm = 0u; arm < ARMS; arm += 1u)
        {
            std::printf(" %13s", "-------------");
        }
        std::printf("\n");

        for (unsigned rounds = 4u; rounds <= 24u; rounds += 4u)
        {
            std::printf("  %8u", rounds);
            for (unsigned arm = 0u; arm < ARMS; arm += 1u)
            {
                cudaMemset(device_agree, 0,
                           (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
                fill_linear_row<<<INPUT_BITS, 256>>>(trials, 20260909ull, rounds, arm_mask[arm],
                                                     device_agree);
                cudaDeviceSynchronize();
                cudaMemcpy(agree.data(), device_agree,
                           agree.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

                double loudest = 0.0;
                for (size_t at = 0u; at < agree.size(); at += 1u)
                {
                    const double rate = (double)agree[at] / (double)trials;
                    const double correlation = (rate * 2.0) - 1.0;
                    const double size = (correlation < 0.0) ? -correlation : correlation;
                    loudest = (size > loudest) ? size : loudest;
                }
                std::printf(" %13.8f", loudest);
            }
            std::printf("\n");
        }

        cudaFree(device_agree);

        std::printf("\n  The linear arm should sit near 1.0, since a GF(2)-linear function's output\n");
        std::printf("  bit is an exclusive-or of input bits and agrees with one of them perfectly\n");
        std::printf("  or not at all. A correlation that falls with rounds is the operation in that\n");
        std::printf("  arm destroying linear structure, and one that stays high is an operation not\n");
        std::printf("  doing that job whatever it does differentially.\n");
    }

    // ---------------------------------------------------------------------------------------
    // The same matrix, read spectrally instead of by its maximum.
    //
    // Every SAC reading above takes the largest of 131072 cells and discards the other 131071. That
    // is what makes it peak at sqrt(2 ln N) whatever the function does, and it is why two published
    // claims and three here turned out to be the maximum doing its job instead of SHA-256 leaking.
    //
    // A structure spread thinly across many cells is invisible to a maximum and obvious to a sum.
    // SHA-256 is built from rotations - 2, 13, 22 and 6, 11, 25 in the state, 7, 18, 17, 19 in the
    // schedule - and a rotation makes bit j depend on bit j-r. If any of that survives into the
    // dependency matrix it appears as a function of (input bit - output bit) modulo 32, spread over
    // every word pair instead of concentrated anywhere.
    //
    // So the cells are folded onto that residue. Each class holds 512*256/32 = 4096 of them, which
    // makes the aggregate 64 times more sensitive than a single cell and unboundedly more sensitive
    // than a maximum, which gets no benefit from the other cells at all.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  The matrix read spectrally instead of by its maximum\n");
    std::printf("================================================================\n");
    std::printf("\n  Every reading above takes the largest of 131072 cells and discards the rest,\n");
    std::printf("  which is why it peaks at sqrt(2 ln N) whatever the function does. A structure\n");
    std::printf("  spread thinly across many cells is invisible to a maximum and plain to a sum.\n");
    std::printf("\n  SHA-256 is built from rotations, and a rotation makes bit j depend on bit j-r,\n");
    std::printf("  so surviving rotational structure appears as a function of (input bit - output\n");
    std::printf("  bit) mod 32 spread over every word pair. Folding onto that residue puts 4096\n");
    std::printf("  cells behind each measurement instead of one.\n");

    {
        // Swept round by round through the window where the ridge lives, instead of sampled at a
        // few depths. If the dominant residue *walks* by a fixed amount per round, that amount is
        // the effective rotation the composition is applying, and following it is unwinding the
        // operation as it runs. A residue that stays put instead is a fixed point of the
        // composition, which is a different and equally readable answer.
        const unsigned RESIDUES = 32u;
        const unsigned CHECKED = 14u;
        const unsigned rounds_at[CHECKED] = {12u, 13u, 14u, 15u, 16u, 17u, 18u, 19u,
                                             20u, 21u, 22u, 23u, 32u, 64u};

        // 4096 cells per residue class, so the aggregate's standard error is the per-cell one
        // divided by 64.
        const double per_cell = 0.5 / std::sqrt((double)trials);
        const double per_class = per_cell / std::sqrt(4096.0);
        const double class_null = std::sqrt(2.0 * std::log((double)RESIDUES));

        std::printf("\n  Per-cell standard error %.8f, per-class %.8f, %u cells per class.\n",
                    per_cell, per_class, 4096u);
        std::printf("  The largest of %u residues peaks near %.2f sigmas under the null.\n",
                    RESIDUES, class_null);

        std::printf("\n  %8s %16s %14s %10s %12s %8s\n", "rounds", "loudest residue", "its sigmas",
                    "null peak", "verdict", "walked");
        std::printf("  %8s %16s %14s %10s %12s %8s\n", "--------", "----------------",
                    "--------------", "----------", "------------", "--------");

        unsigned last_residue = 0u;

        for (unsigned which = 0u; which < CHECKED; which += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 20260909ull, rounds_at[which], device_matrix,
                                              KEEP_EVERYTHING);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            double folded[RESIDUES];
            double counted_in[RESIDUES];
            for (unsigned at = 0u; at < RESIDUES; at += 1u)
            {
                folded[at] = 0.0;
                counted_in[at] = 0.0;
            }

            for (unsigned in_bit = 0u; in_bit < INPUT_BITS; in_bit += 1u)
            {
                for (unsigned out_bit = 0u; out_bit < OUTPUT_BITS; out_bit += 1u)
                {
                    const size_t at = ((size_t)in_bit * OUTPUT_BITS) + out_bit;
                    const double rate = (double)matrix[at] / (double)trials;

                    // Signed, not absolute. A structure has a direction and cancels only if it is
                    // not there; taking magnitudes first would fold noise into a positive bias and
                    // manufacture a signal in every class.
                    const unsigned residue = ((in_bit % 32u) + 32u - (out_bit % 32u)) % 32u;
                    folded[residue] += (rate - 0.5);
                    counted_in[residue] += 1.0;
                }
            }

            double loudest = 0.0;
            unsigned loud_residue = 0u;
            for (unsigned at = 0u; at < RESIDUES; at += 1u)
            {
                if (counted_in[at] <= 0.0)
                {
                    continue;
                }
                const double mean = folded[at] / counted_in[at];
                const double sigmas = (mean < 0.0) ? (-mean / per_class) : (mean / per_class);
                if (sigmas > loudest)
                {
                    loudest = sigmas;
                    loud_residue = at;
                }
            }

            const char *verdict = (loudest > (class_null + 2.0)) ? "STRUCTURE" : "flat";

            // How far the ridge moved since the previous round. A constant step is the effective
            // rotation being tracked; a step of zero is a fixed point; a wandering step is the
            // residue being noise instead of a ridge, which is what the flat rounds should show.
            char walked[16];
            if ((which > 0u) && (loudest > (class_null + 2.0)))
            {
                const unsigned step = (loud_residue + 32u - last_residue) % 32u;
                std::snprintf(walked, sizeof(walked), "%+d", (step <= 16u) ? (int)step
                                                                           : ((int)step - 32));
            }
            else
            {
                std::snprintf(walked, sizeof(walked), "%s", "-");
            }
            last_residue = loud_residue;

            std::printf("  %8u %16u %14.2f %10.2f %12s %8s\n", rounds_at[which], loud_residue,
                        loudest, class_null, verdict, walked);

            // The loudest residue alone is the same error in miniature - one number from
            // thirty-two. The whole profile is printed so peaks and valleys are both visible, and
            // its discrete transform is taken so a repeating trend shows as a frequency instead of
            // having to be spotted by eye. A structure with period p appears at frequency 32/p, and
            // its harmonics appear at multiples of that.
            if (which == 2u)
            {
                std::printf("\n  Full residue profile at round %u, in sigmas\n", rounds_at[which]);
                std::printf("  ");
                for (unsigned at = 0u; at < RESIDUES; at += 1u)
                {
                    const double mean = folded[at] / counted_in[at];
                    std::printf("%+6.2f", mean / per_class);
                    if (((at + 1u) % 8u) == 0u)
                    {
                        std::printf("\n  ");
                    }
                }

                double loudest_tone = 0.0;
                unsigned loud_tone = 0u;
                std::printf("\n  Transform of that profile, magnitude by frequency\n  ");
                for (unsigned tone = 1u; tone <= (RESIDUES / 2u); tone += 1u)
                {
                    double real_part = 0.0;
                    double other_part = 0.0;
                    for (unsigned at = 0u; at < RESIDUES; at += 1u)
                    {
                        const double mean = (folded[at] / counted_in[at]) / per_class;
                        const double angle =
                            (-6.283185307179586 * (double)tone * (double)at) / (double)RESIDUES;
                        real_part += mean * std::cos(angle);
                        other_part += mean * std::sin(angle);
                    }
                    const double size =
                        std::sqrt((real_part * real_part) + (other_part * other_part)) /
                        std::sqrt((double)RESIDUES);
                    if (size > loudest_tone)
                    {
                        loudest_tone = size;
                        loud_tone = tone;
                    }
                    std::printf("f%02u %5.2f  ", tone, size);
                    if ((tone % 4u) == 0u)
                    {
                        std::printf("\n  ");
                    }
                }

                // A transform of white noise has magnitudes near one after this normalisation, and
                // the largest of sixteen peaks near sqrt(2 ln 16) = 2.35 by itself.
                const double tone_null = std::sqrt(2.0 * std::log((double)(RESIDUES / 2u)));
                std::printf("\n  loudest tone f%02u at %.2f, null peak %.2f, period %.1f residues\n",
                            loud_tone, loudest_tone, tone_null,
                            (loud_tone > 0u) ? ((double)RESIDUES / (double)loud_tone) : 0.0);
                std::printf("  %s\n", (loudest_tone > (tone_null + 2.0))
                                          ? "a repeating trend stands clear of the null"
                                          : "no repeating trend above the null");
            }
        }

        std::printf("\n  A residue standing clear of the null peak is rotational structure surviving\n");
        std::printf("  into the dependency matrix, and it would be invisible to the maximum this\n");
        std::printf("  document has been reading. A flat column says the rotations leave no trace\n");
        std::printf("  the fold can find, which is a stronger statement than the maximum could make\n");
        std::printf("  because it is made with 4096 cells behind each number instead of one.\n");
    }

    // ---------------------------------------------------------------------------------------
    // The particle transfer test.
    //
    // The fold above reports which residue is loudest, which is one number about a distribution of
    // thirty-two. Treating the profile as a mass distribution instead gives the two quantities a
    // transported particle actually has: where it is, and how wide it is.
    //
    // Residues are a circle, so the moments must be circular. The mean of a distribution over
    // (in - out) mod 32 is an angle, and the concentration R is one for a distribution sitting on a
    // single residue and zero for one spread evenly over all of them.
    //
    // The two transport regimes are distinguishable and predict different things:
    //
    //   ballistic   the center drifts at a constant rate per round and R stays high
    //   diffusive   the center stays put and R falls, the width growing as sqrt(rounds)
    //
    // Neither is assumed. The measurement says which, and a center that does not move while R
    // collapses is diffusion with no drift at all - which would mean the rotations cancel in
    // aggregate instead of transporting anything.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Particle transfer: where the mass is and how wide\n");
    std::printf("================================================================\n");
    std::printf("\n  The fold reports the loudest residue, which is one number about a distribution\n");
    std::printf("  of thirty-two. Treating the profile as a mass distribution instead gives what a\n");
    std::printf("  transported particle has: a position and a width.\n");
    std::printf("\n  Residues are a circle so the moments are circular. R is one for mass on a\n");
    std::printf("  single residue and zero for mass spread evenly over all of them.\n");
    std::printf("\n  Ballistic transport drifts at a constant rate with R holding. Diffusive\n");
    std::printf("  transport stays put with R falling. The measurement says which.\n");

    {
        const unsigned RESIDUES = 32u;
        const unsigned FIRST_SEEN = 12u;
        const unsigned LAST_SEEN = 24u;

        std::printf("\n  %8s %14s %12s %12s %14s\n", "rounds", "center", "drift", "R",
                    "mass");
        std::printf("  %8s %14s %12s %12s %14s\n", "--------", "--------------", "------------",
                    "------------", "--------------");

        double last_centre = 0.0;
        int have_last = 0;

        for (unsigned rounds = FIRST_SEEN; rounds <= LAST_SEEN; rounds += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 20260909ull, rounds, device_matrix,
                                              KEEP_EVERYTHING);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            // Magnitude instead of the signed value, because a mass distribution has no sign. The
            // signed fold is the right reading for finding a ridge and the wrong one for weighing
            // it.
            double mass[RESIDUES];
            for (unsigned at = 0u; at < RESIDUES; at += 1u)
            {
                mass[at] = 0.0;
            }
            for (unsigned in_bit = 0u; in_bit < INPUT_BITS; in_bit += 1u)
            {
                for (unsigned out_bit = 0u; out_bit < OUTPUT_BITS; out_bit += 1u)
                {
                    const size_t at = ((size_t)in_bit * OUTPUT_BITS) + out_bit;
                    const double rate = (double)matrix[at] / (double)trials;
                    const double apart = (rate < 0.5) ? (0.5 - rate) : (rate - 0.5);
                    const unsigned residue =
                        ((in_bit % 32u) + 32u - (out_bit % 32u)) % 32u;
                    mass[residue] += apart;
                }
            }

            double total = 0.0;
            double along = 0.0;
            double across = 0.0;
            for (unsigned at = 0u; at < RESIDUES; at += 1u)
            {
                const double angle = (6.283185307179586 * (double)at) / (double)RESIDUES;
                total += mass[at];
                along += mass[at] * std::cos(angle);
                across += mass[at] * std::sin(angle);
            }
            if (total <= 0.0)
            {
                continue;
            }

            const double concentration =
                std::sqrt((along * along) + (across * across)) / total;
            double center = std::atan2(across, along) * (double)RESIDUES / 6.283185307179586;
            if (center < 0.0)
            {
                center += (double)RESIDUES;
            }

            char drift[16];
            if (have_last != 0)
            {
                double moved = center - last_centre;
                while (moved > 16.0)
                {
                    moved -= 32.0;
                }
                while (moved < -16.0)
                {
                    moved += 32.0;
                }
                std::snprintf(drift, sizeof(drift), "%+.3f", moved);
            }
            else
            {
                std::snprintf(drift, sizeof(drift), "%s", "-");
            }
            last_centre = center;
            have_last = 1;

            std::printf("  %8u %14.3f %12s %12.6f %14.2f\n", rounds, center, drift, concentration,
                        total);
        }

        std::printf("\n  A drift column holding one value is ballistic transport and names the rate.\n");
        std::printf("  A drift near zero with R falling is diffusion in place, which would mean the\n");
        std::printf("  rotations cancel in aggregate instead of carrying the mass anywhere. R\n");
        std::printf("  approaching zero is the particle spread evenly over every residue, which is\n");
        std::printf("  where a difference stops being locatable at all.\n");
    }

    // ---------------------------------------------------------------------------------------
    // Is the transport circular?
    //
    // If a bit's path through the function is the same as its neighbor's, shifted by one position,
    // then the whole dependency matrix is built from one row and thirty-two rotations of it. That is
    // what rotation-equivariance means and it is where a signature would come from: one path, reused
    // at every offset.
    //
    // Directly checkable. Take row i, take row i+s, rotate the second back by s, and correlate. If
    // the transport is circular the two agree; if the constants break the symmetry they do not.
    //
    // SHA-256 has reason to fail this. Its rotations are circular but its additions carry, and a
    // carry has a direction and an end - bit thirty-one carries into nothing. So the arithmetic is
    // not rotation-equivariant even though the rotations are, and how much that shows is the
    // measurement.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Is the transport circular\n");
    std::printf("================================================================\n");
    std::printf("\n  If a bit's path is its neighbor's shifted by one, the whole matrix is one row\n");
    std::printf("  and thirty-two rotations of it. That is where a signature would come from: one\n");
    std::printf("  path reused at every offset.\n");
    std::printf("\n  SHA-256 has reason to fail this. Its rotations are circular but its additions\n");
    std::printf("  carry, and a carry has a direction and an end - bit thirty-one carries into\n");
    std::printf("  nothing. The arithmetic is not equivariant even though the rotations are.\n");

    {
        const unsigned CHECKED = 6u;
        const unsigned rounds_at[CHECKED] = {8u, 12u, 16u, 20u, 23u, 64u};

        std::printf("\n  %8s %16s %16s %12s\n", "rounds", "equivariance", "shuffled control",
                    "verdict");
        std::printf("  %8s %16s %16s %12s\n", "--------", "----------------", "----------------",
                    "------------");

        for (unsigned which = 0u; which < CHECKED; which += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 20260909ull, rounds_at[which], device_matrix,
                                              KEEP_EVERYTHING);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            // Correlation of row i against row i+s rotated back by s, over every pair of input bits
            // inside one word and every shift. Rotating within the word instead of across the
            // whole row, because a word boundary is where the circularity would stop.
            double agree_total = 0.0;
            double control_total = 0.0;
            double counted_pairs = 0.0;

            for (unsigned word_in = 0u; word_in < 4u; word_in += 1u)
            {
                for (unsigned base = 0u; base < 32u; base += 1u)
                {
                    for (unsigned shift = 1u; shift < 32u; shift += 1u)
                    {
                        const unsigned first_bit = (word_in * 32u) + base;
                        const unsigned other_bit = (word_in * 32u) + ((base + shift) % 32u);

                        double first_sum = 0.0;
                        double other_sum = 0.0;
                        double cross = 0.0;
                        double first_square = 0.0;
                        double other_square = 0.0;
                        double control_cross = 0.0;

                        for (unsigned out_word = 0u; out_word < 8u; out_word += 1u)
                        {
                            for (unsigned out_bit = 0u; out_bit < 32u; out_bit += 1u)
                            {
                                const unsigned here = (out_word * 32u) + out_bit;
                                // The partner output bit, rotated by the same shift inside its word.
                                const unsigned there =
                                    (out_word * 32u) + ((out_bit + shift) % 32u);

                                const double one =
                                    ((double)matrix[((size_t)first_bit * OUTPUT_BITS) + here] /
                                     (double)trials) - 0.5;
                                const double two =
                                    ((double)matrix[((size_t)other_bit * OUTPUT_BITS) + there] /
                                     (double)trials) - 0.5;

                                // The control pairs the same two rows without rotating the second,
                                // which is the same data with the claimed symmetry removed.
                                const double flat =
                                    ((double)matrix[((size_t)other_bit * OUTPUT_BITS) + here] /
                                     (double)trials) - 0.5;

                                first_sum += one;
                                other_sum += two;
                                cross += one * two;
                                control_cross += one * flat;
                                first_square += one * one;
                                other_square += two * two;
                            }
                        }

                        const double spread = std::sqrt(first_square * other_square);
                        if (spread <= 0.0)
                        {
                            continue;
                        }
                        agree_total += cross / spread;
                        control_total += control_cross / spread;
                        counted_pairs += 1.0;
                    }
                }
            }

            if (counted_pairs <= 0.0)
            {
                continue;
            }
            const double equivariance = agree_total / counted_pairs;
            const double control = control_total / counted_pairs;

            const char *verdict = (equivariance > (control + 0.05)) ? "CIRCULAR" : "not circular";
            std::printf("  %8u %16.6f %16.6f %12s\n", rounds_at[which], equivariance, control,
                        verdict);
        }

        std::printf("\n  The control is the same two rows paired without the rotation, which is the\n");
        std::printf("  identical data with the claimed symmetry removed. Equivariance standing above\n");
        std::printf("  it is a path reused at every offset; the two agreeing is the rotation buying\n");
        std::printf("  nothing, which is what a carry that ends at bit thirty-one would do.\n");
    }

    // ---------------------------------------------------------------------------------------
    // Buried or destroyed.
    //
    // The polynomial part of SHA-256 is absolute. Sigma0 is x^2 + x^13 + x^22 in
    // GF(2)[x]/(x^32 + 1) and that is true independently of any message, any round and any run: it
    // is a fact about the polynomial, not about this system. Its rank is thirty-two at round one and
    // at round sixty-four, and the linear variant reads 0.50000000 at both.
    //
    // So the polynomial never decays and cannot. What decays is whether a prediction built from it
    // still describes the real function, and those are different statements. This measures the
    // second one: how long the carry-free prediction stays right.
    //
    // Agreement starts at one and falls to one half, which is chance for a bit. Where it reaches
    // one half is where the polynomial description stops working - not where the polynomial stops
    // being true.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Buried or destroyed: how long the carry-free prediction holds\n");
    std::printf("================================================================\n");
    std::printf("\n  The polynomial part is absolute. Sigma0 is x^2 + x^13 + x^22 in\n");
    std::printf("  GF(2)[x]/(x^32+1) independently of any message, round or run, its rank is 32 at\n");
    std::printf("  round one and at round sixty-four, and the linear variant reads 0.50000000 at\n");
    std::printf("  both. It does not decay and cannot.\n");
    std::printf("\n  What decays is whether a prediction built from it still describes the real\n");
    std::printf("  function. Agreement of one is exact description; one half is chance.\n");

    {
        unsigned long long *device_agreed = nullptr;
        unsigned long long *device_compared = nullptr;
        unsigned long long *device_position = nullptr;
        cudaMalloc((void **)&device_agreed, sizeof(unsigned long long));
        cudaMalloc((void **)&device_compared, sizeof(unsigned long long));
        cudaMalloc((void **)&device_position, 32u * sizeof(unsigned long long));

        // The inverse is checked before anything is read from it. Every direction figure below
        // depends on decompress_to being the inverse of compress_to, and that had been asserted
        // instead of measured.
        {
            unsigned long long *device_failed = nullptr;
            cudaMalloc((void **)&device_failed, sizeof(unsigned long long));
            std::printf("\n  Round trip, both variants, before anything is read from the inverse\n");
            std::printf("\n  %8s %16s\n", "rounds", "failed");
            std::printf("  %8s %16s\n", "--------", "----------------");

            unsigned long long any_failed = 0u;
            for (unsigned rounds = 1u; rounds <= 24u; rounds += 7u)
            {
                cudaMemset(device_failed, 0, sizeof(unsigned long long));
                round_trip_check<<<256, 128>>>(4096ull, 20260909ull, rounds, device_failed);
                cudaDeviceSynchronize();
                unsigned long long failed = 0u;
                cudaMemcpy(&failed, device_failed, sizeof(failed), cudaMemcpyDeviceToHost);
                any_failed += failed;
                std::printf("  %8u %16llu\n", rounds, (unsigned long long)failed);
            }
            cudaFree(device_failed);

            if (any_failed != 0u)
            {
                std::printf("\n  [!] The inverse does not invert. Every direction figure below is\n");
                std::printf("  meaningless and the anti-correlation it reports is this defect and\n");
                std::printf("  not a property of SHA-256.\n");
            }
            else
            {
                std::printf("\n  The inverse inverts exactly, in both variants, at every depth\n");
                std::printf("  checked. What follows is measuring the function instead of the\n");
                std::printf("  instrument.\n");
            }
        }

        std::printf("\n  A walk from wholly unnatural to wholly natural. One is a polynomial\n");
        std::printf("  describing the object exactly; zero is chance, where no polynomial helps.\n");
        std::printf("  Both directions are run, because the two are known to differ in depth and in\n");
        std::printf("  shape and the question is whether they differ in describability too.\n");

        std::printf("\n  %8s %14s %12s %14s %12s %10s\n", "rounds", "forward", "step", "inverse",
                    "step", "apart");
        std::printf("  %8s %14s %12s %14s %12s %10s\n", "--------", "--------------", "------------",
                    "--------------", "------------", "----------");

        double last_seen[2] = {0.0, 0.0};
        for (unsigned rounds = 1u; rounds <= 24u; rounds += 1u)
        {
            double above[2];
            for (int backward = 0; backward < 2; backward += 1)
            {
                cudaMemset(device_agreed, 0, sizeof(unsigned long long));
                cudaMemset(device_compared, 0, sizeof(unsigned long long));
                carry_free_agreement<<<2048, 128>>>(trials, 20260909ull, rounds, device_agreed,
                                                    device_compared, backward, device_position);
                cudaDeviceSynchronize();

                unsigned long long agreed = 0u;
                unsigned long long compared = 0u;
                cudaMemcpy(&agreed, device_agreed, sizeof(agreed), cudaMemcpyDeviceToHost);
                cudaMemcpy(&compared, device_compared, sizeof(compared), cudaMemcpyDeviceToHost);
                above[backward] = (compared > 0u)
                                      ? ((((double)agreed / (double)compared) - 0.5) * 2.0)
                                      : 0.0;
            }

            char forward_step[16];
            char inverse_step[16];
            if (rounds > 1u)
            {
                std::snprintf(forward_step, sizeof(forward_step), "%+.4f",
                              above[0] - last_seen[0]);
                std::snprintf(inverse_step, sizeof(inverse_step), "%+.4f",
                              above[1] - last_seen[1]);
            }
            else
            {
                std::snprintf(forward_step, sizeof(forward_step), "%s", "-");
                std::snprintf(inverse_step, sizeof(inverse_step), "%s", "-");
            }
            last_seen[0] = above[0];
            last_seen[1] = above[1];

            std::printf("  %8u %14.8f %12s %14.8f %12s %10.4f\n", rounds, above[0], forward_step,
                        above[1], inverse_step, above[1] - above[0]);
        }

        // Is the wrap what makes the two directions differ? A carry runs upward from bit zero,
        // which has no carry-in and must be described exactly, to bit thirty-one, which carries the
        // most accumulated uncertainty and then wraps into nothing. If the wrap is responsible the
        // two directions wear different profiles across bit position; if it is not they wear the
        // same one and the asymmetry is somewhere else.
        std::printf("\n  Describability by bit position, at the round each direction is halfway\n");
        std::printf("\n  %6s %14s %14s %12s\n", "bit", "forward r11", "inverse r6", "apart");
        std::printf("  %6s %14s %14s %12s\n", "------", "--------------", "--------------",
                    "------------");

        double profile[2][32];
        const unsigned halfway[2] = {11u, 6u};
        for (int backward = 0; backward < 2; backward += 1)
        {
            cudaMemset(device_agreed, 0, sizeof(unsigned long long));
            cudaMemset(device_compared, 0, sizeof(unsigned long long));
            cudaMemset(device_position, 0, 32u * sizeof(unsigned long long));
            carry_free_agreement<<<2048, 128>>>(trials, 20260909ull, halfway[backward],
                                                device_agreed, device_compared, backward,
                                                device_position);
            cudaDeviceSynchronize();

            unsigned long long counts[32];
            unsigned long long compared = 0u;
            cudaMemcpy(counts, device_position, sizeof(counts), cudaMemcpyDeviceToHost);
            cudaMemcpy(&compared, device_compared, sizeof(compared), cudaMemcpyDeviceToHost);

            // Each position was compared once per word per trial, so the denominator is the total
            // compared bits divided by the thirty-two positions.
            const double per_position = (double)compared / 32.0;
            for (unsigned bit = 0u; bit < 32u; bit += 1u)
            {
                profile[backward][bit] =
                    (per_position > 0.0)
                        ? (((double)counts[bit] / per_position) - 0.5) * 2.0
                        : 0.0;
            }
        }

        for (unsigned bit = 0u; bit < 32u; bit += 1u)
        {
            std::printf("  %6u %14.6f %14.6f %12.6f\n", bit, profile[0][bit], profile[1][bit],
                        profile[1][bit] - profile[0][bit]);
        }

        std::printf("\n  Bit zero has no carry-in and should be described exactly in both\n");
        std::printf("  directions. A profile that climbs away from bit zero is the carry chain\n");
        std::printf("  accumulating, and the two directions differing in that climb is the wrap\n");
        std::printf("  being responsible for the asymmetry. The same climb in both is the wrap\n");
        std::printf("  being symmetric and the asymmetry living somewhere else.\n");

        cudaFree(device_agreed);
        cudaFree(device_compared);
        cudaFree(device_position);

        std::printf("\n  Agreement falling to one half is the description failing, and the round it\n");
        std::printf("  reaches it is the depth at which the polynomial stops being usable as a\n");
        std::printf("  prediction. The polynomial itself is unchanged there and is still exactly as\n");
        std::printf("  true as it was at round one, which is the difference between buried and\n");
        std::printf("  destroyed stated as a measurement instead of as a position.\n");
    }

    // ---------------------------------------------------------------------------------------
    // Stay put and use every cell.
    //
    // Every reading so far either takes a maximum, which uses one cell of 131072 and throws the
    // rest away, or folds onto residues, which sums them into thirty-two bins and can only see
    // structure that lines up with the fold. Neither uses all the evidence without extremising, and
    // that is the most sensitive thing this matrix supports.
    //
    // The sum of squared z over all cells is chi-square with 131072 degrees of freedom under the
    // null: mean 131072 and standard deviation sqrt(2 * 131072) = 512. So an excess of a few
    // hundred is detectable, which is a per-cell bias near 0.06 standard errors - against the 4.85
    // a maximum needs before it says anything. Roughly eighty times more sensitive to structure
    // spread thinly across every cell instead of concentrated in one.
    //
    // This is the test that a design punishing wide sampling would be least prepared for, and it is
    // the one instrument here that has never been run.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Every cell, without extremising\n");
    std::printf("================================================================\n");
    std::printf("\n  A maximum uses one cell of 131072 and discards the rest. A fold sums them into\n");
    std::printf("  thirty-two bins and sees only what lines up with it. The sum of squared z uses\n");
    std::printf("  all of them and extremises nothing.\n");
    std::printf("\n  Under the null it is chi-square with 131072 degrees of freedom: mean 131072,\n");
    std::printf("  standard deviation 512. That detects a per-cell bias near 0.06 standard errors,\n");
    std::printf("  where a maximum needs 4.85 in one cell before it says anything.\n");

    {
        // The control first, because a statistic this sensitive is worth nothing until the
        // instrument has read a known zero with it. Forty-two draws of a matrix that is binomial
        // by construction, through the same kernel shape, the same tally, the same denominator and
        // the same arithmetic. Whatever this reads is what the instrument adds, and the real arm's
        // number only means something after it is subtracted.
        const unsigned CONTROLS = 42u;
        const double cells_null = (double)(INPUT_BITS * OUTPUT_BITS);
        const double spread_null = std::sqrt(2.0 * cells_null);

        double control_excess = 0.0;
        double control_square = 0.0;

        for (unsigned draw = 0u; draw < CONTROLS; draw += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_null_row<<<INPUT_BITS, 256>>>(trials, 777000001ull + (draw * 2654435761ull),
                                               device_matrix, 0u);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            const double per_cell = 0.5 / std::sqrt((double)trials);
            double total = 0.0;
            for (size_t at = 0u; at < matrix.size(); at += 1u)
            {
                const double rate = (double)matrix[at] / (double)trials;
                const double score = (rate - 0.5) / per_cell;
                total += score * score;
            }
            const double excess = total - cells_null;
            control_excess += excess;
            control_square += excess * excess;
        }

        const double control_mean = control_excess / (double)CONTROLS;
        const double control_var =
            (control_square / (double)CONTROLS) - (control_mean * control_mean);
        const double control_sd = std::sqrt(control_var * (double)CONTROLS / (double)(CONTROLS - 1u));

        std::printf("\n  Control: %u draws of a matrix that is binomial by construction, through the\n",
                    CONTROLS);
        std::printf("  same kernel and the same arithmetic.\n");
        std::printf("    mean excess     %12.1f  (analytic null says 0)\n", control_mean);
        std::printf("    spread of one   %12.1f  (analytic null says %.1f)\n", control_sd,
                    spread_null);
        std::printf("    that mean is    %12.2f sigmas off zero, on the measured spread\n",
                    control_mean / (control_sd / std::sqrt((double)CONTROLS)));

        // The synthetic control says whether the arithmetic and the analytic 512 are right when the
        // cells really are independent. They are not independent in the real arm: all 131072 come
        // from one message set, so its per-draw spread is its own quantity and has to be measured
        // instead of assumed. Forty-two seeds at one fixed post-collapse depth is that
        // measurement, and it is the honest denominator for the pooled claim below.
        const unsigned SPREAD_AT = 32u;
        double real_excess = 0.0;
        double real_square = 0.0;

        for (unsigned draw = 0u; draw < CONTROLS; draw += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 313000007ull + (draw * 2654435761ull),
                                              SPREAD_AT, device_matrix, KEEP_EVERYTHING);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            const double per_cell = 0.5 / std::sqrt((double)trials);
            double total = 0.0;
            for (size_t at = 0u; at < matrix.size(); at += 1u)
            {
                const double rate = (double)matrix[at] / (double)trials;
                const double score = (rate - 0.5) / per_cell;
                total += score * score;
            }
            const double excess = total - cells_null;
            real_excess += excess;
            real_square += excess * excess;
        }

        const double real_mean = real_excess / (double)CONTROLS;
        const double real_var = (real_square / (double)CONTROLS) - (real_mean * real_mean);
        const double real_sd = std::sqrt(real_var * (double)CONTROLS / (double)(CONTROLS - 1u));

        std::printf("\n  SHA-256 at round %u, %u seeds, to measure this statistic's own spread when\n",
                    SPREAD_AT, CONTROLS);
        std::printf("  the cells share one message set as they really do.\n");
        std::printf("    mean excess     %12.1f\n", real_mean);
        std::printf("    spread of one   %12.1f  (analytic null says %.1f, ratio %.2f)\n", real_sd,
                    spread_null, real_sd / spread_null);

        // Every round from twenty-three to sixty-four instead of a handful, because the six
        // sampled first came out negative four times with a mean of -323 against a standard error
        // of 209, which is -1.55 sigmas and settles nothing. Forty-two depths put the error on the
        // mean at 79, where a real -323 would read past four sigmas and a null would not move.
        //
        // A systematically negative chi-square is less variance than random instead of more, which
        // is a stranger claim than excess would be and wants the arithmetic before the story.
        const unsigned CHECKED = 43u;
        unsigned rounds_at[CHECKED];
        for (unsigned at = 0u; at < CHECKED; at += 1u)
        {
            rounds_at[at] = 22u + at;
        }
        const double cells = (double)(INPUT_BITS * OUTPUT_BITS);
        const double null_spread = std::sqrt(2.0 * cells);

        std::printf("\n  %8s %18s %14s %12s %12s\n", "rounds", "sum of z^2", "excess",
                    "sigmas", "verdict");
        std::printf("  %8s %18s %14s %12s %12s\n", "--------", "------------------",
                    "--------------", "------------", "------------");

        double pooled_excess = 0.0;
        double pooled_count = 0.0;

        for (unsigned which = 0u; which < CHECKED; which += 1u)
        {
            cudaMemset(device_matrix, 0,
                       (size_t)INPUT_BITS * OUTPUT_BITS * sizeof(unsigned long long));
            // A different stream per depth. Sharing one seed across depths means the same messages
            // evaluated at different round counts, and those excesses are correlated - pooling them
            // and dividing by the square root of the count would inflate the significance of
            // whatever they share.
            fill_sac_row<<<INPUT_BITS, 256>>>(trials, 20260909ull + (rounds_at[which] * 1000003ull),
                                              rounds_at[which], device_matrix, KEEP_EVERYTHING);
            cudaDeviceSynchronize();
            cudaMemcpy(matrix.data(), device_matrix,
                       matrix.size() * sizeof(unsigned long long), cudaMemcpyDeviceToHost);

            const double per_cell = 0.5 / std::sqrt((double)trials);
            double total = 0.0;
            for (size_t at = 0u; at < matrix.size(); at += 1u)
            {
                const double rate = (double)matrix[at] / (double)trials;
                const double score = (rate - 0.5) / per_cell;
                total += score * score;
            }

            const double excess = total - cells;
            const double sigmas = excess / null_spread;
            const char *verdict = (sigmas > 5.0) ? "STRUCTURE" : "flat";
            std::printf("  %8u %18.1f %14.1f %12.2f %12s\n", rounds_at[which], total, excess,
                        sigmas, verdict);

            // Rounds past the collapse are pooled, because the question is whether their mean sits
            // off zero and one depth cannot answer it.
            if (rounds_at[which] >= 23u)
            {
                pooled_excess += excess;
                pooled_count += 1.0;
            }
        }

        if (pooled_count > 1.0)
        {
            const double mean_excess = pooled_excess / pooled_count;
            const double mean_error = null_spread / std::sqrt(pooled_count);

            // Against the measured spread instead of the analytic one. The analytic 512 assumes
            // the cells are independent, and they are not: all 131072 come from one set of
            // messages. The seed sweep at a fixed depth measured what the spread actually is on
            // this matrix, so it is the honest denominator.
            const double honest_error = real_sd / std::sqrt(pooled_count);
            const double against_control = mean_excess / honest_error;

            std::printf("\n  Pooled over %.0f depths past the collapse: mean excess %.1f.\n",
                        pooled_count, mean_excess);
            std::printf("    against the analytic null   %8.1f  ->  %6.2f sigmas\n", mean_error,
                        mean_excess / mean_error);
            std::printf("    against the measured null   %8.1f  ->  %6.2f sigmas\n", honest_error,
                        against_control);
            std::printf("  %s\n",
                        (std::fabs(against_control) > 3.0)
                            ? "  Off zero against its own control: the matrix is not carrying binomial variance."
                            : "  On zero against its own control: the tendency is the instrument, not SHA-256.");
        }

        std::printf("\n  An excess standing clear of the null is structure spread across every cell,\n");
        std::printf("  invisible to a maximum and to a fold alike, and it would be the first thing\n");
        std::printf("  found past round twenty-three by anything here. A sum sitting on 131072 is\n");
        std::printf("  the matrix carrying nothing at all, measured the most sensitive way this\n");
        std::printf("  data allows instead of the most convenient.\n");
    }

    cudaFree(device_matrix);

    std::printf("\n  The matrix holds %u entries, so its largest deviation peaks near %.2f sigmas\n",
                INPUT_BITS * OUTPUT_BITS, std::sqrt(2.0 * std::log(131072.0)));
    std::printf("  whatever SHA-256 does - the strictest entry of a large matrix is a maximum and\n");
    std::printf("  behaves like one. A round reading near that is flat. A dip at 54 to 57 that is\n");
    std::printf("  real would stand far above it at this sample, and one that is a fluctuation of\n");
    std::printf("  their smaller sample will not appear at all.\n");
    return 0;
}
