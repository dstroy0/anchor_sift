// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_tower_engine.cu: the engine, depth and requests
#include "pi_tower_internal.h"

// 13 and 14 on the engine: position 0 and Bailey's, and the tower's deepest resolution asked for. 15, a segment, is a
// request of its own (pi_tower_segment_request)
void pi_tower_engine(SimResults *results, int count, char **arguments, const PiTowerTurn &turn, unsigned int depth)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long lanes = pi_tower_bbp_lanes();
    unsigned int window = 0u;
    const PiWide tower_position = pi_tower_depth_position(pi_tower_unsigned(depth), &window);
    std::vector<PiTowerBbp> plans(PI_TOWER_PUBLISHED_COUNT + 1u);
    int planned = lanes != 0ull;
    unsigned long long declared = 0ull;
    for (size_t at = 0u; (planned != 0) && (at < plans.size()); at += 1u)
    {
        const PiWide position = (at < PI_TOWER_PUBLISHED_COUNT)
                                    ? pi_tower_unsigned(s_pi_tower_published[at].position - 1ull)
                                    : tower_position;
        planned = pi_tower_bbp_plan(&plans[at], position, lanes, &error);
        const unsigned long long bytes = (planned != 0) ? pi_tower_bbp_bytes(&plans[at]) : 0ull;
        declared = (bytes > declared) ? bytes : declared;
    }
    sim_check(results, planned, "engine: keymath encodes and the scheduler lays out the term, tail and pair programs");
    if ((planned == 0) || !sim_job_submit(results, "pi_tower", count, arguments, declared))
    {
        for (size_t at = 0u; at < plans.size(); at += 1u)
        {
            pi_tower_bbp_free(&plans[at]);
        }
        return;
    }
    scriptura_text(&results->line, "  on the engine, pi's hex digits by BBP, each term a lane of the record machine\n");
    sim_flush(results);
    int published = 1;
    int finished = 1;
    for (size_t at = 0u; at < PI_TOWER_PUBLISHED_COUNT; at += 1u)
    {
        PiTowerBbpRun run;
        const int ran = pi_tower_bbp_sum(results, &plans[at], 0, &run);
        const unsigned int certified = (ran != 0) ? pi_tower_bbp_certified(&plans[at], run.sum) : 0u;
        pi_tower_bbp_print(results, &plans[at], &run, certified);
        const std::string expected = s_pi_tower_published[at].digits;
        finished = finished && ran && run.finished;
        // a published string is at most 23 digits. Its length fits an unsigned int
        published = published && ran && run.finished && ((4u * expected.size()) <= certified) &&
                    (pi_tower_bbp_hex(&plans[at], run.sum, (unsigned int)expected.size()) == expected);
    }
    sim_check(results, finished, "engine: every run sums all its terms");
    sim_check(results, published,
              "on the engine, pi's first 64 bits are 0x243F6A8885A308D3 and its hex digits at Bailey's positions 10^6, "
              "10^6 + 1, 10^7 and 10^8 are his");
    PiTowerBbpRun run;
    PiTowerBbp *const tower = &plans[PI_TOWER_PUBLISHED_COUNT];
    const int ran = pi_tower_bbp_sum(results, tower, 0, &run);
    const unsigned int certified = (ran != 0) ? pi_tower_bbp_certified(tower, run.sum) : 0u;
    pi_tower_bbp_print(results, tower, &run, certified);
    const unsigned long long engine_cell = (ran != 0) ? pi_tower_bbp_cell(tower, run.sum, window) : 0ull;
    const unsigned long long exact_cell =
        pi_tower_word(pi_tower_quotient(turn.multiplier, pi_tower_power_two(turn.precision - depth)));
    scriptura_text(&results->line, "    the cell at 2^");
    scriptura_decimal(&results->line, depth, 1u);
    scriptura_text(&results->line, ", its low 64 bits: engine 0x");
    scriptura_hex(&results->line, engine_cell, 16u);
    scriptura_text(&results->line, ", exact turn 0x");
    scriptura_hex(&results->line, exact_cell, 16u);
    scriptura_character(&results->line, '\n');
    sim_check(results, ran && run.finished && (certified >= window) && (engine_cell == exact_cell),
              "the engine's cell at the deepest resolution asked for, its low 64 bits, is the exact turn's");
    for (size_t at = 0u; at < plans.size(); at += 1u)
    {
        pi_tower_bbp_free(&plans[at]);
    }
    sim_flush(results);
}

