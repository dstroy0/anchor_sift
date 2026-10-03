// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// exponential_integral_main.cu: the request, the readings and the checks
#include "exponential_integral_internal.h"

// E1(x), e^(-x) and ln x read at the request's x, and gamma, each as floor(f 2^bits), with these checks:
// 1. ln 2, e^(-1), gamma and E1(1) each agree with its published digits (OEIS A002162, A068985, A001620, A099285),
//    read at the bits those digits hold.
// 2. e^(-x) / (x + 1) < E1(x) < e^(-x) / x, the bounds the exponential integral keeps for every x > 0.
// 3. E1(x) by the series -gamma - ln x + S(x) floors as the continued fraction does.
// 4. Every reading at bits + 64 floors to the reading at bits.
// 5. On the engine, each series term a lane of the record machine: e^(-x), ln x and E1(x) by its series each floor as
//    on the host, every lane's record on the device is the host interpreter's word for word, and every sum the device
//    takes is the host's. The continued fraction is a chain of levels each waiting on the next and stays on the host.
// 6. The heat exterior at h = 1/200 and c = 1/5, read at the request's bits:
//    a. 2^(-1/2) and Gamma(3/2) agree with their published digits (OEIS A010503, A019704).
//    b. H(0) is 1, and (1 + Z (1 + h))^(-h) < H(Z) < 1 at Z = 1/10, 1 and 2, Jensen's bound and (1 + Z v)^(-h) <= 1.
//    c. Pi_ext(3/2, 1) is -c^2 X^(-1 - 2h) / (2 (1 + 2h)), H being 1 at d = 0.
//    d. -c^2 X^(-1 - 2h) / (2 (1 + 2h)) < Pi_ext(X, eta) < 0 at (1, 0) and (2, 1/2), as 0 < H <= 1.
//    e. x^h at x = 7/1000, Gamma(1 + h), H(1/150), H(2), Pi_ext(1, 0) and Pi_ext(1, 9983/10000) each floor at bits + 64
//       to their reading at bits. z0 moves with the bits: at 128 bits H(1/150) and Pi_ext(1, 9983/10000) are read by
//       the series alone, and at 192 by the Taylor steps.
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

// 5. the engine's readings at the request's x, each held to the host's
static void exponential_engine(SimResults *results, int count, char **arguments, const SimRational *x,
                               unsigned int bits)
{
    if (!sim_job_submit(results, "exponential_integral", count, arguments, exponential_engine_bytes(x, bits)))
    {
        return;
    }
    scriptura_text(&results->line, "  on the engine, each series term a lane of the record machine\n");
    sim_flush(results);
    const unsigned int reads[3] = {EXPONENTIAL_READ_NEGATIVE, EXPONENTIAL_READ_LOGARITHM, EXPONENTIAL_READ_SERIES};
    const char *const names[3] = {"e^(-x)", "ln x", "E1(x) by its series"};
    exponential_engine_reset();
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        ExponentialIntegralBracket engine;
        ExponentialIntegralBracket host;
        const int engine_status = exponential_read_from(&g_exponential_engine, reads[at], x, bits, &engine);
        const int host_status = exponential_read_from(&g_exponential_host, reads[at], x, bits, &host);
        const int same = (engine_status == EXPONENTIAL_INTEGRAL_HELD) && (host_status == EXPONENTIAL_INTEGRAL_HELD) &&
                         anchor_exact_equal(&engine.floor_value, &host.floor_value);
        if (engine_status == EXPONENTIAL_INTEGRAL_HELD)
        {
            exponential_print(&results->line, names[at], &engine);
        }
        else if (engine_status == EXPONENTIAL_INTEGRAL_ENGINE)
        {
            scriptura_text(&results->line, "  ");
            scriptura_text(&results->line, names[at]);
            scriptura_text(&results->line, ": a program did not build or run, or a record or sum on the device is "
                                           "not the host's\n");
        }
        else
        {
            exponential_held(results, engine_status, names[at], bits);
        }
        scriptura_text(&results->line, same ? "    floors on the engine as on the host\n"
                                            : "    does not floor on the engine as on the host\n");
        sim_check(results, same, names[at]);
        sim_flush(results);
    }
    const ExponentialEngineCount counted = exponential_engine_counted();
    scriptura_text(&results->line, "  ");
    scriptura_decimal(&results->line, counted.programs, 1u);
    scriptura_text(&results->line, " programs of ");
    scriptura_decimal(&results->line, counted.steps, 1u);
    scriptura_text(&results->line, " steps in all, ");
    scriptura_decimal(&results->line, counted.lanes, 1u);
    scriptura_text(&results->line, " lanes, ");
    scriptura_decimal(&results->line, counted.same, 1u);
    scriptura_text(&results->line, " records on the device the host interpreter's word for word, ");
    scriptura_decimal(&results->line, counted.sums_same, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, counted.sums, 1u);
    scriptura_text(&results->line, " sums on the device the host's\n");
    sim_check(results, (counted.lanes != 0ull) && (counted.same == counted.lanes),
              "every lane's record on the device is the host interpreter's word for word");
    sim_check(results, (counted.sums != 0ull) && (counted.sums_same == counted.sums),
              "every sum the device takes is the host's");
    sim_flush(results);
}

