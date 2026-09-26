// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Exact rationals on the exact integer, for the sims that carry values no word holds. Every value is kept in lowest
// terms: by a word gcd while both parts fit below 2^62, and wider by the exact integer's gcd and exact division. An
// operation that outgrows the exact integer's width marks the run, and the sim reports it as a failed check.
#ifndef SIM_RATIONAL_H
#define SIM_RATIONAL_H

#include "sim.h"

#define SIM_RATIONAL_SMALL_MOST (1ull << 62)

// the denominator is always positive
typedef struct
{
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
} SimRational;

static int s_sim_rational_wide = 0;

static inline void sim_rational_took(int held)
{
    if (held == 0)
    {
        s_sim_rational_wide = 1;
    }
}

static inline long long sim_rational_gcd(long long left, long long right)
{
    long long first = (left < 0ll) ? -left : left;
    long long second = (right < 0ll) ? -right : right;
    while (second != 0ll)
    {
        const long long rest = first % second;
        first = second;
        second = rest;
    }
    return first;
}

// the value as a signed word, when its magnitude is below 2^62
static inline int sim_rational_small(const AnchorExactInteger *value, long long *small)
{
    for (unsigned int limb = 2u; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        if (value->limb[limb] != 0u)
        {
            return 0;
        }
    }
    const unsigned long long magnitude = ((unsigned long long)value->limb[1] << 32u) | (unsigned long long)value->limb[0];
    if (magnitude >= SIM_RATIONAL_SMALL_MOST)
    {
        return 0;
    }
    // below 2^62, so the magnitude fits the signed word with either sign
    *small = (value->sign < 0) ? -(long long)magnitude : (long long)magnitude;
    return 1;
}

static inline void sim_rational_settle(SimRational *value)
{
    long long numerator = 0ll;
    long long denominator = 0ll;
    if ((sim_rational_small(&value->numerator, &numerator) == 0)
        || (sim_rational_small(&value->denominator, &denominator) == 0) || (denominator <= 0ll))
    {
        AnchorExactInteger common;
        AnchorExactInteger one;
        sim_rational_took(anchor_exact_gcd(&value->numerator, &value->denominator, &common) == ANCHOR_EXACT_OK);
        sim_exact_whole(&one, 1ull);
        if (anchor_exact_compare(&common, &one) > 0)
        {
            AnchorExactInteger top;
            AnchorExactInteger bottom;
            sim_rational_took((anchor_exact_divide_exact(&value->numerator, &common, &top) == ANCHOR_EXACT_OK)
                              && (anchor_exact_divide_exact(&value->denominator, &common, &bottom) == ANCHOR_EXACT_OK));
            value->numerator = top;
            value->denominator = bottom;
        }
        return;
    }
    const long long common = sim_rational_gcd(numerator, denominator);
    if (common > 1ll)
    {
        sim_exact_signed(&value->numerator, numerator / common);
        sim_exact_signed(&value->denominator, denominator / common);
    }
}

static inline SimRational sim_rational(long long numerator, long long denominator)
{
    SimRational value;
    if (denominator == 0ll)
    {
        s_sim_rational_wide = 1;
        denominator = 1ll;
        numerator = 0ll;
    }
    const long long sign = (denominator < 0ll) ? -1ll : 1ll;
    sim_exact_signed(&value.numerator, sign * numerator);
    sim_exact_signed(&value.denominator, sign * denominator);
    sim_rational_settle(&value);
    return value;
}

static inline SimRational sim_rational_sum(SimRational left, SimRational right)
{
    SimRational value;
    AnchorExactInteger left_scaled;
    AnchorExactInteger right_scaled;
    sim_rational_took(sim_exact_product(&left.numerator, &right.denominator, &left_scaled)
                      && sim_exact_product(&right.numerator, &left.denominator, &right_scaled)
                      && sim_exact_sum(&left_scaled, &right_scaled, &value.numerator)
                      && sim_exact_product(&left.denominator, &right.denominator, &value.denominator));
    sim_rational_settle(&value);
    return value;
}

