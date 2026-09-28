// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_tower_billiard.cu: word arithmetic and the billiard
#include "pi_tower_internal.h"

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
void pi_tower_billiard(SimResults *results, const PiWide &alpha, const std::vector<PiWide> &denominators)
{
    unsigned long long increment[PI_TOWER_WORDS];
    unsigned long long twice[PI_TOWER_WORDS];
    unsigned long long single[PI_TOWER_WORDS];
    unsigned long long odd[PI_TOWER_WORDS];
    unsigned long long nearest[PI_TOWER_WORDS];
    unsigned long long closest[PI_TOWER_WORDS];
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        increment[word] =
            ((unsigned long long)alpha.limb[(2u * word) + 1u] << 32u) | (unsigned long long)alpha.limb[2u * word];
        single[word] = 0ull;
        odd[word] = increment[word];
        nearest[word] = ~0ull;
        closest[word] = ~0ull;
        twice[word] = increment[word];
    }
    const unsigned long long twice_carry = pi_tower_words_add(twice, increment);
    const unsigned long long columns = 1ull << PI_TOWER_BILLIARD_BITS;
    // floor(alpha i) and floor(alpha (2i + 1)); A is below 2^P. Both start at 0
    unsigned long long single_integer = 0ull;
    unsigned long long odd_integer = 0ull;
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
        const unsigned long long next_integer = single_integer + pi_tower_words_add(next, increment);
        // the real n alpha 2^P lies in (n A, n A + n): with the top word short of all ones, n < 2^320 cannot carry it
        // past a whole. The floor read from the carries is the real floor
        uncertain += ((next[PI_TOWER_WORDS - 1u] == ~0ull) || (odd[PI_TOWER_WORDS - 1u] == ~0ull)) ? 1ull : 0ull;
        corners += (pi_tower_words_zero(next) != 0) ? 1ull : 0ull;
        zero += (pi_tower_words_zero(odd) != 0) ? 1ull : 0ull;
        const unsigned long long bottom = (3ull * column) + single_integer;
        const unsigned long long top = (3ull * (column + 1ull)) + next_integer;
        for (unsigned long long row = bottom; row <= top; row += 1ull)
        {
            // L = (-1)^(i + j) (d - alpha (2i + 1)) / 2, d = (2j + 1) - 3 (2i + 1) whole; the rows and 3 (2i + 1)
            // stay below 2^27 at 2^24 columns. Each fits a signed word
            const long long range = (long long)((2ull * row) + 1ull) - (long long)(3ull * ((2ull * column) + 1ull));
            // alpha (2i + 1) lies strictly between odd_integer and odd_integer + 1. D stands above it exactly when
            // d > odd_integer, which fits a signed word for the same reason
            const int above = range > (long long)odd_integer;
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
            // the nearest tie: |d - alpha (2i + 1)| below 1 when d is odd_integer or odd_integer + 1
            unsigned long long distance[PI_TOWER_WORDS];
            int near = 0;
            if (range == (long long)odd_integer)
            {
                for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
                {
                    distance[word] = odd[word];
                }
                near = 1;
            }
            else if (range == ((long long)odd_integer + 1ll))
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
        single_integer = next_integer;
        odd_integer += pi_tower_words_add(odd, twice) + twice_carry;
    }
    longest = (run > longest) ? run : longest;
    size_t floors_in_walk = 0u;
    while ((floors_in_walk < denominators.size()) &&
           (pi_tower_compare(denominators[floors_in_walk], pi_tower_unsigned(columns)) <= 0))
    {
        floors_in_walk += 1u;
    }
    int matched = near_corners.size() == floors_in_walk;
    for (size_t at = 0u; (at < near_corners.size()) && (at < floors_in_walk); at += 1u)
    {
        matched = matched && (near_corners[at] == pi_tower_word(denominators[at]));
    }
    scriptura_text(&results->line, "  the billiard from the corner at slope pi, 2^");
    scriptura_decimal(&results->line, PI_TOWER_BILLIARD_BITS, 1u);
    scriptura_text(&results->line, " columns: ");
    scriptura_decimal(&results->line, segments, 1u);
    scriptura_text(&results->line, " segments between ");
    scriptura_decimal(&results->line, vertical, 1u);
    scriptura_text(&results->line, " side-wall and ");
    scriptura_decimal(&results->line, horizontal, 1u);
    scriptura_text(&results->line, " floor-wall hits, ");
    scriptura_decimal(&results->line, corners, 1u);
    scriptura_text(&results->line, " corners\n    the lead in L about the center changed hands ");
    scriptura_decimal(&results->line, changes, 1u);
    scriptura_text(&results->line, " times, the longest lead ");
    scriptura_decimal(&results->line, longest, 1u);
    scriptura_text(&results->line, " segments, one side ahead on ");
    scriptura_decimal(&results->line, ahead, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, segments, 1u);
    scriptura_text(&results->line, "\n    the nearest tie: |L| = ");
    pi_tower_print_exponent(&results->line, pi_tower_words_wide(nearest), pi_tower_power_two(PI_TOWER_BITS + 1u));
    scriptura_text(&results->line, " (p = (1, pi)) in cell (");
    scriptura_decimal(&results->line, nearest_column, 1u);
    scriptura_text(&results->line, ", ");
    scriptura_decimal(&results->line, nearest_row, 1u);
    scriptura_text(&results->line, "), where pi stands nearest ");
    scriptura_decimal(&results->line, (2ull * nearest_row) + 1ull, 1u);
    scriptura_character(&results->line, '/');
    scriptura_decimal(&results->line, (2ull * nearest_column) + 1ull, 1u);
    scriptura_text(&results->line, "\n    the record near-corners at the side walls: ");
    for (size_t at = 0u; at < near_corners.size(); at += 1u)
    {
        scriptura_decimal(&results->line, near_corners[at], 1u);
        scriptura_text(&results->line, (at + 1u < near_corners.size()) ? ", " : "\n");
    }
    // pi is irrational. No corner and no zero L can occur on the real walk; what these two checks measure is that
    // the integer turn's carries decide every floor (uncertain is 0). The walk read is the real one
    sim_check(results, (corners == 0ull) && (uncertain == 0ull),
              "no wall hit on the walk is a corner, and every floor on it is the real floor: one wall always wins");
    sim_check(results, (zero == 0ull) && (uncertain == 0ull),
              "no segment's angular momentum about the center is zero: one sense always leads");
    sim_check(results, matched && (floors_in_walk > 10u), "the walk's record near-corners are exactly the floors' q_j");
    sim_flush(results);
}

