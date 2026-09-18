#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-010
#
# The boundary function asked to define itself, and then run over the sets Fefferman's Navier-Stokes
# statement names, with the inheritance of each boundary kind through the constructors checked in the
# engine's exact integer arithmetic. It claims nothing about any open problem. It presents the rigor and
# stops.
#
#   Usage:  python evidence/proofs/posits/proof_boundary_inheritance.py
#
# proof_domain_boundaries.py named three kinds of boundary from a survey and proved each on a case built
# to have it. A survey assigns the kind by judgment, and judgment is what the discipline forbids. Here the
# kind is not assigned. It is read off the object by two probes, and the object answers:
#
#   FORMAT        raising our scale (the format) moves what we reach.
#   COMPLETENESS  raising our horizon (the computation) moves what we reach.
#   MEASUREMENT   there is a gap to the target and neither probe moves it: the floor is not on our side.
#   NONE          there is no gap: the target is reached exactly.
#
# `measurement` therefore means exactly `unmoved by both of our probes`, and from this side `external`
# means the same. The verdict is only as good as the probes: a probe that cannot move an object is not a
# probe of it. That limit is stated here and not hidden. The classifier is run first on four cases whose
# kind is known by construction (the positive controls, from proof_domain_boundaries.py), and only then
# on the Navier-Stokes objects, which come from examples/0_experimental/exact_navier_stokes_on_torus.py
# and are imported from that file so that one representation carries both.
#
# The arithmetic is the engine's alone: Python integers as the bignum, decimal inputs read by
# representation.exact as (numerator, places) pairs, and booleans. Where a value is not a decimal it is
# carried as (numerator, denominator) integers reduced by their common divisor, the same pair with the
# denominator widened, and pi where a decimal report needs it is a scaled integer by Machin's formula.
#
# Their sets, run here: the Taylor coefficients of a solution of (1)-(3) on the unit torus, reported in
# decimals (a coefficient carrying pi has no last digit) and reported in the exact ring (no scale at
# all); an amplitude deposited to six places, a stand-in for a measured datum; and the ratio in which that
# amplitude cancels. Then inheritance: does the constructor chain datum -> u_1 -> u_2 -> u_3 carry each
# kind forward? Measured: the format kind is absent at every order in the ring, and in a decimal report it
# is absent at the rational datum and present from the first derivative on, because the derivative brings
# pi in; the measurement kind is carried to every order and canceled only by a ratio; the completeness
# kind is carried and grows.
#
# The last part is the algebra of one constructor read in the millennium book's Navier-Stokes chapter
# (theory_bucket/millennium/chapters/chapter_navier_stokes.tex, its account of Corollary 10.6 of the
# 2026 paper it reviews): a periodic field built by summing integer translates of a compactly supported
# one, whose supports stay disjoint. What that constructor inherits from its pieces rests on one exact
# fact, that the bilinear term of a sum splits into the pieces' bilinear terms when supports are disjoint,
# and that fact is shown here on piecewise polynomials with integer coefficients on a lattice of eighths,
# by two routes, with the overlapping case as the drawn null. The construction is theirs; only the
# algebra is run here.
#
# Prior art and language borrowed, named with respect: the problem statement and its numbered conditions
# are Charles Fefferman's (Clay Mathematics Institute, read in full); the probes are the ordinary idea of
# a sensitivity test, not new; the Moore closure and Cantor's diagonal are in proof_set_theory.py with
# their credits; pi by Machin's formula (1706); the fact that a solution's Taylor coefficients follow
# from differentiating the equation at t = 0 is the classical power-series method. No bounding: every
# comparison is an exact equality on integers, on integer pairs, or on sets.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "examples", "0_experimental"))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation import exact  # noqa: E402
import exact_navier_stokes_on_torus as torus  # noqa: E402

AXES = torus.AXES
gcd = torus.gcd


def reduced(numerator, denominator):
    """An integer pair over its common divisor, denominator positive: one canonical name per value."""
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    divisor = gcd(numerator, denominator) or 1
    return numerator // divisor, denominator // divisor


def pair_add(left, right):
    return reduced(left[0] * right[1] + right[0] * left[1], left[1] * right[1])


# ---------------------------------------------------------------- the boundary function, by probes


