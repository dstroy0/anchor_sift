/* MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_ancorae_entropy.c
 * @brief What the candidate count estimator is, measured against published estimators of the same
 *        quantity on sources whose answer is known in advance.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-01
 *
 * @note The claim under test. A candidate count divided by the number of positions estimates the
 *       collision probability, so the negative log of it estimates Renyi entropy of order two. That
 *       was measured against corpora whose entropy was computed from their own histograms, which
 *       shows the arithmetic is consistent and says nothing about whether the estimator is any good.
 *       Here the sources are generated from distributions written down first, so the true value is
 *       known before the data exists and every estimator can be scored against it.
 * @note What is being compared. Three published estimators of the collision probability and the two
 *       forms of the candidate count estimator, all of them estimating the same number, all scored
 *       by bias and root mean square error over repeated trials. A fourth quantity, min entropy, is
 *       reported separately because it is a different property and cannot be scored on this scale.
 * @note Counts, not cycles. Nothing here is timed and no row is a performance claim.
 */
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"

// Sources are drawn from this so a run reproduces exactly. Held to RFC 6234's vectors by its own
// self test
#include "mmgr_sha256.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/**
 * @brief Symbols in the alphabet every source here draws from.
 */
#define ALPHABET 256u

/**
 * @brief The longest corpus any trial builds.
 */
#define MAX_CORPUS 16384u

/**
 * @brief How many independent corpora each row averages over.
 *
 * @note Bias and root mean square error are properties of an estimator and not of one sample, so a
 *       single corpus cannot report either. Each trial draws a fresh corpus from the same
 *       distribution under a different salt.
 */
#define TRIALS 64u

/**
 * @brief How many positions the subsampled estimators look at.
 *
 * @note Sixty four, matching the needle sample count the sift bench uses, so the variance reported
 *       here is the variance that bench actually runs at.
 */
#ifndef PROBE_SAMPLES
#define PROBE_SAMPLES 64u
#endif

/**
 * @brief One source, as a distribution written down before any data exists.
 *
 * @note The point of naming the distribution instead of measuring a corpus. An estimator scored
 *       against a histogram of the same corpus it was computed from is scored against itself, and
 *       every estimator here would pass. Scored against the distribution that generated the corpus,
 *       an estimator can be wrong, which is the only condition under which the score means anything.
 */
typedef struct
{
    const char *name;
    double weight[ALPHABET];
    unsigned levels;
} Source;

/**
 * @brief Builds a source that is uniform over the first @p levels symbols.
 *
 * @param[out] source Receives the distribution [BORROWS].
 * @param[in]  name   Text naming it [BORROWS].
 * @param[in]  levels How many symbols carry weight.
 * @note Collision probability is exactly one over levels here, so the true answer is log2(levels)
 *       bits with no approximation anywhere in it.
 */
static void source_uniform(Source *source, const char *name, unsigned levels)
{
    source->name = name;
    source->levels = levels;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        source->weight[symbol] = (symbol < levels) ? (1.0 / (double)levels) : 0.0;
    }
}

/**
 * @brief Builds a Zipf source over the whole alphabet at exponent @p exponent.
 *
 * @param[out] source   Receives the distribution [BORROWS].
 * @param[in]  name     Text naming it [BORROWS].
 * @param[in]  exponent The Zipf exponent, where larger concentrates more weight on rank one.
 * @note The regime the cost tables were built for. A Zipf source has a long tail and a heavy head,
 *       which is where a plug in estimator's bias is largest, so it is the case that separates the
 *       estimators rather than the one that flatters them.
 */
static void source_zipf(Source *source, const char *name, double exponent)
{
    double total = 0.0;

    source->name = name;
    source->levels = ALPHABET;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        source->weight[symbol] = 1.0 / pow((double)(symbol + 1u), exponent);
        total += source->weight[symbol];
    }
    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        source->weight[symbol] /= total;
    }
}

/**
 * @brief Builds a two symbol source where the first carries @p heavy of the weight.
 *
 * @param[out] source Receives the distribution [BORROWS].
 * @param[in]  name   Text naming it [BORROWS].
 * @param[in]  heavy  Probability of the first symbol.
 * @note The low entropy end. At heavy = 0.99 the collision probability is above 0.98 and every
 *       estimator is squeezed against the ceiling, which is where the candidate count estimator was
 *       predicted to saturate.
 */
