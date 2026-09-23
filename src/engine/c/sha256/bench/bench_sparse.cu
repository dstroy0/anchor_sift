/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_sparse.cu
 * @brief How sparse a nonce difference stays in a real header, walked across many nonces.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note bench_space measured this with sixteen random schedule words and found a one-bit difference
 *       surviving to W27 for the right header. A real mining block is not sixteen random words. The
 *       header tail block carries four words of header, then 0x80000000, then ten zero words, then
 *       the length - so ten of its sixteen inputs are zero and one more is a constant. Whether the
 *       sparse path exists there is a different question and this asks it.
 * @note The headers are the tree's own known-answer vectors, whose hashes and nonces the chain
 *       already recorded, so the block being walked is a block that really was solved instead of a
 *       plausible-looking one.
 * @note Sparsity here is the total Hamming weight of the expanded difference across all sixty-four
 *       schedule words, which is what a message-schedule differential costs an attacker. Lower is
 *       an easier path. The minimum over nonces is the honest figure because the expansion adds
 *       instead of exclusive-ors, so what a flip produces depends on the nonce it is flipped in.
 */

#include <cuda_runtime.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>

namespace
{

/** @brief Words in a message block. */
const unsigned BLOCK_WORDS = 16u;

/** @brief The word the nonce occupies in the header tail block. */
const unsigned NONCE_WORD = 3u;

/** @brief Expands sixteen words to sixty-four by the standard's rule. */
__device__ __forceinline__ void expand(uint32_t *schedule)
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
 * @brief Walks nonces and bit positions, recording how sparse each difference stays.
 *
 * @param[in]     base     The sixteen words of the block, nonce slot ignored [BORROWS].
 * @param[in]     nonces   How many nonces to walk.
 * @param[in]     start    First nonce.
 * @param[out]    lightest Smallest total difference weight seen [BORROWS].
 * @param[out]    deepest  Deepest word still at two bits or fewer [BORROWS].
 * @param[in,out] total    Accumulates total weight, for the mean [BORROWS].
 * @param[in,out] counted  Accumulates how many pairs were walked [BORROWS].
 * @param[out]    at_word  Per-word smallest weight, sixty-four of them [BORROWS].
 * @note One thread per nonce and bit position. Both members of a pair share every word but the
 *       nonce, which is the difference a miner actually steps through.
 */
__global__ void walk_sparse(const uint32_t *base, uint32_t nonces, uint32_t start,
                            unsigned *lightest, unsigned *deepest, unsigned long long *total,
                            unsigned long long *counted, unsigned *at_word, unsigned carries_in)
{
    const uint64_t span = (uint64_t)nonces * 32ull;
    const uint64_t stride = (uint64_t)gridDim.x * blockDim.x;

    for (uint64_t at = (uint64_t)blockIdx.x * blockDim.x + threadIdx.x; at < span; at += stride)
    {
        const uint32_t nonce = start + (uint32_t)(at / 32ull);
        const unsigned bit = (unsigned)(at % 32ull);

        uint32_t left[64];
        uint32_t right[64];
        for (unsigned slot = 0u; slot < BLOCK_WORDS; slot += 1u)
        {
            left[slot] = base[slot];
            right[slot] = base[slot];
        }
        // Which word carries the difference is a parameter instead of always the nonce. A miner
        // rolls the extranonce, which moves the merkle root and so word zero, and rolls the time,
        // which moves word one. Those are difference positions a miner really has and only word
        // three had ever been tested.
        left[carries_in] = nonce;
        right[carries_in] = nonce ^ ((uint32_t)1u << bit);

        expand(left);
        expand(right);

        unsigned weight = 0u;
        unsigned reach = 0u;
        for (unsigned slot = 0u; slot < 64u; slot += 1u)
        {
            const unsigned here = (unsigned)__popc(left[slot] ^ right[slot]);
            weight += here;
            if ((here > 0u) && (here <= 2u))
            {
                reach = slot;
            }

            // A count, not a minimum. The smallest weight seen is a tail statistic and grows more
            // extreme with the sample whether or not anything is there: at 2^25 pairs chance alone
            // delivers a one-bit word about a quarter of the time, so a minimum of one says nothing.
            // A rate can be held against the rate chance gives and the two separated.
            // Exactly one, not at most one. A word the nonce never reaches weighs zero, and
            // counting those reports every untainted word as a perfect path.
            if (here == 1u)
            {
                atomicAdd(&at_word[slot], 1u);
            }
        }

        atomicMin(lightest, weight);
        atomicMax(deepest, reach);
        atomicAdd(total, (unsigned long long)weight);
        atomicAdd(counted, 1ull);
    }
}

/** @brief A block whose header and nonce the chain already recorded. */
struct Vector
{
    const char *header_hex;
    uint32_t nonce;
    const char *source;
};

/** @brief The tree's own known-answer headers, from src/engine/c/sha256/test/kat_validation.cpp. */
const Vector VECTORS[2] = {
    {"0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac7"
     "2c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c",
     0x7c2bac1du, "genesis, height 0"},
    {"0100000081cd02ab7e569e8bcd9317e2fe99f2de44d49ab2b8851ba4a308000000000000e320b6c2fffc8d750423"
     "db8b1eb942ae710e951ed797f7affc8892b0f1fc122bc7f5d74df2b9441a42a14695",
     0x9546a142u, "block 125552"}};

/**
 * @brief Fills the header tail block the way the miner does.
 *
 * @param[out] block      Sixteen words [BORROWS].
 * @param[in]  header_hex The eighty-byte header as hex.
 * @note Bytes sixty-four through seventy-nine of the header, then the padding: 0x80000000, ten zero
 *       words, and the length in bits. Ten of the sixteen inputs are zero and one more is a
 *       constant, which is the whole reason this is not the same experiment as sixteen random
 *       words.
 */
void fill_block(uint32_t *block, const char *header_hex)
{
    for (unsigned slot = 0u; slot < 4u; slot += 1u)
    {
        uint32_t word = 0u;
        for (unsigned byte_at = 0u; byte_at < 4u; byte_at += 1u)
        {
            const unsigned offset = ((64u + (slot * 4u) + byte_at) * 2u);
            char pair[3] = {header_hex[offset], header_hex[offset + 1u], '\0'};
            word = (word << 8) | (uint32_t)std::strtoul(pair, nullptr, 16);
        }
        block[slot] = word;
    }
    block[4] = 0x80000000u;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        block[slot] = 0u;
    }
    block[15] = 640u;
}

