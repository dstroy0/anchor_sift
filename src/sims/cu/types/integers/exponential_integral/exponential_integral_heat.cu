// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// exponential_integral_heat.cu: x^h, Gamma(1 + h), the heat exterior H(Z) and its pressure, every value an integer at
// 2^W rounded outward (exponential_integral.h)
#include "exponential_integral_internal.h"

// the guard a reading starts at past the caller's bits, and what it grows by where the ends floor apart
#define HEAT_GUARD_FIRST 32u
#define HEAT_GUARD_STEP 32u
// z0 = W 45 / 64 + 16: 45 / 64 is past ln 2, and the series at 1 / z0 holds its least term below one unit
#define HEAT_FAR_SHARE 45u
#define HEAT_FAR_SHIFT 6u
#define HEAT_FAR_MARGIN 16u
// the bits a Taylor step's terms fall past W, beyond twice the bits of its bound, and the longest step
#define HEAT_STEP_MARGIN 24u
#define HEAT_STEP_LONGEST 4ull

// the function a reading brackets
enum
{
    HEAT_READ_POWER = 0,
    HEAT_READ_GAMMA = 1,
    HEAT_READ_EXTERIOR = 2,
    HEAT_READ_PRESSURE = 3
};

// a reading's arguments; each function reads the ones it names
typedef struct
{
    SimRational x;
    SimRational h;
    SimRational eta;
    SimRational c;
} HeatArguments;

static ExponentialSpan heat_point(const ExponentialWide &value)
{
    ExponentialSpan span;
    span.low = value;
    span.high = value;
    return span;
}

static ExponentialSpan heat_zero(void)
{
    return heat_point(exponential_unsigned(0ull));
}

static ExponentialSpan heat_span_sum(const ExponentialSpan &left, const ExponentialSpan &right)
{
    ExponentialSpan span;
    span.low = exponential_sum(left.low, right.low);
    span.high = exponential_sum(left.high, right.high);
    return span;
}

// the span widened by `units` at each end
static ExponentialSpan heat_span_widened(const ExponentialSpan &value, const ExponentialWide &units)
{
    ExponentialSpan span;
    span.low = exponential_difference(value.low, units);
    span.high = exponential_sum(value.high, units);
    return span;
}

// the least and the greatest of two spans' ends together
static ExponentialSpan heat_span_hull(const ExponentialSpan &left, const ExponentialSpan &right)
{
    ExponentialSpan span;
    span.low = (exponential_compare(left.low, right.low) < 0) ? left.low : right.low;
    span.high = (exponential_compare(left.high, right.high) > 0) ? left.high : right.high;
    return span;
}

// v times top / bottom, bottom > 0 and top of either sign: a negative top turns the ends over
static ExponentialSpan heat_span_scaled(const ExponentialSpan &value, const ExponentialWide &top,
                                        const ExponentialWide &bottom)
{
    ExponentialSpan span;
    const ExponentialWide &first = (top.sign >= 0) ? value.low : value.high;
    const ExponentialWide &second = (top.sign >= 0) ? value.high : value.low;
    span.low = exponential_floor(exponential_product(first, top), bottom);
    span.high = exponential_ceiling(exponential_product(second, top), bottom);
    return span;
}

static ExponentialSpan heat_span_rational(const ExponentialSpan &value, const SimRational &factor)
{
    return heat_span_scaled(value, factor.numerator, factor.denominator);
}

// the least and the greatest of the four products of two spans' ends, at 2^(2W)
static void heat_product_ends(const ExponentialSpan &left, const ExponentialSpan &right, ExponentialWide *least,
                              ExponentialWide *most)
{
    const ExponentialWide products[4] = {
        exponential_product(left.low, right.low), exponential_product(left.low, right.high),
        exponential_product(left.high, right.low), exponential_product(left.high, right.high)};
    *least = products[0];
    *most = products[0];
    for (unsigned int at = 1u; at < 4u; at += 1u)
    {
        *least = (exponential_compare(products[at], *least) < 0) ? products[at] : *least;
        *most = (exponential_compare(products[at], *most) > 0) ? products[at] : *most;
    }
}

static ExponentialSpan heat_span_product(const ExponentialSpan &left, const ExponentialSpan &right,
                                         const ExponentialWide &unit)
{
    ExponentialWide least;
    ExponentialWide most;
    heat_product_ends(left, right, &least, &most);
    ExponentialSpan span;
    span.low = exponential_floor(least, unit);
    span.high = exponential_ceiling(most, unit);
    return span;
}

