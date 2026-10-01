// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_tower_records.cu: partial quotients, records and floors
#include "pi_tower_internal.h"

// pi's continued fraction's partial quotients after the 3, from numerator / denominator below 1
static std::vector<PiWide> pi_tower_partial_quotients(const PiWide &numerator, const PiWide &denominator)
{
    std::vector<PiWide> quotients;
    PiWide top = denominator;
    PiWide bottom = numerator;
    while (bottom.sign != 0)
    {
        quotients.push_back(pi_tower_quotient(top, bottom));
        const PiWide rest = pi_tower_remainder(top, bottom);
        top = bottom;
        bottom = rest;
    }
    return quotients;
}

// the steps at which the turn stands lower (or higher) than at every step since 1, to 2^turn.range
std::vector<PiTowerRecord> pi_tower_records(const PiTowerTurn &turn, int lowest)
{
    const PiWide one = pi_tower_unsigned(1ull);
    const PiWide bound = pi_tower_power_two(turn.range);
    std::vector<PiTowerRecord> records;
    PiTowerRecord record;
    record.step = one;
    record.place = pi_tower_remainder(turn.multiplier, turn.modulus);
    records.push_back(record);
    for (;;)
    {
        const PiWide place = records.back().place;
        PiWide step;
        int found = 0;
        if (lowest != 0)
        {
            found = (pi_tower_compare(place, one) > 0) &&
                    pi_tower_first_hit(turn.multiplier, turn.modulus, one, pi_tower_difference(place, one), &step);
        }
        else
        {
            const PiWide top = pi_tower_difference(turn.modulus, one);
            found = (pi_tower_compare(place, top) < 0) &&
                    pi_tower_first_hit(turn.multiplier, turn.modulus, pi_tower_sum(place, one), top, &step);
        }
        if ((found == 0) || (pi_tower_compare(step, bound) > 0))
        {
            return records;
        }
        record.step = step;
        record.place = pi_tower_remainder(pi_tower_product(turn.multiplier, step), turn.modulus);
        records.push_back(record);
    }
}

// the record standing at the last record step below count
static const PiTowerRecord &pi_tower_record_before(const std::vector<PiTowerRecord> &records, const PiWide &count)
{
    size_t at = 0u;
    while (((at + 1u) < records.size()) && (pi_tower_compare(records[at + 1u].step, count) < 0))
    {
        at += 1u;
    }
    return records[at];
}

// whether the steps 0 .. count - 1 touch every cell of width cell. The count points cut the circle into count gaps of
// at most three lengths (Sos): point i is followed by i + u where i < count - u, by i - v where i >= v, and by
// i + u - v between, u and v being the lowest and highest standing steps below count. A gap from p holds a whole
// empty cell exactly where (p mod cell) + gap >= 2 cell, and p mod cell is the turn by A mod cell on cell.
int pi_tower_covered(const PiTowerTurn &turn, const PiWide &cell, const PiWide &count)
{
    if (pi_tower_compare(count, pi_tower_power_two(turn.range)) > 0)
    {
        // a record past the range may stand below count. The gaps are not known
        g_pi_tower_records_short = 1;
    }
    const PiTowerRecord &lowest = pi_tower_record_before(turn.lowest, count);
    const PiTowerRecord &highest = pi_tower_record_before(turn.highest, count);
    const PiWide zero = pi_tower_unsigned(0ull);
    const PiWide one = pi_tower_unsigned(1ull);
    const PiWide two_cells = pi_tower_sum(cell, cell);
    const PiWide multiplier = pi_tower_remainder(turn.multiplier, cell);
    const PiWide rising = lowest.place;
    const PiWide falling = pi_tower_difference(turn.modulus, highest.place);
    const PiWide split = pi_tower_difference(count, lowest.step);
    const PiWide from[3] = {zero, highest.step, split};
    const PiWide to[3] = {split, count, highest.step};
    const PiWide gaps[3] = {rising, falling, pi_tower_sum(rising, falling)};
    for (unsigned int kind = 0u; kind < 3u; kind += 1u)
    {
        if ((pi_tower_compare(from[kind], to[kind]) >= 0) || (pi_tower_compare(gaps[kind], cell) <= 0))
        {
            continue;
        }
        if (pi_tower_compare(gaps[kind], two_cells) >= 0)
        {
            return 0;
        }
        if (pi_tower_hit_between(multiplier, cell, from[kind], to[kind], pi_tower_difference(two_cells, gaps[kind]),
                                 pi_tower_difference(cell, one)))
        {
            return 0;
        }
    }
    return 1;
}

