// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// Pi turning at the boundary, and the tower it builds (Doug, 24 September: the turn that gave us tower recursion).
// The boundary is the circle of length 1 and the turn is x -> x + pi, which on the circle is the rotation by
// alpha = pi - 3. The turn never closes, so it never lands where it has been. Its returns near the start are its
// floors: the return map to the arc under a close return is again a rotation, by the Gauss map's angle, and the
// counts of turns on each floor are pi's partial quotients [3; 7, 15, 1, 292, ...] (H. Weyl, 1916; V. T. Sos, 1958,
// the three gap theorem; T. van Ravenstein, "The three gap theorem (Steinhaus conjecture)", J. Austral. Math. Soc. A
// 45, 1988). Cut the boundary into N = 2^k cells: the turn fills every cell at an exact step, and that step and the
// cell it fills are read here from the floors, without walking the turn.
// Everything is exact. pi is bracketed by Machin's formula in integers, and the turn is held as the integer rotation
// y_n = n A mod 2^P, A = floor(alpha 2^P). A first hit, the least n with y_n in a window, is Euclid's descent through
// the floors. Whether the integer turn is the real one, cell for cell, is itself a first hit, and is checked.
// 1. pi is bracketed: floor(pi 2^P) is one integer at both ends of Machin's bracket, and its first 64 bits after the
//    point are the published 0x243F6A8885A308D3.
// 2. The floors: pi's partial quotients, certified by the bracket, begin 7, 15, 1, 292, ... as published.
// 3. The turn's closest returns are the floors: the steps at which the turn comes nearer its start than ever before
//    are exactly the convergents' denominators q_j, every one up to 2^PI_TOWER_RECORD_BITS.
// 4. The integer turn is the real turn: at every resolution no step up to the one searched lands in a cell other
//    than the real one.
// 5. The step that fills the boundary, read from the floors, equals a walk of every step, at 2^1 to 2^PI_TOWER_WALK_MOST
//    cells, and so does the last cell filled.
// 6. At every resolution asked for, the last cell filled is first touched at that step.
// The resolutions come with the request (Doug, 24 September: "you can go to 2^n arbitrarily in the tower it is one
// term"): pi_tower [n] reads 2^n alone, pi_tower [from] [to] reads 2^from to 2^to, and no argument reads 2^1 to 2^100.
// The precision follows the largest, P = 3 n + 64 bits rounded up to a word and at least PI_TOWER_BITS, and a build
// whose exact width cannot hold 3 (P + PI_TOWER_GUARD) + 64 bits refuses it by name (SIM_EXACT_LIMBS sets the width).
// The arc (Doug, 24 September: "if we were on a disk, and pi were on a separate disc balanced by its torsion, that
// would be its planes offset in degrees to our plane"; "this is the arc it follows"). Roll the boundary into a
// cylinder whose cross-section is our disk: the turn is the helix of radius 1 / (2 pi) rising 1 / pi a turn, and it
// pierces our disk at the marks {n pi}. Its bending plane stands at the angle phi = arctan(1 / pi) to our disk, and
// the ratio of its torsion to its curvature is tan phi (Lancret, 1806).
// 7. In Q(pi), where pi is a free variable because it is transcendental (Lindemann, 1882), the helix's Frenet frame
//    taken from its derivatives at the four quarter turns gives curvature 2 pi^3 / (pi^2 + 1), torsion
//    2 pi^2 / (pi^2 + 1), tau / kappa = 1 / pi = tan phi, and a Darboux vector tau T + kappa B along our disk's axis.
// 8. The same numbers from the bracket: kappa, tau and phi in degrees, each printed only where both ends agree.
// The balance and the boundary (Doug, 24 September: "it is present but balanced"; "the UNBALANCING happens at the
// boundary, that is when those forces lose equilibrium"; "one force must win because we cannot divide by zero and the
// boundary is "real" in our information space").
// 9. On the helix the pull points at our axis, so the torque about it is zero, and the angular momentum about it at unit
//    speed is L_z^2 = 1 / (4 (pi^2 + 1)) at all four quarter turns, in Q(pi); L_z from the bracket to 12 places.
// 10. The billiard in the unit square from the corner at slope pi, unfolded: the segment in lattice cell (i, j) carries
//    L = (-1)^(i + j) ((j + 1/2) - pi (i + 1/2)) about the square's centre, with p = (1, pi). L = 0 would need
//    pi = (2j + 1) / (2i + 1), and a corner would need pi (i + 1) whole: each tie is pi rational. Walked from the
//    integer turn over 2^PI_TOWER_BILLIARD_BITS columns, every floor decided with the turn's certainty: no wall hit is
//    a corner, no segment's L is zero, and the walk's record near-corners are exactly the q_j. Measured: how often the
//    lead changes hands, the longest lead, each side's share, and the nearest tie.
// 11. The residue: on every floor with q_j to 2^PI_TOWER_RESIDUE_BITS, pi's first q_j steps have the whole parts of the
//    permutation n -> n p_j mod q_j, and at step q_j pi stands delta_j = q_j pi - (3 q_j + p_j) off the whole.
// 12. The golden helix: the residues flip sign every floor, q_j >= F_(j+1), |delta_j| < 1 / q_(j+1), and the shrink
//    |delta_j| / |delta_(j-1)| is above 1/2 exactly where a_(j+1) = 1. Measured: each shrink against the golden 1/phi,
//    and the growth a floor q_J^(1/J) against phi.
// The tower's deepest turns, on the engine (Doug, 24 September: "I don't want anything less than 2^googol"; "represent
// the base and its operation as separate parts"). The turn at depth n is bit n of alpha, pi's fraction, and the BBP
// formula (D. H. Bailey, P. B. Borwein and S. Plouffe, Math. Comp. 66, 1997) reads it where it stands, without the bits
// before it: {16^d pi} = {4 S_1 - 2 S_4 - S_5 - S_6}, S_j = sum over i of 16^(d - i) / (8 i + j). Each term is a lane
// of the engine's record machine, its power shrunk mod 8 i + j at every square; keymath sizes every register, the
// scheduler lays them, and tessera admits the job.
// 13. On the engine, pi's first 64 bits after the point are 0x243F6A8885A308D3, and its hex digits at Bailey's
//     published positions are his.
// 14. The engine's cell at the deepest resolution asked for, its low 64 bits, is the exact turn's.
// A resolution past 2^20, n given whole or as base^exponent (10^100 for a googol), is held as (2, n): its precision
// and widths are printed exact, and the engine sums the depth-n terms sweep by sweep, printing the terms done and its
// rate. Its digits are printed only once every term is summed.

#include "sim.h"

#include "cycle.h"
#include "key_schedule.h"
#include "keymath.h"

#include <chrono>
#include <csignal>
#include <string>
#include <vector>

// the walks' turn's precision, in bits after the point, and the least precision of the searched turn
#define PI_TOWER_BITS 384u

// the guard bits Machin's bracket is taken at past the turn's precision
#define PI_TOWER_GUARD 32u

// the resolutions read when the request names none
#define PI_TOWER_RESOLUTION_FIRST 1u

#define PI_TOWER_RESOLUTION_LAST 100u

#define PI_TOWER_WALK_MOST 24u

// the floor table and the closest-return check reach 2^PI_TOWER_RECORD_BITS steps
#define PI_TOWER_RECORD_BITS 112u

// the searched turn's records reach PI_TOWER_RECORD_MARGIN bits past the largest resolution
#define PI_TOWER_RECORD_MARGIN 12u

// the residue check walks every floor whose q_j is at most 2^PI_TOWER_RESIDUE_BITS
#define PI_TOWER_RESIDUE_BITS 21u

#define PI_TOWER_WORDS (PI_TOWER_BITS / 64u)

// the first 64 bits of pi after the point
#define PI_TOWER_PUBLISHED_BITS 0x243F6A8885A308D3ull

#define PI_TOWER_PUBLISHED_FLOORS 21u

// the billiard is walked over 2^PI_TOWER_BILLIARD_BITS columns of its unfolded lattice
#define PI_TOWER_BILLIARD_BITS 24u

// the bits after the point the engine's sum holds past its error, and the guard past them that keeps a carry from
// leaving them undecided
#define PI_TOWER_BBP_CERTIFIED 96u

#define PI_TOWER_BBP_GUARD 16u

// a segment takes this many hex digits from each window, the least every window certifies
#define PI_TOWER_SEGMENT_STEP (PI_TOWER_BBP_CERTIFIED / 4u)

// the hex digits a segment reads when the request names none, and the most it may name
#define PI_TOWER_SEGMENT_DIGITS 1000u

#define PI_TOWER_SEGMENT_MOST 65536u

// the deepest resolution the exact turn is held at; past it a resolution is read on the engine alone
#define PI_TOWER_EXACT_MOST (1ull << 20u)

static int s_pi_tower_refused = 0;

// set where a search asks for a record past the reach the records were held to
static int s_pi_tower_records_short = 0;

typedef AnchorExactInteger PiWide;

// one level of the descent: the rotation a on m, and the window's low end
typedef struct
{
    PiWide multiplier;
    PiWide modulus;
    PiWide low;
} PiTowerLevel;

// a step at which the turn sets a record, and where it stands then
typedef struct
{
    PiWide step;
    PiWide place;
} PiTowerRecord;

// the searched turn: A = floor(alpha 2^precision) on 2^precision, its records to 2^reach steps
typedef struct
{
    PiWide multiplier;
    PiWide modulus;
    unsigned int precision;
    unsigned int reach;
    std::vector<PiTowerRecord> lowest;
    std::vector<PiTowerRecord> highest;
} PiTowerTurn;

static void pi_tower_took(AnchorExactStatus status)
{
    if (status != ANCHOR_EXACT_OK)
    {
        s_pi_tower_refused = 1;
    }
}

static PiWide pi_tower_whole(unsigned long long whole)
{
    PiWide value;
    sim_exact_whole(&value, whole);
    return value;
}

static PiWide pi_tower_power_two(unsigned int bits)
{
    PiWide value;
    anchor_exact_zero(&value);
    value.limb[bits / 32u] = 1u << (bits % 32u);
    value.sign = 1;
    return value;
}

static PiWide pi_tower_sum(const PiWide &left, const PiWide &right)
{
    PiWide value;
    anchor_exact_zero(&value);
    pi_tower_took(anchor_exact_add(&left, &right, &value));
    return value;
}

static PiWide pi_tower_difference(const PiWide &left, const PiWide &right)
{
    PiWide value;
    anchor_exact_zero(&value);
    pi_tower_took(anchor_exact_subtract(&left, &right, &value));
    return value;
}

static PiWide pi_tower_product(const PiWide &left, const PiWide &right)
{
    PiWide value;
    anchor_exact_zero(&value);
    pi_tower_took(anchor_exact_multiply(&left, &right, &value));
    return value;
}

// the floor of a quotient of two non-negative integers
static PiWide pi_tower_quotient(const PiWide &numerator, const PiWide &divisor)
{
    PiWide quotient;
    PiWide remainder;
    anchor_exact_zero(&quotient);
    anchor_exact_zero(&remainder);
    pi_tower_took(anchor_exact_divide(&numerator, &divisor, &quotient, &remainder));
    return quotient;
}

static PiWide pi_tower_remainder(const PiWide &numerator, const PiWide &divisor)
{
    PiWide quotient;
    PiWide remainder;
    anchor_exact_zero(&quotient);
    anchor_exact_zero(&remainder);
    pi_tower_took(anchor_exact_divide(&numerator, &divisor, &quotient, &remainder));
    return remainder;
}

static int pi_tower_compare(const PiWide &left, const PiWide &right)
{
    return anchor_exact_compare(&left, &right);
}

// the low 64 bits
static unsigned long long pi_tower_word(const PiWide &value)
{
    return ((unsigned long long)value.limb[1] << 32u) | (unsigned long long)value.limb[0];
}

// the least x >= 0 with low <= (multiplier . x mod modulus) <= high, for low <= high < modulus; 0 where there is
// none. Where no multiple of the multiplier lands in the window, x wraps y times, and y is the least hit of the window
// reflected into the rotation one floor down, modulus mod multiplier on multiplier: Euclid's descent.
static int pi_tower_first_hit(PiWide multiplier, PiWide modulus, PiWide low, PiWide high, PiWide *step)
{
    const PiWide one = pi_tower_whole(1ull);
    std::vector<PiTowerLevel> levels;
    PiWide found;
    for (;;)
    {
        if (low.sign == 0)
        {
            found = pi_tower_whole(0ull);
            break;
        }
        if (multiplier.sign == 0)
        {
            return 0;
        }
        const PiWide least = pi_tower_quotient(pi_tower_sum(low, pi_tower_difference(multiplier, one)), multiplier);
        if (pi_tower_compare(pi_tower_product(multiplier, least), high) <= 0)
        {
            found = least;
            break;
        }
        PiTowerLevel level;
        level.multiplier = multiplier;
        level.modulus = modulus;
        level.low = low;
        levels.push_back(level);
        const PiWide next_multiplier = pi_tower_remainder(modulus, multiplier);
        const PiWide next_low = pi_tower_difference(multiplier, pi_tower_remainder(high, multiplier));
        const PiWide next_high = pi_tower_difference(multiplier, pi_tower_remainder(low, multiplier));
        modulus = multiplier;
        multiplier = next_multiplier;
        low = next_low;
        high = next_high;
    }
    for (size_t at = levels.size(); at > 0u; at -= 1u)
    {
        const PiTowerLevel &level = levels[at - 1u];
        const PiWide reach = pi_tower_sum(level.low, pi_tower_product(level.modulus, found));
        found = pi_tower_quotient(pi_tower_sum(reach, pi_tower_difference(level.multiplier, one)), level.multiplier);
    }
    *step = found;
    return 1;
}

// the least x >= from with low <= (multiplier . x mod modulus) <= high; 0 where there is none
static int pi_tower_first_hit_from(const PiWide &multiplier, const PiWide &modulus, const PiWide &from,
                                   const PiWide &low, const PiWide &high, PiWide *step)
{
    const PiWide start = pi_tower_remainder(pi_tower_product(multiplier, from), modulus);
    const PiWide shifted_low = pi_tower_remainder(pi_tower_difference(pi_tower_sum(low, modulus), start), modulus);
    const PiWide shifted_high = pi_tower_remainder(pi_tower_difference(pi_tower_sum(high, modulus), start), modulus);
    if (pi_tower_compare(shifted_low, shifted_high) > 0)
    {
        // the window wraps past 0, and x = from stands in it
        *step = from;
        return 1;
    }
    PiWide later;
    if (pi_tower_first_hit(multiplier, modulus, shifted_low, shifted_high, &later) == 0)
    {
        return 0;
    }
    *step = pi_tower_sum(from, later);
    return 1;
}

// whether some x in [from, to) has low <= (multiplier . x mod modulus) <= high
static int pi_tower_hit_between(const PiWide &multiplier, const PiWide &modulus, const PiWide &from, const PiWide &to,
                                const PiWide &low, const PiWide &high)
{
    if (pi_tower_compare(from, to) >= 0)
    {
        return 0;
    }
    const PiWide start = pi_tower_remainder(pi_tower_product(multiplier, from), modulus);
    const PiWide shifted_low = pi_tower_remainder(pi_tower_difference(pi_tower_sum(low, modulus), start), modulus);
    const PiWide shifted_high = pi_tower_remainder(pi_tower_difference(pi_tower_sum(high, modulus), start), modulus);
    if (pi_tower_compare(shifted_low, shifted_high) > 0)
    {
        // the window wraps past 0, and x = from stands in it
        return 1;
    }
    PiWide step;
    if (pi_tower_first_hit(multiplier, modulus, shifted_low, shifted_high, &step) == 0)
    {
        return 0;
    }
    return pi_tower_compare(pi_tower_sum(from, step), to) < 0;
}

// 2^bits . arctan(1 / x) within terms + 1: the alternating series, each term floored
static PiWide pi_tower_arctan(unsigned long long x, unsigned int bits, unsigned long long *terms)
{
    const PiWide square = pi_tower_whole(x * x);
    PiWide power = pi_tower_quotient(pi_tower_power_two(bits), pi_tower_whole(x));
    PiWide total = pi_tower_whole(0ull);
    unsigned long long index = 0ull;
    *terms = 0ull;
    while (power.sign != 0)
    {
        const PiWide term = pi_tower_quotient(power, pi_tower_whole((2ull * index) + 1ull));
        total = ((index & 1ull) == 0ull) ? pi_tower_sum(total, term) : pi_tower_difference(total, term);
        *terms += 1ull;
        power = pi_tower_quotient(power, square);
        index += 1ull;
    }
    return total;
}

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

