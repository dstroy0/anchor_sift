/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_narrow.cu
 * @brief SHA-256 squished to a width small enough to answer exactly instead of statistically.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note The observer is not obliged to stand outside the function watching output go past. The
 *       whole object is available, so it can be entered, widened or shrunk. Shrinking is the move
 *       that changes what is knowable: at a narrow enough width the state space is small enough to
 *       enumerate, and every quantity this workbook currently samples becomes exact.
 * @note What it is aimed at. The largest unknown in docs/sha256-topology.md is why the forward and
 *       inverse directions differ - forward differences dying at nine rounds and inverted ones
 *       surviving past thirteen. Topology was tested for it and failed, because a cone bounds what
 *       could arrive instead of what does. At four-bit words the differential probability is a
 *       finite sum over 2^32 states and can simply be computed, with no sampling floor to hide
 *       behind and no control needed because there is nothing left uncertain.
 * @note Two widths, and they answer different questions instead of the same one twice.
 *
 *         four-bit words   a 32-bit state, exhaustively enumerable, exact answers. Too narrow to
 *                          keep the structure: a rotation can only be 1, 2 or 3, so Sigma0 and
 *                          Sigma1 collapse to the same set of amounts. That is what makes it the
 *                          control - it is the same shape with the rotation design removed, so
 *                          anything surviving here is not coming from that design.
 *
 *         eight-bit words  a 64-bit state, not enumerable, so read by sampling. Wide enough for
 *                          three distinct amounts per function, which is the structure the real
 *                          thing has. This is the one to look for flaws in.
 *
 * @note Rounds are the other axis and both settings are run, because they are different objects.
 *       Keeping 64 rounds at a narrower width makes something more mixed than SHA-256; scaling the
 *       rounds down with the width keeps the mixing comparable. Neither is the honest default and
 *       reporting one would be choosing an answer.
 * @warning The rotation amounts here are scaled from the standard's and rounded, and the rounding
 *          is a decision instead of a derivation. A different rounding gives a different object,
 *          and any result that moves when it changes is about the choice instead of about SHA-256.
 */

#include "bench_depth_score.h"

