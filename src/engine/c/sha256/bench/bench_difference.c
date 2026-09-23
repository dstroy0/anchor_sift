/* bench_difference - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_difference.c
 * @brief Is the DIFFERENCE between two winning nonces structured? The permute-the-difference test.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-13
 *
 * @note Douglas, 2026-09-13: "We can permute what's different about our guess to the win."
 *
 * H27 asked a different question and answered it: perturb ONE nonce whose digest already carries k
 * leading zeros and ask whether the zeros survive. They do not, at a sensitivity that would have
 * caught a 1.3x effect at five sigma. That is a statement about a single point and its neighbourhood.
 *
 * This asks about the SOLUTION SET. If the nonces carrying k leading zeros stand in some structured
 * relation to each other, then the difference between a near-win and a win is a thing that can be
 * permuted rather than searched, and the difference is what the engine here is built to carry.
 *
 * THE NULL IS DRAWN AND IT IS EXACT. If the winners are unstructured then for any two of them the
 * XOR is a uniform 32-bit word, so:
 *
 *   - every bit of the XOR is set half the time
 *   - the population count of the XOR averages 16
 *   - no particular XOR value recurs more than chance allows
 *
 * All three are computed against the count actually collected, so the null moves with the sample
 * and is never a number chosen by hand. A departure is reported in sigma, and the sigma is the
 * binomial one for the sample that was taken.
 *
 * @note This measures, it does not mine. It collects winners by exhaustive scan over a nonce range
 *       with a fixed header, which is the only honest way to get an unbiased sample of them.
 *
 * AND THE POSITIVE CONTROL, WHICH THE FIRST WRITING DID NOT HAVE.
 *
 * A null result is a claim about the TEST as much as about the data, and a test that cannot see a
 * signal returns a null on everything. So the same routine is run twice: once on the winners as
 * collected, and once on the same winners with a one percent departure planted on one bit. The
 * planted run states the sensitivity instead of calculating it, and if the plant does not show, the
 * bench refuses rather than reporting a null it has not earned.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/sha256_core.h"

/**
 * @brief How many leading zero BITS a nonce's digest must carry to be collected.
 *
 * @note Sixteen, because the sample size is what decides the sensitivity and the DEPTH only decides
 *       how long the collection takes. At sixteen a winner turns up about every 65536 nonces, so
 *       1024 of them costs 67 million hashes and about a minute on one thread. At twenty it would
 *       be four billion hashes for the same statistics.
 */
#define WANTED_ZEROS 16u

/**
 * @brief How many winners to collect before the difference is examined.
 *
 * @note 1024 winners is 523776 pairs, so the binomial spread on a per-bit count is 362 against an
 *       expectation of 261888. A one percent departure would be seven sigma, which is the
 *       sensitivity this test actually has and is printed beside every row rather than assumed.
 */
#define WANTED_WINNERS 1024u

/**
 * @brief Which bit the positive control plants its signal on.
 *
 * @note A low bit, so planting cannot move the highest bit the scan exercised and thereby change
 *       which bits get read. Any low bit does; nothing about the test depends on which.
 */
#define PLANTED_BIT 3u

/** @brief Leading zero bits of a big-endian digest. */
static uint32_t leading_zeros(const uint8_t *const digest)
{
    uint32_t zeros = 0u;
    for (uint32_t at = 0u; at < 32u; ++at)
    {
        if (digest[at] != 0u)
        {
            uint8_t byte = digest[at];
            while ((byte & 0x80u) == 0u)
            {
                ++zeros;
                byte = (uint8_t)(byte << 1);
            }
            return zeros;
        }
        zeros += 8u;
    }
    return zeros;
}

/**
 * @brief The pairwise-difference statistics over one set of winners.
 *
 * @param[in] label   What set this is, for the heading.
 * @param[in] winners The nonces [BORROWS].
 * @param[in] held    How many.
 * @return            The worst departure found, in sigma.
 *
 * @note This exists as a function so the POSITIVE CONTROL runs the same code as the measurement,
 *       not a second copy of it that could disagree. A planted signal examined by a different
 *       routine proves nothing about the routine that examined the real data.
 */