void pi_tower_print_decimal(ScripturaLine *line, PiWide value)
{
    const PiWide chunk = pi_tower_unsigned(1000000000000000000ull);
    std::vector<unsigned long long> parts;
    do
    {
        parts.push_back(pi_tower_word(pi_tower_remainder(value, chunk)));
        value = pi_tower_quotient(value, chunk);
    } while (value.sign != 0);
    scriptura_decimal(line, parts.back(), 1u);
    for (size_t at = parts.size() - 1u; at > 0u; at -= 1u)
    {
        scriptura_decimal(line, parts[at - 1u], 18u);
    }
}

// numerator / denominator in exponent notation, four significant digits
void pi_tower_print_exponent(ScripturaLine *line, PiWide numerator, PiWide denominator)
{
    if (numerator.sign == 0)
    {
        scriptura_character(line, '0');
        return;
    }
    const PiWide ten = pi_tower_unsigned(10ull);
    long long exponent = 0ll;
    while (pi_tower_compare(numerator, pi_tower_product(denominator, ten)) >= 0)
    {
        denominator = pi_tower_product(denominator, ten);
        exponent += 1ll;
    }
    while (pi_tower_compare(numerator, denominator) < 0)
    {
        numerator = pi_tower_product(numerator, ten);
        exponent -= 1ll;
    }
    const unsigned long long digits =
        pi_tower_word(pi_tower_quotient(pi_tower_product(numerator, pi_tower_unsigned(1000ull)), denominator));
    scriptura_decimal(line, digits / 1000ull, 1u);
    scriptura_character(line, '.');
    scriptura_decimal(line, digits % 1000ull, 3u);
    scriptura_character(line, 'e');
    scriptura_signed(line, exponent);
}

// pi 2^(precision + PI_TOWER_GUARD) strictly between low and high by Machin's formula, and A = floor(alpha 2^precision)
// where both ends agree on it; 0 where they do not
static int pi_tower_machin(unsigned int precision, PiWide *alpha, PiWide *low, PiWide *high, unsigned long long *terms)
{
    const unsigned int bits = precision + PI_TOWER_GUARD;
    unsigned long long fifth_terms = 0ull;
    unsigned long long far_terms = 0ull;
    const PiWide fifth = pi_tower_arctan(5ull, bits, &fifth_terms);
    const PiWide far = pi_tower_arctan(239ull, bits, &far_terms);
    const PiWide middle = pi_tower_difference(pi_tower_product(fifth, pi_tower_unsigned(16ull)),
                                              pi_tower_product(far, pi_tower_unsigned(4ull)));
    const PiWide spread = pi_tower_unsigned((16ull * (fifth_terms + 1ull)) + (4ull * (far_terms + 1ull)));
    *low = pi_tower_difference(middle, spread);
    *high = pi_tower_sum(middle, spread);
    *terms = fifth_terms + far_terms;
    const PiWide guard = pi_tower_power_two(PI_TOWER_GUARD);
    const PiWide below = pi_tower_quotient(*low, guard);
    const PiWide above = pi_tower_quotient(*high, guard);
    *alpha = pi_tower_difference(below, pi_tower_product(pi_tower_unsigned(3ull), pi_tower_power_two(precision)));
    return pi_tower_compare(below, above) == 0;
}