// the steps at which the turn stands lower (or higher) than at every step since 1, to 2^turn.reach
static std::vector<PiTowerRecord> pi_tower_records(const PiTowerTurn &turn, int lowest)
{
    const PiWide one = pi_tower_whole(1ull);
    const PiWide bound = pi_tower_power_two(turn.reach);
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
            found = (pi_tower_compare(place, one) > 0)
                 && pi_tower_first_hit(turn.multiplier, turn.modulus, one, pi_tower_difference(place, one), &step);
        }
        else
        {
            const PiWide top = pi_tower_difference(turn.modulus, one);
            found = (pi_tower_compare(place, top) < 0)
                 && pi_tower_first_hit(turn.multiplier, turn.modulus, pi_tower_sum(place, one), top, &step);
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
static int pi_tower_covered(const PiTowerTurn &turn, const PiWide &cell, const PiWide &count)
{
    if (pi_tower_compare(count, pi_tower_power_two(turn.reach)) > 0)
    {
        // a record past the reach may stand below count, so the gaps are not known
        s_pi_tower_records_short = 1;
    }
    const PiTowerRecord &lowest = pi_tower_record_before(turn.lowest, count);
    const PiTowerRecord &highest = pi_tower_record_before(turn.highest, count);
    const PiWide zero = pi_tower_whole(0ull);
    const PiWide one = pi_tower_whole(1ull);
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

static void pi_tower_print_decimal(ScripturaLine *line, PiWide value)
{
    const PiWide chunk = pi_tower_whole(1000000000000000000ull);
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
static void pi_tower_print_exponent(ScripturaLine *line, PiWide numerator, PiWide denominator)
{
    if (numerator.sign == 0)
    {
        scriptura_character(line, '0');
        return;
    }
    const PiWide ten = pi_tower_whole(10ull);
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
    const unsigned long long digits = pi_tower_word(pi_tower_quotient(pi_tower_product(numerator, pi_tower_whole(1000ull)), denominator));
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
    const PiWide middle = pi_tower_difference(pi_tower_product(fifth, pi_tower_whole(16ull)),
                                              pi_tower_product(far, pi_tower_whole(4ull)));
    const PiWide spread = pi_tower_whole((16ull * (fifth_terms + 1ull)) + (4ull * (far_terms + 1ull)));
    *low = pi_tower_difference(middle, spread);
    *high = pi_tower_sum(middle, spread);
    *terms = fifth_terms + far_terms;
    const PiWide guard = pi_tower_power_two(PI_TOWER_GUARD);
    const PiWide below = pi_tower_quotient(*low, guard);
    const PiWide above = pi_tower_quotient(*high, guard);
    *alpha = pi_tower_difference(below, pi_tower_product(pi_tower_whole(3ull), pi_tower_power_two(precision)));
    return pi_tower_compare(below, above) == 0;
}

// 1. pi bracketed: A = floor(alpha 2^precision), and pi 2^(precision + PI_TOWER_GUARD) strictly between low and high
static int pi_tower_bracket(SimTally *tally, unsigned int precision, PiWide *alpha, PiWide *low, PiWide *high)
{
    const unsigned int bits = precision + PI_TOWER_GUARD;
    unsigned long long terms = 0ull;
    const int agree = pi_tower_machin(precision, alpha, low, high, &terms);
    const unsigned long long leading = pi_tower_word(pi_tower_quotient(*alpha, pi_tower_power_two(precision - 64u)));
    scriptura_text(&tally->line, "  pi by Machin's formula at ");
    scriptura_decimal(&tally->line, bits, 1u);
    scriptura_text(&tally->line, " bits, ");
    scriptura_decimal(&tally->line, terms, 1u);
    scriptura_text(&tally->line, " terms; after the point it begins 0x");
    for (unsigned int nibble = 16u; nibble > 0u; nibble -= 1u)
    {
        scriptura_character(&tally->line, "0123456789ABCDEF"[(leading >> (4u * (nibble - 1u))) & 15ull]);
    }
    scriptura_character(&tally->line, '\n');
    sim_check(tally, agree, "floor(pi 2^P) is one integer at both ends of Machin's bracket, at the turn's precision P");
    sim_check(tally, leading == PI_TOWER_PUBLISHED_BITS, "pi's first 64 bits after the point are 0x243F6A8885A308D3");
    return agree;
}

// 2 and 3. the floors: pi's partial quotients and convergents, and the turn's closest returns
static void pi_tower_floors(SimTally *tally, const PiTowerTurn &turn, std::vector<PiWide> *denominators,
                            std::vector<PiWide> *floors)
{
    const unsigned long long published[PI_TOWER_PUBLISHED_FLOORS] = {7ull, 15ull, 1ull, 292ull, 1ull, 1ull, 1ull,
                                                                     2ull, 1ull, 3ull, 1ull, 14ull, 2ull, 1ull,
                                                                     1ull, 2ull, 2ull, 2ull, 2ull, 1ull, 84ull};
    const PiWide one = pi_tower_whole(1ull);
    const std::vector<PiWide> lower = pi_tower_partial_quotients(turn.multiplier, turn.modulus);
    const std::vector<PiWide> upper = pi_tower_partial_quotients(pi_tower_sum(turn.multiplier, one), turn.modulus);
    size_t common = 0u;
    while ((common < lower.size()) && (common < upper.size()) && (pi_tower_compare(lower[common], upper[common]) == 0))
    {
        common += 1u;
    }
    // the last shared quotient can differ between the two expansions of a rational endpoint, so it is not certified
    const size_t certified = (common > 0u) ? (common - 1u) : 0u;
    int agree = certified >= PI_TOWER_PUBLISHED_FLOORS;
    for (size_t at = 0u; (at < PI_TOWER_PUBLISHED_FLOORS) && (at < certified); at += 1u)
    {
        agree = agree && (pi_tower_compare(lower[at], pi_tower_whole(published[at])) == 0);
    }
    PiWide before = pi_tower_whole(0ull);
    PiWide denominator = one;
    denominators->push_back(denominator);
    floors->push_back(pi_tower_whole(0ull));
    for (size_t at = 0u; at < certified; at += 1u)
    {
        const PiWide next = pi_tower_sum(pi_tower_product(lower[at], denominator), before);
        before = denominator;
        denominator = next;
        denominators->push_back(denominator);
        floors->push_back(lower[at]);
    }
    scriptura_text(&tally->line, "  ");
    scriptura_decimal(&tally->line, certified, 1u);
    scriptura_text(&tally->line, " floors certified by the bracket: pi = [3; ");
    for (size_t at = 0u; (at < certified) && (at < 40u); at += 1u)
    {
        scriptura_decimal(&tally->line, pi_tower_word(lower[at]), 1u);
        scriptura_text(&tally->line, (at + 1u < certified) ? ", " : "]\n");
    }
    if (certified > 40u)
    {
        scriptura_text(&tally->line, "...]\n");
    }
    sim_check(tally, agree, "the certified floors begin 7, 15, 1, 292, 1, 1, 1, 2, 1, 3, 1, 14, 2, 1, 1, 2, 2, 2, 2, 1, 84");
    sim_flush(tally);

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
        const int below = pi_tower_first_hit(turn.multiplier, turn.modulus, one, pi_tower_difference(distance, one),
                                             &from_below);
        const int above = pi_tower_first_hit(turn.multiplier, turn.modulus,
                                             pi_tower_sum(pi_tower_difference(turn.modulus, distance), one),
                                             pi_tower_difference(turn.modulus, one), &from_above);
        if ((below == 0) && (above == 0))
        {
            break;
        }
        step = (below == 0) ? from_above
             : ((above == 0) ? from_below : ((pi_tower_compare(from_below, from_above) < 0) ? from_below : from_above));
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
    while ((matched < returns.size()) && (matched < floors_in_bound)
           && (pi_tower_compare(returns[matched], (*denominators)[matched]) == 0))
    {
        matched += 1u;
    }
    scriptura_text(&tally->line, "  floor j, turns on it a_j, the step q_j of its closest return, and how close\n");
    for (size_t at = 0u; at < floors_in_bound; at += 1u)
    {
        const PiWide place = pi_tower_remainder(pi_tower_product(turn.multiplier, (*denominators)[at]), turn.modulus);
        const PiWide mirror = pi_tower_difference(turn.modulus, place);
        scriptura_text(&tally->line, "    ");
        scriptura_decimal(&tally->line, at, 2u);
        scriptura_text(&tally->line, "  a ");
        pi_tower_print_decimal(&tally->line, (*floors)[at]);
        scriptura_text(&tally->line, "  q ");
        pi_tower_print_decimal(&tally->line, (*denominators)[at]);
        scriptura_text(&tally->line, "  ||q pi|| ");
        pi_tower_print_exponent(&tally->line, (pi_tower_compare(place, mirror) < 0) ? place : mirror, turn.modulus);
        scriptura_character(&tally->line, '\n');
        sim_flush(tally);
    }
    scriptura_text(&tally->line, "  the turn's closest returns to 2^112 steps: ");
    scriptura_decimal(&tally->line, returns.size(), 1u);
    scriptura_text(&tally->line, "; the floors' q_j to 2^112: ");
    scriptura_decimal(&tally->line, floors_in_bound, 1u);
    scriptura_text(&tally->line, "; equal in order: ");
    scriptura_decimal(&tally->line, matched, 1u);
    scriptura_character(&tally->line, '\n');
    sim_check(tally, (matched == returns.size()) && (matched == floors_in_bound) && (matched > 40u),
              "the turn's closest returns are exactly the floors' convergent denominators, to 2^112 steps");
    sim_flush(tally);
}

// the step at which the direct walk fills every one of 2^bits cells, the cell it fills, the longest stall, the step
// at which every cell has been etched a second time, the first step after the fill that etches cell 0, and the first
// step after that one that etches the fill's last cell
static unsigned long long pi_tower_walk(const PiWide &alpha, unsigned int bits, unsigned long long *last,
                                        unsigned long long *stall, unsigned long long *again, unsigned long long *home,
                                        unsigned long long *closing)
{
    unsigned long long increment[PI_TOWER_WORDS];
    unsigned long long place[PI_TOWER_WORDS];
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        increment[word] = ((unsigned long long)alpha.limb[(2u * word) + 1u] << 32u) | (unsigned long long)alpha.limb[2u * word];
        place[word] = 0ull;
    }
    const unsigned long long cells = 1ull << bits;
    std::vector<unsigned char> seen(cells, 0u);
    seen[0] = 1u;
    unsigned long long filled = 1ull;
    unsigned long long twice = 0ull;
    unsigned long long step = 0ull;
    unsigned long long fill = 0ull;
    unsigned long long since = 0ull;
    *stall = 0ull;
    while ((twice < cells) || (*home == 0ull) || (*closing == 0ull))
    {
        unsigned long long carry = 0ull;
        for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
        {
            const unsigned long long added = place[word] + increment[word];
            const unsigned long long total = added + carry;
            carry = ((added < place[word]) || (total < added)) ? 1ull : 0ull;
            place[word] = total;
        }
        step += 1ull;
        since += 1ull;
        const unsigned long long cell = place[PI_TOWER_WORDS - 1u] >> (64u - bits);
        if ((seen[cell] == 0u) && (filled < cells))
        {
            filled += 1ull;
            *stall = (since > *stall) ? since : *stall;
            since = 0ull;
            *last = cell;
            fill = step;
        }
        if (seen[cell] == 1u)
        {
            twice += 1ull;
        }
        if (seen[cell] < 2u)
        {
            seen[cell] += 1u;
        }
        if ((twice == cells) && (*again == 0ull))
        {
            *again = step;
        }
        if ((*home != 0ull) && (step > *home) && (cell == *last) && (*closing == 0ull))
        {
            *closing = step;
        }
        if ((filled == cells) && (step > fill) && (cell == 0ull) && (*home == 0ull))
        {
            *home = step;
        }
    }
    return fill;
}

// a polynomial in pi with integer coefficients, the coefficient of pi^i at i, with no zero at the top
typedef std::vector<PiWide> PiTowerPolynomial;

// a rational function of pi; pi is transcendental, so two are equal exactly where their cross products are equal as
// polynomials
typedef struct
{
    PiTowerPolynomial numerator;
    PiTowerPolynomial denominator;
} PiTowerFraction;

typedef struct
{
    PiTowerFraction axis[3];
} PiTowerVector;

static void pi_tower_polynomial_trim(PiTowerPolynomial *polynomial)
{
    while (!polynomial->empty() && (polynomial->back().sign == 0))
    {
        polynomial->pop_back();
    }
}

static PiTowerPolynomial pi_tower_polynomial_sum(const PiTowerPolynomial &left, const PiTowerPolynomial &right,
                                                 int subtract)
{
    PiTowerPolynomial total((left.size() > right.size()) ? left.size() : right.size(), pi_tower_whole(0ull));
    for (size_t at = 0u; at < total.size(); at += 1u)
    {
        if (at < left.size())
        {
            total[at] = left[at];
        }
        if (at < right.size())
        {
            total[at] = (subtract != 0) ? pi_tower_difference(total[at], right[at]) : pi_tower_sum(total[at], right[at]);
        }
    }
    pi_tower_polynomial_trim(&total);
    return total;
}

static PiTowerPolynomial pi_tower_polynomial_product(const PiTowerPolynomial &left, const PiTowerPolynomial &right)
{
    if (left.empty() || right.empty())
    {
        return PiTowerPolynomial();
    }
    PiTowerPolynomial total((left.size() + right.size()) - 1u, pi_tower_whole(0ull));
    for (size_t one = 0u; one < left.size(); one += 1u)
    {
        for (size_t other = 0u; other < right.size(); other += 1u)
        {
            total[one + other] = pi_tower_sum(total[one + other], pi_tower_product(left[one], right[other]));
        }
    }
    pi_tower_polynomial_trim(&total);
    return total;
}

// coefficient . pi^power
static PiTowerPolynomial pi_tower_monomial(long long coefficient, unsigned int power)
{
    PiTowerPolynomial polynomial(power + 1u, pi_tower_whole(0ull));
    sim_exact_signed(&polynomial[power], coefficient);
    pi_tower_polynomial_trim(&polynomial);
    return polynomial;
}

static PiTowerFraction pi_tower_fraction(const PiTowerPolynomial &numerator, const PiTowerPolynomial &denominator)
{
    PiTowerFraction fraction;
    fraction.numerator = numerator;
    fraction.denominator = denominator;
    return fraction;
}

static PiTowerFraction pi_tower_fraction_sum(const PiTowerFraction &left, const PiTowerFraction &right, int subtract)
{
    return pi_tower_fraction(pi_tower_polynomial_sum(pi_tower_polynomial_product(left.numerator, right.denominator),
                                                     pi_tower_polynomial_product(right.numerator, left.denominator),
                                                     subtract),
                             pi_tower_polynomial_product(left.denominator, right.denominator));
}

static PiTowerFraction pi_tower_fraction_product(const PiTowerFraction &left, const PiTowerFraction &right)
{
    return pi_tower_fraction(pi_tower_polynomial_product(left.numerator, right.numerator),
                             pi_tower_polynomial_product(left.denominator, right.denominator));
}

static PiTowerFraction pi_tower_fraction_quotient(const PiTowerFraction &left, const PiTowerFraction &right)
{
    return pi_tower_fraction(pi_tower_polynomial_product(left.numerator, right.denominator),
                             pi_tower_polynomial_product(left.denominator, right.numerator));
}

static int pi_tower_fraction_zero(const PiTowerFraction &fraction)
{
    return fraction.numerator.empty();
}

static int pi_tower_fraction_equal(const PiTowerFraction &left, const PiTowerFraction &right)
{
    return pi_tower_polynomial_sum(pi_tower_polynomial_product(left.numerator, right.denominator),
                                   pi_tower_polynomial_product(right.numerator, left.denominator), 1)
        .empty();
}

static PiTowerFraction pi_tower_vector_dot(const PiTowerVector &left, const PiTowerVector &right)
{
    PiTowerFraction total = pi_tower_fraction_product(left.axis[0], right.axis[0]);
    total = pi_tower_fraction_sum(total, pi_tower_fraction_product(left.axis[1], right.axis[1]), 0);
    return pi_tower_fraction_sum(total, pi_tower_fraction_product(left.axis[2], right.axis[2]), 0);
}

static PiTowerVector pi_tower_vector_cross(const PiTowerVector &left, const PiTowerVector &right)
{
    PiTowerVector cross;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        const unsigned int next = (axis + 1u) % 3u;
        const unsigned int after = (axis + 2u) % 3u;
        cross.axis[axis] = pi_tower_fraction_sum(pi_tower_fraction_product(left.axis[next], right.axis[after]),
                                                 pi_tower_fraction_product(left.axis[after], right.axis[next]), 1);
    }
    return cross;
}

// the k-th derivative of the helix (a cos s, a sin s, b s) at the quarter turn s = quarter . pi / 2, where every
// derivative of the cosine and the sine is 1, 0 or -1
static PiTowerVector pi_tower_helix_derivative(const PiTowerFraction &radius, const PiTowerFraction &rise,
                                               unsigned int quarter, unsigned int order)
{
    const long long cosine[4] = {1ll, 0ll, -1ll, 0ll};
    const long long sine[4] = {0ll, 1ll, 0ll, -1ll};
    const PiTowerPolynomial one = pi_tower_monomial(1ll, 0u);
    const unsigned int turn = (quarter + order) % 4u;
    PiTowerVector derivative;
    derivative.axis[0] = pi_tower_fraction_product(radius, pi_tower_fraction(pi_tower_monomial(cosine[turn], 0u), one));
    derivative.axis[1] = pi_tower_fraction_product(radius, pi_tower_fraction(pi_tower_monomial(sine[turn], 0u), one));
    derivative.axis[2] = (order == 1u) ? rise : pi_tower_fraction(PiTowerPolynomial(), one);
    return derivative;
}

// value . 10^places as a whole number and its places
static void pi_tower_print_places(ScripturaLine *line, const PiWide &scaled, unsigned int places)
{
    PiWide unit = pi_tower_whole(1ull);
    for (unsigned int place = 0u; place < places; place += 1u)
    {
        unit = pi_tower_product(unit, pi_tower_whole(10ull));
    }
    pi_tower_print_decimal(line, pi_tower_quotient(scaled, unit));
    scriptura_character(line, '.');
    scriptura_decimal(line, pi_tower_word(pi_tower_remainder(scaled, unit)), places);
}

// 2^bits . arctan(scaled / 2^bits) within 3 terms + 2, for scaled / 2^bits below 1 / 2: each power floored, its error
// held below 1 / (1 - x^2) < 1.34, each term's below 2.34, and the tail below the first term dropped
static PiWide pi_tower_arctan_fixed(const PiWide &scaled, unsigned int bits, unsigned long long *terms)
{
    const PiWide square = pi_tower_product(scaled, scaled);
    const PiWide square_unit = pi_tower_power_two(2u * bits);
    PiWide power = scaled;
    PiWide total = pi_tower_whole(0ull);
    unsigned long long index = 0ull;
    *terms = 0ull;
    while (power.sign != 0)
    {
        const PiWide term = pi_tower_quotient(power, pi_tower_whole((2ull * index) + 1ull));
        total = ((index & 1ull) == 0ull) ? pi_tower_sum(total, term) : pi_tower_difference(total, term);
        *terms += 1ull;
        power = pi_tower_quotient(pi_tower_product(power, square), square_unit);
        index += 1ull;
    }
    return total;
}

// the floor of the square root of a non-negative integer, by Newton's step from above
static PiWide pi_tower_root(const PiWide &value)
{
    if (value.sign == 0)
    {
        return value;
    }
    const PiWide two = pi_tower_whole(2ull);
    PiWide guess = value;
    for (;;)
    {
        const PiWide next = pi_tower_quotient(pi_tower_sum(guess, pi_tower_quotient(value, guess)), two);
        if (pi_tower_compare(next, guess) >= 0)
        {
            return guess;
        }
        guess = next;
    }
}

// 7, 8 and 9. the arc: the helix on the cylinder over our disk, in Q(pi) and from the bracket
static void pi_tower_arc(SimTally *tally, const PiWide &low, const PiWide &high, unsigned int bits)
{
    const PiTowerPolynomial one = pi_tower_monomial(1ll, 0u);
    const PiTowerPolynomial square_and_one = pi_tower_polynomial_sum(pi_tower_monomial(1ll, 2u), one, 0);
    // circumference 1 around our disk, and 1 / pi along the axis for each turn: a = 1 / (2 pi), b = 1 / (2 pi^2)
    const PiTowerFraction radius = pi_tower_fraction(one, pi_tower_monomial(2ll, 1u));
    const PiTowerFraction rise = pi_tower_fraction(one, pi_tower_monomial(2ll, 2u));
    const PiTowerFraction curvature_squared = pi_tower_fraction(pi_tower_monomial(4ll, 6u),
                                                                pi_tower_polynomial_product(square_and_one, square_and_one));
    const PiTowerFraction torsion_expected = pi_tower_fraction(pi_tower_monomial(2ll, 2u), square_and_one);
    const PiTowerFraction inverse_square = pi_tower_fraction(one, pi_tower_monomial(1ll, 2u));
    const PiTowerFraction momentum_expected = pi_tower_fraction(
        one, pi_tower_polynomial_sum(pi_tower_monomial(4ll, 2u), pi_tower_monomial(4ll, 0u), 0));
    int bending = 1;
    int twisting = 1;
    int balanced = 1;
    int tilted = 1;
    int axial = 1;
    int torque_free = 1;
    int momentum_held = 1;
    for (unsigned int quarter = 0u; quarter < 4u; quarter += 1u)
    {
        // order 0 is the place; only its two coordinates across our disk are read, and those are exact
        const PiTowerVector place = pi_tower_helix_derivative(radius, rise, quarter, 0u);
        const PiTowerVector first = pi_tower_helix_derivative(radius, rise, quarter, 1u);
        const PiTowerVector second = pi_tower_helix_derivative(radius, rise, quarter, 2u);
        const PiTowerVector third = pi_tower_helix_derivative(radius, rise, quarter, 3u);
        const PiTowerVector cross = pi_tower_vector_cross(first, second);
        const PiTowerFraction speed_squared = pi_tower_vector_dot(first, first);
        const PiTowerFraction cross_squared = pi_tower_vector_dot(cross, cross);
        // kappa^2 = |g' x g''|^2 / |g'|^6, tau = det(g', g'', g''') / |g' x g''|^2
        const PiTowerFraction kappa_squared = pi_tower_fraction_quotient(
            cross_squared, pi_tower_fraction_product(speed_squared, pi_tower_fraction_product(speed_squared, speed_squared)));
        const PiTowerFraction torsion = pi_tower_fraction_quotient(
            pi_tower_vector_dot(first, pi_tower_vector_cross(second, third)), cross_squared);
        const PiTowerFraction torsion_squared = pi_tower_fraction_product(torsion, torsion);
        bending = bending && pi_tower_fraction_equal(kappa_squared, curvature_squared);
        twisting = twisting && pi_tower_fraction_equal(torsion, torsion_expected);
        balanced = balanced && pi_tower_fraction_equal(pi_tower_fraction_quotient(torsion_squared, kappa_squared), inverse_square);
        // the tangent's rise over its run around the disk, squared: tan^2 of the tilt
        const PiTowerFraction around = pi_tower_fraction_sum(pi_tower_fraction_product(first.axis[0], first.axis[0]),
                                                             pi_tower_fraction_product(first.axis[1], first.axis[1]), 0);
        const PiTowerFraction tilt_squared = pi_tower_fraction_quotient(
            pi_tower_fraction_product(first.axis[2], first.axis[2]), around);
        tilted = tilted && pi_tower_fraction_equal(tilt_squared, inverse_square)
              && pi_tower_fraction_equal(tilt_squared, pi_tower_fraction_quotient(torsion_squared, kappa_squared));
        // |g'|^3 (tau T + kappa B) = tau |g'|^2 g' + g' x g''
        const PiTowerFraction scale = pi_tower_fraction_product(torsion, speed_squared);
        PiTowerVector darboux;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            darboux.axis[axis] = pi_tower_fraction_sum(pi_tower_fraction_product(scale, first.axis[axis]), cross.axis[axis], 0);
        }
        axial = axial && pi_tower_fraction_zero(darboux.axis[0]) && pi_tower_fraction_zero(darboux.axis[1])
             && (pi_tower_fraction_zero(darboux.axis[2]) == 0);
        // about our axis: the torque's share is x y'' - y x'', the momentum's x y' - y x', at unit speed over |g'|
        const PiTowerFraction torque = pi_tower_fraction_sum(pi_tower_fraction_product(place.axis[0], second.axis[1]),
                                                             pi_tower_fraction_product(place.axis[1], second.axis[0]), 1);
        const PiTowerFraction momentum = pi_tower_fraction_sum(pi_tower_fraction_product(place.axis[0], first.axis[1]),
                                                               pi_tower_fraction_product(place.axis[1], first.axis[0]), 1);
        torque_free = torque_free && pi_tower_fraction_zero(torque);
        momentum_held = momentum_held
                     && pi_tower_fraction_equal(pi_tower_fraction_quotient(pi_tower_fraction_product(momentum, momentum),
                                                                           speed_squared),
                                                momentum_expected);
    }
    scriptura_text(&tally->line, "  the arc: the helix of radius 1/(2 pi) rising 1/pi a turn, over our disk\n");
    sim_check(tally, bending, "in Q(pi), the helix's curvature is 2 pi^3 / (pi^2 + 1) at all four quarter turns");
    sim_check(tally, twisting, "in Q(pi), its torsion is 2 pi^2 / (pi^2 + 1) at all four");
    sim_check(tally, balanced && tilted,
              "tau / kappa = 1 / pi, the tangent of its tilt against our disk, at all four (Lancret)");
    sim_check(tally, axial, "its Darboux vector tau T + kappa B lies along our disk's axis at all four");
    sim_check(tally, torque_free && momentum_held,
              "the torque about our axis is zero and L_z^2 = 1 / (4 (pi^2 + 1)) at unit speed, at all four: present, and balanced");

    // the numbers: kappa and tau rise with pi, and arctan(1 / pi) falls, so each is bracketed by the ends of pi's
    const unsigned int places = 12u;
    PiWide unit = pi_tower_whole(1ull);
    for (unsigned int place = 0u; place < places; place += 1u)
    {
        unit = pi_tower_product(unit, pi_tower_whole(10ull));
    }
    const PiWide scale = pi_tower_power_two(bits);
    const PiWide scale_squared = pi_tower_power_two(2u * bits);
    const PiWide ends[2] = {low, high};
    PiWide kappa[2];
    PiWide tau[2];
    for (unsigned int end = 0u; end < 2u; end += 1u)
    {
        const PiWide square = pi_tower_product(ends[end], ends[end]);
        const PiWide below = pi_tower_sum(square, scale_squared);
        // kappa = 2 P^3 / (2^bits (P^2 + 4^bits)), tau = 2 P^2 / (P^2 + 4^bits), for pi = P / 2^bits
        kappa[end] = pi_tower_quotient(pi_tower_product(pi_tower_product(square, ends[end]), pi_tower_product(unit, pi_tower_whole(2ull))),
                                       pi_tower_product(scale, below));
        tau[end] = pi_tower_quotient(pi_tower_product(square, pi_tower_product(unit, pi_tower_whole(2ull))), below);
    }
    unsigned long long small_terms = 0ull;
    unsigned long long large_terms = 0ull;
    // 1 / pi 2^bits lies strictly between these, so arctan(1 / pi) 2^bits lies between their arctangents
    const PiWide small = pi_tower_quotient(scale_squared, high);
    const PiWide large = pi_tower_sum(pi_tower_quotient(scale_squared, low), pi_tower_whole(1ull));
    const PiWide small_angle = pi_tower_arctan_fixed(small, bits, &small_terms);
    const PiWide large_angle = pi_tower_arctan_fixed(large, bits, &large_terms);
    // degrees = 180 phi / pi = 180 S / P, with S = phi 2^bits
    const PiWide degrees = pi_tower_product(unit, pi_tower_whole(180ull));
    const PiWide tilt_low = pi_tower_quotient(
        pi_tower_product(pi_tower_difference(small_angle, pi_tower_whole((3ull * small_terms) + 2ull)), degrees), high);
    const PiWide tilt_high = pi_tower_quotient(
        pi_tower_product(pi_tower_sum(large_angle, pi_tower_whole((3ull * large_terms) + 2ull)), degrees), low);
    // L_z = 1 / (2 sqrt(pi^2 + 1)) falls as pi rises; its square is 4^bits / (4 (P^2 + 4^bits)), and the floor of the
    // root of a floor is the floor of the root
    PiWide momentum[2];
    for (unsigned int end = 0u; end < 2u; end += 1u)
    {
        const PiWide below = pi_tower_product(pi_tower_sum(pi_tower_product(ends[end], ends[end]), scale_squared),
                                              pi_tower_whole(4ull));
        momentum[end] = pi_tower_root(pi_tower_quotient(pi_tower_product(pi_tower_product(unit, unit), scale_squared), below));
    }
    const int agree = (pi_tower_compare(kappa[0], kappa[1]) == 0) && (pi_tower_compare(tau[0], tau[1]) == 0)
                   && (pi_tower_compare(tilt_low, tilt_high) == 0) && (pi_tower_compare(momentum[0], momentum[1]) == 0);
    scriptura_text(&tally->line, "    curvature ");
    pi_tower_print_places(&tally->line, kappa[0], places);
    scriptura_text(&tally->line, ", torsion ");
    pi_tower_print_places(&tally->line, tau[0], places);
    scriptura_text(&tally->line, ", the tilt of its plane against our disk ");
    pi_tower_print_places(&tally->line, tilt_low, places);
    scriptura_text(&tally->line, " degrees, and against our axis ");
    // the tilt is irrational, so the floor of 90 less it is 90 less its floor, less one
    pi_tower_print_places(&tally->line,
                          pi_tower_difference(pi_tower_product(unit, pi_tower_whole(90ull)),
                                              pi_tower_sum(tilt_low, pi_tower_whole(1ull))),
                          places);
    scriptura_text(&tally->line, " degrees\n    angular momentum about our axis at unit speed ");
    pi_tower_print_places(&tally->line, momentum[0], places);
    scriptura_character(&tally->line, '\n');
    sim_check(tally, agree, "curvature, torsion, tilt and L_z agree at both ends of pi's bracket to 12 places");
    sim_flush(tally);
}