// the heat exterior's arguments
#define EXPONENTIAL_HEAT_SHARE_TOP 1ll
#define EXPONENTIAL_HEAT_SHARE_BOTTOM 200ll
#define EXPONENTIAL_HEAT_SPEED_TOP 1ll
#define EXPONENTIAL_HEAT_SPEED_BOTTOM 5ll

// which heat reading a row of check e takes
enum
{
    EXPONENTIAL_HEAT_POWER = 0,
    EXPONENTIAL_HEAT_GAMMA = 1,
    EXPONENTIAL_HEAT_EXTERIOR = 2,
    EXPONENTIAL_HEAT_PRESSURE = 3
};

// a row of check e: the reading, its name, and its arguments as small fractions
typedef struct
{
    unsigned int read;
    const char *name;
    long long first_top;
    long long first_bottom;
    long long second_top;
    long long second_bottom;
} ExponentialHeatRow;

static const ExponentialHeatRow s_exponential_heat_rows[] = {
    {EXPONENTIAL_HEAT_POWER, "(7/1000)^h", 7ll, 1000ll, 0ll, 1ll},
    {EXPONENTIAL_HEAT_GAMMA, "Gamma(1 + h)", 0ll, 1ll, 0ll, 1ll},
    {EXPONENTIAL_HEAT_EXTERIOR, "H(1/150)", 1ll, 150ll, 0ll, 1ll},
    {EXPONENTIAL_HEAT_EXTERIOR, "H(2)", 2ll, 1ll, 0ll, 1ll},
    {EXPONENTIAL_HEAT_PRESSURE, "Pi_ext(1, 0)", 1ll, 1ll, 0ll, 1ll},
    {EXPONENTIAL_HEAT_PRESSURE, "Pi_ext(1, 9983/10000)", 1ll, 1ll, 9983ll, 10000ll},
};

#define EXPONENTIAL_HEAT_ROW_COUNT (sizeof(s_exponential_heat_rows) / sizeof(s_exponential_heat_rows[0]))

static int exponential_heat_reading(const ExponentialHeatRow *row, unsigned int bits,
                                    ExponentialIntegralBracket *bracket)
{
    const SimRational h = sim_rational(EXPONENTIAL_HEAT_SHARE_TOP, EXPONENTIAL_HEAT_SHARE_BOTTOM);
    const SimRational speed = sim_rational(EXPONENTIAL_HEAT_SPEED_TOP, EXPONENTIAL_HEAT_SPEED_BOTTOM);
    const SimRational first = sim_rational(row->first_top, row->first_bottom);
    const SimRational second = sim_rational(row->second_top, row->second_bottom);
    if (row->read == EXPONENTIAL_HEAT_POWER)
    {
        return power_floor(&first, &h, bits, bracket);
    }
    if (row->read == EXPONENTIAL_HEAT_GAMMA)
    {
        return gamma_floor(&h, bits, bracket);
    }
    if (row->read == EXPONENTIAL_HEAT_EXTERIOR)
    {
        return heat_exterior_floor(&first, &h, bits, bracket);
    }
    return exterior_pressure_floor(&first, &second, &speed, &h, bits, bracket);
}

