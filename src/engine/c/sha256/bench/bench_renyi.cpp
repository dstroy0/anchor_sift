/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_renyi.cpp
 * @brief The Renyi order as an axis, swept over the whole nonce domain enumerated exhaustively.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Every entropy this workbook has reported so far was collision entropy, Renyi order two.
 *       That was never a decision. Order two is what a collision counter measures and a collision
 *       counter is what was to hand, so thirty-one hypotheses were graded on one point of a
 *       continuous family without the family ever being looked at.
 * @note The family is the axis. Renyi order alpha runs from zero to infinity and each end of it
 *       answers a different question about the same distribution:
 *
 *         alpha = 0     the size of the support, which counts the values that never occur
 *         alpha = 1/2   the cost of guessing, by Arikan's bound E[G] <= (2^H_{1/2} + 1) / 2
 *         alpha = 1     Shannon entropy
 *         alpha = 2     collision probability, and Bellare-Kohno balance is this one rescaled
 *         alpha = inf   the single most over-represented value
 *
 *       Holes sit at one end of that axis and bumps at the other, and everything this project has
 *       measured sits at one interior point of it.
 * @note Arikan's bound is the reason order one half is not optional. Search cost is governed by
 *       H_{1/2}, which weights many small probabilities instead of a few large ones, so it is the
 *       tail that sets the cost of guessing and order two is blind to exactly that. A workbook
 *       whose subject is the cost of finding a nonce has been reading the wrong order throughout.
 * @note The domain is enumerated, not sampled. Every one of the 2^32 nonces of one real header is
 *       hashed, whole SHA256d over all eighty bytes, and the whole 256-bit digest is read. A
 *       window is a readout of that digest and never a truncation of the computation.
 * @note For a random function the deficit is predicted in closed form. Writing the bin counts as
 *       c_i = m(1 + e_i) with m = d/r the exact mean, the deficit at order alpha is
 *
 *         w - H_alpha = alpha * variance(e) / (2 ln 2)     for m much greater than one
 *
 *       so the deficit profile of a random function is a straight line through the origin in
 *       alpha, of slope variance(e)/(2 ln 2) with variance(e) = (r-1)/d exactly. That predicts a
 *       ratio between orders with no free parameter at all: the order two deficit is four times
 *       the order one half deficit. Curvature in that line is structure.
 * @note Where m falls to one the linearisation stops applying and the counts go Poisson, whose
 *       moments about the mean are the Bell numbers. Both regimes appear here because the 32-bit
 *       windows over a 2^32 domain are exactly the Poisson case, and that is where the holes are.
 * @note Two controls run the identical pipeline. A digest built as the nonce repeated eight times
 *       makes every aligned window perfectly balanced, so every deficit it reports must be zero
 *       and any other answer is an estimator defect. A splitmix64 chain is a good pseudorandom
 *       function and must reproduce the predictions instead of zero. One control fails toward
 *       flat and the other toward random, so between them an estimator cannot be wrong quietly.
 * @warning Arithmetic here is written to be numerically stable instead of obvious, because the
 *          quantity of interest is a deficit of order 1e-5 bits sitting under a value of order 16.
 *          Every deficit is accumulated through log1p and expm1 on the deviation instead of by
 *          subtracting two large logarithms, and the compiler is told not to contract multiplies
 *          and adds into fused operations so that the arithmetic run is the arithmetic written.
 */

#include "bench_load_limit.h"
#include "sha256_core.h"

// Defined by the build that compiles the device arm alongside this one. Without it the file builds
// and runs exactly as before, host only, which keeps a machine without a device able to reproduce
// every number here.
#if BENCH_RENYI_HAS_CUDA
#include "bench_renyi_cuda.h"
#endif

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <thread>
#include <vector>

namespace
{

/** @brief Aligned byte windows over the 256-bit digest. */
const unsigned BYTE_WINDOWS = 32u;

/** @brief Aligned sixteen-bit windows over the 256-bit digest. */
const unsigned WORD_WINDOWS = 16u;

/** @brief Bins in a byte window. */
const unsigned BYTE_BINS = 256u;

/** @brief Bins in a sixteen-bit window. */
const unsigned WORD_BINS = 65536u;

/** @brief Digest bytes, which is also the number of byte windows. */
const unsigned DIGEST_BYTES = 32u;

/** @brief The padding word the standard appends after the message. */
const uint32_t PADDING_LEAD_WORD = 0x80000000u;

/** @brief Length of a block header in bits, as the final schedule word carries it. */
const uint32_t HEADER_LENGTH_BITS = 0x00000280u;

/** @brief Length of a digest in bits, as the second hash's final schedule word carries it. */
const uint32_t DIGEST_LENGTH_BITS = 0x00000100u;

/** @brief Which function fills the digest, so the estimator can be graded against known answers. */
enum Source
{
    SOURCE_SHA256D,  /**< The real thing: whole SHA256d over the whole header. */
    SOURCE_CONSTANT, /**< A fixed digest. One occupied bin per window at any domain size. */
    SOURCE_BALANCED, /**< The nonce repeated eight times. Every aligned window exactly balanced. */
    SOURCE_SPLITMIX  /**< A splitmix64 chain. A good pseudorandom function. */
};

/**
 * @brief Reverses the byte order of a word.
 *
 * @param[in] value Word to reverse.
 * @return          The reversed word.
 */
uint32_t reverse_word_bytes(uint32_t value)
{
    return ((value & 0x000000ffu) << 24) | ((value & 0x0000ff00u) << 8) |
           ((value & 0x00ff0000u) >> 8) | ((value & 0xff000000u) >> 24);
}

/**
 * @brief Advances a splitmix64 state and returns its output.
 *
 * @param[in,out] state Generator state [BORROWS].
 * @return              Sixty-four output bits.
 */
uint64_t splitmix64(uint64_t *state)
{
    *state += 0x9e3779b97f4a7c15ull;
    uint64_t mixed = *state;
    mixed = (mixed ^ (mixed >> 30)) * 0xbf58476d1ce4e5b9ull;
    mixed = (mixed ^ (mixed >> 27)) * 0x94d049bb133111ebull;
    return mixed ^ (mixed >> 31);
}

/** @brief The header tail and midstate a nonce is hashed against. */
struct Job
{
    Sha256State midstate;      /**< Chaining value after header bytes 0 through 63. */
    uint32_t merkle_root_tail; /**< Header bytes 64 through 67, big-endian. */
    uint32_t ntime;            /**< Header bytes 68 through 71, big-endian. */
    uint32_t nbits;            /**< Header bytes 72 through 75, big-endian. */
};

/**
 * @brief Fills the thirty-two digest bytes for one nonce, in the standard's own output order.
 *
 * @param[in]  job    Midstate and header tail [BORROWS].
 * @param[in]  source Which function to evaluate.
 * @param[in]  nonce  The nonce being evaluated.
 * @param[out] digest Thirty-two bytes [BORROWS].
 * @note The nonce sits in the header little-endian and SHA-256 reads its message big-endian, which
 *       is the reversal on the schedule word below and the one place this has gone wrong before.
 */
void fill_digest(const Job &job, Source source, uint32_t nonce, uint8_t *digest)
{
    if (source == SOURCE_CONSTANT)
    {
        std::memset(digest, 0, DIGEST_BYTES);
        return;
    }

    if (source == SOURCE_BALANCED)
    {
        for (unsigned copy = 0u; copy < 8u; copy += 1u)
        {
            digest[(copy * 4u) + 0u] = (uint8_t)(nonce >> 24);
            digest[(copy * 4u) + 1u] = (uint8_t)(nonce >> 16);
            digest[(copy * 4u) + 2u] = (uint8_t)(nonce >> 8);
            digest[(copy * 4u) + 3u] = (uint8_t)nonce;
        }
        return;
    }

    if (source == SOURCE_SPLITMIX)
    {
        uint64_t state = (uint64_t)nonce;
        for (unsigned half = 0u; half < 4u; half += 1u)
        {
            const uint64_t drawn = splitmix64(&state);
            for (unsigned byte = 0u; byte < 8u; byte += 1u)
            {
                digest[(half * 8u) + byte] = (uint8_t)(drawn >> (56u - (byte * 8u)));
            }
        }
        return;
    }

    uint32_t message_block[SHA256_BLOCK_WORDS];
    Sha256State first_pass = job.midstate;

    message_block[0] = job.merkle_root_tail;
    message_block[1] = job.ntime;
    message_block[2] = job.nbits;
    message_block[3] = reverse_word_bytes(nonce);
    message_block[4] = PADDING_LEAD_WORD;
    for (unsigned slot = 5u; slot < 15u; slot += 1u)
    {
        message_block[slot] = 0u;
    }
    message_block[15] = HEADER_LENGTH_BITS;
    sha256_block_compress(&first_pass, message_block);

    Sha256State second_pass;
    sha256_state_init(&second_pass);
    for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
    {
        message_block[slot] = first_pass.word[slot];
    }
    message_block[8] = PADDING_LEAD_WORD;
    for (unsigned slot = 9u; slot < 15u; slot += 1u)
    {
        message_block[slot] = 0u;
    }
    message_block[15] = DIGEST_LENGTH_BITS;
    sha256_block_compress(&second_pass, message_block);

    for (unsigned word = 0u; word < SHA256_STATE_WORDS; word += 1u)
    {
        digest[(word * 4u) + 0u] = (uint8_t)(second_pass.word[word] >> 24);
        digest[(word * 4u) + 1u] = (uint8_t)(second_pass.word[word] >> 16);
        digest[(word * 4u) + 2u] = (uint8_t)(second_pass.word[word] >> 8);
        digest[(word * 4u) + 3u] = (uint8_t)second_pass.word[word];
    }
}

/** @brief Everything one worker counts, merged into one set at the end. */
struct Counts
{
    std::vector<uint64_t> byte_window; /**< [window][value], 32 by 256. */
    std::vector<uint64_t> word_window; /**< [window][value], 16 by 65536. */
    uint64_t leading_zero[257];        /**< How many digests carried exactly k leading zero bits. */