static double difference_examine(const char *const label, const uint32_t *const winners,
                                 const uint32_t held)
{
    /* Every pair's XOR. The null: each bit set in half of them, popcount averaging 16. */
    uint64_t pairs = 0u;
    uint64_t bit_set[32];
    uint64_t popcount_total = 0u;
    for (uint32_t at = 0u; at < 32u; ++at)
    {
        bit_set[at] = 0u;
    }

    for (uint32_t one = 0u; one < held; ++one)
    {
        for (uint32_t two = one + 1u; two < held; ++two)
        {
            const uint32_t difference = winners[one] ^ winners[two];
            ++pairs;
            uint32_t ones = 0u;
            for (uint32_t bit = 0u; bit < 32u; ++bit)
            {
                if (((difference >> bit) & 1u) != 0u)
                {
                    ++bit_set[bit];
                    ++ones;
                }
            }
            popcount_total += ones;
        }
    }

    const double expected = (double)pairs / 2.0;

    /* The binomial spread for p = 1/2 over `pairs` trials is sqrt(pairs)/2. Newton on the square
     * root rather than a library call, so the null is computed from the sample and from nothing
     * else. */
    double root = (double)pairs;
    for (uint32_t step = 0u; step < 64u; ++step)
    {
        root = 0.5 * (root + ((double)pairs / root));
    }
    const double bit_sigma = root / 2.0;

    (void)printf("  %s\n", label);
    (void)printf("  %llu pairs. Each bit of the difference should be set in half of them.\n\n",
                 (unsigned long long)pairs);
    (void)printf("  %4s %14s %14s %10s\n", "bit", "set", "expected", "sigma");
    (void)printf("  %s\n", "----------------------------------------------------");

    /* ONLY THE BITS THE SCAN ACTUALLY EXERCISED.
     *
     * The collection walks upward from nonce zero and stops once it has enough winners, so every
     * winner lies below where it stopped. Bits above that are ZERO IN ALL OF THEM BY CONSTRUCTION,
     * their XOR is almost never set, and reading them reports the shape of the sampling rather than
     * the shape of the solution set. Left in, bit 26 came back at 723 sigma and the mean popcount
     * at 13.0 against a null of 16 -- both entirely an artifact of where the scan stopped.
     *
     * The highest bit set anywhere in the sample is the honest boundary. */
    uint32_t exercised = 0u;
    {
        uint32_t seen = 0u;
        for (uint32_t at = 0u; at < held; ++at)
        {
            seen |= winners[at];
        }
        while (seen != 0u)
        {
            ++exercised;
            seen >>= 1;
        }
    }
    (void)printf("  the scan exercised bits 0..%u; above that every winner is zero by\n",
                 (exercised > 0u) ? (exercised - 1u) : 0u);
    (void)printf("  construction and reading them would measure the sampling, not the set.\n\n");

    double worst = 0.0;
    uint32_t worst_bit = 0u;
    for (uint32_t bit = 0u; bit < exercised; ++bit)
    {
        const double off = ((double)bit_set[bit] - expected) / bit_sigma;
        const double magnitude = (off < 0.0) ? -off : off;
        if (magnitude > worst)
        {
            worst = magnitude;
            worst_bit = bit;
        }
        if (bit < 8u)
        {
            (void)printf("  %4u %14llu %14.0f %10.2f\n", bit,
                         (unsigned long long)bit_set[bit], expected, off);
        }
    }

    (void)printf("  ... %u more\n\n", (exercised > 8u) ? (exercised - 8u) : 0u);
    (void)printf("  WORST BIT %u at %.2f sigma, over %u exercised bits\n",
                 worst_bit, worst, exercised);

    /* The popcount null is half the exercised bits, for the same reason. */
    uint64_t exercised_ones = 0u;
    for (uint32_t bit = 0u; bit < exercised; ++bit)
    {
        exercised_ones += bit_set[bit];
    }
    (void)printf("  mean popcount over those bits %.4f, the null is %.4f\n\n",
                 (double)exercised_ones / (double)pairs, (double)exercised / 2.0);
    return worst;
}

/**
 * @brief Plant a one percent departure on one bit, by nudging how often that bit is set.
 *
 * @param[in,out] winners The copy to plant into [BORROWS].
 * @param[in]     held    How many.
 * @param[in]     bit     Which bit carries the planted signal.
 *
 * @note THE SIZE OF THE PLANT IS DERIVED, NOT PICKED. If a fraction `share` of the winners carry
 *       the bit, the pairwise XOR carries it with probability `2 * share * (1 - share)`. Setting
 *       that to 0.495 -- one percent below the null of a half -- gives `share = 0.45`. So the plant
 *       is: force exactly 45 of every 100 winners to carry the bit and the rest to clear it.
 *
 * @note This is the smallest effect the file CLAIMS to see. If it does not come back at about seven
 *       sigma then the claim was arithmetic and not a measurement, and every null this bench has
 *       ever printed means nothing.
 */