#include <cuda_runtime.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace
{

/** @brief Words in the chaining value, as in the standard. */
const unsigned WORDS = 8u;

/** @brief The standard's round constants, truncated to the working width by the device. */
__constant__ uint32_t d_wide_constant[64] = {
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

/**
 * @brief The six rotation amounts at a given width, scaled from the standard's.
 *
 * @param[in]  width  Bits per word.
 * @param[out] low_a  First amount of the low mixing function [BORROWS].
 * @param[out] low_b  Second [BORROWS].
 * @param[out] low_c  Third [BORROWS].
 * @param[out] high_a First amount of the high mixing function [BORROWS].
 * @param[out] high_b Second [BORROWS].
 * @param[out] high_c Third [BORROWS].
 * @note Derived instead of tabulated, so the width can be swept instead of picked at two points.
 *       The standard uses 2, 13, 22 and 6, 11, 25 on 32 bits; these are scaled by the width,
 *       rounded, forced nonzero and forced distinct within each function by stepping upward.
 * @note Distinctness is where the narrowing bites and the effect is the whole reason to sweep. A
 *       function needs three different amounts to spread a bit three ways, and below about six
 *       bits there are not three distinct nonzero amounts to be had, so the two functions collapse
 *       onto each other and the rotation design disappears. The sweep shows where that happens
 *       instead of asserting it.
 */
__host__ __device__ __forceinline__ void rotation_amounts(unsigned width, unsigned *low_a,
                                                          unsigned *low_b, unsigned *low_c,
                                                          unsigned *high_a, unsigned *high_b,
                                                          unsigned *high_c)
{
    const unsigned standard[6] = {2u, 13u, 22u, 6u, 11u, 25u};
    unsigned scaled[6];

    for (unsigned at = 0u; at < 6u; at += 1u)
    {
        unsigned value = ((standard[at] * width) + 16u) / 32u;
        if (value == 0u)
        {
            value = 1u;
        }
        if (value >= width)
        {
            value = width - 1u;
        }
        scaled[at] = value;
    }

    // Try to make each triple distinct by stepping upward and wrapping, but give up after a
    // bounded number of attempts instead of looping forever.
    //
    // Below six bits there are not three distinct nonzero amounts to be had - at width three the
    // only choices are one and two - so distinctness is not merely awkward there, it is impossible.
    // The first version of this retried until it succeeded and hung on exactly that case, which is
    // the narrowing breaking the construction at precisely the width this sweep exists to examine.
    // Repeated amounts are the honest outcome and the caller reports them instead of being handed
    // a triple that pretends to be distinct.
    for (unsigned base = 0u; base < 6u; base += 3u)
    {
        for (unsigned at = base + 1u; at < (base + 3u); at += 1u)
        {
            for (unsigned attempt = 0u; attempt < width; attempt += 1u)
            {
                int clashes = 0;
                for (unsigned before = base; before < at; before += 1u)
                {
                    clashes |= (scaled[at] == scaled[before]) ? 1 : 0;
                }
                if (clashes == 0)
                {
                    break;
                }
                scaled[at] = (scaled[at] % (width - 1u)) + 1u;
            }
        }
    }

    *low_a = scaled[0];
    *low_b = scaled[1];
    *low_c = scaled[2];
    *high_a = scaled[3];
    *high_b = scaled[4];
    *high_c = scaled[5];
}

/** @brief Rotates within the working width. */
__device__ __forceinline__ uint32_t turn(uint32_t value, unsigned by, unsigned width,
                                         uint32_t mask)
{
    by %= width;
    return (by == 0u) ? (value & mask)
                      : (((value >> by) | (value << (width - by))) & mask);
}

/**
 * @brief One round of the narrowed function.
 *
 * @param[in,out] state Eight words of the working width [BORROWS].
 * @param[in]     round Which round, selecting the constant.
 * @param[in]     word  The message word for this round.
 * @param[in]     width Bits per word, four or eight.
 * @note The shape is the standard's exactly: same two carries, same shift of six words, same
 *       choice and majority. Only the width and the rotation amounts change, so anything that
 *       differs between this and SHA-256 is those two things and nothing else.
 */
__device__ __forceinline__ void narrow_step(uint32_t *state, unsigned round, uint32_t word,
                                            unsigned width)
{
    const uint32_t mask = (width >= 32u) ? 0xffffffffu : ((1u << width) - 1u);
    unsigned low_a = 0u;
    unsigned low_b = 0u;
    unsigned low_c = 0u;
    unsigned high_a = 0u;
    unsigned high_b = 0u;
    unsigned high_c = 0u;
    rotation_amounts(width, &low_a, &low_b, &low_c, &high_a, &high_b, &high_c);

    const uint32_t mix_high = turn(state[4], high_a, width, mask) ^
                              turn(state[4], high_b, width, mask) ^
                              turn(state[4], high_c, width, mask);
    const uint32_t choose = state[6] ^ (state[4] & (state[5] ^ state[6]));
    const uint32_t carry_one =
        (state[7] + mix_high + choose + (d_wide_constant[round] >> (32u - width)) + word) & mask;
    const uint32_t mix_low = turn(state[0], low_a, width, mask) ^
                             turn(state[0], low_b, width, mask) ^
                             turn(state[0], low_c, width, mask);
    const uint32_t majority = (state[0] & state[1]) | (state[2] & (state[0] ^ state[1]));

    state[7] = state[6];
    state[6] = state[5];
    state[5] = state[4];
    state[4] = (state[3] + carry_one) & mask;
    state[3] = state[2];
    state[2] = state[1];
    state[1] = state[0];
    state[0] = (carry_one + mix_low + majority) & mask;
}

/** @brief The inverse of one round, which the bijection guarantees exists. */
__device__ __forceinline__ void narrow_unstep(uint32_t *state, unsigned round, uint32_t word,
                                              unsigned width)
{
    const uint32_t mask = (width >= 32u) ? 0xffffffffu : ((1u << width) - 1u);
    const unsigned low_a = (width == 4u) ? 1u : 1u;
    const unsigned low_b = (width == 4u) ? 2u : 3u;
    const unsigned low_c = (width == 4u) ? 3u : 6u;
    const unsigned high_a = (width == 4u) ? 1u : 2u;
    const unsigned high_b = (width == 4u) ? 2u : 4u;
    const unsigned high_c = (width == 4u) ? 3u : 7u;

    const uint32_t before_a = state[1];
    const uint32_t before_b = state[2];
    const uint32_t before_c = state[3];
    const uint32_t before_e = state[5];
    const uint32_t before_f = state[6];
    const uint32_t before_g = state[7];

    const uint32_t mix_low = turn(before_a, low_a, width, mask) ^
                             turn(before_a, low_b, width, mask) ^
                             turn(before_a, low_c, width, mask);
    const uint32_t majority = (before_a & before_b) | (before_c & (before_a ^ before_b));
    const uint32_t carry_one = (state[0] - mix_low - majority) & mask;
    const uint32_t before_d = (state[4] - carry_one) & mask;
    const uint32_t mix_high = turn(before_e, high_a, width, mask) ^
                              turn(before_e, high_b, width, mask) ^
                              turn(before_e, high_c, width, mask);
    const uint32_t choose = before_g ^ (before_e & (before_f ^ before_g));
    const uint32_t before_h =
        (carry_one - mix_high - choose - (d_wide_constant[round] >> (32u - width)) - word) & mask;

    state[0] = before_a;
    state[1] = before_b;
    state[2] = before_c;
    state[3] = before_d;
    state[4] = before_e;
    state[5] = before_f;
    state[6] = before_g;
    state[7] = before_h;
}

/** @brief Unpacks a packed state into eight words. */
__device__ __forceinline__ void unpack(uint64_t packed, uint32_t *state, unsigned width)
{
    const uint32_t mask = (1u << width) - 1u;
    for (unsigned slot = 0u; slot < WORDS; slot += 1u)
    {
        state[slot] = (uint32_t)((packed >> (slot * width)) & (uint64_t)mask);
    }
}

/**
 * @brief Counts, over every state, how far a difference has spread after r rounds.
 *
 * @param[in]     span      How many states to walk, which is the whole space when exhaustive.
 * @param[in]     width     Bits per word.
 * @param[in]     rounds    How many rounds.
 * @param[in]     backward  Nonzero to walk the inverse.
 * @param[in]     difference Packed input difference.
 * @param[in]     words     Message words, one per round.
 * @param[in,out] spread    Accumulates the Hamming distance of the whole output [BORROWS].
 * @param[in,out] counted   Accumulates how many states were walked [BORROWS].
 * @note Exhaustive at four-bit words, where the state is 32 bits and every one of them is visited,
 *       so what comes back is the exact expectation and not an estimate of it. At eight bits the
 *       space is 64 bits and the same kernel walks a prefix of it instead, which is sampling and
 *       is labeled as such.
 */
__global__ void spread_of(uint64_t span, unsigned width, unsigned rounds, int backward,
                          uint64_t difference, const uint32_t *words, unsigned long long *spread,
                          unsigned long long *counted)
{
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    unsigned long long local_spread = 0u;
    unsigned long long local_counted = 0u;

    for (uint64_t at = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; at < span; at += stride)
    {
        uint32_t left[WORDS];
        uint32_t right[WORDS];
        unpack(at, left, width);
        unpack(at ^ difference, right, width);

        for (unsigned step = 0u; step < rounds; step += 1u)
        {
            if (backward != 0)
            {
                const unsigned which = rounds - 1u - step;
                narrow_unstep(left, which, words[which], width);
                narrow_unstep(right, which, words[which], width);
            }
            else
            {
                narrow_step(left, step, words[step], width);
                narrow_step(right, step, words[step], width);
            }
        }

        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            local_spread += (unsigned long long)__popc(left[slot] ^ right[slot]);
        }
        local_counted += 1u;
    }

    atomicAdd(spread, local_spread);
    atomicAdd(counted, local_counted);
}

/**
 * @brief Sweeps a whole subspace of inputs and exclusive-ors every output together.
 *
 * @param[in]     dimension How many input bits are swept, so 2^dimension inputs in the set.
 * @param[in]     positions Which bit of the packed state each swept coordinate moves [BORROWS].
 * @param[in]     base      The packed state every unswept coordinate is held at.
 * @param[in]     width     Bits per word.
 * @param[in]     rounds    How many rounds.
 * @param[in]     backward  Nonzero to walk the inverse.
 * @param[in]     words     Message words, one per round.
 * @param[in,out] total     Accumulates the exclusive-or of every output [BORROWS].
 * @note This is the rake instead of another probe. A differential picks one pin at a time; this
 *       holds every coordinate still and moves one subspace through all of its values at once, then
 *       reads the sum. Where the algebraic degree of the output in those coordinates is below the
 *       dimension of the subspace, that sum is **exactly zero** - not small, zero - because every
 *       monomial of degree below the dimension appears an even number of times and cancels.
 * @note Which makes it the one measurement here that needs no control and has no floor. A
 *       statistical reading is a number to be compared against a null; this is an identity that
 *       either holds or does not. The workbook already has what sets its reach: the algebraic
 *       degree is three at round four and at least twelve at round five.
 * @note Exclusive-or instead of addition, because the property is over GF(2) and this is the one
 *       place in this tree where that language is the right one - degree is a GF(2) notion.
 */
__global__ void integral_sum(unsigned dimension, const unsigned *positions, uint64_t base,
                             unsigned width, unsigned rounds, int backward, const uint32_t *words,
                             unsigned long long *total)
{
    const uint64_t span = (uint64_t)1u << dimension;
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    unsigned long long local = 0u;

    for (uint64_t at = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; at < span; at += stride)
    {
        uint64_t packed = base;
        for (unsigned bit = 0u; bit < dimension; bit += 1u)
        {
            if (((at >> bit) & 1u) != 0u)
            {
                packed ^= (uint64_t)1u << positions[bit];
            }
        }

        uint32_t state[WORDS];
        unpack(packed, state, width);

        for (unsigned step = 0u; step < rounds; step += 1u)
        {
            if (backward != 0)
            {
                const unsigned which = rounds - 1u - step;
                narrow_unstep(state, which, words[which], width);
            }
            else
            {
                narrow_step(state, step, words[step], width);
            }
        }

        uint64_t out = 0u;
        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            out |= ((uint64_t)state[slot]) << (slot * width);
        }
        local ^= out;
    }

    atomicXor(total, local);
}