    Counts() : byte_window((size_t)BYTE_WINDOWS * BYTE_BINS, 0u),
               word_window((size_t)WORD_WINDOWS * WORD_BINS, 0u)
    {
        std::memset(leading_zero, 0, sizeof(leading_zero));
    }
};

/**
 * @brief Reads a field of bits from the digest starting at an arbitrary bit, treating it as a ring.
 *
 * @param[in] digest Thirty-two bytes [BORROWS].
 * @param[in] start  First bit, counting from the most significant bit of byte zero.
 * @param[in] width  How many bits, at most 32.
 * @return           The field, most significant bit first.
 * @note From the symbol-width posit in anchor_sift: a detector is not told where the units begin,
 *       and a slice of the right width at the wrong offset splits every unit across two symbols.
 *       Every window in this bench was byte-aligned until this existed, so structure sitting at an
 *       offset of one to seven bits was split at every width and invisible to all of it.
 * @note The digest is read as a ring so that every phase reads all 256 bits instead of running
 *       off the end and reading a short final window, which would make the last window of each
 *       phase incomparable with the others.
 */
uint32_t extract_bits(const uint8_t *digest, unsigned start, unsigned width)
{
    uint32_t value = 0u;
    for (unsigned step = 0u; step < width; step += 1u)
    {
        const unsigned at = (start + step) & 255u;
        value = (value << 1) | (uint32_t)((digest[at >> 3] >> (7u - (at & 7u))) & 1u);
    }
    return value;
}

/**
 * @brief Counts leading zero bits the way the protocol reads a digest.
 *
 * @param[in] digest Thirty-two bytes in the standard's output order [BORROWS].
 * @return           Leading zero bits, up to 256.
 * @note The protocol reads a digest little-endian, so the most significant byte is the last one.
 *       This is the one statistic here that is read in protocol order instead of standard order,
 *       because it is the one that decides whether a nonce is a share.
 */
unsigned protocol_leading_zeros(const uint8_t *digest)
{
    unsigned leading = 0u;

    for (unsigned step = 0u; step < DIGEST_BYTES; step += 1u)
    {
        const uint8_t value = digest[(DIGEST_BYTES - 1u) - step];
        if (value != 0u)
        {
            unsigned bit = 0u;
            while (((value >> (7u - bit)) & 1u) == 0u)
            {
                bit += 1u;
            }
            return leading + bit;
        }
        leading += 8u;
    }
    return 256u;
}

/**
 * @brief Hashes one contiguous nonce range and counts it.
 *
 * @param[in]     job         Midstate and header tail [BORROWS].
 * @param[in]     source      Which function to evaluate.
 * @param[in]     first       First nonce in this worker's range.
 * @param[in]     count       How many nonces, ascending.
 * @param[in,out] counts      Where the private histograms accumulate [BORROWS].
 * @param[in,out] wide_window Shared counter per 32-bit value of digest bytes 0 to 3, or null.
 */
void count_range(const Job &job, Source source, uint64_t first, uint64_t count, unsigned phase,
                 Counts *counts, std::atomic<unsigned char> *wide_window)
{
    uint8_t digest[DIGEST_BYTES];

    for (uint64_t step = 0u; step < count; step += 1u)
    {
        const uint32_t nonce = (uint32_t)(first + step);
        fill_digest(job, source, nonce, digest);

        if (phase == 0u)
        {
            // Byte-aligned, which is a whole-byte read and needs no bit walking.
            for (unsigned window = 0u; window < BYTE_WINDOWS; window += 1u)
            {
                counts->byte_window[((size_t)window * BYTE_BINS) + digest[window]] += 1u;
            }

            for (unsigned window = 0u; window < WORD_WINDOWS; window += 1u)
            {
                const unsigned value =
                    ((unsigned)digest[window * 2u] << 8) | (unsigned)digest[(window * 2u) + 1u];
                counts->word_window[((size_t)window * WORD_BINS) + value] += 1u;
            }
        }
        else
        {
            for (unsigned window = 0u; window < BYTE_WINDOWS; window += 1u)
            {
                const unsigned value = extract_bits(digest, (window * 8u) + phase, 8u);
                counts->byte_window[((size_t)window * BYTE_BINS) + value] += 1u;
            }

            for (unsigned window = 0u; window < WORD_WINDOWS; window += 1u)
            {
                const unsigned value = extract_bits(digest, (window * 16u) + phase, 16u);
                counts->word_window[((size_t)window * WORD_BINS) + value] += 1u;
            }
        }

        counts->leading_zero[protocol_leading_zeros(digest)] += 1u;

        if (wide_window != nullptr)
        {
            const uint32_t value = ((uint32_t)digest[0] << 24) | ((uint32_t)digest[1] << 16) |
                                   ((uint32_t)digest[2] << 8) | (uint32_t)digest[3];
            wide_window[value].fetch_add(1u, std::memory_order_relaxed);
        }
    }
}

/** @brief The Renyi orders swept, with infinity carried as its own flag. */
struct Order
{
    double alpha;    /**< The order. */
    const char *tag; /**< How it prints. */
    int is_support;  /**< Nonzero for order zero, which counts occupied bins. */
    int is_peak;     /**< Nonzero for order infinity, which reads the largest bin. */
};

const Order ORDERS[7] = {{0.0, "0", 1, 0},   {0.5, "1/2", 0, 0}, {1.0, "1", 0, 0},
                         {2.0, "2", 0, 0},   {3.0, "3", 0, 0},   {4.0, "4", 0, 0},
                         {0.0, "inf", 0, 1}};

/**
 * @brief What one bin contributes to the deficit sum at one order.
 *
 * @param[in] order     Which order.
 * @param[in] deviation The bin's relative deviation from the mean, (count - mean) / mean.
 * @param[in] is_empty  Nonzero where the bin holds nothing.
 * @return              The bin's term.
 * @note The empty bin is the whole reason this is a function instead of two lines written twice.
 *       At a positive order it contributes exactly minus one, since (0)^alpha - 1 is minus one. At
 *       order one it contributes exactly zero, since the count in front of the logarithm goes to
 *       zero faster than the logarithm goes to minus infinity. Those two rules are opposite and
 *       there is one place in this file that knows both. A second copy of them got the Shannon
 *       case wrong and put 0.2965 in a table where 0.8272 belonged, which is the argument for the
 *       function existing.
 */
long double deficit_term(const Order &order, long double deviation, int is_empty)
{
    if (order.alpha == 1.0)
    {
        return (is_empty != 0) ? 0.0L : ((1.0L + deviation) * std::log1p(deviation));
    }
    return (is_empty != 0) ? -1.0L
                           : std::expm1((long double)order.alpha * std::log1p(deviation));
}

/**
 * @brief Computes the entropy deficit of one histogram at one Renyi order.
 *
 * @param[in] counts Bin counts [BORROWS].
 * @param[in] bins   How many bins.
 * @param[in] total  Sum of the counts, which is the domain size.
 * @param[in] order  Which order to evaluate.
 * @return           log2(bins) minus the Renyi entropy, in bits.
 * @note Written on the deviation instead of on the counts. With c = m(1 + e) and m = total/bins,
 *       the deficit is log2((1/r) sum (1+e)^alpha) / (alpha - 1), and every term is formed through
 *       log1p and expm1 so that a deviation of 1e-5 is not asked to survive being added to one and
 *       subtracted again. Taking the difference of two logarithms instead loses the answer.
 */
double deficit_at(const uint64_t *counts, size_t bins, uint64_t total, const Order &order)
{
    const double mean = (double)total / (double)bins;

    if (order.is_support != 0)
    {
        size_t occupied = 0u;
        for (size_t bin = 0u; bin < bins; bin += 1u)
        {
            occupied += (counts[bin] != 0u) ? 1u : 0u;
        }
        return -std::log2((double)occupied / (double)bins);
    }

    if (order.is_peak != 0)
    {
        uint64_t largest = 0u;
        for (size_t bin = 0u; bin < bins; bin += 1u)
        {
            largest = (counts[bin] > largest) ? counts[bin] : largest;
        }
        return std::log2((double)largest / mean);
    }

    long double accumulated = 0.0L;
    for (size_t bin = 0u; bin < bins; bin += 1u)
    {
        const long double deviation = ((long double)counts[bin] - (long double)mean) /
                                      (long double)mean;
        accumulated += deficit_term(order, deviation, (counts[bin] == 0u) ? 1 : 0);
    }

    if (order.alpha == 1.0)
    {
        return (double)(accumulated / (long double)bins / std::log(2.0L));
    }

    const long double mean_power = accumulated / (long double)bins;
    return (double)(std::log1p(mean_power) / std::log(2.0L) / (long double)(order.alpha - 1.0));
}

/**
 * @brief The deficit a random function is predicted to show, in the regime where bins are full.
 *
 * @param[in] bins  How many bins.
 * @param[in] total Domain size.
 * @param[in] alpha Renyi order.
 * @return          Predicted deficit in bits.
 * @note This is the linearisation, valid where the mean bin count is far above one. The variance
 *       of the relative deviation is exactly (r-1)/d for a multinomial, so nothing here is fitted.
 */
double predicted_deficit(size_t bins, uint64_t total, const Order &order)
{
    const double variance = ((double)bins - 1.0) / (double)total;

    if (order.is_support != 0)
    {
        // Expected empty bins are r exp(-m), which underflows to nothing once the mean count is
        // large. Left as it computes instead of rounded to zero by hand.
        const double empty = (double)bins * std::exp(-(double)total / (double)bins);
        const double deficit = -std::log2(1.0 - (empty / (double)bins));
        // Underflow leaves a signed zero, which prints as "-0" and reads as a sign convention
        // that does not exist here.
        return (deficit == 0.0) ? 0.0 : deficit;
    }

    if (order.is_peak != 0)
    {
        // The largest of r deviations, each near normal with this variance. Extreme value, so the
        // leading term with its first correction instead of a bare square root.
        const double logs = 2.0 * std::log((double)bins);
        const double expected_peak =
            std::sqrt(variance) *
            (std::sqrt(logs) - ((std::log(std::log((double)bins)) + std::log(4.0 * 3.14159265358979)) /
                                (2.0 * std::sqrt(logs))));
        return std::log2(1.0 + expected_peak);
    }

    return order.alpha * variance / (2.0 * std::log(2.0));
}

/**
 * @brief The deficit a random function is predicted to show where the bins are nearly empty.
 *
 * @param[in] bins  How many bins.
 * @param[in] total Domain size.
 * @param[in] order Which order.
 * @return          Predicted deficit in bits.
 * @note Here the counts are Poisson with mean d/r and the deficit is read straight off the
 *       moments, summed instead of quoted so that the number printed is one this program derived.
 *       At mean one the moments are the Bell numbers, which is worth knowing but is not assumed.
 */
double predicted_deficit_sparse(size_t bins, uint64_t total, const Order &order)
{
    const double mean = (double)total / (double)bins;
    // Enough terms that the tail left out is far below the smallest quantity read off this sum.
    const unsigned terms = 256u;

    long double weight = std::exp(-(long double)mean);
    long double moment = 0.0L;
    long double occupied = 0.0L;
    long double above = 1.0L;
    unsigned peak = 0u;

    for (unsigned count = 0u; count < terms; count += 1u)
    {
        if (count > 0u)
        {
            weight *= (long double)mean / (long double)count;
            occupied += weight;
        }

        // The largest of r Poisson draws is the largest count the range is big enough to hold, so
        // walk the upper tail down until fewer than one bin is expected to reach it.
        if (above * (long double)bins >= 1.0L)
        {
            peak = count;
        }
        above -= weight;

        if ((order.is_peak != 0) || (count == 0u))
        {
            continue;
        }
        if (order.alpha == 1.0)
        {
            moment += weight * (long double)count * std::log((long double)count);
        }
        else
        {
            moment += weight * std::pow((long double)count, (long double)order.alpha);
        }
    }

    if (order.is_support != 0)
    {
        return (double)(-std::log(occupied) / std::log(2.0L));
    }
    if (order.is_peak != 0)
    {
        return std::log2((double)peak / mean);
    }
    if (order.alpha == 1.0)
    {
        // E[c log2 c] / mean, less log2 of the mean. The second term is zero exactly when the
        // mean is one, which is the full-domain case and is where this was first read, so a
        // version without it agreed at the operating point and disagreed everywhere else. A
        // defect that hides precisely where it is being used is the worst kind to leave in.
        return (double)((moment / (long double)mean / std::log(2.0L)) -
                        std::log2((long double)mean));
    }
    return (double)(std::log(moment / std::pow((long double)mean, (long double)order.alpha)) /
                    std::log(2.0L) / (long double)(order.alpha - 1.0));
}

/**
 * @brief Transforms the hole indicator over every one of the 2^32 masks and reports the largest.
 *
 * @param[in] wide_window Preimage counts for the 32-bit window [BORROWS].
 * @param[in] bins        How many values, which is 2^32.
 * @param[in] hole_total  How many of them are unreached, used as an exact check on the transform.
 * @param[in] workers     How many threads to use.
 * @note The byte-pair test above covers 393,210 masks, which is every mask confined to two of the
 *       four bytes. That leaves 4.29 billion masks unexamined, and the ones it leaves out are
 *       exactly the ones that span three or four bytes. This examines all of them.
 * @note In thirty-two dimensions there is no inside to look out from. Every one of the 2^32 values
 *       is a corner of the cube, so "check every point on the outside looking in" and "check every
 *       direction" are the same instruction, and the complete set of linear directions is the
 *       complete set of nonzero masks. That is what a Walsh-Hadamard transform computes, all of it,
 *       in n log n instead of n squared.
 * @note Signed 32-bit is enough, but only once the right set is transformed, and the bound is worth
 *       writing down because the first version of it was wrong. After any stage the value at a
 *       position is a signed sum over a subset of the indicator, so its magnitude is at most the
 *       number of ones in that subset and therefore at most the total number of ones. At the full
 *       domain the holes number about 1.58e9 against a type that holds 2.147e9, which is fine; at a
 *       reduced domain nearly every value is a hole and the count runs to 4.2e9, which is not.
 * @note So the smaller of the two sets is transformed. Marking the reached values instead of the
 *       holes changes no coefficient that matters, because the two indicators differ by the
 *       constant one and a constant has no Walsh weight anywhere except at mask zero. Taking the
 *       smaller side bounds the total by half the range and the type covers it.
 * @note That mistake was caught by the transform's own check instead of by inspection, which is
 *       the argument for the check existing. The coefficient at mask zero is the plain sum of the
 *       indicator, so it must equal the count exactly, and it read -66587004 against 4228380292 -
 *       a difference of exactly 2^32, which is a wraparound wearing its cause on its face.
 * @note The transform's own check is free: the coefficient at mask zero is the plain sum of the
 *       indicator, so it has to equal the hole count exactly. A transform that got that wrong got
 *       everything wrong, and it is checked instead of assumed.
 */
/**
 * @brief A 128-bit unsigned accumulator, as two 64-bit halves.
 *
 * @note Parseval's sum is the only quantity here that needs more than 64 bits, and it needs them
 *       for a specific reason. When the transform is correct the sum equals the length times the
 *       marked count, which is at most 2^63 and fits; when the transform is wrong the sum can be
 *       far larger, wrap, and land back inside the range looking correct. A check that a wrong
 *       answer can pass is not a check. So the accumulator is wider than the correct answer needs.
 * @note Written by hand instead of with a compiler extension because this file is built by both
 *       g++ and cl, and MSVC has no __int128. A type available on one arm and not the other would
 *       mean the device build silently skipped the check the host build relied on.
 */
struct WideSum
{
    uint64_t high; /**< Bits 64 and above. */
    uint64_t low;  /**< Bits 0 through 63. */
};

/**
 * @brief Adds a 64-bit value into a 128-bit accumulator.
 *
 * @param[in,out] total Accumulator [BORROWS].
 * @param[in]     value What to add.
 */
void wide_add(WideSum *total, uint64_t value)
{
    const uint64_t before = total->low;
    total->low += value;
    // The carry is the whole point of the type, so it is tested instead of assumed away.
    total->high += (total->low < before) ? 1u : 0u;
}

/**
 * @brief Reports whether two 128-bit accumulators hold the same value.
 *
 * @param[in] left  One [BORROWS].
 * @param[in] right The other [BORROWS].
 * @return          Nonzero where they are equal.
 */
int wide_same(const WideSum *left, const WideSum *right)
{
    return ((left->high == right->high) && (left->low == right->low)) ? 1 : 0;
}

void walsh_transform(int32_t *values, size_t span_total, unsigned stages, unsigned workers)
{
    const size_t butterflies = span_total / 2u;

    for (unsigned stage = 0u; stage < stages; stage += 1u)
    {
        const size_t span = (size_t)1u << stage;
        std::vector<std::thread> movers;

        for (unsigned slice = 0u; slice < workers; slice += 1u)
        {
            movers.push_back(std::thread([values, butterflies, span, stage, workers, slice]() {
                const size_t first = (butterflies / workers) * slice;
                const size_t last =
                    (slice + 1u == workers) ? butterflies : ((butterflies / workers) * (slice + 1u));

                for (size_t step = first; step < last; step += 1u)
                {
                    const size_t low = ((step >> stage) << (stage + 1u)) | (step & (span - 1u));
                    const int32_t left = values[low];
                    const int32_t right = values[low + span];
                    values[low] = left + right;
                    values[low + span] = left - right;
                }
            }));
        }
        for (std::thread &mover : movers)
        {
            mover.join();
        }
    }
}

/**
 * @brief Runs the transform on a small known case and reports whether it is trustworthy.
 *
 * @param[in] workers How many threads, so the threaded path is the one under test.
 * @return            Nonzero where every check passed.
 * @note The large run cannot be checked against a direct computation because that is quadratic in
 *       four billion. A small one can, and the same code performs both, so the small one is the
 *       evidence. Three checks, each of which the wrong answer fails:
 *
 *         the coefficient at mask zero is the plain sum of the indicator
 *         no coefficient exceeds that sum, since the indicator is zero or one
 *         Parseval: the squares of the coefficients sum to the length times the sum
 *
 *       Parseval is the one that binds. It is an identity over the whole spectrum instead of a
 *       bound on one entry, so a transform that is wrong anywhere fails it, and it costs one pass.
 */
int walsh_transform_self_test(unsigned workers, unsigned stages)
{
    const size_t span_total = (size_t)1u << stages;

    std::vector<int32_t> values(span_total, 0);
    std::mt19937 generator(20260908u);
    uint64_t marked = 0u;
    for (size_t at = 0u; at < span_total; at += 1u)
    {
        values[at] = ((generator() & 3u) == 0u) ? 1 : 0;
        marked += (uint64_t)values[at];
    }

    walsh_transform(values.data(), span_total, stages, workers);

    if ((uint64_t)values[0] != marked)
    {
        std::printf("  [!] self test: mask zero reads %d against %llu marked\n", values[0],
                    (unsigned long long)marked);
        return 0;
    }

    // Parseval, accumulated wide. A coefficient can reach the marked count, so its square can
    // reach that squared, and the sum runs over every mask. Nothing narrower than 128 bits is
    // guaranteed to hold it once this is used on the full range.
    WideSum energy = {0u, 0u};
    int64_t largest = 0;
    for (size_t mask = 0u; mask < span_total; mask += 1u)
    {
        const int64_t here = (int64_t)values[mask];
        const int64_t size = (here < 0) ? -here : here;
        wide_add(&energy, (uint64_t)(size * size));
        largest = (size > largest) ? size : largest;
    }

    WideSum expected = {0u, 0u};
    for (size_t step = 0u; step < span_total; step += 1u)
    {
        wide_add(&expected, marked);
    }
    if (wide_same(&energy, &expected) == 0)
    {
        std::printf("  [!] self test: Parseval fails\n");
        return 0;
    }
    if ((uint64_t)largest > marked)
    {
        std::printf("  [!] self test: a coefficient of %lld exceeds the marked count %llu\n",
                    (long long)largest, (unsigned long long)marked);
        return 0;
    }
    return 1;
}

void report_full_spectrum(const std::atomic<unsigned char> *wide_window, size_t bins,
                          uint64_t hole_total, unsigned workers)
{
    const uint64_t wanted = (uint64_t)bins * sizeof(int32_t);
    const uint64_t budget = bench_memory_budget();

    std::printf("\n  Every direction, not only the ones inside two bytes\n");
    std::printf("\n  %-46s %14.2f GB\n", "the transform needs",
                (double)wanted / (1024.0 * 1024.0 * 1024.0));
    std::printf("  %-46s %14.2f GB\n", "the budget allows",
                (double)budget / (1024.0 * 1024.0 * 1024.0));

    if ((budget != 0u) && (wanted > budget))
    {
        std::printf("\n  [!] over budget, so this pass is skipped instead of paged. The byte-pair\n");
        std::printf("      figures above stand and cover masks inside any two bytes only.\n");
        return;
    }

    // The same code on a case small enough to check completely, before it is trusted on a case
    // that is not. A transform that fails here would have produced a number here that looked like
    // a finding, which is exactly what it did before this existed.
    // Several sizes, not one. The bug this caught the first time lived only at large stage counts,
    // so a self test at a single small size would have passed and cleared a transform that was
    // wrong at the size it was about to be used at.
    for (unsigned stages = 12u; stages <= 26u; stages += 2u)
    {
        if (walsh_transform_self_test(workers, stages) == 0)
        {
            std::printf("\n  [!] the transform failed its self test at %u stages, so this pass is\n",
                        stages);
            std::printf("      skipped. It passed at every smaller size, which is why the test\n");
            std::printf("      sweeps instead of picking one.\n");
            return;
        }
    }
    std::printf("  %-46s %14s\n", "self test, 12 through 26 stages", "passed");

    int32_t *const spectrum = new (std::nothrow) int32_t[bins];
    if (spectrum == nullptr)
    {
        std::printf("\n  [!] the allocation failed, so this pass is skipped.\n");
        return;
    }

    // Whichever side is smaller. The two indicators differ by the constant one, which carries no
    // Walsh weight away from mask zero, so every coefficient this reports is the same either way.
    const int mark_holes = (hole_total <= (uint64_t)(bins / 2u)) ? 1 : 0;
    const uint64_t marked = (mark_holes != 0) ? hole_total : ((uint64_t)bins - hole_total);

    if (marked >= 2147483647ull)
    {
        std::printf("\n  [!] the smaller side still holds %llu values, which a signed 32-bit sum\n",
                    (unsigned long long)marked);
        std::printf("      cannot carry. Skipped instead of wrapped.\n");
        delete[] spectrum;
        return;
    }

    std::printf("  %-46s %14s\n", "transforming the smaller side",
                (mark_holes != 0) ? "the holes" : "the reached");

    for (size_t value = 0u; value < bins; value += 1u)
    {
        const int is_hole = (wide_window[value].load(std::memory_order_relaxed) == 0u) ? 1 : 0;
        spectrum[value] = ((mark_holes != 0) == (is_hole != 0)) ? 1 : 0;
    }

    // Count what was actually written before transforming it. This separates a bad fill from a bad
    // transform, which reasoning about the code could not do: the failure was non-deterministic,
    // and a non-deterministic wrong answer is a race or bad memory instead of wrong arithmetic.
    uint64_t filled = 0u;
    for (size_t value = 0u; value < bins; value += 1u)
    {
        filled += (uint64_t)spectrum[value];
    }
    if (filled != marked)
    {
        std::printf("\n  [!] the fill wrote %llu ones where %llu were expected, so the array was\n",
                    (unsigned long long)filled, (unsigned long long)marked);
        std::printf("      wrong before any transform touched it. Nothing printed.\n");
        delete[] spectrum;
        return;
    }

    walsh_transform(spectrum, bins, 32u, workers);

    // Parseval over the whole spectrum, which is the check that binds. A bound on one coefficient
    // can be satisfied by an array that is wrong everywhere else; an identity over the sum cannot.
    // Accumulated in 128 bits because the terms reach the marked count squared, about 2.5e18 at
    // the full domain, and their sum runs to the length times the marked count, about 6.8e18 -
    // which is inside 64 bits only by a factor of one and a half, and outside it the moment the
    // marked count is any larger. Not a width to be casual about.
    WideSum energy = {0u, 0u};
    int64_t largest_seen = 0;
    for (size_t mask = 0u; mask < bins; mask += 1u)
    {
        const int64_t here = (int64_t)spectrum[mask];
        const int64_t size = (here < 0) ? -here : here;
        wide_add(&energy, (uint64_t)(size * size));
        largest_seen = (size > largest_seen) ? size : largest_seen;
    }

    // The length times the marked count, formed by repeated addition into the same wide type, so
    // the comparison is between two values built the same way and neither can wrap past the other.
    WideSum expected_energy = {0u, 0u};
    for (size_t step = 0u; step < bins; step += 1u)
    {
        wide_add(&expected_energy, marked);
    }

    if ((wide_same(&energy, &expected_energy) == 0) || ((uint64_t)largest_seen > marked))
    {
        std::printf("\n  [!] the transform does not satisfy Parseval, or a coefficient exceeds the\n");
        std::printf("      marked count, which is impossible for a zero-one indicator. Largest\n");
        std::printf("      coefficient %lld against a marked count of %llu. Nothing printed.\n",
                    (long long)largest_seen, (unsigned long long)marked);
        delete[] spectrum;
        return;
    }

    if ((uint64_t)spectrum[0] != marked)
    {
        std::printf("\n  [!] the coefficient at mask zero is %lld and the marked count is %llu.\n",
                    (long long)spectrum[0], (unsigned long long)marked);
        std::printf("      Those have to be equal, so the transform is wrong and nothing below\n");
        std::printf("      it means anything. Not printed.\n");
        delete[] spectrum;
        return;
    }

    const double subset = (double)hole_total;
    const double population = (double)bins;
    const double deviation = std::sqrt(subset * (population - subset) / (population - 1.0));

    double worst = 0.0;
    size_t worst_mask = 0u;
    uint64_t beyond_five = 0u;
    uint64_t beyond_six = 0u;

    for (size_t mask = 1u; mask < bins; mask += 1u)
    {
        const double score = std::fabs((double)spectrum[mask]) / deviation;
        beyond_five += (score > 5.0) ? 1u : 0u;
        beyond_six += (score > 6.0) ? 1u : 0u;
        if (score > worst)
        {
            worst = score;
            worst_mask = mask;
        }
    }

    // The largest of this many standard normals, to first order with its first correction. Not a
    // threshold anybody chose, and the count beside it is what a reader should weigh instead.
    const double logs = 2.0 * std::log((double)(bins - 1u));
    const double expected_worst =
        std::sqrt(logs) -
        ((std::log(std::log((double)(bins - 1u))) + std::log(4.0 * 3.14159265358979)) /
         (2.0 * std::sqrt(logs)));

    std::printf("\n  %-46s %14llu\n", "masks tested, every nonzero one",
                (unsigned long long)(bins - 1u));
    std::printf("  %-46s %14.1f\n", "one standard deviation of a coefficient", deviation);
    std::printf("  %-46s %14.4f\n", "largest coefficient, in deviations", worst);
    std::printf("  %-46s %14.4f\n", "largest a random arrangement would give", expected_worst);
    std::printf("  %-46s   %08llx\n", "where the largest sits", (unsigned long long)worst_mask);
    std::printf("  %-46s %14llu   expected %10.1f\n", "coefficients beyond five deviations",
                (unsigned long long)beyond_five,
                (double)(bins - 1u) * 5.733031e-07);
    std::printf("  %-46s %14llu   expected %10.4f\n", "coefficients beyond six deviations",
                (unsigned long long)beyond_six,
                (double)(bins - 1u) * 1.973175e-09);

    delete[] spectrum;
}

/**
 * @brief Prints the deficit profile of one family of windows.
 *
 * @param[in] title   What the family is called.
 * @param[in] counts  All windows laid out end to end [BORROWS].
 * @param[in] windows How many windows.
 * @param[in] bins    Bins per window.
 * @param[in] total   Domain size.
 */
void report_family(const char *title, const uint64_t *counts, unsigned windows, size_t bins,
                   uint64_t total)
{
    const double mean = (double)total / (double)bins;
    // The linearised prediction is an expansion in the relative deviation, which stops being small
    // once the mean count approaches one. Below that the counts are Poisson and are summed as such.
    const int sparse = (mean < 8.0) ? 1 : 0;
    // The chi-square statistic behind every deficit has variance twice its degrees of freedom, so
    // one window resolves its own deficit to this fraction and no better.
    const double resolution = std::sqrt(2.0 / ((double)bins - 1.0));

    std::printf("\n  %s\n", title);
    std::printf("  windows %u, bins %llu, mean count %.4g, one-window resolution %.3g of the "
                "deficit\n",
                windows, (unsigned long long)bins, mean, resolution);
    std::printf("  prediction: %s\n",
                (sparse != 0) ? "Poisson moments, summed here" : "alpha * var(e) / (2 ln 2)");

    std::printf("\n  %5s %16s %16s %12s %12s\n", "order", "mean deficit", "predicted", "ratio",
                "spread");
    std::printf("  %5s %16s %16s %12s %12s\n", "-----", "----------------", "----------------",
                "------------", "------------");

    double average_at[7];

    for (unsigned index = 0u; index < 7u; index += 1u)
    {
        const Order &order = ORDERS[index];
        std::vector<double> per_window((size_t)windows, 0.0);
        double sum = 0.0;

        for (unsigned window = 0u; window < windows; window += 1u)
        {
            per_window[window] = deficit_at(&counts[(size_t)window * bins], bins, total, order);
            sum += per_window[window];
        }

        const double average = sum / (double)windows;

        // Two passes, about the mean. The one-pass form, mean of squares less square of the mean,
        // subtracts two nearly equal large numbers whenever the windows agree closely, which is
        // exactly the case this bench is built to produce. It lands on either side of zero
        // depending on instruction selection, so the host printed 0 and the device printed
        // 8.4e-08 and then a NaN from the square root of a negative. Same counts, same deficits,
        // different arithmetic - and the acceptance test caught it instead of the eye.
        double square_sum = 0.0;
        for (unsigned window = 0u; window < windows; window += 1u)
        {
            const double offset = per_window[window] - average;
            square_sum += offset * offset;
        }
        const double spread = std::sqrt(square_sum / (double)windows);
        const double predicted = (sparse != 0) ? predicted_deficit_sparse(bins, total, order)
                                               : predicted_deficit(bins, total, order);
        average_at[index] = average;

        // A prediction that has underflowed is not a prediction, and dividing by it would print a
        // ratio that looks like a finding. Say there is nothing to compare against instead.
        if (predicted > 1e-300)
        {
            std::printf("  %5s %16.9g %16.9g %12.5f %12.4g\n", order.tag, average, predicted,
                        average / predicted, spread);
        }
        else
        {
            std::printf("  %5s %16.9g %16.9g %12s %12.4g\n", order.tag, average, predicted, "--",
                        spread);
        }
    }

    // The relation between two orders is the parameter-free part. Every scale factor common to
    // both cancels, so a departure from four cannot be blamed on the domain size or the bin count.
    const double at_half = average_at[1];
    const double at_two = average_at[3];

    // A distribution that is exactly flat has no deficit at either order, and the ratio of two
    // zeros is not four and is not a failure to be four. It is nothing, and it says so.
    if (at_half == 0.0)
    {
        std::printf("\n  order two over order one half : both deficits are exactly zero, so the\n");
        std::printf("  ratio is undefined. Exact flatness is the answer, not a ratio.\n");
        return;
    }

    std::printf("\n  order two over order one half : %.6f", at_two / at_half);
    if (sparse != 0)
    {
        const double expected = predicted_deficit_sparse(bins, total, ORDERS[3]) /
                                predicted_deficit_sparse(bins, total, ORDERS[1]);
        std::printf("   (Poisson says %.6f)\n", expected);
    }
    else
    {
        std::printf("   (a random function says exactly 4)\n");
    }
}

/**
 * @brief Runs one source over the domain and reports everything read off it.
 *
 * @param[in] name        What to call this source in the output.
 * @param[in] job         Midstate and header tail [BORROWS].
 * @param[in] source      Which function to evaluate.
 * @param[in] domain      How many nonces to enumerate, from zero.
 * @param[in] workers     How many threads.
 * @param[in] phase       Bit offset every window starts at, zero for byte-aligned.
 * @param[in] wide_window Shared 32-bit-window counters, or null to skip that family.
 */
void run_source(const char *name, const Job &job, Source source, uint64_t domain, unsigned workers,
                unsigned phase, int on_device, std::atomic<unsigned char> *wide_window)
{
    std::printf("\n================================================================\n");
    std::printf("  %s\n", name);
    std::printf("================================================================\n");

    if (wide_window != nullptr)
    {
        std::memset((void *)wide_window, 0, (size_t)1u << 32);
    }

    Counts merged;
    bool counted_on_device = false;

#if BENCH_RENYI_HAS_CUDA
    if (on_device != 0)
    {
        RenyiCudaJob device_job;
        for (unsigned word = 0u; word < SHA256_STATE_WORDS; word += 1u)
        {
            device_job.midstate[word] = job.midstate.word[word];
        }
        device_job.merkle_root_tail = job.merkle_root_tail;
        device_job.ntime = job.ntime;
        device_job.nbits = job.nbits;

        // The device fills the same three histograms the host threads would, and nothing else.
        // Every deficit, prediction and control below is the host's own code reading them.
        if (renyi_cuda_count(&device_job, (int)source, domain, phase, merged.byte_window.data(),
                             merged.word_window.data(), merged.leading_zero,
                             (unsigned char *)wide_window) == 0)
        {
            std::printf("\n  [!] the device refused this run, so nothing was counted.\n");
            return;
        }
        counted_on_device = true;
    }
#endif

    if (!counted_on_device)
    {
    std::vector<Counts> parts((size_t)workers);
    std::vector<std::thread> threads;
    const uint64_t share = domain / workers;

    for (unsigned worker = 0u; worker < workers; worker += 1u)
    {
        const uint64_t first = (uint64_t)worker * share;
        const uint64_t count = (worker + 1u == workers) ? (domain - first) : share;
        threads.push_back(std::thread(count_range, std::cref(job), source, first, count, phase,
                                      &parts[worker], wide_window));
    }
    for (std::thread &thread : threads)
    {
        thread.join();
    }

    for (unsigned worker = 0u; worker < workers; worker += 1u)
    {
        for (size_t slot = 0u; slot < merged.byte_window.size(); slot += 1u)
        {
            merged.byte_window[slot] += parts[worker].byte_window[slot];
        }
        for (size_t slot = 0u; slot < merged.word_window.size(); slot += 1u)
        {
            merged.word_window[slot] += parts[worker].word_window[slot];
        }
        for (unsigned bit = 0u; bit <= 256u; bit += 1u)
        {
            merged.leading_zero[bit] += parts[worker].leading_zero[bit];
        }
    }
    }

    // From here down there is one reporting path, whichever arm did the counting. A device that
    // also computed its own deficits would be failure mode fifteen by construction.
    report_family("byte windows, all 32 positions", merged.byte_window.data(), BYTE_WINDOWS,
                  BYTE_BINS, domain);
    report_family("sixteen-bit windows, all 16 positions", merged.word_window.data(), WORD_WINDOWS,
                  WORD_BINS, domain);

    if (wide_window != nullptr)
    {
        // The 32-bit window over a 2^32 domain is the one place where a bin can be empty, which is
        // the whole reason it is worth the four gigabytes it costs.
        const size_t bins = (size_t)1u << 32;
        // One pass over four gigabytes reduces the whole window to how many bins carry each count.
        // Counts here are Poisson about a mean of one, so only about a dozen distinct values ever
        // occur and every statistic below is a sum over those instead of over the bins. Scanning
        // the bins once per order instead costs seven passes of transcendentals over 2^32 and
        // takes hours to produce the same numbers.
        const unsigned spectrum_span = 256u;
        std::vector<uint64_t> spectrum(spectrum_span, 0u);
        for (size_t bin = 0u; bin < bins; bin += 1u)
        {
            const unsigned count = wide_window[bin].load(std::memory_order_relaxed);
            spectrum[(count < (spectrum_span - 1u)) ? count : (spectrum_span - 1u)] += 1u;
        }
        if (spectrum[spectrum_span - 1u] != 0u)
        {
            // The last bucket is a catch-all and its members have lost their counts, so every
            // statistic below would be wrong by an unknown amount. Say so instead of print them.
            std::printf("\n  [!] %llu bins carry %u or more preimages, which the spectrum cannot\n",
                        (unsigned long long)spectrum[spectrum_span - 1u], spectrum_span - 1u);
            std::printf("      represent. The figures below would be wrong and are not printed.\n");
            return;
        }

        std::printf("\n  32-bit window at digest bytes 0 to 3, preimage counts\n");
        std::printf("\n  %6s %20s %20s %12s\n", "count", "bins observed", "Poisson predicts",
                    "ratio");
        std::printf("  %6s %20s %20s %12s\n", "------", "--------------------",
                    "--------------------", "------------");

        const double mean = (double)domain / (double)bins;
        long double weight = std::exp(-(long double)mean);
        for (unsigned count = 0u; count < 8u; count += 1u)
        {
            if (count > 0u)
            {
                weight *= (long double)mean / (long double)count;
            }
            const double predicted = (double)weight * (double)bins;
            std::printf("  %6u %20llu %20.6g %12.6f\n", count,
                        (unsigned long long)spectrum[count], predicted,
                        (double)spectrum[count] / predicted);
        }

        std::printf("\n  values never reached : %llu of %llu, a fraction of %.9f\n",
                    (unsigned long long)spectrum[0], (unsigned long long)bins,
                    (double)spectrum[0] / (double)bins);
        std::printf("  a random function is unreachable on 1/e = %.9f of its range\n",
                    std::exp(-1.0));

        std::printf("\n  Renyi profile of that window\n");
        std::printf("\n  %5s %16s %16s %12s\n", "order", "deficit", "Poisson", "ratio");
        std::printf("  %5s %16s %16s %12s\n", "-----", "----------------", "----------------",
                    "------------");
        size_t occupied = 0u;
        uint64_t largest = 0u;
        for (unsigned count = 1u; count < spectrum_span; count += 1u)
        {
            occupied += (size_t)spectrum[count];
            largest = (spectrum[count] != 0u) ? (uint64_t)count : largest;
        }

        for (unsigned index = 0u; index < 7u; index += 1u)
        {
            const Order &order = ORDERS[index];
            long double accumulated = 0.0L;

            for (unsigned count = 0u; count < spectrum_span; count += 1u)
            {
                if ((spectrum[count] == 0u) || (order.is_support != 0) || (order.is_peak != 0))
                {
                    continue;
                }
                const long double deviation = ((long double)count - (long double)mean) /
                                              (long double)mean;
                accumulated += (long double)spectrum[count] *
                               deficit_term(order, deviation, (count == 0u) ? 1 : 0);
            }

            double measured;
            if (order.is_support != 0)
            {
                measured = -std::log2((double)occupied / (double)bins);
            }
            else if (order.is_peak != 0)
            {
                measured = std::log2((double)largest / mean);
            }
            else if (order.alpha == 1.0)
            {
                measured = (double)(accumulated / (long double)bins / std::log(2.0L));
            }
            else
            {
                measured = (double)(std::log1p(accumulated / (long double)bins) /
                                    std::log(2.0L) / (long double)(order.alpha - 1.0));
            }

            const double predicted = predicted_deficit_sparse(bins, domain, order);
            std::printf("  %5s %16.9g %16.9g %12.6f\n", order.tag, measured, predicted,
                        measured / predicted);
        }

        // -------------------------------------------------------------------------------------
        // The arrangement, which every number above is blind to by construction.
        //
        // From anchor_sift's ledger: histogram quantities are permutation invariant, so they
        // describe the maximum entropy case and are free. Every figure printed above - all seven
        // Renyi orders, the balance, the count of holes - is a function of the count multiset and
        // nothing else, so shuffling which value carries which count leaves every one of them
        // exactly unchanged. That is not a weakness of the estimator, it is what those quantities
        // are, and it means the entire measurement so far cannot see where the holes sit.
        //
        // The arrangement is what remains. The permutation null deletes exactly it and preserves
        // exactly the histogram, which is what makes it the right null: it is the data with one
        // property removed instead of a model that could be false.
        //
        // The statistic is the Walsh spectrum of the hole indicator. A hole set with no linear
        // structure has every non-trivial Walsh coefficient at zero within sampling. Byte-pair
        // histograms are accumulated in the pass, then transformed, which tests every mask that
        // fits in any two bytes - 393,210 of them - exhaustively instead of by sampling.
        // -------------------------------------------------------------------------------------
        {
            const unsigned PAIR_COUNT = 6u;
            const unsigned PAIR_BINS = 65536u;
            const unsigned PAIR_LEFT[6] = {0u, 0u, 0u, 1u, 1u, 2u};
            const unsigned PAIR_RIGHT[6] = {1u, 2u, 3u, 2u, 3u, 3u};

            std::vector<int64_t> pair_counts((size_t)PAIR_COUNT * PAIR_BINS, 0);
            uint64_t hole_total = 0u;

            for (size_t bin = 0u; bin < bins; bin += 1u)
            {
                if (wide_window[bin].load(std::memory_order_relaxed) != 0u)
                {
                    continue;
                }
                hole_total += 1u;
                const unsigned byte[4] = {(unsigned)((bin >> 24) & 0xffu),
                                          (unsigned)((bin >> 16) & 0xffu),
                                          (unsigned)((bin >> 8) & 0xffu),
                                          (unsigned)(bin & 0xffu)};
                for (unsigned pair = 0u; pair < PAIR_COUNT; pair += 1u)
                {
                    const unsigned key = (byte[PAIR_LEFT[pair]] << 8) | byte[PAIR_RIGHT[pair]];
                    pair_counts[((size_t)pair * PAIR_BINS) + key] += 1;
                }
            }

            // A random subset of size H drawn from N values, read against a balanced sign
            // pattern, gives a coefficient of mean zero and this variance. Nothing is fitted.
            const double subset = (double)hole_total;
            const double population = (double)bins;
            const double deviation =
                std::sqrt(subset * (population - subset) / (population - 1.0));

            double worst = 0.0;
            unsigned worst_pair = 0u;
            unsigned worst_mask = 0u;
            unsigned beyond_five = 0u;
            unsigned tested = 0u;

            for (unsigned pair = 0u; pair < PAIR_COUNT; pair += 1u)
            {
                int64_t *const row = &pair_counts[(size_t)pair * PAIR_BINS];
                // Fast Walsh-Hadamard in place. Afterwards row[m] is the sum over values of the
                // hole indicator times minus one to the parity of value and m.
                for (unsigned span = 1u; span < PAIR_BINS; span <<= 1)
                {
                    for (unsigned start = 0u; start < PAIR_BINS; start += (span << 1))
                    {
                        for (unsigned step = start; step < (start + span); step += 1u)
                        {
                            const int64_t low = row[step];
                            const int64_t high = row[step + span];
                            row[step] = low + high;
                            row[step + span] = low - high;
                        }
                    }
                }

                for (unsigned mask = 1u; mask < PAIR_BINS; mask += 1u)
                {
                    const double score = std::fabs((double)row[mask]) / deviation;
                    tested += 1u;
                    beyond_five += (score > 5.0) ? 1u : 0u;
                    if (score > worst)
                    {
                        worst = score;
                        worst_pair = pair;
                        worst_mask = mask;
                    }
                }
            }

            std::printf("\n  The arrangement of the holes, which nothing above can see\n");
            std::printf("\n  Every figure above is a function of the count multiset alone, so a\n");
            std::printf("  permutation of which value carries which count leaves all of them exactly\n");
            std::printf("  unchanged. Where the holes sit is a separate question and this is it.\n");
            std::printf("\n  %-46s %14llu\n", "holes in the arrangement",
                        (unsigned long long)hole_total);
            std::printf("  %-46s %14.1f\n", "one standard deviation of a coefficient", deviation);
            std::printf("  %-46s %14u\n", "masks tested, every one in any two bytes", tested);
            std::printf("  %-46s %14.4f\n", "largest coefficient, in deviations", worst);
            std::printf("  %-46s %14u\n", "coefficients beyond five deviations", beyond_five);
            std::printf("  %-46s   bytes %u,%u mask %04x\n", "where the largest sits",
                        PAIR_LEFT[worst_pair], PAIR_RIGHT[worst_pair], worst_mask);
            // -------------------------------------------------------------------------------
            // Looking at the holes instead of only testing them.
            //
            // A billion and a half is a small enough set to walk. The Walsh test above asks one
            // question of it, and only about masks confined to two bytes, which is 393,210 of the
            // 4.29 billion masks that exist. These are the questions that need no mask at all:
            // how far apart consecutive holes sit, and how long the runs get. Both have exact
            // predictions and neither is a linear statistic, so a structure that is invisible to
            // a Walsh coefficient can still show here.
            //
            // From the corpus audit posit: nine problems in the anchor-sift work were found by
            // reading output and none by a statistic leaving its range.
            // -------------------------------------------------------------------------------
            {
                const double rate = (double)hole_total / (double)bins;
                uint64_t gap_histogram[24];
                std::memset(gap_histogram, 0, sizeof(gap_histogram));

                uint64_t previous = 0u;
                int seen_one = 0;
                uint64_t longest_hole_run = 0u;
                uint64_t longest_gap_run = 0u;
                uint64_t current_hole_run = 0u;
                uint64_t current_gap_run = 0u;
                uint32_t first_holes[8];
                unsigned first_seen = 0u;

                for (size_t bin = 0u; bin < bins; bin += 1u)
                {
                    const int is_hole =
                        (wide_window[bin].load(std::memory_order_relaxed) == 0u) ? 1 : 0;

                    if (is_hole != 0)
                    {
                        current_hole_run += 1u;
                        current_gap_run = 0u;
                        longest_hole_run =
                            (current_hole_run > longest_hole_run) ? current_hole_run
                                                                  : longest_hole_run;
                        if (first_seen < 8u)
                        {
                            first_holes[first_seen] = (uint32_t)bin;
                            first_seen += 1u;
                        }
                        if (seen_one != 0)
                        {
                            const uint64_t gap = (uint64_t)bin - previous;
                            unsigned slot = 0u;
                            while (((gap >> slot) > 1u) && (slot < 23u))
                            {
                                slot += 1u;
                            }
                            gap_histogram[slot] += 1u;
                        }
                        previous = (uint64_t)bin;
                        seen_one = 1;
                    }
                    else
                    {
                        current_gap_run += 1u;
                        current_hole_run = 0u;
                        longest_gap_run = (current_gap_run > longest_gap_run) ? current_gap_run
                                                                             : longest_gap_run;
                    }
                }

                std::printf("\n  Walking the holes in value order, which needs no mask at all\n");
                std::printf("\n  Gaps between consecutive holes. A hole rate of %.6f scattered at\n",
                            rate);
                std::printf("  random gives geometric gaps, so each bucket has an exact expectation.\n");
                std::printf("\n  %10s %20s %20s %12s\n", "gap", "observed", "expected", "ratio");
                std::printf("  %10s %20s %20s %12s\n", "----------", "--------------------",
                            "--------------------", "------------");

                for (unsigned slot = 0u; slot < 12u; slot += 1u)
                {
                    // A gap lands in this bucket when it is at least 2^slot and below 2^(slot+1).
                    const double low = std::pow(2.0, (double)slot);
                    const double high = std::pow(2.0, (double)slot + 1.0);
                    const double expected =
                        (double)hole_total *
                        (std::pow(1.0 - rate, low - 1.0) - std::pow(1.0 - rate, high - 1.0));
                    std::printf("  %10.0f %20llu %20.6g %12.6f\n", low,
                                (unsigned long long)gap_histogram[slot], expected,
                                (expected > 0.0) ? ((double)gap_histogram[slot] / expected) : 0.0);
                }

                // Runs are the other non-linear reading and the prediction is exact: the longest
                // run of k independent events of probability p over n trials sits near
                // log(n(1-p)) / log(1/p).
                const double hole_run_expected =
                    std::log((double)bins * (1.0 - rate)) / std::log(1.0 / rate);
                const double gap_run_expected =
                    std::log((double)bins * rate) / std::log(1.0 / (1.0 - rate));

                std::printf("\n  %-40s %12llu   expected %8.2f\n", "longest run of holes",
                            (unsigned long long)longest_hole_run, hole_run_expected);
                std::printf("  %-40s %12llu   expected %8.2f\n", "longest run of reached values",
                            (unsigned long long)longest_gap_run, gap_run_expected);

                std::printf("\n  the first eight holes, printed instead of summarised :");
                for (unsigned at = 0u; at < first_seen; at += 1u)
                {
                    std::printf(" %08x", first_holes[at]);
                }
                std::printf("\n");
            }

            // -------------------------------------------------------------------------------
            // How the counts flow around a hole.
            //
            // A hole has no preimages, so nothing flows into it by definition. Its neighbors do,
            // and the question is whether they know about it. Take the count field c(v) on the
            // 32-bit cube and ask, for every single-bit direction, whether c(v) tells you anything
            // about c(v xor d). Under a random function it tells you nothing and the correlation
            // is zero in all thirty-two directions.
            //
            // This uses the whole count and not the hole indicator, so it sees a value with six
            // preimages sitting beside one with none, which the indicator flattens away. It is
            // also not a linear statistic of the indicator, so it is not what the Walsh test
            // measured under another name.
            //
            // The pass is blocked so both members of every pair are resident. Reading the array as
            // 2^16 blocks of 2^16 bytes puts a direction below 2^16 inside one block, and one at
            // or above it between block b and block b xor (d >> 16) at the same offset, so either
            // way two 64 KB blocks are in cache and nothing is a random access to four gigabytes.
            // -------------------------------------------------------------------------------
            {
                const unsigned BLOCK_BITS = 16u;
                const size_t block_span = (size_t)1u << BLOCK_BITS;
                const size_t block_count = bins >> BLOCK_BITS;

                double mean_count = 0.0;
                double mean_square = 0.0;
                for (unsigned count = 0u; count < spectrum_span; count += 1u)
                {
                    const double share = (double)spectrum[count] / (double)bins;
                    mean_count += share * (double)count;
                    mean_square += share * (double)count * (double)count;
                }
                const double variance = mean_square - (mean_count * mean_count);

                std::printf("\n  How the counts flow around a hole, in every single-bit direction\n");
                std::printf("\n  c(v) against c(v xor d) over all %llu values, using the whole count\n",
                            (unsigned long long)bins);
                std::printf("  instead of the hole indicator. A random function correlates at zero\n");
                std::printf("  in every direction. Mean count %.6f, variance %.6f.\n", mean_count,
                            variance);
                std::printf("\n  %10s %18s %14s %14s\n", "direction", "correlation", "in sigma",
                            "verdict");
                std::printf("  %10s %18s %14s %14s\n", "----------", "------------------",
                            "--------------", "--------------");

                // Each pair is counted once from each end, so the estimator sees 2^32 pairs and
                // its standard error is one over the square root of that.
                const double error = 1.0 / std::sqrt((double)bins);
                double worst_flow = 0.0;
                unsigned worst_direction = 0u;

                // Accumulated in integers. A count is under 256 so a product is under 65536, and
                // 2^32 of them cannot exceed 2^48, so a uint64 holds the sum exactly and there is
                // no rounding anywhere in this statistic. Floating point here would be slower and
                // less exact at the same time.
                std::vector<uint64_t> joint_by_direction(32u, 0u);
                {
                    std::vector<std::thread> flow_threads;
                    const unsigned flow_workers = (workers < 32u) ? workers : 32u;
                    for (unsigned slice = 0u; slice < flow_workers; slice += 1u)
                    {
                        flow_threads.push_back(std::thread([&, slice]() {
                            for (unsigned bit = slice; bit < 32u; bit += flow_workers)
                            {
                                const uint64_t direction = (uint64_t)1u << bit;
                                uint64_t joint = 0u;

                                for (size_t block = 0u; block < block_count; block += 1u)
                                {
                                    const size_t partner =
                                        (bit < BLOCK_BITS) ? block
                                                           : (block ^ (direction >> BLOCK_BITS));
                                    const size_t left_base = block << BLOCK_BITS;
                                    const size_t right_base = partner << BLOCK_BITS;

                                    for (size_t offset = 0u; offset < block_span; offset += 1u)
                                    {
                                        const size_t mate = (bit < BLOCK_BITS)
                                                                ? (offset ^ (size_t)direction)
                                                                : offset;
                                        joint += (uint64_t)wide_window[left_base + offset].load(
                                                     std::memory_order_relaxed) *
                                                 (uint64_t)wide_window[right_base + mate].load(
                                                     std::memory_order_relaxed);
                                    }
                                }
                                joint_by_direction[bit] = joint;
                            }
                        }));
                    }
                    for (std::thread &thread : flow_threads)
                    {
                        thread.join();
                    }
                }

                for (unsigned bit = 0u; bit < 32u; bit += 1u)
                {
                    const uint64_t direction = (uint64_t)1u << bit;
                    const double correlation =
                        (variance > 0.0)
                            ? (((double)joint_by_direction[bit] / (double)bins) -
                               (mean_count * mean_count)) /
                                  variance
                            : 0.0;
                    const double sigma = correlation / error;
                    if (std::fabs(sigma) > std::fabs(worst_flow))
                    {
                        worst_flow = sigma;
                        worst_direction = bit;
                    }

                    if ((bit < 4u) || (std::fabs(sigma) > 4.0))
                    {
                        std::printf("  %10llu %18.9f %14.3f %14s\n",
                                    (unsigned long long)direction, correlation, sigma,
                                    (std::fabs(sigma) > 4.0) ? "LOOK" : "flat");
                    }
                }

                std::printf("\n  %-44s bit %u at %.3f sigma\n", "strongest of the 32 directions",
                            worst_direction, worst_flow);
                std::printf("  The largest of 32 standard normals sits near 2.2, so a reading\n");
                std::printf("  under about 3 is the absence of flow instead of a failure to look.\n");
                std::printf("  Directions are printed only where they are the first four or where\n");
                std::printf("  they exceed four sigma, so an empty middle means every one was flat.\n");
            }

            std::printf("\n  The largest of %u independent standard normals sits near 4.6, so a\n",
                        tested);
            std::printf("  reading below about 5 is the absence of linear structure and not a\n");
            std::printf("  failure to look. This runs on the control as well, and the control is\n");
            std::printf("  what says which of those two it is.\n");

            report_full_spectrum(wide_window, bins, hole_total, workers);
        }

        std::printf("\n  Arikan: expected guesses at most (2^H_{1/2} + 1)/2, so the measured\n");
        std::printf("  order one half deficit is worth a factor of %.6f off a blind search of\n",
                    std::pow(2.0, [&]() {
                        // ORDERS[1] is order one half, and going through deficit_term instead of
                        // spelling the sum again is the point: this was a third copy of the same
                        // arithmetic, and the second copy is what put a wrong Shannon figure in
                        // the table above.
                        long double accumulated = 0.0L;
                        for (unsigned count = 0u; count < spectrum_span; count += 1u)
                        {
                            if (spectrum[count] == 0u)
                            {
                                continue;
                            }
                            const long double deviation = ((long double)count - (long double)mean) /
                                                          (long double)mean;
                            accumulated += (long double)spectrum[count] *
                                           deficit_term(ORDERS[1], deviation,
                                                        (count == 0u) ? 1 : 0);
                        }
                        return (double)(std::log1p(accumulated / (long double)bins) /
                                        std::log(2.0L) / -0.5L);
                    }()));
        std::printf("  this window's output. That is the whole of what the non-uniformity buys,\n");
        std::printf("  and it buys it against guessing the output, which is not what mining does.\n");
    }

    // The statistic the pool actually reads. Over a whole nonce range this is exhaustive, so the
    // comparison is against the exact binomial mean instead of against a sample of it.
    std::printf("\n  leading zero bits, protocol order, over the whole enumerated domain\n");
    std::printf("\n  %6s %20s %20s %12s\n", "bits", "nonces at least", "expected", "ratio");
    std::printf("  %6s %20s %20s %12s\n", "------", "--------------------",
                "--------------------", "------------");

    uint64_t at_least = 0u;
    for (unsigned bits = 68u; bits >= 20u; bits -= 4u)
    {
        at_least = 0u;
        for (unsigned found = bits; found <= 256u; found += 1u)
        {
            at_least += merged.leading_zero[found];
        }
        const double expected = (double)domain * std::pow(2.0, -(double)bits);
        std::printf("  %6u %20llu %20.6g %12.6g\n", bits, (unsigned long long)at_least, expected,
                    (double)at_least / expected);
    }

    if (source == SOURCE_SHA256D)
    {
        unsigned deepest = 0u;
        for (unsigned found = 0u; found <= 256u; found += 1u)
        {
            if (merged.leading_zero[found] != 0u)
            {
                deepest = found;
            }
        }
        std::printf("\n  deepest nonce in the whole domain : %u leading zero bits\n", deepest);
        std::printf("\n  That is not a fluctuation and the ratio column above should not be read\n");
        std::printf("  as one. This is block 125552's own header, so its own solved nonce is in\n");
        std::printf("  the domain being enumerated, and a run over every nonce is guaranteed to\n");
        std::printf("  find it. The block's published hash carries 64 leading zero bits, so a\n");
        std::printf("  deepest of %u is the pipeline rediscovering a known 2011 answer from the\n",
                    deepest);
        std::printf("  header alone. It is the strongest external check available here, and it\n");
        std::printf("  is worth more than the rows below it, which are ordinary statistics.\n");
    }
}

} // namespace