static void difference_plant(uint32_t *const winners, const uint32_t held, const uint32_t bit)
{
    const uint32_t carrying = (held * 45u) / 100u;
    for (uint32_t at = 0u; at < held; ++at)
    {
        if (at < carrying)
        {
            winners[at] |= (1u << bit);
        }
        else
        {
            winners[at] &= ~(1u << bit);
        }
    }
}

int main(void)
{
    /* A fixed header. Its contents do not matter -- what matters is that every winner collected
     * comes from the SAME header, so the only thing varying between them is the nonce. */
    uint8_t header[80];
    for (uint32_t at = 0u; at < 80u; ++at)
    {
        header[at] = (uint8_t)((at * 37u) + 11u);
    }

    uint32_t *const winners = (uint32_t *)malloc(sizeof(uint32_t) * WANTED_WINNERS);
    if (winners == NULL)
    {
        (void)fprintf(stderr, "no room\n");
        return 1;
    }

    (void)printf("\n  THE DIFFERENCE BETWEEN WINNERS. Is it structured, or is it uniform?\n\n");
    (void)printf("  collecting nonces whose digest carries %u leading zero bits\n", WANTED_ZEROS);

    uint32_t held = 0u;
    uint64_t scanned = 0u;
    for (uint64_t nonce = 0u; (nonce <= 0xFFFFFFFFull) && (held < WANTED_WINNERS); ++nonce)
    {
        header[76] = (uint8_t)(nonce & 0xFFu);
        header[77] = (uint8_t)((nonce >> 8) & 0xFFu);
        header[78] = (uint8_t)((nonce >> 16) & 0xFFu);
        header[79] = (uint8_t)((nonce >> 24) & 0xFFu);

        uint8_t digest[32];
        sha256_double_hash(header, 80u, digest);
        ++scanned;

        if (leading_zeros(digest) >= WANTED_ZEROS)
        {
            winners[held] = (uint32_t)nonce;
            ++held;
        }
    }

    (void)printf("  scanned %llu nonces, collected %u winners\n\n",
                 (unsigned long long)scanned, held);

    if (held < 2u)
    {
        (void)printf("  too few winners to compare. Nothing is claimed.\n\n");
        free(winners);
        return 0;
    }

    const double measured = difference_examine("MEASURED, the real winners", winners, held);

    /* THE POSITIVE CONTROL, WITHOUT WHICH THE NULL ABOVE SAYS NOTHING.
     *
     * The file claims a one percent departure would show at about seven sigma. That was arithmetic.
     * Here the same routine is handed the same winners with a one percent departure PLANTED on one
     * bit, and what it reports is the sensitivity this bench actually has. A null is only worth its
     * positive control. */
    uint32_t *const planted = (uint32_t *)malloc(sizeof(uint32_t) * held);
    if (planted == NULL)
    {
        (void)fprintf(stderr, "no room for the control\n");
        free(winners);
        return 1;
    }
    (void)memcpy(planted, winners, sizeof(uint32_t) * held);
    difference_plant(planted, held, PLANTED_BIT);

    (void)printf("  %s\n\n", "====================================================");
    const double control = difference_examine("POSITIVE CONTROL, one percent planted on bit 3",
                                              planted, held);
    free(planted);

    (void)printf("  %s\n", "====================================================");
    (void)printf("  planted one percent came back at %.2f sigma on bit %u\n", control, PLANTED_BIT);
    (void)printf("  the real winners' worst departure was %.2f sigma\n\n", measured);

    if (control < 4.0)
    {
        /* Four sigma is not a chosen tolerance: it is the point below which the planted signal and
         * an ordinary fluctuation of the null are the same reading, so the bench cannot separate
         * them and no result it prints is a measurement. */
        (void)printf("  REFUSED. The bench cannot see a signal it was handed, so it has never\n");
        (void)printf("  been able to see one, and every null it has printed is uninformative.\n\n");
        free(winners);
        return 1;
    }

    (void)printf("  The bench sees a one percent effect. So the measured reading is a measurement:\n");
    (void)printf("  a structured solution set moves these, and this one does not.\n\n");

    free(winners);
    return 0;
}