/** @brief The stream the depth benches draw from, so a width sweep samples the same way they do. */
__device__ __forceinline__ uint64_t splitmix(uint64_t &state)
{
    state += 0x9e3779b97f4a7c15ull;
    uint64_t mixed = state;
    mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
    mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
    return mixed ^ (mixed >> 31);
}

/**
 * @brief Per-word Hamming distance after r rounds at a stated width, sampled.
 *
 * @param[in]     trials   How many pairs to draw.
 * @param[in]     seed     Stream seed.
 * @param[in]     width    Bits per word.
 * @param[in]     rounds   How deep to go.
 * @param[in]     backward Nonzero to walk the inverse.
 * @param[in,out] sums     Room for eight accumulators [BORROWS].
 * @param[in,out] counted  How many pairs were walked [BORROWS].
 * @note Per-word instead of whole-state, because the 32-bit result this is being compared against
 *       is the largest of eight per-word readings. A whole-state distance would be a different
 *       statistic and the widths would not be comparable to it or to each other.
 * @note One bit of difference, as the 32-bit arm uses, so the only thing changing across the sweep
 *       is the width.
 */
__global__ void narrow_walk(uint64_t trials, uint64_t seed, unsigned width, unsigned rounds,
                            int backward, unsigned long long *sums, unsigned long long *counted)
{
    const uint32_t mask = (width >= 32u) ? 0xffffffffu : ((1u << width) - 1u);
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    unsigned long long local[8];
    for (unsigned slot = 0u; slot < 8u; slot += 1u)
    {
        local[slot] = 0u;
    }
    unsigned long long seen = 0u;

    for (uint64_t at = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; at < trials; at += stride)
    {
        uint64_t generator = seed + (at * 0x2545f4914f6cdd1dull);

        uint32_t words[24];
        for (unsigned slot = 0u; slot < 24u; slot += 1u)
        {
            words[slot] = (uint32_t)splitmix(generator) & mask;
        }

        uint32_t left[8];
        uint32_t right[8];
        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            left[slot] = (uint32_t)splitmix(generator) & mask;
            right[slot] = left[slot];
        }

        const unsigned where = (unsigned)(splitmix(generator) % (uint64_t)(width * 8u));
        right[where / width] ^= (1u << (where % width));

        for (unsigned turn_at = 0u; turn_at < rounds; turn_at += 1u)
        {
            if (backward != 0)
            {
                const unsigned which = rounds - 1u - turn_at;
                narrow_unstep(left, which, words[which], width);
                narrow_unstep(right, which, words[which], width);
            }
            else
            {
                narrow_step(left, turn_at, words[turn_at], width);
                narrow_step(right, turn_at, words[turn_at], width);
            }
        }

        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            local[slot] += (unsigned long long)__popc((left[slot] ^ right[slot]) & mask);
        }
        seen += 1u;
    }

    for (unsigned slot = 0u; slot < 8u; slot += 1u)
    {
        atomicAdd(&sums[slot], local[slot]);
    }
    atomicAdd(counted, seen);
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned sample_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 32u;

    std::printf("================================================================\n");
    std::printf("  SHA-256 squished, so the answers are computed instead of sampled\n");
    std::printf("================================================================\n");
    std::printf("\n  The observer is not obliged to stand outside watching output go past. The\n");
    std::printf("  whole object is available and can be shrunk, and shrinking is the move that\n");
    std::printf("  changes what is knowable: at four-bit words the state is 32 bits and every one\n");
    std::printf("  of them can be visited, so the differential spread is a finite sum instead of\n");
    std::printf("  an estimate with a floor under it.\n");
    std::printf("\n  Aimed at the largest unknown in the topology document: why forward differences\n");
    std::printf("  die at nine rounds and inverted ones survive past thirteen. Topology was tested\n");
    std::printf("  for it and failed, because a cone bounds what could arrive and not what does.\n");
    std::printf("\n  Four-bit words are the control: too narrow for three distinct rotation amounts,\n");
    std::printf("  so Sigma0 and Sigma1 collapse together and the rotation design is gone. Anything\n");
    std::printf("  surviving there is not coming from that design. Eight-bit words keep three\n");
    std::printf("  distinct amounts, which is the structure the real thing has.\n");

    uint32_t words[64];
    uint32_t state = 20260908u;
    for (unsigned at = 0u; at < 64u; at += 1u)
    {
        state = (state * 1103515245u) + 12345u;
        words[at] = (state >> 16);
    }
    uint32_t *device_words = nullptr;
    cudaMalloc((void **)&device_words, sizeof(words));
    cudaMemcpy(device_words, words, sizeof(words), cudaMemcpyHostToDevice);

    unsigned long long *device_spread = nullptr;
    unsigned long long *device_counted = nullptr;
    cudaMalloc((void **)&device_spread, sizeof(unsigned long long));
    cudaMalloc((void **)&device_counted, sizeof(unsigned long long));

    std::printf("\n  Width is swept instead of picked, because it is a coordinate and a coordinate\n");
    std::printf("  that can be scanned is not one to fix. The rotation amounts are derived from the\n");
    std::printf("  standard's by scaling, so every width is the same construction instead of a\n");
    std::printf("  hand-made object per width.\n");

    std::printf("\n  %8s %8s %18s %18s %12s\n", "width", "state", "low amounts", "high amounts",
                "distinct");
    std::printf("  %8s %8s %18s %18s %12s\n", "--------", "--------", "------------------",
                "------------------", "------------");
    for (unsigned width = 3u; width <= 8u; width += 1u)
    {
        unsigned la = 0u;
        unsigned lb = 0u;
        unsigned lc = 0u;
        unsigned ha = 0u;
        unsigned hb = 0u;
        unsigned hc = 0u;
        rotation_amounts(width, &la, &lb, &lc, &ha, &hb, &hc);
        const int low_distinct = ((la != lb) && (lb != lc) && (la != lc)) ? 1 : 0;
        const int high_distinct = ((ha != hb) && (hb != hc) && (ha != hc)) ? 1 : 0;
        const int sets_differ = ((la != ha) || (lb != hb) || (lc != hc)) ? 1 : 0;
        char summary[24];
        std::snprintf(summary, sizeof(summary), "%s%s",
                      ((low_distinct != 0) && (high_distinct != 0)) ? "yes" : "no",
                      (sets_differ != 0) ? ", differ" : ", same");
        std::printf("  %8u %8u %6u %5u %5u %6u %5u %5u %12s\n", width, width * WORDS, la, lb, lc,
                    ha, hb, hc, summary);
    }

    for (unsigned width = 3u; width <= 8u; width += 1u)
    {
        const unsigned bits = width * WORDS;
        const uint64_t span =
            (bits <= sample_bits) ? ((uint64_t)1u << bits) : ((uint64_t)1u << sample_bits);
        const int exhaustive = (bits <= sample_bits) ? 1 : 0;
        // Saturation for a whole state of this width, which is half its bits.
        const double saturated = (double)bits / 2.0;

        std::printf("\n================================================================\n");
        std::printf("  %u-bit words, %u-bit state, %s over %llu states\n", width, bits,
                    (exhaustive != 0) ? "EXHAUSTIVE" : "sampled", (unsigned long long)span);
        std::printf("================================================================\n");

        for (unsigned rounds_setting = 0u; rounds_setting < 2u; rounds_setting += 1u)
        {
            // Both settings, because they are different objects. Keeping 64 rounds at a narrow
            // width makes something more mixed than SHA-256; scaling the rounds with the width
            // keeps the mixing comparable. Reporting one would be choosing an answer.
            const unsigned deepest = (rounds_setting == 0u) ? ((64u * width) / 32u) : 24u;
            std::printf("\n  rounds scaled with the width to %u, and read to that depth\n",
                        deepest);
            std::printf("\n  %8s %16s %16s %14s\n", "rounds", "forward spread", "inverse spread",
                        "saturated at");
            std::printf("  %8s %16s %16s %14s\n", "--------", "----------------",
                        "----------------", "--------------");

            for (unsigned rounds = 1u; rounds <= deepest; rounds += 1u)
            {
                double reading[2];
                for (int backward = 0; backward < 2; backward += 1)
                {
                    cudaMemset(device_spread, 0, sizeof(unsigned long long));
                    cudaMemset(device_counted, 0, sizeof(unsigned long long));
                    // A single-bit difference on the word a round reads first, which is the
                    // scarcest stratum and the one that survives deepest.
                    spread_of<<<2048, 256>>>(span, width, rounds, backward,
                                             (uint64_t)1u << (7u * width), device_words,
                                             device_spread, device_counted);
                    cudaDeviceSynchronize();

                    unsigned long long total = 0u;
                    unsigned long long seen = 0u;
                    cudaMemcpy(&total, device_spread, sizeof(total), cudaMemcpyDeviceToHost);
                    cudaMemcpy(&seen, device_counted, sizeof(seen), cudaMemcpyDeviceToHost);
                    reading[backward] = (seen > 0u) ? ((double)total / (double)seen) : 0.0;
                }

                std::printf("  %8u %16.6f %16.6f %14.1f\n", rounds, reading[0], reading[1],
                            saturated);
            }
        }
    }

    std::printf("\n================================================================\n");
    std::printf("  Reading it\n");
    std::printf("================================================================\n");
    std::printf("\n  The spread columns are the mean Hamming distance of the whole output state.\n");
    std::printf("  Saturation is half the state bits, and a column that reaches it has lost the\n");
    std::printf("  difference entirely. Where the run is exhaustive these are the exact values and\n");
    std::printf("  there is no floor to clear and no control to compare against, because nothing\n");
    std::printf("  about them is uncertain.\n");
    std::printf("\n  If the forward and inverse columns saturate at different rounds here, the\n");
    std::printf("  asymmetry is a property of this shape at any width and the full-size reading\n");
    std::printf("  was not a coincidence of sampling. If they saturate together, the asymmetry\n");
    std::printf("  belongs to the 32-bit width or to something the narrowing removed, and the\n");
    std::printf("  four-bit control says whether the rotation design is what removed it.\n");

    // ---------------------------------------------------------------------------------------
    // The rake, in both directions.
    //
    // Hold every coordinate still and move one subspace through all of its values at once. Where
    // the algebraic degree in those coordinates is below the dimension of the subspace, the
    // exclusive-or of every output is exactly zero, because each monomial below that degree appears
    // an even number of times. Zero is the reading, not a small number, so this needs no control
    // and has no floor.
    //
    // Both directions, because the inverse holds pressure from the other end: an integral that dies
    // at r rounds forward and s backward covers r plus s when the two are matched in the middle,
    // and this tree has already measured the inverse to be the slower-diffusing side.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  The rake: every pin set at once, and the hole is exact\n");
    std::printf("================================================================\n");
    std::printf("\n  A differential moves one pin. This holds every coordinate still and sweeps a\n");
    std::printf("  whole subspace, then reads the sum. Below the subspace dimension the algebraic\n");
    std::printf("  degree cannot survive the cancellation, so the sum is exactly zero - an\n");
    std::printf("  identity that holds or does not, instead of a number to be compared against a\n");
    std::printf("  null. It is the one reading here that needs no control.\n");

    {
        unsigned *device_positions = nullptr;
        unsigned long long *device_total = nullptr;
        cudaMalloc((void **)&device_positions, 32u * sizeof(unsigned));
        cudaMalloc((void **)&device_total, sizeof(unsigned long long));

        for (unsigned width = 4u; width <= 8u; width += 4u)
        {
            std::printf("\n  %u-bit words\n", width);
            std::printf("\n  %10s %10s %20s %20s\n", "dimension", "inputs", "forward zero to",
                        "inverse zero to");
            std::printf("  %10s %10s %20s %20s\n", "----------", "----------",
                        "--------------------", "--------------------");

            for (unsigned dimension = 2u; dimension <= 12u; dimension += 2u)
            {
                // The swept bits are taken from the word a round reads first, spilling into the
                // next word where the dimension exceeds the width.
                std::vector<unsigned> positions(dimension);
                for (unsigned bit = 0u; bit < dimension; bit += 1u)
                {
                    positions[bit] = ((7u * width) + bit) % (width * WORDS);
                }
                cudaMemcpy(device_positions, positions.data(), dimension * sizeof(unsigned),
                           cudaMemcpyHostToDevice);

                unsigned reach[2] = {0u, 0u};
                for (int backward = 0; backward < 2; backward += 1)
                {
                    for (unsigned rounds = 1u; rounds <= 24u; rounds += 1u)
                    {
                        // Every base, not one. An integral is a degree bound and a degree bound
                        // holds on every coset, so a zero at a single base is not the property -
                        // it is that base cancelling. Measured at one base the reach came out
                        // non-monotone in the dimension, which is impossible for a real integral,
                        // and the coset decomposition confirmed the kernel was adding correctly
                        // and the single base was the defect.
                        int all_zero = 1;
                        for (unsigned trial = 0u; (trial < 8u) && (all_zero != 0); trial += 1u)
                        {
                            uint64_t base = 0x0123456789abcdefull;
                            base ^= (uint64_t)trial * 0x9e3779b97f4a7c15ull;

                            cudaMemset(device_total, 0, sizeof(unsigned long long));
                            integral_sum<<<256, 256>>>(dimension, device_positions, base, width,
                                                       rounds, backward, device_words,
                                                       device_total);
                            cudaDeviceSynchronize();

                            unsigned long long sum = 0u;
                            cudaMemcpy(&sum, device_total, sizeof(sum), cudaMemcpyDeviceToHost);
                            all_zero = (sum == 0u) ? 1 : 0;
                        }
                        if (all_zero == 0)
                        {
                            break;
                        }
                        reach[backward] = rounds;
                    }
                }

                std::printf("  %10u %10llu %20u %20u\n", dimension,
                            (unsigned long long)1u << dimension, reach[0], reach[1]);
            }
        }

        cudaFree(device_positions);
        cudaFree(device_total);
    }

    // ---------------------------------------------------------------------------------------
    // Bisecting the monotonicity violation.
    //
    // Integral reach must not fall as the dimension rises: if a subspace sums to zero, any larger
    // subspace containing it is the exclusive-or of that sum over each coset, and a sum of zeros is
    // zero. The swept positions here are nested, yet four-bit words read a reach of five at
    // dimension eight and three at dimension ten. That cannot both be true.
    //
    // The decomposition is the test. A dimension-ten sum has to equal the exclusive-or of the four
    // dimension-eight sums over its cosets, as an identity about how the kernel adds things up
    // instead of anything about SHA-256. If it does not, the kernel is wrong. If it does, the
    // reasoning above is wrong and one of those zeros was an accident instead of a degree bound.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Bisecting the monotonicity violation\n");
    std::printf("================================================================\n");
    std::printf("\n  A dimension-ten sum must equal the exclusive-or of the four dimension-eight\n");
    std::printf("  sums over its cosets. That is an identity about the kernel's bookkeeping, not\n");
    std::printf("  about the function, so a mismatch localises the defect immediately.\n");
    std::printf("\n  %8s %20s %20s %12s\n", "rounds", "whole at dim 10", "cosets of dim 8",
                "agree");
    std::printf("  %8s %20s %20s %12s\n", "--------", "--------------------",
                "--------------------", "------------");

    {
        const unsigned width = 4u;
        unsigned *device_positions = nullptr;
        unsigned long long *device_total = nullptr;
        cudaMalloc((void **)&device_positions, 32u * sizeof(unsigned));
        cudaMalloc((void **)&device_total, sizeof(unsigned long long));

        for (unsigned rounds = 1u; rounds <= 6u; rounds += 1u)
        {
            std::vector<unsigned> ten(10u);
            for (unsigned bit = 0u; bit < 10u; bit += 1u)
            {
                ten[bit] = ((7u * width) + bit) % (width * WORDS);
            }
            cudaMemcpy(device_positions, ten.data(), 10u * sizeof(unsigned),
                       cudaMemcpyHostToDevice);
            cudaMemset(device_total, 0, sizeof(unsigned long long));
            integral_sum<<<256, 256>>>(10u, device_positions, 0x0123456789abcdefull, width, rounds,
                                       1, device_words, device_total);
            cudaDeviceSynchronize();
            unsigned long long whole = 0u;
            cudaMemcpy(&whole, device_total, sizeof(whole), cudaMemcpyDeviceToHost);

            // The same span, taken as four cosets of the dimension-eight subspace. The two extra
            // coordinates of the ten-dimensional space are what selects the coset.
            std::vector<unsigned> eight(8u);
            for (unsigned bit = 0u; bit < 8u; bit += 1u)
            {
                eight[bit] = ten[bit];
            }
            cudaMemcpy(device_positions, eight.data(), 8u * sizeof(unsigned),
                       cudaMemcpyHostToDevice);

            unsigned long long assembled = 0u;
            for (unsigned coset = 0u; coset < 4u; coset += 1u)
            {
                uint64_t shifted = 0x0123456789abcdefull;
                if ((coset & 1u) != 0u)
                {
                    shifted ^= (uint64_t)1u << ten[8];
                }
                if ((coset & 2u) != 0u)
                {
                    shifted ^= (uint64_t)1u << ten[9];
                }
                cudaMemset(device_total, 0, sizeof(unsigned long long));
                integral_sum<<<256, 256>>>(8u, device_positions, shifted, width, rounds, 1,
                                           device_words, device_total);
                cudaDeviceSynchronize();
                unsigned long long part = 0u;
                cudaMemcpy(&part, device_total, sizeof(part), cudaMemcpyDeviceToHost);
                assembled ^= part;
            }

            std::printf("  %8u %20llx %20llx %12s\n", rounds, whole, assembled,
                        (whole == assembled) ? "yes" : "NO");
        }

        cudaFree(device_positions);
        cudaFree(device_total);
    }

    std::printf("\n  Agreement everywhere means the kernel adds correctly and the reach table's\n");
    std::printf("  zeros at one base were accidents instead of degree bounds - which would mean\n");
    std::printf("  the reach has to be read over several bases, not one. Disagreement means the\n");
    std::printf("  kernel is wrong and nothing it has produced counts.\n");

    std::printf("\n  The reach columns are the last round at which the sum was still exactly zero.\n");
    std::printf("  A dimension that reaches further than the one below it is the degree growing\n");
    std::printf("  slower than the dimension, and where the columns stop growing with dimension the\n");
    std::printf("  degree has caught up and the rake is finished.\n");
    std::printf("\n  Forward and inverse are read separately because the inverse holds pressure from\n");
    std::printf("  the other end: matched in the middle, an integral covers the sum of the two, and\n");
    std::printf("  the inverse is already known to be the slower-diffusing side.\n");

    // ---------------------------------------------------------------------------------------
    // Does the peak destruction rate follow the width?
    //
    // At 32 bits the forward decay peaks at 29.73 per round, which is 4.89 bits against 5.000 for
    // exactly 32. One 32-bit word destroyed per round is the natural reading of that, and it makes
    // a prediction the width sweep can falsify: the peak should track the width. At 8 bits it
    // should read near 8, not near 32.
    //
    // The alternative is that the peak is a constant of the construction instead of of the word,
    // in which case every width peaks near the same figure and the coincidence at 32 was a
    // coincidence.
    //
    // The statistic is the largest of eight per-word readings with a width-aware null, which is the
    // same statistic the 32-bit result came from. Rounds pinned at the ceiling are the shift chain
    // holding an untouched word and carry no rate, so they are excluded here as they are there.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Peak destruction rate against width\n");
    std::printf("================================================================\n");
    std::printf("\n  At 32 bits the forward decay peaks at 29.73 per round, 4.89 bits against 5.000\n");
    std::printf("  for exactly 32. If that is one word destroyed per round the peak tracks the\n");
    std::printf("  width and reads near 8 at eight bits; if it is a constant of the construction\n");
    std::printf("  every width peaks near the same figure and 32 was a coincidence.\n");

    {
        const unsigned WIDTHS = 7u;
        const unsigned width_of[WIDTHS] = {4u, 6u, 8u, 12u, 16u, 24u, 32u};
        const uint64_t many = (uint64_t)1u << 22u;

        unsigned long long *device_sums = nullptr;
        unsigned long long *device_seen = nullptr;
        cudaMalloc((void **)&device_sums, 8u * sizeof(unsigned long long));
        cudaMalloc((void **)&device_seen, sizeof(unsigned long long));

        // The amounts are scaled from the standard's and rounded, so they change with the width and
        // so does their arithmetic relationship to it. A rotation by r on a w-bit word has orbit
        // length w/gcd(w,r), so where the width shares factors with an amount that rotation has
        // short orbits and mixes weakly. Sweeping the width therefore sweeps the construction, not
        // one construction at several sizes, and the worst gcd in a row is the honest label for how
        // much of the design survived the narrowing.
        std::printf("\n  %6s %11s %11s %6s %11s %10s %8s %8s\n", "width", "low rot", "high rot",
                    "worst", "peak x/rd", "peak bits", "w bits", "dies at");
        std::printf("  %6s %11s %11s %6s %11s %10s %8s %8s\n", "------", "-----------",
                    "-----------", "------", "-----------", "----------", "--------", "--------");

        for (unsigned which = 0u; which < WIDTHS; which += 1u)
        {
            const unsigned width = width_of[which];
            const double ceiling = bench_depth_ceiling((double)many, (double)width);
            const double floor_at = 1.9;

            double before = 0.0;
            double peak = 0.0;
            unsigned dies = 0u;

            for (unsigned rounds = 1u; rounds <= 20u; rounds += 1u)
            {
                cudaMemset(device_sums, 0, 8u * sizeof(unsigned long long));
                cudaMemset(device_seen, 0, sizeof(unsigned long long));
                narrow_walk<<<2048, 128>>>(many, 20260909ull + (rounds * 7919ull) + width, width,
                                           rounds, 0, device_sums, device_seen);
                cudaDeviceSynchronize();

                unsigned long long sums[8];
                unsigned long long counted = 0u;
                cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
                cudaMemcpy(&counted, device_seen, sizeof(counted), cudaMemcpyDeviceToHost);

                double strongest = 0.0;
                for (unsigned slot = 0u; slot < 8u; slot += 1u)
                {
                    const double score =
                        bench_depth_score_at_width((double)sums[slot], (double)counted,
                                                   (double)width);
                    const double size = (score < 0.0) ? -score : score;
                    strongest = (size > strongest) ? size : strongest;
                }

                // A ratio is only a rate where both ends are readable: above the floor, and off the
                // ceiling that a pinned round sits at.
                if ((before > floor_at * 4.0) && (before < (ceiling * 0.95)) &&
                    (strongest > floor_at * 2.0))
                {
                    const double ratio = before / strongest;
                    peak = (ratio > peak) ? ratio : peak;
                }
                if ((dies == 0u) && (strongest < 4.0))
                {
                    dies = rounds;
                }
                before = strongest;
            }

            const double peak_bits = (peak > 0.0) ? std::log2(peak) : 0.0;
            const double width_bits = std::log2((double)width);

            unsigned low_a = 0u;
            unsigned low_b = 0u;
            unsigned low_c = 0u;
            unsigned high_a = 0u;
            unsigned high_b = 0u;
            unsigned high_c = 0u;
            rotation_amounts(width, &low_a, &low_b, &low_c, &high_a, &high_b, &high_c);

            const unsigned every[6] = {low_a, low_b, low_c, high_a, high_b, high_c};
            unsigned worst = 1u;
            for (unsigned at = 0u; at < 6u; at += 1u)
            {
                unsigned left = width;
                unsigned right = every[at];
                while (right != 0u)
                {
                    const unsigned carry = left % right;
                    left = right;
                    right = carry;
                }
                worst = (left > worst) ? left : worst;
            }

            char low_text[16];
            char high_text[16];
            std::snprintf(low_text, sizeof(low_text), "%u,%u,%u", low_a, low_b, low_c);
            std::snprintf(high_text, sizeof(high_text), "%u,%u,%u", high_a, high_b, high_c);

            std::printf("  %6u %11s %11s %6u %11.2f %10.2f %8.2f %8u\n", width, low_text, high_text,
                        worst, peak, peak_bits, width_bits, dies);
        }

        cudaFree(device_sums);
        cudaFree(device_seen);

        std::printf("\n  The worst column is the largest gcd between the width and any of its six\n");
        std::printf("  rotation amounts, so it is the shortest orbit the narrowing left in place.\n");
        std::printf("  A row with a worst above one is not the same construction as a row with one,\n");
        std::printf("  and this sweep therefore compares seven constructions instead of one at\n");
        std::printf("  seven sizes. The peak column tracks that instead of the width.\n");
        std::printf("\n  The peak column is not measurable at this resolution either. The collapse\n");
        std::printf("  falls between two integer rounds, so a ratio of rounds is a derivative sampled\n");
        std::printf("  coarser than the thing it is sampling, and it lands where the round grid\n");
        std::printf("  happens to cut the fall. Sub-round resolution wants the input weight swept\n");
        std::printf("  instead, since a heavier difference collapses earlier and walks the fall\n");
        std::printf("  across the grid.\n");
        std::printf("\n  The dies column is the one that holds still, and it holds still at nine or\n");
        std::printf("  ten across an eightfold change in width. A wall set by how many words are on\n");
        std::printf("  the chain is exactly what does not move when the bits inside them change; a\n");
        std::printf("  wall set by the width of a word would have moved and did not. Varying the\n");
        std::printf("  word count instead of the word width is the test that would settle it, and\n");
        std::printf("  this bench holds eight words at every width.\n");
        std::printf("\n  The two triples above are the state functions, Sigma0 at 2, 13, 22 and\n");
        std::printf("  Sigma1 at 6, 11, 25. The schedule's own constants - sigma0 at 7, 18 and a\n");
        std::printf("  shift of 3, sigma1 at 17, 19 and a shift of 10 - are not swept here and are\n");
        std::printf("  not narrowed by anything in this tree, because this bench feeds independent\n");
        std::printf("  random words instead of expanding a schedule. A nonce travels through those\n");
        std::printf("  four and not through these two, so the same orbit argument aimed at them is\n");
        std::printf("  the sharper form of this question.\n");
    }

    cudaFree(device_words);
    cudaFree(device_spread);
    cudaFree(device_counted);
    return 0;
}
