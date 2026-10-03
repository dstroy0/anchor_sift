// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// axis_heat.cu: the least temperature on the axis of a turning column, by Proposition 21 of the millennium research
// paper
#include "exponential_integral.h"

#include "cfg_json.h"

// The column turns with the potential vortex v r = C outside X = X_b, where X = r^2 / (2 nu tau) and tau is the time
// left to the singular time T*. At the time t = T* - tau its axis stands above the temperature it started at by at
// least
//     A (K(s_b) / tau - J(s_b) / t),   A = C^2 Pr^2 / (4 nu c),   s_b = Pr X_b / 2,
//     K(s) = (1 + 1/s) E1(s) - e^(-s) / s,   J(s) = e^(-s) / s - E1(s),
// with Pr = mu c / k and nu = mu / rho. Every quantity is an exact rational read from the cfg's decimals, and E1(s_b)
// and e^(-s_b) are the exponential integral's brackets at 2^bits. While tau <= T* / 2 the time t is at least T* / 2,
// and the axis has risen by the cfg's rise once tau <= A K / (rise + 2 A J / T*), with K at its low end and J at its
// high end.
// Checks:
// 1. K(s_b) > 0 at its low end, the sign Proposition 21 proves.
// 2. K(s_b) from E1 by its series overlaps K(s_b) from E1 by its continued fraction.
// 3. K(s_b) at 2^(bits + 64) overlaps K(s_b) at 2^bits.
// The request: axis_heat <cfg>.
//     bash examples/navier_stokes/run.sh examples/navier_stokes/cfg/water_20c.cfg

// the tokens a cfg may hold, and the bytes of its text
#define AXIS_HEAT_TOKENS 64u
#define AXIS_HEAT_TEXT 4096u
// the bits a second reading is taken at past the first
#define AXIS_HEAT_SECOND_BITS 64u
// the places after the first digit a value is printed with, truncated
#define AXIS_HEAT_PLACES 12u

// what the cfg gives, each an exact rational
typedef struct
{
    SimRational viscosity;
    SimRational density;
    SimRational conductivity;
    SimRational heat_capacity;
    SimRational circulation;
    SimRational join;
    SimRational singular_time;
    SimRational rise;
    unsigned int bits;
} AxisHeatRequest;

// a value that lies between two exact rationals
typedef struct
{
    SimRational low;
    SimRational high;
} AxisHeatInterval;

// `text`, `length` bytes of plain decimal, read exactly into `value`: 1, or 0 where it does not read
static int axis_heat_decimal(const char *text, size_t length, SimRational *value)
{
    const void *const point = memchr(text, '.', length);
    // the point lies inside the text. The places after it number fewer than the text's bytes
    const unsigned int places = (point != NULL) ? (unsigned int)(length - 1u - (size_t)((const char *)point - text)) : 0u;
    if ((anchor_exact_from_decimal(text, length, places, &value->numerator) != ANCHOR_EXACT_OK) ||
        (sim_exact_power(10ull, places, &value->denominator) == 0))
    {
        return 0;
    }
    sim_rational_settle(value);
    return 1;
}

// the decimal string the member `name` of the object at `object` holds, read into `value`: 1, or 0 where it is missing
// or does not read
static int axis_heat_member(const char *text, const CfgJsonToken *tokens, unsigned int object, const char *name,
                            SimRational *value)
{
    const unsigned int member = cfg_json_member(text, tokens, object, name);
    return (member != 0u) && (tokens[member].kind == CFG_JSON_STRING) &&
           axis_heat_decimal(&text[tokens[member].start], tokens[member].end - tokens[member].start, value);
}