static SimRational heat_rational(const ExponentialWide &top, const ExponentialWide &bottom)
{
    SimRational value;
    value.numerator = top;
    value.denominator = bottom;
    sim_rational_settle(&value);
    return value;
}

static SimRational heat_whole(unsigned long long number)
{
    return sim_rational((long long)number, 1ll);
}

// value^power for a whole power, 0 where the width cannot hold it
static ExponentialWide heat_raised(const ExponentialWide &value, unsigned long long power)
{
    ExponentialWide result = exponential_unsigned(1ull);
    for (unsigned long long at = 0ull; (at < power) && (exponential_short() == 0); at += 1ull)
    {
        result = exponential_product(result, value);
    }
    return result;
}

// the whole root of `value` of degree `degree` into `root`: 1 where it is exact. A root past 1 needs the value's bits
// to reach the degree, and is found by halving between 2^(b / degree) and 2^(b / degree + 1)
static int heat_root(const ExponentialWide &value, unsigned long long degree, ExponentialWide *root)
{
    const ExponentialWide one = exponential_unsigned(1ull);
    if (exponential_compare(value, one) == 0)
    {
        *root = one;
        return 1;
    }
    const unsigned long long length = sim_exact_bits(&value);
    if ((degree == 0ull) || (length < degree))
    {
        return 0;
    }
    ExponentialWide low = exponential_power_two((unsigned int)((length - 1ull) / degree));
    ExponentialWide high = exponential_power_two((unsigned int)((length - 1ull) / degree) + 1u);
    while (exponential_compare(exponential_difference(high, low), one) > 0)
    {
        const ExponentialWide middle = exponential_floor(exponential_sum(low, high), exponential_unsigned(2ull));
        if (exponential_compare(heat_raised(middle, degree), value) <= 0)
        {
            low = middle;
        }
        else
        {
            high = middle;
        }
    }
    *root = low;
    return exponential_compare(heat_raised(low, degree), value) == 0;
}

// e^(t / 2^W) at 2^W for a whole t of either sign
static ExponentialSpan heat_exponential(const ExponentialWide &exponent, unsigned int scale)
{
    unsigned long long last = 0ull;
    ExponentialWide magnitude = exponent;
    magnitude.sign = (exponent.sign == 0) ? 0 : 1;
    const ExponentialSpan rising = exponential_rising_host(magnitude, exponential_power_two(scale), scale, &last);
    return (exponent.sign < 0) ? exponential_turned(rising, scale) : rising;
}

// x^h at 2^W for x = top / bottom > 0 and h = power_top / power_bottom of either sign: e^(h ln x), the exponential
// read at each end of h ln x's span
static ExponentialSpan heat_power(const ExponentialWide &top, const ExponentialWide &bottom,
                                  const ExponentialWide &power_top, const ExponentialWide &power_bottom,
                                  unsigned int scale)
{
    const ExponentialSpan logarithm = exponential_logarithm(&g_exponential_host, top, bottom, scale);
    const ExponentialSpan exponent = heat_span_scaled(logarithm, power_top, power_bottom);
    ExponentialSpan span;
    span.low = heat_exponential(exponent.low, scale).low;
    span.high = heat_exponential(exponent.high, scale).high;
    return span;
}

// x^h exactly where h = p / q and x is a q-th power y^q, y^p then a rational: 1 with `span` the floor and ceiling of
// y^p at 2^W
static int heat_power_exact(const SimRational &x, const SimRational &h, unsigned int scale, ExponentialSpan *span)
{
    ExponentialWide top_root;
    ExponentialWide bottom_root;
    const unsigned long long degree_bits = sim_exact_bits(&h.denominator);
    if (degree_bits > 32ull)
    {
        return 0;
    }
    const unsigned long long degree = (unsigned long long)h.denominator.limb[0];
    if (!heat_root(x.numerator, degree, &top_root) || !heat_root(x.denominator, degree, &bottom_root))
    {
        return 0;
    }
    ExponentialWide magnitude = h.numerator;
    magnitude.sign = (magnitude.sign == 0) ? 0 : 1;
    if (sim_exact_bits(&magnitude) > 32ull)
    {
        return 0;
    }
    const unsigned long long power = (magnitude.sign == 0) ? 0ull : (unsigned long long)magnitude.limb[0];
    if (power > (unsigned long long)exponential_integral_width())
    {
        return 0;
    }
    const ExponentialWide raised_top = heat_raised(top_root, power);
    const ExponentialWide raised_bottom = heat_raised(bottom_root, power);
    const int negative = h.numerator.sign < 0;
    *span = exponential_scaled(negative ? raised_bottom : raised_top, negative ? raised_top : raised_bottom, scale);
    return 1;
}

