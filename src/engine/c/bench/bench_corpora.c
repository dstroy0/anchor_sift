/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_corpora.c
 * @brief Generated corpora and the two statistics a dispatch decision is made from.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Deliberately self contained. The bench this came out of reached SHA-256 out of the vendored
 *       library to fill a buffer, pulling that library's whole header tree in. The include paths
 *       that served it stopped the build configuring at all.
 */

#include "bench_corpora.h"

#include <string.h>

/** @brief Symbols the skewed alphabet uses before the tail is filled with one more. */
#define SKEWED_SYMBOLS 27u

/**
 * @brief One step of splitmix64.
 *
 * @param[in,out] state Generator state, advanced by the call [BORROWS].
 * @return              The next value in the stream.
 */
static uint64_t splitmix64(uint64_t *state)
{
    *state += 0x9E3779B97F4A7C15ULL;
    uint64_t held = *state;

    held = (held ^ (held >> 30)) * 0xBF58476D1CE4E5B9ULL;
    held = (held ^ (held >> 27)) * 0x94D049BB133111EBULL;
    return held ^ (held >> 31);
}

/**
 * @brief Fills a buffer with uniform bytes.
 *
 * @param[out] bytes  Where to write [BORROWS].
 * @param[in]  length How many.
 * @param[in]  seed   Selects the stream.
 */
static void fill_uniform(uint8_t *bytes, size_t length, uint64_t seed)
{
    uint64_t state = seed;
    size_t written = 0u;

    while (written < length)
    {
        const uint64_t drawn = splitmix64(&state);
        size_t taking = length - written;

        if (taking > sizeof drawn)
        {
            taking = sizeof drawn;
        }
        memcpy(bytes + written, &drawn, taking);
        written += taking;
    }
}

/**
 * @brief Maps a uniform buffer onto a geometric alphabet of 27 symbols, in place.
 *
 * @param[in,out] bytes  Bytes to remap [BORROWS].
 * @param[in]     length How many.
 * @note A distribution and no arrangement. An arm reading only the histogram cannot tell this from
 *       a language with the same histogram, and that makes it the right control for a cost model
 *       built out of the histogram.
 */
static void map_skewed(uint8_t *bytes, size_t length)
{
    uint8_t table[256];
    size_t filled = 0u;
    uint8_t symbol = 0u;

    while ((filled < sizeof table) && (symbol < SKEWED_SYMBOLS))
    {
        size_t width = (sizeof table - filled) / 2u;

        if (width == 0u)
        {
            width = 1u;
        }
        if ((filled + width) > sizeof table)
        {
            width = sizeof table - filled;
        }
        memset(table + filled, (int)('a' + symbol), width);
        filled += width;
        symbol += 1u;
    }
    while (filled < sizeof table)
    {
        table[filled] = (uint8_t)' ';
        filled += 1u;
    }
    for (size_t at = 0u; at < length; at += 1u)
    {
        bytes[at] = table[bytes[at]];
    }
}

/**
 * @brief Fills a buffer with a period of sixteen.
 *
 * @param[out] bytes  Where to write [BORROWS].
 * @param[in]  length How many.
 */
static void fill_periodic(uint8_t *bytes, size_t length)
{
    for (size_t at = 0u; at < length; at += 1u)
    {
        bytes[at] = (uint8_t)(at % 16u);
    }
}

void bench_build_bytes(uint8_t *bytes, size_t length, CorpusKind kind, uint64_t seed)
{
    if (kind == CORPUS_PERIODIC)
    {
        fill_periodic(bytes, length);
        return;
    }
    fill_uniform(bytes, length, seed);
    if (kind == CORPUS_SKEWED)
    {
        map_skewed(bytes, length);
    }
}

const char *bench_corpus_name(CorpusKind kind)
{
    if (kind == CORPUS_UNIFORM)
    {
        return "uniform";
    }
    if (kind == CORPUS_SKEWED)
    {
        return "skewed";
    }
    if (kind == CORPUS_PERIODIC)
    {
        return "periodic16";
    }
    return "unknown";
}

double bench_collision_entropy(const uint8_t *corpus, size_t length, size_t *distinct)
{
    size_t counts[256] = {0};
    double squared = 0.0;
    size_t used = 0u;

    for (size_t at = 0u; at < length; at += 1u)
    {
        counts[corpus[at]] += 1u;
    }
    for (size_t slot = 0u; slot < 256u; slot += 1u)
    {
        if (counts[slot] != 0u)
        {
            const double share = (double)counts[slot] / (double)length;

            squared += share * share;
            used += 1u;
        }
    }
    *distinct = used;

    // -log2 of the collision probability, by halving until the value reaches [1,2) and counting.
    // A series on the remainder finishes it. The bench reports this to three places and a dispatch
    // threshold cannot turn on the last of them.
    double walk = squared;
    double bits = 0.0;

    while (walk < 1.0)
    {
        walk *= 2.0;
        bits += 1.0;
    }
    const double fraction = walk - 1.0;

    return bits - (fraction * 1.4426950) + (fraction * fraction * 0.7213475);
}

