// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// exponential_integral_main.cu: the request, the readings and the checks
#include "exponential_integral.h"

// E1(x), e^(-x) and ln x read at the request's x, and gamma, each as floor(f 2^bits), with these checks:
// 1. ln 2, e^(-1), gamma and E1(1) each agree with its published digits (OEIS A002162, A068985, A001620, A099285),
//    read at the bits those digits hold.
// 2. e^(-x) / (x + 1) < E1(x) < e^(-x) / x, the bounds the exponential integral keeps for every x > 0.
// 3. E1(x) by the series -gamma - ln x + S(x) floors as the continued fraction does.
// 4. Every reading at bits + 64 floors to the reading at bits.
// The request: exponential_integral [x [bits]], x a whole number, a fraction p/q or a decimal, read exactly. With none
// it reads x = 7 at 128 bits.
//     src/sims/run.sh exponential_integral -- 7.0078 192

// the x and the bits a request that names none reads
#define EXPONENTIAL_REQUEST_TOP 7ull
#define EXPONENTIAL_REQUEST_BITS 128u
// the bits a second reading is taken at past the first
#define EXPONENTIAL_SECOND_BITS 64u

// a published value: its decimal digits after the point, truncated, and where they are published
typedef struct
{
    const char *name;
    const char *digits;
    const char *source;
} ExponentialPublished;

static const ExponentialPublished s_exponential_published[] = {
    {"ln 2", "69314718055994530941723212145817656807550013436025", "OEIS A002162"},
    {"e^(-1)", "36787944117144232159552377016146086744581113103176", "OEIS A068985"},
    {"gamma", "57721566490153286060651209008240243104215933593992", "OEIS A001620"},
    {"E1(1)", "219383934395520273677163775460", "OEIS A099285"},
};

#define EXPONENTIAL_PUBLISHED_COUNT (sizeof(s_exponential_published) / sizeof(s_exponential_published[0]))

// the whole number written in the first `length` characters of `digits`, into `value`: 1, or 0 where a character is
// no digit
static int exponential_digits(const char *digits, size_t length, AnchorExactInteger *value)
{
    sim_exact_unsigned(value, 0ull);
    for (size_t at = 0u; at < length; at += 1u)
    {
        if ((digits[at] < '0') || (digits[at] > '9'))
        {
            return 0;
        }
        AnchorExactInteger scaled;
        AnchorExactInteger digit;
        sim_exact_unsigned(&digit, (unsigned long long)(digits[at] - '0'));
        if ((sim_exact_scaled(value, 10ull, &scaled) == 0) || (sim_exact_sum(&scaled, &digit, value) == 0))
        {
            return 0;
        }
    }
    return 1;
}

// 10^places exactly
static AnchorExactInteger exponential_ten_power(unsigned int places)
{
    AnchorExactInteger power;
    sim_exact_power(10ull, places, &power);
    return power;
}

static AnchorExactInteger exponential_two_power(unsigned int bits)
{
    AnchorExactInteger power;
    sim_exact_power(2ull, bits, &power);
    return power;
}

// `text`, a whole number, p/q or a decimal, read exactly into `x`: 1, or 0 where it does not read
static int exponential_request(const char *text, SimRational *x)
{
    const char *const slash = strchr(text, '/');
    const char *const point = strchr(text, '.');
    if (slash != NULL)
    {
        return exponential_digits(text, (size_t)(slash - text), &x->numerator) &&
               exponential_digits(slash + 1, strlen(slash + 1), &x->denominator) && (x->denominator.sign > 0);
    }
    if (point != NULL)
    {
        AnchorExactInteger whole;
        AnchorExactInteger part;
        AnchorExactInteger scaled;
        const unsigned int places = (unsigned int)strlen(point + 1);
        x->denominator = exponential_ten_power(places);
        return exponential_digits(text, (size_t)(point - text), &whole) &&
               exponential_digits(point + 1, places, &part) &&
               sim_exact_product(&whole, &x->denominator, &scaled) && sim_exact_sum(&scaled, &part, &x->numerator);
    }
    sim_exact_unsigned(&x->denominator, 1ull);
    return exponential_digits(text, strlen(text), &x->numerator);
}