def boundary_kind(reach, format_level, horizon_level, target):
    """Read the kind off the object: a gap to the target, and what each probe moves.

    `reach(format, horizon)` is what we hold at those settings. Raising each setting by one is the probe.
    """
    here = reach(format_level, horizon_level)
    gap = here != target
    moved_by_format = reach(format_level + 1, horizon_level) != here
    moved_by_horizon = reach(format_level, horizon_level + 1) != here
    if not gap:
        kind = "none"
    elif moved_by_format and moved_by_horizon:
        kind = "format and completeness"
    elif moved_by_format:
        kind = "format"
    elif moved_by_horizon:
        kind = "completeness"
    else:
        kind = "measurement"
    return kind, gap, moved_by_format, moved_by_horizon


def describe(out, name, verdict):
    kind, gap, by_format, by_horizon = verdict
    out.write(
        "    %-48s gap %-5s format %-5s horizon %-5s -> %s\n"
        % (name, gap, by_format, by_horizon, kind)
    )


# ---------------------------------------------------------------- positive controls, kind known by construction

FORMAT_PRIMES = [
    (998244353, 23, 3),
    (2013265921, 27, 31),
]  # prime, 2-adic order of p-1, primitive root
DEPOSIT = exact.units("1.234567")  # a value deposited to six places
TRUTH = exact.units(
    "1.2345671234567"
)  # a defined stand-in for the value the deposit truncates