// the cfg at `path` read into `request`: 1, or 0 with the reason written to `line`
static int axis_heat_read(const char *path, AxisHeatRequest *request, ScripturaLine *line)
{
    char text[AXIS_HEAT_TEXT];
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        scriptura_text(line, "  the cfg does not open\n");
        return 0;
    }
    const size_t length = fread(text, 1u, sizeof(text), file);
    const int whole = feof(file) != 0;
    fclose(file);
    CfgJsonToken tokens[AXIS_HEAT_TOKENS];
    CfgJsonParse parse;
    if (!whole || (cfg_json_parse(text, length, tokens, AXIS_HEAT_TOKENS, &parse) == 0))
    {
        scriptura_text(line, whole ? "  the cfg does not parse: " : "  the cfg is longer than the reader holds\n");
        if (whole)
        {
            scriptura_text(line, parse.reason);
            scriptura_character(line, '\n');
        }
        return 0;
    }
    const unsigned int fluid = cfg_json_member(text, tokens, 0u, "fluid");
    const unsigned int column = cfg_json_member(text, tokens, 0u, "column");
    const unsigned int bits = cfg_json_member(text, tokens, 0u, "bits");
    unsigned long long asked = 0ull;
    const int read = (fluid != 0u) && (column != 0u) && (bits != 0u) &&
                     axis_heat_member(text, tokens, fluid, "viscosity", &request->viscosity) &&
                     axis_heat_member(text, tokens, fluid, "density", &request->density) &&
                     axis_heat_member(text, tokens, fluid, "conductivity", &request->conductivity) &&
                     axis_heat_member(text, tokens, fluid, "heat_capacity", &request->heat_capacity) &&
                     axis_heat_member(text, tokens, column, "circulation", &request->circulation) &&
                     axis_heat_member(text, tokens, column, "join", &request->join) &&
                     axis_heat_member(text, tokens, column, "singular_time", &request->singular_time) &&
                     axis_heat_member(text, tokens, column, "rise", &request->rise) &&
                     cfg_json_unsigned(text, &tokens[bits], &asked) && (asked > 0ull) && (asked < (1ull << 20u));
    if (!read)
    {
        scriptura_text(line, "  the cfg lacks a value, or one does not read: fluid viscosity, density, conductivity "
                             "and heat_capacity, column circulation, join, singular_time and rise as decimal strings, "
                             "and bits a whole number\n");
        return 0;
    }
    // below 2^20, checked above
    request->bits = (unsigned int)asked;
    return 1;
}

// numerator / denominator as a rational in lowest terms; the denominator is positive
static SimRational axis_heat_ratio(const AnchorExactInteger *numerator, const AnchorExactInteger *denominator)
{
    SimRational value;
    value.numerator = *numerator;
    value.denominator = *denominator;
    sim_rational_settle(&value);
    return value;
}

// K(s) and J(s) between the ends E1(s) and e^(-s) give at 2^bits, s = p / q:
// K 2^bits = (E1 2^bits (p + q) - e^(-s) 2^bits q) / p and J 2^bits = (e^(-s) 2^bits q - E1 2^bits p) / p
static void axis_heat_shares(const SimRational *s, const ExponentialIntegralBracket *integral,
                             const ExponentialIntegralBracket *decay, AxisHeatInterval *kept,
                             AxisHeatInterval *before_start)
{
    AnchorExactInteger unit;
    AnchorExactInteger below;
    AnchorExactInteger whole;
    AnchorExactInteger first;
    AnchorExactInteger second;
    AnchorExactInteger top;
    sim_exact_power(2ull, integral->bits, &unit);
    sim_exact_product(&s->numerator, &unit, &below);
    sim_exact_sum(&s->numerator, &s->denominator, &whole);
    sim_exact_product(&integral->low, &whole, &first);
    sim_exact_product(&decay->high, &s->denominator, &second);
    sim_exact_less(&first, &second, &top);
    kept->low = axis_heat_ratio(&top, &below);
    sim_exact_product(&integral->high, &whole, &first);
    sim_exact_product(&decay->low, &s->denominator, &second);
    sim_exact_less(&first, &second, &top);
    kept->high = axis_heat_ratio(&top, &below);
    sim_exact_product(&decay->low, &s->denominator, &first);
    sim_exact_product(&integral->high, &s->numerator, &second);
    sim_exact_less(&first, &second, &top);
    before_start->low = axis_heat_ratio(&top, &below);
    sim_exact_product(&decay->high, &s->denominator, &first);
    sim_exact_product(&integral->low, &s->numerator, &second);
    sim_exact_less(&first, &second, &top);
    before_start->high = axis_heat_ratio(&top, &below);
}

// 1 where the two intervals share a point
static int axis_heat_overlap(const AxisHeatInterval *one, const AxisHeatInterval *other)
{
    return (sim_rational_sign(sim_rational_difference(one->low, other->high)) <= 0) &&
           (sim_rational_sign(sim_rational_difference(other->low, one->high)) <= 0);
}

