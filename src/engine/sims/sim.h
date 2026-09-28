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

#define SIM_LINE_CAPACITY 8192ull

// the words a counter owns in its key's run of counters: sim_binomial_half takes one word per 64 trials,
// sim_poisson_four_cumulants one per 6 electrons and sim_thinned one per 64 / bits electrons, and a word past these
// is drawn on a key of the counter's own (sim_counter_draw), so no count runs into the next counter's words
#define SIM_COUNTER_STRIDE 65536ull

#define SIM_COUNTER_PAST_PURPOSE 0x50415354ull

struct TesseraClient;

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
    struct TesseraClient *job;
    unsigned long long job_declared;
} SimResults;

// a sim that uses the device is one job on the device's tessera daemon, submitted before its first device
// allocation and released by sim_close; the signum is the host BLAKE3 of the sim's name and arguments
int sim_job_submit(SimResults *results, const char *name, int count, char *const *arguments,
                   unsigned long long declared);

void sim_job_release(SimResults *results);

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

// word `word` of a counter's draws: the first SIM_COUNTER_STRIDE lie in the counter's own stride of the key's counters,
// and each word past them is drawn on a key made from the counter, so a count of any size keeps to its own words
static inline __host__ __device__ unsigned long long sim_counter_draw(unsigned long long key,
                                                                      unsigned long long counter,
                                                                      unsigned long long word)
{
    if (word < SIM_COUNTER_STRIDE)
    {
        return sim_draw(key, (counter * SIM_COUNTER_STRIDE) + word);
    }
    return sim_draw(key ^ sim_mix(counter ^ SIM_COUNTER_PAST_PURPOSE), word);
}

static inline __host__ __device__ unsigned long long sim_bits_set(unsigned long long word)
{
    word = word - ((word >> 1u) & 0x5555555555555555ull);
    word = (word & 0x3333333333333333ull) + ((word >> 2u) & 0x3333333333333333ull);
    word = (word + (word >> 4u)) & 0x0F0F0F0F0F0F0F0Full;
    return (word * 0x0101010101010101ull) >> 56u;
}

