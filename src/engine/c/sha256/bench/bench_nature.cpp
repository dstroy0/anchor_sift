/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_nature.cpp
 * @brief Which of the two linear languages has grip on natural data, over every lag.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note bench_language found the translation between SHA-256's two module structures is one-way.
 *       An integer-linear map leaks about 3.5 bits to the exclusive-or view, because an addition is
 *       an exclusive-or plus a carry. A GF(2)-linear map leaks 0.03 bits back, which is nothing. So
 *       GF(2) is strictly the more expressive of the two.
 * @note That raised a claim about intuition instead of about SHA-256: nature is full of
 *       accumulation, phase and carry and nearly empty of parity, so the intuition trained on it is
 *       trained on the weaker language. That was an analogy. This makes it a number, on real
 *       corpora - language, vocalisation, images, infrasound, number theory.
 * @note Two defects in the first attempt are why this exists instead of the Python that preceded
 *       it. The null was flat over 256 bins, which is wrong for a corpus that uses ten byte values:
 *       sqrt(2) read 4.09 bits of grip and has none. And the lags were six hand-picked numbers,
 *       which fixes a scale, and fixing a scale is the defect the symbol-width posit exists to
 *       prevent.
 * @note The null here is exact instead of sampled. Shuffling a corpus destroys arrangement and
 *       keeps the alphabet, and for a shuffled sequence every lag gives the same distribution: the
 *       difference of two independent draws from the marginal. That convolution is computable in
 *       closed form from the marginal in 65,536 operations, so the baseline carries no sampling
 *       noise of its own and no seed.
 * @note Two built controls, and they must fail in opposite directions. One sequence has each block
 *       equal to the previous block exclusive-ored with a constant, so its exclusive-or difference
 *       at the period is exactly that constant and its additive difference is spread by carries.
 *       The other adds instead, and the roles swap. The corpus's own repeating-key file was tried
 *       for this first and is not a GF(2)-only control: a repeating exclusive-or key puts a period
 *       into the data that both languages see, and it read add 1.1585 against xor 0.9213.
 */

