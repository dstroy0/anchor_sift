/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_trap.cu
 * @brief Whether the state partway through says anything about how the digest ends.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note The round is a bijection and the mixing functions all have full rank, so the reachable set
 *       never narrows: 2^32 nonces stay 2^32 distinct states however many rounds run. That rules
 *       out a funnel in the counting sense and says nothing at all about the question that matters,
 *       which is whether the funnel is visible from inside it.
 * @note If any statistic of the state at round r predicts whether the finished digest carries
 *       leading zeros, a nonce can be refused at round r instead of at round 128 and the cost of
 *       mining falls by whatever fraction of the rounds is skipped. That is the only shape of
 *       shortcut this tree has not tested: bench_renyi surveyed the *output* set for structure and
 *       found none, and bench_depth measured how *differences* propagate, but neither asked whether
 *       an intermediate value correlates with the final one.
 * @note The test is a per-bit one because it is the weakest assumption available. Instead of
 *       guessing which function of the state might carry the signal, every one of the 256 state
 *       bits is scored separately for how differently it behaves on nonces whose digest came out
 *       small.
 *       Anything a simple early-reject rule could use has to show up as a bias on at least one bit.
 * @warning A winner here is a digest whose top bits are zero at a threshold far weaker than a real
 *          share, because a real one arrives once in 2^32 and no sample reaches that. The weaker
 *          threshold is what makes the question answerable at all, and a correlation that exists
 *          only at the real threshold and not at this one would be missed.
 */