// words += increment over PI_TOWER_WORDS, returning the carry out of the top word
static unsigned long long pi_tower_words_add(unsigned long long *words, const unsigned long long *increment)
{
    unsigned long long carry = 0ull;
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        const unsigned long long added = words[word] + increment[word];
        const unsigned long long total = added + carry;
        carry = ((added < words[word]) || (total < added)) ? 1ull : 0ull;
        words[word] = total;
    }
    return carry;
}

// -1, 0 or 1 as left is below, equal to or above right
static int pi_tower_words_compare(const unsigned long long *left, const unsigned long long *right)
{
    for (unsigned int word = PI_TOWER_WORDS; word > 0u; word -= 1u)
    {
        if (left[word - 1u] != right[word - 1u])
        {
            return (left[word - 1u] < right[word - 1u]) ? -1 : 1;
        }
    }
    return 0;
}

static int pi_tower_words_zero(const unsigned long long *words)
{
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        if (words[word] != 0ull)
        {
            return 0;
        }
    }
    return 1;
}

// 2^(64 PI_TOWER_WORDS) - words, the distance up to the next whole
static void pi_tower_words_complement(const unsigned long long *words, unsigned long long *complement)
{
    unsigned long long carry = 1ull;
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        const unsigned long long flipped = ~words[word];
        complement[word] = flipped + carry;
        carry = ((carry != 0ull) && (complement[word] == 0ull)) ? 1ull : 0ull;
    }
}

static PiWide pi_tower_words_wide(const unsigned long long *words)
{
    PiWide value;
    anchor_exact_zero(&value);
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        // the low and high halves of a 64-bit word each fit one 32-bit limb
        value.limb[2u * word] = (uint32_t)(words[word] & 0xFFFFFFFFull);
        // the high half, shifted down, is below 2^32
        value.limb[(2u * word) + 1u] = (uint32_t)(words[word] >> 32u);
    }
    value.sign = (pi_tower_words_zero(words) != 0) ? 0 : 1;
    return value;
}

