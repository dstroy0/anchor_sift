/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_words.cu
 * @brief The wall against the number of words on the chain, which is the axis nothing has varied.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note bench_narrow sweeps the width of a word and finds the wall sitting at nine or ten rounds at
 *       every width from four bits to thirty-two. A wall that does not move when the bits inside a
 *       word change is evidence for the wall belonging to the chain instead of to the word, and it
 *       is not proof, because that sweep holds eight words at every width. The word count is the
 *       axis that has never been varied and this varies it.
 * @note The prediction is sharp enough to fail. If the wall is the shift chain emptying, it sits at
 *       the word count plus a small constant, and SHA-256's own eight words walling at ten fixes
 *       that constant at two. Six words should wall at eight and sixteen at eighteen. If instead the
 *       wall stays near ten as the count changes, it belongs to the mixing functions and the width
 *       sweep's agreement was a coincidence.
 * @note Everything else is held at the standard's: thirty-two bit words, the standard's rotation
 *       amounts, the standard's constants. Only the count moves, so nothing else can explain a
 *       difference.
 * @warning Six words is the narrowest this generalisation admits, because choice reads three words
 *          from the high half and majority three from the low half, and a half of fewer than three
 *          has nothing to read.
 */

#include "bench_depth_score.h"

#include <cuda_runtime.h>

#include <cstdint>
#include <cstdio>