static void source_two_point(Source *source, const char *name, double heavy)
{
    source->name = name;
    source->levels = 2u;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        source->weight[symbol] = 0.0;
    }
    source->weight[0] = heavy;
    source->weight[1] = 1.0 - heavy;
}

/**
 * @brief Returns the collision probability of a source, from its distribution.
 *
 * @param[in] source The distribution [BORROWS].
 * @return           The sum of the squared probabilities.
 * @note The truth every estimator below is scored against. It is computed from the weights and never
 *       from a corpus, so no corpus can flatter it.
 */
static double true_collision(const Source *source)
{
    double total = 0.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        total += source->weight[symbol] * source->weight[symbol];
    }
    return total;
}

/**
 * @brief Draws @p length symbols from @p source into @p into.
 *
 * @param[in]  source The distribution to draw from [BORROWS].
 * @param[out] into   Storage to fill [BORROWS].
 * @param[in]  length How many symbols.
 * @param[in]  salt   Which stream to draw from, so trials differ.
 * @note Inverse transform sampling on a uniform built from four bytes of SHA-256 counter mode output.
 *       The generator is the one held to published vectors elsewhere in this tree, so a source that
 *       comes out wrong is a defect here and not in the randomness.
 */
static void draw_from(const Source *source, uint8_t *into, size_t length, uint64_t salt)
{
    uint8_t seed[16];
    uint8_t digest[MMGR_SHA256_BYTES];
    size_t written = 0u;
    unsigned spent = MMGR_SHA256_BYTES;
    uint64_t block = 0u;

    while (written < length)
    {
        if ((spent + 4u) > MMGR_SHA256_BYTES)
        {
            for (unsigned index = 0u; index < 8u; index++)
            {
                // Explicit cast narrows one byte out of each 64 bit word, most significant first
                seed[index] = (uint8_t)((salt >> (56u - (index * 8u))) & 0xFFu);
                seed[8u + index] = (uint8_t)((block >> (56u - (index * 8u))) & 0xFFu);
            }
            mmgr_sha256(seed, sizeof seed, digest);
            spent = 0u;
            block++;
        }

        const uint32_t raw = ((uint32_t)digest[spent] << 24) | ((uint32_t)digest[spent + 1u] << 16) |
                             ((uint32_t)digest[spent + 2u] << 8) | (uint32_t)digest[spent + 3u];
        const double point = (double)raw / 4294967296.0;
        double running = 0.0;
        unsigned chosen = 0u;

        spent += 4u;

        for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
        {
            running += source->weight[symbol];
            if (point < running)
            {
                chosen = symbol;
                break;
            }
        }
        into[written] = (uint8_t)chosen;
        written++;
    }
}

/**
 * @brief Counts each symbol in a corpus.
 *
 * @param[in]  corpus Symbols to count [BORROWS].
 * @param[in]  length How many.
 * @param[out] counts One counter per symbol [BORROWS].
 */
static void tally(const uint8_t *corpus, size_t length, uint32_t *counts)
{
    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        counts[symbol] = 0u;
    }
    for (size_t index = 0u; index < length; index++)
    {
        counts[corpus[index]]++;
    }
}

/**
 * @brief The plug in estimate of the collision probability.
 *
 * @param[in] counts One counter per symbol [BORROWS].
 * @param[in] length How many symbols the corpus held.
 * @return           The sum of the squared empirical frequencies.
 * @note The maximum likelihood estimator, and the obvious one. Its expectation is the true collision
 *       probability plus (1 - true) / length, so it is biased upward and the bias is largest on a
 *       short corpus over a flat source. It needs a histogram, which needs the alphabet enumerated.
 */
static double estimate_plug_in(const uint32_t *counts, size_t length)
{
    double total = 0.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        const double share = (double)counts[symbol] / (double)length;

        total += share * share;
    }
    return total;
}