static ExponentialSpan heat_power_of(const SimRational &x, const SimRational &h, unsigned int scale)
{
    ExponentialSpan span;
    if (heat_power_exact(x, h, scale, &span))
    {
        return span;
    }
    return heat_power(x.numerator, x.denominator, h.numerator, h.denominator, scale);
}

// T = W 45 / 64 + 16
static unsigned long long heat_far(unsigned int scale)
{
    return (((unsigned long long)scale * HEAT_FAR_SHARE) >> HEAT_FAR_SHIFT) + HEAT_FAR_MARGIN;
}

// Gamma(1 + h) at 2^W for h = p / q, 0 <= h < 1. The sum over k >= 0 of T^k / (1 + h)_(k + 1) rises to k near T and
// falls past it; it stops at the first term N whose high end is at most 1 once the ratio T q / (p + (N + 2) q) is below
// 1, and the tail past it, at most term N T q / (p + (N + 2) q - T q), is added to the high end
static ExponentialSpan heat_gamma(const SimRational &h, unsigned int scale)
{
    const ExponentialWide unit = exponential_power_two(scale);
    if (h.numerator.sign == 0)
    {
        return heat_point(unit);
    }
    const unsigned long long far = heat_far(scale);
    const ExponentialWide &p = h.numerator;
    const ExponentialWide &q = h.denominator;
    const ExponentialWide far_wide = exponential_unsigned(far);
    const ExponentialWide far_q = exponential_product(far_wide, q);
    const ExponentialWide one = exponential_unsigned(1ull);
    ExponentialSpan term = exponential_scaled(q, exponential_sum(q, p), scale);
    ExponentialSpan total = term;
    for (unsigned long long index = 0ull; exponential_short() == 0; index += 1ull)
    {
        const ExponentialWide divisor = exponential_sum(p, exponential_product(exponential_unsigned(index + 2ull), q));
        term.low = exponential_floor(exponential_product(term.low, far_q), divisor);
        term.high = exponential_ceiling(exponential_product(term.high, far_q), divisor);
        total = heat_span_sum(total, term);
        const ExponentialWide past =
            exponential_sum(p, exponential_product(exponential_unsigned(index + 3ull), q));
        if ((exponential_compare(past, far_q) > 0) && (exponential_compare(term.high, one) <= 0))
        {
            total.high = exponential_sum(total.high, exponential_ceiling(exponential_product(term.high, far_q),
                                                                         exponential_difference(past, far_q)));
            break;
        }
    }
    // T sum + theta, theta between 1 and 1 + h / T = (T q + p) / (T q)
    ExponentialSpan inner;
    inner.low = exponential_sum(exponential_product(far_wide, total.low), unit);
    inner.high = exponential_sum(exponential_product(far_wide, total.high),
                                 exponential_ceiling(exponential_product(unit, exponential_sum(far_q, p)), far_q));
    // e^(-T) is below 2^-W, and the sum near 2^(2W): it is read at 2^(2W + 16) and the product brought back to 2^W
    const unsigned int deep = (2u * scale) + 16u;
    unsigned long long last = 0ull;
    const ExponentialSpan decay = exponential_turned(exponential_rising_host(far_wide, one, deep, &last), deep);
    const ExponentialSpan lifted = heat_power_of(heat_whole(far), h, scale);
    return heat_span_product(heat_span_product(inner, decay, exponential_power_two(deep)), lifted, unit);
}