#include <cuda_runtime.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace
{

/** @brief Bits of the finished digest that must be zero for a nonce to count as a winner. */
const unsigned WINNING_ZEROS = 16u;

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

/** @brief The standard's initial chaining value. */
__constant__ uint32_t d_start[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                                    0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};

__device__ __forceinline__ uint32_t turn(uint32_t value, uint32_t by)
{
    return __funnelshift_r(value, value, by);
}

__device__ __forceinline__ uint32_t small_zero(uint32_t value)
{
    return turn(value, 7u) ^ turn(value, 18u) ^ (value >> 3u);
}

__device__ __forceinline__ uint32_t small_one(uint32_t value)
{
    return turn(value, 17u) ^ turn(value, 19u) ^ (value >> 10u);
}

#define TRAP_ROUND(a_, b_, c_, d_, e_, f_, g_, h_, round_, word_)                                 \
    do                                                                                            \
    {                                                                                             \
        const uint32_t high = turn(e_, 6u) ^ turn(e_, 11u) ^ turn(e_, 25u);                       \
        const uint32_t choose = g_ ^ (e_ & (f_ ^ g_));                                            \
        const uint32_t one = h_ + high + choose + d_constant[round_] + (word_);                   \
        const uint32_t low = turn(a_, 2u) ^ turn(a_, 13u) ^ turn(a_, 22u);                        \
        const uint32_t many = (a_ & b_) | (c_ & (a_ ^ b_));                                       \
        h_ = g_; g_ = f_; f_ = e_; e_ = d_ + one;                                                 \
        d_ = c_; c_ = b_; b_ = a_; a_ = one + low + many;                                          \
    } while (0)

/**
 * @brief Hashes a nonce, keeps the state at a chosen round, and scores the finished digest.
 *
 * @param[in]     midstate  Chaining value after the header's first block [BORROWS].
 * @param[in]     tail      Header words sixty-four through seventy-five [BORROWS].
 * @param[in]     nonces    How many nonces to walk.
 * @param[in]     watch     Which round of the second block to photograph.
 * @param[in,out] ones_all  256 counters, how often each state bit was one [BORROWS].
 * @param[in,out] ones_win  The same, over winners only [BORROWS].
 * @param[in,out] winners   How many winners were seen [BORROWS].
 * @param[in,out] walked    How many nonces were walked [BORROWS].
 * @note The photograph is taken of the second block, because that is the one whose output is
 *       tested. A correlation in the first block would have to survive the second to be usable.
 */
__global__ void look_for_the_trap(const uint32_t *midstate, const uint32_t *tail, uint32_t nonces,
                                  unsigned watch, unsigned long long *ones_all,
                                  unsigned long long *ones_win, unsigned long long *winners,
                                  unsigned long long *walked, uint32_t *winner_photos,
                                  uint32_t *control_photos, unsigned *kept_winners,
                                  unsigned *kept_control, unsigned keep_limit)
{
    __shared__ unsigned long long tally_all[256];
    __shared__ unsigned long long tally_win[256];
    for (unsigned at = threadIdx.x; at < 256u; at += blockDim.x)
    {
        tally_all[at] = 0u;
        tally_win[at] = 0u;
    }
    __syncthreads();

    const uint32_t stride = gridDim.x * blockDim.x;
    unsigned long long seen = 0u;
    unsigned long long won = 0u;

    for (uint32_t index = (blockIdx.x * blockDim.x) + threadIdx.x; index < nonces; index += stride)
    {
        uint32_t schedule[64];
        schedule[0] = tail[0];
        schedule[1] = tail[1];
        schedule[2] = tail[2];
        schedule[3] = __byte_perm(index, 0u, 0x0123u);
        schedule[4] = 0x80000000u;
        for (unsigned slot = 5u; slot < 15u; slot += 1u)
        {
            schedule[slot] = 0u;
        }
        schedule[15] = 0x00000280u;

        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            schedule[slot] = small_one(schedule[slot - 2u]) + schedule[slot - 7u] +
                             small_zero(schedule[slot - 15u]) + schedule[slot - 16u];
        }

        uint32_t a = midstate[0], b = midstate[1], c = midstate[2], d = midstate[3];
        uint32_t e = midstate[4], f = midstate[5], g = midstate[6], h = midstate[7];
        for (unsigned round = 0u; round < 64u; round += 1u)
        {
            TRAP_ROUND(a, b, c, d, e, f, g, h, round, schedule[round]);
        }

        schedule[0] = midstate[0] + a;
        schedule[1] = midstate[1] + b;
        schedule[2] = midstate[2] + c;
        schedule[3] = midstate[3] + d;
        schedule[4] = midstate[4] + e;
        schedule[5] = midstate[5] + f;
        schedule[6] = midstate[6] + g;
        schedule[7] = midstate[7] + h;
        schedule[8] = 0x80000000u;
        for (unsigned slot = 9u; slot < 15u; slot += 1u)
        {
            schedule[slot] = 0u;
        }
        schedule[15] = 0x00000100u;
        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            schedule[slot] = small_one(schedule[slot - 2u]) + schedule[slot - 7u] +
                             small_zero(schedule[slot - 15u]) + schedule[slot - 16u];
        }

        a = d_start[0]; b = d_start[1]; c = d_start[2]; d = d_start[3];
        e = d_start[4]; f = d_start[5]; g = d_start[6]; h = d_start[7];

        uint32_t photo[8];
        for (unsigned round = 0u; round < 64u; round += 1u)
        {
            if (round == watch)
            {
                photo[0] = a; photo[1] = b; photo[2] = c; photo[3] = d;
                photo[4] = e; photo[5] = f; photo[6] = g; photo[7] = h;
            }
            TRAP_ROUND(a, b, c, d, e, f, g, h, round, schedule[round]);
        }

        // Bitcoin reads the hash as a little-endian number, so the leading zeros land in word seven
        // and that word alone decides a rejection.
        const uint32_t top = __byte_perm(d_start[7] + h, 0u, 0x0123u);
        const int is_winner = (top >> (32u - WINNING_ZEROS)) == 0u;

        for (unsigned slot = 0u; slot < 8u; slot += 1u)
        {
            uint32_t bits = photo[slot];
            while (bits != 0u)
            {
                const unsigned bit = (unsigned)__ffs((int)bits) - 1u;
                atomicAdd(&tally_all[(slot * 32u) + bit], 1ull);
                if (is_winner != 0)
                {
                    atomicAdd(&tally_win[(slot * 32u) + bit], 1ull);
                }
                bits &= bits - 1u;
            }
        }
        // The photograph is kept as well as counted. Single bits are unigrams and a structure can
        // be invisible in those while showing plainly in pairs, so the raw states are carried back
        // and every pair scored on the host instead of guessed at here.
        if (is_winner != 0)
        {
            const unsigned slot = atomicAdd(kept_winners, 1u);
            if (slot < keep_limit)
            {
                for (unsigned word = 0u; word < 8u; word += 1u)
                {
                    winner_photos[(slot * 8u) + word] = photo[word];
                }
            }
        }
        else if ((index & 0xffffu) == 0u)
        {
            // A control drawn on a fixed stride instead of at random, so it is reproducible and
            // independent of anything the digest did.
            const unsigned slot = atomicAdd(kept_control, 1u);
            if (slot < keep_limit)
            {
                for (unsigned word = 0u; word < 8u; word += 1u)
                {
                    control_photos[(slot * 8u) + word] = photo[word];
                }
            }
        }

        seen += 1u;
        won += (unsigned long long)(is_winner != 0);
    }
    __syncthreads();

    for (unsigned at = threadIdx.x; at < 256u; at += blockDim.x)
    {
        atomicAdd(&ones_all[at], tally_all[at]);
        atomicAdd(&ones_win[at], tally_win[at]);
    }
    atomicAdd(walked, seen);
    atomicAdd(winners, won);
}