/** @brief The schedule's own mixing functions, on the host, for the exact trace. */
uint32_t small_sigma_zero(uint32_t value)
{
    return ((value >> 7) | (value << 25)) ^ ((value >> 18) | (value << 14)) ^ (value >> 3);
}

/** @brief The other one. */
uint32_t small_sigma_one(uint32_t value)
{
    return ((value >> 17) | (value << 15)) ^ ((value >> 19) | (value << 13)) ^ (value >> 10);
}

/**
 * @brief The difference the schedule carries when no carry ever fires, exactly.
 *
 * @param[in]  from   Which of the sixteen input words carries the difference.
 * @param[in]  bit    Which bit of it is flipped.
 * @param[out] weight Weight at each of the sixty-four words [BORROWS].
 * @note Addition is replaced by exclusive-or, which is the standard linearisation and is exact
 *       whenever no carry propagates. What it gives is the floor: a word whose linearised weight is
 *       w cannot come out below w except by a carry cancelling something, so a word with linearised
 *       weight one carries a genuine path and a word with linearised weight nine reaching one is a
 *       coincidence of carries and costs whatever that coincidence costs.
 * @note This is why sampling was the wrong tool for the question. The trace is thirty-two words of
 *       arithmetic and needs no pairs at all.
 */
void trace_linear(unsigned from, unsigned bit, unsigned *weight, int *tainted)
{
    // Whether a word depends on the input at all is a separate fact from what its linearised
    // difference weighs, and conflating them reports a word whose GF(2) terms cancel as a word the
    // difference never reaches. W25 from a merkle difference is exactly that case: 25-7 and 25-2
    // are both tainted, the contributions cancel to zero over GF(2), and the real word still
    // differs because the carries do not cancel with them.
    int reaches[64];
    for (unsigned at = 0u; at < 16u; at += 1u)
    {
        reaches[at] = (at == from) ? 1 : 0;
    }
    for (unsigned at = 16u; at < 64u; at += 1u)
    {
        reaches[at] = (reaches[at - 16u] | reaches[at - 15u] | reaches[at - 7u] |
                       reaches[at - 2u]);
    }
    for (unsigned at = 0u; at < 64u; at += 1u)
    {
        tainted[at] = reaches[at];
    }

    uint32_t difference[64];
    for (unsigned at = 0u; at < 16u; at += 1u)
    {
        difference[at] = 0u;
    }
    difference[from] = (uint32_t)1u << bit;

    for (unsigned at = 16u; at < 64u; at += 1u)
    {
        difference[at] = difference[at - 16u] ^ small_sigma_zero(difference[at - 15u]) ^
                         difference[at - 7u] ^ small_sigma_one(difference[at - 2u]);
    }
    // Counted by hand instead of by a builtin, because this half runs on the host and MSVC has no
    // __builtin_popcount.
    for (unsigned at = 0u; at < 64u; at += 1u)
    {
        unsigned counted_bits = 0u;
        uint32_t remaining = difference[at];
        while (remaining != 0u)
        {
            counted_bits += 1u;
            remaining &= remaining - 1u;
        }
        weight[at] = counted_bits;
    }
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned nonce_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 20u;
    const uint32_t nonces = (uint32_t)1u << nonce_bits;

    std::printf("================================================================\n");
    std::printf("  How sparse a nonce difference stays in a real header\n");
    std::printf("================================================================\n");
    std::printf("\n  bench_space asked this with sixteen random schedule words and found a one-bit\n");
    std::printf("  difference surviving to W27. A real mining block is not sixteen random words:\n");
    std::printf("  four words of header, then 0x80000000, ten zero words, and the length. Ten of\n");
    std::printf("  sixteen inputs are zero and one more is a constant.\n");
    std::printf("\n  The headers are the tree's own known-answer vectors, so these are blocks that\n");
    std::printf("  really were solved. Sparsity is the total weight of the expanded difference over\n");
    std::printf("  all sixty-four words, which is what a schedule differential costs.\n");
    std::printf("\n  Walking 2^%u nonces by 32 bit positions each.\n", nonce_bits);

    // The exact trace first, because it costs nothing and it decides what the sampling below can
    // possibly mean. A word whose linearised weight is one carries a real path; a word whose
    // linearised weight is nine reaching one is carries cancelling and costs what that costs.
    std::printf("\n================================================================\n");
    std::printf("  The path with no carries, traced exactly\n");
    std::printf("================================================================\n");
    std::printf("\n  Addition replaced by exclusive-or, which is exact whenever no carry fires. A\n");
    std::printf("  word cannot come out below its linearised weight except by a carry cancelling\n");
    std::printf("  something, so this is the floor and it needs no pairs at all.\n");
    std::printf("\n  Smallest linearised weight over the 32 input bits, by difference position.\n");

    std::printf("\n  %6s %14s %14s %14s %14s\n", "word", "in W0 (merkle)", "in W1 (time)",
                "in W2 (nbits)", "in W3 (nonce)");
    std::printf("  %6s %14s %14s %14s %14s\n", "------", "--------------", "--------------",
                "--------------", "--------------");

    unsigned floor_at[4][64];
    int reached[4][64];
    for (unsigned from = 0u; from < 4u; from += 1u)
    {
        for (unsigned at = 0u; at < 64u; at += 1u)
        {
            floor_at[from][at] = 33u;
            reached[from][at] = 0;
        }
        for (unsigned bit = 0u; bit < 32u; bit += 1u)
        {
            unsigned weight[64];
            int tainted[64];
            trace_linear(from, bit, weight, tainted);
            for (unsigned at = 0u; at < 64u; at += 1u)
            {
                reached[from][at] |= tainted[at];
                if ((weight[at] > 0u) && (weight[at] < floor_at[from][at]))
                {
                    floor_at[from][at] = weight[at];
                }
            }
        }
    }

    for (unsigned at = 16u; at < 40u; at += 1u)
    {
        std::printf("  %6u", at);
        for (unsigned from = 0u; from < 4u; from += 1u)
        {
            if (reached[from][at] == 0)
            {
                std::printf(" %14s", "untouched");
            }
            else if (floor_at[from][at] == 33u)
            {
                // Reached, but every one of the thirty-two input bits cancels to zero over GF(2).
                // The real word still differs, through the carries the linearisation drops.
                std::printf(" %14s", "cancels");
            }
            else
            {
                std::printf(" %14u", floor_at[from][at]);
            }
        }
        std::printf("\n");
    }

    std::printf("\n  A one in this table is a word that carries a genuine one-bit path. Anything\n");
    std::printf("  larger reaching one bit in the sampled table below is carries cancelling, and\n");
    std::printf("  the two must not be read as the same finding.\n");

    uint32_t *device_base = nullptr;
    unsigned *device_lightest = nullptr;
    unsigned *device_deepest = nullptr;
    unsigned long long *device_total = nullptr;
    unsigned long long *device_counted = nullptr;
    unsigned *device_at_word = nullptr;
    cudaMalloc((void **)&device_base, BLOCK_WORDS * sizeof(uint32_t));
    cudaMalloc((void **)&device_lightest, sizeof(unsigned));
    cudaMalloc((void **)&device_deepest, sizeof(unsigned));
    cudaMalloc((void **)&device_total, sizeof(unsigned long long));
    cudaMalloc((void **)&device_counted, sizeof(unsigned long long));
    cudaMalloc((void **)&device_at_word, 64u * sizeof(unsigned));

    std::printf("\n  %-26s %10s %10s %10s %12s\n", "block", "min bits", "mean bits", "deepest",
                "at nonce");
    std::printf("  %-26s %10s %10s %10s %12s\n", "--------------------------", "----------",
                "----------", "----------", "------------");

    unsigned per_word[3][64];

    for (unsigned which = 0u; which < 3u; which += 1u)
    {
        uint32_t block[BLOCK_WORDS];
        const char *label = nullptr;
        uint32_t start = 0u;

        if (which < 2u)
        {
            fill_block(block, VECTORS[which].header_hex);
            label = VECTORS[which].source;

            // Start below the recorded nonce so the walk crosses it instead of beginning on it.
            start = VECTORS[which].nonce - (nonces / 2u);
        }
        else
        {
            // The same padded shape with header words that are not a real block, so a difference
            // between this row and the two above is the particular header instead of the shape.
            fill_block(block, VECTORS[0].header_hex);
            block[0] = 0x12345678u;
            block[1] = 0x9abcdef0u;
            block[2] = 0x0f1e2d3cu;
            label = "padded shape, invented header";
            start = 0u;
        }

        cudaMemcpy(device_base, block, sizeof(block), cudaMemcpyHostToDevice);
        cudaMemset(device_lightest, 0xff, sizeof(unsigned));
        cudaMemset(device_deepest, 0, sizeof(unsigned));
        cudaMemset(device_total, 0, sizeof(unsigned long long));
        cudaMemset(device_counted, 0, sizeof(unsigned long long));
        cudaMemset(device_at_word, 0, 64u * sizeof(unsigned));

        walk_sparse<<<4096, 128>>>(device_base, nonces, start, device_lightest, device_deepest,
                                   device_total, device_counted, device_at_word, NONCE_WORD);
        cudaDeviceSynchronize();

        unsigned lightest = 0u;
        unsigned deepest = 0u;
        unsigned long long total = 0u;
        unsigned long long counted = 0u;
        cudaMemcpy(&lightest, device_lightest, sizeof(lightest), cudaMemcpyDeviceToHost);
        cudaMemcpy(&deepest, device_deepest, sizeof(deepest), cudaMemcpyDeviceToHost);
        cudaMemcpy(&total, device_total, sizeof(total), cudaMemcpyDeviceToHost);
        cudaMemcpy(&counted, device_counted, sizeof(counted), cudaMemcpyDeviceToHost);
        cudaMemcpy(per_word[which], device_at_word, 64u * sizeof(unsigned),
                   cudaMemcpyDeviceToHost);

        char where[16];
        if (which < 2u)
        {
            std::snprintf(where, sizeof(where), "%u", VECTORS[which].nonce);
        }
        else
        {
            std::snprintf(where, sizeof(where), "%s", "-");
        }
        std::printf("  %-26s %10u %10.1f %10u %12s\n", label, lightest,
                    (counted > 0u) ? ((double)total / (double)counted) : 0.0, deepest, where);
    }

    // The trace is exact, so it predicts instead of describing: a word it floors at one should show
    // a large count below, and a word it floors at two should show a small one or none. Checking
    // that is the difference between a law and a story, and it is the same discipline that caught
    // the minimum-versus-rate error one section up.
    std::printf("\n================================================================\n");
    std::printf("  The trace against the sampling, on genesis\n");
    std::printf("================================================================\n");
    std::printf("\n  A word the trace floors at one carries a real path and should show a large\n");
    std::printf("  count. A word it floors at two can only reach one bit by a carry cancelling,\n");
    std::printf("  and should show few or none. A disagreement means one of the two is wrong.\n");

    {
        uint32_t block[BLOCK_WORDS];
        fill_block(block, VECTORS[0].header_hex);
        cudaMemcpy(device_base, block, sizeof(block), cudaMemcpyHostToDevice);

        std::printf("\n  %-14s %8s %10s %14s %12s\n", "difference in", "word", "trace", "counted",
                    "agrees");
        std::printf("  %-14s %8s %10s %14s %12s\n", "--------------", "--------", "----------",
                    "--------------", "------------");

        const char *named[4] = {"W0 merkle", "W1 time", "W2 nbits", "W3 nonce"};
        for (unsigned from = 0u; from < 4u; from += 1u)
        {
            cudaMemset(device_lightest, 0xff, sizeof(unsigned));
            cudaMemset(device_deepest, 0, sizeof(unsigned));
            cudaMemset(device_total, 0, sizeof(unsigned long long));
            cudaMemset(device_counted, 0, sizeof(unsigned long long));
            cudaMemset(device_at_word, 0, 64u * sizeof(unsigned));

            walk_sparse<<<4096, 128>>>(device_base, nonces, 0u, device_lightest, device_deepest,
                                       device_total, device_counted, device_at_word, from);
            cudaDeviceSynchronize();

            unsigned counts[64];
            cudaMemcpy(counts, device_at_word, sizeof(counts), cudaMemcpyDeviceToHost);

            for (unsigned at = 16u; at < 40u; at += 1u)
            {
                const unsigned floored = floor_at[from][at];
                if ((floored != 1u) && (counts[at] == 0u))
                {
                    continue;
                }

                // A floor of one should be common and anything else should be rare. Rare is judged
                // against the whole sweep instead of a fixed number, since the sweep size is an
                // argument.
                const double many = (double)nonces * 32.0;
                const int is_common = ((double)counts[at] > (many * 0.001)) ? 1 : 0;

                // What the floor does and does not predict, stated so the verdict is not a threshold
                // picked to make rows agree:
                //
                //   floor 1    a carry-free chain reaches one bit. Common or rare depending on how
                //              long that chain is, since every addition on it must not carry.
                //   cancels    the GF(2) terms sum to zero, so the real difference is nothing but
                //              carries - and a carry-only difference is often a single bit. These
                //              are among the sparsest words in practice, not the emptiest.
                //   floor 2    one carry must cancel one bit. Uncommon but reachable.
                //   floor 3+   two or more bits must cancel. Effectively never.
                //
                // So only a floor of three or more appearing often is a contradiction.
                const int agrees = ((floored < 3u) || (floored == 33u) || (is_common == 0)) ? 1 : 0;

                char trace_text[16];
                if (reached[from][at] == 0)
                {
                    std::snprintf(trace_text, sizeof(trace_text), "%s", "untouched");
                }
                else if (floored == 33u)
                {
                    std::snprintf(trace_text, sizeof(trace_text), "%s", "cancels");
                }
                else
                {
                    std::snprintf(trace_text, sizeof(trace_text), "%u", floored);
                }
                std::printf("  %-14s %8u %10s %14u %12s\n", named[from], at, trace_text, counts[at],
                            (agrees != 0) ? "yes" : "NO");
            }
        }

        std::printf("\n  Every row agreeing means the trace is the law and the sampling was only\n");
        std::printf("  ever reading it through carries. The deepest one-bit path a miner can reach\n");
        std::printf("  is then a fact about which header word is moved, not about how many nonces\n");
        std::printf("  are tried.\n");
    }

    cudaFree(device_base);
    cudaFree(device_lightest);
    cudaFree(device_deepest);
    cudaFree(device_total);
    cudaFree(device_counted);
    cudaFree(device_at_word);

    // The per-word minimum is where bench_space read W27, so the same column is printed here for
    // the real blocks. A real header holding sparsity deeper than random words did would mean the
    // padding is helping the difference stay thin instead of hindering it.
    // How often a word comes out at one bit or fewer, against how often chance alone delivers it.
    // Thirty-three of the 2^32 differences a word can carry have weight zero or one, so the rate to
    // beat is 33/2^32 and a word matching it is carrying no path at all.
    const double pairs = (double)nonces * 32.0;
    const double by_chance = pairs * (33.0 / 4294967296.0);

    std::printf("\n  How often each word comes out at one bit or fewer\n");
    std::printf("\n  Pairs per word: %.0f. Chance alone gives %.3f such words, since 33 of the\n",
                pairs, by_chance);
    std::printf("  2^32 possible differences weigh zero or one. A count near that is no path; a\n");
    std::printf("  count far above it is a difference the schedule is carrying instead of mixing.\n");
    std::printf("\n  Only words beating chance by tenfold are listed, plus every word up to 27.\n");

    std::printf("\n  %6s %14s %14s %14s %12s\n", "word", "genesis", "125552", "invented",
                "vs chance");
    std::printf("  %6s %14s %14s %14s %12s\n", "------", "--------------", "--------------",
                "--------------", "------------");
    for (unsigned at = 0u; at < 64u; at += 1u)
    {
        const unsigned most = (per_word[0][at] > per_word[1][at]) ? per_word[0][at]
                                                                  : per_word[1][at];
        const unsigned highest = (most > per_word[2][at]) ? most : per_word[2][at];
        if ((at > 27u) && ((double)highest < (by_chance * 10.0)))
        {
            continue;
        }
        const double ratio = (by_chance > 0.0) ? ((double)highest / by_chance) : 0.0;
        std::printf("  %6u %14u %14u %14u %12.1fx\n", at, per_word[0][at], per_word[1][at],
                    per_word[2][at], ratio);
    }

    std::printf("\n  bench_space read one bit through W27 with sixteen random words, at 131072\n");
    std::printf("  pairs per word where chance gives 0.001 - so those were real. This asks the\n");
    std::printf("  same question of a real block at a sample where chance gives a quarter, which\n");
    std::printf("  is why it counts instead of minimising. A word only carries a path where its\n");
    std::printf("  count stands clear of the chance figure printed above.\n");
    return 0;
}