// H's series at Z = top / bottom, h = p / q: sum over k of (-1)^k (h)_k (1 + h)_(k + extra) Z^k / k!, extra 0 for H
// and 1 for the series of -U'(1 + h, 2, z) z^(2 + h). Term k + 1 is term k times (p + k q) (p + (1 + k + extra) q) Z /
// (q^2 (k + 1)). It stops at the first term at most one unit, or the first whose exact ratio to the last is at least
// 1, as the rounding of terms near the least is as wide as they are, and the value lies between the
// sum before that term and the sum with it. `terms`, where given, takes every term to the last, each signed
static ExponentialSpan heat_series(const ExponentialWide &top, const ExponentialWide &bottom, const SimRational &h,
                                   unsigned int extra, unsigned int scale, std::vector<ExponentialSpan> *terms)
{
    const ExponentialWide &p = h.numerator;
    const ExponentialWide &q = h.denominator;
    const ExponentialWide one = exponential_unsigned(1ull);
    ExponentialSpan magnitude =
        (extra != 0u) ? exponential_scaled(exponential_sum(q, p), q, scale) : heat_point(exponential_power_two(scale));
    ExponentialSpan total = magnitude;
    if (terms != NULL)
    {
        terms->clear();
        terms->push_back(magnitude);
    }
    const ExponentialWide divisor_part = exponential_product(exponential_product(q, q), bottom);
    for (unsigned long long index = 0ull; exponential_short() == 0; index += 1ull)
    {
        const ExponentialWide rise_first = exponential_sum(p, exponential_product(exponential_unsigned(index), q));
        const ExponentialWide rise_second =
            exponential_sum(p, exponential_product(exponential_unsigned(1ull + index + extra), q));
        const ExponentialWide multiplier = exponential_product(exponential_product(rise_first, rise_second), top);
        const ExponentialWide divisor = exponential_product(divisor_part, exponential_unsigned(index + 1ull));
        ExponentialSpan next;
        next.low = exponential_floor(exponential_product(magnitude.low, multiplier), divisor);
        next.high = exponential_ceiling(exponential_product(magnitude.high, multiplier), divisor);
        const int negative = (index & 1ull) == 0ull;
        ExponentialSpan signed_next = next;
        if (negative)
        {
            signed_next.low = exponential_difference(exponential_unsigned(0ull), next.high);
            signed_next.high = exponential_difference(exponential_unsigned(0ull), next.low);
        }
        if ((exponential_compare(next.high, one) <= 0) || (exponential_compare(multiplier, divisor) >= 0))
        {
            if (terms != NULL)
            {
                terms->push_back(signed_next);
            }
            return heat_span_hull(total, heat_span_sum(total, signed_next));
        }
        total = heat_span_sum(total, signed_next);
        if (terms != NULL)
        {
            terms->push_back(signed_next);
        }
        magnitude = next;
    }
    return total;
}

// int_0^1 u^(2h) S(u)^2 du for S(u) the sum of terms[k] u^k over the first `count` terms: the square's coefficients
// summed at 2^(2W), each over 1 + 2h + j = (q + 2p + j q) / q
static ExponentialSpan heat_square_integral(const std::vector<ExponentialSpan> &terms, size_t count,
                                            const SimRational &h, const ExponentialWide &unit)
{
    const ExponentialWide &p = h.numerator;
    const ExponentialWide &q = h.denominator;
    ExponentialSpan total = heat_zero();
    for (size_t power = 0u; (power + 1u) < (2u * count); power += 1u)
    {
        ExponentialWide least = exponential_unsigned(0ull);
        ExponentialWide most = exponential_unsigned(0ull);
        const size_t first = (power < count) ? 0u : (power - count + 1u);
        for (size_t at = first; (at <= power) && (at < count); at += 1u)
        {
            ExponentialWide low;
            ExponentialWide high;
            heat_product_ends(terms[at], terms[power - at], &low, &high);
            least = exponential_sum(least, low);
            most = exponential_sum(most, high);
        }
        const ExponentialWide divisor = exponential_sum(exponential_sum(q, exponential_sum(p, p)),
                                                        exponential_product(exponential_unsigned(power), q));
        ExponentialSpan coefficient;
        coefficient.low = least;
        coefficient.high = most;
        total = heat_span_sum(total, heat_span_scaled(coefficient, q, divisor));
    }
    ExponentialSpan span;
    span.low = exponential_floor(total.low, unit);
    span.high = exponential_ceiling(total.high, unit);
    return span;
}

// int_0^1 u^(2h) H(u Z)^2 du for Z = top / bottom <= 1 / z0. H(u Z) lies between the partial sums through the
// series' last term and before it, each positive while the terms past the first sum below it, and the integral lies
// between the integrals of their squares. A partial sum that cannot be shown positive leaves the low end at 0
static ExponentialSpan heat_far_integral(const ExponentialWide &top, const ExponentialWide &bottom,
                                         const SimRational &h, unsigned int scale)
{
    const ExponentialWide unit = exponential_power_two(scale);
    std::vector<ExponentialSpan> terms;
    heat_series(top, bottom, h, 0u, scale, &terms);
    ExponentialWide rest = exponential_unsigned(0ull);
    for (size_t at = 1u; at < terms.size(); at += 1u)
    {
        rest = exponential_sum(rest, (terms[at].high.sign >= 0) ? terms[at].high
                                                                : exponential_difference(exponential_unsigned(0ull),
                                                                                         terms[at].low));
    }
    ExponentialSpan span = heat_span_hull(heat_square_integral(terms, terms.size() - 1u, h, unit),
                                          heat_square_integral(terms, terms.size(), h, unit));
    if (exponential_compare(rest, terms[0].low) >= 0)
    {
        span.low = exponential_unsigned(0ull);
    }
    return span;
}