/**
 * @brief Counts which nonces win, by bit position and by how many bits they carry.
 *
 * @param[in]     midstate    Chaining value after the header's first block [BORROWS].
 * @param[in]     tail        Header words sixty-four through seventy-five [BORROWS].
 * @param[in]     nonces      How many nonces to walk.
 * @param[in,out] by_bit      32 counters, winners whose nonce carried each bit [BORROWS].
 * @param[in,out] by_weight   33 counters, winners at each nonce Hamming weight [BORROWS].
 * @param[in,out] winners     Total winners [BORROWS].
 * @note The totals need no counting because they are exact: half the nonce space carries any given
 *       bit, and C(32,w) of it has weight w. Only the winners have to be counted, and comparing a
 *       measured count against an exact total is a stronger test than comparing two measured ones.
 * @note This is the scarcity question aimed at the input instead of at a difference. If a nonce of
 *       low weight wins more often than one of high weight, the search order is not arbitrary and
 *       the cheap nonces should be tried first.
 */
__global__ void which_nonces_win(const uint32_t *midstate, const uint32_t *tail, uint64_t nonces,
                                 unsigned long long *by_bit, unsigned long long *by_weight,
                                 unsigned long long *winners)
{
    // Sixty-four bits of counter, because the whole nonce space is 2^32 and a uint32_t loop cannot
    // express its own bound. Sweeping 2^31 instead leaves bit thirty-one zero in every sample,
    // which reads as a 180 sigma bias against an expectation computed over the full space - an
    // artifact of the range, not a property of SHA-256.
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;

    for (uint64_t counter = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; counter < nonces;
         counter += stride)
    {
        const uint32_t index = (uint32_t)counter;
        uint32_t schedule[64];
        schedule[0] = tail[0];
        schedule[1] = tail[1];
        schedule[2] = tail[2];
        schedule[3] = __byte_perm(index, 0u, 0x0123u);
        schedule[4] = 0x80000000u;
        for (unsigned slot = 5u; slot < 15u; slot += 1u)
        {
            schedule[slot] = 0u;
        }
        schedule[15] = 0x00000280u;
        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            schedule[slot] = small_one(schedule[slot - 2u]) + schedule[slot - 7u] +
                             small_zero(schedule[slot - 15u]) + schedule[slot - 16u];
        }

        uint32_t a = midstate[0], b = midstate[1], c = midstate[2], d = midstate[3];
        uint32_t e = midstate[4], f = midstate[5], g = midstate[6], h = midstate[7];
        for (unsigned round = 0u; round < 64u; round += 1u)
        {
            TRAP_ROUND(a, b, c, d, e, f, g, h, round, schedule[round]);
        }

        schedule[0] = midstate[0] + a;
        schedule[1] = midstate[1] + b;
        schedule[2] = midstate[2] + c;
        schedule[3] = midstate[3] + d;
        schedule[4] = midstate[4] + e;
        schedule[5] = midstate[5] + f;
        schedule[6] = midstate[6] + g;
        schedule[7] = midstate[7] + h;
        schedule[8] = 0x80000000u;
        for (unsigned slot = 9u; slot < 15u; slot += 1u)
        {
            schedule[slot] = 0u;
        }
        schedule[15] = 0x00000100u;
        for (unsigned slot = 16u; slot < 64u; slot += 1u)
        {
            schedule[slot] = small_one(schedule[slot - 2u]) + schedule[slot - 7u] +
                             small_zero(schedule[slot - 15u]) + schedule[slot - 16u];
        }

        a = d_start[0]; b = d_start[1]; c = d_start[2]; d = d_start[3];
        e = d_start[4]; f = d_start[5]; g = d_start[6]; h = d_start[7];
        for (unsigned round = 0u; round < 64u; round += 1u)
        {
            TRAP_ROUND(a, b, c, d, e, f, g, h, round, schedule[round]);
        }

        const uint32_t top = __byte_perm(d_start[7] + h, 0u, 0x0123u);
        if ((top >> (32u - WINNING_ZEROS)) != 0u)
        {
            continue;
        }

        atomicAdd(winners, 1ull);
        atomicAdd(&by_weight[__popc(index)], 1ull);
        uint32_t bits = index;
        while (bits != 0u)
        {
            const unsigned bit = (unsigned)__ffs((int)bits) - 1u;
            atomicAdd(&by_bit[bit], 1ull);
            bits &= bits - 1u;
        }
    }
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned nonce_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 26u;
    const uint32_t nonces = (uint32_t)1u << nonce_bits;

    // An arbitrary fixed header, and arbitrary is correct instead of lazy: the question is about
    // SHA-256's own statistics and not about any block, so a header that is merely fixed answers it
    // exactly as a published one would. Calling these genesis when they are not would be a claim
    // the bench does not check.
    const uint32_t midstate[8] = {0x14a1f4d4u, 0x2a1bcd0cu, 0x0e2c6c6au, 0x6b4d7e78u,
                                  0x6a0d0b47u, 0x8a4c4f1eu, 0xd1f2a5c7u, 0x0be3a6e2u};
    const uint32_t tail[3] = {0x4b1e5e4au, 0x29ab5f49u, 0xffff001du};

    std::printf("================================================================\n");
    std::printf("  Is the funnel visible from inside it\n");
    std::printf("================================================================\n");
    std::printf("\n  The round is a bijection and every mixing function has full rank, so the\n");
    std::printf("  reachable set never narrows and there is no funnel in the counting sense. The\n");
    std::printf("  question that is left is whether one is visible from inside: does the state at\n");
    std::printf("  round r say anything about how the digest ends?\n");
    std::printf("\n  If it does, a nonce can be refused at round r instead of at round 128 and the\n");
    std::printf("  cost of mining falls by the rounds skipped. Every one of the 256 state bits is\n");
    std::printf("  scored separately, so anything a simple early-reject rule could use has to show\n");
    std::printf("  up here as a bias on at least one bit.\n");
    std::printf("\n  Winner means the digest's top %u bits are zero, which is far weaker than a\n",
                WINNING_ZEROS);
    std::printf("  share and is what makes the question answerable at this sample size.\n");
    std::printf("\n  Walking 2^%u nonces per watched round.\n", nonce_bits);

    uint32_t *device_midstate = nullptr;
    uint32_t *device_tail = nullptr;
    unsigned long long *device_all = nullptr;
    unsigned long long *device_win = nullptr;
    unsigned long long *device_winners = nullptr;
    unsigned long long *device_walked = nullptr;
    cudaMalloc((void **)&device_midstate, 8u * sizeof(uint32_t));
    cudaMalloc((void **)&device_tail, 3u * sizeof(uint32_t));
    cudaMalloc((void **)&device_all, 256u * sizeof(unsigned long long));
    cudaMalloc((void **)&device_win, 256u * sizeof(unsigned long long));
    cudaMalloc((void **)&device_winners, sizeof(unsigned long long));
    cudaMalloc((void **)&device_walked, sizeof(unsigned long long));

    // Room for the photographs themselves, so pairs can be scored on the host. Updating a counter
    // per pair on the device would be thirty-two thousand atomics per winner; carrying the states
    // back is a few megabytes and lets every pair be scored exactly once.
    const unsigned KEEP_LIMIT = 40000u;
    uint32_t *device_winner_photos = nullptr;
    uint32_t *device_control_photos = nullptr;
    unsigned *device_kept_winners = nullptr;
    unsigned *device_kept_control = nullptr;
    cudaMalloc((void **)&device_winner_photos, (size_t)KEEP_LIMIT * 8u * sizeof(uint32_t));
    cudaMalloc((void **)&device_control_photos, (size_t)KEEP_LIMIT * 8u * sizeof(uint32_t));
    cudaMalloc((void **)&device_kept_winners, sizeof(unsigned));
    cudaMalloc((void **)&device_kept_control, sizeof(unsigned));

    std::vector<uint32_t> winner_photos((size_t)KEEP_LIMIT * 8u);
    std::vector<uint32_t> control_photos((size_t)KEEP_LIMIT * 8u);
    cudaMemcpy(device_midstate, midstate, sizeof(midstate), cudaMemcpyHostToDevice);
    cudaMemcpy(device_tail, tail, sizeof(tail), cudaMemcpyHostToDevice);

    std::printf("\n  %8s %12s %14s %14s %12s\n", "round", "winners", "strongest bit", "expected max",
                "verdict");
    std::printf("  %8s %12s %14s %14s %12s\n", "--------", "------------", "--------------",
                "--------------", "------------");

    const unsigned WATCHED = 5u;
    const unsigned watch_at[WATCHED] = {8u, 16u, 32u, 48u, 56u};

    for (unsigned which = 0u; which < WATCHED; which += 1u)
    {
        cudaMemset(device_all, 0, 256u * sizeof(unsigned long long));
        cudaMemset(device_win, 0, 256u * sizeof(unsigned long long));
        cudaMemset(device_winners, 0, sizeof(unsigned long long));
        cudaMemset(device_walked, 0, sizeof(unsigned long long));

        cudaMemset(device_kept_winners, 0, sizeof(unsigned));
        cudaMemset(device_kept_control, 0, sizeof(unsigned));

        look_for_the_trap<<<2048, 128>>>(device_midstate, device_tail, nonces, watch_at[which],
                                         device_all, device_win, device_winners, device_walked,
                                         device_winner_photos, device_control_photos,
                                         device_kept_winners, device_kept_control, KEEP_LIMIT);
        cudaDeviceSynchronize();

        unsigned long long ones_all[256];
        unsigned long long ones_win[256];
        unsigned long long winners = 0u;
        unsigned long long walked = 0u;
        cudaMemcpy(ones_all, device_all, sizeof(ones_all), cudaMemcpyDeviceToHost);
        cudaMemcpy(ones_win, device_win, sizeof(ones_win), cudaMemcpyDeviceToHost);
        cudaMemcpy(&winners, device_winners, sizeof(winners), cudaMemcpyDeviceToHost);
        cudaMemcpy(&walked, device_walked, sizeof(walked), cudaMemcpyDeviceToHost);

        // Each bit is a two-proportion test: how often it was one among winners, against how often
        // among everything. A rule that rejects early needs at least one bit where those differ.
        double strongest = 0.0;
        unsigned strongest_bit = 0u;
        if ((winners > 0u) && (walked > 0u))
        {
            for (unsigned at = 0u; at < 256u; at += 1u)
            {
                const double overall = (double)ones_all[at] / (double)walked;
                const double among = (double)ones_win[at] / (double)winners;
                const double spread = std::sqrt((overall * (1.0 - overall)) / (double)winners);
                if (spread <= 0.0)
                {
                    continue;
                }
                const double score = (among - overall) / spread;
                const double size = (score < 0.0) ? -score : score;
                if (size > strongest)
                {
                    strongest = size;
                    strongest_bit = at;
                }
            }
        }

        // The largest of 256 draws from a standard normal sits near 2.9, so that is the figure the
        // strongest bit has to beat before it means anything.
        const double expected_max = 2.89;
        const char *verdict = (strongest > (expected_max + 1.5)) ? "SIGNAL" : "nothing";
        std::printf("  %8u %12llu %8.2f (b%3u) %14.2f %12s\n", watch_at[which], winners, strongest,
                    strongest_bit, expected_max, verdict);

        // Pairs, which is where contamination would show if it crossed a boundary instead of
        // sitting on one bit. Two positions that separately look ordinary can carry the outcome
        // jointly, and a per-bit test is blind to exactly that.
        unsigned kept_win = 0u;
        unsigned kept_con = 0u;
        cudaMemcpy(&kept_win, device_kept_winners, sizeof(kept_win), cudaMemcpyDeviceToHost);
        cudaMemcpy(&kept_con, device_kept_control, sizeof(kept_con), cudaMemcpyDeviceToHost);
        kept_win = (kept_win < KEEP_LIMIT) ? kept_win : KEEP_LIMIT;
        kept_con = (kept_con < KEEP_LIMIT) ? kept_con : KEEP_LIMIT;

        if ((kept_win > 200u) && (kept_con > 200u))
        {
            cudaMemcpy(winner_photos.data(), device_winner_photos,
                       (size_t)kept_win * 8u * sizeof(uint32_t), cudaMemcpyDeviceToHost);
            cudaMemcpy(control_photos.data(), device_control_photos,
                       (size_t)kept_con * 8u * sizeof(uint32_t), cudaMemcpyDeviceToHost);

            double loudest_pair = 0.0;
            unsigned loud_left = 0u;
            unsigned loud_right = 0u;

            for (unsigned left = 0u; left < 256u; left += 1u)
            {
                for (unsigned right = left + 1u; right < 256u; right += 1u)
                {
                    unsigned won_ones = 0u;
                    for (unsigned at = 0u; at < kept_win; at += 1u)
                    {
                        const uint32_t *photo = &winner_photos[(size_t)at * 8u];
                        const unsigned one = (photo[left / 32u] >> (left % 32u)) & 1u;
                        const unsigned two = (photo[right / 32u] >> (right % 32u)) & 1u;
                        won_ones += (one ^ two);
                    }
                    unsigned con_ones = 0u;
                    for (unsigned at = 0u; at < kept_con; at += 1u)
                    {
                        const uint32_t *photo = &control_photos[(size_t)at * 8u];
                        const unsigned one = (photo[left / 32u] >> (left % 32u)) & 1u;
                        const unsigned two = (photo[right / 32u] >> (right % 32u)) & 1u;
                        con_ones += (one ^ two);
                    }

                    const double won_rate = (double)won_ones / (double)kept_win;
                    const double con_rate = (double)con_ones / (double)kept_con;
                    const double spread =
                        std::sqrt((0.25 / (double)kept_win) + (0.25 / (double)kept_con));
                    if (spread <= 0.0)
                    {
                        continue;
                    }
                    const double score = (won_rate - con_rate) / spread;
                    const double size = (score < 0.0) ? -score : score;
                    if (size > loudest_pair)
                    {
                        loudest_pair = size;
                        loud_left = left;
                        loud_right = right;
                    }
                }
            }

            // Detection reach for the largest of N draws is sqrt(2 ln N), which this tree uses
            // elsewhere. There are 32640 pairs, so the null peaks near 4.56 whatever is or is not
            // there.
            const double pair_null = std::sqrt(2.0 * std::log(32640.0));
            const char *pair_verdict = (loudest_pair > (pair_null + 1.5)) ? "SIGNAL" : "nothing";
            std::printf("  %8s %5u/%-6u %8.2f (%3u^%3u) %10.2f %12s\n", "  pairs", kept_win,
                        kept_con, loudest_pair, loud_left, loud_right, pair_null, pair_verdict);
        }
    }

    // ---------------------------------------------------------------------------------------
    // Which nonces win.
    //
    // The same question aimed at the input instead of the middle. If a nonce carrying few bits wins
    // more often than one carrying many, the search order is not arbitrary and the cheap nonces
    // should be tried first - which is the scarcity argument, applied where it would actually pay.
    //
    // The totals are exact instead of measured: half the nonce space carries any given bit and
    // C(32,w) of it has weight w. Only winners need counting, and a measured count against an exact
    // total is a stronger test than two measured counts against each other.
    // ---------------------------------------------------------------------------------------
    std::printf("\n================================================================\n");
    std::printf("  Which nonces win\n");
    std::printf("================================================================\n");
    std::printf("\n  If a nonce carrying few bits wins more often than one carrying many, the cheap\n");
    std::printf("  nonces should be searched first. The totals here are exact instead of measured:\n");
    std::printf("  half the space carries any given bit, and C(32,w) of it has weight w.\n");

    {
        unsigned long long *device_by_bit = nullptr;
        unsigned long long *device_by_weight = nullptr;
        unsigned long long *device_won = nullptr;
        cudaMalloc((void **)&device_by_bit, 32u * sizeof(unsigned long long));
        cudaMalloc((void **)&device_by_weight, 33u * sizeof(unsigned long long));
        cudaMalloc((void **)&device_won, sizeof(unsigned long long));
        cudaMemset(device_by_bit, 0, 32u * sizeof(unsigned long long));
        cudaMemset(device_by_weight, 0, 33u * sizeof(unsigned long long));
        cudaMemset(device_won, 0, sizeof(unsigned long long));

        // The whole space, always, whatever the sample size used above. A partial sweep leaves the
        // high bits unrepresented and every expectation here is computed over the full 2^32.
        const uint64_t whole_space = (uint64_t)1u << 32;
        which_nonces_win<<<4096, 128>>>(device_midstate, device_tail, whole_space, device_by_bit,
                                        device_by_weight, device_won);
        cudaDeviceSynchronize();

        unsigned long long by_bit[32];
        unsigned long long by_weight[33];
        unsigned long long won = 0u;
        cudaMemcpy(by_bit, device_by_bit, sizeof(by_bit), cudaMemcpyDeviceToHost);
        cudaMemcpy(by_weight, device_by_weight, sizeof(by_weight), cudaMemcpyDeviceToHost);
        cudaMemcpy(&won, device_won, sizeof(won), cudaMemcpyDeviceToHost);

        std::printf("\n  %llu winners over the whole 2^32 nonce space, exhaustively.\n", won);

        // Each nonce bit is carried by half the space, so half the winners should carry it too.
        double loudest_bit = 0.0;
        unsigned loud_bit = 0u;
        for (unsigned bit = 0u; bit < 32u; bit += 1u)
        {
            const double expected = (double)won / 2.0;
            const double spread = std::sqrt((double)won * 0.25);
            if (spread <= 0.0)
            {
                continue;
            }
            const double score = ((double)by_bit[bit] - expected) / spread;
            const double size = (score < 0.0) ? -score : score;
            if (size > loudest_bit)
            {
                loudest_bit = size;
                loud_bit = bit;
            }
        }

        // Weight w holds C(32,w) of the space, so it should hold that fraction of the winners.
        double loudest_weight = 0.0;
        unsigned loud_weight = 0u;
        double choose = 1.0;
        for (unsigned weight = 0u; weight <= 32u; weight += 1u)
        {
            if (weight > 0u)
            {
                choose = (choose * (double)(33u - weight)) / (double)weight;
            }
            const double share = choose / 4294967296.0;
            const double expected = (double)won * share;
            if (expected < 30.0)
            {
                continue;
            }
            const double spread = std::sqrt(expected * (1.0 - share));
            const double score = ((double)by_weight[weight] - expected) / spread;
            const double size = (score < 0.0) ? -score : score;
            if (size > loudest_weight)
            {
                loudest_weight = size;
                loud_weight = weight;
            }
        }

        const double bit_null = std::sqrt(2.0 * std::log(32.0));
        const double weight_null = std::sqrt(2.0 * std::log(33.0));
        std::printf("\n  %-34s %10s %10s %12s\n", "what", "loudest", "null peak", "verdict");
        std::printf("  %-34s %10s %10s %12s\n", "----------------------------------", "----------",
                    "----------", "------------");
        std::printf("  %-34s %8.2f (b%2u) %10.2f %12s\n", "winners carrying each nonce bit",
                    loudest_bit, loud_bit, bit_null,
                    (loudest_bit > (bit_null + 1.5)) ? "SIGNAL" : "nothing");
        std::printf("  %-34s %8.2f (w%2u) %10.2f %12s\n", "winners at each nonce weight",
                    loudest_weight, loud_weight, weight_null,
                    (loudest_weight > (weight_null + 1.5)) ? "SIGNAL" : "nothing");

        cudaFree(device_by_bit);
        cudaFree(device_by_weight);
        cudaFree(device_won);

        std::printf("\n  A signal in either row would mean the nonce space is not flat and the\n");
        std::printf("  search order matters. Nothing in both means every nonce is equally likely to\n");
        std::printf("  win whatever it looks like, and enumeration order is free.\n");
    }

    cudaFree(device_midstate);
    cudaFree(device_tail);
    cudaFree(device_all);
    cudaFree(device_win);
    cudaFree(device_winners);
    cudaFree(device_walked);

    std::printf("\n  The strongest of 256 bits is a maximum, and the largest of 256 standard normal\n");
    std::printf("  draws sits near 2.89 whether or not anything is there, so a column reading near\n");
    std::printf("  three is the null and not a weak signal. Only a reading well clear of it would\n");
    std::printf("  be a funnel visible from inside, and it would mean a nonce could be refused at\n");
    std::printf("  that round instead of at the end.\n");
    return 0;
}
