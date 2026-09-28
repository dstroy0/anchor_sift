// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_tower_main.cu: main
#include "pi_tower_internal.h"

static void pi_tower_fill(SimResults *results, const PiTowerTurn &turn, const std::vector<PiWide> &denominators,
                          const std::vector<PiWide> &floors, unsigned int from_bits, unsigned int to_bits,
                          const PiWide &walk_alpha);

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    unsigned int from_bits = PI_TOWER_RESOLUTION_FIRST;
    unsigned int to_bits = PI_TOWER_RESOLUTION_LAST;
    const int single = (count == 2) && pi_tower_resolution(arguments[1], &from_bits);
    const int ranged = (count == 3) && pi_tower_resolution(arguments[1], &from_bits) &&
                       pi_tower_resolution(arguments[2], &to_bits) && (from_bits <= to_bits);
    if (single != 0)
    {
        to_bits = from_bits;
    }
    PiWide deep;
    if ((count == 2) && (single == 0) && (pi_tower_request(arguments[1], &deep) != 0))
    {
        pi_tower_deep(&results, count, arguments, deep);
        return sim_close(&results, "pi tower");
    }
    // 15: pi_tower segment d [digits], d whole or base^exponent and 0 allowed, digits 1 to PI_TOWER_SEGMENT_MAX
    if ((count >= 3) && (count <= 4) && (strcmp(arguments[1], "segment") == 0))
    {
        PiWide position = pi_tower_unsigned(0ull);
        PiWide digits = pi_tower_unsigned(PI_TOWER_SEGMENT_DIGITS);
        const int placed = (strcmp(arguments[2], "0") == 0) || (pi_tower_request(arguments[2], &position) != 0);
        const int sized = (count == 3) || ((pi_tower_request(arguments[3], &digits) != 0) &&
                                           (pi_tower_compare(digits, pi_tower_unsigned(PI_TOWER_SEGMENT_MAX)) <= 0));
        if ((placed != 0) && (sized != 0))
        {
            // at most PI_TOWER_SEGMENT_MAX. An unsigned int holds it
            pi_tower_segment_request(&results, count, arguments, position, (unsigned int)pi_tower_word(digits));
            return sim_close(&results, "pi tower");
        }
    }
    if ((count > 1) && (single == 0) && (ranged == 0))
    {
        scriptura_text(&results.line,
                       "  usage: pi_tower [n] or pi_tower [from] [to], resolutions 2^1 to 2^1048576 cells; pi_tower "
                       "n\n  past 2^20, n whole or base^exponent, reads the depth-n turn on the engine alone; pi_tower "
                       "segment d [digits]\n  reads that many hex digits (1 to ");
        scriptura_decimal(&results.line, PI_TOWER_SEGMENT_MAX, 1u);
        scriptura_text(&results.line, ", ");
        scriptura_decimal(&results.line, PI_TOWER_SEGMENT_DIGITS, 1u);
        scriptura_text(&results.line, " if none) from position d + 1 on the engine\n");
        sim_check(&results, 0, "the request names its resolutions");
        return sim_close(&results, "pi tower");
    }
    // P = 3 n + 64 rounded up to a word, at least the walks' 384
    unsigned int precision = (((3u * to_bits) + 64u + 63u) / 64u) * 64u;
    precision = (precision < PI_TOWER_BITS) ? PI_TOWER_BITS : precision;
    const unsigned long long needed = (3ull * (precision + PI_TOWER_GUARD)) + 64ull;
    scriptura_text(&results.line, "  resolutions 2^");
    scriptura_decimal(&results.line, from_bits, 1u);
    scriptura_text(&results.line, " to 2^");
    scriptura_decimal(&results.line, to_bits, 1u);
    scriptura_text(&results.line, " cells, the turn held to ");
    scriptura_decimal(&results.line, precision, 1u);
    scriptura_text(&results.line, " bits, in an exact width of ");
    scriptura_decimal(&results.line, (unsigned long long)ANCHOR_EXACT_BITS, 1u);
    scriptura_text(&results.line, " bits\n");
    if (needed > (unsigned long long)ANCHOR_EXACT_BITS)
    {
        unsigned long long limbs = 1ull;
        while ((limbs * 32ull) < needed)
        {
            limbs *= 2ull;
        }
        scriptura_text(&results.line, "  the turn needs an exact width of ");
        scriptura_decimal(&results.line, needed, 1u);
        scriptura_text(&results.line, " bits: run with SIM_EXACT_LIMBS=");
        scriptura_decimal(&results.line, limbs, 1u);
        scriptura_character(&results.line, '\n');
        sim_check(&results, 0, "the exact width holds the turn the resolutions ask for");
        return sim_close(&results, "pi tower");
    }
    PiTowerTurn turn;
    PiWide pi_low;
    PiWide pi_high;
    if (pi_tower_bracket(&results, precision, &turn.multiplier, &pi_low, &pi_high) == 0)
    {
        return sim_close(&results, "pi tower");
    }
    pi_tower_arc(&results, pi_low, pi_high, precision + PI_TOWER_GUARD);
    turn.modulus = pi_tower_power_two(precision);
    turn.precision = precision;
    turn.range = ((to_bits + PI_TOWER_RECORD_MARGIN) > PI_TOWER_RECORD_BITS) ? (to_bits + PI_TOWER_RECORD_MARGIN)
                                                                             : PI_TOWER_RECORD_BITS;
    turn.lowest = pi_tower_records(turn, 1);
    turn.highest = pi_tower_records(turn, 0);
    // the walks' turn, floor(alpha 2^384): a floor of a floor is the floor
    const PiWide walk_alpha = pi_tower_quotient(turn.multiplier, pi_tower_power_two(precision - PI_TOWER_BITS));
    std::vector<PiWide> denominators;
    std::vector<PiWide> floors;
    pi_tower_floors(&results, turn, &denominators, &floors);
    pi_tower_residues(&results, walk_alpha, denominators, floors);
    pi_tower_golden(&results, turn, denominators, floors);
    pi_tower_billiard(&results, walk_alpha, denominators);
    pi_tower_fill(&results, turn, denominators, floors, from_bits, to_bits, walk_alpha);
    pi_tower_engine(&results, count, arguments, turn, to_bits);
    return sim_close(&results, "pi tower");
}