// `value` as d.ddd... e n, its first digit and AXIS_HEAT_PLACES more, truncated, every step exact
static void axis_heat_print(ScripturaLine *line, SimRational value)
{
    if (sim_rational_sign(value) == 0)
    {
        scriptura_character(line, '0');
        return;
    }
    if (sim_rational_sign(value) < 0)
    {
        scriptura_character(line, '-');
        value = sim_rational_absolute(value);
    }
    const SimRational ten = sim_rational(10ll, 1ll);
    const SimRational one = sim_rational(1ll, 1ll);
    long long exponent = 0ll;
    while (sim_rational_sign(sim_rational_difference(value, ten)) >= 0)
    {
        value = sim_rational_product(value, sim_rational_reciprocal(ten));
        exponent += 1ll;
    }
    while (sim_rational_sign(sim_rational_difference(value, one)) < 0)
    {
        value = sim_rational_product(value, ten);
        exponent -= 1ll;
    }
    sim_ratio_print(line, &value.numerator, &value.denominator, AXIS_HEAT_PLACES);
    if (exponent != 0ll)
    {
        scriptura_character(line, 'e');
        scriptura_signed(line, exponent);
    }
}

// one named value and its unit on a line
static void axis_heat_line(ScripturaLine *line, const char *name, SimRational value, const char *unit)
{
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " = ");
    axis_heat_print(line, value);
    scriptura_text(line, unit);
    scriptura_character(line, '\n');
}

// one named interval and its unit on a line
static void axis_heat_interval(ScripturaLine *line, const char *name, const AxisHeatInterval *interval,
                               const char *unit)
{
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " between ");
    axis_heat_print(line, interval->low);
    scriptura_text(line, " and ");
    axis_heat_print(line, interval->high);
    scriptura_text(line, unit);
    scriptura_character(line, '\n');
}

// a reading's verdict reported: 1 where it is held; the width named where the build's cannot hold it
static int axis_heat_held(SimResults *results, int status, const char *name, unsigned int bits)
{
    if (status == EXPONENTIAL_INTEGRAL_HELD)
    {
        return 1;
    }
    scriptura_text(&results->line, "  ");
    scriptura_text(&results->line, name);
    scriptura_text(&results->line, " at 2^");
    scriptura_decimal(&results->line, bits, 1u);
    if (status == EXPONENTIAL_INTEGRAL_WIDTH)
    {
        scriptura_text(&results->line, " is refused: the build's exact width, ");
        scriptura_decimal(&results->line, exponential_integral_width(), 1u);
        scriptura_text(&results->line, " bits (SIM_EXACT_LIMBS), does not hold its bracket\n");
    }
    else
    {
        scriptura_text(&results->line, " is refused: s_b is outside its domain\n");
    }
    sim_check(results, 0, name);
    return 0;
}

// K(s_b) and J(s_b) at 2^bits, E1 by its continued fraction, or by its series where `series` is set: 1 where both
// brackets are held
static int axis_heat_reading(SimResults *results, const SimRational *s, unsigned int bits, int series,
                             AxisHeatInterval *kept, AxisHeatInterval *before_start)
{
    ExponentialIntegralBracket integral;
    ExponentialIntegralBracket decay;
    const int integral_status =
        series ? exponential_integral_series_floor(s, bits, &integral) : exponential_integral_floor(s, bits, &integral);
    const int held = axis_heat_held(results, integral_status, series ? "E1(s_b) by its series" : "E1(s_b)", bits) &&
                     axis_heat_held(results, exponential_negative_floor(s, bits, &decay), "e^(-s_b)", bits);
    if (held)
    {
        axis_heat_shares(s, &integral, &decay, kept, before_start);
    }
    return held;
}