// -c^2 X^(-1 - 2h) / (2 (1 + 2h)) at 2^bits, from X^(-2h)'s bracket: its ends, the low end floored and the high ceiled
static int exponential_heat_bound(const SimRational *x, unsigned int bits, AnchorExactInteger *low,
                                  AnchorExactInteger *high)
{
    const SimRational h = sim_rational(EXPONENTIAL_HEAT_SHARE_TOP, EXPONENTIAL_HEAT_SHARE_BOTTOM);
    const SimRational speed = sim_rational(EXPONENTIAL_HEAT_SPEED_TOP, EXPONENTIAL_HEAT_SPEED_BOTTOM);
    const SimRational two_h = sim_rational_product(sim_rational(2ll, 1ll), h);
    ExponentialIntegralBracket lifted;
    const SimRational negative_two_h = sim_rational_negative(two_h);
    if (power_floor(x, &negative_two_h, bits, &lifted) != EXPONENTIAL_INTEGRAL_HELD)
    {
        return 0;
    }
    // the factor -c^2 / (2 (1 + 2h) X), negative: the high end of X^(-2h) gives the low end of the bound
    const SimRational factor = sim_rational_negative(sim_rational_product(
        sim_rational_product(speed, speed),
        sim_rational_reciprocal(sim_rational_product(
            sim_rational_product(sim_rational(2ll, 1ll), sim_rational_sum(sim_rational(1ll, 1ll), two_h)), *x))));
    AnchorExactInteger top;
    AnchorExactInteger quotient;
    AnchorExactInteger remainder;
    AnchorExactInteger one;
    sim_exact_unsigned(&one, 1ull);
    if ((sim_exact_product(&lifted.high, &factor.numerator, &top) == 0) ||
        (anchor_exact_divide(&top, &factor.denominator, &quotient, &remainder) != ANCHOR_EXACT_OK))
    {
        return 0;
    }
    *low = quotient;
    if (remainder.sign != 0)
    {
        anchor_exact_subtract(&quotient, &one, low);
    }
    if ((sim_exact_product(&lifted.low, &factor.numerator, &top) == 0) ||
        (anchor_exact_divide(&top, &factor.denominator, high, &remainder) != ANCHOR_EXACT_OK))
    {
        return 0;
    }
    return 1;
}