// U(1 + h, 2, z) and its derivative at the end of the carry, times z0^h, and int of their square over the steps
typedef struct
{
    ExponentialSpan value;
    ExponentialSpan slope;
    ExponentialSpan integral;
} HeatCarried;

// U(1 + h, 2, z) z0^h carried from z0 down to `end` by Taylor steps, each at most z / 4 and at most 4 long: the two
// starts below carry the solution that grows as e^z, and over a step of length |s| their terms rise near e^|s| before
// they cancel, which the rounding pays for in bits. With s the step and d_n = c_n s^n,
// z w'' + (2 - z) w' - (1 + h) w = 0 gives
//     d_(n + 2) = ((n + 1 + h) s^2 d_n - (n + 1) (n + 2 - z) s d_(n + 1)) / (z (n + 1) (n + 2)),
// run from the two starts (1, 0) and (0, 1) and joined with the value and s times the slope. On the disk of radius z / 2
// about z, |w| <= M = 3 2^e / z, 2^e >= z0^h, as Gamma(1 + h) > 0.88 and Re >= z / 2 there. With 2 |s| / z <= 2^-k,
// k >= 1, the terms past N sum to at most 2 M 2^(-k (N + 1)) for the value, 4 M (N + 1) 2^(-k (N + 1)) for s times the
// slope, and 2 |s| M^2 2^(-k (N + 1)) for the integral
static HeatCarried heat_carry(const SimRational &h, unsigned long long far, const SimRational &end, unsigned int scale,
                              int integrate)
{
    const ExponentialWide unit = exponential_power_two(scale);
    const SimRational far_rational = heat_whole(far);
    const ExponentialWide far_wide = exponential_unsigned(far);
    // the start: H's series at 1 / z0 over z0, and -(its series with extra 1) over z0^2
    HeatCarried carried;
    carried.value = heat_span_scaled(heat_series(exponential_unsigned(1ull), far_wide, h, 0u, scale, NULL),
                                     exponential_unsigned(1ull), far_wide);
    carried.slope = heat_span_scaled(heat_series(exponential_unsigned(1ull), far_wide, h, 1u, scale, NULL),
                                     exponential_difference(exponential_unsigned(0ull), exponential_unsigned(1ull)),
                                     exponential_product(far_wide, far_wide));
    carried.integral = heat_zero();
    // 2^e >= z0^h: e = ceil(p L / q), z0 below 2^L
    const ExponentialWide length = exponential_unsigned(sim_exact_bits(&far_wide));
    const ExponentialWide lift = exponential_ceiling(exponential_product(h.numerator, length), h.denominator);
    const unsigned int lift_bits = (lift.sign > 0) ? lift.limb[0] : 0u;
    SimRational at = far_rational;
    const SimRational quarter = sim_rational(1ll, 4ll);
    const SimRational longest = heat_whole(HEAT_STEP_LONGEST);
    while ((sim_rational_sign(sim_rational_difference(at, end)) > 0) && (exponential_short() == 0) &&
           (s_sim_rational_wide == 0))
    {
        const SimRational fourth = sim_rational_product(at, quarter);
        const SimRational length_of =
            (sim_rational_sign(sim_rational_difference(fourth, longest)) < 0) ? fourth : longest;
        const SimRational less = sim_rational_difference(at, length_of);
        const SimRational next = (sim_rational_sign(sim_rational_difference(less, end)) > 0) ? less : end;
        const SimRational step = sim_rational_difference(next, at);
        const SimRational span_of = sim_rational_absolute(step);
        // k: the most with 2^k 2 |s| <= z, at least 1 as |s| <= z / 4
        unsigned int fall = 1u;
        while (sim_rational_sign(sim_rational_difference(
                   at, sim_rational_product(span_of, heat_whole(2ull << (fall + 1u))))) >= 0)
        {
            fall += 1u;
        }
        // M = 3 2^e / z, and k (N + 1) past W by twice M's bits, z0's bits and the margin
        const ExponentialWide bound_top = exponential_product(exponential_unsigned(3ull),
                                                              exponential_product(exponential_power_two(lift_bits),
                                                                                  at.denominator));
        const ExponentialWide bound_whole = exponential_ceiling(bound_top, at.numerator);
        const unsigned int bound_bits = (unsigned int)sim_exact_bits(&bound_whole) + 1u;
        const unsigned int wanted = scale + (2u * bound_bits) + (unsigned int)sim_exact_bits(&far_wide) +
                                    HEAT_STEP_MARGIN;
        const unsigned int count = (wanted / fall) + 2u;
        const SimRational square_over = sim_rational_product(sim_rational_product(step, step),
                                                             sim_rational_reciprocal(at));
        const SimRational step_over = sim_rational_product(step, sim_rational_reciprocal(at));
        std::vector<ExponentialSpan> first(count + 1u);
        std::vector<ExponentialSpan> second(count + 1u);
        first[0] = heat_point(unit);
        first[1] = heat_zero();
        second[0] = heat_zero();
        second[1] = heat_point(unit);
        for (unsigned int index = 0u; (index + 2u) <= count; index += 1u)
        {
            const SimRational rise = sim_rational_sum(h, heat_whole(index + 1u));
            const SimRational spread =
                sim_rational_reciprocal(heat_whole((unsigned long long)(index + 1u) * (unsigned long long)(index + 2u)));
            const SimRational alpha = sim_rational_product(sim_rational_product(rise, square_over), spread);
            const SimRational beta = sim_rational_product(
                sim_rational_product(sim_rational_negative(step_over),
                                     sim_rational_difference(heat_whole(index + 2u), at)),
                sim_rational_reciprocal(heat_whole(index + 2u)));
            first[index + 2u] =
                heat_span_sum(heat_span_rational(first[index], alpha), heat_span_rational(first[index + 1u], beta));
            second[index + 2u] =
                heat_span_sum(heat_span_rational(second[index], alpha), heat_span_rational(second[index + 1u], beta));
        }
        const ExponentialSpan lead = heat_span_rational(carried.slope, step);
        ExponentialSpan first_sum = heat_zero();
        ExponentialSpan second_sum = heat_zero();
        ExponentialSpan first_slope = heat_zero();
        ExponentialSpan second_slope = heat_zero();
        for (unsigned int index = 0u; index <= count; index += 1u)
        {
            first_sum = heat_span_sum(first_sum, first[index]);
            second_sum = heat_span_sum(second_sum, second[index]);
            const ExponentialWide weight = exponential_unsigned(index);
            first_slope = heat_span_sum(first_slope, heat_span_scaled(first[index], weight, exponential_unsigned(1ull)));
            second_slope =
                heat_span_sum(second_slope, heat_span_scaled(second[index], weight, exponential_unsigned(1ull)));
        }
        // the tails: 2 M 2^(-k (N + 1)), 4 M (N + 1) 2^(-k (N + 1)) and 2 |s| M^2 2^(-k (N + 1)), each at 2^W
        const ExponentialWide tail_bottom =
            exponential_product(at.numerator, exponential_power_two(fall * (count + 1u)));
        const ExponentialWide value_tail = exponential_ceiling(
            exponential_product(exponential_product(bound_top, unit), exponential_unsigned(2ull)), tail_bottom);
        const ExponentialWide slope_tail = exponential_ceiling(
            exponential_product(exponential_product(bound_top, unit), exponential_unsigned(4ull * (count + 1ull))),
            tail_bottom);
        const ExponentialSpan value = heat_span_widened(
            heat_span_sum(heat_span_product(carried.value, first_sum, unit), heat_span_product(lead, second_sum, unit)),
            value_tail);
        const ExponentialSpan slope_step = heat_span_widened(heat_span_sum(heat_span_product(carried.value, first_slope,
                                                                                             unit),
                                                                           heat_span_product(lead, second_slope, unit)),
                                                             slope_tail);
        if (integrate)
        {
            std::vector<ExponentialSpan> joined(count + 1u);
            for (unsigned int index = 0u; index <= count; index += 1u)
            {
                joined[index] = heat_span_sum(heat_span_product(carried.value, first[index], unit),
                                              heat_span_product(lead, second[index], unit));
            }
            // int over [z + s, z] of w^2 = |s| sum over n of E_n / (n + 1), E the square of the d_n
            ExponentialSpan total = heat_zero();
            for (unsigned int power = 0u; power <= count; power += 1u)
            {
                ExponentialWide least = exponential_unsigned(0ull);
                ExponentialWide most = exponential_unsigned(0ull);
                for (unsigned int index = 0u; index <= power; index += 1u)
                {
                    ExponentialWide low;
                    ExponentialWide high;
                    heat_product_ends(joined[index], joined[power - index], &low, &high);
                    least = exponential_sum(least, low);
                    most = exponential_sum(most, high);
                }
                ExponentialSpan coefficient;
                coefficient.low = least;
                coefficient.high = most;
                total = heat_span_sum(total, heat_span_scaled(coefficient, exponential_unsigned(1ull),
                                                              exponential_unsigned(power + 1u)));
            }
            ExponentialSpan piece;
            piece.low = exponential_floor(total.low, unit);
            piece.high = exponential_ceiling(total.high, unit);
            const ExponentialWide integral_tail = exponential_ceiling(
                exponential_product(exponential_product(exponential_product(bound_top, bound_top), unit),
                                    exponential_product(span_of.numerator, exponential_unsigned(2ull))),
                exponential_product(exponential_product(tail_bottom, at.numerator), span_of.denominator));
            carried.integral = heat_span_sum(carried.integral,
                                             heat_span_widened(heat_span_rational(piece, span_of), integral_tail));
        }
        carried.value = value;
        carried.slope = heat_span_rational(slope_step, sim_rational_reciprocal(step));
        at = next;
    }
    return carried;
}

