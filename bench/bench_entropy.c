// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "impensa_ancorae_acus/impensa_ancorae_acus.h"

#include "mmgr_sha256.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define ALPHABET 256u

#define MAX_CORPUS 16384u

#define TRIALS 64u

#ifndef PROBE_SAMPLES
#define PROBE_SAMPLES 64u
#endif

typedef struct
{
    const char *name;
    double weight[ALPHABET];
    unsigned levels;
} Source;

static void source_uniform(Source *source, const char *name, unsigned levels)
{
    source->name = name;
    source->levels = levels;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        source->weight[symbol] = (symbol < levels) ? (1.0 / (double)levels) : 0.0;
    }
}

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

static double true_collision(const Source *source)
{
    double total = 0.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        total += source->weight[symbol] * source->weight[symbol];
    }
    return total;
}

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
    const double bound = share + (2.576 * sqrt((share * (1.0 - share)) / ((double)length - 1.0)));
    const double capped = (bound > 1.0) ? 1.0 : bound;

    return -log2(capped);
}

#define MAX_ORDER 5u

static double true_renyi(const Source *source, unsigned order)
{
    double total = 0.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        total += pow(source->weight[symbol], (double)order);
    }
    return log2(total) / (1.0 - (double)order);
}

static double plug_in_power(const uint32_t *counts, size_t length, unsigned order)
{
    double total = 0.0;

    for (unsigned symbol = 0u; symbol < ALPHABET; symbol++)
    {
        total += pow((double)counts[symbol] / (double)length, (double)order);
    }
    return total;
}

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