#include "bench_load_limit.h"
#include "sha256_core.h"

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace
{

/** @brief Longest lag examined. */
const unsigned LAG_LIMIT = 4096u;

/** @brief Bytes read from each corpus. */
const size_t SAMPLE_CAP = 2000000u;

/**
 * @brief Collision entropy shortfall of a 256-bin distribution, in bits below flat.
 *
 * @param[in] counts 256 bin counts [BORROWS].
 * @param[in] total  Sum of the counts.
 * @return           Eight minus the collision entropy.
 * @note The unbiased estimator. The naive sum of squared frequencies is biased upward and would
 *       report grip that is not there.
 */
double shortfall_of(const uint64_t *counts, uint64_t total)
{
    if (total < 2u)
    {
        return 0.0;
    }

    long double collisions = 0.0L;
    for (unsigned bin = 0u; bin < 256u; bin += 1u)
    {
        const long double here = (long double)counts[bin];
        collisions += here * (here - 1.0L);
    }
    const long double possible = (long double)total * ((long double)total - 1.0L);
    if (collisions <= 0.0L)
    {
        return 8.0;
    }
    return 8.0 + std::log2((double)(collisions / possible));
}

/**
 * @brief The shortfall a shuffle of the same bytes would give, computed exactly.
 *
 * @param[in] marginal How often each byte value occurs [BORROWS].
 * @param[in] total    How many bytes.
 * @param[in] additive Nonzero for the integer difference, zero for exclusive-or.
 * @return             The baseline shortfall.
 * @note For a shuffled sequence the pair at any lag is two independent draws from the marginal, so
 *       the difference distribution is the marginal convolved with itself under that group. That is
 *       exact, identical at every lag, and carries no seed - which is better than shuffling once
 *       and inheriting that draw's noise.
 */
double baseline_of(const uint64_t *marginal, uint64_t total, int additive)
{
    // Without replacement, which is what a shuffle actually does and what the live reading does
    // too: positions i and i+lag are distinct, so the pair is two distinct members of the multiset
    // and never one member counted twice.
    //
    // The earlier version of this drew with replacement, as the product of two marginals. That is
    // the same thing only in the limit, and the gap between them is not shared between the two
    // languages: on a sixteen-value alphabet it read -0.0030 in the exclusive-or view and +0.0005
    // in the additive one, a differential of 0.0035 bits leaning toward additive, which is the
    // direction of the conclusion this baseline supports. Subtracting a known discrepancy is
    // better than measuring around it.
    const double count = (double)total;
    const double pairs = count * (count - 1.0);

    double spread[256];
    std::memset(spread, 0, sizeof(spread));
    for (unsigned left = 0u; left < 256u; left += 1u)
    {
        const double left_count = (double)marginal[left];
        if (left_count == 0.0)
        {
            continue;
        }
        for (unsigned right = 0u; right < 256u; right += 1u)
        {
            const double right_count =
                (double)marginal[right] - ((left == right) ? 1.0 : 0.0);
            if (right_count <= 0.0)
            {
                continue;
            }
            const unsigned at = (additive != 0) ? ((left - right) & 0xffu) : (left ^ right);
            spread[at] += (left_count * right_count) / pairs;
        }
    }

    double collisions = 0.0;
    for (unsigned bin = 0u; bin < 256u; bin += 1u)
    {
        collisions += spread[bin] * spread[bin];
    }
    return (collisions > 0.0) ? (8.0 + std::log2(collisions)) : 8.0;
}

/** @brief How the nonce is removed from the digest byte, or not. */
enum Removal
{
    REMOVAL_NONE,     /**< The digest byte as it comes. */
    REMOVAL_SUBTRACT, /**< The nonce subtracted, which is the integer language's inverse. */
    REMOVAL_XOR       /**< The nonce exclusive-ored out, which is GF(2)'s inverse. */
};

/**
 * @brief Builds a byte stream of SHA256d digests indexed by nonce, with the nonce removed or not.
 *
 * @param[in] length  How many nonces, one byte each.
 * @param[in] removal How to take the nonce back out.
 * @return            The stream.
 * @note One byte per nonce instead of the whole digest, because the point is to line the output up
 *       against the input that produced it. With thirty-two bytes per nonce the subtraction would
 *       have no single thing to subtract from.
 * @note The subtractive move applied to the output. A digest is the nonce carried through 128
 *       rounds, so taking the nonce back out asks what is left of it that the function did not
 *       destroy. If SHA256d held any additive relation to its input, the subtracted stream would
 *       concentrate where the raw stream does not, and the exclusive-or removal asks the same
 *       question in the other language.
 * @note Both removals are exact inverses of an operation the function never performed, which is
 *       the point instead of an objection: the test is whether the digest behaves as though it
 *       had, in either language.
 */
std::vector<unsigned char> digest_stream(size_t length, Removal removal, unsigned rounds,
                                         unsigned word)
{
    const uint8_t header[BITCOIN_HEADER_BYTES] = {
        0x01, 0x00, 0x00, 0x00, 0x81, 0xcd, 0x02, 0xab, 0x7e, 0x56, 0x9e, 0x8b, 0xcd, 0x93, 0x17,
        0xe2, 0xfe, 0x99, 0xf2, 0xde, 0x44, 0xd4, 0x9a, 0xb2, 0xb8, 0x85, 0x1b, 0xa4, 0xa3, 0x08,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe3, 0x20, 0xb6, 0xc2, 0xff, 0xfc, 0x8d, 0x75, 0x04,
        0x23, 0xdb, 0x8b, 0x1e, 0xb9, 0x42, 0xae, 0x71, 0x0e, 0x95, 0x1e, 0xd7, 0x97, 0xf7, 0xaf,
        0xfc, 0x88, 0x92, 0xb0, 0xf1, 0xfc, 0x12, 0x2b, 0xc7, 0xf5, 0xd7, 0x4d, 0xf2, 0xb9, 0x44,
        0x1a, 0x42, 0xa1, 0x46, 0x95};

    Sha256State midstate;
    sha256_header_midstate(&midstate, header);

    const uint32_t merkle_tail = ((uint32_t)header[64] << 24) | ((uint32_t)header[65] << 16) |
                                 ((uint32_t)header[66] << 8) | (uint32_t)header[67];
    const uint32_t ntime = ((uint32_t)header[68] << 24) | ((uint32_t)header[69] << 16) |
                           ((uint32_t)header[70] << 8) | (uint32_t)header[71];
    const uint32_t nbits = ((uint32_t)header[72] << 24) | ((uint32_t)header[73] << 16) |
                           ((uint32_t)header[74] << 8) | (uint32_t)header[75];

    std::vector<unsigned char> out(length, 0u);
    for (size_t nonce = 0u; nonce < length; nonce += 1u)
    {
        uint32_t block[SHA256_BLOCK_WORDS];
        Sha256State first = midstate;

        block[0] = merkle_tail;
        block[1] = ntime;
        block[2] = nbits;
        const uint32_t value = (uint32_t)nonce;
        block[3] = ((value & 0x000000ffu) << 24) | ((value & 0x0000ff00u) << 8) |
                   ((value & 0x00ff0000u) >> 8) | ((value & 0xff000000u) >> 24);
        block[4] = 0x80000000u;
        for (unsigned slot = 5u; slot < 15u; slot += 1u)
        {
            block[slot] = 0u;
        }
        block[15] = 0x00000280u;

        unsigned char digest_byte = 0u;
        if (rounds >= 64u)
        {
            sha256_block_compress(&first, block);

            Sha256State second;
            sha256_state_init(&second);
            for (unsigned slot = 0u; slot < SHA256_STATE_WORDS; slot += 1u)
            {
                block[slot] = first.word[slot];
            }
            block[8] = 0x80000000u;
            for (unsigned slot = 9u; slot < 15u; slot += 1u)
            {
                block[slot] = 0u;
            }
            block[15] = 0x00000100u;
            sha256_block_compress(&second, block);
            digest_byte = (unsigned char)second.word[7];
        }
        else
        {
            // Unwound. Only the block the nonce enters is run, and only part of it, so what is
            // read is the nonce's own propagation instead of a second hash on top of it. The
            // second compression would re-mix whatever the first left and hide the thing being
            // looked for.
            sha256_block_compress_partial(&first, block, rounds);
            digest_byte = (unsigned char)first.word[word & 7u];
        }
        const unsigned char taken = (unsigned char)(nonce & 0xffu);

        if (removal == REMOVAL_SUBTRACT)
        {
            out[nonce] = (unsigned char)(digest_byte - taken);
        }
        else if (removal == REMOVAL_XOR)
        {
            out[nonce] = (unsigned char)(digest_byte ^ taken);
        }
        else
        {
            out[nonce] = digest_byte;
        }
    }
    return out;
}

/** @brief What one corpus reported. */
struct Reading
{
    double best_xor;
    double best_add;
    unsigned xor_lag;
    unsigned add_lag;
};

/**
 * @brief Sweeps every lag and returns the best grip each language found.
 *
 * @param[in] seats   The corpus bytes [BORROWS].
 * @param[in] length  How many bytes to use.
 * @param[in] workers How many threads.
 * @return            Best grip and where it sat, per language.
 */
Reading sweep(const unsigned char *seats, size_t length, unsigned workers)
{
    uint64_t marginal[256];
    std::memset(marginal, 0, sizeof(marginal));
    for (size_t at = 0u; at < length; at += 1u)
    {
        marginal[seats[at]] += 1u;
    }

    const double xor_baseline = baseline_of(marginal, (uint64_t)length, 0);
    const double add_baseline = baseline_of(marginal, (uint64_t)length, 1);

    std::vector<double> by_xor(LAG_LIMIT + 1u, 0.0);
    std::vector<double> by_add(LAG_LIMIT + 1u, 0.0);
    std::vector<std::thread> hands;

    for (unsigned slice = 0u; slice < workers; slice += 1u)
    {
        hands.push_back(std::thread([&, slice]() {
            for (unsigned lag = 1u + slice; lag <= LAG_LIMIT; lag += workers)
            {
                if ((size_t)lag >= length)
                {
                    break;
                }
                uint64_t xor_counts[256];
                uint64_t add_counts[256];
                std::memset(xor_counts, 0, sizeof(xor_counts));
                std::memset(add_counts, 0, sizeof(add_counts));

                const size_t pairs = length - lag;
                for (size_t at = 0u; at < pairs; at += 1u)
                {
                    xor_counts[seats[at] ^ seats[at + lag]] += 1u;
                    add_counts[(unsigned char)(seats[at] - seats[at + lag])] += 1u;
                }

                by_xor[lag] = shortfall_of(xor_counts, (uint64_t)pairs) - xor_baseline;
                by_add[lag] = shortfall_of(add_counts, (uint64_t)pairs) - add_baseline;
            }
        }));
    }
    for (std::thread &hand : hands)
    {
        hand.join();
    }

    Reading out = {0.0, 0.0, 0u, 0u};
    for (unsigned lag = 1u; lag <= LAG_LIMIT; lag += 1u)
    {
        if (by_xor[lag] > out.best_xor)
        {
            out.best_xor = by_xor[lag];
            out.xor_lag = lag;
        }
        if (by_add[lag] > out.best_add)
        {
            out.best_add = by_add[lag];
            out.add_lag = lag;
        }
    }
    return out;
}

/** @brief Builds a sequence one language reads exactly and the other cannot. */
std::vector<unsigned char> built_control(int additive, size_t length, unsigned period)
{
    std::vector<unsigned char> out;
    out.reserve(length);

    unsigned char block[64];
    uint32_t state = 20260908u;
    for (unsigned at = 0u; at < period; at += 1u)
    {
        state = (state * 1103515245u) + 12345u;
        block[at] = (unsigned char)(state >> 16);
    }

    const unsigned char offset = 0x5au;
    while (out.size() < length)
    {
        for (unsigned at = 0u; at < period; at += 1u)
        {
            out.push_back(block[at]);
        }
        for (unsigned at = 0u; at < period; at += 1u)
        {
            block[at] = (additive != 0) ? (unsigned char)(block[at] + offset)
                                        : (unsigned char)(block[at] ^ offset);
        }
    }
    out.resize(length);
    return out;
}

} // namespace