// H(Z) at 2^W, Z = top / bottom >= 0
static ExponentialSpan heat_exterior(const SimRational &z, const SimRational &h, unsigned int scale)
{
    const ExponentialWide unit = exponential_power_two(scale);
    if ((z.numerator.sign == 0) || (h.numerator.sign == 0))
    {
        return heat_point(unit);
    }
    const unsigned long long far = heat_far(scale);
    const ExponentialWide far_wide = exponential_unsigned(far);
    if (exponential_compare(z.denominator, exponential_product(far_wide, z.numerator)) >= 0)
    {
        return heat_series(z.numerator, z.denominator, h, 0u, scale, NULL);
    }
    // H(Z) = (Z z0)^(-h) Z^(-1) w(1 / Z), w carried as U z0^h
    const SimRational end = sim_rational_reciprocal(z);
    const HeatCarried carried = heat_carry(h, far, end, scale, 0);
    const ExponentialSpan lifted =
        heat_power_of(sim_rational_product(z, heat_whole(far)), sim_rational_negative(h), scale);
    return heat_span_rational(heat_span_product(lifted, carried.value, unit), end);
}

// Pi_ext(X, eta) at 2^W
static ExponentialSpan heat_pressure(const HeatArguments *arguments, unsigned int scale)
{
    const ExponentialWide unit = exponential_power_two(scale);
    const SimRational &x = arguments->x;
    const SimRational &h = arguments->h;
    const SimRational spread = sim_rational_difference(heat_whole(1ull), sim_rational_product(arguments->eta,
                                                                                              arguments->eta));
    const SimRational twice = sim_rational_product(heat_whole(2ull), spread);
    // -(c^2 / 2)
    const SimRational weight = sim_rational_negative(
        sim_rational_product(sim_rational_product(arguments->c, arguments->c), sim_rational(1ll, 2ll)));
    const unsigned long long far = heat_far(scale);
    const SimRational two_h = sim_rational_product(heat_whole(2ull), h);
    const SimRational far_rational = heat_whole(far);
    if (sim_rational_sign(sim_rational_difference(x, sim_rational_product(twice, far_rational))) >= 0)
    {
        // X^(-1 - 2h) int_0^1 u^(2h) H(2 d u / X)^2 du
        const SimRational near = sim_rational_product(twice, sim_rational_reciprocal(x));
        const ExponentialSpan integral = heat_far_integral(near.numerator, near.denominator, h, scale);
        const ExponentialSpan lifted = heat_power_of(x, sim_rational_negative(two_h), scale);
        return heat_span_rational(heat_span_product(lifted, integral, unit),
                                  sim_rational_product(weight, sim_rational_reciprocal(x)));
    }
    // (2 d)^(-1) (2 d z0)^(-2h) (int_(X / (2 d))^z0 (U z0^h)^2 dz + z0^(-1) int_0^1 u^(2h) H(u / z0)^2 du)
    const SimRational start = sim_rational_product(x, sim_rational_reciprocal(twice));
    const HeatCarried carried = heat_carry(h, far, start, scale, 1);
    const ExponentialSpan beyond = heat_span_scaled(
        heat_far_integral(exponential_unsigned(1ull), exponential_unsigned(far), h, scale), exponential_unsigned(1ull),
        exponential_unsigned(far));
    const ExponentialSpan inner = heat_span_sum(carried.integral, beyond);
    const ExponentialSpan lifted =
        heat_power_of(sim_rational_product(twice, far_rational), sim_rational_negative(two_h), scale);
    return heat_span_rational(heat_span_product(lifted, inner, unit),
                              sim_rational_product(weight, sim_rational_reciprocal(twice)));
}