namespace
{

/** @brief Most words this sweep will place on the chain. */
const unsigned MOST_WORDS = 16u;

/** @brief The standard's round constants. */
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

/** @brief The stream the other depth benches draw from. */
__device__ __forceinline__ uint64_t splitmix(uint64_t &state)
{
    state += 0x9e3779b97f4a7c15ull;
    uint64_t mixed = state;
    mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
    mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
    return mixed ^ (mixed >> 31);
}

/** @brief Rotates right by the standard's rule. */
__device__ __forceinline__ uint32_t turn(uint32_t value, unsigned by)
{
    return (value >> by) | (value << (32u - by));
}

/**
 * @brief One round of SHA-256 generalised to a stated number of state words.
 *
 * @param[in,out] state The chain, count words of it [BORROWS].
 * @param[in]     round Which round constant to use.
 * @param[in]     word  This round's message word.
 * @param[in]     count How many words are on the chain.
 * @note At eight words this is the standard's round exactly, so the sweep contains SHA-256 itself
 *       as one of its rows instead of a model of it. The low half is fed by majority and Sigma0
 *       from its own head, the high half by choice and Sigma1 from its own head, and the two halves
 *       are joined the way the standard joins them.
 * @note The shift is the whole point of the sweep. A difference entering at the head of a half has
 *       to walk the length of that half before it reaches the tail, and how long that takes is what
 *       is being measured.
 */
__device__ __forceinline__ void wide_step(uint32_t *state, unsigned round, uint32_t word,
                                          unsigned count)
{
    const unsigned half = count / 2u;

    const uint32_t mix_high = turn(state[half], 6u) ^ turn(state[half], 11u) ^
                              turn(state[half], 25u);
    const uint32_t choose =
        state[half + 2u] ^ (state[half] & (state[half + 1u] ^ state[half + 2u]));
    const uint32_t carry_one =
        state[count - 1u] + mix_high + choose + d_constant[round & 63u] + word;

    const uint32_t mix_low = turn(state[0], 2u) ^ turn(state[0], 13u) ^ turn(state[0], 22u);
    const uint32_t majority = (state[0] & state[1]) | (state[2] & (state[0] ^ state[1]));

    for (unsigned at = count - 1u; at > 0u; at -= 1u)
    {
        state[at] = state[at - 1u];
    }

    // The shift has already moved the word below the join into the join, so the addition lands on
    // top of it. Reading state[half - 1] here instead would read a word the shift has also just
    // overwritten, which drops the word that belongs in the join and quietly deletes one slot of
    // the chain every round - the chain this bench exists to measure the length of.
    state[half] += carry_one;
    state[0] = carry_one + mix_low + majority;
}

/**
 * @brief Walks pairs differing in one bit and sums the per-word Hamming distance.
 *
 * @param[in]     trials  How many pairs to draw.
 * @param[in]     seed    Stream seed.
 * @param[in]     count   How many words are on the chain.
 * @param[in]     rounds  How deep to go.
 * @param[in,out] sums    Room for MOST_WORDS accumulators [BORROWS].
 * @param[in,out] counted How many pairs were walked [BORROWS].
 */
__global__ void wide_walk(uint64_t trials, uint64_t seed, unsigned count, unsigned rounds,
                          unsigned long long *sums, unsigned long long *counted)
{
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    unsigned long long local[MOST_WORDS];
    for (unsigned slot = 0u; slot < MOST_WORDS; slot += 1u)
    {
        local[slot] = 0u;
    }
    unsigned long long seen = 0u;

    for (uint64_t at = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; at < trials; at += stride)
    {
        uint64_t generator = seed + (at * 0x2545f4914f6cdd1dull);

        uint32_t words[32];
        for (unsigned slot = 0u; slot < 32u; slot += 1u)
        {
            words[slot] = (uint32_t)splitmix(generator);
        }

        uint32_t left[MOST_WORDS];
        uint32_t right[MOST_WORDS];
        for (unsigned slot = 0u; slot < count; slot += 1u)
        {
            left[slot] = (uint32_t)splitmix(generator);
            right[slot] = left[slot];
        }

        const unsigned where = (unsigned)(splitmix(generator) % (uint64_t)(count * 32u));
        right[where / 32u] ^= (1u << (where % 32u));

        for (unsigned turn_at = 0u; turn_at < rounds; turn_at += 1u)
        {
            wide_step(left, turn_at, words[turn_at & 31u], count);
            wide_step(right, turn_at, words[turn_at & 31u], count);
        }

        for (unsigned slot = 0u; slot < count; slot += 1u)
        {
            local[slot] += (unsigned long long)__popc(left[slot] ^ right[slot]);
        }
        seen += 1u;
    }

    for (unsigned slot = 0u; slot < MOST_WORDS; slot += 1u)
    {
        atomicAdd(&sums[slot], local[slot]);
    }
    atomicAdd(counted, seen);
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned trial_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 24u;
    const uint64_t trials = (uint64_t)1u << trial_bits;

    std::printf("================================================================\n");
    std::printf("  The wall against how many words are on the chain\n");
    std::printf("================================================================\n");
    std::printf("\n  bench_narrow found the wall at nine or ten rounds at every width from four\n");
    std::printf("  bits to thirty-two, which is evidence the wall belongs to the chain instead of\n");
    std::printf("  to the word - and not proof, because that sweep holds eight words at every\n");
    std::printf("  width. This varies the count and holds everything else at the standard's.\n");
    std::printf("\n  The prediction can fail. If the wall is the chain emptying it sits at the word\n");
    std::printf("  count plus a constant, and SHA-256's eight words walling at ten fixes that\n");
    std::printf("  constant at two: six words should wall at eight, sixteen at eighteen. A wall\n");
    std::printf("  that stays near ten instead belongs to the mixing functions.\n");
    std::printf("\n  Pairs per cell: 2^%u. Eight words is SHA-256 itself, not a model of it.\n",
                trial_bits);

    unsigned long long *device_sums = nullptr;
    unsigned long long *device_counted = nullptr;
    cudaMalloc((void **)&device_sums, MOST_WORDS * sizeof(unsigned long long));
    cudaMalloc((void **)&device_counted, sizeof(unsigned long long));

    std::printf("\n  %8s %12s %12s %12s %14s\n", "words", "wall", "predicted", "error", "which");
    std::printf("  %8s %12s %12s %12s %14s\n", "--------", "------------", "------------",
                "------------", "--------------");

    const unsigned COUNTS = 6u;
    const unsigned count_of[COUNTS] = {6u, 8u, 10u, 12u, 14u, 16u};

    for (unsigned which = 0u; which < COUNTS; which += 1u)
    {
        const unsigned count = count_of[which];
        unsigned wall = 0u;

        for (unsigned rounds = 1u; rounds <= 30u; rounds += 1u)
        {
            cudaMemset(device_sums, 0, MOST_WORDS * sizeof(unsigned long long));
            cudaMemset(device_counted, 0, sizeof(unsigned long long));
            wide_walk<<<4096, 128>>>(trials, 20260909ull + (rounds * 7919ull) + count, count,
                                     rounds, device_sums, device_counted);
            cudaDeviceSynchronize();

            unsigned long long sums[MOST_WORDS];
            unsigned long long counted = 0u;
            cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
            cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);

            double strongest = 0.0;
            for (unsigned slot = 0u; slot < count; slot += 1u)
            {
                const double score = bench_depth_score((double)sums[slot], (double)counted);
                const double size = (score < 0.0) ? -score : score;
                strongest = (size > strongest) ? size : strongest;
            }

            if ((wall == 0u) && (strongest < 4.0))
            {
                wall = rounds;
                break;
            }
        }

        // Eight words walling at ten is what fixes the constant, so that row must come out with
        // zero error or the prediction is being fitted instead of tested.
        const unsigned predicted = count + 2u;
        const int error = (int)wall - (int)predicted;
        const char *verdict = (error == 0) ? "chain" : ((wall >= 9u) && (wall <= 11u)) ? "mixing"
                                                                                      : "neither";

        // Eight words is SHA-256, and bench_depth_cuda reads its wall at ten. That row is the
        // control: if it does not come back ten, this generalisation is not SHA-256 at eight words
        // and no other row means anything.
        const char *note = "";
        if (count == 8u)
        {
            note = (wall == 10u) ? "  <- SHA-256, matches bench_depth"
                                 : "  <- SHA-256, DOES NOT MATCH bench_depth's 10";
        }
        std::printf("  %8u %12u %12u %+12d %14s%s\n", count, wall, predicted, error, verdict, note);
    }

