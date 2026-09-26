// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef SIM_H
#define SIM_H

#include "engine_config.h"

#include "exact_integer.h"
#include "scriptura.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIM_LINE_ROOM 8192ull

#define SIM_COUNTER_STRIDE 65536ull

struct TesseraClient;

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
    struct TesseraClient *job;
    unsigned long long job_declared;
} SimTally;

// a sim that uses the device is one job on the device's tessera daemon, submitted before its first device
// allocation and released by sim_close; the signum is the host BLAKE3 of the sim's name and arguments
int sim_job_submit(SimTally *tally, const char *name, int count, char *const *arguments, unsigned long long declared);

void sim_job_release(SimTally *tally);

static inline __host__ __device__ unsigned long long sim_mix(unsigned long long word)
{
    unsigned long long mixed = word + 0x9E3779B97F4A7C15ull;
    mixed = (mixed ^ (mixed >> 30u)) * 0xBF58476D1CE4E5B9ull;
    mixed = (mixed ^ (mixed >> 27u)) * 0x94D049BB133111EBull;
    return mixed ^ (mixed >> 31u);
}

static inline __host__ __device__ unsigned long long sim_draw(unsigned long long key, unsigned long long counter)
{
    return sim_mix(key ^ sim_mix(counter));
}

static inline __host__ __device__ unsigned long long sim_draw_below(unsigned long long key, unsigned long long counter,
                                                                    unsigned long long bound)
{
    return sim_draw(key, counter) % bound;
}

static inline __host__ __device__ unsigned long long sim_bits_set(unsigned long long word)
{
    word = word - ((word >> 1u) & 0x5555555555555555ull);
    word = (word & 0x3333333333333333ull) + ((word >> 2u) & 0x3333333333333333ull);
    word = (word + (word >> 4u)) & 0x0F0F0F0F0F0F0F0Full;
    return (word * 0x0101010101010101ull) >> 56u;
}

static inline __host__ __device__ unsigned long long sim_binomial_half(unsigned long long key, unsigned long long counter,
                                                                       unsigned long long trials)
{
    unsigned long long heads = 0ull;
    unsigned long long word = 0ull;
    for (unsigned long long done = 0ull; done < trials; done += 64ull)
    {
        const unsigned long long draw = sim_draw(key, (counter * SIM_COUNTER_STRIDE) + word);
        const unsigned long long left = trials - done;
        const unsigned long long kept = (left >= 64ull) ? draw : (draw & ((1ull << left) - 1ull));
        heads += sim_bits_set(kept);
        word += 1ull;
    }
    return heads;
}

// one electron's draw of the shot below: 0, 1, 2 or 4 with chances 9, 8, 6 and 1 in 24
#define SIM_SHOT_CHANCES 24ull

// six electrons' chances from one word, 24^6 of them
#define SIM_SHOT_DIGITS 6ull

#define SIM_SHOT_DIGIT_WORD 191102976ull

// A count of mean S whose first four cumulants are each S, a Poisson count's: each of the S expected electrons adds
// 0, 1, 2 or 4 with chances 9, 8, 6 and 1 in 24, a law whose factorial moments are 1 to the fourth, as Poisson(1)'s
// are; it parts from Poisson at the fifth. A word's draw below 24^6 gives six electrons' chances, so a counter's
// SIM_COUNTER_STRIDE words hold 6 of them each.
static inline __host__ __device__ unsigned long long sim_poisson_four_cumulants(unsigned long long key,
                                                                               unsigned long long counter,
                                                                               unsigned long long electrons)
{
    unsigned long long collected = 0ull;
    unsigned long long word = 0ull;
    for (unsigned long long done = 0ull; done < electrons; done += SIM_SHOT_DIGITS)
    {
        unsigned long long digits = sim_draw(key, (counter * SIM_COUNTER_STRIDE) + word) % SIM_SHOT_DIGIT_WORD;
        const unsigned long long left = electrons - done;
        const unsigned long long taken = (left < SIM_SHOT_DIGITS) ? left : SIM_SHOT_DIGITS;
        for (unsigned long long digit = 0ull; digit < taken; digit += 1ull)
        {
            const unsigned long long chance = digits % SIM_SHOT_CHANCES;
            digits /= SIM_SHOT_CHANCES;
            collected += (chance < 9ull) ? 0ull : ((chance < 17ull) ? 1ull : ((chance < 23ull) ? 2ull : 4ull));
        }
        word += 1ull;
    }
    return collected;
}

static inline void sim_open(SimTally *tally, char *room)
{
    memset(tally, 0, sizeof(*tally));
    tally->line.out = room;
    tally->line.room = SIM_LINE_ROOM;
}

static inline void sim_flush(SimTally *tally)
{
    scriptura_write(&tally->line, stdout);
    tally->line.at = 0ull;
    fflush(stdout);
}

static inline void sim_check(SimTally *tally, int held, const char *what)
{
    tally->checks += 1ull;
    if (held == 0)
    {
        tally->failures += 1ull;
        scriptura_text(&tally->line, "  FAILED: ");
        scriptura_text(&tally->line, what);
        scriptura_character(&tally->line, '\n');
    }
}

static inline int sim_close(SimTally *tally, const char *name)
{
    sim_job_release(tally);
    scriptura_text(&tally->line, "  ");
    scriptura_text(&tally->line, name);
    scriptura_text(&tally->line, ": ");
    scriptura_decimal(&tally->line, tally->checks, 1u);
    scriptura_text(&tally->line, " checks, ");
    scriptura_decimal(&tally->line, tally->failures, 1u);
    scriptura_text(&tally->line, " failed\n");
    sim_flush(tally);
    return (tally->failures == 0ull) ? 0 : 1;
}