static ExponentialSpan heat_span_of(unsigned int read, const HeatArguments *arguments, unsigned int scale)
{
    if (read == HEAT_READ_POWER)
    {
        return heat_power_of(arguments->x, arguments->h, scale);
    }
    if (read == HEAT_READ_GAMMA)
    {
        return heat_gamma(arguments->h, scale);
    }
    if (read == HEAT_READ_EXTERIOR)
    {
        return heat_exterior(arguments->x, arguments->h, scale);
    }
    return heat_pressure(arguments, scale);
}

// 1 where 0 <= h < 1
static int heat_share(const SimRational &h)
{
    return (h.numerator.sign >= 0) && (exponential_compare(h.numerator, h.denominator) < 0);
}

// A reading at 2^bits: the span at 2^(bits + guard), its ends floored to 2^bits, the guard grown until they agree
static int heat_read(unsigned int read, HeatArguments *arguments, unsigned int bits, ExponentialIntegralBracket *bracket)
{
    sim_rational_settle(&arguments->x);
    sim_rational_settle(&arguments->h);
    sim_rational_settle(&arguments->eta);
    sim_rational_settle(&arguments->c);
    for (unsigned int guard = HEAT_GUARD_FIRST;; guard += HEAT_GUARD_STEP)
    {
        exponential_short_clear();
        s_sim_rational_wide = 0;
        const unsigned int scale = bits + guard;
        const ExponentialSpan span = heat_span_of(read, arguments, scale);
        const ExponentialWide step = exponential_power_two(guard);
        const ExponentialWide low = exponential_floor(span.low, step);
        const ExponentialWide high = exponential_floor(span.high, step);
        if ((exponential_short() != 0) || (s_sim_rational_wide != 0))
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

static HeatArguments heat_arguments(const SimRational *x, const SimRational *h)
{
    HeatArguments arguments;
    arguments.x = (x != NULL) ? *x : heat_whole(1ull);
    arguments.h = (h != NULL) ? *h : heat_whole(0ull);
    arguments.eta = heat_whole(0ull);
    arguments.c = heat_whole(0ull);
    return arguments;
}

int power_floor(const SimRational *x, const SimRational *h, unsigned int bits, ExponentialIntegralBracket *bracket)
{
    if ((x->denominator.sign <= 0) || (x->numerator.sign <= 0) || (h->denominator.sign <= 0))
    {
        return EXPONENTIAL_INTEGRAL_DOMAIN;
    }
    HeatArguments arguments = heat_arguments(x, h);
    return heat_read(HEAT_READ_POWER, &arguments, bits, bracket);
}

int gamma_floor(const SimRational *h, unsigned int bits, ExponentialIntegralBracket *bracket)
{
    if ((h->denominator.sign <= 0) || !heat_share(*h))
    {
        return EXPONENTIAL_INTEGRAL_DOMAIN;
    }
    HeatArguments arguments = heat_arguments(NULL, h);
    return heat_read(HEAT_READ_GAMMA, &arguments, bits, bracket);
}

int heat_exterior_floor(const SimRational *z, const SimRational *h, unsigned int bits,
                        ExponentialIntegralBracket *bracket)
{
    if ((z->denominator.sign <= 0) || (z->numerator.sign < 0) || (h->denominator.sign <= 0) || !heat_share(*h))
    {
        return EXPONENTIAL_INTEGRAL_DOMAIN;
    }
    HeatArguments arguments = heat_arguments(z, h);
    return heat_read(HEAT_READ_EXTERIOR, &arguments, bits, bracket);
}

int exterior_pressure_floor(const SimRational *x, const SimRational *eta, const SimRational *c, const SimRational *h,
                            unsigned int bits, ExponentialIntegralBracket *bracket)
{
    if ((x->denominator.sign <= 0) || (x->numerator.sign <= 0) || (eta->denominator.sign <= 0) ||
        (c->denominator.sign <= 0) || (h->denominator.sign <= 0) || !heat_share(*h) ||
        (sim_rational_sign(sim_rational_difference(sim_rational_product(*eta, *eta), heat_whole(1ull))) > 0))
    {
        return EXPONENTIAL_INTEGRAL_DOMAIN;
    }
    HeatArguments arguments = heat_arguments(x, h);
    arguments.eta = *eta;
    arguments.c = *c;
    return heat_read(HEAT_READ_PRESSURE, &arguments, bits, bracket);
}