int main(int argc, char **argv)
{
    const unsigned domain_bits = (argc > 1) ? (unsigned)std::atoi(argv[1]) : 32u;
    const int with_holes = (argc > 2) ? std::atoi(argv[2]) : 1;
    const int with_controls = (argc > 3) ? std::atoi(argv[3]) : 7;
    // The bit every window starts at. A detector is not told where the units begin, and a slice of
    // the right width at the wrong offset splits every unit across two symbols, so eight phases is
    // eight different symbolisations of the same digest and only one of them has been looked at.
    const unsigned phase = (argc > 4) ? ((unsigned)std::atoi(argv[4]) & 7u) : 0u;
    const uint64_t domain = (uint64_t)1u << domain_bits;
    // This machine runs a desktop while a bench runs on it, so the bench takes what is left instead
    // of everything but one core. See bench_load_limit.h for why one spare core is not enough.
    bench_lower_priority();
    const unsigned workers = bench_worker_count((argc > 5) ? (unsigned)std::atoi(argv[5]) : 0u);
    int on_device = (argc > 6) ? std::atoi(argv[6]) : 0;

#if BENCH_RENYI_HAS_CUDA
    char device_text[256];
    if ((on_device != 0) && (renyi_cuda_available(device_text, sizeof(device_text)) == 0))
    {
        std::printf("\n  [!] no usable device, falling back to the host.\n");
        on_device = 0;
    }
#else
    if (on_device != 0)
    {
        std::printf("\n  [!] this binary was built without the device arm, using the host.\n");
        on_device = 0;
    }
#endif

    std::printf("================================================================\n");
    std::printf("  The Renyi order axis, over the whole nonce domain\n");
    std::printf("================================================================\n");
    std::printf("\n  Every entropy in this workbook so far has been order two, because a collision\n");
    std::printf("  counter is what was to hand. Order is an axis and it has never been swept.\n");
    std::printf("\n  order 0    counts values that never occur          the holes\n");
    std::printf("  order 1/2  governs guessing, by Arikan's bound      the cost of search\n");
    std::printf("  order 1    Shannon\n");
    std::printf("  order 2    collision probability                    everything measured so far\n");
    std::printf("  order inf  the single most over-represented value   the largest bump\n");
    std::printf("\n  Domain: 2^%u nonces of one real header, enumerated instead of sampled.\n",
                domain_bits);
    std::printf("  Function: whole SHA256d over all eighty bytes. A window is a readout of the\n");
    std::printf("  whole 256-bit digest, never a truncation of the computation.\n");
    std::printf("  Threads: %u.\n", workers);
#if BENCH_RENYI_HAS_CUDA
    if (on_device != 0)
    {
        std::printf("  Counting on the device: %s. Every statistic below is still the host's own\n",
                    device_text);
        std::printf("  code reading the same three histograms, computed once.\n");
    }
#endif
    std::printf("  Window phase: %u. Every window starts %u bits into the digest, which is a\n",
                phase, phase);
    std::printf("  different symbolisation of the same 256 bits instead of a different read of\n");
    std::printf("  the same one. Eight phases exist and only phase zero has ever been looked at.\n");

    // Block 125552 by default, the header this tree validates against. Real, and already a known
    // answer. A different one may be supplied as 160 hex characters, which is what the conservation
    // check needs: every measurement in this workbook has been taken on one header, and one header
    // is one corpus. A quantity that does not conserve across headers is a fact about that header.
    uint8_t header[BITCOIN_HEADER_BYTES] = {
        0x01, 0x00, 0x00, 0x00, 0x81, 0xcd, 0x02, 0xab, 0x7e, 0x56, 0x9e, 0x8b, 0xcd, 0x93, 0x17,
        0xe2, 0xfe, 0x99, 0xf2, 0xde, 0x44, 0xd4, 0x9a, 0xb2, 0xb8, 0x85, 0x1b, 0xa4, 0xa3, 0x08,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe3, 0x20, 0xb6, 0xc2, 0xff, 0xfc, 0x8d, 0x75, 0x04,
        0x23, 0xdb, 0x8b, 0x1e, 0xb9, 0x42, 0xae, 0x71, 0x0e, 0x95, 0x1e, 0xd7, 0x97, 0xf7, 0xaf,
        0xfc, 0x88, 0x92, 0xb0, 0xf1, 0xfc, 0x12, 0x2b, 0xc7, 0xf5, 0xd7, 0x4d, 0xf2, 0xb9, 0x44,
        0x1a, 0x42, 0xa1, 0x46, 0x95};

    if (argc > 7)
    {
        const char *const supplied = argv[7];
        size_t given = 0u;
        while (supplied[given] != '\0')
        {
            given += 1u;
        }
        if (given != ((size_t)BITCOIN_HEADER_BYTES * 2u))
        {
            std::printf("\n  [!] a supplied header must be exactly %u hex characters, not %zu.\n",
                        BITCOIN_HEADER_BYTES * 2u, given);
            return 1;
        }
        for (unsigned at = 0u; at < BITCOIN_HEADER_BYTES; at += 1u)
        {
            unsigned value = 0u;
            for (unsigned half = 0u; half < 2u; half += 1u)
            {
                const char digit = supplied[(at * 2u) + half];
                const unsigned nibble =
                    (digit >= '0' && digit <= '9')
                        ? (unsigned)(digit - '0')
                        : ((digit >= 'a' && digit <= 'f')
                               ? (unsigned)(digit - 'a' + 10)
                               : ((digit >= 'A' && digit <= 'F') ? (unsigned)(digit - 'A' + 10)
                                                                 : 16u));
                if (nibble > 15u)
                {
                    std::printf("\n  [!] '%c' is not a hex digit.\n", digit);
                    return 1;
                }
                value = (value << 4) | nibble;
            }
            header[at] = (uint8_t)value;
        }
        std::printf("  Header: supplied, %u bytes read from the command line.\n",
                    BITCOIN_HEADER_BYTES);
    }
    else
    {
        std::printf("  Header: block 125552, the tree's own known answer.\n");
    }

    Job job;
    sha256_header_midstate(&job.midstate, header);
    job.merkle_root_tail = ((uint32_t)header[64] << 24) | ((uint32_t)header[65] << 16) |
                           ((uint32_t)header[66] << 8) | (uint32_t)header[67];
    job.ntime = ((uint32_t)header[68] << 24) | ((uint32_t)header[69] << 16) |
                ((uint32_t)header[70] << 8) | (uint32_t)header[71];
    job.nbits = ((uint32_t)header[72] << 24) | ((uint32_t)header[73] << 16) |
                ((uint32_t)header[74] << 8) | (uint32_t)header[75];

    std::atomic<unsigned char> *wide_window = nullptr;
    if ((with_holes != 0) && (domain_bits >= 24u))
    {
        wide_window = new (std::nothrow) std::atomic<unsigned char>[(size_t)1u << 32];
        if (wide_window == nullptr)
        {
            std::printf("\n  [!] four gigabytes unavailable, the 32-bit window is skipped\n");
        }
    }

    // A bitmask instead of a flag, so a long run need not repeat a control already recorded at
    // this domain. One is the fixed digest, two the balanced one, four the pseudorandom one.
    if ((with_controls & 1) != 0)
    {
        run_source("Control one: a fixed digest, one occupied bin per window at any domain size",
                   job, SOURCE_CONSTANT, domain, workers, phase, on_device, nullptr);
    }
    if ((with_controls & 2) != 0)
    {
        run_source("Control two: the nonce repeated eight times, balanced only at the full domain",
                   job, SOURCE_BALANCED, domain, workers, phase, on_device, nullptr);
    }
    if ((with_controls & 4) != 0)
    {
        // The splitmix control gets the wide window too. Without it the arrangement figure has no
        // null and the number would be uninterpretable on its own, which is the whole lesson of
        // the sigma counts this workbook has had to correct twice.
        run_source("Control three: a splitmix64 chain, a good pseudorandom function", job,
                   SOURCE_SPLITMIX, domain, workers, phase, on_device, wide_window);
    }
    if (with_controls != 7)
    {
        std::printf("\n  [!] controls %d of 7 were run. A control skipped here has to have been\n",
                    with_controls);
        std::printf("      run at this same domain in another pass, or the figures below grade\n");
        std::printf("      against nothing. Skipping all of them grades nothing at all.\n");
    }
    run_source("SHA256d over the whole header, the whole nonce domain enumerated", job,
               SOURCE_SHA256D, domain, workers, phase, on_device, wide_window);

    delete[] wide_window;

    std::printf("\n================================================================\n");
    std::printf("  Reading it\n");
    std::printf("================================================================\n");
    std::printf("\n  Control one must report exactly log2(bins) at every order, which is 8 for the\n");
    std::printf("  byte windows and 16 for the sixteen-bit windows. It was handed a distribution\n");
    std::printf("  on one point, and that answer does not depend on the domain size, so it grades\n");
    std::printf("  the estimator at any run length including a short one.\n");
    std::printf("\n  Control two must report zero at every order, but only where the domain fills\n");
    std::printf("  the windows. At 2^32 it does. Below that a function of k bits cannot fill a\n");
    std::printf("  wider window and the control correctly reports the shortfall instead.\n");
    std::printf("\n  Control three must report the prediction, not zero. An estimator that reports\n");
    std::printf("  flatness for a pseudorandom function is broken in the opposite direction, and\n");
    std::printf("  one control alone cannot tell the two failures apart.\n");
    std::printf("\n  Then SHA256d. The ratio column is the map. A flat plane reads 1.000 at every\n");
    std::printf("  order and every window; a bump reads high at one position and a hole reads at\n");
    std::printf("  order zero. The order two over order one half figure is the parameter-free\n");
    std::printf("  test, because every common scale cancels out of a ratio between orders.\n");
    return 0;
}