static inline SimRational sim_rational_negative(SimRational value)
{
    value.numerator.sign = -value.numerator.sign;
    return value;
}

static inline SimRational sim_rational_difference(SimRational left, SimRational right)
{
    return sim_rational_sum(left, sim_rational_negative(right));
}

static inline SimRational sim_rational_product(SimRational left, SimRational right)
{
    SimRational value;
    sim_rational_took(sim_exact_product(&left.numerator, &right.numerator, &value.numerator)
                      && sim_exact_product(&left.denominator, &right.denominator, &value.denominator));
    sim_rational_settle(&value);
    return value;
}

static inline SimRational sim_rational_reciprocal(SimRational value)
{
    if (value.numerator.sign == 0)
    {
        s_sim_rational_wide = 1;
        return sim_rational(0ll, 1ll);
    }
    SimRational turned;
    turned.numerator = value.denominator;
    turned.denominator = value.numerator;
    if (turned.denominator.sign < 0)
    {
        turned.denominator.sign = 1;
        turned.numerator.sign = -turned.numerator.sign;
    }
    return turned;
}

// the denominator is positive, so the numerator carries the sign
static inline int sim_rational_sign(SimRational value)
{
    return (value.numerator.sign > 0) ? 1 : ((value.numerator.sign < 0) ? -1 : 0);
}

static inline SimRational sim_rational_absolute(SimRational value)
{
    if (value.numerator.sign < 0)
    {
        value.numerator.sign = 1;
    }
    return value;
}

static inline int sim_rational_equal(SimRational left, SimRational right)
{
    AnchorExactInteger left_cross;
    AnchorExactInteger right_cross;
    const int held = sim_exact_product(&left.numerator, &right.denominator, &left_cross)
                  && sim_exact_product(&right.numerator, &left.denominator, &right_cross);
    sim_rational_took(held);
    return held && (anchor_exact_compare(&left_cross, &right_cross) == 0);
}

// a reduced fraction when it fits a word; wider, the exact value printed to 12 places
static inline void sim_rational_print(ScripturaLine *line, SimRational value)
{
    long long numerator = 0ll;
    long long denominator = 1ll;
    if ((sim_rational_small(&value.numerator, &numerator) == 0)
        || (sim_rational_small(&value.denominator, &denominator) == 0))
    {
        sim_ratio_print(line, &value.numerator, &value.denominator, 12u);
        return;
    }
    const long long common = sim_rational_gcd(numerator, denominator);
    if (common > 1ll)
    {
        numerator /= common;
        denominator /= common;
    }
    scriptura_signed(line, numerator);
    if (denominator != 1ll)
    {
        scriptura_character(line, '/');
        // the denominator is kept positive
        scriptura_decimal(line, (unsigned long long)denominator, 1u);
    }
}

// the number of bits in the magnitude: 0 for 0
static inline unsigned long long sim_exact_bits(const AnchorExactInteger *value)
{
    for (unsigned int limb = ANCHOR_EXACT_LIMBS; limb > 0u; limb -= 1u)
    {
        unsigned int word = value->limb[limb - 1u];
        if (word != 0u)
        {
            unsigned long long bits = 32ull * (limb - 1u);
            while (word != 0u)
            {
                bits += 1ull;
                word >>= 1u;
            }
            return bits;
        }
    }
    return 0ull;
}

// base^power exactly, by repeated squaring
static inline int sim_exact_power(unsigned long long base, unsigned long long power, AnchorExactInteger *result)
{
    AnchorExactInteger square;
    AnchorExactInteger next;
    sim_exact_whole(result, 1ull);
    sim_exact_whole(&square, base);
    while (power != 0ull)
    {
        if ((power & 1ull) != 0ull)
        {
            if (sim_exact_product(result, &square, &next) == 0)
            {
                return 0;
            }
            *result = next;
        }
        power >>= 1u;
        if (power != 0ull)
        {
            if (sim_exact_product(&square, &square, &next) == 0)
            {
                return 0;
            }
            square = next;
        }
    }
    return 1;
}

#endif