// floor(f 2^bits) printed as the decimal places 2^bits holds, truncated, beside its hex
static void exponential_print(ScripturaLine *line, const char *name, const ExponentialIntegralBracket *bracket)
{
    const unsigned int places = (bracket->bits * 3u) / 10u;
    AnchorExactInteger lifted;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    const AnchorExactInteger ten = exponential_ten_power(places);
    const AnchorExactInteger unit = exponential_two_power(bracket->bits);
    sim_exact_product(&bracket->floor_value, &ten, &lifted);
    anchor_exact_divide(&lifted, &unit, &quotient, &remainder);
    AnchorExactInteger whole;
    AnchorExactInteger fraction;
    anchor_exact_divide(&quotient, &ten, &whole, &fraction);
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " = ");
    if (quotient.sign < 0)
    {
        scriptura_character(line, '-');
    }
    whole.sign = (whole.sign < 0) ? 1 : whole.sign;
    fraction.sign = (fraction.sign < 0) ? 1 : fraction.sign;
    sim_exact_decimal(line, &whole);
    scriptura_character(line, '.');
    // the places are written with their leading zeros
    char digits[4096];
    ScripturaLine held;
    held.out = digits;
    held.capacity = sizeof(digits);
    held.at = 0ull;
    sim_exact_decimal(&held, &fraction);
    const unsigned long long shown = (fraction.sign != 0) ? held.at : 0ull;
    for (unsigned long long pad = shown; pad < places; pad += 1ull)
    {
        scriptura_character(line, '0');
    }
    for (unsigned long long at = 0ull; at < shown; at += 1ull)
    {
        scriptura_character(line, digits[at]);
    }
    scriptura_text(line, " (floor at 2^");
    scriptura_decimal(line, bracket->bits, 1u);
    scriptura_text(line, ")\n");
}

// a reading's verdict reported: 1 where it is held; the width named where the build's cannot hold it
static int exponential_held(SimResults *results, int status, const char *name, unsigned int bits)
{
    if (status == EXPONENTIAL_INTEGRAL_HELD)
    {
        return 1;
    }
    scriptura_text(&results->line, "  ");
    scriptura_text(&results->line, name);
    if (status == EXPONENTIAL_INTEGRAL_WIDTH)
    {
        scriptura_text(&results->line, " at 2^");
        scriptura_decimal(&results->line, bits, 1u);
        scriptura_text(&results->line, " is refused: the build's exact width, ");
        scriptura_decimal(&results->line, exponential_integral_width(), 1u);
        scriptura_text(&results->line, " bits (SIM_EXACT_LIMBS), does not hold its bracket\n");
    }
    else
    {
        scriptura_text(&results->line, " is refused: x is outside its domain\n");
    }
    return 0;
}

// 1 where floor(f 2^bits) and the published digits D, d of them, name overlapping intervals:
// F 10^d < (D + 1) 2^bits and D 2^bits < (F + 1) 10^d
static int exponential_published_agrees(const ExponentialIntegralBracket *bracket, const char *digits)
{
    const unsigned int places = (unsigned int)strlen(digits);
    AnchorExactInteger published;
    AnchorExactInteger one;
    AnchorExactInteger published_next;
    AnchorExactInteger floor_next;
    sim_exact_unsigned(&one, 1ull);
    if ((exponential_digits(digits, places, &published) == 0) ||
        (sim_exact_sum(&published, &one, &published_next) == 0) ||
        (sim_exact_sum(&bracket->floor_value, &one, &floor_next) == 0))
    {
        return 0;
    }
    const AnchorExactInteger ten = exponential_ten_power(places);
    const AnchorExactInteger unit = exponential_two_power(bracket->bits);
    AnchorExactInteger first;
    AnchorExactInteger second;
    AnchorExactInteger third;
    AnchorExactInteger fourth;
    return sim_exact_product(&bracket->floor_value, &ten, &first) &&
           sim_exact_product(&published_next, &unit, &second) && sim_exact_product(&published, &unit, &third) &&
           sim_exact_product(&floor_next, &ten, &fourth) && (anchor_exact_compare(&first, &second) < 0) &&
           (anchor_exact_compare(&third, &fourth) < 0);
}