// 4, 5 and 6. at each resolution, the step that fills the boundary: the least count of steps whose points touch every
// cell, found by doubling and halving on the three gap test
static void pi_tower_fill(SimResults *results, const PiTowerTurn &turn, const std::vector<PiWide> &denominators,
                          const std::vector<PiWide> &floors, unsigned int from_bits, unsigned int to_bits,
                          const PiWide &walk_alpha)
{
    const PiWide one = pi_tower_unsigned(1ull);
    const PiWide two = pi_tower_unsigned(2ull);
    int certain = 1;
    int walked = 1;
    int touched = 1;
    int found_home = 1;
    unsigned int same_period = 0u;
    unsigned int walks = 0u;
    const unsigned int walks_expected =
        (from_bits > PI_TOWER_WALK_MAX)
            ? 0u
            : (((to_bits < PI_TOWER_WALK_MAX) ? to_bits : PI_TOWER_WALK_MAX) - from_bits + 1u);
    scriptura_text(&results->line, "  2^k cells: the step that fills the boundary, its ratio to the cells, the last "
                                   "cell filled as a place on the circle, and the floor it fills on\n");
    for (unsigned int bits = from_bits; bits <= to_bits; bits += 1u)
    {
        const PiWide cells = pi_tower_power_two(bits);
        const PiWide cell = pi_tower_power_two(turn.precision - bits);
        PiWide covering = cells;
        PiWide short_of = pi_tower_difference(cells, one);
        while (pi_tower_covered(turn, cell, covering) == 0)
        {
            short_of = covering;
            covering = pi_tower_product(covering, two);
        }
        while (pi_tower_compare(pi_tower_difference(covering, short_of), one) > 0)
        {
            const PiWide middle = pi_tower_quotient(pi_tower_sum(covering, short_of), two);
            if (pi_tower_covered(turn, cell, middle) != 0)
            {
                covering = middle;
            }
            else
            {
                short_of = middle;
            }
        }
        const PiWide fill = pi_tower_difference(covering, one);
        const PiWide place = pi_tower_remainder(pi_tower_product(turn.multiplier, fill), turn.modulus);
        const PiWide last = pi_tower_quotient(place, cell);

        // cell 0 etched again: the least step after the fill whose place is below one cell
        PiWide home;
        const int homed = pi_tower_first_hit_from(turn.multiplier, turn.modulus, covering, pi_tower_unsigned(0ull),
                                                  pi_tower_difference(cell, one), &home);
        found_home = found_home && homed;
        // and the fill's last cell etched again after that: the second run's close
        PiWide closing;
        const PiWide closing_low = pi_tower_product(last, cell);
        const int closed = (homed != 0) &&
                           pi_tower_first_hit_from(turn.multiplier, turn.modulus, pi_tower_sum(home, one), closing_low,
                                                   pi_tower_difference(pi_tower_sum(closing_low, cell), one), &closing);
        found_home = found_home && closed;
        const PiWide range = (closed != 0) ? pi_tower_sum(closing, one) : covering;

        // the integer turn is the real one on every step below range: step n's real place lies in
        // (n A, n A + n), which crosses into the next cell only where (n A mod cell) > cell - n
        PiWide unsure;
        const PiWide multiplier = pi_tower_remainder(turn.multiplier, cell);
        const int wanders = pi_tower_first_hit(multiplier, cell, pi_tower_sum(pi_tower_difference(cell, range), one),
                                               pi_tower_difference(cell, one), &unsure) &&
                            (pi_tower_compare(unsure, range) < 0);
        certain = certain && (wanders == 0);

        PiWide first;
        const PiWide low = pi_tower_product(last, cell);
        touched = touched &&
                  pi_tower_first_hit(turn.multiplier, turn.modulus, low,
                                     pi_tower_difference(pi_tower_sum(low, cell), one), &first) &&
                  (pi_tower_compare(first, fill) == 0);

        size_t level = 0u;
        while (((level + 1u) < denominators.size()) && (pi_tower_compare(denominators[level + 1u], fill) <= 0))
        {
            level += 1u;
        }
        scriptura_text(&results->line, "    2^");
        scriptura_decimal(&results->line, bits, 1u);
        scriptura_text(&results->line, "  step ");
        pi_tower_print_exponent(&results->line, fill, one);
        scriptura_text(&results->line, " = ");
        pi_tower_print_decimal(&results->line, fill);
        scriptura_text(&results->line, "  x");
        sim_ratio_print(&results->line, &fill, &cells, 4u);
        scriptura_text(&results->line, "  last cell at ");
        sim_ratio_print(&results->line, &last, &cells, 12u);
        scriptura_text(&results->line, "  floor ");
        scriptura_decimal(&results->line, level, 1u);
        if ((level + 1u) < floors.size())
        {
            scriptura_text(&results->line, " (a ");
            pi_tower_print_decimal(&results->line, floors[level + 1u]);
            scriptura_character(&results->line, ')');
        }
        if (homed != 0)
        {
            scriptura_text(&results->line, "  cell 0 again at step ");
            pi_tower_print_decimal(&results->line, home);
            scriptura_text(&results->line, ", ");
            pi_tower_print_decimal(&results->line, pi_tower_difference(home, fill));
            scriptura_text(&results->line, " after the fill");
        }
        if (closed != 0)
        {
            const PiWide second = pi_tower_difference(closing, home);
            const int order = pi_tower_compare(second, fill);
            scriptura_text(&results->line, "; the last cell again at step ");
            pi_tower_print_decimal(&results->line, closing);
            scriptura_text(&results->line, ", ");
            pi_tower_print_decimal(&results->line, second);
            scriptura_text(&results->line, " after cell 0: ");
            if (order == 0)
            {
                scriptura_text(&results->line, "the same period");
                same_period += 1u;
            }
            else
            {
                pi_tower_print_decimal(&results->line, (order < 0) ? pi_tower_difference(fill, second)
                                                                   : pi_tower_difference(second, fill));
                scriptura_text(&results->line, (order < 0) ? " shorter" : " longer");
            }
        }
        if (bits <= PI_TOWER_WALK_MAX)
        {
            unsigned long long walked_last = 0ull;
            unsigned long long stall = 0ull;
            unsigned long long again = 0ull;
            unsigned long long walked_home = 0ull;
            unsigned long long walked_closing = 0ull;
            const unsigned long long walked_fill =
                pi_tower_walk(walk_alpha, bits, &walked_last, &stall, &again, &walked_home, &walked_closing);
            walked = walked && (walked_fill == pi_tower_word(fill)) && (walked_last == pi_tower_word(last)) &&
                     (closed != 0) && (walked_home == pi_tower_word(home)) &&
                     (walked_closing == pi_tower_word(closing));
            walks += 1u;
            scriptura_text(&results->line, "  walked ");
            scriptura_decimal(&results->line, walked_fill, 1u);
            scriptura_text(&results->line, ", longest stall ");
            scriptura_decimal(&results->line, stall, 1u);
            scriptura_text(&results->line, ", etched again by ");
            scriptura_decimal(&results->line, again, 1u);
        }
        scriptura_character(&results->line, '\n');
        sim_flush(results);
    }
    sim_check(results, certain,
              "the integer turn lands in the real turn's cell on every step searched, at every resolution");
    sim_check(results, walked && (walks == walks_expected),
              "the step, the last cell and cell 0's next etch read from the floors equal a walk of every step, at "
              "every resolution asked for up to 2^24 cells");
    sim_check(results, found_home,
              "at every resolution cell 0 is etched again after the fill, then the fill's last cell, at steps the "
              "floors name");
    sim_check(results, s_pi_tower_records_short == 0, "every count searched stands within the records' range");
    scriptura_text(&results->line,
                   "  the second run, cell 0 to the first run's last cell, has the first run's period at ");
    scriptura_decimal(&results->line, same_period, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, (to_bits - from_bits) + 1u, 1u);
    scriptura_text(&results->line, " resolutions\n");
    sim_flush(results);
    sim_check(results, touched, "at every resolution the last cell's first touch is the step that fills the boundary");
    sim_check(results, s_pi_tower_refused == 0, "no exact operation outgrew the width");
}