/** @brief Positions sampled per lag. Reading every position is quadratic in the lag count. */
#define PERIOD_SAMPLES 200000u

/**
 * @brief Margin below which a candidate is called noise and no period is reported.
 *
 * @note A detection floor, not a dispatch threshold. The margin is returned whatever this does, and
 *       a caller can read that number instead of trusting the flag. Uniform and skewed both score
 *       near zero here because their agreement is the same at every lag. Having no period means
 *       exactly that.
 */
#define PERIOD_FLOOR 0.05

BenchPeriod bench_recover_period(const uint8_t *corpus, size_t length)
{
    BenchPeriod found = {0u, 0.0, 0.0, 0.0};
    double agreement[BENCH_LONGEST_LAG + 1u];

    if (length < (2u * BENCH_LONGEST_LAG))
    {
        return found;
    }

    size_t counts[256] = {0};

    for (size_t at = 0u; at < length; at += 1u)
    {
        counts[corpus[at]] += 1u;
    }
    for (size_t slot = 0u; slot < 256u; slot += 1u)
    {
        const double share = (double)counts[slot] / (double)length;

        found.at_chance += share * share;
    }

    const size_t usable = length - BENCH_LONGEST_LAG;
    size_t stride = usable / PERIOD_SAMPLES;

    if (stride == 0u)
    {
        stride = 1u;
    }

    for (size_t lag = 1u; lag <= BENCH_LONGEST_LAG; lag += 1u)
    {
        size_t same = 0u;
        size_t seen = 0u;

        for (size_t at = 0u; at < usable; at += stride)
        {
            if (corpus[at] == corpus[at + lag])
            {
                same += 1u;
            }
            seen += 1u;
        }
        agreement[lag] = (seen != 0u) ? ((double)same / (double)seen) : 0.0;
    }

    // Scored on a candidate and all of its multiples against every lag outside that family. A
    // sequence repeating every sixteen agrees with itself at 16, 32, 48 and 64 alike, so the
    // tallest of those is settled by noise and taking it reports a harmonic as the period.
    for (size_t period = 2u; period <= (BENCH_LONGEST_LAG / 2u); period += 1u)
    {
        double inside = 0.0;
        double outside = 0.0;
        size_t within = 0u;
        size_t beyond = 0u;

        // Exactly two multiples for every candidate. Family size otherwise grows as the candidate
        // shrinks, and the score is a mean over the family. A short wrong candidate can win by
        // holding more members and catching one good lag among them. A period that is not a whole
        // number of lags supplies the good lag: at 16.59 the fundamental sits 0.59 away
        // from lag 16 while 2P sits 0.18 away from lag 33, so 33 agrees better than 16 does. The
        // Python side read three published cell edges short by a factor near two thirds this way.
        for (size_t lag = 1u; lag <= BENCH_LONGEST_LAG; lag += 1u)
        {
            if (((lag % period) == 0u) && (lag <= (2u * period)))
            {
                inside += agreement[lag];
                within += 1u;
            }
            else if ((lag % period) != 0u)
            {
                outside += agreement[lag];
                beyond += 1u;
            }
        }
        if ((within < 2u) || (beyond == 0u))
        {
            continue;
        }

        const double margin = (inside / (double)within) - (outside / (double)beyond);

        if (margin > found.margin)
        {
            found.margin = margin;
            found.period = period;
            found.agreement = agreement[period];
        }
    }

    if (found.margin < PERIOD_FLOOR)
    {
        found.period = 0u;
        found.agreement = 0.0;
    }
    return found;
}

double bench_predicted_rate(double entropy, double anchors)
{
    double held = 1.0;
    double remaining = entropy * anchors;

    while (remaining >= 1.0)
    {
        held *= 0.5;
        remaining -= 1.0;
    }
    // 2^-r on [0,1) as e^(-r ln2) to second order: 1 - r ln2 + (r ln2)^2 / 2. The first version of
    // this carried half of each coefficient, which put every prediction 15 percent high and read as
    // a filter beating its own bound by a quarter.
    return held * (1.0 - (remaining * 0.6931472) + (remaining * remaining * 0.2402265));
}