// 10. the billiard from the corner at slope pi, walked through its unfolded lattice. Column i holds the cells
// j = floor(pi i) .. floor(pi (i + 1)), each one segment between walls, in the order the ball runs them; each floor
// is 3 n + floor(alpha n), read from the integer turn's carries.
static void pi_tower_billiard(SimTally *tally, const PiWide &alpha, const std::vector<PiWide> &denominators)
{
    unsigned long long increment[PI_TOWER_WORDS];
    unsigned long long twice[PI_TOWER_WORDS];
    unsigned long long single[PI_TOWER_WORDS];
    unsigned long long odd[PI_TOWER_WORDS];
    unsigned long long nearest[PI_TOWER_WORDS];
    unsigned long long closest[PI_TOWER_WORDS];
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        increment[word] = ((unsigned long long)alpha.limb[(2u * word) + 1u] << 32u) | (unsigned long long)alpha.limb[2u * word];
        single[word] = 0ull;
        odd[word] = increment[word];
        nearest[word] = ~0ull;
        closest[word] = ~0ull;
        twice[word] = increment[word];
    }
    const unsigned long long twice_carry = pi_tower_words_add(twice, increment);
    const unsigned long long columns = 1ull << PI_TOWER_BILLIARD_BITS;
    // floor(alpha i) and floor(alpha (2i + 1)); A is below 2^P, so both start at 0
    unsigned long long single_whole = 0ull;
    unsigned long long odd_whole = 0ull;
    unsigned long long segments = 0ull;
    unsigned long long vertical = 0ull;
    unsigned long long horizontal = 0ull;
    unsigned long long corners = 0ull;
    unsigned long long uncertain = 0ull;
    unsigned long long zero = 0ull;
    unsigned long long changes = 0ull;
    unsigned long long run = 0ull;
    unsigned long long longest = 0ull;
    unsigned long long ahead = 0ull;
    unsigned long long nearest_column = 0ull;
    unsigned long long nearest_row = 0ull;
    int sign_before = 0;
    std::vector<unsigned long long> near_corners;
    for (unsigned long long column = 0ull; column < columns; column += 1ull)
    {
        unsigned long long next[PI_TOWER_WORDS];
        for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
        {
            next[word] = single[word];
        }
        const unsigned long long next_whole = single_whole + pi_tower_words_add(next, increment);
        // the real n alpha 2^P lies in (n A, n A + n): with the top word short of all ones, n < 2^320 cannot carry it
        // past a whole, so the floor read from the carries is the real floor
        uncertain += ((next[PI_TOWER_WORDS - 1u] == ~0ull) || (odd[PI_TOWER_WORDS - 1u] == ~0ull)) ? 1ull : 0ull;
        corners += (pi_tower_words_zero(next) != 0) ? 1ull : 0ull;
        zero += (pi_tower_words_zero(odd) != 0) ? 1ull : 0ull;
        const unsigned long long bottom = (3ull * column) + single_whole;
        const unsigned long long top = (3ull * (column + 1ull)) + next_whole;
        for (unsigned long long row = bottom; row <= top; row += 1ull)
        {
            // L = (-1)^(i + j) (d - alpha (2i + 1)) / 2, d = (2j + 1) - 3 (2i + 1) whole; the rows and 3 (2i + 1)
            // stay below 2^27 at 2^24 columns, so each fits a signed word
            const long long reach = (long long)((2ull * row) + 1ull) - (long long)(3ull * ((2ull * column) + 1ull));
            // alpha (2i + 1) lies strictly between odd_whole and odd_whole + 1, so d stands above it exactly when
            // d > odd_whole, which fits a signed word for the same reason
            const int above = reach > (long long)odd_whole;
            // the parity of i + j, one bit, fits an int
            const int positive = above ^ (int)((column + row) & 1ull);
            if ((segments != 0ull) && (positive != sign_before))
            {
                changes += 1ull;
                longest = (run > longest) ? run : longest;
                run = 0ull;
            }
            run += 1ull;
            ahead += (positive != 0) ? 1ull : 0ull;
            sign_before = positive;
            segments += 1ull;
            // the nearest tie: |d - alpha (2i + 1)| below 1 when d is odd_whole or odd_whole + 1
            unsigned long long distance[PI_TOWER_WORDS];
            int near = 0;
            if (reach == (long long)odd_whole)
            {
                for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
                {
                    distance[word] = odd[word];
                }
                near = 1;
            }
            else if (reach == ((long long)odd_whole + 1ll))
            {
                pi_tower_words_complement(odd, distance);
                near = 1;
            }
            if ((near != 0) && (pi_tower_words_compare(distance, nearest) < 0))
            {
                for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
                {
                    nearest[word] = distance[word];
                }
                nearest_column = column;
                nearest_row = row;
            }
        }
        horizontal += top - bottom;
        vertical += 1ull;
        // how near the wall hit at x = i + 1 comes to a corner: alpha (i + 1)'s distance to a whole
        unsigned long long mirror[PI_TOWER_WORDS];
        pi_tower_words_complement(next, mirror);
        const unsigned long long *const miss = (pi_tower_words_compare(next, mirror) < 0) ? next : mirror;
        if (pi_tower_words_compare(miss, closest) < 0)
        {
            for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
            {
                closest[word] = miss[word];
            }
            near_corners.push_back(column + 1ull);
        }
        for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
        {
            single[word] = next[word];
        }
        single_whole = next_whole;
        odd_whole += pi_tower_words_add(odd, twice) + twice_carry;
    }
    longest = (run > longest) ? run : longest;
    size_t floors_in_walk = 0u;
    while ((floors_in_walk < denominators.size())
           && (pi_tower_compare(denominators[floors_in_walk], pi_tower_whole(columns)) <= 0))
    {
        floors_in_walk += 1u;
    }
    int matched = near_corners.size() == floors_in_walk;
    for (size_t at = 0u; (at < near_corners.size()) && (at < floors_in_walk); at += 1u)
    {
        matched = matched && (near_corners[at] == pi_tower_word(denominators[at]));
    }
    scriptura_text(&tally->line, "  the billiard from the corner at slope pi, 2^");
    scriptura_decimal(&tally->line, PI_TOWER_BILLIARD_BITS, 1u);
    scriptura_text(&tally->line, " columns: ");
    scriptura_decimal(&tally->line, segments, 1u);
    scriptura_text(&tally->line, " segments between ");
    scriptura_decimal(&tally->line, vertical, 1u);
    scriptura_text(&tally->line, " side-wall and ");
    scriptura_decimal(&tally->line, horizontal, 1u);
    scriptura_text(&tally->line, " floor-wall hits, ");
    scriptura_decimal(&tally->line, corners, 1u);
    scriptura_text(&tally->line, " corners\n    the lead in L about the centre changed hands ");
    scriptura_decimal(&tally->line, changes, 1u);
    scriptura_text(&tally->line, " times, the longest lead ");
    scriptura_decimal(&tally->line, longest, 1u);
    scriptura_text(&tally->line, " segments, one side ahead on ");
    scriptura_decimal(&tally->line, ahead, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, segments, 1u);
    scriptura_text(&tally->line, "\n    the nearest tie: |L| = ");
    pi_tower_print_exponent(&tally->line, pi_tower_words_wide(nearest), pi_tower_power_two(PI_TOWER_BITS + 1u));
    scriptura_text(&tally->line, " (p = (1, pi)) in cell (");
    scriptura_decimal(&tally->line, nearest_column, 1u);
    scriptura_text(&tally->line, ", ");
    scriptura_decimal(&tally->line, nearest_row, 1u);
    scriptura_text(&tally->line, "), where pi stands nearest ");
    scriptura_decimal(&tally->line, (2ull * nearest_row) + 1ull, 1u);
    scriptura_character(&tally->line, '/');
    scriptura_decimal(&tally->line, (2ull * nearest_column) + 1ull, 1u);
    scriptura_text(&tally->line, "\n    the record near-corners at the side walls: ");
    for (size_t at = 0u; at < near_corners.size(); at += 1u)
    {
        scriptura_decimal(&tally->line, near_corners[at], 1u);
        scriptura_text(&tally->line, (at + 1u < near_corners.size()) ? ", " : "\n");
    }
    sim_check(tally, (corners == 0ull) && (uncertain == 0ull),
              "no wall hit on the walk is a corner, and every floor on it is the real floor: one wall always wins");
    sim_check(tally, (zero == 0ull) && (uncertain == 0ull),
              "no segment's angular momentum about the centre is zero: one sense always leads");
    sim_check(tally, matched && (floors_in_walk > 10u), "the walk's record near-corners are exactly the floors' q_j");
    sim_flush(tally);
}

// 11. The residue (Doug, 24 September: "if qa is almost a whole number, we can get its identity and its null
// permutation will make it a whole, that is its residue"). On floor j, q_j alpha = p_j + delta_j. Put p_j / q_j for
// alpha and the turn is the permutation n -> n p_j mod q_j of q_j cells, whole again after q_j steps: the identity.
// Where q_j |delta_j| < 1, pi's whole parts for n < q_j are the permutation's, floor(n alpha) = floor(n p_j / q_j),
// each point carried n delta_j / q_j off the permutation's mark, past it where delta_j > 0 and short of it where
// delta_j < 0 (so into the right-closed cell), and at n = q_j pi stands at P + delta_j where the permutation is whole:
// the residue. Walked on the 384-bit turn, the whole parts read from its carries, on every floor with q_j at most
// 2^PI_TOWER_RESIDUE_BITS.
static void pi_tower_residues(SimTally *tally, const PiWide &walk_alpha, const std::vector<PiWide> &denominators,
                              const std::vector<PiWide> &floors)
{
    const PiWide modulus = pi_tower_power_two(PI_TOWER_BITS);
    const PiWide limit = pi_tower_power_two(PI_TOWER_RESIDUE_BITS);
    unsigned long long increment[PI_TOWER_WORDS];
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        increment[word] = ((unsigned long long)walk_alpha.limb[(2u * word) + 1u] << 32u)
                        | (unsigned long long)walk_alpha.limb[2u * word];
    }
    int held = 1;
    int certain = 1;
    unsigned int walked = 0u;
    // p_(j-2) and p_(j-1), from p_(-1) = 1 and p_0 = 0
    unsigned long long numerator_before = 1ull;
    unsigned long long numerator = 0ull;
    scriptura_text(&tally->line, "  the residue: floor j, pi's identity P/q, the residue q pi - P, and q steps walked as the permutation n -> n p mod q\n");
    for (size_t at = 0u; (at < denominators.size()) && (pi_tower_compare(denominators[at], limit) <= 0); at += 1u)
    {
        if (at > 0u)
        {
            // a_j p_(j-1) + p_(j-2): each p_j is below q_j, below 2^21, so the words hold them
            const unsigned long long next = (pi_tower_word(floors[at]) * numerator) + numerator_before;
            numerator_before = numerator;
            numerator = next;
        }
        const unsigned long long steps = pi_tower_word(denominators[at]);
        const PiWide residue = pi_tower_difference(pi_tower_product(denominators[at], walk_alpha),
                                                   pi_tower_product(pi_tower_whole(numerator), modulus));
        const int negative = residue.sign < 0;
        PiWide size = residue;
        size.sign = (residue.sign == 0) ? 0 : 1;
        // the real residue lies in (qA - pM, qA - pM + q); the integer whole parts are the real ones and each point stays
        // in its cell when q (size + q) < M where delta > 0, and q size < M with size >= q where delta < 0
        const PiWide q = denominators[at];
        certain = certain
               && ((negative == 0)
                       ? (pi_tower_compare(pi_tower_product(q, pi_tower_sum(size, q)), modulus) < 0)
                       : ((pi_tower_compare(pi_tower_product(q, size), modulus) < 0) && (pi_tower_compare(size, q) >= 0)));
        unsigned long long place[PI_TOWER_WORDS];
        for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
        {
            place[word] = 0ull;
        }
        unsigned long long whole = 0ull;
        int floor_held = 1;
        for (unsigned long long step = 0ull; step < steps; step += 1ull)
        {
            // n p < 2^42, so the permutation's whole part is a word's quotient
            floor_held = floor_held && (whole == ((step * numerator) / steps));
            whole += pi_tower_words_add(place, increment);
        }
        // at n = q the walk stands at the residue: whole P past 3 q, and delta past it, or whole P - 1 and |delta|
        // short of the next
        const PiWide standing = pi_tower_words_wide(place);
        floor_held = floor_held && (whole == ((negative != 0) ? (numerator - 1ull) : numerator))
                  && (pi_tower_compare(standing, (negative != 0) ? pi_tower_difference(modulus, size) : size) == 0);
        held = held && floor_held;
        walked += 1u;
        scriptura_text(&tally->line, "    ");
        scriptura_decimal(&tally->line, at, 2u);
        scriptura_text(&tally->line, "  ");
        scriptura_decimal(&tally->line, (3ull * steps) + numerator, 1u);
        scriptura_character(&tally->line, '/');
        scriptura_decimal(&tally->line, steps, 1u);
        scriptura_text(&tally->line, "  residue ");
        scriptura_character(&tally->line, (negative != 0) ? '-' : '+');
        pi_tower_print_exponent(&tally->line, size, modulus);
        scriptura_text(&tally->line, (floor_held != 0) ? "  the permutation's whole parts, and the residue at step q\n"
                                                       : "  NOT the permutation\n");
        sim_flush(tally);
    }
    sim_check(tally, held && certain && (walked >= 12u),
              "on every floor with q_j to 2^21, pi's first q_j steps have the whole parts of the permutation n -> n p_j mod q_j, and at step q_j it stands its residue off the whole");
}

