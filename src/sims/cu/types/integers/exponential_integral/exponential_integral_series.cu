// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// exponential_integral_series.cu: the brackets, every value an integer at 2^W rounded outward
#include "exponential_integral.h"

typedef AnchorExactInteger ExponentialWide;

// a value v held as low <= v 2^W <= high
typedef struct
{
    ExponentialWide low;
    ExponentialWide high;
} ExponentialSpan;

// the guard a reading starts at past the caller's bits, and what it grows by where the ends floor apart
#define EXPONENTIAL_GUARD_FIRST 32u
#define EXPONENTIAL_GUARD_STEP 32u

// set where an operation outgrows the build's exact width
static int s_exponential_short = 0;

static void exponential_took(AnchorExactStatus status)
{
    if (status != ANCHOR_EXACT_OK)
    {
        s_exponential_short = 1;
    }
}

static ExponentialWide exponential_unsigned(unsigned long long number)
{
    ExponentialWide value;
    sim_exact_unsigned(&value, number);
    return value;
}

static ExponentialWide exponential_power_two(unsigned int bits)
{
    ExponentialWide value;
    anchor_exact_zero(&value);
    if (bits >= (32u * ANCHOR_EXACT_LIMBS))
    {
        s_exponential_short = 1;
        return value;
    }
    value.limb[bits / 32u] = 1u << (bits % 32u);
    value.sign = 1;
    return value;
}

static ExponentialWide exponential_sum(const ExponentialWide &left, const ExponentialWide &right)
{
    ExponentialWide value;
    anchor_exact_zero(&value);
    exponential_took(anchor_exact_add(&left, &right, &value));
    return value;
}

static ExponentialWide exponential_difference(const ExponentialWide &left, const ExponentialWide &right)
{
    ExponentialWide value;
    anchor_exact_zero(&value);
    exponential_took(anchor_exact_subtract(&left, &right, &value));
    return value;
}

static ExponentialWide exponential_product(const ExponentialWide &left, const ExponentialWide &right)
{
    ExponentialWide value;
    anchor_exact_zero(&value);
    exponential_took(anchor_exact_multiply(&left, &right, &value));
    return value;
}

static ExponentialWide exponential_negated(ExponentialWide value)
{
    value.sign = -value.sign;
    return value;
}

// floor(numerator / divisor) for a positive divisor and a numerator of either sign: the division truncates toward
// zero, and a negative quotient with a remainder steps down one
static ExponentialWide exponential_floor(const ExponentialWide &numerator, const ExponentialWide &divisor)
{
    ExponentialWide quotient;
    ExponentialWide remainder;
    anchor_exact_zero(&quotient);
    anchor_exact_zero(&remainder);
    exponential_took(anchor_exact_divide(&numerator, &divisor, &quotient, &remainder));
    if ((numerator.sign < 0) && (remainder.sign != 0))
    {
        quotient = exponential_difference(quotient, exponential_unsigned(1ull));
    }
    return quotient;
}

// ceil(numerator / divisor) for a positive divisor: -floor(-numerator / divisor)
static ExponentialWide exponential_ceiling(const ExponentialWide &numerator, const ExponentialWide &divisor)
{
    return exponential_negated(exponential_floor(exponential_negated(numerator), divisor));
}

static int exponential_compare(const ExponentialWide &left, const ExponentialWide &right)
{
    return anchor_exact_compare(&left, &right);
}

// the span x is held in at 2^W, x = top / bottom
static ExponentialSpan exponential_scaled(const ExponentialWide &top, const ExponentialWide &bottom, unsigned int scale)
{
    const ExponentialWide lifted = exponential_product(top, exponential_power_two(scale));
    ExponentialSpan span;
    span.low = exponential_floor(lifted, bottom);
    span.high = exponential_ceiling(lifted, bottom);
    return span;
}