// 1. the published values, each read at the bits its digits hold and 8 past them
static void exponential_published(SimResults *results)
{
    SimRational one;
    SimRational two;
    sim_exact_unsigned(&one.numerator, 1ull);
    sim_exact_unsigned(&one.denominator, 1ull);
    sim_exact_unsigned(&two.numerator, 2ull);
    sim_exact_unsigned(&two.denominator, 1ull);
    for (unsigned int at = 0u; at < EXPONENTIAL_PUBLISHED_COUNT; at += 1u)
    {
        const ExponentialPublished *const value = &s_exponential_published[at];
        const unsigned int bits = (((unsigned int)strlen(value->digits) * 10u) / 3u) + 8u;
        ExponentialIntegralBracket bracket;
        const int status = (at == 0u)   ? logarithm_floor(&two, bits, &bracket)
                           : (at == 1u) ? exponential_negative_floor(&one, bits, &bracket)
                           : (at == 2u) ? euler_gamma_floor(bits, &bracket)
                                        : exponential_integral_floor(&one, bits, &bracket);
        const int held = exponential_held(results, status, value->name, bits);
        const int agrees = held && exponential_published_agrees(&bracket, value->digits);
        if (held)
        {
            exponential_print(&results->line, value->name, &bracket);
        }
        scriptura_text(&results->line, agrees ? "    agrees with its " : "    does not agree with its ");
        scriptura_decimal(&results->line, strlen(value->digits), 1u);
        scriptura_text(&results->line, " published digits, ");
        scriptura_text(&results->line, value->source);
        scriptura_character(&results->line, '\n');
        sim_check(results, agrees, value->name);
    }
}