/**
 * @brief The unbiased estimate of the collision probability.
 *
 * @param[in] counts One counter per symbol [BORROWS].
 * @param[in] length How many symbols the corpus held.
 * @return           The proportion of ordered pairs of distinct positions that agree.
 * @note The standard U statistic. Counting pairs of distinct positions instead of squaring
 *       frequencies removes the plug in estimator's bias exactly, since a position is never paired
 *       with itself. Solving the plug in estimator's known bias for the true value gives the same
 *       expression, so the first order bias correction and the U statistic are one estimator and not
 *       two.
 */
static double estimate_unbiased(const uint32_t *counts, size_t length)
{
    double pairs = 0.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        const double held = (double)counts[symbol];

        pairs += held * (held - 1.0);
    }
    return pairs / ((double)length * ((double)length - 1.0));
}

/**
 * @brief The candidate count estimate, counting the probe position's own match.
 *
 * @param[in] corpus  Symbols to probe [BORROWS].
 * @param[in] length  How many.
 * @param[in] samples How many probe positions to average over.
 * @return            The mean candidate count over the corpus length.
 * @note What a one point anchor measures. A probe position is chosen, every position carrying the
 *       same symbol is counted, and the count is divided by the corpus length. No histogram is built
 *       and the alphabet is never enumerated, so this is the only estimator here that a domain with
 *       an unenumerable alphabet admits.
 * @note Averaged over every position this is algebraically the plug in estimator, so it inherits that
 *       estimator's upward bias exactly. Sampling fewer positions leaves the bias where it is and
 *       adds variance.
 */
static double estimate_probe_with_self(const uint8_t *corpus, size_t length, size_t samples)
{
    const size_t step = (length > samples) ? (length / samples) : 1u;
    double total = 0.0;
    unsigned taken = 0u;

    for (size_t at = 0u; at < length; at += step)
    {
        uint32_t matching = 0u;

        for (size_t index = 0u; index < length; index++)
        {
            if (corpus[index] == corpus[at])
            {
                matching++;
            }
        }
        total += (double)matching / (double)length;
        taken++;
    }
    return (taken == 0u) ? 0.0 : (total / (double)taken);
}

/**
 * @brief The candidate count estimate, excluding the probe position's own match.
 *
 * @param[in] corpus  Symbols to probe [BORROWS].
 * @param[in] length  How many.
 * @param[in] samples How many probe positions to average over.
 * @return            The mean candidate count, less the probe's own hit, over the remaining positions.
 * @note The same probe with one subtraction, and the subtraction is the whole difference between a
 *       biased estimator and an unbiased one. Averaged over every position this is algebraically the
 *       U statistic. The sift bench subtracts the needle's own occurrence for a reason recorded there
 *       as a measurement error, and that correction and this one are the same correction.
 */
static double estimate_probe_without_self(const uint8_t *corpus, size_t length, size_t samples)
{
    const size_t step = (length > samples) ? (length / samples) : 1u;
    double total = 0.0;
    unsigned taken = 0u;

    for (size_t at = 0u; at < length; at += step)
    {
        uint32_t matching = 0u;

        for (size_t index = 0u; index < length; index++)
        {
            if ((index != at) && (corpus[index] == corpus[at]))
            {
                matching++;
            }
        }
        total += (double)matching / ((double)length - 1.0);
        taken++;
    }
    return (taken == 0u) ? 0.0 : (total / (double)taken);
}

/**
 * @brief The most common value estimate of min entropy.
 *
 * @param[in] counts One counter per symbol [BORROWS].
 * @param[in] length How many symbols the corpus held.
 * @return           A lower confidence bound on min entropy, in bits.
 * @note NIST SP 800-90B section 6.3.1, the most common value estimate, with the same upper confidence
 *       bound on the modal probability the specification uses. It is here as context and is not
 *       scored against the collision entropy column, because min entropy is the negative log of the
 *       largest probability and collision entropy is the negative log of a sum of squares. Two
 *       estimators of two different properties cannot be ranked against one truth.
 */
static double estimate_min_entropy(const uint32_t *counts, size_t length)
{
    uint32_t highest = 0u;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        if (counts[symbol] > highest)
        {
            highest = counts[symbol];
        }
    }

    const double share = (double)highest / (double)length;
    // The specification's upper bound on the modal probability at 99 percent confidence
    const double bound = share + (2.576 * sqrt((share * (1.0 - share)) / ((double)length - 1.0)));
    const double capped = (bound > 1.0) ? 1.0 : bound;

    return -log2(capped);
}