// 1. pi bracketed: A = floor(alpha 2^precision), and pi 2^(precision + PI_TOWER_GUARD) strictly between low and high
int pi_tower_bracket(SimResults *results, unsigned int precision, PiWide *alpha, PiWide *low, PiWide *high)
{
    const unsigned int bits = precision + PI_TOWER_GUARD;
    unsigned long long terms = 0ull;
    const int agree = pi_tower_machin(precision, alpha, low, high, &terms);
    const unsigned long long leading = pi_tower_word(pi_tower_quotient(*alpha, pi_tower_power_two(precision - 64u)));
    scriptura_text(&results->line, "  pi by Machin's formula at ");
    scriptura_decimal(&results->line, bits, 1u);
    scriptura_text(&results->line, " bits, ");
    scriptura_decimal(&results->line, terms, 1u);
    scriptura_text(&results->line, " terms; after the point it begins 0x");
    for (unsigned int nibble = 16u; nibble > 0u; nibble -= 1u)
    {
        scriptura_character(&results->line, "0123456789ABCDEF"[(leading >> (4u * (nibble - 1u))) & 15ull]);
    }
    scriptura_character(&results->line, '\n');
    sim_check(results, agree,
              "floor(pi 2^P) is one integer at both ends of Machin's bracket, at the turn's precision P");
    sim_check(results, leading == PI_TOWER_PUBLISHED_BITS, "pi's first 64 bits after the point are 0x243F6A8885A308D3");
    return agree;
}