// 2, 3 and 4 at the request's x
static void exponential_at(SimResults *results, const SimRational *x, unsigned int bits)
{
    ExponentialIntegralBracket integral;
    ExponentialIntegralBracket series;
    ExponentialIntegralBracket decay;
    ExponentialIntegralBracket logarithm;
    ExponentialIntegralBracket gamma;
    const int integral_held = exponential_held(results, exponential_integral_floor(x, bits, &integral), "E1(x)", bits);
    const int decay_held = exponential_held(results, exponential_negative_floor(x, bits, &decay), "e^(-x)", bits);
    const int logarithm_held = exponential_held(results, logarithm_floor(x, bits, &logarithm), "ln x", bits);
    const int gamma_held = exponential_held(results, euler_gamma_floor(bits, &gamma), "gamma", bits);
    const int series_held =
        exponential_held(results, exponential_integral_series_floor(x, bits, &series), "E1(x) by its series", bits);
    if (integral_held)
    {
        exponential_print(&results->line, "E1(x)", &integral);
    }
    if (decay_held)
    {
        exponential_print(&results->line, "e^(-x)", &decay);
    }
    if (logarithm_held)
    {
        exponential_print(&results->line, "ln x", &logarithm);
    }
    if (gamma_held)
    {
        exponential_print(&results->line, "gamma", &gamma);
    }
    // 2. E1 low (p + q) > e^(-x) high q, and E1 high p < e^(-x) low q, every end at 2^bits
    int bounded = integral_held && decay_held;
    if (bounded)
    {
        AnchorExactInteger sum;
        AnchorExactInteger left;
        AnchorExactInteger right;
        bounded = sim_exact_sum(&x->numerator, &x->denominator, &sum) &&
                  sim_exact_product(&integral.low, &sum, &left) &&
                  sim_exact_product(&decay.high, &x->denominator, &right) && (anchor_exact_compare(&left, &right) > 0) &&
                  sim_exact_product(&integral.high, &x->numerator, &left) &&
                  sim_exact_product(&decay.low, &x->denominator, &right) && (anchor_exact_compare(&left, &right) < 0);
    }
    scriptura_text(&results->line, bounded ? "  e^(-x) / (x + 1) < E1(x) < e^(-x) / x holds\n"
                                           : "  e^(-x) / (x + 1) < E1(x) < e^(-x) / x does not hold\n");
    sim_check(results, bounded, "e^(-x) / (x + 1) < E1(x) < e^(-x) / x");
    // 3. the series floors as the continued fraction does
    const int routes = integral_held && series_held && anchor_exact_equal(&integral.floor_value, &series.floor_value);
    scriptura_text(&results->line, routes ? "  E1(x) by its series floors as by its continued fraction\n"
                                          : "  E1(x) by its series does not floor as by its continued fraction\n");
    sim_check(results, routes, "E1(x) by its series and by its continued fraction");
    // 4. each reading at bits + 64 floors to the reading at bits
    const ExponentialIntegralBracket *const first[4] = {&integral, &decay, &logarithm, &gamma};
    const int held[4] = {integral_held, decay_held, logarithm_held, gamma_held};
    const char *const names[4] = {"E1(x)", "e^(-x)", "ln x", "gamma"};
    const AnchorExactInteger step = exponential_two_power(EXPONENTIAL_SECOND_BITS);
    for (unsigned int at = 0u; at < 4u; at += 1u)
    {
        ExponentialIntegralBracket second;
        const unsigned int deeper = bits + EXPONENTIAL_SECOND_BITS;
        const int status = (at == 0u)   ? exponential_integral_floor(x, deeper, &second)
                           : (at == 1u) ? exponential_negative_floor(x, deeper, &second)
                           : (at == 2u) ? logarithm_floor(x, deeper, &second)
                                        : euler_gamma_floor(deeper, &second);
        int same = held[at] && exponential_held(results, status, names[at], deeper);
        if (same)
        {
            // a floor of a floor is the floor: the deeper reading over 2^64, floored, is the first
            AnchorExactInteger quotient;
            AnchorExactInteger remainder;
            anchor_exact_divide(&second.floor_value, &step, &quotient, &remainder);
            if ((second.floor_value.sign < 0) && (remainder.sign != 0))
            {
                AnchorExactInteger one;
                AnchorExactInteger lowered;
                sim_exact_unsigned(&one, 1ull);
                anchor_exact_subtract(&quotient, &one, &lowered);
                quotient = lowered;
            }
            same = anchor_exact_equal(&quotient, &first[at]->floor_value);
        }
        scriptura_text(&results->line, "  ");
        scriptura_text(&results->line, names[at]);
        scriptura_text(&results->line, same ? " at 2^" : " does not, at 2^");
        scriptura_decimal(&results->line, deeper, 1u);
        scriptura_text(&results->line, same ? ", floors to its reading at 2^" : ", floor to its reading at 2^");
        scriptura_decimal(&results->line, bits, 1u);
        scriptura_character(&results->line, '\n');
        sim_check(results, same, names[at]);
    }
}

int main(int count, char **arguments)
{
    char capacity[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, capacity);
    SimRational x;
    sim_exact_unsigned(&x.numerator, EXPONENTIAL_REQUEST_TOP);
    sim_exact_unsigned(&x.denominator, 1ull);
    unsigned int bits = EXPONENTIAL_REQUEST_BITS;
    const int read = (count < 2) || exponential_request(arguments[1], &x);
    char *end = NULL;
    const unsigned long asked = (count >= 3) ? strtoul(arguments[2], &end, 10) : 0ul;
    const int sized = (count < 3) || ((end != NULL) && (*end == '\0') && (asked > 0ul) && (asked < (1ul << 20u)));
    if (!read || !sized || (count > 3))
    {
        fprintf(stderr, "exponential_integral [x [bits]]: x a whole number, p/q or a decimal, bits a whole number\n");
        return 2;
    }
    bits = (count >= 3) ? (unsigned int)asked : bits;
    scriptura_text(&results.line, "  exponential integral: x = ");
    sim_rational_print(&results.line, x);
    scriptura_text(&results.line, ", read at 2^");
    scriptura_decimal(&results.line, bits, 1u);
    scriptura_character(&results.line, '\n');
    exponential_published(&results);
    sim_flush(&results);
    exponential_at(&results, &x, bits);
    return sim_close(&results, "exponential integral");
}