def has_root_of_order(prime, generator, length):
    if (prime - 1) % length != 0:
        return False
    root = pow(generator, (prime - 1) // length, prime)
    return pow(root, length, prime) == 1 and pow(root, length // 2, prime) != 1


def ntt_reach(format_level, horizon_level):
    """The power-of-two exponents up to the horizon whose length has a root modulo the format's prime."""
    prime, _, generator = FORMAT_PRIMES[min(format_level, len(FORMAT_PRIMES) - 1)]
    return frozenset(
        exponent
        for exponent in range(1, horizon_level + 1)
        if has_root_of_order(prime, generator, 2**exponent)
    )


def tree_reach(_format_level, horizon_level):
    """Leaves of a full 3-ary tree of depth 12 reachable within the horizon; the scale plays no part."""
    return 3 ** min(horizon_level, 12)


def deposit_at(places):
    """The deposit read at `places` decimal places, at least its own six, as a reduced pair."""
    digits = max(places, DEPOSIT[1])
    return reduced(exact.at_scale(DEPOSIT[0], DEPOSIT[1], digits), 10**digits)


def deposit_reach(format_level, _horizon_level):
    return deposit_at(format_level)


def report_controls(out):
    out.write("  positive controls: four objects whose kind is fixed by construction\n")
    ntt = boundary_kind(ntt_reach, 0, 25, frozenset(range(1, 26)))
    tree = boundary_kind(tree_reach, 0, 7, 3**12)
    deposit = boundary_kind(deposit_reach, 6, 0, reduced(TRUTH[0], 10 ** TRUTH[1]))
    exact_value = boundary_kind(lambda _f, _h: reduced(22, 7), 0, 0, reduced(22, 7))
    describe(out, "NTT length, prime 119*2^23+1, horizon 2^25", ntt)
    describe(out, "3-ary tree count at horizon 7 of 12", tree)
    describe(out, "a deposit of 6 places against its true value", deposit)
    describe(out, "the rational 22/7 against itself", exact_value)
    # the null for the classifier: a probe that cannot move the object reports measurement
    blind = boundary_kind(lambda _f, _h: 3**7, 0, 7, 3**12)
    describe(out, "null: the tree count with the horizon probe cut", blind)
    out.write(
        "    the null shows the limit: measurement means unmoved by OUR probes, nothing more\n\n"
    )
    return (
        ntt[0] == "format"
        and tree[0] == "completeness"
        and deposit[0] == "measurement"
        and exact_value[0] == "none"
        and blind[0] == "measurement"
    )


# ---------------------------------------------------------------- pi as a scaled integer, Machin 1706


def arctan_reciprocal(whole, scale):
    total = 0
    sign = 1
    power = whole
    whole_squared = whole * whole
    index = 0
    while True:
        term = scale // ((2 * index + 1) * power)
        if term == 0:
            break
        total += sign * term
        sign = -sign
        index += 1
        power *= whole_squared
    return total


def pi_scaled(digits):
    """floor(pi * 10^digits), by Machin's formula pi = 16 arctan(1/5) - 4 arctan(1/239)."""
    guard = 10
    scale = 10 ** (digits + guard)
    value = 16 * arctan_reciprocal(5, scale) - 4 * arctan_reciprocal(239, scale)
    return value // (10**guard)


def evaluate_part(poly, den, part, digits):
    """floor(10^digits * (sum_p c_p pi^p) / den) for the real (part 0) or imaginary (part 1) integers.

    pi enters as a scaled integer carrying 20 places past `digits`. The floor is exact unless the true
    expansion runs twenty nines at that place; the probe compares values, and a value with pi in it moves.
    """
    work = digits + 20
    pi_value = pi_scaled(work)
    total = (0, 1)
    for power, pair in poly.items():
        coefficient = pair[part]
        if coefficient == 0:
            continue
        if power >= 0:
            total = pair_add(
                total, (coefficient * pi_value**power, 10 ** (work * power))
            )
        else:
            total = pair_add(
                total, (coefficient * 10 ** (work * (-power)), pi_value ** (-power))
            )
    numerator, denominator = total[0] * 10**digits, total[1] * den
    return numerator // denominator


# ---------------------------------------------------------------- their sets


def within(vector, radius):
    return tuple(
        torus.Scalar(
            {
                mode: poly
                for mode, poly in vector[axis].modes.items()
                if max(abs(mode[0]), abs(mode[1]), abs(mode[2])) <= radius
            },
            vector[axis].den,
        )
        for axis in AXES
    )


def decimal_reach_for(vector):
    """The coefficients within the horizon, each read as a pair of decimals floored at the scale.

    A floored decimal is returned as a reduced pair. 1/2 read at one place and at two places is the
    same value, and only a value whose expansion goes on is moved by the scale.
    """

    def reach(digits, radius):
        held = within(vector, radius)
        rows = []
        for axis in AXES:
            for mode in sorted(held[axis].modes):
                poly = held[axis].modes[mode]
                rows.append(
                    (
                        axis,
                        mode,
                        reduced(
                            evaluate_part(poly, held[axis].den, 0, digits), 10**digits
                        ),
                        reduced(
                            evaluate_part(poly, held[axis].den, 1, digits), 10**digits
                        ),
                    )
                )
        return tuple(rows)

    return reach


def ring_reach_for(vector):
    """The coefficients within the horizon, exact; the scale is not part of the representation."""

    def reach(_digits, radius):
        return exact_rows(within(vector, radius))

    return reach


def exact_rows(vector):
    return tuple(
        (axis, mode, vector[axis].den, tuple(sorted(vector[axis].modes[mode].items())))
        for axis in AXES
        for mode in sorted(vector[axis].modes)
    )


def abc_with_amplitude(amplitude):
    return torus.abc_field(amplitude, (2, 1), (3, 1))


def report_their_sets(out):
    out.write(
        "  their sets: Taylor coefficients of (1)-(3) on the unit torus, read by the probes\n"
    )
    generic = torus.generic_field()
    velocities, _ = torus.taylor_velocity(generic, torus.VISCOSITY, 3)
    second = velocities[2]  # its modes reach |k|_inf = 2

    decimal_narrow = boundary_kind(decimal_reach_for(second), 30, 1, exact_rows(second))
    decimal_full = boundary_kind(decimal_reach_for(second), 30, 2, exact_rows(second))
    ring_narrow = boundary_kind(ring_reach_for(second), 30, 1, exact_rows(second))
    ring_full = boundary_kind(ring_reach_for(second), 30, 2, exact_rows(second))
    describe(out, "u_2 in decimals, 30 places, modes |k|_inf <= 1", decimal_narrow)
    describe(out, "u_2 in decimals, 30 places, modes |k|_inf <= 2", decimal_full)
    describe(out, "u_2 in the ring, modes |k|_inf <= 1", ring_narrow)
    describe(out, "u_2 in the ring, modes |k|_inf <= 2", ring_full)

    # a measured amplitude: the ABC datum with A deposited to 6 places against a stand-in true value
    order = 2

    def measured_reach(digits, radius):
        held, _ = torus.taylor_velocity(
            abc_with_amplitude(deposit_at(digits)), torus.VISCOSITY, order
        )
        return exact_rows(within(held[order], radius))

    true_velocities, _ = torus.taylor_velocity(
        abc_with_amplitude(reduced(TRUTH[0], 10 ** TRUTH[1])), torus.VISCOSITY, order
    )
    measured = boundary_kind(measured_reach, 6, 1, exact_rows(true_velocities[order]))
    describe(out, "u_2 from A deposited to 6 places, against true A", measured)

    # the ratio in which the amplitude cancels: u_1 / u_0 mode by mode is -4 nu pi^2 for either A
    rate = torus.decay_rate(torus.VISCOSITY, -4)

    def ratio_rows(velocities_held):
        expected = torus.vec_times(velocities_held[0], rate)
        return tuple(
            (axis, mode, velocities_held[1][axis] == expected[axis])
            for axis in AXES
            for mode in sorted(velocities_held[0][axis].modes)
        )

    def ratio_reach(digits, _radius):
        held, _ = torus.taylor_velocity(
            abc_with_amplitude(deposit_at(digits)), torus.VISCOSITY, 1
        )
        return ratio_rows(held)

    ratio = boundary_kind(ratio_reach, 6, 1, ratio_rows(true_velocities))
    ratio_all_true = all(row[2] for row in ratio_rows(true_velocities))
    describe(out, "u_1/u_0 = -4 nu pi^2, deposit against true A", ratio)
    out.write(
        "    the ratio identity holds at every mode for the true amplitude: %s\n\n"
        % ratio_all_true
    )

    return (
        decimal_narrow[0] == "format and completeness"
        and decimal_full[0] == "format"
        and ring_narrow[0] == "completeness"
        and ring_full[0] == "none"
        and measured[0] == "measurement"
        and ratio[0] == "none"
        and ratio_all_true
    )


# ---------------------------------------------------------------- inheritance through the constructor chain


def report_inheritance(out):
    out.write(
        "  inheritance: which kinds the chain datum -> u_1 -> u_2 -> u_3 carries forward\n"
    )
    depth = 3
    generic = torus.generic_field()
    velocities, _ = torus.taylor_velocity(generic, torus.VISCOSITY, depth)

    # format: in the ring, the scale probe is silent at every order; in decimals it moves once pi enters
    ring_silent = []
    decimal_moves = []
    for step in range(depth + 1):
        held = velocities[step]
        radius = torus.mode_radius(held)
        ring_silent.append(
            not boundary_kind(ring_reach_for(held), 30, radius, exact_rows(held))[2]
        )
        decimal_moves.append(
            boundary_kind(decimal_reach_for(held), 30, radius, exact_rows(held))[2]
        )
    decimal_pattern = decimal_moves == [False] + [True] * depth
    out.write(
        "    format, ring:     scale probe silent at orders 0..%d: %s\n"
        % (depth, ring_silent)
    )
    out.write(
        "    format, decimals: scale probe moves at orders 0..%d:  %s\n"
        % (depth, decimal_moves)
    )
    out.write(
        "      silent at the datum, whose coefficients are rational, and moving from order 1 on: the\n"
    )
    out.write(
        "      derivative brings pi in, and a coefficient with pi has no last digit: %s\n"
        % decimal_pattern
    )

    # measurement: a deposit's gap is carried to every order, and on the linear ABC solution it is carried
    # exactly, gap_m = (-4 nu pi^2)^m gap_0; on the generic datum it is nonzero at every order
    truth = reduced(TRUTH[0], 10 ** TRUTH[1])
    deposit = deposit_at(6)
    abc_dep, _ = torus.taylor_velocity(
        abc_with_amplitude(deposit), torus.VISCOSITY, depth
    )
    abc_true, _ = torus.taylor_velocity(
        abc_with_amplitude(truth), torus.VISCOSITY, depth
    )
    rate = torus.decay_rate(torus.VISCOSITY, -4)
    gap_0 = torus.vec_sub(abc_true[0], abc_dep[0])
    abc_gaps = [
        not torus.vec_is_zero(torus.vec_sub(abc_true[step], abc_dep[step]))
        for step in range(depth + 1)
    ]
    abc_exact = all(
        torus.vec_eq(
            torus.vec_sub(abc_true[step], abc_dep[step]),
            torus.vec_times(gap_0, torus.ratio_power(rate, step)),
        )
        for step in range(depth + 1)
    )

    gen_dep, _ = torus.taylor_velocity(
        torus.generic_field(deposit), torus.VISCOSITY, depth
    )
    gen_true, _ = torus.taylor_velocity(
        torus.generic_field(truth), torus.VISCOSITY, depth
    )
    gen_gaps = [
        not torus.vec_is_zero(torus.vec_sub(gen_true[step], gen_dep[step]))
        for step in range(depth + 1)
    ]
    out.write(
        "    measurement, ABC:     gap nonzero at orders 0..%d: %s ; gap_m = (-4 nu pi^2)^m gap_0 exactly: %s\n"
        % (depth, abc_gaps, abc_exact)
    )
    out.write(
        "    measurement, generic: gap nonzero at orders 0..%d: %s (carried, not lowered by any order)\n"
        % (depth, gen_gaps)
    )

    # completeness: modes outside a fixed horizon, per order: carried and growing
    outside = [torus.modes_outside(velocities[step], 1) for step in range(depth + 1)]
    growing = (
        all(outside[step + 1] >= outside[step] for step in range(depth))
        and outside[depth] > outside[0]
    )
    out.write(
        "    completeness: modes outside |k|_inf <= 1 at orders 0..%d: %s ; carried and growing: %s\n\n"
        % (depth, outside, growing)
    )
    return (
        all(ring_silent)
        and decimal_pattern
        and all(abc_gaps)
        and abc_exact
        and all(gen_gaps)
        and growing
    )


# ---------------------------------------------------------------- the disjoint-translate constructor, its algebra
#
# Polynomials in y = 8 x with integer coefficients, as lists; the unit interval is y in [0, 8], and a
# piecewise polynomial is a list of (lower, upper, poly) on integer cells, zero off its pieces.


def poly_mul(left, right):
    product = [0] * (len(left) + len(right) - 1)
    for index_left, value_left in enumerate(left):
        for index_right, value_right in enumerate(right):
            product[index_left + index_right] += value_left * value_right
    return product


def poly_add(left, right):
    total = [0] * max(len(left), len(right))
    for index, value in enumerate(left):
        total[index] += value
    for index, value in enumerate(right):
        total[index] += value
    return total


def poly_derivative(poly):
    """d/dx = 8 d/dy on the lattice of eighths."""
    return [8 * index * value for index, value in enumerate(poly)][1:] or [0]


def poly_integral(poly, lower, upper):
    """The exact integral over [lower, upper] in y, as a reduced integer pair."""
    total = (0, 1)
    for index, value in enumerate(poly):
        total = pair_add(
            total, (value * (upper ** (index + 1) - lower ** (index + 1)), index + 1)
        )
    return total


def poly_is_zero(poly):
    return all(value == 0 for value in poly)


def bump(lower, upper):
    """(y - lower)^2 (upper - y)^2 on [lower, upper]: a compactly supported piece with integer coefficients."""
    rising = [-lower, 1]
    falling = [upper, -1]
    return [
        (lower, upper, poly_mul(poly_mul(rising, rising), poly_mul(falling, falling)))
    ]


def piecewise_canonical(pieces):
    """Split on every breakpoint, add the polynomials covering each cell, drop the zero cells."""
    points = sorted({point for piece in pieces for point in (piece[0], piece[1])})
    result = []
    for lower, upper in zip(points, points[1:]):
        total = [0]
        for piece_lower, piece_upper, poly in pieces:
            if piece_lower <= lower and upper <= piece_upper:
                total = poly_add(total, poly)
        if not poly_is_zero(total):
            result.append((lower, upper, total))
    return result


def piecewise_add(left, right):
    return piecewise_canonical(left + right)


def piecewise_neg(pieces):
    return [(lower, upper, [-value for value in poly]) for lower, upper, poly in pieces]


def piecewise_mul(left, right):
    product = []
    for left_lower, left_upper, left_poly in left:
        for right_lower, right_upper, right_poly in right:
            lower, upper = max(left_lower, right_lower), min(left_upper, right_upper)
            if lower < upper:
                product.append((lower, upper, poly_mul(left_poly, right_poly)))
    return piecewise_canonical(product)


def piecewise_derivative(pieces):
    return piecewise_canonical(
        [(lower, upper, poly_derivative(poly)) for lower, upper, poly in pieces]
    )


def piecewise_is_zero(pieces):
    return not piecewise_canonical(pieces)


def piecewise_integral(pieces):
    total = (0, 1)
    for lower, upper, poly in pieces:
        total = pair_add(total, poly_integral(poly, lower, upper))
    return total


def bilinear(left, right):
    """left * right', the shape of the transport term (u . grad) v in one variable."""
    return piecewise_mul(left, piecewise_derivative(right))


def report_constructor(out):
    out.write(
        "  the disjoint-translate constructor: the bilinear term of a sum splits exactly when supports are disjoint\n"
    )
    piece = bump(0, 2)  # [0, 1/4] in eighths
    apart = bump(4, 6)  # [1/2, 3/4]
    overlapping = bump(1, 3)  # [1/8, 3/8]

    def cross_terms(first, second):
        return piecewise_add(bilinear(first, second), bilinear(second, first))

    def split_holds(first, second):
        whole = piecewise_add(first, second)
        of_sum = bilinear(whole, whole)
        of_parts = piecewise_add(bilinear(first, first), bilinear(second, second))
        difference = piecewise_add(of_sum, piecewise_neg(of_parts))
        # route one: every coefficient on every cell is zero; route two: the exact integral of the square is zero
        by_coefficients = piecewise_is_zero(difference)
        by_integral = piecewise_integral(piecewise_mul(difference, difference))[0] == 0
        cross = cross_terms(first, second)
        return (
            by_coefficients,
            by_integral,
            piecewise_integral(piecewise_mul(cross, cross)),
        )

    disjoint_coefficients, disjoint_integral, disjoint_square = split_holds(
        piece, apart
    )
    overlap_coefficients, overlap_integral, overlap_square = split_holds(
        piece, overlapping
    )
    linear_inherits = piecewise_is_zero(
        piecewise_add(
            piecewise_derivative(piecewise_add(piece, apart)),
            piecewise_neg(
                piecewise_add(piecewise_derivative(piece), piecewise_derivative(apart))
            ),
        )
    )

    out.write(
        "    pieces in eighths: (y-a)^2 (b-y)^2 on [0,2] and on [4,6] (disjoint), on [1,3] (overlapping)\n"
    )
    out.write(
        "    disjoint: split holds by coefficients %s, by integral %s ; int (cross)^2 dy = %d/%d\n"
        % (
            disjoint_coefficients,
            disjoint_integral,
            disjoint_square[0],
            disjoint_square[1],
        )
    )
    out.write(
        "    overlap (the null): split holds by coefficients %s, by integral %s ; int (cross)^2 dy = %d/%d\n"
        % (overlap_coefficients, overlap_integral, overlap_square[0], overlap_square[1])
    )
    out.write(
        "    the linear terms split regardless (derivative of the sum): %s\n"
        % linear_inherits
    )
    out.write(
        "   , a sum of disjoint translates inherits the equation from its pieces through the bilinear\n"
    )
    out.write(
        "    term only because the cross terms vanish; the construction is theirs, this is its algebra.\n\n"
    )
    return (
        disjoint_coefficients
        and disjoint_integral
        and disjoint_square[0] == 0
        and not overlap_coefficients
        and not overlap_integral
        and overlap_square[0] > 0
        and linear_inherits
    )


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    out.write(
        "  PROOF: the boundary function defined by probes, run on their sets, inheritance checked\n\n"
    )
    results = [
        report_controls(out),
        report_their_sets(out),
        report_inheritance(out),
        report_constructor(out),
    ]
    if all(results):
        out.write(
            "  every part lands: the probes recover the known kinds, read their sets, and the chain carries\n"
        )
        out.write(
            "  the measurement and completeness kinds forward while the ring carries no format kind at all.\n"
        )
        out.write("  nothing here bears on whether (A), (B), (C) or (D) holds.\n")
    else:
        out.write("  a part missed its forced outcome: refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