// e^x at 2^W for x = top / bottom >= 0. Term k is term k - 1 times x / k, floored low and ceiled high. The series
// stops at the first term N whose high end is at most 1 with N + 1 > x, and the tail past it, at most term N x /
// (N + 1 - x), is added to the high end
static ExponentialSpan exponential_rising(const ExponentialWide &top, const ExponentialWide &bottom, unsigned int scale)
{
    ExponentialSpan term;
    term.low = exponential_power_two(scale);
    term.high = term.low;
    ExponentialSpan total = term;
    const ExponentialWide one = exponential_unsigned(1ull);
    for (unsigned long long index = 1ull; (s_exponential_short == 0) && (top.sign != 0); index += 1ull)
    {
        const ExponentialWide divisor = exponential_product(bottom, exponential_unsigned(index));
        term.low = exponential_floor(exponential_product(term.low, top), divisor);
        term.high = exponential_ceiling(exponential_product(term.high, top), divisor);
        total.low = exponential_sum(total.low, term.low);
        total.high = exponential_sum(total.high, term.high);
        const ExponentialWide past = exponential_product(bottom, exponential_unsigned(index + 1ull));
        if ((exponential_compare(past, top) > 0) && (exponential_compare(term.high, one) <= 0))
        {
            total.high = exponential_sum(
                total.high, exponential_ceiling(exponential_product(term.high, top), exponential_difference(past, top)));
            break;
        }
    }
    return total;
}

// 1 / v at 2^W for a span v >= 1 at 2^W, its ends swapped
static ExponentialSpan exponential_turned(const ExponentialSpan &value, unsigned int scale)
{
    const ExponentialWide square = exponential_power_two(2u * scale);
    ExponentialSpan span;
    span.low = exponential_floor(square, value.high);
    span.high = exponential_ceiling(square, value.low);
    return span;
}

// artanh(top / bottom) at 2^W for 0 <= top < bottom. Term k is y^(2k + 1) / (2k + 1), its power the last times y^2,
// each floored low and ceiled high. It stops where the power's high end is at most 1, and the tail past term N, at
// most y^(2N + 1) y^2 / ((2N + 3) (1 - y^2)), is added to the high end
static ExponentialSpan exponential_artanh(const ExponentialWide &top, const ExponentialWide &bottom,
                                          unsigned int scale)
{
    ExponentialSpan power = exponential_scaled(top, bottom, scale);
    ExponentialSpan total = power;
    if (top.sign == 0)
    {
        return total;
    }
    const ExponentialWide top_square = exponential_product(top, top);
    const ExponentialWide bottom_square = exponential_product(bottom, bottom);
    const ExponentialWide room = exponential_difference(bottom_square, top_square);
    const ExponentialWide one = exponential_unsigned(1ull);
    for (unsigned long long index = 1ull; s_exponential_short == 0; index += 1ull)
    {
        power.low = exponential_floor(exponential_product(power.low, top_square), bottom_square);
        power.high = exponential_ceiling(exponential_product(power.high, top_square), bottom_square);
        const ExponentialWide odd = exponential_unsigned((2ull * index) + 1ull);
        total.low = exponential_sum(total.low, exponential_floor(power.low, odd));
        total.high = exponential_sum(total.high, exponential_ceiling(power.high, odd));
        if (exponential_compare(power.high, one) <= 0)
        {
            const ExponentialWide next_odd = exponential_unsigned((2ull * index) + 3ull);
            total.high = exponential_sum(total.high,
                                         exponential_ceiling(exponential_product(power.high, top_square),
                                                             exponential_product(next_odd, room)));
            break;
        }
    }
    return total;
}

// ln 2 = 2 artanh(1/3) at 2^W
static ExponentialSpan exponential_logarithm_two(unsigned int scale)
{
    const ExponentialSpan half = exponential_artanh(exponential_unsigned(1ull), exponential_unsigned(3ull), scale);
    ExponentialSpan span;
    span.low = exponential_sum(half.low, half.low);
    span.high = exponential_sum(half.high, half.high);
    return span;
}