// 11. The residue (Doug, 24 September: "if qa is almost a whole number, we can get its identity and its null
// permutation will make it a whole, that is its residue"). On floor j, q_j alpha = p_j + delta_j. Put p_j / q_j for
// alpha and the turn is the permutation n -> n p_j mod q_j of q_j cells, whole again after q_j steps: the identity.
// Where q_j |delta_j| < 1, pi's whole parts for n < q_j are the permutation's, floor(n alpha) = floor(n p_j / q_j),
// each point carried n delta_j / q_j off the permutation's mark, past it where delta_j > 0 and short of it where
// delta_j < 0 (so into the right-closed cell), and at n = q_j pi stands at P + delta_j where the permutation is whole:
// the residue. Walked on the 384-bit turn, the whole parts read from its carries, on every floor with q_j at most
// 2^PI_TOWER_RESIDUE_BITS.
void pi_tower_residues(SimResults *results, const PiWide &walk_alpha, const std::vector<PiWide> &denominators,
                       const std::vector<PiWide> &floors)
{
    const PiWide modulus = pi_tower_power_two(PI_TOWER_BITS);
    const PiWide limit = pi_tower_power_two(PI_TOWER_RESIDUE_BITS);
    unsigned long long increment[PI_TOWER_WORDS];
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        increment[word] = ((unsigned long long)walk_alpha.limb[(2u * word) + 1u] << 32u) |
                          (unsigned long long)walk_alpha.limb[2u * word];
    }
    int ok = 1;
    int certain = 1;
    unsigned int walked = 0u;
    // p_(j-2) and p_(j-1), from p_(-1) = 1 and p_0 = 0
    unsigned long long numerator_before = 1ull;
    unsigned long long numerator = 0ull;
    scriptura_text(&results->line, "  the residue: floor j, pi's identity P/q, the residue q pi - P, and q steps "
                                   "walked as the permutation n -> n p mod q\n");
    for (size_t at = 0u; (at < denominators.size()) && (pi_tower_compare(denominators[at], limit) <= 0); at += 1u)
    {
        if (at > 0u)
        {
            // a_j p_(j-1) + p_(j-2): each p_j is below q_j, below 2^21. The words hold them
            const unsigned long long next = (pi_tower_word(floors[at]) * numerator) + numerator_before;
            numerator_before = numerator;
            numerator = next;
        }
        const unsigned long long steps = pi_tower_word(denominators[at]);
        const PiWide residue = pi_tower_difference(pi_tower_product(denominators[at], walk_alpha),
                                                   pi_tower_product(pi_tower_unsigned(numerator), modulus));
        const int negative = residue.sign < 0;
        PiWide size = residue;
        size.sign = (residue.sign == 0) ? 0 : 1;
        // the real residue lies in (qA - pM, qA - pM + q); the integer whole parts are the real ones and each point
        // stays in its cell when q (size + q) < M where delta > 0, and q size < M with size >= q where delta < 0
        const PiWide q = denominators[at];
        certain =
            certain && ((negative == 0) ? (pi_tower_compare(pi_tower_product(q, pi_tower_sum(size, q)), modulus) < 0)
                                        : ((pi_tower_compare(pi_tower_product(q, size), modulus) < 0) &&
                                           (pi_tower_compare(size, q) >= 0)));
        unsigned long long place[PI_TOWER_WORDS];
        for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
        {
            place[word] = 0ull;
        }
        unsigned long long integer_sum = 0ull;
        int floor_ok = 1;
        for (unsigned long long step = 0ull; step < steps; step += 1ull)
        {
            // n p < 2^42. The permutation's whole part is a word's quotient
            floor_ok = floor_ok && (integer_sum == ((step * numerator) / steps));
            integer_sum += pi_tower_words_add(place, increment);
        }
        // at n = q the walk stands at the residue: whole P past 3 q, and delta past it, or whole P - 1 and |delta|
        // short of the next
        const PiWide standing = pi_tower_words_wide(place);
        floor_ok = floor_ok && (integer_sum == ((negative != 0) ? (numerator - 1ull) : numerator)) &&
                   (pi_tower_compare(standing, (negative != 0) ? pi_tower_difference(modulus, size) : size) == 0);
        ok = ok && floor_ok;
        walked += 1u;
        scriptura_text(&results->line, "    ");
        scriptura_decimal(&results->line, at, 2u);
        scriptura_text(&results->line, "  ");
        scriptura_decimal(&results->line, (3ull * steps) + numerator, 1u);
        scriptura_character(&results->line, '/');
        scriptura_decimal(&results->line, steps, 1u);
        scriptura_text(&results->line, "  residue ");
        scriptura_character(&results->line, (negative != 0) ? '-' : '+');
        pi_tower_print_exponent(&results->line, size, modulus);
        scriptura_text(&results->line, (floor_ok != 0) ? "  the permutation's whole parts, and the residue at step q\n"
                                                       : "  NOT the permutation\n");
        sim_flush(results);
    }
    sim_check(results, ok && certain && (walked >= 12u),
              "on every floor with q_j to 2^21, pi's first q_j steps have the whole parts of the permutation n -> n "
              "p_j mod q_j, and at step q_j it stands its residue off the whole");
}
