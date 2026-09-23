/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_depth_cuda.cu
 * @brief The depth sweep on the device, deep enough to find where the inverse direction dies.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note bench_depth measured the forward direction dying at nine rounds and the inverse still
 *       reading 51.8 standard errors at twelve. It stopped at twelve for want of samples, so every
 *       envelope figure quoting the inverse is a lower bound instead of a measurement. This exists
 *       to end that.
 * @note Only counting moves to the device. The scoring is bench_depth_score.h, included by both
 *       arms, because a sum of Hamming distances turned into standard errors is four lines of
 *       arithmetic and four lines is exactly the size of thing that gets written twice and then
 *       disagrees. Failure mode fifteen has already put two wrong numbers in this tree's tables.
 * @note Every word is read instead of one. Choosing a readout in advance has driven a result three
 *       times here, and in this bench specifically the choice was inverted: the surviving word is
 *       the least overwritten end of the shift chain, not the most mixed, so both earlier tables
 *       understated both directions.
 * @note The round trip is checked on the device before anything is measured with it. An inverse
 *       that is not the inverse would make every number below meaningless, and it costs one kernel
 *       to rule out.
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

/** @brief Words in a chaining value. */
const unsigned WORDS = 8u;

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

__device__ __forceinline__ uint32_t turn(uint32_t value, uint32_t by)
{
    return __funnelshift_r(value, value, by);
}

__device__ __forceinline__ uint32_t mix_high(uint32_t value)
{
    return turn(value, 6u) ^ turn(value, 11u) ^ turn(value, 25u);
}

__device__ __forceinline__ uint32_t mix_low(uint32_t value)
{
    return turn(value, 2u) ^ turn(value, 13u) ^ turn(value, 22u);
}

/** @brief One round forward. */
__device__ __forceinline__ void step(uint32_t *state, unsigned round, uint32_t word)
{
    const uint32_t choose = state[6] ^ (state[4] & (state[5] ^ state[6]));
    const uint32_t carry_one =
        state[7] + mix_high(state[4]) + choose + d_constant[round] + word;
    const uint32_t majority = (state[0] & state[1]) | (state[2] & (state[0] ^ state[1]));
    const uint32_t carry_two = mix_low(state[0]) + majority;

    state[7] = state[6];
    state[6] = state[5];
    state[5] = state[4];
    state[4] = state[3] + carry_one;
    state[3] = state[2];
    state[2] = state[1];
    state[1] = state[0];
    state[0] = carry_one + carry_two;
}

/** @brief One round backward, which the bijection guarantees exists. */
__device__ __forceinline__ void unstep(uint32_t *state, unsigned round, uint32_t word)
{
    const uint32_t before_a = state[1];
    const uint32_t before_b = state[2];
    const uint32_t before_c = state[3];
    const uint32_t before_e = state[5];
    const uint32_t before_f = state[6];
    const uint32_t before_g = state[7];

    const uint32_t majority =
        (before_a & before_b) | (before_c & (before_a ^ before_b));
    const uint32_t carry_two = mix_low(before_a) + majority;
    const uint32_t carry_one = state[0] - carry_two;
    const uint32_t before_d = state[4] - carry_one;
    const uint32_t choose = before_g ^ (before_e & (before_f ^ before_g));
    const uint32_t before_h =
        carry_one - mix_high(before_e) - choose - d_constant[round] - word;

    state[0] = before_a;
    state[1] = before_b;
    state[2] = before_c;
    state[3] = before_d;
    state[4] = before_e;
    state[5] = before_f;
    state[6] = before_g;
    state[7] = before_h;
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
 * @brief Checks that the inverse returns what the forward step produced.
 *
 * @param[in]     trials How many random states to try.
 * @param[in]     seed   Where the generator starts.
 * @param[in,out] wrong  Counts the states that did not return [BORROWS].
 * @note Run before anything is measured. An inverse that is not the inverse makes every reading
 *       below it meaningless and it costs one kernel to rule out.
 */
__global__ void round_trip(uint64_t trials, uint64_t seed, unsigned long long *wrong)
{
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    for (uint64_t at = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; at < trials; at += stride)
    {
        uint64_t generator = seed + at;
        uint32_t state[WORDS];
        uint32_t kept[WORDS];
        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            state[slot] = (uint32_t)splitmix(generator);
            kept[slot] = state[slot];
        }
        const uint32_t word = (uint32_t)splitmix(generator);
        const unsigned round = (unsigned)(splitmix(generator) % 64u);

        step(state, round, word);
        unstep(state, round, word);

        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            if (state[slot] != kept[slot])
            {
                atomicAdd(wrong, 1ull);
                break;
            }
        }
    }
}

/**
 * @brief Runs pairs at a given weight and depth, accumulating Hamming distance per word.
 *
 * @param[in]     trials      How many pairs.
 * @param[in]     seed        Where the generator starts.
 * @param[in]     weight_low  Fewest bits to differ.
 * @param[in]     weight_high Most bits to differ.
 * @param[in]     rounds      How many rounds.
 * @param[in]     backward    Nonzero to walk the inverse.
 * @param[in,out] sums        Eight accumulators, one per state word [BORROWS].
 * @param[in,out] counted     How many pairs were actually used [BORROWS].
 * @note The flipped positions are distinct. Drawing them independently lets two land on the same
 *       bit and cancel, so a request for sixteen delivers fourteen and the pair lands in a stratum
 *       it does not belong to, which mislabels every row of a table stratified by weight.
 */
__global__ void walk(uint64_t trials, uint64_t seed, unsigned weight_low, unsigned weight_high,
                     unsigned rounds, int backward, unsigned long long *sums,
                     unsigned long long *counted)
{
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    unsigned long long local[WORDS];
    for (unsigned slot = 0u; slot < WORDS; slot += 1u)
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
            words[slot] = (uint32_t)splitmix(generator);
        }

        uint32_t left[WORDS];
        uint32_t right[WORDS];
        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            left[slot] = (uint32_t)splitmix(generator);
            right[slot] = left[slot];
        }

        const unsigned span = weight_high - weight_low + 1u;
        const unsigned flips = weight_low + (unsigned)(splitmix(generator) % span);
        unsigned chosen[32];
        unsigned placed = 0u;
        while (placed < flips)
        {
            const unsigned where = (unsigned)(splitmix(generator) % 256u);
            int already = 0;
            for (unsigned seen_at = 0u; seen_at < placed; seen_at += 1u)
            {
                already |= (chosen[seen_at] == where) ? 1 : 0;
            }
            if (already == 0)
            {
                chosen[placed] = where;
                placed += 1u;
            }
        }
        for (unsigned bit = 0u; bit < flips; bit += 1u)
        {
            right[chosen[bit] / 32u] ^= (1u << (chosen[bit] % 32u));
        }

        for (unsigned turn_at = 0u; turn_at < rounds; turn_at += 1u)
        {
            if (backward != 0)
            {
                const unsigned which = rounds - 1u - turn_at;
                unstep(left, which, words[which]);
                unstep(right, which, words[which]);
            }
            else
            {
                step(left, turn_at, words[turn_at]);
                step(right, turn_at, words[turn_at]);
            }
        }

        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            local[slot] += (unsigned long long)__popc(left[slot] ^ right[slot]);
        }
        seen += 1u;
    }

    for (unsigned slot = 0u; slot < WORDS; slot += 1u)
    {
        atomicAdd(&sums[slot], local[slot]);
    }
    atomicAdd(counted, seen);
}