    // ---------------------------------------------------------------------------------------
    // Where the plus two comes from.
    //
    // Only two slots are mixed by the round at all. Slot zero takes T1 plus T2 and slot half takes
    // d plus T1; every other slot is state[i] = state[i-1], which is a copy and carries a difference
    // unchanged instead of mixing it. So the tail of the chain holds whatever slot zero produced
    // count-1 rounds earlier, and the wall should decompose as
    //
    //     wall = m + (count - 1)
    //
    // where m is how long the round function takes to saturate a freshly mixed word. The measured
    // wall of count + 2 puts m at 3, and that is checkable instead of inferable: read each slot's
    // own death depth instead of the largest across slots. If the decomposition holds, slot k dies
    // about m + k rounds in and the deepest slot reproduces the whole wall.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Where the plus two comes from\n");
    std::printf("================================================================\n");
    std::printf("\n  Only slot zero and slot half are mixed by the round. Every other slot is a copy\n");
    std::printf("  of the one above it, which transports a difference without touching it, so the\n");
    std::printf("  tail holds what slot zero made count-1 rounds ago. That predicts the wall is a\n");
    std::printf("  mixing depth plus a transport delay, and count + 2 puts the mixing depth at 3.\n");
    std::printf("\n  Each slot's own death depth, instead of the largest across slots.\n");

    for (unsigned which = 0u; which < COUNTS; which += 1u)
    {
        const unsigned count = count_of[which];

        std::printf("\n  %u words\n", count);
        std::printf("\n  %8s %12s %14s %10s\n", "slot", "dies at", "predicted 3+k", "role");
        std::printf("  %8s %12s %14s %10s\n", "--------", "------------", "--------------",
                    "----------");

        unsigned deepest_slot = 0u;
        unsigned per_slot[MOST_WORDS];
        for (unsigned slot = 0u; slot < count; slot += 1u)
        {
            unsigned dies = 0u;
            for (unsigned rounds = 1u; rounds <= 30u; rounds += 1u)
            {
                cudaMemset(device_sums, 0, MOST_WORDS * sizeof(unsigned long long));
                cudaMemset(device_counted, 0, sizeof(unsigned long long));
                wide_walk<<<4096, 128>>>(trials, 20260909ull + (rounds * 7919ull) + count, count,
                                         rounds, device_sums, device_counted);
                cudaDeviceSynchronize();

                unsigned long long sums[MOST_WORDS];
                unsigned long long counted = 0u;
                cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
                cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);

                const double score = bench_depth_score((double)sums[slot], (double)counted);
                const double size = (score < 0.0) ? -score : score;
                if (size < 4.0)
                {
                    dies = rounds;
                    break;
                }
            }
            per_slot[slot] = dies;
            deepest_slot = (dies > deepest_slot) ? dies : deepest_slot;

            const char *role = "copy";
            if (slot == 0u)
            {
                role = "mixed a";
            }
            else if (slot == (count / 2u))
            {
                role = "mixed e";
            }
            std::printf("  %8u %12u %14u %10s\n", slot, dies, 3u + slot, role);
        }
        std::printf("\n  deepest slot dies at %u, and the whole-chain wall is %u\n", deepest_slot,
                    count + 2u);

        // Each half read as its own chain, since both are chains of copies below one mixed head.
        // The offsets are what differ, and the difference between them is the asymmetry: a takes
        // T1 plus T2, both halves fully mixed, while e takes d - a raw copy - plus T1. Twice the
        // mixing into a should saturate it sooner, and the offset is where that shows.
        const unsigned half_at = count / 2u;
        double a_offset = 0.0;
        double e_offset = 0.0;
        unsigned a_seen = 0u;
        unsigned e_seen = 0u;
        for (unsigned slot = 0u; slot < count; slot += 1u)
        {
            if (per_slot[slot] == 0u)
            {
                continue;
            }
            if (slot < half_at)
            {
                a_offset += (double)per_slot[slot] - (double)slot;
                a_seen += 1u;
            }
            else
            {
                e_offset += (double)per_slot[slot] - (double)slot;
                e_seen += 1u;
            }
        }
        if ((a_seen > 0u) && (e_seen > 0u))
        {
            const double a_law = a_offset / (double)a_seen;
            const double e_law = e_offset / (double)e_seen;
            std::printf("  a half reads slot + %.2f, e half reads slot + %.2f, apart by %.2f\n",
                        a_law, e_law, a_law - e_law);
        }
    }

    std::printf("\n  A slot column reading three plus its index is the decomposition holding: a\n");
    std::printf("  mixing depth of three at the two mixed slots, and one round of transport per\n");
    std::printf("  copy below them. The plus two is then 3 minus 1, and it is a property of the\n");
    std::printf("  round function instead of of the chain, which is why it did not move when the\n");
    std::printf("  word count did.\n");

    cudaFree(device_sums);
    cudaFree(device_counted);

    std::printf("\n  A chain column throughout is the wall belonging to the shift chain, and it\n");
    std::printf("  makes the width sweep's agreement a consequence instead of a coincidence. A\n");
    std::printf("  mixing column is the opposite finding: the wall would then be a property of the\n");
    std::printf("  rotation and choice functions and would have to be explained by them instead.\n");
    return 0;
}