static inline void sim_exact_whole(AnchorExactInteger *value, unsigned long long whole)
{
    anchor_exact_zero(value);
    // the low and high halves of a 64-bit word each fit one 32-bit limb
    value->limb[0] = (uint32_t)(whole & 0xFFFFFFFFull);
    // the high half, shifted down, is below 2^32
    value->limb[1] = (uint32_t)(whole >> 32u);
    value->sign = (whole == 0ull) ? 0 : 1;
}

static inline void sim_exact_signed(AnchorExactInteger *value, long long whole)
{
    // the magnitude of a negative 64-bit word is its two's complement negation, taken unsigned
    const unsigned long long magnitude = (whole < 0ll) ? (0ull - (unsigned long long)whole) : (unsigned long long)whole;
    sim_exact_whole(value, magnitude);
    if (whole < 0ll)
    {
        value->sign = -1;
    }
}

static inline int sim_exact_product(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                    AnchorExactInteger *result)
{
    return anchor_exact_multiply(left, right, result) == ANCHOR_EXACT_OK;
}

static inline int sim_exact_scaled(const AnchorExactInteger *value, unsigned long long factor, AnchorExactInteger *result)
{
    AnchorExactInteger scale;
    sim_exact_whole(&scale, factor);
    return sim_exact_product(value, &scale, result);
}

static inline int sim_exact_sum(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                AnchorExactInteger *result)
{
    return anchor_exact_add(left, right, result) == ANCHOR_EXACT_OK;
}

static inline int sim_exact_less(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                 AnchorExactInteger *result)
{
    return anchor_exact_subtract(left, right, result) == ANCHOR_EXACT_OK;
}

static inline int sim_ratio_compare(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator,
                                    const AnchorExactInteger *other_numerator,
                                    const AnchorExactInteger *other_denominator, int *order)
{
    AnchorExactInteger left;
    AnchorExactInteger right;
    if ((sim_exact_product(numerator, other_denominator, &left) == 0)
        || (sim_exact_product(other_numerator, denominator, &right) == 0))
    {
        return 0;
    }
    *order = anchor_exact_compare(&left, &right);
    return 1;
}

static inline unsigned long long sim_ratio_floor(const AnchorExactInteger *numerator,
                                                 const AnchorExactInteger *denominator)
{
    unsigned long long below = 0ull;
    unsigned long long above = 0xFFFFFFFFFFFFFFFFull;
    AnchorExactInteger trial;
    while (below < above)
    {
        const unsigned long long middle = below + ((above - below) / 2ull) + ((above - below) & 1ull);
        if ((sim_exact_scaled(denominator, middle, &trial) != 0) && (anchor_exact_compare(&trial, numerator) <= 0))
        {
            below = middle;
        }
        else
        {
            above = middle - 1ull;
        }
    }
    return below;
}

static inline void sim_ratio_print(ScripturaLine *line, const AnchorExactInteger *numerator,
                                   const AnchorExactInteger *denominator, unsigned int places)
{
    if ((denominator->sign == 0) || (places > 18u))
    {
        scriptura_text(line, "undefined");
        return;
    }
    AnchorExactInteger top = *numerator;
    AnchorExactInteger bottom = *denominator;
    const int negative = (top.sign * bottom.sign) < 0;
    top.sign = (top.sign == 0) ? 0 : 1;
    bottom.sign = 1;
    if ((places > 0u) && (anchor_exact_scale_by_ten(&top, places) != ANCHOR_EXACT_OK))
    {
        scriptura_text(line, "too wide");
        return;
    }
    const unsigned long long scaled = sim_ratio_floor(&top, &bottom);
    unsigned long long unit = 1ull;
    for (unsigned int place = 0u; place < places; place += 1u)
    {
        unit *= 10ull;
    }
    if (negative)
    {
        scriptura_character(line, '-');
    }
    scriptura_decimal(line, scaled / unit, 1u);
    if (places > 0u)
    {
        scriptura_character(line, '.');
        scriptura_decimal(line, scaled % unit, places);
    }
}

static inline void sim_fraction_print(ScripturaLine *line, unsigned long long numerator, unsigned long long denominator,
                                      unsigned int places)
{
    AnchorExactInteger top;
    AnchorExactInteger bottom;
    sim_exact_whole(&top, numerator);
    sim_exact_whole(&bottom, denominator);
    sim_ratio_print(line, &top, &bottom, places);
}

static inline int sim_took(SimTally *tally, cudaError_t status, const char *what)
{
    if (status != cudaSuccess)
    {
        sim_check(tally, 0, what);
        scriptura_text(&tally->line, "    cuda: ");
        scriptura_text(&tally->line, cudaGetErrorString(status));
        scriptura_character(&tally->line, '\n');
        return 0;
    }
    return 1;
}

static inline unsigned long long sim_launch_blocks(unsigned long long count, unsigned long long threads)
{
    return (count + threads - 1ull) / threads;
}

static inline EngineSignum sim_content(const unsigned short *lanes, unsigned long long count, unsigned long long key)
{
    EngineSignum content;
    for (unsigned int word = 0u; word < (ENGINE_SIGNUM_BYTES / 8u); word += 1u)
    {
        unsigned long long running = sim_mix(key + word);
        for (unsigned long long lane = word; lane < count; lane += (ENGINE_SIGNUM_BYTES / 8u))
        {
            running = sim_mix(running ^ lanes[lane]);
        }
        for (unsigned int byte = 0u; byte < 8u; byte += 1u)
        {
            // one byte of the running word, taken from the bottom after the shift
            content.bytes[(word * 8u) + byte] = (unsigned char)(running >> (8u * byte));
        }
    }
    return content;
}

#endif