// 12. The golden helix (Doug, 24 September: "their period is a contraction of the golden spiral, pi is riding its
// inverse in the negative space"; "pi DOES ride it, and it rides it exactly because thats a helix"). The residues flip
// sign each floor, a half turn, and shrink by 1 / [a_(j+1); a_(j+2), ...]: on the cylinder of angle and log size they
// step down a helix. The golden ratio [1; 1, 1, ...] shrinks by exactly 1 / phi every half turn, and every tower is at
// least as tall as its, q_j >= F_(j+1). Each residue is bracketed from the turn, (qA - pM, qA - pM + q), and every
// comparison is decided at both ends.
static void pi_tower_golden(SimTally *tally, const PiTowerTurn &turn, const std::vector<PiWide> &denominators,
                            const std::vector<PiWide> &floors)
{
    const PiWide bound = pi_tower_power_two(PI_TOWER_RECORD_BITS);
    std::vector<PiWide> low;
    std::vector<PiWide> high;
    PiWide numerator_before = pi_tower_whole(1ull);
    PiWide numerator = pi_tower_whole(0ull);
    PiWide fibonacci_before = pi_tower_whole(0ull);
    PiWide fibonacci = pi_tower_whole(1ull);
    int alternates = 1;
    int above_golden_floor = 1;
    int under_next = 1;
    for (size_t at = 0u; (at < denominators.size()) && (pi_tower_compare(denominators[at], bound) <= 0); at += 1u)
    {
        if (at > 0u)
        {
            const PiWide next = pi_tower_sum(pi_tower_product(floors[at], numerator), numerator_before);
            numerator_before = numerator;
            numerator = next;
        }
        // F_(j+1): F_1 = 1 at j = 0
        above_golden_floor = above_golden_floor && (pi_tower_compare(denominators[at], fibonacci) >= 0);
        const PiWide residue = pi_tower_difference(pi_tower_product(denominators[at], turn.multiplier),
                                                   pi_tower_product(numerator, turn.modulus));
        PiWide size = residue;
        size.sign = (residue.sign == 0) ? 0 : 1;
        // the real residue's size: (size, size + q) where it is positive, (size - q, size) where negative
        low.push_back((residue.sign > 0) ? size : pi_tower_difference(size, denominators[at]));
        high.push_back((residue.sign > 0) ? pi_tower_sum(size, denominators[at]) : size);
        alternates = alternates && (residue.sign == (((at & 1u) == 0u) ? 1 : -1));
        // under the next floor: |delta_j| < 1 / q_(j+1), and so under the golden 1 / F_(j+2)
        if ((at + 1u) < denominators.size())
        {
            under_next = under_next && (pi_tower_compare(pi_tower_product(high.back(), denominators[at + 1u]), turn.modulus) < 0);
        }
        const PiWide next_fibonacci = pi_tower_sum(fibonacci, fibonacci_before);
        fibonacci_before = fibonacci;
        fibonacci = next_fibonacci;
    }
    scriptura_text(&tally->line, "  the golden helix: floor j (a_(j+1)), the residue's shrink |delta_j| / |delta_(j-1)|, against 1/phi = 0.6180\n");
    int band_held = 1;
    int decided = 1;
    unsigned int below = 0u;
    unsigned int above = 0u;
    unsigned int banded = 0u;
    // |delta_(j-1)| = a_(j+1) |delta_j| + |delta_(j+1)| (Euclid), so the shrink lies in (1 / (a_(j+1) + 1), 1 / a_(j+1))
    for (size_t at = 1u; (at < low.size()) && ((at + 1u) < floors.size()); at += 1u)
    {
        // shrink below 1/phi exactly where (2 x + y)^2 < 5 y^2, x = |delta_j|, y = |delta_(j-1)|: that falls as x
        // rises and rises with y, so the two corners of the bracket decide it
        const PiWide least = pi_tower_difference(
            pi_tower_product(pi_tower_whole(5ull), pi_tower_product(low[at - 1u], low[at - 1u])),
            pi_tower_product(pi_tower_sum(pi_tower_sum(high[at], high[at]), low[at - 1u]),
                             pi_tower_sum(pi_tower_sum(high[at], high[at]), low[at - 1u])));
        const PiWide most = pi_tower_difference(
            pi_tower_product(pi_tower_whole(5ull), pi_tower_product(high[at - 1u], high[at - 1u])),
            pi_tower_product(pi_tower_sum(pi_tower_sum(low[at], low[at]), high[at - 1u]),
                             pi_tower_sum(pi_tower_sum(low[at], low[at]), high[at - 1u])));
        const int under = least.sign > 0;
        decided = decided && (least.sign == most.sign) && (least.sign != 0);
        below += (under != 0) ? 1u : 0u;
        above += (under == 0) ? 1u : 0u;
        // the shrink stands between 1/2 and 1 exactly on the floors of 1: 2 x > y
        const int wide = pi_tower_compare(pi_tower_sum(low[at], low[at]), high[at - 1u]) > 0;
        const int narrow = pi_tower_compare(pi_tower_sum(high[at], high[at]), low[at - 1u]) < 0;
        decided = decided && ((wide != 0) || (narrow != 0));
        const int one_floor = pi_tower_compare(floors[at + 1u], pi_tower_whole(1ull)) == 0;
        band_held = band_held && (wide == one_floor);
        banded += (wide != 0) ? 1u : 0u;
        scriptura_text(&tally->line, "    ");
        scriptura_decimal(&tally->line, at, 2u);
        scriptura_text(&tally->line, " (");
        pi_tower_print_decimal(&tally->line, floors[at + 1u]);
        scriptura_text(&tally->line, ")  ");
        sim_ratio_print(&tally->line, &low[at], &high[at - 1u], 4u);
        scriptura_text(&tally->line, (under != 0) ? "  below the golden shrink\n" : "  above the golden shrink\n");
        sim_flush(tally);
    }
    // the mean growth a floor, q_J^(1 / J), to 6 places: the largest r with r^J <= q_J 10^(6 J)
    const size_t last = low.size() - 1u;
    PiWide scaled = denominators[last];
    for (size_t place = 0u; place < (6u * last); place += 1u)
    {
        scaled = pi_tower_product(scaled, pi_tower_whole(10ull));
    }
    unsigned long long root_low = 1000000ull;
    unsigned long long root_high = 100000000ull;
    while ((root_high - root_low) > 1ull)
    {
        const unsigned long long middle = root_low + ((root_high - root_low) / 2ull);
        PiWide power = pi_tower_whole(1ull);
        for (size_t times = 0u; times < last; times += 1u)
        {
            power = pi_tower_product(power, pi_tower_whole(middle));
        }
        if (pi_tower_compare(power, scaled) <= 0)
        {
            root_low = middle;
        }
        else
        {
            root_high = middle;
        }
    }
    // phi = (1 + sqrt 5) / 2 to 6 places: (10^6 + floor(sqrt(5 10^12))) / 2, the root's floor taken exactly
    const unsigned long long golden = (1000000ull + pi_tower_word(pi_tower_root(pi_tower_whole(5000000000000ull)))) / 2ull;
    scriptura_text(&tally->line, "    ");
    scriptura_decimal(&tally->line, below, 1u);
    scriptura_text(&tally->line, " floors shrink below the golden 1/phi and ");
    scriptura_decimal(&tally->line, above, 1u);
    scriptura_text(&tally->line, " above; ");
    scriptura_decimal(&tally->line, banded, 1u);
    scriptura_text(&tally->line, " shrink between 1/2 and 1, the floors of 1\n    growth a floor, q_");
    scriptura_decimal(&tally->line, last, 1u);
    scriptura_text(&tally->line, "^(1/");
    scriptura_decimal(&tally->line, last, 1u);
    scriptura_text(&tally->line, ") = ");
    scriptura_decimal(&tally->line, root_low / 1000000ull, 1u);
    scriptura_character(&tally->line, '.');
    scriptura_decimal(&tally->line, root_low % 1000000ull, 6u);
    scriptura_text(&tally->line, ", against the golden phi = ");
    scriptura_decimal(&tally->line, golden / 1000000ull, 1u);
    scriptura_character(&tally->line, '.');
    scriptura_decimal(&tally->line, golden % 1000000ull, 6u);
    scriptura_character(&tally->line, '\n');
    sim_check(tally, alternates, "the residues flip sign on every floor, a half turn: from above on even floors, from below on odd");
    sim_check(tally, above_golden_floor && under_next,
              "every floor is at least the golden one, q_j >= F_(j+1), and every residue is under the next floor's 1 / q_(j+1)");
    sim_check(tally, decided && band_held,
              "the shrink stands between 1/2 and 1 exactly where the next floor is 1, each side of 1/phi decided at both ends");
    sim_flush(tally);
}

// one record program on the engine: the key keymath imprints, the layout the scheduler lays, and the record cycle loads
typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
} PiTowerProgram;

// pi's hex digits from position d + 1 on the engine. Term i <= d is a lane: 16^(d - i) mod 8 i + j by powering in base
// 16, each square taken mod 8 i + j, and that residue's fraction floored to W bits. Tail term d + t is a lane of its
// own, 2^W / ((8 (d + t) + j) 16^t) floored. The pair program adds two lanes' sums mod 2^W, and its rounds reduce a
// sweep to one. Every lane's sum is wrapped to W = 32 k - 1 bits, so with its sign it fills k whole limbs.
typedef struct
{
    PiWide position;
    PiWide terms;
    unsigned int position_bits;
    unsigned int fraction_bits;
    unsigned int tail_terms;
    unsigned int tail_bits;
    unsigned int in_limbs;
    unsigned int out_limbs;
    unsigned long long lanes;
    PiTowerProgram term;
    PiTowerProgram tail;
    PiTowerProgram pair;
} PiTowerBbp;

// how far a run on the engine reached: the terms summed, the seconds it took, and where every term was summed, the sum
typedef struct
{
    unsigned long long done;
    unsigned long long sweeps;
    double seconds;
    int finished;
    PiWide sum;
} PiTowerBbpRun;

// the four denominators' offsets, 8 i + j
static const unsigned int s_pi_tower_bbp_offset[4] = {1u, 4u, 5u, 6u};

// set by an interrupt: the run stops after the sweep it is in and reports how far it reached
static volatile sig_atomic_t s_pi_tower_stopped = 0;

static void pi_tower_stop(int signal_number)
{
    (void)signal_number;
    s_pi_tower_stopped = 1;
}

static unsigned int pi_tower_bit_length(const PiWide &value)
{
    unsigned int limb = ANCHOR_EXACT_LIMBS;
    while ((limb > 0u) && (value.limb[limb - 1u] == 0u))
    {
        limb -= 1u;
    }
    if (limb == 0u)
    {
        return 0u;
    }
    unsigned int bits = 32u * (limb - 1u);
    for (unsigned int top = value.limb[limb - 1u]; top != 0u; top >>= 1u)
    {
        bits += 1u;
    }
    return bits;
}

static unsigned int pi_tower_step(std::vector<EngineRecordStep> *steps, EngineRecordOperation operation,
                                  unsigned int left, unsigned int right)
{
    EngineRecordStep step;
    step.operation = operation;
    step.left = left;
    step.right = right;
    step.member = 0u;
    steps->push_back(step);
    // a program's steps are counted in an unsigned int, as keymath counts them
    return (unsigned int)(steps->size() - 1u);
}

static unsigned int pi_tower_field(std::vector<EngineRecordStep> *steps, unsigned int field, unsigned int member)
{
    const unsigned int step = pi_tower_step(steps, ENGINE_RECORD_FIELD, field, 0u);
    (*steps)[step].member = member;
    return step;
}

// a register holding a non-negative integer: one constant below 2^64, and past it Horner's rule over the 32-bit limbs
// from the top, a product by 2^32 and a sum a limb
static unsigned int pi_tower_constant(std::vector<EngineRecordStep> *steps, const PiWide &value)
{
    unsigned int used = ANCHOR_EXACT_LIMBS;
    while ((used > 1u) && (value.limb[used - 1u] == 0u))
    {
        used -= 1u;
    }
    if (used <= 2u)
    {
        return pi_tower_step(steps, ENGINE_RECORD_CONSTANT, value.limb[0], (used > 1u) ? value.limb[1] : 0u);
    }
    unsigned int held = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, value.limb[used - 2u], value.limb[used - 1u]);
    for (unsigned int limb = used - 2u; limb > 0u; limb -= 1u)
    {
        const unsigned int shift = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, 0u, 1u);
        held = pi_tower_step(steps, ENGINE_RECORD_PRODUCT, held, shift);
        if (value.limb[limb - 1u] != 0u)
        {
            const unsigned int low = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, value.limb[limb - 1u], 0u);
            held = pi_tower_step(steps, ENGINE_RECORD_SUM, held, low);
        }
    }
    return held;
}

// 4 S_1 - 2 S_4 - S_5 - S_6 of a lane's four fractions, wrapped to W bits: the lane's sum mod 2^W
static void pi_tower_bbp_combine(std::vector<EngineRecordStep> *steps, const unsigned int *fraction,
                                 unsigned int fraction_bits)
{
    const unsigned int four = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, 4u, 0u);
    const unsigned int two = pi_tower_step(steps, ENGINE_RECORD_CONSTANT, 2u, 0u);
    const unsigned int first = pi_tower_step(steps, ENGINE_RECORD_PRODUCT, four, fraction[0]);
    const unsigned int second = pi_tower_step(steps, ENGINE_RECORD_PRODUCT, two, fraction[1]);
    const unsigned int less = pi_tower_step(steps, ENGINE_RECORD_DIFFERENCE, first, second);
    const unsigned int fewer = pi_tower_step(steps, ENGINE_RECORD_DIFFERENCE, less, fraction[2]);
    const unsigned int least = pi_tower_step(steps, ENGINE_RECORD_DIFFERENCE, fewer, fraction[3]);
    pi_tower_step(steps, ENGINE_RECORD_WRAP, least, fraction_bits);
}

// keymath imprints the program, its last step the output, and the scheduler lays its registers, each reused once its
// last reader has run
static int pi_tower_program_lay(PiTowerProgram *program, const std::vector<EngineRecordStep> &steps,
                                const unsigned int *field_bits, unsigned int members, const unsigned int *in_limbs,
                                const EngineRecordTable *tables, unsigned int table_count, EngineError *error)
{
    memset(program, 0, sizeof(*program));
    // a program's steps are counted in an unsigned int, as keymath counts them
    const unsigned int count = (unsigned int)steps.size();
    const unsigned int output = count - 1u;
    const unsigned int field_offset[1] = {0u};
    const KeymathRecordRequest imprint = {steps.data(), count,      field_bits,  1u,          members, &output,
                                          1u,           tables,     table_count, &program->key, error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return 0;
    }
    const KeyScheduleRecordRequest lay = {&program->key, field_offset, 1u, in_limbs, 1, &program->layout, error};
    if (key_schedule_record_lay(&lay) == KEY_SCHEDULE_REFUSED)
    {
        keymath_record_release(&program->key);
        return 0;
    }
    return 1;
}

static void pi_tower_program_free(PiTowerProgram *program)
{
    cycle_record_release(program->record);
    key_schedule_record_release(&program->layout);
    keymath_record_release(&program->key);
    program->record = NULL;
}

static void pi_tower_bbp_free(PiTowerBbp *bbp)
{
    pi_tower_program_free(&bbp->term);
    pi_tower_program_free(&bbp->tail);
    pi_tower_program_free(&bbp->pair);
}

// the term lane: field 0 is i
static int pi_tower_bbp_term_lay(PiTowerBbp *bbp, EngineError *error)
{
    std::vector<EngineRecordStep> steps;
    const unsigned int index = pi_tower_field(&steps, 0u, 0u);
    const unsigned int position = pi_tower_constant(&steps, bbp->position);
    const unsigned int exponent = pi_tower_step(&steps, ENGINE_RECORD_DIFFERENCE, position, index);
    const unsigned int nibbles = (bbp->position_bits + 3u) / 4u;
    // 16^nibbles stands above every exponent, so a quotient by any lower power of 16 keeps a whole nibble to index by
    const unsigned int above = pi_tower_constant(&steps, pi_tower_power_two(4u * nibbles));
    const unsigned int guarded = pi_tower_step(&steps, ENGINE_RECORD_SUM, exponent, above);
    const unsigned int eight = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, 8u, 0u);
    const unsigned int eighth = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, eight, index);
    const unsigned int one = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, 1u, 0u);
    unsigned int modulus[4];
    unsigned int residue[4];
    for (unsigned int kind = 0u; kind < 4u; kind += 1u)
    {
        const unsigned int offset = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, s_pi_tower_bbp_offset[kind], 0u);
        modulus[kind] = pi_tower_step(&steps, ENGINE_RECORD_SUM, eighth, offset);
        residue[kind] = one;
    }
    // 16^e from the top nibble down: r becomes r^16 . 16^(the nibble), each square and product taken mod 8 i + j
    for (unsigned int nibble = nibbles; nibble > 0u; nibble -= 1u)
    {
        const unsigned int place = pi_tower_constant(&steps, pi_tower_power_two(4u * (nibble - 1u)));
        const unsigned int digit = pi_tower_step(&steps, ENGINE_RECORD_QUOTIENT, guarded, place);
        const unsigned int power = pi_tower_step(&steps, ENGINE_RECORD_TABLE, digit, 0u);
        for (unsigned int kind = 0u; kind < 4u; kind += 1u)
        {
            for (unsigned int square = 0u; square < 4u; square += 1u)
            {
                const unsigned int squared = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, residue[kind], residue[kind]);
                residue[kind] = pi_tower_step(&steps, ENGINE_RECORD_REMAINDER, squared, modulus[kind]);
            }
            const unsigned int raised = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, residue[kind], power);
            residue[kind] = pi_tower_step(&steps, ENGINE_RECORD_REMAINDER, raised, modulus[kind]);
        }
    }
    const unsigned int unit = pi_tower_constant(&steps, pi_tower_power_two(bbp->fraction_bits));
    unsigned int fraction[4];
    for (unsigned int kind = 0u; kind < 4u; kind += 1u)
    {
        const unsigned int scaled = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, residue[kind], unit);
        fraction[kind] = pi_tower_step(&steps, ENGINE_RECORD_QUOTIENT, scaled, modulus[kind]);
    }
    pi_tower_bbp_combine(&steps, fraction, bbp->fraction_bits);
    // 16^v for a nibble v, below 2^61
    unsigned int values[32];
    for (unsigned int row = 0u; row < 16u; row += 1u)
    {
        const unsigned long long power = 1ull << (4u * row);
        // the low and high halves of the word each fit a limb
        values[2u * row] = (unsigned int)(power & 0xFFFFFFFFull);
        values[(2u * row) + 1u] = (unsigned int)(power >> 32u);
    }
    const EngineRecordTable table = {4u, 61u, values};
    const unsigned int field_bits[1] = {bbp->position_bits};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {bbp->in_limbs, 0u, 0u};
    return pi_tower_program_lay(&bbp->term, steps, field_bits, 1u, in_limbs, &table, 1u, error);
}