/**
 * @brief The same walk, read one bit position at a time instead of one word at a time.
 *
 * @param[in]     trials      How many pairs to draw.
 * @param[in]     seed        Stream seed.
 * @param[in]     weight_low  Fewest bits to flip.
 * @param[in]     weight_high Most bits to flip.
 * @param[in]     rounds      How deep to go.
 * @param[in]     backward    Nonzero to run the inverse.
 * @param[in,out] differed    Room for 256 counters, one per bit position [BORROWS].
 * @param[in,out] counted     How many pairs were actually used [BORROWS].
 * @note A word's mean Hamming distance is the sum of thirty-two bit rates, so two positions leaning
 *       opposite ways cancel in the word reading and survive here. This is the same experiment with
 *       the summation removed, which is the only difference that matters.
 * @note Shared counters and one global atomic per position at the end. Two hundred and fifty-six
 *       global atomics per pair would cost more than the SHA-256 rounds being measured.
 */
__global__ void walk_bits(uint64_t trials, uint64_t seed, unsigned weight_low,
                          unsigned weight_high, unsigned rounds, int backward,
                          unsigned long long *differed, unsigned long long *counted)
{
    __shared__ unsigned long long tally[256];
    for (unsigned at = threadIdx.x; at < 256u; at += blockDim.x)
    {
        tally[at] = 0u;
    }
    __syncthreads();

    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    unsigned long long seen = 0u;

    for (uint64_t at = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; at < trials; at += stride)
    {
        uint64_t generator = seed + (at * 0x2545f4914f6cdd1dull);

        uint32_t words[24];
        for (unsigned slot = 0u; slot < 24u; slot += 1u)
        {
            words[slot] = (uint32_t)splitmix(generator);
        }

        uint32_t left[WORDS];
        uint32_t right[WORDS];
        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            left[slot] = (uint32_t)splitmix(generator);
            right[slot] = left[slot];
        }

        const unsigned span = weight_high - weight_low + 1u;
        const unsigned flips = weight_low + (unsigned)(splitmix(generator) % span);
        unsigned chosen[32];
        unsigned placed = 0u;
        while (placed < flips)
        {
            const unsigned where = (unsigned)(splitmix(generator) % 256u);
            int already = 0;
            for (unsigned seen_at = 0u; seen_at < placed; seen_at += 1u)
            {
                already |= (chosen[seen_at] == where) ? 1 : 0;
            }
            if (already == 0)
            {
                chosen[placed] = where;
                placed += 1u;
            }
        }
        for (unsigned bit = 0u; bit < flips; bit += 1u)
        {
            right[chosen[bit] / 32u] ^= (1u << (chosen[bit] % 32u));
        }

        for (unsigned turn_at = 0u; turn_at < rounds; turn_at += 1u)
        {
            if (backward != 0)
            {
                const unsigned which = rounds - 1u - turn_at;
                unstep(left, which, words[which]);
                unstep(right, which, words[which]);
            }
            else
            {
                step(left, turn_at, words[turn_at]);
                step(right, turn_at, words[turn_at]);
            }
        }

        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            uint32_t apart = left[slot] ^ right[slot];
            while (apart != 0u)
            {
                const unsigned bit = (unsigned)__ffs((int)apart) - 1u;
                atomicAdd(&tally[(slot * 32u) + bit], 1ull);
                apart &= apart - 1u;
            }
        }
        seen += 1u;
    }
    __syncthreads();

    for (unsigned at = threadIdx.x; at < 256u; at += blockDim.x)
    {
        atomicAdd(&differed[at], tally[at]);
    }

    // Every thread carries its own count, exactly as the word kernel does. Adding this from one
    // thread of the block would divide the denominator by the block size and inflate every score
    // by eleven.
    atomicAdd(counted, seen);
}

/**
 * @brief The standard's message schedule, expanded from sixteen words to sixty-four.
 *
 * @param[in,out] schedule Sixty-four words, the first sixteen already filled [BORROWS].
 * @note Every arm above fed twenty-four independent uniform words, which is a different function
 *       from SHA-256 in the one way that matters here: the same word goes to both members of a pair
 *       and therefore cancels out of the additive difference exactly. That makes the schedule
 *       contribute nothing, and what those arms measured was state diffusion alone.
 * @note A difference placed in the message does not cancel, because expansion carries it into every
 *       later word. That is the difference a miner actually varies.
 */
__host__ __device__ __forceinline__ void expand(uint32_t *schedule)
{
    for (unsigned at = 16u; at < 64u; at += 1u)
    {
        const uint32_t behind_fifteen = schedule[at - 15u];
        const uint32_t behind_two = schedule[at - 2u];
        const uint32_t low = ((behind_fifteen >> 7) | (behind_fifteen << 25)) ^
                             ((behind_fifteen >> 18) | (behind_fifteen << 14)) ^
                             (behind_fifteen >> 3);
        const uint32_t high = ((behind_two >> 17) | (behind_two << 15)) ^
                              ((behind_two >> 19) | (behind_two << 13)) ^ (behind_two >> 10);
        schedule[at] = schedule[at - 16u] + low + schedule[at - 7u] + high;
    }
}

/**
 * @brief The forward walk with the difference in the message instead of in the state.
 *
 * @param[in]     trials   How many pairs to draw.
 * @param[in]     seed     Stream seed.
 * @param[in]     rounds   How deep to go.
 * @param[in]     where    Which bit of the nonce word to flip, 0 to 31.
 * @param[in,out] sums     Room for WORDS accumulators [BORROWS].
 * @param[in,out] counted  How many pairs were actually used [BORROWS].
 * @note Both members start from an identical chaining state and an identical message except for one
 *       bit of word three, which is where a Bitcoin header's nonce sits. The schedule is the
 *       standard's, so that one bit expands instead of eliding.
 */