int main(int count, char **arguments)
{
    char capacity[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, capacity);
    AxisHeatRequest request;
    if ((count != 2) || (axis_heat_read(arguments[1], &request, &results.line) == 0))
    {
        sim_flush(&results);
        fprintf(stderr, "axis_heat <cfg>\n");
        return 2;
    }
    const SimRational two = sim_rational(2ll, 1ll);
    const SimRational four = sim_rational(4ll, 1ll);
    const SimRational diffusion = sim_rational_product(request.viscosity, sim_rational_reciprocal(request.density));
    const SimRational prandtl = sim_rational_product(sim_rational_product(request.viscosity, request.heat_capacity),
                                                     sim_rational_reciprocal(request.conductivity));
    const SimRational s = sim_rational_product(sim_rational_product(prandtl, request.join), sim_rational_reciprocal(two));
    const SimRational squared = sim_rational_product(sim_rational_product(request.circulation, request.circulation),
                                                     sim_rational_product(prandtl, prandtl));
    const SimRational scale = sim_rational_product(
        squared, sim_rational_reciprocal(sim_rational_product(four, sim_rational_product(diffusion, request.heat_capacity))));
    scriptura_text(&results.line, "  axis heat: the potential vortex outside X_b, read at 2^");
    scriptura_decimal(&results.line, request.bits, 1u);
    scriptura_character(&results.line, '\n');
    axis_heat_line(&results.line, "nu", diffusion, " m^2/s");
    axis_heat_line(&results.line, "Pr", prandtl, "");
    axis_heat_line(&results.line, "s_b = Pr X_b / 2", s, "");
    axis_heat_line(&results.line, "A = C^2 Pr^2 / (4 nu c)", scale, " K s");
    AxisHeatInterval kept;
    AxisHeatInterval before_start;
    AxisHeatInterval kept_series;
    AxisHeatInterval before_start_series;
    AxisHeatInterval kept_deeper;
    AxisHeatInterval before_start_deeper;
    const int held = axis_heat_reading(&results, &s, request.bits, 0, &kept, &before_start);
    const int series_held = axis_heat_reading(&results, &s, request.bits, 1, &kept_series, &before_start_series);
    const int deeper_held = axis_heat_reading(&results, &s, request.bits + AXIS_HEAT_SECOND_BITS, 0, &kept_deeper,
                                              &before_start_deeper);
    if (held)
    {
        axis_heat_interval(&results.line, "K(s_b)", &kept, "");
        axis_heat_interval(&results.line, "J(s_b)", &before_start, "");
        const SimRational lowest = sim_rational_product(scale, kept.low);
        const SimRational start = sim_rational_product(scale, before_start.high);
        axis_heat_line(&results.line, "A K(s_b), the least coefficient of 1 / tau", lowest, " K s");
        axis_heat_line(&results.line, "A J(s_b), the most coefficient of 1 / t", start, " K s");
        // tau <= A K / (rise + 2 A J / T*), and no later than T* / 2
        const SimRational spent =
            sim_rational_product(sim_rational_product(two, start), sim_rational_reciprocal(request.singular_time));
        const SimRational reached =
            sim_rational_product(lowest, sim_rational_reciprocal(sim_rational_sum(request.rise, spent)));
        const SimRational half = sim_rational_product(request.singular_time, sim_rational_reciprocal(two));
        const SimRational time_left =
            (sim_rational_sign(sim_rational_difference(reached, half)) <= 0) ? reached : half;
        axis_heat_line(&results.line, "the latest tau by which the axis has risen by the cfg's rise", time_left, " s");
        // 1. the sign Proposition 21 proves
        const int positive = sim_rational_sign(kept.low) > 0;
        scriptura_text(&results.line, positive ? "  K(s_b) > 0 at its low end\n" : "  K(s_b) is not above 0 at its low end\n");
        sim_check(&results, positive, "K(s_b) > 0");
    }
    // 2. the series and the continued fraction
    const int routes = held && series_held && axis_heat_overlap(&kept, &kept_series);
    scriptura_text(&results.line, routes ? "  K(s_b) by E1's series overlaps K(s_b) by its continued fraction\n"
                                         : "  K(s_b) by E1's series does not overlap K(s_b) by its continued fraction\n");
    sim_check(&results, routes, "K(s_b) by E1's series and by its continued fraction");
    // 3. a deeper reading
    const int deeper = held && deeper_held && axis_heat_overlap(&kept, &kept_deeper);
    scriptura_text(&results.line, deeper ? "  K(s_b) at 2^(bits + 64) overlaps K(s_b) at 2^bits\n"
                                         : "  K(s_b) at 2^(bits + 64) does not overlap K(s_b) at 2^bits\n");
    sim_check(&results, deeper, "K(s_b) at 2^(bits + 64)");
    return sim_close(&results, "axis heat");
}
