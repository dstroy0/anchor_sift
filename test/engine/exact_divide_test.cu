// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Proves the exact integer's division: the long division returns numerator = quotient . divisor + remainder with the
// remainder below the divisor and the signs of truncation, over keyed and edge-shaped limbs at every width; the
// exact division (a multiply by the divisor's inverse and a mask) returns the quotient of every product and refuses
// what leaves a remainder; the gcd divides both values and leaves coprime cofactors.

#include "no_rounding/exact_integer.h"

#include <cstdio>
#include <cstring>

#define DIVIDE_TRIALS 200000u
#define DIVIDE_WIDE_TRIALS 4000u
#define EXACT_TRIALS 20000u
#define GCD_TRIALS 4000u
#define DIVIDE_KEY 0x444956ull

static int s_checks = 0;
static int s_failed = 0;

static void check(const char *name, int ok)
{
    s_checks += 1;
    if (ok == 0)
    {
        s_failed += 1;
        printf("  FAIL %s\n", name);
    }
    else
    {
        printf("  ok   %s\n", name);
    }
}

static unsigned long long divide_mix(unsigned long long value)
{
    value ^= value >> 33u;
    value *= 0xFF51AFD7ED558CCDull;
    value ^= value >> 33u;
    value *= 0xC4CEB9FE1A85EC53ull;
    value ^= value >> 33u;
    return value;
}

static unsigned long long s_counter = 0ull;

static unsigned int divide_draw(void)
{
    s_counter += 1ull;
    // the low word of the mixed counter
    return (unsigned int)divide_mix(DIVIDE_KEY ^ divide_mix(s_counter));
}

// limbs that land on the division's edges more often than chance: zeros, ones, the top bit alone, all ones
static unsigned int divide_edge_limb(void)
{
    static const unsigned int shaped[6] = {0u, 1u, 0x7FFFFFFFu, 0x80000000u, 0xFFFFFFFFu, 0xFFFFFFFEu};
    const unsigned int pick = divide_draw() % 8u;
    return (pick < 6u) ? shaped[pick] : divide_draw();
}

static void divide_value(AnchorExactInteger *value, unsigned int limbs, int shaped)
{
    anchor_exact_zero(value);
    for (unsigned int at = 0u; at < limbs; at++)
    {
        value->limb[at] = (shaped != 0) ? divide_edge_limb() : divide_draw();
    }
    int nonzero = 0;
    for (unsigned int at = 0u; at < ANCHOR_EXACT_LIMBS; at++)
    {
        nonzero |= (value->limb[at] != 0u) ? 1 : 0;
    }
    value->sign = (nonzero == 0) ? 0 : (((divide_draw() & 1u) != 0u) ? -1 : 1);
}

static int divide_magnitude_below(const AnchorExactInteger *small, const AnchorExactInteger *large)
{
    AnchorExactInteger left = *small;
    AnchorExactInteger right = *large;
    left.sign = (left.sign == 0) ? 0 : 1;
    right.sign = (right.sign == 0) ? 0 : 1;
    return anchor_exact_compare(&left, &right) < 0;
}

// numerator = quotient . divisor + remainder, |remainder| < |divisor|, the remainder's sign the numerator's or zero
static int divide_holds(const AnchorExactInteger *numerator, const AnchorExactInteger *divisor)
{
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    AnchorExactInteger product;
    AnchorExactInteger rebuilt;
    if (anchor_exact_divide(numerator, divisor, &quotient, &remainder) != ANCHOR_EXACT_OK)
    {
        return 0;
    }
    if ((anchor_exact_multiply(&quotient, divisor, &product) != ANCHOR_EXACT_OK)
        || (anchor_exact_add(&product, &remainder, &rebuilt) != ANCHOR_EXACT_OK))
    {
        return 0;
    }
    const int signed_right = (remainder.sign == 0) || (remainder.sign == numerator->sign);
    return anchor_exact_equal(&rebuilt, numerator) && divide_magnitude_below(&remainder, divisor) && signed_right;
}

static unsigned int divide_width(unsigned int most)
{
    return 1u + (divide_draw() % most);
}