static inline __host__ __device__ unsigned long long sim_binomial_half(unsigned long long key,
                                                                       unsigned long long counter,
                                                                       unsigned long long trials)
{
    unsigned long long heads = 0ull;
    unsigned long long word = 0ull;
    for (unsigned long long done = 0ull; done < trials; done += 64ull)
    {
        const unsigned long long draw = sim_counter_draw(key, counter, word);
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
        unsigned long long digits = sim_counter_draw(key, counter, word) % SIM_SHOT_DIGIT_WORD;
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

static inline void sim_open(SimResults *results, char *capacity)
{
    memset(results, 0, sizeof(*results));
    results->line.out = capacity;
    results->line.capacity = SIM_LINE_CAPACITY;
}

static inline void sim_flush(SimResults *results)
{
    scriptura_write(&results->line, stdout);
    results->line.at = 0ull;
    fflush(stdout);
}

static inline void sim_check(SimResults *results, int passed, const char *what)
{
    results->checks += 1ull;
    if (passed == 0)
    {
        results->failures += 1ull;
        scriptura_text(&results->line, "  FAILED: ");
        scriptura_text(&results->line, what);
        scriptura_character(&results->line, '\n');
    }
}

static inline int sim_close(SimResults *results, const char *name)
{
    sim_job_release(results);
    scriptura_text(&results->line, "  ");
    scriptura_text(&results->line, name);
    scriptura_text(&results->line, ": ");
    scriptura_decimal(&results->line, results->checks, 1u);
    scriptura_text(&results->line, " checks, ");
    scriptura_decimal(&results->line, results->failures, 1u);
    scriptura_text(&results->line, " failed\n");
    sim_flush(results);
    return (results->failures == 0ull) ? 0 : 1;
}

static inline void sim_exact_unsigned(AnchorExactInteger *value, unsigned long long number)
{
    anchor_exact_zero(value);
    // the low and high halves of a 64-bit word each fit one 32-bit limb
    value->limb[0] = (uint32_t)(number & 0xFFFFFFFFull);
    // the high half, shifted down, is below 2^32
    value->limb[1] = (uint32_t)(number >> 32u);
    value->sign = (number == 0ull) ? 0 : 1;
}

static inline void sim_exact_signed(AnchorExactInteger *value, long long number)
{
    // the magnitude of a negative 64-bit word is its two's complement negation, taken unsigned
    const unsigned long long magnitude =
        (number < 0ll) ? (0ull - (unsigned long long)number) : (unsigned long long)number;
    sim_exact_unsigned(value, magnitude);
    if (number < 0ll)
    {
        value->sign = -1;
    }
}

static inline int sim_exact_product(const AnchorExactInteger *left, const AnchorExactInteger *right,
                                    AnchorExactInteger *result)
{
    return anchor_exact_multiply(left, right, result) == ANCHOR_EXACT_OK;
}

static inline int sim_exact_scaled(const AnchorExactInteger *value, unsigned long long factor,
                                   AnchorExactInteger *result)
{
    AnchorExactInteger scale;
    sim_exact_unsigned(&scale, factor);
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
    if ((sim_exact_product(numerator, other_denominator, &left) == 0) ||
        (sim_exact_product(other_numerator, denominator, &right) == 0))
    {
        return 0;
    }
    *order = anchor_exact_compare(&left, &right);
    return 1;
}

// the floor of numerator / denominator, both non-negative, by bisection below `bound`, which the caller knows the
// quotient is under
static inline unsigned long long sim_ratio_floor(const AnchorExactInteger *numerator,
                                                 const AnchorExactInteger *denominator, unsigned long long bound)
{
    unsigned long long below = 0ull;
    unsigned long long above = bound - 1ull;
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

// one group of an exact integer's decimal digits: 10^9, the widest power of ten whose remainder shifted up a limb
// still fits a word
#define SIM_DECIMAL_GROUP 1000000000ull

#define SIM_DECIMAL_GROUP_DIGITS 9u

// 10^9 exceeds 2^29, so a magnitude of ANCHOR_EXACT_BITS bits has at most ANCHOR_EXACT_BITS / 29 + 1 groups
#define SIM_DECIMAL_GROUPS ((((unsigned long long)(ANCHOR_EXACT_BITS)) / 29ull) + 1ull)

// the count of limbs up to and including the top non-zero one; 0 for zero
static inline unsigned long long sim_exact_limbs_used(const AnchorExactInteger *value)
{
    unsigned long long used = ANCHOR_EXACT_LIMBS;
    while ((used > 0ull) && (value->limb[used - 1ull] == 0u))
    {
        used -= 1ull;
    }
    return used;
}

// the magnitude of `value` in decimal, every digit exact: each group of nine is the remainder of a short division of
// the limbs by 10^9, taken from the top limb down
static inline void sim_exact_decimal(ScripturaLine *line, const AnchorExactInteger *value)
{
    AnchorExactInteger work = *value;
    unsigned int groups[SIM_DECIMAL_GROUPS];
    unsigned long long count = 0ull;
    unsigned long long used = sim_exact_limbs_used(&work);
    do
    {
        unsigned long long remainder = 0ull;
        for (unsigned long long index = used; index > 0ull; index -= 1ull)
        {
            const unsigned long long dividend = (remainder << 32u) | work.limb[index - 1ull];
            // the remainder is below 10^9, so the dividend is below 10^9 * 2^32 and its quotient fits a limb
            work.limb[index - 1ull] = (uint32_t)(dividend / SIM_DECIMAL_GROUP);
            remainder = dividend % SIM_DECIMAL_GROUP;
        }
        // a remainder by 10^9 is below 2^30
        groups[count] = (unsigned int)remainder;
        count += 1ull;
        used = sim_exact_limbs_used(&work);
    } while (used > 0ull);
    scriptura_decimal(line, groups[count - 1ull], 1u);
    for (unsigned long long group = count - 1ull; group > 0ull; group -= 1ull)
    {
        scriptura_decimal(line, groups[group - 1ull], SIM_DECIMAL_GROUP_DIGITS);
    }
}

// the ratio truncated, not rounded, to `places`, at any width the exact integer holds: the whole part is printed exact,
// and the fraction is the floor of the remainder times 10^places over the denominator, which is below 10^places
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
    AnchorExactInteger integer_part;
    AnchorExactInteger rest;
    if ((anchor_exact_divide(&top, &bottom, &integer_part, &rest) != ANCHOR_EXACT_OK) ||
        ((places > 0u) && (anchor_exact_scale_by_ten(&rest, places) != ANCHOR_EXACT_OK)))
    {
        scriptura_text(line, "too wide");
        return;
    }
    if (negative)
    {
        scriptura_character(line, '-');
    }
    sim_exact_decimal(line, &integer_part);
    if (places > 0u)
    {
        unsigned long long unit = 1ull;
        for (unsigned int place = 0u; place < places; place += 1u)
        {
            unit *= 10ull;
        }
        scriptura_character(line, '.');
        scriptura_decimal(line, sim_ratio_floor(&rest, &bottom, unit), places);
    }
}

static inline void sim_fraction_print(ScripturaLine *line, unsigned long long numerator, unsigned long long denominator,
                                      unsigned int places)
{
    AnchorExactInteger top;
    AnchorExactInteger bottom;
    sim_exact_unsigned(&top, numerator);
    sim_exact_unsigned(&bottom, denominator);
    sim_ratio_print(line, &top, &bottom, places);
}

static inline int sim_status_check(SimResults *results, cudaError_t status, const char *what)
{
    if (status != cudaSuccess)
    {
        // the runtime's last error is taken here, once reported, so the next launch check does not read it again
        (void)cudaGetLastError();
        sim_check(results, 0, what);
        scriptura_text(&results->line, "    cuda: ");
        scriptura_text(&results->line, cudaGetErrorString(status));
        scriptura_character(&results->line, '\n');
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