// 6. the heat exterior
static void exponential_heat(SimResults *results, unsigned int bits)
{
    const SimRational h = sim_rational(EXPONENTIAL_HEAT_SHARE_TOP, EXPONENTIAL_HEAT_SHARE_BOTTOM);
    const SimRational speed = sim_rational(EXPONENTIAL_HEAT_SPEED_TOP, EXPONENTIAL_HEAT_SPEED_BOTTOM);
    scriptura_text(&results->line, "  the heat exterior, h = 1/200 and c = 1/5\n");
    // a. the published values
    {
        const SimRational two = sim_rational(2ll, 1ll);
        const SimRational negative_half = sim_rational(-1ll, 2ll);
        const SimRational half = sim_rational(1ll, 2ll);
        const char *const names[2] = {"2^(-1/2)", "Gamma(3/2)"};
        const char *const digits[2] = {"70710678118654752440084436210484903928483593768847",
                                       "88622692545275801364908374167057259139877472806119"};
        const char *const sources[2] = {"OEIS A010503", "OEIS A019704"};
        for (unsigned int at = 0u; at < 2u; at += 1u)
        {
            const unsigned int places_bits = (((unsigned int)strlen(digits[at]) * 10u) / 3u) + 8u;
            ExponentialIntegralBracket bracket;
            const int status = (at == 0u) ? power_floor(&two, &negative_half, places_bits, &bracket)
                                          : gamma_floor(&half, places_bits, &bracket);
            const int held = exponential_held(results, status, names[at], places_bits);
            const int agrees = held && exponential_published_agrees(&bracket, digits[at]);
            if (held)
            {
                exponential_print(&results->line, names[at], &bracket);
            }
            scriptura_text(&results->line, agrees ? "    agrees with its " : "    does not agree with its ");
            scriptura_decimal(&results->line, strlen(digits[at]), 1u);
            scriptura_text(&results->line, " published digits, ");
            scriptura_text(&results->line, sources[at]);
            scriptura_character(&results->line, '\n');
            sim_check(results, agrees, names[at]);
        }
    }
    const AnchorExactInteger unit = exponential_two_power(bits);
    // b. H(0) = 1, and Jensen's bound below 1
    {
        const SimRational zero = sim_rational(0ll, 1ll);
        ExponentialIntegralBracket bracket;
        const int one = exponential_held(results, heat_exterior_floor(&zero, &h, bits, &bracket), "H(0)", bits) &&
                        anchor_exact_equal(&bracket.floor_value, &unit);
        scriptura_text(&results->line, one ? "  H(0) is 1\n" : "  H(0) is not 1\n");
        sim_check(results, one, "H(0) is 1");
        const long long places[3][2] = {{1ll, 10ll}, {1ll, 1ll}, {2ll, 1ll}};
        const char *const names[3] = {"H(1/10)", "H(1)", "H(2)"};
        for (unsigned int at = 0u; at < 3u; at += 1u)
        {
            const SimRational z = sim_rational(places[at][0], places[at][1]);
            const SimRational base =
                sim_rational_sum(sim_rational(1ll, 1ll),
                                 sim_rational_product(z, sim_rational_sum(sim_rational(1ll, 1ll), h)));
            const SimRational negative_h = sim_rational_negative(h);
            ExponentialIntegralBracket lower;
            const int held = exponential_held(results, heat_exterior_floor(&z, &h, bits, &bracket), names[at], bits) &&
                             exponential_held(results, power_floor(&base, &negative_h, bits, &lower),
                                              "(1 + Z (1 + h))^(-h)", bits);
            const int between = held && (anchor_exact_compare(&lower.high, &bracket.low) < 0) &&
                                (anchor_exact_compare(&bracket.high, &unit) < 0);
            if (held)
            {
                exponential_print(&results->line, names[at], &bracket);
            }
            scriptura_text(&results->line, between ? "    lies between (1 + Z (1 + h))^(-h) and 1\n"
                                                   : "    does not lie between (1 + Z (1 + h))^(-h) and 1\n");
            sim_check(results, between, names[at]);
        }
    }
    // c and d. the pressure at d = 0, and its bounds
    {
        const long long cases[3][4] = {{3ll, 2ll, 1ll, 1ll}, {1ll, 1ll, 0ll, 1ll}, {2ll, 1ll, 1ll, 2ll}};
        const char *const names[3] = {"Pi_ext(3/2, 1)", "Pi_ext(1, 0)", "Pi_ext(2, 1/2)"};
        for (unsigned int at = 0u; at < 3u; at += 1u)
        {
            const SimRational x = sim_rational(cases[at][0], cases[at][1]);
            const SimRational eta = sim_rational(cases[at][2], cases[at][3]);
            ExponentialIntegralBracket bracket;
            AnchorExactInteger low;
            AnchorExactInteger high;
            const int held =
                exponential_held(results, exterior_pressure_floor(&x, &eta, &speed, &h, bits, &bracket), names[at],
                                 bits) &&
                exponential_heat_bound(&x, bits, &low, &high);
            AnchorExactInteger zero;
            sim_exact_unsigned(&zero, 0ull);
            // at d = 0 the reading and the closed form overlap; elsewhere the reading lies above the bound and below 0
            const int kept = held && ((at == 0u) ? ((anchor_exact_compare(&bracket.low, &high) <= 0) &&
                                                    (anchor_exact_compare(&low, &bracket.high) <= 0))
                                                 : ((anchor_exact_compare(&high, &bracket.low) < 0) &&
                                                    (anchor_exact_compare(&bracket.high, &zero) < 0)));
            if (held)
            {
                exponential_print(&results->line, names[at], &bracket);
            }
            if (at == 0u)
            {
                scriptura_text(&results->line, kept ? "    is -c^2 X^(-1 - 2h) / (2 (1 + 2h))\n"
                                                    : "    is not -c^2 X^(-1 - 2h) / (2 (1 + 2h))\n");
            }
            else
            {
                scriptura_text(&results->line, kept ? "    lies between -c^2 X^(-1 - 2h) / (2 (1 + 2h)) and 0\n"
                                                    : "    does not lie between -c^2 X^(-1 - 2h) / (2 (1 + 2h)) and 0\n");
            }
            sim_check(results, kept, names[at]);
        }
    }
    sim_flush(results);
    // e. each reading at bits + 64 floors to its reading at bits
    const AnchorExactInteger step = exponential_two_power(EXPONENTIAL_SECOND_BITS);
    for (unsigned int at = 0u; at < EXPONENTIAL_HEAT_ROW_COUNT; at += 1u)
    {
        const ExponentialHeatRow *const row = &s_exponential_heat_rows[at];
        ExponentialIntegralBracket first;
        ExponentialIntegralBracket second;
        const unsigned int deeper = bits + EXPONENTIAL_SECOND_BITS;
        int same = exponential_held(results, exponential_heat_reading(row, bits, &first), row->name, bits) &&
                   exponential_held(results, exponential_heat_reading(row, deeper, &second), row->name, deeper);
        if (same)
        {
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
            same = anchor_exact_equal(&quotient, &first.floor_value);
            exponential_print(&results->line, row->name, &first);
        }
        scriptura_text(&results->line, same ? "    at 2^" : "    does not, at 2^");
        scriptura_decimal(&results->line, deeper, 1u);
        scriptura_text(&results->line, same ? ", floors to its reading at 2^" : ", floor to its reading at 2^");
        scriptura_decimal(&results->line, bits, 1u);
        scriptura_character(&results->line, '\n');
        sim_check(results, same, row->name);
        sim_flush(results);
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
    sim_flush(&results);
    exponential_heat(&results, bits);
    sim_flush(&results);
    exponential_engine(&results, count, arguments, &x, bits);
    return sim_close(&results, "exponential integral");
}
