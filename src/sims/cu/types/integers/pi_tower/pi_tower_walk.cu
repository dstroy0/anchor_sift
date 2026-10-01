// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_tower_walk.cu: the walk, polynomials, fractions and the arc
#include "pi_tower_internal.h"

// the step at which the direct walk fills every one of 2^bits cells, the cell it fills, the longest stall, the step
// at which every cell has been etched a second time, the first step after the fill that etches cell 0, and the first
// step after that one that etches the fill's last cell
unsigned long long pi_tower_walk(const PiWide &alpha, unsigned int bits, unsigned long long *last,
                                 unsigned long long *stall, unsigned long long *again, unsigned long long *home,
                                 unsigned long long *closing)
{
    unsigned long long increment[PI_TOWER_WORDS];
    unsigned long long place[PI_TOWER_WORDS];
    for (unsigned int word = 0u; word < PI_TOWER_WORDS; word += 1u)
    {
        increment[word] =
            ((unsigned long long)alpha.limb[(2u * word) + 1u] << 32u) | (unsigned long long)alpha.limb[2u * word];
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
    PiTowerPolynomial total((left.size() > right.size()) ? left.size() : right.size(), pi_tower_unsigned(0ull));
    for (size_t at = 0u; at < total.size(); at += 1u)
    {
        if (at < left.size())
        {
            total[at] = left[at];
        }
        if (at < right.size())
        {
            total[at] =
                (subtract != 0) ? pi_tower_difference(total[at], right[at]) : pi_tower_sum(total[at], right[at]);
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
    PiTowerPolynomial total((left.size() + right.size()) - 1u, pi_tower_unsigned(0ull));
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
    PiTowerPolynomial polynomial(power + 1u, pi_tower_unsigned(0ull));
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
    PiWide unit = pi_tower_unsigned(1ull);
    for (unsigned int place = 0u; place < places; place += 1u)
    {
        unit = pi_tower_product(unit, pi_tower_unsigned(10ull));
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
    PiWide total = pi_tower_unsigned(0ull);
    unsigned long long index = 0ull;
    *terms = 0ull;
    while (power.sign != 0)
    {
        const PiWide term = pi_tower_quotient(power, pi_tower_unsigned((2ull * index) + 1ull));
        total = ((index & 1ull) == 0ull) ? pi_tower_sum(total, term) : pi_tower_difference(total, term);
        *terms += 1ull;
        power = pi_tower_quotient(pi_tower_product(power, square), square_unit);
        index += 1ull;
    }
    return total;
}

// the floor of the square root of a non-negative integer, by Newton's step from above
PiWide pi_tower_root(const PiWide &value)
{
    if (value.sign == 0)
    {
        return value;
    }
    const PiWide two = pi_tower_unsigned(2ull);
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
void pi_tower_arc(SimResults *results, const PiWide &low, const PiWide &high, unsigned int bits)
{
    const PiTowerPolynomial one = pi_tower_monomial(1ll, 0u);
    const PiTowerPolynomial square_and_one = pi_tower_polynomial_sum(pi_tower_monomial(1ll, 2u), one, 0);
    // circumference 1 around our disk, and 1 / pi along the axis for each turn: a = 1 / (2 pi), b = 1 / (2 pi^2)
    const PiTowerFraction radius = pi_tower_fraction(one, pi_tower_monomial(2ll, 1u));
    const PiTowerFraction rise = pi_tower_fraction(one, pi_tower_monomial(2ll, 2u));
    const PiTowerFraction curvature_squared =
        pi_tower_fraction(pi_tower_monomial(4ll, 6u), pi_tower_polynomial_product(square_and_one, square_and_one));
    const PiTowerFraction torsion_expected = pi_tower_fraction(pi_tower_monomial(2ll, 2u), square_and_one);
    const PiTowerFraction inverse_square = pi_tower_fraction(one, pi_tower_monomial(1ll, 2u));
    const PiTowerFraction momentum_expected =
        pi_tower_fraction(one, pi_tower_polynomial_sum(pi_tower_monomial(4ll, 2u), pi_tower_monomial(4ll, 0u), 0));
    int bending = 1;
    int twisting = 1;
    int balanced = 1;
    int tilted = 1;
    int axial = 1;
    int torque_free = 1;
    int momentum_ok = 1;
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
            cross_squared,
            pi_tower_fraction_product(speed_squared, pi_tower_fraction_product(speed_squared, speed_squared)));
        const PiTowerFraction torsion =
            pi_tower_fraction_quotient(pi_tower_vector_dot(first, pi_tower_vector_cross(second, third)), cross_squared);
        const PiTowerFraction torsion_squared = pi_tower_fraction_product(torsion, torsion);
        bending = bending && pi_tower_fraction_equal(kappa_squared, curvature_squared);
        twisting = twisting && pi_tower_fraction_equal(torsion, torsion_expected);
        balanced = balanced &&
                   pi_tower_fraction_equal(pi_tower_fraction_quotient(torsion_squared, kappa_squared), inverse_square);
        // the tangent's rise over its run around the disk, squared: tan^2 of the tilt
        const PiTowerFraction around =
            pi_tower_fraction_sum(pi_tower_fraction_product(first.axis[0], first.axis[0]),
                                  pi_tower_fraction_product(first.axis[1], first.axis[1]), 0);
        const PiTowerFraction tilt_squared =
            pi_tower_fraction_quotient(pi_tower_fraction_product(first.axis[2], first.axis[2]), around);
        tilted = tilted && pi_tower_fraction_equal(tilt_squared, inverse_square) &&
                 pi_tower_fraction_equal(tilt_squared, pi_tower_fraction_quotient(torsion_squared, kappa_squared));
        // |g'|^3 (tau T + kappa B) = tau |g'|^2 g' + g' x g''
        const PiTowerFraction scale = pi_tower_fraction_product(torsion, speed_squared);
        PiTowerVector darboux;
        for (unsigned int axis = 0u; axis < 3u; axis += 1u)
        {
            darboux.axis[axis] =
                pi_tower_fraction_sum(pi_tower_fraction_product(scale, first.axis[axis]), cross.axis[axis], 0);
        }
        axial = axial && pi_tower_fraction_zero(darboux.axis[0]) && pi_tower_fraction_zero(darboux.axis[1]) &&
                (pi_tower_fraction_zero(darboux.axis[2]) == 0);
        // about our axis: the torque's share is x y'' - y x'', the momentum's x y' - y x', at unit speed over |g'|
        const PiTowerFraction torque =
            pi_tower_fraction_sum(pi_tower_fraction_product(place.axis[0], second.axis[1]),
                                  pi_tower_fraction_product(place.axis[1], second.axis[0]), 1);
        const PiTowerFraction momentum =
            pi_tower_fraction_sum(pi_tower_fraction_product(place.axis[0], first.axis[1]),
                                  pi_tower_fraction_product(place.axis[1], first.axis[0]), 1);
        torque_free = torque_free && pi_tower_fraction_zero(torque);
        momentum_ok =
            momentum_ok && pi_tower_fraction_equal(
                               pi_tower_fraction_quotient(pi_tower_fraction_product(momentum, momentum), speed_squared),
                               momentum_expected);
    }
    scriptura_text(&results->line, "  the arc: the helix of radius 1/(2 pi) rising 1/pi a turn, over our disk\n");
    sim_check(results, bending, "in Q(pi), the helix's curvature is 2 pi^3 / (pi^2 + 1) at all four quarter turns");
    sim_check(results, twisting, "in Q(pi), its torsion is 2 pi^2 / (pi^2 + 1) at all four");
    sim_check(results, balanced && tilted,
              "tau / kappa = 1 / pi, the tangent of its tilt against our disk, at all four (Lancret)");
    sim_check(results, axial, "its Darboux vector tau T + kappa B lies along our disk's axis at all four");
    sim_check(results, torque_free && momentum_ok,
              "the torque about our axis is zero and L_z^2 = 1 / (4 (pi^2 + 1)) at unit speed, at all four: present, "
              "and balanced");

    // the numbers: kappa and tau rise with pi, and arctan(1 / pi) falls. Each is bracketed by the ends of pi's
    const unsigned int places = 12u;
    PiWide unit = pi_tower_unsigned(1ull);
    for (unsigned int place = 0u; place < places; place += 1u)
    {
        unit = pi_tower_product(unit, pi_tower_unsigned(10ull));
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
        kappa[end] = pi_tower_quotient(
            pi_tower_product(pi_tower_product(square, ends[end]), pi_tower_product(unit, pi_tower_unsigned(2ull))),
            pi_tower_product(scale, below));
        tau[end] = pi_tower_quotient(pi_tower_product(square, pi_tower_product(unit, pi_tower_unsigned(2ull))), below);
    }
    unsigned long long small_terms = 0ull;
    unsigned long long large_terms = 0ull;
    // 1 / pi 2^bits lies strictly between these. Arctan(1 / pi) 2^bits lies between their arctangents
    const PiWide small = pi_tower_quotient(scale_squared, high);
    const PiWide large = pi_tower_sum(pi_tower_quotient(scale_squared, low), pi_tower_unsigned(1ull));
    const PiWide small_angle = pi_tower_arctan_fixed(small, bits, &small_terms);
    const PiWide large_angle = pi_tower_arctan_fixed(large, bits, &large_terms);
    // degrees = 180 phi / pi = 180 S / P, with S = phi 2^bits
    const PiWide degrees = pi_tower_product(unit, pi_tower_unsigned(180ull));
    const PiWide tilt_low = pi_tower_quotient(
        pi_tower_product(pi_tower_difference(small_angle, pi_tower_unsigned((3ull * small_terms) + 2ull)), degrees),
        high);
    const PiWide tilt_high = pi_tower_quotient(
        pi_tower_product(pi_tower_sum(large_angle, pi_tower_unsigned((3ull * large_terms) + 2ull)), degrees), low);
    // L_z = 1 / (2 sqrt(pi^2 + 1)) falls as pi rises; its square is 4^bits / (4 (P^2 + 4^bits)), and the floor of the
    // root of a floor is the floor of the root
    PiWide momentum[2];
    for (unsigned int end = 0u; end < 2u; end += 1u)
    {
        const PiWide below = pi_tower_product(pi_tower_sum(pi_tower_product(ends[end], ends[end]), scale_squared),
                                              pi_tower_unsigned(4ull));
        momentum[end] =
            pi_tower_root(pi_tower_quotient(pi_tower_product(pi_tower_product(unit, unit), scale_squared), below));
    }
    const int agree = (pi_tower_compare(kappa[0], kappa[1]) == 0) && (pi_tower_compare(tau[0], tau[1]) == 0) &&
                      (pi_tower_compare(tilt_low, tilt_high) == 0) && (pi_tower_compare(momentum[0], momentum[1]) == 0);
    scriptura_text(&results->line, "    curvature ");
    pi_tower_print_places(&results->line, kappa[0], places);
    scriptura_text(&results->line, ", torsion ");
    pi_tower_print_places(&results->line, tau[0], places);
    scriptura_text(&results->line, ", the tilt of its plane against our disk ");
    pi_tower_print_places(&results->line, tilt_low, places);
    scriptura_text(&results->line, " degrees, and against our axis ");
    // the tilt is irrational. The floor of 90 less it is 90 less its floor, less one
    pi_tower_print_places(&results->line,
                          pi_tower_difference(pi_tower_product(unit, pi_tower_unsigned(90ull)),
                                              pi_tower_sum(tilt_low, pi_tower_unsigned(1ull))),
                          places);
    scriptura_text(&results->line, " degrees\n    angular momentum about our axis at unit speed ");
    pi_tower_print_places(&results->line, momentum[0], places);
    scriptura_character(&results->line, '\n');
    sim_check(results, agree, "curvature, torsion, tilt and L_z agree at both ends of pi's bracket to 12 places");
    sim_flush(results);
}