int main(void)
{
    printf("  exact integer division\n");

    unsigned int held = 0u;
    for (unsigned int trial = 0u; trial < DIVIDE_TRIALS; trial++)
    {
        AnchorExactInteger numerator;
        AnchorExactInteger divisor;
        const unsigned int top = divide_width(8u);
        divide_value(&numerator, top, 1);
        do
        {
            divide_value(&divisor, divide_width(top), 1);
        } while (divisor.sign == 0);
        held += (unsigned int)divide_holds(&numerator, &divisor);
    }
    check("long division rebuilds its numerator on edge-shaped limbs to 8 wide", held == DIVIDE_TRIALS);

    held = 0u;
    for (unsigned int trial = 0u; trial < DIVIDE_WIDE_TRIALS; trial++)
    {
        AnchorExactInteger numerator;
        AnchorExactInteger divisor;
        // the product check needs quotient . divisor inside the width, which the numerator bounds
        const unsigned int top = divide_width(ANCHOR_EXACT_LIMBS - 1u);
        divide_value(&numerator, top, (int)(trial & 1u));
        do
        {
            divide_value(&divisor, divide_width(top), (int)(trial & 1u));
        } while (divisor.sign == 0);
        held += (unsigned int)divide_holds(&numerator, &divisor);
    }
    check("long division rebuilds its numerator at every width", held == DIVIDE_WIDE_TRIALS);

    // the add-back case of algorithm D: the estimate from the top limbs is one high
    {
        AnchorExactInteger numerator;
        AnchorExactInteger divisor;
        anchor_exact_zero(&numerator);
        anchor_exact_zero(&divisor);
        numerator.limb[0] = 0u;
        numerator.limb[1] = 0u;
        numerator.limb[2] = 0x80000000u;
        numerator.limb[3] = 0x7FFFFFFFu;
        numerator.sign = 1;
        divisor.limb[0] = 1u;
        divisor.limb[1] = 0u;
        divisor.limb[2] = 0x80000000u;
        divisor.sign = 1;
        check("long division holds where the estimate runs high", divide_holds(&numerator, &divisor));
    }

    {
        AnchorExactInteger numerator;
        AnchorExactInteger zero;
        AnchorExactInteger quotient;
        AnchorExactInteger remainder;
        divide_value(&numerator, 4u, 0);
        anchor_exact_zero(&zero);
        check("a zero divisor is refused",
              (anchor_exact_divide(&numerator, &zero, &quotient, &remainder) == ANCHOR_EXACT_BY_ZERO)
                  && (anchor_exact_divide_exact(&numerator, &zero, &quotient) == ANCHOR_EXACT_BY_ZERO));
    }

    held = 0u;
    unsigned int refused = 0u;
    for (unsigned int trial = 0u; trial < EXACT_TRIALS; trial++)
    {
        AnchorExactInteger quotient;
        AnchorExactInteger divisor;
        AnchorExactInteger product;
        AnchorExactInteger found;
        const unsigned int quotient_limbs = divide_width(ANCHOR_EXACT_LIMBS / 2u);
        divide_value(&quotient, quotient_limbs, (int)(trial & 1u));
        do
        {
            divide_value(&divisor, divide_width(ANCHOR_EXACT_LIMBS / 2u), (int)(trial & 1u));
        } while (divisor.sign == 0);
        // a divisor with twos in it half the time
        if ((trial & 2u) != 0u)
        {
            divisor.limb[0] &= ~0xFFu;
            if ((divisor.limb[0] == 0u) && (divisor.limb[1] == 0u))
            {
                divisor.limb[1] = 1u;
                divisor.sign = (divisor.sign == 0) ? 1 : divisor.sign;
            }
        }
        if (anchor_exact_multiply(&quotient, &divisor, &product) != ANCHOR_EXACT_OK)
        {
            continue;
        }
        held += ((anchor_exact_divide_exact(&product, &divisor, &found) == ANCHOR_EXACT_OK)
                 && anchor_exact_equal(&found, &quotient))
              ? 1u
              : 0u;
        // one more than a nonzero product is not a multiple of a divisor above one
        AnchorExactInteger one;
        AnchorExactInteger off;
        AnchorExactInteger magnitude = divisor;
        magnitude.sign = 1;
        anchor_exact_zero(&one);
        one.limb[0] = 1u;
        one.sign = 1;
        if ((product.sign != 0) && (anchor_exact_compare(&magnitude, &one) > 0)
            && (anchor_exact_add(&product, &one, &off) == ANCHOR_EXACT_OK))
        {
            refused += (anchor_exact_divide_exact(&off, &divisor, &found) == ANCHOR_EXACT_NOT_EXACT) ? 1u : 0u;
        }
        else
        {
            refused += 1u;
        }
    }
    check("exact division returns the quotient of every product, odd and even divisors", held == EXACT_TRIALS);
    check("exact division refuses a value that leaves a remainder", refused == EXACT_TRIALS);

    held = 0u;
    for (unsigned int trial = 0u; trial < GCD_TRIALS; trial++)
    {
        AnchorExactInteger shared;
        AnchorExactInteger first;
        AnchorExactInteger second;
        AnchorExactInteger left;
        AnchorExactInteger right;
        AnchorExactInteger common;
        divide_value(&shared, divide_width(ANCHOR_EXACT_LIMBS / 4u), 0);
        divide_value(&first, divide_width(ANCHOR_EXACT_LIMBS / 4u), (int)(trial & 1u));
        divide_value(&second, divide_width(ANCHOR_EXACT_LIMBS / 4u), (int)(trial & 1u));
        if ((shared.sign == 0) || (anchor_exact_multiply(&shared, &first, &left) != ANCHOR_EXACT_OK)
            || (anchor_exact_multiply(&shared, &second, &right) != ANCHOR_EXACT_OK))
        {
            held += 1u;
            continue;
        }
        anchor_exact_gcd(&left, &right, &common);
        AnchorExactInteger left_part;
        AnchorExactInteger right_part;
        AnchorExactInteger again;
        AnchorExactInteger one;
        AnchorExactInteger quotient;
        AnchorExactInteger remainder;
        anchor_exact_zero(&one);
        one.limb[0] = 1u;
        one.sign = 1;
        int ok = (common.sign > 0);
        ok = ok && (anchor_exact_divide_exact(&left, &common, &left_part) == ANCHOR_EXACT_OK);
        ok = ok && (anchor_exact_divide_exact(&right, &common, &right_part) == ANCHOR_EXACT_OK);
        if (ok && (left_part.sign != 0) && (right_part.sign != 0))
        {
            anchor_exact_gcd(&left_part, &right_part, &again);
            ok = anchor_exact_equal(&again, &one);
        }
        // the shared factor divides the gcd
        ok = ok && (anchor_exact_divide(&common, &shared, &quotient, &remainder) == ANCHOR_EXACT_OK) && (remainder.sign == 0);
        held += ok ? 1u : 0u;
    }
    check("the gcd divides both, holds the shared factor, and leaves coprime cofactors", held == GCD_TRIALS);

    // against Euclid on the long division, which is proved above apart from the gcd
    held = 0u;
    for (unsigned int trial = 0u; trial < GCD_TRIALS; trial++)
    {
        AnchorExactInteger shared;
        AnchorExactInteger first;
        AnchorExactInteger second;
        AnchorExactInteger left;
        AnchorExactInteger right;
        AnchorExactInteger common;
        divide_value(&shared, divide_width(ANCHOR_EXACT_LIMBS / 4u), (int)(trial & 1u));
        divide_value(&first, divide_width(ANCHOR_EXACT_LIMBS / 4u), (int)(trial & 1u));
        divide_value(&second, divide_width(ANCHOR_EXACT_LIMBS / 4u), 0);
        if ((anchor_exact_multiply(&shared, &first, &left) != ANCHOR_EXACT_OK)
            || (anchor_exact_multiply(&shared, &second, &right) != ANCHOR_EXACT_OK))
        {
            held += 1u;
            continue;
        }
        AnchorExactInteger larger = left;
        AnchorExactInteger smaller = right;
        larger.sign = (larger.sign == 0) ? 0 : 1;
        smaller.sign = (smaller.sign == 0) ? 0 : 1;
        while (smaller.sign != 0)
        {
            AnchorExactInteger quotient;
            AnchorExactInteger remainder;
            (void)anchor_exact_divide(&larger, &smaller, &quotient, &remainder);
            larger = smaller;
            smaller = remainder;
        }
        held += ((anchor_exact_gcd(&left, &right, &common) == ANCHOR_EXACT_OK) && anchor_exact_equal(&common, &larger)) ? 1u : 0u;
    }
    check("the gcd equals Euclid's on the long division", held == GCD_TRIALS);

    {
        AnchorExactInteger zero;
        AnchorExactInteger value;
        AnchorExactInteger common;
        anchor_exact_zero(&zero);
        divide_value(&value, 5u, 0);
        anchor_exact_gcd(&zero, &value, &common);
        AnchorExactInteger magnitude = value;
        magnitude.sign = (value.sign == 0) ? 0 : 1;
        const int with_zero = anchor_exact_equal(&common, &magnitude);
        anchor_exact_gcd(&zero, &zero, &common);
        check("gcd(0, x) = |x| and gcd(0, 0) = 0", with_zero && (common.sign == 0));
    }

    printf("  exact divide test: %d checks, %d failed\n", s_checks, s_failed);
    return (s_failed == 0) ? 0 : 1;
}