// the tail lane: field 0 is t, the term d + t
static int pi_tower_bbp_tail_lay(PiTowerBbp *bbp, EngineError *error)
{
    std::vector<EngineRecordStep> steps;
    const unsigned int ahead = pi_tower_field(&steps, 0u, 0u);
    const unsigned int position = pi_tower_constant(&steps, bbp->position);
    const unsigned int index = pi_tower_step(&steps, ENGINE_RECORD_SUM, position, ahead);
    const unsigned int eight = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, 8u, 0u);
    const unsigned int eighth = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, eight, index);
    const unsigned int scale = pi_tower_step(&steps, ENGINE_RECORD_TABLE, ahead, 0u);
    const unsigned int unit = pi_tower_constant(&steps, pi_tower_power_two(bbp->fraction_bits));
    unsigned int fraction[4];
    for (unsigned int kind = 0u; kind < 4u; kind += 1u)
    {
        const unsigned int offset = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, s_pi_tower_bbp_offset[kind], 0u);
        const unsigned int modulus = pi_tower_step(&steps, ENGINE_RECORD_SUM, eighth, offset);
        const unsigned int below = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, modulus, scale);
        fraction[kind] = pi_tower_step(&steps, ENGINE_RECORD_QUOTIENT, unit, below);
    }
    pi_tower_bbp_combine(&steps, fraction, bbp->fraction_bits);
    // 16^v for every v the tail's field can hold
    const unsigned int rows = 1u << bbp->tail_bits;
    const unsigned int out_bits = (4u * (rows - 1u)) + 1u;
    const unsigned int row_limbs = (out_bits + 31u) / 32u;
    std::vector<unsigned int> values((size_t)rows * row_limbs, 0u);
    for (unsigned int row = 0u; row < rows; row += 1u)
    {
        values[((size_t)row * row_limbs) + ((4u * row) / 32u)] = 1u << ((4u * row) % 32u);
    }
    const EngineRecordTable table = {bbp->tail_bits, out_bits, values.data()};
    const unsigned int field_bits[1] = {bbp->tail_bits};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {1u, 0u, 0u};
    return pi_tower_program_lay(&bbp->tail, steps, field_bits, 1u, in_limbs, &table, 1u, error);
}

// the pair lane: two lanes' sums, members 0 and 1, added mod 2^W
static int pi_tower_bbp_pair_lay(PiTowerBbp *bbp, EngineError *error)
{
    std::vector<EngineRecordStep> steps;
    const unsigned int left = pi_tower_field(&steps, 0u, 0u);
    const unsigned int right = pi_tower_field(&steps, 0u, 1u);
    const unsigned int sum = pi_tower_step(&steps, ENGINE_RECORD_SUM, left, right);
    pi_tower_step(&steps, ENGINE_RECORD_WRAP, sum, bbp->fraction_bits);
    const unsigned int field_bits[1] = {bbp->fraction_bits + 1u};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {bbp->out_limbs, bbp->out_limbs, 0u};
    return pi_tower_program_lay(&bbp->pair, steps, field_bits, 2u, in_limbs, NULL, 0u, error);
}

// E = 4 (N + T) + 1: each of the N + T lanes floors four fractions weighted 4, 2, 1 and 1, off by less than 4 units
// either way, and the terms past the tail add less than 1
static PiWide pi_tower_bbp_error(const PiTowerBbp *bbp)
{
    const PiWide lanes = pi_tower_sum(bbp->terms, pi_tower_whole(bbp->tail_terms));
    return pi_tower_sum(pi_tower_product(lanes, pi_tower_whole(4ull)), pi_tower_whole(1ull));
}

// the run at hex position d, from d alone: W holds PI_TOWER_BBP_CERTIFIED bits past the error with PI_TOWER_BBP_GUARD
// to spare, and the tail runs until 16^T >= 2^(W + 8)
static int pi_tower_bbp_plan(PiTowerBbp *bbp, const PiWide &position, unsigned long long lanes, EngineError *error)
{
    memset(bbp, 0, sizeof(*bbp));
    bbp->position = position;
    bbp->terms = pi_tower_sum(position, pi_tower_whole(1ull));
    const unsigned int position_bits = pi_tower_bit_length(position);
    bbp->position_bits = (position_bits == 0u) ? 1u : position_bits;
    bbp->lanes = lanes;
    for (unsigned int limbs = 2u;; limbs += 1u)
    {
        bbp->fraction_bits = (32u * limbs) - 1u;
        bbp->tail_terms = (bbp->fraction_bits + 11u) / 4u;
        bbp->out_limbs = limbs;
        if (bbp->fraction_bits >= (PI_TOWER_BBP_CERTIFIED + PI_TOWER_BBP_GUARD + pi_tower_bit_length(pi_tower_bbp_error(bbp))))
        {
            break;
        }
    }
    bbp->tail_bits = pi_tower_bit_length(pi_tower_whole(bbp->tail_terms));
    bbp->in_limbs = (bbp->position_bits + 31u) / 32u;
    if (pi_tower_bbp_term_lay(bbp, error) == 0)
    {
        return 0;
    }
    if (pi_tower_bbp_tail_lay(bbp, error) == 0)
    {
        pi_tower_program_free(&bbp->term);
        return 0;
    }
    if (pi_tower_bbp_pair_lay(bbp, error) == 0)
    {
        pi_tower_program_free(&bbp->term);
        pi_tower_program_free(&bbp->tail);
        return 0;
    }
    return 1;
}

// the device bytes a run holds: its lanes' inputs, two rooms of sums, the pair program's index, the total, and the
// three programs' step tables and lookup tables
static unsigned long long pi_tower_bbp_bytes(const PiTowerBbp *bbp)
{
    const unsigned long long rooms = (bbp->lanes + 1ull) * bbp->out_limbs;
    const unsigned long long steps = (unsigned long long)bbp->term.layout.steps + bbp->tail.layout.steps
                                   + bbp->pair.layout.steps;
    const unsigned long long tables = bbp->term.layout.table_word_count + bbp->tail.layout.table_word_count;
    return (((bbp->lanes * bbp->in_limbs) + (2ull * rooms) + (bbp->lanes + 1ull) + bbp->out_limbs + tables)
            * sizeof(unsigned int))
         + (steps * sizeof(DeviceRecordStep));
}

// every lane's integer, first + lane, in limbs of 32 bits from the low
static __global__ void pi_tower_bbp_count(unsigned int *out, unsigned long long count, unsigned int limbs,
                                          unsigned long long first)
{
    const unsigned long long stride = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long lane = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; lane < count;
         lane += stride)
    {
        const unsigned long long value = first + lane;
        unsigned int *const place = &out[lane * limbs];
        // the low and high halves of the word each fit a limb
        place[0] = (unsigned int)(value & 0xFFFFFFFFull);
        for (unsigned int limb = 1u; limb < limbs; limb += 1u)
        {
            place[limb] = (limb == 1u) ? (unsigned int)(value >> 32u) : 0u;
        }
    }
}

static int pi_tower_bbp_counted(SimTally *tally, unsigned int *out, unsigned long long count, unsigned int limbs,
                                unsigned long long first)
{
    const unsigned long long blocks = sim_launch_blocks(count, 256ull);
    // at most 4096 blocks, so the count fits an unsigned int
    pi_tower_bbp_count<<<(unsigned int)((blocks < 4096ull) ? blocks : 4096ull), 256u>>>(out, count, limbs, first);
    return sim_took(tally, cudaGetLastError(), "engine: the lanes' integers");
}

// the sums of count lanes in rooms[0], reduced to one by rounds of the pair program, the rooms taking turns; the room
// the one sum lands in, or NULL
static unsigned int *pi_tower_bbp_reduce(SimTally *tally, const PiTowerBbp *bbp, unsigned int *const *rooms,
                                         const unsigned int *index, unsigned long long count, EngineError *error)
{
    unsigned int from = 0u;
    unsigned long long left = count;
    while (left > 1ull)
    {
        const unsigned long long pairs = left / 2ull;
        // lane k reads index 2 k and 2 k + 1, lanes 2 k and 2 k + 1 of the room
        const CycleRecordRunRequest run = {bbp->pair.record, {rooms[from], rooms[from], NULL}, {left, left, 0ull},
                                           index,            pairs,                          rooms[1u - from],
                                           error};
        if (cycle_record_run(&run) == CYCLE_REFUSED)
        {
            sim_check(tally, 0, "engine: the pair program adds a sweep's lanes");
            return NULL;
        }
        // the odd lane out rides into the next round unpaired
        if (((left & 1ull) != 0ull)
            && !sim_took(tally,
                         cudaMemcpy(&rooms[1u - from][pairs * bbp->out_limbs], &rooms[from][(left - 1ull) * bbp->out_limbs],
                                    bbp->out_limbs * sizeof(unsigned int), cudaMemcpyDeviceToDevice),
                         "engine: the odd lane"))
        {
            return NULL;
        }
        left = pairs + (left & 1ull);
        from = 1u - from;
    }
    return rooms[from];
}

// the sum read from the device: the pair program's two's complement over W + 1 bits, taken mod 2^W
static int pi_tower_bbp_read(SimTally *tally, const PiTowerBbp *bbp, const unsigned int *total, PiWide *sum)
{
    std::vector<unsigned int> limbs(bbp->out_limbs, 0u);
    if (!sim_took(tally, cudaMemcpy(limbs.data(), total, bbp->out_limbs * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                  "engine: the sum read back"))
    {
        return 0;
    }
    anchor_exact_zero(sum);
    int zero = 1;
    for (unsigned int limb = 0u; limb < bbp->out_limbs; limb += 1u)
    {
        sum->limb[limb] = limbs[limb];
    }
    // W = 32 k - 1, so the sign's bit W is the top limb's top bit
    sum->limb[bbp->out_limbs - 1u] &= 0x7FFFFFFFu;
    for (unsigned int limb = 0u; limb < bbp->out_limbs; limb += 1u)
    {
        zero = zero && (sum->limb[limb] == 0u);
    }
    sum->sign = (zero != 0) ? 0 : 1;
    return 1;
}

// a progress line: the terms done, the rate, and what is left at that rate
static void pi_tower_bbp_progress(SimTally *tally, const PiTowerBbp *bbp, const PiTowerBbpRun *run)
{
    // a run's seconds are non-negative and far below 2^64 microseconds, so the floor fits the word
    const unsigned long long micros = (unsigned long long)(run->seconds * 1000000.0);
    const PiWide left = pi_tower_difference(bbp->terms, pi_tower_whole(run->done));
    scriptura_text(&tally->line, "    ");
    pi_tower_print_decimal(&tally->line, pi_tower_whole(run->done));
    scriptura_text(&tally->line, " of ");
    pi_tower_print_decimal(&tally->line, bbp->terms);
    scriptura_text(&tally->line, " terms in ");
    scriptura_decimal(&tally->line, run->sweeps, 1u);
    scriptura_text(&tally->line, " cycles and ");
    sim_fraction_print(&tally->line, micros, 1000000ull, 3u);
    scriptura_text(&tally->line, " s, ");
    pi_tower_print_exponent(&tally->line, pi_tower_product(pi_tower_whole(run->done), pi_tower_whole(1000000ull)),
                            pi_tower_whole((micros == 0ull) ? 1ull : micros));
    scriptura_text(&tally->line, " terms a second");
    if ((left.sign != 0) && (run->done != 0ull))
    {
        // the years left: left . micros / (done . 10^6 . 31557600)
        scriptura_text(&tally->line, "; ");
        pi_tower_print_exponent(&tally->line, left, pi_tower_whole(1ull));
        scriptura_text(&tally->line, " left, ");
        pi_tower_print_exponent(&tally->line, pi_tower_product(left, pi_tower_whole(micros)),
                                pi_tower_product(pi_tower_whole(run->done), pi_tower_whole(31557600000000ull)));
        scriptura_text(&tally->line, " years at this rate");
    }
    scriptura_character(&tally->line, '\n');
    sim_flush(tally);
}

// the run on the device: the tail's lanes reduced to the first total, then sweep after sweep of term lanes, each sweep
// one cycle of the term program over as many lanes as the device holds at once, reduced with the total carried in
static int pi_tower_bbp_sum(SimTally *tally, PiTowerBbp *bbp, int report, PiTowerBbpRun *run)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    memset(run, 0, sizeof(*run));
    unsigned int *inputs = NULL;
    unsigned int *rooms[2] = {NULL, NULL};
    unsigned int *index = NULL;
    unsigned int *total = NULL;
    const size_t sum_bytes = bbp->out_limbs * sizeof(unsigned int);
    const unsigned long long room_bytes = (bbp->lanes + 1ull) * sum_bytes;
    int good = (cycle_record_load(&bbp->term.layout, &bbp->term.record, &error) != CYCLE_REFUSED)
            && (cycle_record_load(&bbp->tail.layout, &bbp->tail.record, &error) != CYCLE_REFUSED)
            && (cycle_record_load(&bbp->pair.layout, &bbp->pair.record, &error) != CYCLE_REFUSED);
    sim_check(tally, good, "engine: the term, tail and pair programs load");
    good = good
        && sim_took(tally, cudaMalloc((void **)&inputs, bbp->lanes * bbp->in_limbs * sizeof(unsigned int)),
                    "engine: the lanes' inputs")
        && sim_took(tally, cudaMalloc((void **)&rooms[0], room_bytes), "engine: the sums")
        && sim_took(tally, cudaMalloc((void **)&rooms[1], room_bytes), "engine: the sums")
        && sim_took(tally, cudaMalloc((void **)&index, (bbp->lanes + 1ull) * sizeof(unsigned int)), "engine: the index")
        && sim_took(tally, cudaMalloc((void **)&total, sum_bytes), "engine: the total")
        && pi_tower_bbp_counted(tally, index, bbp->lanes + 1ull, 1u, 0ull)
        && pi_tower_bbp_counted(tally, inputs, bbp->tail_terms, 1u, 1ull);
    if (good != 0)
    {
        const CycleRecordRunRequest tail = {bbp->tail.record, {inputs, NULL, NULL}, {bbp->tail_terms, 0ull, 0ull},
                                            NULL,             bbp->tail_terms,      rooms[0],
                                            &error};
        good = cycle_record_run(&tail) != CYCLE_REFUSED;
        sim_check(tally, good, "engine: the tail program runs");
    }
    unsigned int *landed = (good != 0) ? pi_tower_bbp_reduce(tally, bbp, rooms, index, bbp->tail_terms, &error) : NULL;
    good = (landed != NULL)
        && sim_took(tally, cudaMemcpy(total, landed, sum_bytes, cudaMemcpyDeviceToDevice), "engine: the total");
    const std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    double next_report = 1.0;
    while ((good != 0) && (s_pi_tower_stopped == 0)
           && (pi_tower_compare(pi_tower_whole(run->done), bbp->terms) < 0))
    {
        const PiWide left = pi_tower_difference(bbp->terms, pi_tower_whole(run->done));
        const unsigned long long sweep = (pi_tower_compare(left, pi_tower_whole(bbp->lanes)) > 0) ? bbp->lanes
                                                                                                 : pi_tower_word(left);
        good = pi_tower_bbp_counted(tally, inputs, sweep, bbp->in_limbs, run->done);
        const CycleRecordRunRequest terms = {bbp->term.record, {inputs, NULL, NULL}, {sweep, 0ull, 0ull},
                                             NULL,             sweep,                rooms[0],
                                             &error};
        if ((good != 0) && (cycle_record_run(&terms) == CYCLE_REFUSED))
        {
            sim_check(tally, 0, "engine: the term program runs a sweep");
            good = 0;
        }
        good = good
            && sim_took(tally, cudaMemcpy(&rooms[0][sweep * bbp->out_limbs], total, sum_bytes, cudaMemcpyDeviceToDevice),
                        "engine: the total carried in");
        landed = (good != 0) ? pi_tower_bbp_reduce(tally, bbp, rooms, index, sweep + 1ull, &error) : NULL;
        good = (landed != NULL)
            && sim_took(tally, cudaMemcpy(total, landed, sum_bytes, cudaMemcpyDeviceToDevice), "engine: the total");
        run->done += (good != 0) ? sweep : 0ull;
        run->sweeps += (good != 0) ? 1ull : 0ull;
        run->seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
        if ((report != 0) && (run->seconds >= next_report))
        {
            pi_tower_bbp_progress(tally, bbp, run);
            next_report *= 2.0;
        }
    }
    run->finished = (good != 0) && (pi_tower_compare(pi_tower_whole(run->done), bbp->terms) == 0);
    good = good && ((run->finished == 0) || pi_tower_bbp_read(tally, bbp, total, &run->sum));
    cudaFree(inputs);
    cudaFree(rooms[0]);
    cudaFree(rooms[1]);
    cudaFree(index);
    cudaFree(total);
    cycle_record_release(bbp->term.record);
    cycle_record_release(bbp->tail.record);
    cycle_record_release(bbp->pair.record);
    bbp->term.record = NULL;
    bbp->tail.record = NULL;
    bbp->pair.record = NULL;
    return good;
}