// ln n at 2^W for a whole n >= 1: e ln 2 + 2 artanh((n - 2^e) / (n + 2^e)), 2^e the power of two nearest n, which
// leaves |y| at most 1/3
static ExponentialSpan exponential_logarithm_whole(const ExponentialWide &whole, unsigned int scale)
{
    ExponentialSpan span;
    anchor_exact_zero(&span.low);
    anchor_exact_zero(&span.high);
    const unsigned long long length = sim_exact_bits(&whole);
    if (length <= 1ull)
    {
        return span;
    }
    const unsigned int below = (unsigned int)(length - 1ull);
    const ExponentialWide floor_power = exponential_power_two(below);
    const ExponentialWide ceiling_power = exponential_power_two(below + 1u);
    const int upper = exponential_compare(exponential_difference(whole, floor_power),
                                          exponential_difference(ceiling_power, whole)) > 0;
    const unsigned int exponent = upper ? (below + 1u) : below;
    const ExponentialWide power = upper ? ceiling_power : floor_power;
    const ExponentialWide offset = exponential_difference(whole, power);
    const int negative = offset.sign < 0;
    ExponentialWide magnitude = offset;
    magnitude.sign = (offset.sign == 0) ? 0 : 1;
    const ExponentialSpan near = exponential_artanh(magnitude, exponential_sum(whole, power), scale);
    const ExponentialSpan two = exponential_logarithm_two(scale);
    const ExponentialWide count = exponential_unsigned(exponent);
    const ExponentialWide near_low = exponential_sum(near.low, near.low);
    const ExponentialWide near_high = exponential_sum(near.high, near.high);
    span.low = exponential_product(count, two.low);
    span.high = exponential_product(count, two.high);
    span.low = negative ? exponential_difference(span.low, near_high) : exponential_sum(span.low, near_low);
    span.high = negative ? exponential_difference(span.high, near_low) : exponential_sum(span.high, near_high);
    return span;
}

// ln(top / bottom) at 2^W: ln top - ln bottom
static ExponentialSpan exponential_logarithm(const ExponentialWide &top, const ExponentialWide &bottom,
                                             unsigned int scale)
{
    const ExponentialSpan above = exponential_logarithm_whole(top, scale);
    const ExponentialSpan under = exponential_logarithm_whole(bottom, scale);
    ExponentialSpan span;
    span.low = exponential_difference(above.low, under.high);
    span.high = exponential_difference(above.high, under.low);
    return span;
}

// the continued fraction for e^x E1(x) cut at element `depth`, at 2^W. Element 1 is (1, x), element 2j is (j, 1) and
// element 2j + 1 is (j, x). Evaluated from the deepest level up: level i is its own denominator plus the next
// element's numerator over level i + 1, each division rounded outward
static ExponentialSpan exponential_convergent(const ExponentialSpan &x, unsigned long long depth, unsigned int scale)
{
    const ExponentialWide unit = exponential_power_two(scale);
    const ExponentialWide square = exponential_power_two(2u * scale);
    ExponentialSpan level;
    level.low = ((depth & 1ull) != 0ull) ? x.low : unit;
    level.high = ((depth & 1ull) != 0ull) ? x.high : unit;
    for (unsigned long long index = depth - 1ull; (index >= 1ull) && (s_exponential_short == 0); index -= 1ull)
    {
        const unsigned long long next = index + 1ull;
        const ExponentialWide numerator = exponential_product(exponential_unsigned(next / 2ull), square);
        const ExponentialSpan own = ((index & 1ull) != 0ull) ? x : ExponentialSpan{unit, unit};
        ExponentialSpan above;
        above.low = exponential_sum(own.low, exponential_floor(numerator, level.high));
        above.high = exponential_sum(own.high, exponential_ceiling(numerator, level.low));
        level = above;
    }
    return exponential_turned(level, scale);
}

// e^x E1(x) at 2^W for a span x > 0: the convergents at `depth` and `depth + 1` bracket it, the depth doubling until
// the two agree to within 2^(guard - 8) of one another or the rounding of so deep a fraction would pass that
static ExponentialSpan exponential_fraction(const ExponentialSpan &x, unsigned int scale, unsigned int guard)
{
    const ExponentialWide allowed = exponential_power_two(guard - 8u);
    const unsigned long long deepest = 1ull << ((guard > 12u) ? ((guard - 12u < 40u) ? (guard - 12u) : 40u) : 1u);
    ExponentialSpan span;
    for (unsigned long long depth = 8ull; s_exponential_short == 0; depth *= 2ull)
    {
        const ExponentialSpan first = exponential_convergent(x, depth, scale);
        const ExponentialSpan second = exponential_convergent(x, depth + 1ull, scale);
        span.low = (exponential_compare(first.low, second.low) < 0) ? first.low : second.low;
        span.high = (exponential_compare(first.high, second.high) > 0) ? first.high : second.high;
        if ((exponential_compare(exponential_difference(span.high, span.low), allowed) <= 0) || (depth >= deepest))
        {
            break;
        }
    }
    return span;
}