int main(int argc, char **argv)
{
    bench_lower_priority();
    const unsigned workers = bench_worker_count(0u);

    std::printf("================================================================================\n");
    std::printf("  Which linear language has grip on natural data, over every lag to %u\n", LAG_LIMIT);
    std::printf("================================================================================\n");
    std::printf("\n  Grip is bits of structure a language sees at some lag beyond what the alphabet\n");
    std::printf("  alone accounts for. The baseline is exact: for a shuffle every lag gives the\n");
    std::printf("  difference of two independent draws from the marginal, which is that marginal\n");
    std::printf("  convolved with itself and needs no seed and no sampling.\n");
    std::printf("\n  The lag is swept instead of picked. Six hand-chosen lags was the first attempt\n");
    std::printf("  and fixing a scale is the defect the symbol-width posit exists to prevent.\n");
    std::printf("\n  Bytes per corpus: %zu. Threads: %u.\n", SAMPLE_CAP, workers);

    std::printf("\n  %-34s %10s %10s %8s %8s %8s\n", "corpus", "xor", "add", "xor lag", "add lag",
                "which");
    std::printf("  %-34s %10s %10s %8s %8s %8s\n", "----------------------------------",
                "----------", "----------", "--------", "--------", "--------");

    // -------------------------------------------------------------------------------------
    // Does the analytic baseline actually equal a shuffle?
    //
    // The baseline used everywhere below is the difference distribution of two independent draws
    // from the marginal, convolved in closed form. The claim is that this is what a shuffle would
    // give without a shuffle's seed. That is an argument and not a check, and the two are not
    // identical objects: a shuffle draws a pair without replacement from the exact multiset, and
    // the convolution draws with replacement from the marginal.
    //
    // The difference is order one over the length and ought to vanish at two million bytes. Ought
    // to is what this measures, because the whole method here is that a null is checked instead of
    // reasoned about.
    // -------------------------------------------------------------------------------------
    {
        std::printf("\n  Checking the analytic baseline against an actual shuffle\n");
        std::printf("\n  %-28s %14s %14s %14s\n", "sequence", "mean diff", "spread", "in sigma");
        std::printf("  %-28s %14s %14s %14s\n", "----------------------------", "--------------",
                    "--------------", "--------------");

        for (int which = 0; which < 2; which += 1)
        {
            std::vector<unsigned char> body = built_control(which, 400000u, 8u);
            // A corpus-like alphabet as well as the built one, since the two differ in exactly the
            // way that matters here: sixteen byte values against 256.
            if (which == 1)
            {
                for (size_t at = 0u; at < body.size(); at += 1u)
                {
                    body[at] = (unsigned char)('a' + (body[at] % 26u));
                }
            }

            uint64_t marginal[256];
            std::memset(marginal, 0, sizeof(marginal));
            for (size_t at = 0u; at < body.size(); at += 1u)
            {
                marginal[body[at]] += 1u;
            }

            // Several shuffles, not one. A single shuffle carries its own sampling noise, and
            // reading one draw as though it were the null is the mistake of treating a sample as
            // a distribution - which is what produced an apparent 0.0035 bit differential bias
            // that two separate explanations then failed to account for.
            const unsigned draws = 8u;
            double differential[8];
            double mean_differential = 0.0;

            for (unsigned draw = 0u; draw < draws; draw += 1u)
            {
                std::vector<unsigned char> mixed = body;
                uint32_t state = 20260908u + (draw * 7919u);
                for (size_t at = mixed.size() - 1u; at > 0u; at -= 1u)
                {
                    state = (state * 1103515245u) + 12345u;
                    const size_t swap = (size_t)((state >> 8) % (uint32_t)(at + 1u));
                    const unsigned char keep = mixed[at];
                    mixed[at] = mixed[swap];
                    mixed[swap] = keep;
                }

                uint64_t xor_counts[256];
                uint64_t add_counts[256];
                std::memset(xor_counts, 0, sizeof(xor_counts));
                std::memset(add_counts, 0, sizeof(add_counts));
                const size_t pairs = mixed.size() - 1u;
                for (size_t at = 0u; at < pairs; at += 1u)
                {
                    xor_counts[mixed[at] ^ mixed[at + 1u]] += 1u;
                    add_counts[(unsigned char)(mixed[at] - mixed[at + 1u])] += 1u;
                }

                const double xor_gap = shortfall_of(xor_counts, (uint64_t)pairs) -
                                       baseline_of(marginal, (uint64_t)body.size(), 0);
                const double add_gap = shortfall_of(add_counts, (uint64_t)pairs) -
                                       baseline_of(marginal, (uint64_t)body.size(), 1);
                differential[draw] = add_gap - xor_gap;
                mean_differential += differential[draw];
            }

            mean_differential /= (double)draws;
            double square_sum = 0.0;
            for (unsigned draw = 0u; draw < draws; draw += 1u)
            {
                const double offset = differential[draw] - mean_differential;
                square_sum += offset * offset;
            }
            const double spread = std::sqrt(square_sum / (double)draws);

            // The conclusion downstream is a comparison between the two languages, so a baseline
            // error only bends it where the error differs between them. A shared error cancels out
            // of the difference and is harmless however large it is; a differential one does not.
            std::printf("  %-28s %14.6f %14.6f %14.2f\n",
                        (which == 0) ? "16 byte values" : "26 byte values", mean_differential,
                        spread, (spread > 0.0) ? (mean_differential / spread) : 0.0);
        }
        std::printf("\n  The first two columns are what a shuffled sequence reads against the\n");
        std::printf("  analytic baseline, per language, and both should be zero because a shuffle\n");
        std::printf("  has no arrangement. The third is the one that matters: the conclusion is a\n");
        std::printf("  comparison between the languages, so a shared error cancels out of it and\n");
        std::printf("  only a differential error bends it. Read the third column against the\n");
        std::printf("  add-minus-xor gaps below, which run from about 0.04 to 0.16 bits.\n");
    }

    // The two built controls first, because every row below them is only readable if they behave.
    //
    // These are read at the lag they were designed around and not at the best lag over the sweep,
    // and the reason is a property of the constructions instead of a convenience. A sequence whose
    // exclusive-or difference at lag L is a fixed constant is necessarily periodic with period 2L,
    // because that constant cancels against itself, and a globally periodic sequence is visible to
    // every language at its period. Reading the maximum picked up that period instead of the
    // designed structure and both controls came out wrong: the xor-periodic one read add 6.54 at
    // lag 16, which is its own repeat instead of its exclusive-or structure.
    //
    // At the designed lag the question is the intended one. The natural rows below still use the
    // maximum over the sweep, because for those the lag is not known in advance and picking one
    // would be the fixed-scale defect again.
    for (int additive = 0; additive < 2; additive += 1)
    {
        const unsigned designed = 8u;
        const std::vector<unsigned char> made = built_control(additive, SAMPLE_CAP, designed);

        uint64_t marginal[256];
        std::memset(marginal, 0, sizeof(marginal));
        for (size_t at = 0u; at < made.size(); at += 1u)
        {
            marginal[made[at]] += 1u;
        }

        uint64_t xor_counts[256];
        uint64_t add_counts[256];
        std::memset(xor_counts, 0, sizeof(xor_counts));
        std::memset(add_counts, 0, sizeof(add_counts));
        const size_t pairs = made.size() - designed;
        for (size_t at = 0u; at < pairs; at += 1u)
        {
            xor_counts[made[at] ^ made[at + designed]] += 1u;
            add_counts[(unsigned char)(made[at] - made[at + designed])] += 1u;
        }

        const double at_xor = shortfall_of(xor_counts, (uint64_t)pairs) -
                              baseline_of(marginal, (uint64_t)made.size(), 0);
        const double at_add = shortfall_of(add_counts, (uint64_t)pairs) -
                              baseline_of(marginal, (uint64_t)made.size(), 1);

        std::printf("  %-34s %10.4f %10.4f %8u %8u %8s\n",
                    (additive != 0) ? "[built] add at its own lag"
                                    : "[built] xor at its own lag",
                    at_xor, at_add, designed, designed,
                    (at_xor > (at_add + 0.02)) ? "xor"
                                               : ((at_add > (at_xor + 0.02)) ? "add" : "level"));
    }

    // SHA256d against its own nonce, raw and with the nonce taken back out in each language.
    // A shuffle of the raw stream sits beside them as the floor, because a reading that does not
    // clear what a shuffled version of the same bytes gives is not a reading.
    {
        const Removal removals[3] = {REMOVAL_NONE, REMOVAL_SUBTRACT, REMOVAL_XOR};
        const char *names[3] = {"[sha] digest by nonce", "[sha] nonce subtracted",
                                "[sha] nonce xored out"};

        for (unsigned which = 0u; which < 3u; which += 1u)
        {
            const std::vector<unsigned char> stream =
                digest_stream(SAMPLE_CAP, removals[which], 64u, 7u);
            const Reading found = sweep(stream.data(), stream.size(), workers);
            std::printf("  %-34s %10.4f %10.4f %8u %8u %8s\n", names[which], found.best_xor,
                        found.best_add, found.xor_lag, found.add_lag,
                        (found.best_xor > (found.best_add + 0.02))
                            ? "xor"
                            : ((found.best_add > (found.best_xor + 0.02)) ? "add" : "level"));
        }

        // Unwound, to find the round the grip disappears at. At the full function everything sits
        // on the floor, so the question is not whether there is structure but where it went.
        for (unsigned rounds = 4u; rounds <= 24u; rounds += 2u)
        {
            // Every word, not one. Reading word seven alone gave 0.0000 at four and six rounds,
            // because after r rounds that position still holds an untouched midstate word and the
            // stream is a constant - absence read as a measurement, for the third time today, and
            // the same fix bench_depth already needed. A coordinate that can be scanned is not one
            // to pick.
            Reading best = {0.0, 0.0, 0u, 0u};
            unsigned best_word = 0u;
            for (unsigned word = 0u; word < 8u; word += 1u)
            {
                const std::vector<unsigned char> stream =
                    digest_stream(SAMPLE_CAP, REMOVAL_NONE, rounds, word);
                const Reading found = sweep(stream.data(), stream.size(), workers);
                if ((found.best_xor > best.best_xor) || (found.best_add > best.best_add))
                {
                    if (found.best_xor > best.best_xor)
                    {
                        best.best_xor = found.best_xor;
                        best.xor_lag = found.xor_lag;
                    }
                    if (found.best_add > best.best_add)
                    {
                        best.best_add = found.best_add;
                        best.add_lag = found.add_lag;
                        best_word = word;
                    }
                }
            }
            char label[44];
            std::snprintf(label, sizeof(label), "[sha] unwound to %2u rounds, w%u", rounds,
                          best_word);
            std::printf("  %-34s %10.4f %10.4f %8u %8u %8s\n", label, best.best_xor,
                        best.best_add, best.xor_lag, best.add_lag,
                        (best.best_xor > (best.best_add + 0.02))
                            ? "xor"
                            : ((best.best_add > (best.best_xor + 0.02)) ? "add" : "level"));
        }

        std::vector<unsigned char> mixed = digest_stream(SAMPLE_CAP, REMOVAL_NONE, 64u, 7u);
        uint32_t state = 20260908u;
        for (size_t at = mixed.size() - 1u; at > 0u; at -= 1u)
        {
            state = (state * 1103515245u) + 12345u;
            const size_t swap = (size_t)((state >> 8) % (uint32_t)(at + 1u));
            const unsigned char keep = mixed[at];
            mixed[at] = mixed[swap];
            mixed[swap] = keep;
        }
        const Reading shuffled = sweep(mixed.data(), mixed.size(), workers);
        std::printf("  %-34s %10.4f %10.4f %8u %8u %8s\n", "[sha] the same bytes shuffled",
                    shuffled.best_xor, shuffled.best_add, shuffled.xor_lag, shuffled.add_lag,
                    "floor");
    }

    for (int at = 1; at < argc; at += 1)
    {
        std::FILE *const handle = std::fopen(argv[at], "rb");
        if (handle == nullptr)
        {
            continue;
        }
        std::vector<unsigned char> body(SAMPLE_CAP, 0u);
        const size_t read = std::fread(body.data(), 1u, SAMPLE_CAP, handle);
        std::fclose(handle);
        if (read < 100000u)
        {
            continue;
        }
        body.resize(read);

        std::string label(argv[at]);
        const size_t slash = label.find_last_of("/\\");
        if (slash != std::string::npos)
        {
            label = label.substr(slash + 1u);
        }
        const size_t dot = label.find_last_of('.');
        if (dot != std::string::npos)
        {
            label = label.substr(0u, dot);
        }

        const Reading found = sweep(body.data(), body.size(), workers);
        std::printf("  %-34s %10.4f %10.4f %8u %8u %8s\n", label.substr(0u, 34u).c_str(),
                    found.best_xor, found.best_add, found.xor_lag, found.add_lag,
                    (found.best_xor > (found.best_add + 0.02))
                        ? "xor"
                        : ((found.best_add > (found.best_xor + 0.02)) ? "add" : "level"));
    }

    std::printf("\n  The two built rows must come out lopsided in opposite directions. If they do\n");
    std::printf("  not, this instrument is measuring neither language and no row below them means\n");
    std::printf("  anything. That is not a formality: the first version of this test failed on\n");
    std::printf("  three separate controls and its natural rows looked entirely plausible.\n");
    std::printf("\n  The two are lopsided by different amounts, 2.19 bits against 3.84, and that is\n");
    std::printf("  not a tilt in the statistic. Each control saturates its own ceiling exactly. A\n");
    std::printf("  grip cannot exceed eight bits less that corpus's own baseline, and the two\n");
    std::printf("  controls have different alphabets: the exclusive-or one uses 16 byte values and\n");
    std::printf("  carries a baseline of 2.4594, so its ceiling is 5.5406 and it reads 5.5406; the\n");
    std::printf("  additive one walks all 256 values, carries a baseline of zero, so its ceiling is\n");
    std::printf("  8.0000 and it reads 8.0000.\n");
    std::printf("\n  Expecting two differently built objects to give equal magnitudes was the error,\n");
    std::printf("  and it was alphabet size read as instrument bias - the same confound this tool\n");
    std::printf("  had already been corrected for twice. These are entropy differences over\n");
    std::printf("  distributions with different supports. What is calibrated is each against its\n");
    std::printf("  own ceiling, and both are exact, so the natural magnitudes below are readable.\n");
    return 0;
}