// the leading bits every value within the error of the sum shares: the real {16^d pi} 2^W lies strictly within E units
// of the sum S, so floor(x / 2^(W - k)) is decided wherever S - E and S + E agree on it, and neither wraps
static unsigned int pi_tower_bbp_certified(const PiTowerBbp *bbp, const PiWide &sum)
{
    const PiWide error = pi_tower_bbp_error(bbp);
    const PiWide low = pi_tower_difference(sum, error);
    const PiWide high = pi_tower_sum(sum, error);
    if ((low.sign < 0) || (pi_tower_compare(high, pi_tower_power_two(bbp->fraction_bits)) >= 0))
    {
        return 0u;
    }
    unsigned int bits = bbp->fraction_bits;
    while ((bits > 0u)
           && (pi_tower_compare(pi_tower_quotient(low, pi_tower_power_two(bbp->fraction_bits - bits)),
                                pi_tower_quotient(high, pi_tower_power_two(bbp->fraction_bits - bits)))
               != 0))
    {
        bits -= 1u;
    }
    return bits;
}

// the first `digits` hex digits of the sum's fraction
static std::string pi_tower_bbp_hex(const PiTowerBbp *bbp, const PiWide &sum, unsigned int digits)
{
    std::string hex;
    for (unsigned int digit = 0u; digit < digits; digit += 1u)
    {
        const PiWide shifted = pi_tower_quotient(sum, pi_tower_power_two(bbp->fraction_bits - (4u * (digit + 1u))));
        hex.push_back("0123456789ABCDEF"[pi_tower_word(shifted) & 15ull]);
    }
    return hex;
}

// one run's line: its shape on the engine, how it went, and the digits it certified
static void pi_tower_bbp_print(SimTally *tally, const PiTowerBbp *bbp, const PiTowerBbpRun *run, unsigned int certified)
{
    scriptura_text(&tally->line, "    hex position ");
    pi_tower_print_decimal(&tally->line, bbp->position);
    scriptura_text(&tally->line, ": ");
    pi_tower_print_decimal(&tally->line, bbp->terms);
    scriptura_text(&tally->line, " term lanes of ");
    scriptura_decimal(&tally->line, bbp->term.layout.steps, 1u);
    scriptura_text(&tally->line, " steps on ");
    scriptura_decimal(&tally->line, bbp->term.layout.file_limbs, 1u);
    scriptura_text(&tally->line, " register limbs, ");
    scriptura_decimal(&tally->line, bbp->tail_terms, 1u);
    scriptura_text(&tally->line, " tail lanes, W ");
    scriptura_decimal(&tally->line, bbp->fraction_bits, 1u);
    scriptura_text(&tally->line, "; ");
    scriptura_decimal(&tally->line, run->sweeps, 1u);
    scriptura_text(&tally->line, " cycles of up to ");
    scriptura_decimal(&tally->line, bbp->lanes, 1u);
    scriptura_text(&tally->line, " lanes in ");
    // a run's seconds are non-negative and far below 2^64 microseconds, so the floor fits the word
    sim_fraction_print(&tally->line, (unsigned long long)(run->seconds * 1000000.0), 1000000ull, 3u);
    scriptura_text(&tally->line, " s");
    if (run->finished != 0)
    {
        scriptura_text(&tally->line, "; ");
        scriptura_decimal(&tally->line, certified, 1u);
        scriptura_text(&tally->line, " bits certified: ");
        scriptura_text(&tally->line, pi_tower_bbp_hex(bbp, run->sum, certified / 4u).c_str());
    }
    scriptura_character(&tally->line, '\n');
    sim_flush(tally);
}

// the lanes a sweep holds: every thread the device keeps resident at once
static unsigned long long pi_tower_bbp_lanes(void)
{
    int device = 0;
    cudaDeviceProp properties;
    if ((cudaGetDevice(&device) != cudaSuccess) || (cudaGetDeviceProperties(&properties, device) != cudaSuccess))
    {
        return 0ull;
    }
    // both counts are positive device properties
    return (unsigned long long)properties.multiProcessorCount * (unsigned long long)properties.maxThreadsPerMultiProcessor;
}

// Bailey's table of pi's hex digits, each at the position of its first digit (D. H. Bailey, "The BBP Algorithm for
// Pi", 2006, table 1), and the 23 digits his text gives from position 1,000,001
typedef struct
{
    unsigned long long position;
    const char *digits;
} PiTowerPublished;

static const PiTowerPublished s_pi_tower_published[] = {
    {1ull, "243F6A8885A308D3"},
    {1000000ull, "26C65E52CB4593"},
    {1000001ull, "6C65E52CB459350050E4BB1"},
    {10000000ull, "17AF5863EFED8D"},
    {100000000ull, "ECB840E21926EC"},
};

#define PI_TOWER_PUBLISHED_COUNT (sizeof(s_pi_tower_published) / sizeof(s_pi_tower_published[0]))

// the hex position whose window holds the turn at depth n, and the window's bits through it: the cell at 2^n is
// floor(alpha 2^n), and its low bits are alpha's bits n - 63 .. n, which the run from position floor((n - 64) / 4)
// holds within its first 67
static PiWide pi_tower_depth_position(const PiWide &depth, unsigned int *window)
{
    const PiWide reach = pi_tower_whole(64ull);
    if (pi_tower_compare(depth, reach) <= 0)
    {
        // at most 64
        *window = (unsigned int)pi_tower_word(depth);
        return pi_tower_whole(0ull);
    }
    const PiWide position = pi_tower_quotient(pi_tower_difference(depth, reach), pi_tower_whole(4ull));
    // depth - 4 d is 64 to 67
    *window = (unsigned int)pi_tower_word(pi_tower_difference(depth, pi_tower_product(position, pi_tower_whole(4ull))));
    return position;
}

// the low 64 bits of the engine's cell at depth n: the window's first `window` bits
static unsigned long long pi_tower_bbp_cell(const PiTowerBbp *bbp, const PiWide &sum, unsigned int window)
{
    return pi_tower_word(pi_tower_quotient(sum, pi_tower_power_two(bbp->fraction_bits - window)));
}

// how a segment went: whether every window ran, every window was summed, and every overlap agreed
typedef struct
{
    int ran;
    int finished;
    int certified;
    int overlapped;
    unsigned int windows;
} PiTowerSegment;

// the bytes a segment's largest window holds on the device: its last, whose position and widths are the largest
static int pi_tower_segment_declared(const PiWide &position, unsigned int digits, unsigned long long lanes,
                                     unsigned long long *declared, EngineError *error)
{
    const unsigned int windows = (digits + PI_TOWER_SEGMENT_STEP - 1u) / PI_TOWER_SEGMENT_STEP;
    const PiWide last = pi_tower_sum(position, pi_tower_whole((unsigned long long)(windows - 1u) * PI_TOWER_SEGMENT_STEP));
    PiTowerBbp bbp;
    if (pi_tower_bbp_plan(&bbp, last, lanes, error) == 0)
    {
        return 0;
    }
    const unsigned long long bytes = pi_tower_bbp_bytes(&bbp);
    *declared = (bytes > *declared) ? bytes : *declared;
    pi_tower_bbp_free(&bbp);
    return 1;
}

// 15. A segment of `digits` hex digits from hex position d + 1, read as windows at d, d + 24, d + 48, ..., each its own
// run on the engine. Each window must certify its 24 digits, and the digits it certifies past them must be the next
// window's first (Bailey: "a result calculated at position d can be checked by repeating at position d - 1").
static PiTowerSegment pi_tower_bbp_segment(SimTally *tally, const PiWide &position, unsigned int digits,
                                           unsigned long long lanes, int report, std::string *segment)
{
    PiTowerSegment result = {1, 1, 1, 1, 0u};
    EngineError error;
    memset(&error, 0, sizeof(error));
    segment->clear();
    std::string pending;
    while ((result.ran != 0) && (result.finished != 0) && (segment->size() < digits))
    {
        const PiWide window = pi_tower_sum(position, pi_tower_whole((unsigned long long)result.windows * PI_TOWER_SEGMENT_STEP));
        PiTowerBbp bbp;
        if (pi_tower_bbp_plan(&bbp, window, lanes, &error) == 0)
        {
            result.ran = 0;
            break;
        }
        PiTowerBbpRun run;
        result.ran = pi_tower_bbp_sum(tally, &bbp, report, &run);
        result.finished = (result.ran != 0) && (run.finished != 0);
        const unsigned int certified = (result.finished != 0) ? pi_tower_bbp_certified(&bbp, run.sum) : 0u;
        if (report != 0)
        {
            pi_tower_bbp_print(tally, &bbp, &run, certified);
        }
        if (result.finished != 0)
        {
            result.windows += 1u;
            const std::string read = pi_tower_bbp_hex(&bbp, run.sum, certified / 4u);
            result.certified = result.certified && (read.size() >= PI_TOWER_SEGMENT_STEP);
            result.overlapped = result.overlapped && (read.compare(0u, pending.size(), pending) == 0);
            const size_t taken = ((digits - segment->size()) < PI_TOWER_SEGMENT_STEP) ? (digits - segment->size())
                                                                                     : PI_TOWER_SEGMENT_STEP;
            segment->append(read, 0u, taken);
            pending = (read.size() > PI_TOWER_SEGMENT_STEP) ? read.substr(PI_TOWER_SEGMENT_STEP) : std::string();
        }
        pi_tower_bbp_free(&bbp);
    }
    return result;
}

// a segment's digits, 64 to a line, each line headed by the position of its first digit
static void pi_tower_segment_print(SimTally *tally, const PiWide &position, const std::string &segment)
{
    for (size_t at = 0u; at < segment.size(); at += 64u)
    {
        scriptura_text(&tally->line, "    ");
        pi_tower_print_decimal(&tally->line, pi_tower_sum(position, pi_tower_whole((unsigned long long)at + 1ull)));
        scriptura_text(&tally->line, "  ");
        scriptura_text(&tally->line, segment.substr(at, 64u).c_str());
        scriptura_character(&tally->line, '\n');
        sim_flush(tally);
    }
}

// 13, 14 and 15 on the engine: position 0 and Bailey's, the tower's deepest resolution asked for, and segments at 0
// and at 10^6
static void pi_tower_engine(SimTally *tally, int count, char **arguments, const PiTowerTurn &turn, unsigned int depth)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned long long lanes = pi_tower_bbp_lanes();
    unsigned int window = 0u;
    const PiWide tower_position = pi_tower_depth_position(pi_tower_whole(depth), &window);
    std::vector<PiTowerBbp> plans(PI_TOWER_PUBLISHED_COUNT + 1u);
    int planned = lanes != 0ull;
    unsigned long long declared = 0ull;
    for (size_t at = 0u; (planned != 0) && (at < plans.size()); at += 1u)
    {
        const PiWide position = (at < PI_TOWER_PUBLISHED_COUNT)
                              ? pi_tower_whole(s_pi_tower_published[at].position - 1ull)
                              : tower_position;
        planned = pi_tower_bbp_plan(&plans[at], position, lanes, &error);
        const unsigned long long bytes = (planned != 0) ? pi_tower_bbp_bytes(&plans[at]) : 0ull;
        declared = (bytes > declared) ? bytes : declared;
    }
    sim_check(tally, planned, "engine: keymath imprints and the scheduler lays the term, tail and pair programs");
    if ((planned == 0) || !sim_job_submit(tally, "pi_tower", count, arguments, declared))
    {
        for (size_t at = 0u; at < plans.size(); at += 1u)
        {
            pi_tower_bbp_free(&plans[at]);
        }
        return;
    }
    scriptura_text(&tally->line, "  on the engine, pi's hex digits by BBP, each term a lane of the record machine\n");
    sim_flush(tally);
    int published = 1;
    int finished = 1;
    for (size_t at = 0u; at < PI_TOWER_PUBLISHED_COUNT; at += 1u)
    {
        PiTowerBbpRun run;
        const int ran = pi_tower_bbp_sum(tally, &plans[at], 0, &run);
        const unsigned int certified = (ran != 0) ? pi_tower_bbp_certified(&plans[at], run.sum) : 0u;
        pi_tower_bbp_print(tally, &plans[at], &run, certified);
        const std::string expected = s_pi_tower_published[at].digits;
        finished = finished && ran && run.finished;
        // a published string is at most 23 digits, so its length fits an unsigned int
        published = published && ran && run.finished && ((4u * expected.size()) <= certified)
                 && (pi_tower_bbp_hex(&plans[at], run.sum, (unsigned int)expected.size()) == expected);
    }
    sim_check(tally, finished, "engine: every run sums all its terms");
    sim_check(tally, published,
              "on the engine, pi's first 64 bits are 0x243F6A8885A308D3 and its hex digits at Bailey's positions 10^6, 10^6 + 1, 10^7 and 10^8 are his");
    PiTowerBbpRun run;
    PiTowerBbp *const tower = &plans[PI_TOWER_PUBLISHED_COUNT];
    const int ran = pi_tower_bbp_sum(tally, tower, 0, &run);
    const unsigned int certified = (ran != 0) ? pi_tower_bbp_certified(tower, run.sum) : 0u;
    pi_tower_bbp_print(tally, tower, &run, certified);
    const unsigned long long engine_cell = (ran != 0) ? pi_tower_bbp_cell(tower, run.sum, window) : 0ull;
    const unsigned long long exact_cell
        = pi_tower_word(pi_tower_quotient(turn.multiplier, pi_tower_power_two(turn.precision - depth)));
    scriptura_text(&tally->line, "    the cell at 2^");
    scriptura_decimal(&tally->line, depth, 1u);
    scriptura_text(&tally->line, ", its low 64 bits: engine 0x");
    scriptura_hex(&tally->line, engine_cell, 16u);
    scriptura_text(&tally->line, ", exact turn 0x");
    scriptura_hex(&tally->line, exact_cell, 16u);
    scriptura_character(&tally->line, '\n');
    sim_check(tally, ran && run.finished && (certified >= window) && (engine_cell == exact_cell),
              "the engine's cell at the deepest resolution asked for, its low 64 bits, is the exact turn's");
    for (size_t at = 0u; at < plans.size(); at += 1u)
    {
        pi_tower_bbp_free(&plans[at]);
    }
    sim_flush(tally);
}