// S(x) = sum over k >= 1 of (-1)^(k + 1) x^k / (k k!) at 2^W, x = top / bottom >= 0. x^k / k! is carried as e^x's
// terms are, and each term is that over k, floored low and ceiled high. Once k - 1 >= x the terms fall, and S lies
// between the partial sums through k - 1 and through k: the series stops there at the first k whose term's high end
// is at most 1
static ExponentialSpan exponential_alternating(const ExponentialWide &top, const ExponentialWide &bottom,
                                               unsigned int scale)
{
    ExponentialSpan power;
    power.low = exponential_power_two(scale);
    power.high = power.low;
    ExponentialSpan total;
    anchor_exact_zero(&total.low);
    anchor_exact_zero(&total.high);
    ExponentialSpan before = total;
    const ExponentialWide one = exponential_unsigned(1ull);
    for (unsigned long long index = 1ull; (s_exponential_short == 0) && (top.sign != 0); index += 1ull)
    {
        const ExponentialWide count = exponential_unsigned(index);
        const ExponentialWide divisor = exponential_product(bottom, count);
        power.low = exponential_floor(exponential_product(power.low, top), divisor);
        power.high = exponential_ceiling(exponential_product(power.high, top), divisor);
        const ExponentialWide term_low = exponential_floor(power.low, count);
        const ExponentialWide term_high = exponential_ceiling(power.high, count);
        before = total;
        if ((index & 1ull) != 0ull)
        {
            total.low = exponential_sum(total.low, term_low);
            total.high = exponential_sum(total.high, term_high);
        }
        else
        {
            total.low = exponential_difference(total.low, term_high);
            total.high = exponential_difference(total.high, term_low);
        }
        const ExponentialWide fallen = exponential_product(bottom, exponential_unsigned(index - 1ull));
        if ((exponential_compare(fallen, top) >= 0) && (exponential_compare(term_high, one) <= 0))
        {
            ExponentialSpan span;
            span.low = (exponential_compare(before.low, total.low) < 0) ? before.low : total.low;
            span.high = (exponential_compare(before.high, total.high) > 0) ? before.high : total.high;
            return span;
        }
    }
    return total;
}

// E1(x) at 2^W by the continued fraction: e^x E1(x) times e^(-x), both positive
static ExponentialSpan exponential_integral_span(const ExponentialWide &top, const ExponentialWide &bottom,
                                                 unsigned int scale, unsigned int guard)
{
    const ExponentialSpan fraction = exponential_fraction(exponential_scaled(top, bottom, scale), scale, guard);
    const ExponentialSpan decay = exponential_turned(exponential_rising(top, bottom, scale), scale);
    const ExponentialWide unit = exponential_power_two(scale);
    ExponentialSpan span;
    span.low = exponential_floor(exponential_product(fraction.low, decay.low), unit);
    span.high = exponential_ceiling(exponential_product(fraction.high, decay.high), unit);
    return span;
}

// gamma at 2^W: S(1) - E1(1)
static ExponentialSpan exponential_gamma(unsigned int scale, unsigned int guard)
{
    const ExponentialWide one = exponential_unsigned(1ull);
    const ExponentialSpan sum = exponential_alternating(one, one, scale);
    const ExponentialSpan integral = exponential_integral_span(one, one, scale, guard);
    ExponentialSpan span;
    span.low = exponential_difference(sum.low, integral.high);
    span.high = exponential_difference(sum.high, integral.low);
    return span;
}

// the function a reading brackets
enum
{
    EXPONENTIAL_READ_INTEGRAL = 0,
    EXPONENTIAL_READ_SERIES = 1,
    EXPONENTIAL_READ_NEGATIVE = 2,
    EXPONENTIAL_READ_LOGARITHM = 3,
    EXPONENTIAL_READ_GAMMA = 4
};