__global__ void walk_nonce(uint64_t trials, uint64_t seed, unsigned rounds, unsigned where,
                           unsigned long long *sums, unsigned long long *counted)
{
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;
    unsigned long long local[WORDS];
    for (unsigned slot = 0u; slot < WORDS; slot += 1u)
    {
        local[slot] = 0u;
    }
    unsigned long long seen = 0u;

    for (uint64_t at = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; at < trials; at += stride)
    {
        uint64_t generator = seed + (at * 0x2545f4914f6cdd1dull);

        uint32_t left_schedule[64];
        uint32_t right_schedule[64];
        for (unsigned slot = 0u; slot < 16u; slot += 1u)
        {
            left_schedule[slot] = (uint32_t)splitmix(generator);
            right_schedule[slot] = left_schedule[slot];
        }

        // Word three is the nonce in a Bitcoin header's second block. One bit of it, expanded by
        // the standard's schedule, is the whole difference.
        right_schedule[3] ^= (1u << where);
        expand(left_schedule);
        expand(right_schedule);

        uint32_t left[WORDS];
        uint32_t right[WORDS];
        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            left[slot] = (uint32_t)splitmix(generator);
            right[slot] = left[slot];
        }

        for (unsigned turn_at = 0u; turn_at < rounds; turn_at += 1u)
        {
            step(left, turn_at, left_schedule[turn_at]);
            step(right, turn_at, right_schedule[turn_at]);
        }

        for (unsigned slot = 0u; slot < WORDS; slot += 1u)
        {
            local[slot] += (unsigned long long)__popc(left[slot] ^ right[slot]);
        }
        seen += 1u;
    }

    for (unsigned slot = 0u; slot < WORDS; slot += 1u)
    {
        atomicAdd(&sums[slot], local[slot]);
    }
    atomicAdd(counted, seen);
}

/** @brief A straight line fitted to log2 of a decay, and the window it was fitted over. */
struct Decay
{
    double per_round;   ///< Slope in bits per round. Negative, because a decay falls.
    double at_zero;     ///< Where the line sits at round zero, in bits.
    unsigned first;     ///< First round in the fit window.
    unsigned last;      ///< Last round in the fit window.
    unsigned used;      ///< How many rounds were fitted.
};

/**
 * @brief Fits a straight line to the logarithm of a decay over the rounds that are clearly signal.
 *
 * @param[in] readings One reading per round, indexed by round [BORROWS].
 * @param[in] deepest  Highest round present in the array.
 * @param[in] floor    The noise floor, measured instead of assumed.
 * @return             The fitted line and the window used.
 * @note The window is every contiguous round whose reading stands at least a hundredfold above the
 *       floor, starting from the shallowest such round. That threshold is what makes the fit a
 *       statement about the decay instead of about the floor: a reading near the floor is mostly
 *       noise and would drag the slope toward zero.
 * @note The fit is on log2, so a geometric decay is a straight line and the slope is the factor per
 *       round. Fitting the readings themselves would weight the deep rounds at nothing.
 */