// a resolution past the exact turn's: held as (2, n), every part that does not ask for pi's bits printed exact, and
// the depth-n turn summed on the engine sweep by sweep until every term is in or the run is stopped
static void pi_tower_deep(SimTally *tally, int count, char **arguments, const PiWide &depth)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const PiWide word = pi_tower_whole(64ull);
    const PiWide precision = pi_tower_product(
        pi_tower_quotient(pi_tower_sum(pi_tower_sum(pi_tower_product(depth, pi_tower_whole(3ull)), word),
                                       pi_tower_whole(63ull)),
                          word),
        word);
    const PiWide needed = pi_tower_sum(
        pi_tower_product(pi_tower_sum(precision, pi_tower_whole(PI_TOWER_GUARD)), pi_tower_whole(3ull)), word);
    // the exact width a host turn would need, as a power of two of limbs
    unsigned int width = 0u;
    while (pi_tower_compare(pi_tower_product(pi_tower_power_two(width), pi_tower_whole(32ull)), needed) < 0)
    {
        width += 1u;
    }
    scriptura_text(&tally->line, "  resolution (2, n): 2^n cells, n = ");
    pi_tower_print_decimal(&tally->line, depth);
    scriptura_text(&tally->line, "\n    the turn's precision P = ");
    pi_tower_print_decimal(&tally->line, precision);
    scriptura_text(&tally->line, " bits; a host turn would need an exact width of ");
    pi_tower_print_decimal(&tally->line, needed);
    scriptura_text(&tally->line, " bits, SIM_EXACT_LIMBS = 2^");
    scriptura_decimal(&tally->line, width, 1u);
    scriptura_character(&tally->line, '\n');
    sim_flush(tally);
    unsigned int window = 0u;
    const PiWide position = pi_tower_depth_position(depth, &window);
    PiTowerBbp bbp;
    const unsigned long long lanes = pi_tower_bbp_lanes();
    const int planned = (lanes != 0ull) && pi_tower_bbp_plan(&bbp, position, lanes, &error);
    sim_check(tally, planned, "engine: keymath imprints and the scheduler lays the term, tail and pair programs");
    if (planned == 0)
    {
        return;
    }
    if (!sim_job_submit(tally, "pi_tower", count, arguments, pi_tower_bbp_bytes(&bbp)))
    {
        pi_tower_bbp_free(&bbp);
        return;
    }
    scriptura_text(&tally->line, "    the turn at depth n is alpha's bit n: its cell's low bits are the window from hex position ");
    pi_tower_print_decimal(&tally->line, position);
    scriptura_text(&tally->line, ", on the engine\n");
    sim_flush(tally);
    s_pi_tower_stopped = 0;
    void (*const was)(int) = signal(SIGINT, pi_tower_stop);
    PiTowerBbpRun run;
    const int ran = pi_tower_bbp_sum(tally, &bbp, 1, &run);
    signal(SIGINT, was);
    pi_tower_bbp_progress(tally, &bbp, &run);
    const unsigned int certified = ((ran != 0) && (run.finished != 0)) ? pi_tower_bbp_certified(&bbp, run.sum) : 0u;
    pi_tower_bbp_print(tally, &bbp, &run, certified);
    if ((run.finished != 0) && (certified >= window))
    {
        scriptura_text(&tally->line, "    the cell at 2^n, its low 64 bits: 0x");
        scriptura_hex(&tally->line, pi_tower_bbp_cell(&bbp, run.sum, window), 16u);
        scriptura_character(&tally->line, '\n');
    }
    else if (run.finished == 0)
    {
        scriptura_text(&tally->line, "    stopped: no digit at depth n is printed until every term is summed\n");
    }
    sim_check(tally, ran, "engine: every sweep the run made summed on the record machine");
    sim_check(tally, (run.finished == 0) || (certified >= window),
              "a finished run certifies the window through depth n");
    pi_tower_bbp_free(&bbp);
    sim_flush(tally);
}

static void pi_tower_fill(SimTally *tally, const PiTowerTurn &turn, const std::vector<PiWide> &denominators,
                          const std::vector<PiWide> &floors, unsigned int from_bits, unsigned int to_bits,
                          const PiWide &walk_alpha);

// a whole number of decimal digits, from the text up to the first character that is not one; 0 where there are none
static int pi_tower_digits(const char **text, PiWide *value)
{
    const PiWide ten = pi_tower_whole(10ull);
    *value = pi_tower_whole(0ull);
    const char *walk = *text;
    while ((*walk >= '0') && (*walk <= '9'))
    {
        // one decimal digit, 0 to 9
        *value = pi_tower_sum(pi_tower_product(*value, ten), pi_tower_whole((unsigned long long)(*walk - '0')));
        walk += 1;
    }
    const int read = walk != *text;
    *text = walk;
    return read;
}

// n from the request, whole or as base^exponent, the base and its operation kept apart until n is formed; 0 where the
// text is neither, n is 0, or n outgrows the exact width
static int pi_tower_request(const char *text, PiWide *value)
{
    if (text == NULL)
    {
        return 0;
    }
    s_pi_tower_refused = 0;
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
        if ((pi_tower_digits(&walk, &exponent) == 0)
            || (pi_tower_compare(exponent, pi_tower_whole(ANCHOR_EXACT_BITS)) > 0))
        {
            return 0;
        }
        // base^exponent by squaring, over the exponent's bits from the top
        *value = pi_tower_whole(1ull);
        for (unsigned int bit = pi_tower_bit_length(exponent); (bit > 0u) && (s_pi_tower_refused == 0); bit -= 1u)
        {
            *value = pi_tower_product(*value, *value);
            if (((exponent.limb[(bit - 1u) / 32u] >> ((bit - 1u) % 32u)) & 1u) != 0u)
            {
                *value = pi_tower_product(*value, base);
            }
        }
    }
    return (*walk == '\0') && (value->sign != 0) && (s_pi_tower_refused == 0);
}

// a resolution from the request, from 1 to 2^20
static int pi_tower_resolution(const char *text, unsigned int *bits)
{
    PiWide value;
    if ((pi_tower_request(text, &value) == 0) || (pi_tower_compare(value, pi_tower_whole(PI_TOWER_EXACT_MOST)) > 0))
    {
        return 0;
    }
    // at most 2^20, so an unsigned int holds it
    *bits = (unsigned int)pi_tower_word(value);
    return 1;
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    unsigned int from_bits = PI_TOWER_RESOLUTION_FIRST;
    unsigned int to_bits = PI_TOWER_RESOLUTION_LAST;
    const int single = (count == 2) && pi_tower_resolution(arguments[1], &from_bits);
    const int ranged = (count == 3) && pi_tower_resolution(arguments[1], &from_bits)
                    && pi_tower_resolution(arguments[2], &to_bits) && (from_bits <= to_bits);
    if (single != 0)
    {
        to_bits = from_bits;
    }
    PiWide deep;
    if ((count == 2) && (single == 0) && (pi_tower_request(arguments[1], &deep) != 0))
    {
        pi_tower_deep(&tally, count, arguments, deep);
        return sim_close(&tally, "pi tower");
    }
    if ((count > 1) && (single == 0) && (ranged == 0))
    {
        scriptura_text(&tally.line, "  usage: pi_tower [n] or pi_tower [from] [to], resolutions 2^1 to 2^1048576 cells; pi_tower n\n  past 2^20, n whole or base^exponent, reads the depth-n turn on the engine alone\n");
        sim_check(&tally, 0, "the request names its resolutions");
        return sim_close(&tally, "pi tower");
    }
    // P = 3 n + 64 rounded up to a word, at least the walks' 384
    unsigned int precision = (((3u * to_bits) + 64u + 63u) / 64u) * 64u;
    precision = (precision < PI_TOWER_BITS) ? PI_TOWER_BITS : precision;
    const unsigned long long needed = (3ull * (precision + PI_TOWER_GUARD)) + 64ull;
    scriptura_text(&tally.line, "  resolutions 2^");
    scriptura_decimal(&tally.line, from_bits, 1u);
    scriptura_text(&tally.line, " to 2^");
    scriptura_decimal(&tally.line, to_bits, 1u);
    scriptura_text(&tally.line, " cells, the turn held to ");
    scriptura_decimal(&tally.line, precision, 1u);
    scriptura_text(&tally.line, " bits, in an exact width of ");
    scriptura_decimal(&tally.line, (unsigned long long)ANCHOR_EXACT_BITS, 1u);
    scriptura_text(&tally.line, " bits\n");
    if (needed > (unsigned long long)ANCHOR_EXACT_BITS)
    {
        unsigned long long limbs = 1ull;
        while ((limbs * 32ull) < needed)
        {
            limbs *= 2ull;
        }
        scriptura_text(&tally.line, "  the turn needs an exact width of ");
        scriptura_decimal(&tally.line, needed, 1u);
        scriptura_text(&tally.line, " bits: run with SIM_EXACT_LIMBS=");
        scriptura_decimal(&tally.line, limbs, 1u);
        scriptura_character(&tally.line, '\n');
        sim_check(&tally, 0, "the exact width holds the turn the resolutions ask for");
        return sim_close(&tally, "pi tower");
    }
    PiTowerTurn turn;
    PiWide pi_low;
    PiWide pi_high;
    if (pi_tower_bracket(&tally, precision, &turn.multiplier, &pi_low, &pi_high) == 0)
    {
        return sim_close(&tally, "pi tower");
    }
    pi_tower_arc(&tally, pi_low, pi_high, precision + PI_TOWER_GUARD);
    turn.modulus = pi_tower_power_two(precision);
    turn.precision = precision;
    turn.reach = ((to_bits + PI_TOWER_RECORD_MARGIN) > PI_TOWER_RECORD_BITS) ? (to_bits + PI_TOWER_RECORD_MARGIN)
                                                                              : PI_TOWER_RECORD_BITS;
    turn.lowest = pi_tower_records(turn, 1);
    turn.highest = pi_tower_records(turn, 0);
    // the walks' turn, floor(alpha 2^384): a floor of a floor is the floor
    const PiWide walk_alpha = pi_tower_quotient(turn.multiplier, pi_tower_power_two(precision - PI_TOWER_BITS));
    std::vector<PiWide> denominators;
    std::vector<PiWide> floors;
    pi_tower_floors(&tally, turn, &denominators, &floors);
    pi_tower_residues(&tally, walk_alpha, denominators, floors);
    pi_tower_golden(&tally, turn, denominators, floors);
    pi_tower_billiard(&tally, walk_alpha, denominators);
    pi_tower_fill(&tally, turn, denominators, floors, from_bits, to_bits, walk_alpha);
    pi_tower_engine(&tally, count, arguments, turn, to_bits);
    return sim_close(&tally, "pi tower");
}

// 4, 5 and 6. at each resolution, the step that fills the boundary: the least count of steps whose points touch every
// cell, found by doubling and halving on the three gap test
static void pi_tower_fill(SimTally *tally, const PiTowerTurn &turn, const std::vector<PiWide> &denominators,
                          const std::vector<PiWide> &floors, unsigned int from_bits, unsigned int to_bits,
                          const PiWide &walk_alpha)
{
    const PiWide one = pi_tower_whole(1ull);
    const PiWide two = pi_tower_whole(2ull);
    int certain = 1;
    int walked = 1;
    int touched = 1;
    int found_home = 1;
    unsigned int same_period = 0u;
    unsigned int walks = 0u;
    const unsigned int walks_expected = (from_bits > PI_TOWER_WALK_MOST)
                                          ? 0u
                                          : (((to_bits < PI_TOWER_WALK_MOST) ? to_bits : PI_TOWER_WALK_MOST) - from_bits + 1u);
    scriptura_text(&tally->line, "  2^k cells: the step that fills the boundary, its ratio to the cells, the last cell filled as a place on the circle, and the floor it fills on\n");
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
        const int homed = pi_tower_first_hit_from(turn.multiplier, turn.modulus, covering, pi_tower_whole(0ull),
                                                  pi_tower_difference(cell, one), &home);
        found_home = found_home && homed;
        // and the fill's last cell etched again after that: the second run's close
        PiWide closing;
        const PiWide closing_low = pi_tower_product(last, cell);
        const int closed = (homed != 0)
                        && pi_tower_first_hit_from(turn.multiplier, turn.modulus, pi_tower_sum(home, one), closing_low,
                                                   pi_tower_difference(pi_tower_sum(closing_low, cell), one), &closing);
        found_home = found_home && closed;
        const PiWide reach = (closed != 0) ? pi_tower_sum(closing, one) : covering;

        // the integer turn is the real one on every step below reach: step n's real place lies in
        // (n A, n A + n), which crosses into the next cell only where (n A mod cell) > cell - n
        PiWide unsure;
        const PiWide multiplier = pi_tower_remainder(turn.multiplier, cell);
        const int wanders = pi_tower_first_hit(multiplier, cell, pi_tower_sum(pi_tower_difference(cell, reach), one),
                                               pi_tower_difference(cell, one), &unsure)
                         && (pi_tower_compare(unsure, reach) < 0);
        certain = certain && (wanders == 0);

        PiWide first;
        const PiWide low = pi_tower_product(last, cell);
        touched = touched && pi_tower_first_hit(turn.multiplier, turn.modulus, low,
                                                pi_tower_difference(pi_tower_sum(low, cell), one), &first)
               && (pi_tower_compare(first, fill) == 0);

        size_t level = 0u;
        while (((level + 1u) < denominators.size()) && (pi_tower_compare(denominators[level + 1u], fill) <= 0))
        {
            level += 1u;
        }
        scriptura_text(&tally->line, "    2^");
        scriptura_decimal(&tally->line, bits, 1u);
        scriptura_text(&tally->line, "  step ");
        pi_tower_print_exponent(&tally->line, fill, one);
        scriptura_text(&tally->line, " = ");
        pi_tower_print_decimal(&tally->line, fill);
        scriptura_text(&tally->line, "  x");
        sim_ratio_print(&tally->line, &fill, &cells, 4u);
        scriptura_text(&tally->line, "  last cell at ");
        sim_ratio_print(&tally->line, &last, &cells, 12u);
        scriptura_text(&tally->line, "  floor ");
        scriptura_decimal(&tally->line, level, 1u);
        if ((level + 1u) < floors.size())
        {
            scriptura_text(&tally->line, " (a ");
            pi_tower_print_decimal(&tally->line, floors[level + 1u]);
            scriptura_character(&tally->line, ')');
        }
        if (homed != 0)
        {
            scriptura_text(&tally->line, "  cell 0 again at step ");
            pi_tower_print_decimal(&tally->line, home);
            scriptura_text(&tally->line, ", ");
            pi_tower_print_decimal(&tally->line, pi_tower_difference(home, fill));
            scriptura_text(&tally->line, " after the fill");
        }
        if (closed != 0)
        {
            const PiWide second = pi_tower_difference(closing, home);
            const int order = pi_tower_compare(second, fill);
            scriptura_text(&tally->line, "; the last cell again at step ");
            pi_tower_print_decimal(&tally->line, closing);
            scriptura_text(&tally->line, ", ");
            pi_tower_print_decimal(&tally->line, second);
            scriptura_text(&tally->line, " after cell 0: ");
            if (order == 0)
            {
                scriptura_text(&tally->line, "the same period");
                same_period += 1u;
            }
            else
            {
                pi_tower_print_decimal(&tally->line, (order < 0) ? pi_tower_difference(fill, second)
                                                                 : pi_tower_difference(second, fill));
                scriptura_text(&tally->line, (order < 0) ? " shorter" : " longer");
            }
        }
        if (bits <= PI_TOWER_WALK_MOST)
        {
            unsigned long long walked_last = 0ull;
            unsigned long long stall = 0ull;
            unsigned long long again = 0ull;
            unsigned long long walked_home = 0ull;
            unsigned long long walked_closing = 0ull;
            const unsigned long long walked_fill = pi_tower_walk(walk_alpha, bits, &walked_last, &stall, &again,
                                                                 &walked_home, &walked_closing);
            walked = walked && (walked_fill == pi_tower_word(fill)) && (walked_last == pi_tower_word(last))
                  && (closed != 0) && (walked_home == pi_tower_word(home))
                  && (walked_closing == pi_tower_word(closing));
            walks += 1u;
            scriptura_text(&tally->line, "  walked ");
            scriptura_decimal(&tally->line, walked_fill, 1u);
            scriptura_text(&tally->line, ", longest stall ");
            scriptura_decimal(&tally->line, stall, 1u);
            scriptura_text(&tally->line, ", etched again by ");
            scriptura_decimal(&tally->line, again, 1u);
        }
        scriptura_character(&tally->line, '\n');
        sim_flush(tally);
    }
    sim_check(tally, certain, "the integer turn lands in the real turn's cell on every step searched, at every resolution");
    sim_check(tally, walked && (walks == walks_expected),
              "the step, the last cell and cell 0's next etch read from the floors equal a walk of every step, at every resolution asked for up to 2^24 cells");
    sim_check(tally, found_home,
              "at every resolution cell 0 is etched again after the fill, then the fill's last cell, at steps the floors name");
    sim_check(tally, s_pi_tower_records_short == 0, "every count searched stands within the records' reach");
    scriptura_text(&tally->line, "  the second run, cell 0 to the first run's last cell, has the first run's period at ");
    scriptura_decimal(&tally->line, same_period, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, (to_bits - from_bits) + 1u, 1u);
    scriptura_text(&tally->line, " resolutions\n");
    sim_flush(tally);
    sim_check(tally, touched, "at every resolution the last cell's first touch is the step that fills the boundary");
    sim_check(tally, s_pi_tower_refused == 0, "no exact operation outgrew the width");
}