static ExponentialSpan exponential_span_of(unsigned int read, const ExponentialWide &top, const ExponentialWide &bottom,
                                           unsigned int scale, unsigned int guard)
{
    if (read == EXPONENTIAL_READ_INTEGRAL)
    {
        return exponential_integral_span(top, bottom, scale, guard);
    }
    if (read == EXPONENTIAL_READ_NEGATIVE)
    {
        return exponential_turned(exponential_rising(top, bottom, scale), scale);
    }
    if (read == EXPONENTIAL_READ_LOGARITHM)
    {
        return exponential_logarithm(top, bottom, scale);
    }
    const ExponentialSpan gamma = exponential_gamma(scale, guard);
    if (read == EXPONENTIAL_READ_GAMMA)
    {
        return gamma;
    }
    // E1(x) = -gamma - ln x + S(x)
    const ExponentialSpan logarithm = exponential_logarithm(top, bottom, scale);
    const ExponentialSpan sum = exponential_alternating(top, bottom, scale);
    ExponentialSpan span;
    span.low = exponential_difference(exponential_difference(sum.low, gamma.high), logarithm.high);
    span.high = exponential_difference(exponential_difference(sum.high, gamma.low), logarithm.low);
    return span;
}

// A reading at 2^bits: the span at 2^(bits + guard), its ends floored to 2^bits, the guard grown until they agree.
// EXPONENTIAL_INTEGRAL_WIDTH where the build's width cannot hold the span at some guard, and
// EXPONENTIAL_INTEGRAL_DOMAIN where x is outside the function's domain
static int exponential_read(unsigned int read, const SimRational *x, unsigned int bits,
                            ExponentialIntegralBracket *bracket)
{
    const ExponentialWide top = (x != NULL) ? x->numerator : exponential_unsigned(1ull);
    const ExponentialWide bottom = (x != NULL) ? x->denominator : exponential_unsigned(1ull);
    const int positive_only = (read != EXPONENTIAL_READ_NEGATIVE) && (read != EXPONENTIAL_READ_GAMMA);
    if ((bottom.sign <= 0) || (top.sign < 0) || (positive_only && (top.sign == 0)))
    {
        return EXPONENTIAL_INTEGRAL_DOMAIN;
    }
    for (unsigned int guard = EXPONENTIAL_GUARD_FIRST;; guard += EXPONENTIAL_GUARD_STEP)
    {
        s_exponential_short = 0;
        const unsigned int scale = bits + guard;
        const ExponentialSpan span = exponential_span_of(read, top, bottom, scale, guard);
        const ExponentialWide step = exponential_power_two(guard);
        const ExponentialWide low = exponential_floor(span.low, step);
        const ExponentialWide high = exponential_floor(span.high, step);
        if (s_exponential_short != 0)
        {
            return EXPONENTIAL_INTEGRAL_WIDTH;
        }
        if (exponential_compare(low, high) == 0)
        {
            bracket->low = low;
            bracket->high = exponential_ceiling(span.high, step);
            bracket->floor_value = low;
            bracket->bits = bits;
            return EXPONENTIAL_INTEGRAL_HELD;
        }
    }
}

int exponential_integral_floor(const SimRational *x, unsigned int bits, ExponentialIntegralBracket *bracket)
{
    return exponential_read(EXPONENTIAL_READ_INTEGRAL, x, bits, bracket);
}

int exponential_integral_series_floor(const SimRational *x, unsigned int bits, ExponentialIntegralBracket *bracket)
{
    return exponential_read(EXPONENTIAL_READ_SERIES, x, bits, bracket);
}

int exponential_negative_floor(const SimRational *x, unsigned int bits, ExponentialIntegralBracket *bracket)
{
    return exponential_read(EXPONENTIAL_READ_NEGATIVE, x, bits, bracket);
}

int logarithm_floor(const SimRational *x, unsigned int bits, ExponentialIntegralBracket *bracket)
{
    return exponential_read(EXPONENTIAL_READ_LOGARITHM, x, bits, bracket);
}

int euler_gamma_floor(unsigned int bits, ExponentialIntegralBracket *bracket)
{
    return exponential_read(EXPONENTIAL_READ_GAMMA, NULL, bits, bracket);
}

unsigned int exponential_integral_width(void)
{
    return 32u * ANCHOR_EXACT_LIMBS;
}