/**
 * @brief The highest Renyi order the ladder reaches.
 *
 * @note Five. The correction shrinks with every order and the question is where it stops mattering,
 *       so the ladder needs enough rungs to show the trend and no more.
 */
#define MAX_ORDER 5u

/**
 * @brief Returns the Renyi entropy of a source at @p order, from its distribution.
 *
 * @param[in] source The distribution [BORROWS].
 * @param[in] order  Which Renyi order, two or greater.
 * @return           The entropy in bits.
 * @note Computed from the weights and never from a corpus, so it is the truth the estimators below
 *       are scored against at every order.
 */
static double true_renyi(const Source *source, unsigned order)
{
    double total = 0.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        total += pow(source->weight[symbol], (double)order);
    }
    return log2(total) / (1.0 - (double)order);
}

/**
 * @brief The plug in estimate of the sum of the @p order th powers.
 *
 * @param[in] counts One counter per symbol [BORROWS].
 * @param[in] length How many symbols the corpus held.
 * @param[in] order  Which power.
 * @return           The sum of the empirical frequencies raised to that power.
 * @note The uncorrected form at every order. It counts a position as coinciding with itself, which is
 *       what the correction below removes.
 */
static double plug_in_power(const uint32_t *counts, size_t length, unsigned order)
{
    double total = 0.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        total += pow((double)counts[symbol] / (double)length, (double)order);
    }
    return total;
}

/**
 * @brief The unbiased estimate of the sum of the @p order th powers.
 *
 * @param[in] counts One counter per symbol [BORROWS].
 * @param[in] length How many symbols the corpus held.
 * @param[in] order  Which power.
 * @return           The proportion of ordered tuples of distinct positions that all agree.
 * @note The same correction as the second order one, applied @p order deep. Where the pair estimator
 *       refuses to pair a position with itself, this refuses every tuple in which any two indices
 *       coincide, which is the falling factorial in both the numerator and the denominator. Applying
 *       the correction recursively is what climbing this ladder means.
 * @note Doubles carry the factorials because the numerator reaches roughly length to the fifth, past
 *       what 64 bits holds. What the ratio needs is relative precision and a double has sixteen
 *       digits of it.
 */
static double unbiased_power(const uint32_t *counts, size_t length, unsigned order)
{
    double tuples = 0.0;
    double available = 1.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        double falling = 1.0;

        for (unsigned step = 0u; step < order; step++)
        {
            falling *= (double)counts[symbol] - (double)step;
        }
        // A symbol appearing fewer times than the order contributes no tuple of distinct positions,
        // and the falling factorial goes negative there instead of to zero
        if (falling > 0.0)
        {
            tuples += falling;
        }
    }
    for (unsigned step = 0u; step < order; step++)
    {
        available *= (double)length - (double)step;
    }
    return tuples / available;
}

/**
 * @brief Reports what the correction is worth at each Renyi order on one source.
 *
 * @param[in] source The distribution to draw from [BORROWS].
 * @param[in] length How many symbols each trial's corpus holds.
 * @note The question this answers. The correction removes coincident indices, and applying it deeper
 *       removes coincident tuples, so it can be climbed. What the correction is worth at each rung,
 *       and whether there is a source on which it is worth nothing at any rung, is measured here
 *       instead of argued.
 */
static void score_ladder(const Source *source, size_t length)
{
    static uint8_t corpus[MAX_CORPUS];
    uint32_t counts[ALPHABET];

    for (unsigned order = 2u; order <= MAX_ORDER; order++)
    {
        const double truth = true_renyi(source, order);
        double plug_bias = 0.0;
        double free_bias = 0.0;
        double correction = 0.0;

        for (unsigned trial = 0u; trial < TRIALS; trial++)
        {
            draw_from(source, corpus, length, 0xA5000000u + trial);
            tally(corpus, length, counts);

            const double scale = 1.0 / (1.0 - (double)order);
            const double plug = log2(plug_in_power(counts, length, order)) * scale;
            const double freed = log2(unbiased_power(counts, length, order)) * scale;

            plug_bias += plug - truth;
            free_bias += freed - truth;
            correction += fabs(freed - plug);
        }

        printf("ancorae_ladder,%s,%u,%u,%u,%.4f,%.4f,%.4f,%.4f\n", source->name, (unsigned)length, order, TRIALS,
               truth, plug_bias / (double)TRIALS, free_bias / (double)TRIALS, correction / (double)TRIALS);
    }
}