// a resolution past the exact turn's: held as (2, n), every part that does not ask for pi's bits printed exact, and
// the depth-n turn summed on the engine sweep by sweep until every term is in or the run is stopped
void pi_tower_deep(SimResults *results, int count, char **arguments, const PiWide &depth)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const PiWide word = pi_tower_unsigned(64ull);
    const PiWide precision = pi_tower_product(
        pi_tower_quotient(pi_tower_sum(pi_tower_sum(pi_tower_product(depth, pi_tower_unsigned(3ull)), word),
                                       pi_tower_unsigned(63ull)),
                          word),
        word);
    const PiWide needed = pi_tower_sum(
        pi_tower_product(pi_tower_sum(precision, pi_tower_unsigned(PI_TOWER_GUARD)), pi_tower_unsigned(3ull)), word);
    // the exact width a host turn would need, as a power of two of limbs
    unsigned int width = 0u;
    while (pi_tower_compare(pi_tower_product(pi_tower_power_two(width), pi_tower_unsigned(32ull)), needed) < 0)
    {
        width += 1u;
    }
    scriptura_text(&results->line, "  resolution (2, n): 2^n cells, n = ");
    pi_tower_print_decimal(&results->line, depth);
    scriptura_text(&results->line, "\n    the turn's precision P = ");
    pi_tower_print_decimal(&results->line, precision);
    scriptura_text(&results->line, " bits; a host turn would need an exact width of ");
    pi_tower_print_decimal(&results->line, needed);
    scriptura_text(&results->line, " bits, SIM_EXACT_LIMBS = 2^");
    scriptura_decimal(&results->line, width, 1u);
    scriptura_character(&results->line, '\n');
    sim_flush(results);
    unsigned int window = 0u;
    const PiWide position = pi_tower_depth_position(depth, &window);
    PiTowerBbp bbp;
    const unsigned long long lanes = pi_tower_bbp_lanes();
    const int planned = (lanes != 0ull) && pi_tower_bbp_plan(&bbp, position, lanes, &error);
    sim_check(results, planned, "engine: keymath encodes and the scheduler lays out the term, tail and pair programs");
    if (planned == 0)
    {
        return;
    }
    if (!sim_job_submit(results, "pi_tower", count, arguments, pi_tower_bbp_bytes(&bbp)))
    {
        pi_tower_bbp_free(&bbp);
        return;
    }
    scriptura_text(&results->line,
                   "    the turn at depth n is alpha's bit n: its cell's low bits are the window from hex position ");
    pi_tower_print_decimal(&results->line, position);
    scriptura_text(&results->line, ", on the engine\n");
    sim_flush(results);
    g_pi_tower_stopped = 0;
    void (*const was)(int) = signal(SIGINT, pi_tower_stop);
    PiTowerBbpRun run;
    const int ran = pi_tower_bbp_sum(results, &bbp, 1, &run);
    signal(SIGINT, was);
    pi_tower_bbp_progress(results, &bbp, &run);
    const unsigned int certified = ((ran != 0) && (run.finished != 0)) ? pi_tower_bbp_certified(&bbp, run.sum) : 0u;
    pi_tower_bbp_print(results, &bbp, &run, certified);
    if ((run.finished != 0) && (certified >= window))
    {
        scriptura_text(&results->line, "    the cell at 2^n, its low 64 bits: 0x");
        scriptura_hex(&results->line, pi_tower_bbp_cell(&bbp, run.sum, window), 16u);
        scriptura_character(&results->line, '\n');
    }
    else if (run.finished == 0)
    {
        scriptura_text(&results->line, "    stopped: no digit at depth n is printed until every term is summed\n");
    }
    sim_check(results, ran, "engine: every sweep the run made summed on the record machine");
    sim_check(results, (run.finished == 0) || (certified >= window),
              "a finished run certifies the window through depth n");
    pi_tower_bbp_free(&bbp);
    sim_flush(results);
}

// a whole number of decimal digits, from the text up to the first character that is not one; 0 where there are none
static int pi_tower_digits(const char **text, PiWide *value)
{
    const PiWide ten = pi_tower_unsigned(10ull);
    *value = pi_tower_unsigned(0ull);
    const char *walk = *text;
    while ((*walk >= '0') && (*walk <= '9'))
    {
        // one decimal digit, 0 to 9
        *value = pi_tower_sum(pi_tower_product(*value, ten), pi_tower_unsigned((unsigned long long)(*walk - '0')));
        walk += 1;
    }
    const int read = walk != *text;
    *text = walk;
    return read;
}

// n from the request, whole or as base^exponent, the base and its operation kept apart until n is formed; 0 where the
// text is neither, n is 0, or n outgrows the exact width
int pi_tower_request(const char *text, PiWide *value)
{
    if (text == NULL)
    {
        return 0;
    }
    g_pi_tower_error = 0;
    const char *walk = text;
    PiWide base;
    if (pi_tower_digits(&walk, &base) == 0)
    {
        return 0;
    }
    *value = base;
    if (*walk == '^')
    {
        walk += 1;
        PiWide exponent;
        if ((pi_tower_digits(&walk, &exponent) == 0) ||
            (pi_tower_compare(exponent, pi_tower_unsigned(ANCHOR_EXACT_BITS)) > 0))
        {
            return 0;
        }
        // base^exponent by squaring, over the exponent's bits from the top
        *value = pi_tower_unsigned(1ull);
        for (unsigned int bit = pi_tower_bit_length(exponent); (bit > 0u) && (g_pi_tower_error == 0); bit -= 1u)
        {
            *value = pi_tower_product(*value, *value);
            if (((exponent.limb[(bit - 1u) / 32u] >> ((bit - 1u) % 32u)) & 1u) != 0u)
            {
                *value = pi_tower_product(*value, base);
            }
        }
    }
    return (*walk == '\0') && (value->sign != 0) && (g_pi_tower_error == 0);
}

// a resolution from the request, from 1 to 2^20
int pi_tower_resolution(const char *text, unsigned int *bits)
{
    PiWide value;
    if ((pi_tower_request(text, &value) == 0) || (pi_tower_compare(value, pi_tower_unsigned(PI_TOWER_EXACT_MAX)) > 0))
    {
        return 0;
    }
    // at most 2^20. An unsigned int holds it
    *bits = (unsigned int)pi_tower_word(value);
    return 1;
}