Decay fit_decay(const double *readings, unsigned deepest, double floor_at, double ceiling)
{
    Decay out = {0.0, 0.0, 0u, 0u, 0u};
    const double wanted = floor_at * 100.0;
    const double pinned = ceiling * 0.95;

    // Rounds where no difference has reached the least-diffused word all read the ceiling and read
    // it identically, so they describe the chain length instead of any decay. Fitting through them
    // drags the slope toward zero, which is exactly how this fit first reported 1.469 per round for
    // a decay whose own ratios reach 30.
    unsigned first = 0u;
    while ((first <= deepest) && ((readings[first] < wanted) || (readings[first] >= pinned)))
    {
        first += 1u;
    }
    unsigned last = first;
    while (((last + 1u) <= deepest) && (readings[last + 1u] >= wanted))
    {
        last += 1u;
    }
    if ((first > deepest) || ((last - first) < 1u))
    {
        return out;
    }

    double sum_round = 0.0;
    double sum_bits = 0.0;
    double sum_both = 0.0;
    double sum_square = 0.0;
    double counted = 0.0;
    for (unsigned round_at = first; round_at <= last; round_at += 1u)
    {
        const double bits = std::log2(readings[round_at]);
        const double where = (double)round_at;
        sum_round += where;
        sum_bits += bits;
        sum_both += where * bits;
        sum_square += where * where;
        counted += 1.0;
    }

    const double spread = (counted * sum_square) - (sum_round * sum_round);
    if (spread == 0.0)
    {
        return out;
    }
    out.per_round = ((counted * sum_both) - (sum_round * sum_bits)) / spread;
    out.at_zero = (sum_bits - (out.per_round * sum_round)) / counted;
    out.first = first;
    out.last = last;
    out.used = (unsigned)counted;
    return out;
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned trial_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 24u;
    const unsigned deepest = (argc > 2) ? (unsigned)std::atoi(argv[2]) : 24u;
    const uint64_t trials = (uint64_t)1u << trial_bits;

    std::printf("================================================================\n");
    std::printf("  The depth sweep on the device, deep enough to find the end\n");
    std::printf("================================================================\n");
    std::printf("\n  The host sweep found the forward direction dying at nine rounds and the\n");
    std::printf("  inverse still reading 51.8 standard errors at twelve, where it stopped for want\n");
    std::printf("  of samples. Every envelope figure quoting the inverse is therefore a lower\n");
    std::printf("  bound instead of a measurement, and this exists to end that.\n");
    std::printf("\n  Pairs per cell: 2^%u = %llu. Depth swept to %u rounds. Every word read.\n",
                trial_bits, (unsigned long long)trials, deepest);

    unsigned long long *device_wrong = nullptr;
    unsigned long long *device_sums = nullptr;
    unsigned long long *device_counted = nullptr;
    cudaMalloc((void **)&device_wrong, sizeof(unsigned long long));
    cudaMalloc((void **)&device_sums, WORDS * sizeof(unsigned long long));
    cudaMalloc((void **)&device_counted, sizeof(unsigned long long));

    cudaMemset(device_wrong, 0, sizeof(unsigned long long));
    round_trip<<<1024, 256>>>(1000000ull, 20260908ull, device_wrong);
    cudaDeviceSynchronize();
    unsigned long long wrong = 0u;
    cudaMemcpy(&wrong, device_wrong, sizeof(wrong), cudaMemcpyDeviceToHost);
    std::printf("\n  round trips forward then back : 1000000, of those that did not return: %llu\n",
                wrong);
    if (wrong != 0u)
    {
        std::printf("\n  [!] the inverse is not the inverse, so nothing below it means anything.\n");
        return 1;
    }

    const unsigned STRATA = 5u;
    const unsigned low[STRATA] = {1u, 2u, 3u, 5u, 9u};
    const unsigned high[STRATA] = {1u, 2u, 4u, 8u, 16u};

    std::printf("\n  %12s %16s %16s\n", "bits differ", "forward dies", "inverted dies");
    std::printf("  %12s %16s %16s\n", "------------", "----------------", "----------------");

    for (unsigned band = 0u; band < STRATA; band += 1u)
    {
        unsigned dies[2] = {0u, 0u};

        for (int backward = 0; backward < 2; backward += 1)
        {
            for (unsigned rounds = 1u; rounds <= deepest; rounds += 1u)
            {
                cudaMemset(device_sums, 0, WORDS * sizeof(unsigned long long));
                cudaMemset(device_counted, 0, sizeof(unsigned long long));
                walk<<<2048, 128>>>(trials, 20260908ull + (rounds * 7919ull) + band, low[band],
                                    high[band], rounds, backward, device_sums, device_counted);
                cudaDeviceSynchronize();

                unsigned long long sums[WORDS];
                unsigned long long counted = 0u;
                cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
                cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);

                // Every word, and the strongest taken. The surviving word is the least overwritten
                // end of the shift chain, which is the opposite of what was chosen by hand before.
                double strongest = 0.0;
                for (unsigned slot = 0u; slot < WORDS; slot += 1u)
                {
                    const double score =
                        bench_depth_score((double)sums[slot], (double)counted);
                    const double size = (score < 0.0) ? -score : score;
                    strongest = (size > strongest) ? size : strongest;
                }

                if ((dies[backward] == 0u) && (strongest < 4.0))
                {
                    dies[backward] = rounds;
                }
            }
        }

        char label[16];
        if (low[band] == high[band])
        {
            std::snprintf(label, sizeof(label), "%u", low[band]);
        }
        else
        {
            std::snprintf(label, sizeof(label), "%u to %u", low[band], high[band]);
        }

        char forward_label[16];
        char backward_label[16];
        std::snprintf(forward_label, sizeof(forward_label), "%s%u",
                      (dies[0] == 0u) ? "past " : "", (dies[0] == 0u) ? deepest : dies[0]);
        std::snprintf(backward_label, sizeof(backward_label), "%s%u",
                      (dies[1] == 0u) ? "past " : "", (dies[1] == 0u) ? deepest : dies[1]);

        std::printf("  %12s %16s %16s\n", label, forward_label, backward_label);
    }

    // ---------------------------------------------------------------------------------------
    // Exactly zero, or merely tiny?
    //
    // The statistic scales as the square root of the sample, so a signal that is exactly zero can
    // never be pushed past a threshold by more pairs, and one that is small but nonzero always can.
    // Forward stopped at ten rounds and stayed there under sixty-four times the samples while the
    // inverse kept climbing, and that is the difference between those two cases instead of a
    // difference of depth.
    //
    // Which is checkable directly. Read the statistic itself instead of where it crosses four: a
    // column flat near zero across sample sizes is exactly zero, and one growing like the square
    // root of the sample is nonzero and merely small.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Exactly zero, or merely tiny\n");
    std::printf("================================================================\n");
    std::printf("\n  The statistic grows as the square root of the sample, so an exactly zero signal\n");
    std::printf("  cannot be pushed past a threshold by more pairs and a small nonzero one always\n");
    std::printf("  can. Reading the statistic instead of its crossing separates the two.\n");
    std::printf("\n  Weight one. Doubling the pairs multiplies a real signal by 1.414 and leaves a\n");
    std::printf("  zero one alone.\n");

    for (int backward = 0; backward < 2; backward += 1)
    {
        std::printf("\n  %s\n", (backward != 0) ? "inverse" : "forward");
        std::printf("\n  %8s", "rounds");
        for (unsigned shift = 0u; shift < 3u; shift += 1u)
        {
            std::printf(" %14s", (shift == 0u) ? "at 2^22" : ((shift == 1u) ? "at 2^24" : "at 2^26"));
        }
        std::printf(" %12s\n", "ratio");
        std::printf("  %8s %14s %14s %14s %12s\n", "--------", "--------------", "--------------",
                    "--------------", "------------");

        for (unsigned rounds = 9u; rounds <= 18u; rounds += 1u)
        {
            double seen[3];
            for (unsigned shift = 0u; shift < 3u; shift += 1u)
            {
                const uint64_t many = (uint64_t)1u << (22u + (shift * 2u));
                cudaMemset(device_sums, 0, WORDS * sizeof(unsigned long long));
                cudaMemset(device_counted, 0, sizeof(unsigned long long));
                walk<<<2048, 128>>>(many, 20260908ull + (rounds * 7919ull), 1u, 1u, rounds,
                                    backward, device_sums, device_counted);
                cudaDeviceSynchronize();

                unsigned long long sums[WORDS];
                unsigned long long counted = 0u;
                cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
                cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);

                double strongest = 0.0;
                for (unsigned slot = 0u; slot < WORDS; slot += 1u)
                {
                    const double score = bench_depth_score((double)sums[slot], (double)counted);
                    const double size = (score < 0.0) ? -score : score;
                    strongest = (size > strongest) ? size : strongest;
                }
                seen[shift] = strongest;
            }

            // Sixteenfold more pairs multiplies a real signal by four and a zero one by nothing.
            const double ratio = (seen[0] > 0.0) ? (seen[2] / seen[0]) : 0.0;
            std::printf("  %8u %14.3f %14.3f %14.3f %12.2f\n", rounds, seen[0], seen[1], seen[2],
                        ratio);
        }
    }

    std::printf("\n  Sixteen times the pairs multiplies a real signal by four. A ratio near four is\n");
    std::printf("  a signal that was always there and was merely under the threshold; a ratio near\n");
    std::printf("  one is noise, and noise means exactly zero instead of small.\n");

    // ---------------------------------------------------------------------------------------
    // Is the forward zero the function, or the statistic?
    //
    // The forward reading fell from sixty-nine standard errors to noise in one round, which is not
    // how a statistic decays - the inverse alongside it falls by a factor near three and a half per
    // round and takes seven rounds to do the same thing. An exact zero after a sixty-nine sigma
    // reading is a structural fact instead of a sample size.
    //
    // One candidate is that the statistic goes blind instead of the function going ideal. A word's
    // mean Hamming distance is the sum of thirty-two bit rates, and a sum cancels a pair of
    // positions leaning opposite ways. So the same walk is read one bit position at a time, which
    // sees everything the word reading sees plus what the summation throws away.
    //
    // If the zero is blindness, the bit reading carries past where the word reading stopped. If the
    // zero is the function, both stop in the same round and the candidate is subtracted.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  The function, or the statistic\n");
    std::printf("================================================================\n");
    std::printf("\n  Forward fell from sixty-nine standard errors to noise in one round. The inverse\n");
    std::printf("  beside it falls by about three and a half per round and needs seven rounds to\n");
    std::printf("  cover the same ground. A cliff after a sixty-nine sigma reading is structure,\n");
    std::printf("  not sample size, and there are two candidates for what the structure is.\n");
    std::printf("\n  A word's mean Hamming distance is the sum of thirty-two bit rates, and summing\n");
    std::printf("  cancels two positions leaning opposite ways. Reading the same walk one bit\n");
    std::printf("  position at a time removes only the summation. If the word statistic went blind,\n");
    std::printf("  this carries past where it stopped; if the function did, both stop together.\n");
    std::printf("\n  The bit null is a coin, so the noise floor is the largest of 256 draws rather\n");
    std::printf("  than of 8, near 2.9 instead of near 1.9. Both columns are strongest of their\n");
    std::printf("  own kind, so they are compared by where each leaves its own floor.\n");

    unsigned long long *device_bits = nullptr;
    cudaMalloc((void **)&device_bits, 256u * sizeof(unsigned long long));

    for (int backward = 0; backward < 2; backward += 1)
    {
        std::printf("\n  %s, at 2^24 pairs, one bit flipped\n",
                    (backward != 0) ? "inverse" : "forward");
        std::printf("\n  %8s %16s %16s %14s\n", "rounds", "by word", "by bit position",
                    "which sees");
        std::printf("  %8s %16s %16s %14s\n", "--------", "----------------", "----------------",
                    "--------------");

        for (unsigned rounds = 8u; rounds <= 18u; rounds += 1u)
        {
            const uint64_t many = (uint64_t)1u << 24u;
            const uint64_t stream = 20260908ull + (rounds * 7919ull);

            cudaMemset(device_sums, 0, WORDS * sizeof(unsigned long long));
            cudaMemset(device_counted, 0, sizeof(unsigned long long));
            walk<<<2048, 128>>>(many, stream, 1u, 1u, rounds, backward, device_sums,
                                device_counted);
            cudaDeviceSynchronize();

            unsigned long long sums[WORDS];
            unsigned long long counted = 0u;
            cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
            cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);

            double by_word = 0.0;
            for (unsigned slot = 0u; slot < WORDS; slot += 1u)
            {
                const double score = bench_depth_score((double)sums[slot], (double)counted);
                const double size = (score < 0.0) ? -score : score;
                by_word = (size > by_word) ? size : by_word;
            }

            // The same seed and the same depth, so the two columns read one experiment instead of
            // two. A different stream here would leave a disagreement unattributable.
            cudaMemset(device_bits, 0, 256u * sizeof(unsigned long long));
            cudaMemset(device_counted, 0, sizeof(unsigned long long));
            walk_bits<<<2048, 128>>>(many, stream, 1u, 1u, rounds, backward, device_bits,
                                     device_counted);
            cudaDeviceSynchronize();

            unsigned long long tally[256];
            unsigned long long bit_counted = 0u;
            cudaMemcpy(tally, device_bits, sizeof(tally), cudaMemcpyDeviceToHost);
            cudaMemcpy(&bit_counted, device_counted, sizeof(bit_counted), cudaMemcpyDeviceToHost);

            double by_bit = 0.0;
            for (unsigned at = 0u; at < 256u; at += 1u)
            {
                const double score = bench_depth_bit_score((double)tally[at],
                                                           (double)bit_counted);
                const double size = (score < 0.0) ? -score : score;
                by_bit = (size > by_bit) ? size : by_bit;
            }

            const char *reads = "neither";
            if ((by_word >= 4.0) && (by_bit >= 5.0))
            {
                reads = "both";
            }
            else if (by_bit >= 5.0)
            {
                reads = "bit only";
            }
            else if (by_word >= 4.0)
            {
                reads = "word only";
            }
            std::printf("  %8u %16.3f %16.3f %14s\n", rounds, by_word, by_bit, reads);
        }
    }

    cudaFree(device_bits);

    std::printf("\n  A row reading bit only is the word statistic going blind instead of the\n");
    std::printf("  function going ideal, and the envelope quoted from the word reading is short by\n");
    std::printf("  however many such rows there are. A table with no such row subtracts the\n");
    std::printf("  candidate and leaves the cliff standing as a fact about SHA-256.\n");

    // ---------------------------------------------------------------------------------------
    // A cliff, or a steeper slope?
    //
    // Calling the forward zero exact was one step further than the samples go. Forward falls from
    // 1071 to 36 between rounds eight and nine, a factor near thirty per round, where the inverse
    // falls by about two. A slope that steep leaves round ten at 36/30, which is 1.2 - underneath
    // the 1.9 noise floor of a largest-of-eight statistic. So an exact zero and a slope fifteen
    // times steeper than the inverse's predict the same unreadable row, and the ratio test cannot
    // tell them apart where it was run.
    //
    // It tells them apart with more pairs, because the two predictions diverge: a continued slope
    // scales with the square root of the sample and a zero does not. At 2^30 the slope predicts
    // near ten and the zero predicts the floor, which is not a close call.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  A cliff, or a steeper slope\n");
    std::printf("================================================================\n");
    std::printf("\n  Forward falls by a factor near thirty per round where the inverse falls by two.\n");
    std::printf("  A slope that steep puts round ten at 1.2, underneath the 1.9 floor of a\n");
    std::printf("  largest-of-eight statistic, so a genuine zero and a merely steeper slope predict\n");
    std::printf("  the same unreadable row and the sweep above cannot separate them.\n");
    std::printf("\n  More pairs separate them, because only one of the two grows. The slope column\n");
    std::printf("  is what round nine would become at this depth if the factor held.\n");

    {
        const double anchor[2] = {36.035, 8428.069};   // round nine at 2^24, both directions.
        const double factor[2] = {29.7, 2.10};         // rounds eight to nine, both directions.

        for (int backward = 0; backward < 2; backward += 1)
        {
            std::printf("\n  %s, round ten, one bit flipped\n",
                        (backward != 0) ? "inverse" : "forward");
            std::printf("\n  %10s %14s %14s %14s\n", "pairs", "observed", "if slope held",
                        "verdict");
            std::printf("  %10s %14s %14s %14s\n", "----------", "--------------",
                        "--------------", "--------------");

            for (unsigned power = 26u; power <= 30u; power += 2u)
            {
                const uint64_t many = (uint64_t)1u << power;
                cudaMemset(device_sums, 0, WORDS * sizeof(unsigned long long));
                cudaMemset(device_counted, 0, sizeof(unsigned long long));
                walk<<<4096, 128>>>(many, 20260908ull + (10ull * 7919ull), 1u, 1u, 10u, backward,
                                    device_sums, device_counted);
                cudaDeviceSynchronize();

                unsigned long long sums[WORDS];
                unsigned long long counted = 0u;
                cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
                cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);

                double strongest = 0.0;
                for (unsigned slot = 0u; slot < WORDS; slot += 1u)
                {
                    const double score = bench_depth_score((double)sums[slot], (double)counted);
                    const double size = (score < 0.0) ? -score : score;
                    strongest = (size > strongest) ? size : strongest;
                }

                // Round nine's reading, divided by one more round of its own decay, then carried
                // from 2^24 to here by the square root of the sample ratio.
                const double carried = std::sqrt((double)many / (double)((uint64_t)1u << 24u));
                const double predicted = (anchor[backward] / factor[backward]) * carried;

                const char *verdict = "floor";
                if (strongest > (predicted * 0.5))
                {
                    verdict = "slope holds";
                }
                else if (strongest > 6.0)
                {
                    verdict = "something";
                }
                std::printf("  %10s %14.3f %14.3f %14s\n",
                            (power == 26u) ? "2^26" : ((power == 28u) ? "2^28" : "2^30"),
                            strongest, predicted, verdict);
            }
        }
    }

    std::printf("\n  The inverse row is the control: its slope is known to hold at round ten, so a\n");
    std::printf("  reading near its prediction says the method works and a forward row at the floor\n");
    std::printf("  beneath a prediction near ten is a cliff instead of a slope.\n");

    // ---------------------------------------------------------------------------------------
    // Projecting each slope onto the cliff.
    //
    // A cliff is only a cliff against a trend. Everything above measured decay from round eight,
    // which is one round of forward slope before it terminates - not enough to say what the trend
    // was. So both directions are swept from round one, the noise floor is measured instead of
    // assumed, a line is fitted to the rounds that are clearly signal, and the fitted lines are
    // asked where they cross things.
    //
    // Three intersections, and each one says something different:
    //
    //   own line against the floor  - where a direction would have died had it kept its own trend.
    //                                 The gap to where it actually died is the cliff, in rounds.
    //   the two lines against each other - the round where both directions are equally visible.
    //   each line at the other's wall - what one direction predicts at the depth the other reaches.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Projecting each slope onto the cliff\n");
    std::printf("================================================================\n");
    std::printf("\n  A cliff is only a cliff against a trend, and everything above measured the\n");
    std::printf("  forward trend from a single round. Both directions are swept from round one at\n");
    std::printf("  2^26 pairs, the floor is measured instead of assumed, and a line is fitted to\n");
    std::printf("  the rounds standing a hundredfold clear of that floor.\n");

    {
        const unsigned PROJECT_DEEPEST = 20u;
        const unsigned FLOOR_FROM = 21u;
        const unsigned FLOOR_TO = 26u;
        const uint64_t many = (uint64_t)1u << 26u;

        double curve[2][PROJECT_DEEPEST + 1u];
        double floor_at = 0.0;
        double floor_count = 0.0;

        for (int backward = 0; backward < 2; backward += 1)
        {
            for (unsigned rounds = 1u; rounds <= FLOOR_TO; rounds += 1u)
            {
                cudaMemset(device_sums, 0, WORDS * sizeof(unsigned long long));
                cudaMemset(device_counted, 0, sizeof(unsigned long long));
                walk<<<4096, 128>>>(many, 20260908ull + (rounds * 7919ull), 1u, 1u, rounds,
                                    backward, device_sums, device_counted);
                cudaDeviceSynchronize();

                unsigned long long sums[WORDS];
                unsigned long long counted = 0u;
                cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
                cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);

                double strongest = 0.0;
                for (unsigned slot = 0u; slot < WORDS; slot += 1u)
                {
                    const double score = bench_depth_score((double)sums[slot], (double)counted);
                    const double size = (score < 0.0) ? -score : score;
                    strongest = (size > strongest) ? size : strongest;
                }

                if (rounds <= PROJECT_DEEPEST)
                {
                    curve[backward][rounds] = strongest;
                }

                // The floor is the same statistic at depths where nothing survives, in both
                // directions, so it is this experiment's own floor instead of a table value for
                // the largest of eight half-normals.
                if (rounds >= FLOOR_FROM)
                {
                    floor_at += strongest;
                    floor_count += 1.0;
                }
            }
        }
        floor_at = (floor_count > 0.0) ? (floor_at / floor_count) : 1.86;
        curve[0][0] = 0.0;
        curve[1][0] = 0.0;

        std::printf("\n  Measured noise floor, rounds %u to %u, both directions: %.3f\n", FLOOR_FROM,
                    FLOOR_TO, floor_at);

        std::printf("\n  %8s %16s %10s %16s %10s\n", "rounds", "forward", "fwd x/rd", "inverse",
                    "inv x/rd");
        std::printf("  %8s %16s %10s %16s %10s\n", "--------", "----------------", "----------",
                    "----------------", "----------");
        for (unsigned rounds = 1u; rounds <= PROJECT_DEEPEST; rounds += 1u)
        {
            char forward_step[16];
            char inverse_step[16];
            for (int backward = 0; backward < 2; backward += 1)
            {
                char *const into = (backward != 0) ? inverse_step : forward_step;
                if ((rounds > 1u) && (curve[backward][rounds] > 0.0))
                {
                    std::snprintf(into, sizeof(forward_step), "%.2f",
                                  curve[backward][rounds - 1u] / curve[backward][rounds]);
                }
                else
                {
                    std::snprintf(into, sizeof(forward_step), "%s", "-");
                }
            }
            std::printf("  %8u %16.3f %10s %16.3f %10s\n", rounds, curve[0][rounds], forward_step,
                        curve[1][rounds], inverse_step);
        }

        const double ceiling = bench_depth_ceiling((double)many, BENCH_DEPTH_WORD_BITS);
        std::printf("  Saturation ceiling, a word no difference has reached yet: %.3f\n", ceiling);
        std::printf("\n  A run of rounds pinned at that ceiling is the shift chain holding an\n");
        std::printf("  untouched word, not a decay, and it is kept out of the fit below.\n");

        const Decay forward_line = fit_decay(curve[0], PROJECT_DEEPEST, floor_at, ceiling);
        const Decay inverse_line = fit_decay(curve[1], PROJECT_DEEPEST, floor_at, ceiling);

        std::printf("\n  %10s %14s %14s %10s %10s\n", "direction", "factor/round", "fitted over",
                    "rounds", "at round 0");
        std::printf("  %10s %14s %14s %10s %10s\n", "----------", "--------------",
                    "--------------", "----------", "----------");
        for (int backward = 0; backward < 2; backward += 1)
        {
            const Decay line = (backward != 0) ? inverse_line : forward_line;
            char window[16];
            std::snprintf(window, sizeof(window), "%u-%u", line.first, line.last);
            std::printf("  %10s %14.3f %14s %10u %10.1f\n", (backward != 0) ? "inverse" : "forward",
                        std::pow(2.0, -line.per_round), window, line.used, line.at_zero);
        }

        // Where a fitted line falls to the floor. This is the round the direction would have died
        // in had it kept the trend it was on, and the distance from where it actually died is the
        // whole of what "cliff" means.
        const double floor_bits = std::log2(floor_at);
        std::printf("\n  Intersections\n");
        std::printf("\n  %-44s %12s %12s %10s\n", "what crosses what", "at round", "actually",
                    "shortfall");
        std::printf("  %-44s %12s %12s %10s\n", "--------------------------------------------",
                    "------------", "------------", "----------");

        const unsigned died[2] = {10u, 15u};
        for (int backward = 0; backward < 2; backward += 1)
        {
            const Decay line = (backward != 0) ? inverse_line : forward_line;
            if (line.used < 2u)
            {
                continue;
            }
            const double crosses = (floor_bits - line.at_zero) / line.per_round;
            char label[64];
            std::snprintf(label, sizeof(label), "%s trend, projected onto the floor",
                          (backward != 0) ? "inverse" : "forward");
            std::printf("  %-44s %12.2f %12u %10.2f\n", label, crosses, died[backward],
                        crosses - (double)died[backward]);
        }

        if ((forward_line.used >= 2u) && (inverse_line.used >= 2u))
        {
            const double apart = forward_line.per_round - inverse_line.per_round;
            if (apart != 0.0)
            {
                const double meets = (inverse_line.at_zero - forward_line.at_zero) / apart;
                const double height = (forward_line.per_round * meets) + forward_line.at_zero;
                std::printf("  %-44s %12.2f %12s %10s\n", "the two trends, against each other",
                            meets, "-", "-");
                std::printf("  %-44s %12.2f %12s %10s\n", "  ...where they read (bits)", height,
                            "-", "-");
            }

            // What each direction's trend predicts at the depth the other actually reached. A trend
            // that predicts something readable where the other direction stopped is a statement
            // about which direction to spend samples on.
            for (int backward = 0; backward < 2; backward += 1)
            {
                const Decay line = (backward != 0) ? inverse_line : forward_line;
                const unsigned there = died[1 - backward];
                const double bits = (line.per_round * (double)there) + line.at_zero;
                char label[64];
                std::snprintf(label, sizeof(label), "%s trend, at the %s wall (round %u)",
                              (backward != 0) ? "inverse" : "forward",
                              (backward != 0) ? "forward" : "inverse", there);
                std::printf("  %-44s %12.3f %12s %10s\n", label, std::pow(2.0, bits), "-", "-");
            }
        }

        std::printf("\n  A shortfall near zero says a direction died where its own trend said it\n");
        std::printf("  would, which is a sample limit and no structure at all. A large negative\n");
        std::printf("  shortfall says it died early against its own trend, and that is the cliff.\n");
    }

    // ---------------------------------------------------------------------------------------
    // The nonce, which does not elide.
    //
    // Every arm above hands the same schedule word to both members of a pair, and in the additive
    // difference that word cancels identically - (h + S + Ch + K + W) minus (h' + S' + Ch' + K + W)
    // contains no W. So the schedule contributed exactly nothing, and what those arms measured was
    // the state chain unwinding on its own. That is why it comes out a smooth slope: there is only
    // one mechanism in it.
    //
    // A miner does not vary the state. A miner varies the nonce, which enters the schedule and is
    // expanded into every later word, so it cannot cancel. This arm places one bit of difference in
    // message word three - where a header's nonce sits - runs the standard's expansion, and reads
    // the same statistic. Whether the wall is in the same place is the question.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  The nonce, which does not elide\n");
    std::printf("================================================================\n");
    std::printf("\n  Every arm above hands both members of a pair the same schedule word, and in\n");
    std::printf("  the additive difference that word cancels identically. The schedule contributed\n");
    std::printf("  nothing, so those arms measured the state chain unwinding alone - one mechanism,\n");
    std::printf("  which is why it comes out a smooth slope.\n");
    std::printf("\n  A miner varies the nonce, not the state. One bit of message word three, run\n");
    std::printf("  through the standard's expansion, cannot cancel and reaches every later word.\n");

    // Which words the nonce reaches is exact instead of statistical, so it is computed instead of
    // sampled. W[at] draws on at-16, at-15, at-7 and at-2, so taint propagates by those four edges
    // from word three, and a round whose word is untouched does identical work for every nonce.
    {
        int tainted[64];
        for (unsigned at = 0u; at < 16u; at += 1u)
        {
            tainted[at] = (at == 3u) ? 1 : 0;
        }
        for (unsigned at = 16u; at < 64u; at += 1u)
        {
            tainted[at] = (tainted[at - 16u] | tainted[at - 15u] | tainted[at - 7u] |
                           tainted[at - 2u]);
        }

        unsigned first_touched = 64u;
        unsigned clean_count = 0u;
        unsigned last_clean = 0u;
        for (unsigned at = 0u; at < 64u; at += 1u)
        {
            if (tainted[at] == 0)
            {
                clean_count += 1u;
                last_clean = at;
            }
            else if (first_touched == 64u)
            {
                first_touched = at;
            }
        }

        std::printf("\n  Exact schedule dependency, one nonce word\n");
        std::printf("\n  %-46s %14u\n", "first schedule word the nonce reaches", first_touched);
        std::printf("  %-46s %14u\n", "schedule words independent of the nonce", clean_count);
        std::printf("  %-46s %14u\n", "deepest nonce-independent word", last_clean);

        std::printf("\n  ");
        for (unsigned at = 0u; at < 64u; at += 1u)
        {
            std::printf("%c", (tainted[at] != 0) ? 'n' : '.');
            if (((at + 1u) % 16u) == 0u)
            {
                std::printf("\n  ");
            }
        }
        std::printf("\n  A dot is a schedule word every nonce shares, computed once per header\n");
        std::printf("  instead of once per nonce. Rounds before the first n do identical state\n");
        std::printf("  work for every nonce and belong outside the inner loop with the midstate.\n");

        // The other side of the same curve. Forward taint says which rounds every nonce shares;
        // the backward cone says which rounds do not need all eight words, because the difficulty
        // test reads one word and not the digest. Bitcoin compares the hash as a little-endian
        // number, so the leading zeros land in word seven, and that single word is the only output
        // a rejection needs.
        //
        // The round moves a to b, b to c and so on, so a word at the output reaches back one slot
        // per round until it arrives at e or a, which draw on five and seven words respectively.
        // Until that happens the tail is narrower than the function.
        const unsigned needs[WORDS] = {
            0xf7u,   // a' takes a, b, c, e, f, g, h - every word but d.
            0x01u,   // b' is a.
            0x02u,   // c' is b.
            0x04u,   // d' is c.
            0xf8u,   // e' takes d, e, f, g, h.
            0x10u,   // f' is e.
            0x20u,   // g' is f.
            0x40u    // h' is g.
        };

        std::printf("\n  Exact backward cone, from the one word a rejection reads\n");
        std::printf("\n  %-22s %14s %14s\n", "rounds from the end", "words needed", "of eight");
        std::printf("  %-22s %14s %14s\n", "----------------------", "--------------",
                    "--------------");

        unsigned wanted = 1u << 7;
        unsigned narrow_area = 0u;
        unsigned narrow_rounds = 0u;
        for (unsigned back = 1u; back <= 12u; back += 1u)
        {
            unsigned earlier = 0u;
            for (unsigned slot = 0u; slot < WORDS; slot += 1u)
            {
                if ((wanted & (1u << slot)) != 0u)
                {
                    earlier |= needs[slot];
                }
            }
            wanted = earlier;

            // Only the tail counts. Adding the full width for rounds past the cone would sum a
            // longer span than narrow_rounds names, and subtracting the two then underflows.
            const unsigned width = (unsigned)__popcnt(wanted);
            if ((width < WORDS) && (narrow_rounds == (back - 1u)))
            {
                narrow_area += width;
                narrow_rounds = back;
            }
            if (back <= 10u)
            {
                std::printf("  %-22u %14u %14u\n", back, width, WORDS);
            }
        }

        std::printf("\n  %-46s %14u\n", "tail rounds needing fewer than eight words",
                    narrow_rounds);
        std::printf("  %-46s %14u\n", "word-rounds in that tail, against eight each",
                    narrow_area);
        std::printf("  %-46s %14u\n", "front rounds every nonce shares", first_touched);

        // What a nonce cannot avoid: the sixty-four rounds, less the front rounds that are shared
        // and less the words the tail never needs.
        const unsigned full = 64u * WORDS;
        const unsigned saved_front = first_touched * WORDS;
        const unsigned saved_tail = (narrow_rounds * WORDS) - narrow_area;
        std::printf("  %-46s %14u\n", "word-rounds per nonce, all sixty-four rounds", full);
        std::printf("  %-46s %14u\n", "  less the shared front", saved_front);
        std::printf("  %-46s %14u\n", "  less the narrow tail", saved_tail);
        std::printf("  %-46s %14u\n", "smallest area a nonce must actually cross",
                    full - saved_front - saved_tail);
        std::printf("\n  That last figure is the floor this arithmetic gives for one SHA-256 block\n");
        std::printf("  of a nonce loop. It is a count of word-rounds, not of instructions, and\n");
        std::printf("  nothing here has yet checked it against what the miner does per nonce.\n");
    }

    {
        const uint64_t many = (uint64_t)1u << 24u;
        const double ceiling = bench_depth_ceiling((double)many, BENCH_DEPTH_WORD_BITS);

        std::printf("\n  %8s %16s %10s %14s\n", "rounds", "state difference", "x/round",
                    "nonce difference");
        std::printf("  %8s %16s %10s %14s\n", "--------", "----------------", "----------",
                    "--------------");

        double before_state = 0.0;
        for (unsigned rounds = 1u; rounds <= 20u; rounds += 1u)
        {
            double reading[2];
            for (int is_nonce = 0; is_nonce < 2; is_nonce += 1)
            {
                cudaMemset(device_sums, 0, WORDS * sizeof(unsigned long long));
                cudaMemset(device_counted, 0, sizeof(unsigned long long));
                if (is_nonce != 0)
                {
                    walk_nonce<<<4096, 128>>>(many, 20260908ull + (rounds * 7919ull), rounds, 7u,
                                              device_sums, device_counted);
                }
                else
                {
                    walk<<<4096, 128>>>(many, 20260908ull + (rounds * 7919ull), 1u, 1u, rounds, 0,
                                        device_sums, device_counted);
                }
                cudaDeviceSynchronize();

                unsigned long long sums[WORDS];
                unsigned long long counted = 0u;
                cudaMemcpy(sums, device_sums, sizeof(sums), cudaMemcpyDeviceToHost);
                cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);

                double strongest = 0.0;
                for (unsigned slot = 0u; slot < WORDS; slot += 1u)
                {
                    const double score = bench_depth_score((double)sums[slot], (double)counted);
                    const double size = (score < 0.0) ? -score : score;
                    strongest = (size > strongest) ? size : strongest;
                }
                reading[is_nonce] = strongest;
            }

            char step_size[16];
            if ((rounds > 1u) && (reading[0] > 0.0) && (before_state < ceiling * 0.95))
            {
                std::snprintf(step_size, sizeof(step_size), "%.2f", before_state / reading[0]);
            }
            else
            {
                std::snprintf(step_size, sizeof(step_size), "%s", "-");
            }
            before_state = reading[0];

            std::printf("  %8u %16.3f %10s %14.3f\n", rounds, reading[0], step_size, reading[1]);
        }

        std::printf("\n  A nonce column that stays at the ceiling for longer than the state column\n");
        std::printf("  is the expansion delaying arrival instead of the round function mixing\n");
        std::printf("  harder, and a nonce column that outlives the state column is the schedule\n");
        std::printf("  carrying difference the state chain had already destroyed.\n");
    }

    std::printf("\n  A column reading past the sweep is still a lower bound and says so. A column\n");
    std::printf("  with a number in it is where four standard errors was no longer cleared, at\n");
    std::printf("  this many pairs, reading whichever word held the difference longest.\n");

    cudaFree(device_wrong);
    cudaFree(device_sums);
    cudaFree(device_counted);
    return 0;
}