// 2 and 3. the floors: pi's partial quotients and convergents, and the turn's closest returns
void pi_tower_floors(SimResults *results, const PiTowerTurn &turn, std::vector<PiWide> *denominators,
                     std::vector<PiWide> *floors)
{
    const unsigned long long published[PI_TOWER_PUBLISHED_FLOORS] = {7ull, 15ull, 1ull, 292ull, 1ull,  1ull, 1ull,
                                                                     2ull, 1ull,  3ull, 1ull,   14ull, 2ull, 1ull,
                                                                     1ull, 2ull,  2ull, 2ull,   2ull,  1ull, 84ull};
    const PiWide one = pi_tower_unsigned(1ull);
    const std::vector<PiWide> lower = pi_tower_partial_quotients(turn.multiplier, turn.modulus);
    const std::vector<PiWide> upper = pi_tower_partial_quotients(pi_tower_sum(turn.multiplier, one), turn.modulus);
    size_t common = 0u;
    while ((common < lower.size()) && (common < upper.size()) && (pi_tower_compare(lower[common], upper[common]) == 0))
    {
        common += 1u;
    }
    // the last shared quotient can differ between the two expansions of a rational endpoint. It is not certified
    const size_t certified = (common > 0u) ? (common - 1u) : 0u;
    int agree = certified >= PI_TOWER_PUBLISHED_FLOORS;
    for (size_t at = 0u; (at < PI_TOWER_PUBLISHED_FLOORS) && (at < certified); at += 1u)
    {
        agree = agree && (pi_tower_compare(lower[at], pi_tower_unsigned(published[at])) == 0);
    }
    PiWide before = pi_tower_unsigned(0ull);
    PiWide denominator = one;
    denominators->push_back(denominator);
    floors->push_back(pi_tower_unsigned(0ull));
    for (size_t at = 0u; at < certified; at += 1u)
    {
        const PiWide next = pi_tower_sum(pi_tower_product(lower[at], denominator), before);
        before = denominator;
        denominator = next;
        denominators->push_back(denominator);
        floors->push_back(lower[at]);
    }
    scriptura_text(&results->line, "  ");
    scriptura_decimal(&results->line, certified, 1u);
    scriptura_text(&results->line, " floors certified by the bracket: pi = [3; ");
    for (size_t at = 0u; (at < certified) && (at < 40u); at += 1u)
    {
        scriptura_decimal(&results->line, pi_tower_word(lower[at]), 1u);
        scriptura_text(&results->line, (at + 1u < certified) ? ", " : "]\n");
    }
    if (certified > 40u)
    {
        scriptura_text(&results->line, "...]\n");
    }
    sim_check(results, agree,
              "the certified floors begin 7, 15, 1, 292, 1, 1, 1, 2, 1, 3, 1, 14, 2, 1, 1, 2, 2, 2, 2, 1, 84");
    sim_flush(results);

    // the closest returns: records of the distance to the start, by first hits from both sides
    const PiWide bound = pi_tower_power_two(PI_TOWER_RECORD_BITS);
    std::vector<PiWide> returns;
    PiWide step = one;
    for (;;)
    {
        returns.push_back(step);
        const PiWide place = pi_tower_remainder(pi_tower_product(turn.multiplier, step), turn.modulus);
        const PiWide mirror = pi_tower_difference(turn.modulus, place);
        const PiWide distance = (pi_tower_compare(place, mirror) < 0) ? place : mirror;
        if (pi_tower_compare(distance, one) <= 0)
        {
            break;
        }
        PiWide from_below;
        PiWide from_above;
        const int below =
            pi_tower_first_hit(turn.multiplier, turn.modulus, one, pi_tower_difference(distance, one), &from_below);
        const int above = pi_tower_first_hit(turn.multiplier, turn.modulus,
                                             pi_tower_sum(pi_tower_difference(turn.modulus, distance), one),
                                             pi_tower_difference(turn.modulus, one), &from_above);
        if ((below == 0) && (above == 0))
        {
            break;
        }
        step = (below == 0)
                   ? from_above
                   : ((above == 0) ? from_below
                                   : ((pi_tower_compare(from_below, from_above) < 0) ? from_below : from_above));
        if (pi_tower_compare(step, bound) > 0)
        {
            break;
        }
    }
    size_t matched = 0u;
    size_t floors_in_bound = 0u;
    while ((floors_in_bound < denominators->size()) && (pi_tower_compare((*denominators)[floors_in_bound], bound) <= 0))
    {
        floors_in_bound += 1u;
    }
    while ((matched < returns.size()) && (matched < floors_in_bound) &&
           (pi_tower_compare(returns[matched], (*denominators)[matched]) == 0))
    {
        matched += 1u;
    }
    scriptura_text(&results->line, "  floor j, turns on it a_j, the step q_j of its closest return, and how close\n");
    for (size_t at = 0u; at < floors_in_bound; at += 1u)
    {
        const PiWide place = pi_tower_remainder(pi_tower_product(turn.multiplier, (*denominators)[at]), turn.modulus);
        const PiWide mirror = pi_tower_difference(turn.modulus, place);
        scriptura_text(&results->line, "    ");
        scriptura_decimal(&results->line, at, 2u);
        scriptura_text(&results->line, "  a ");
        pi_tower_print_decimal(&results->line, (*floors)[at]);
        scriptura_text(&results->line, "  q ");
        pi_tower_print_decimal(&results->line, (*denominators)[at]);
        scriptura_text(&results->line, "  ||q pi|| ");
        pi_tower_print_exponent(&results->line, (pi_tower_compare(place, mirror) < 0) ? place : mirror, turn.modulus);
        scriptura_character(&results->line, '\n');
        sim_flush(results);
    }
    scriptura_text(&results->line, "  the turn's closest returns to 2^112 steps: ");
    scriptura_decimal(&results->line, returns.size(), 1u);
    scriptura_text(&results->line, "; the floors' q_j to 2^112: ");
    scriptura_decimal(&results->line, floors_in_bound, 1u);
    scriptura_text(&results->line, "; equal in order: ");
    scriptura_decimal(&results->line, matched, 1u);
    scriptura_character(&results->line, '\n');
    sim_check(results, (matched == returns.size()) && (matched == floors_in_bound) && (matched > 40u),
              "the turn's closest returns are exactly the floors' convergent denominators, to 2^112 steps");
    sim_flush(results);
}