/**
 * @brief Scores every estimator on one source at one corpus length.
 *
 * @param[in] source The distribution to draw from [BORROWS].
 * @param[in] length How many symbols each trial's corpus holds.
 * @note Bias is the mean signed error in bits and root mean square error is the spread around the
 *       truth. Both are reported because an estimator can be unbiased and useless, and an estimator
 *       can be tightly wrong.
 */
static void score(const Source *source, size_t length)
{
    static uint8_t corpus[MAX_CORPUS];
    uint32_t counts[ALPHABET];

    const double truth = -log2(true_collision(source));

    double bias[4] = {0.0, 0.0, 0.0, 0.0};
    double squares[4] = {0.0, 0.0, 0.0, 0.0};
    double min_entropy = 0.0;

    for (unsigned trial = 0u; trial < TRIALS; trial++)
    {
        draw_from(source, corpus, length, 0xA5000000u + trial);
        tally(corpus, length, counts);

        const double estimate[4] = {
            -log2(estimate_plug_in(counts, length)),
            -log2(estimate_unbiased(counts, length)),
            -log2(estimate_probe_with_self(corpus, length, PROBE_SAMPLES)),
            -log2(estimate_probe_without_self(corpus, length, PROBE_SAMPLES)),
        };

        for (unsigned which = 0u; which < 4u; which++)
        {
            const double error = estimate[which] - truth;

            bias[which] += error;
            squares[which] += error * error;
        }
        min_entropy += estimate_min_entropy(counts, length);
    }

    printf("ancorae_entropy,%s,%u,%u,%.4f", source->name, (unsigned)length, TRIALS, truth);
    for (unsigned which = 0u; which < 4u; which++)
    {
        printf(",%.4f,%.4f", bias[which] / (double)TRIALS, sqrt(squares[which] / (double)TRIALS));
    }
    printf(",%.4f\n", min_entropy / (double)TRIALS);
}

int main(void)
{
    Source sources[10];
    unsigned made = 0u;

    // One symbol carrying all the weight. Every power of the distribution sums to one, so every Renyi
    // order is zero and there are no distinct positions to exclude. It is here to be the case where
    // the correction has nothing to act on
    source_uniform(&sources[made], "point1", 1u);
    made++;
    source_uniform(&sources[made], "uniform2", 2u);
    made++;
    source_uniform(&sources[made], "uniform16", 16u);
    made++;
    source_uniform(&sources[made], "uniform256", 256u);
    made++;
    source_zipf(&sources[made], "zipf0.5", 0.5);
    made++;
    source_zipf(&sources[made], "zipf1.0", 1.0);
    made++;
    source_zipf(&sources[made], "zipf1.5", 1.5);
    made++;
    source_two_point(&sources[made], "skew0.90", 0.90);
    made++;
    source_two_point(&sources[made], "skew0.99", 0.99);
    made++;

    static const size_t lengths[] = {256u, 1024u, 4096u, 16384u};

    printf("bench,source,length,trials,true_h2,"
           "plugin_bias,plugin_rmse,unbiased_bias,unbiased_rmse,"
           "probe_self_bias,probe_self_rmse,probe_nonself_bias,probe_nonself_rmse,mcv_min_entropy\n");

    for (unsigned which = 0u; which < made; which++)
    {
        for (size_t index = 0u; index < (sizeof lengths / sizeof lengths[0]); index++)
        {
            score(&sources[which], lengths[index]);
        }
    }

    printf("bench,source,length,order,trials,true_renyi,plugin_bias,unbiased_bias,correction_bits\n");

    for (unsigned which = 0u; which < made; which++)
    {
        for (size_t index = 0u; index < (sizeof lengths / sizeof lengths[0]); index++)
        {
            score_ladder(&sources[which], lengths[index]);
        }
    }
    return 0;
}
