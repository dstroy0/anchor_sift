#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-017
#
# The Navier-Stokes solution map made visible on the unit torus: the energy cascade of a datum, shell by
# shell and order by order, and the growth of the Taylor coefficients whose limit is the reciprocal of
# the time the solution stays analytic. It reads the same sets exact_navier_stokes_on_torus.py defines,
# in the same integer arithmetic, and it claims nothing about any of Fefferman's four alternatives. It
# shows the knot; it does not cut it.
#
#   Usage:  python examples/0_experimental/exact_navier_stokes_cascade.py
#
# This reads no corpus. It sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. It imports the ring, the recurrence and Parseval from exact_navier_stokes_on_torus.py so one
# representation carries both files, and it adds no arithmetic of its own beyond a product of two exact
# quantities. Python integers are the bignum, representation.exact reads the viscosity, and the rest is
# booleans and comparisons. No float, no fraction library.
#
# THE PICTURE. A solution of (1), (2), (3) on the unit torus is carried as its Taylor coefficients at
# t = 0, u(t) = sum_m u_m t^m / m!. Each u_m is a field in the ring, a finite sum of modes with Gaussian
# integer Laurent coefficients in pi over one integer denominator. Two exact, pi-free readings of the
# cascade come straight off that:
#
#   the mode front   the count of modes k carried at order m, grouped by |k|_1. The product of two modes
#                    adds their index vectors. The front advances by exactly one in |k|_1 per order,
#                    and the count is a whole number at every shell. This is energy reaching finer scales
#                    order by order, read as integers.
#   the energy shell the energy an order deposits in the shell |k|^2 = r, an exact element of the ring
#                    (a Laurent polynomial in pi over an integer). Whether a shell carries energy is the
#                    exact test "is this quantity zero", which needs no numeric value of pi. The energies
#                    over all shells sum to the total, Parseval's identity, exact.
#
# THE KNOT. The regularity question is whether the solution stays smooth for all time. In this picture it
# is one quantity, the growth rate of the coefficients. That rate fixes the radius in t over which the
# series converges, and the radius is how long the solution stays analytic; a finite radius is a blowup.
# For the Arnold-Beltrami-Childress datum the rate is a single exact element of the ring, constant in the
# order. The series is e^{-4 nu pi^2 t} u_0, entire, and the datum never blows up. For a generic datum
# only finitely many orders are computed. Each bounds the rate from one side and no finite order reaches
# the limit. That is the completeness boundary of the precision document, the same shape as the horizon
# on the zeros of zeta in the analytic-number-theory workbook: a computation names finitely many to a
# stated precision and never reaches a statement about all of them. Reading the limit needs infinitely
# many orders and a step outside exact arithmetic, and neither is taken here.
#
# Positive control: the ABC datum's energy obeys the exact law E(u_{m+1}) = (16 nu^2 pi^4) E(u_m) at every
# order, its energy stays wholly in the shell |k|^2 = 1, and its coefficient rate is constant, the mark
# of the entire solution with infinite analyticity radius. Two routes: the per-order energy from the
# velocity coefficients and from the vorticity coefficients reconstructed by Biot-Savart, agreeing to the
# integer, and the Parseval decomposition summing the shells back to the total. Drawn null: the ABC datum
# does not cascade (energy stays in one shell at every order), the contrast that shows the generic
# cascade is a real feature and not an artifact; and a corrupted energy route, one mode dropped, is
# caught. Floor: finitely many orders, stated in the sentence that makes the claim.
#
# Prior art, named with respect. The equations and the sets are as named in exact_navier_stokes_on_torus.py,
# Fefferman's statement and Navier's, Stokes's and Euler's equations, with Beltrami, Arnold and Childress,
# Leray, Biot-Savart and Helmholtz credited there. The energy sum over modes is Parseval's. That the radius
# of the time-Taylor series is the interval of analyticity, and that a finite one is the first singular
# time, is classical: Foias and Temam on the time-analyticity of the Navier-Stokes solutions, and Kato.
# Cited from memory of the literature, unread here, and this file verifies only the exact per-order
# quantities and rests on no unread result. This file adds no new mathematics.

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
DEPTH = 5           # Taylor orders 0..DEPTH on the cheaper velocity route
ROUTE_DEPTH = 3     # orders on which the second, vorticity route is also computed


def ratio_mul(left, right):
    """The product of two exact ring scalars (Laurent polynomials in pi over an integer)."""
    return torus.Ratio(torus.poly_mul(left.poly, right.poly), left.den * right.den)


def pi_degree(ratio):
    """The highest power of pi present, an exact integer, or None for the zero quantity."""
    return max(ratio.poly) if ratio.poly else None


def l1_shell(mode):
    return abs(mode[0]) + abs(mode[1]) + abs(mode[2])


def counts_by_l1(vector):
    """How many modes the field carries at each |k|_1 shell, a whole number per shell."""
    tally = {}
    for mode in torus.modes_of(vector):
        shell = l1_shell(mode)
        tally[shell] = tally.get(shell, 0) + 1
    return tally


def energy_in_shell(vector, shell):
    """The energy the field deposits in the shell |k|^2 = shell, an exact ring scalar."""
    masked = tuple(torus.Scalar({mode: poly for mode, poly in vector[axis].modes.items()
                                 if torus.norm_of(mode) == shell}, vector[axis].den)
                   for axis in AXES)
    return torus.parseval(masked, masked)


def energy_shells(vector):
    return sorted({torus.norm_of(mode) for mode in torus.modes_of(vector)})


def report_front(out):
    """The mode front: the cascade to finer scales, read as integers, generic against the null of ABC."""
    out.write("  the mode front: modes carried per |k|_1 shell, order by order (exact integer counts)\n")
    generic = torus.generic_field()
    abc = torus.abc_field((1, 1), (2, 1), (3, 1))
    generic_velocity, _ = torus.taylor_velocity(generic, torus.VISCOSITY, DEPTH)
    abc_velocity, _ = torus.taylor_velocity(abc, torus.VISCOSITY, DEPTH)

    widest = max(l1_shell(mode) for step in range(DEPTH + 1) for mode in torus.modes_of(generic_velocity[step]))
    header = "    order " + "".join("  |k|1=%d" % shell for shell in range(1, widest + 1))
    out.write("    generic datum, divergence-free and not Beltrami:\n")
    out.write(header + "\n")
    for step in range(DEPTH + 1):
        tally = counts_by_l1(generic_velocity[step])
        row = "".join("  %6d" % tally.get(shell, 0) for shell in range(1, widest + 1))
        out.write("    %5d %s\n" % (step, row))

    # the front advances by exactly one shell per order: energy reaches the next finer scale each step
    generic_front = [max(l1_shell(mode) for mode in torus.modes_of(generic_velocity[step]))
                     for step in range(DEPTH + 1)]
    front_advances = all(generic_front[step + 1] == generic_front[step] + 1 for step in range(DEPTH))

    # the null: the ABC datum is an eigenfunction, curl u_0 = 2 pi u_0. Every order stays on |k|_1 = 1
    abc_front = [max(l1_shell(mode) for mode in torus.modes_of(abc_velocity[step]))
                 for step in range(DEPTH + 1)]
    abc_stays = all(shell == 1 for shell in abc_front)

    out.write("    generic front (largest |k|_1 by order): %s ; advances by one per order: %s\n"
              % (generic_front, front_advances))
    out.write("    null, ABC datum front: %s ; stays in one shell (no cascade): %s\n\n"
              % (abc_front, abc_stays))
    return front_advances and abc_stays


def report_energy(out):
    """The energy per shell, two routes, the Parseval decomposition, and the ABC null of no cascade."""
    out.write("  the energy shells: which shells carry energy, by two routes, summing to the total\n")
    generic = torus.generic_field()
    abc = torus.abc_field((1, 1), (2, 1), (3, 1))
    generic_velocity, _ = torus.taylor_velocity(generic, torus.VISCOSITY, DEPTH)
    abc_velocity, _ = torus.taylor_velocity(abc, torus.VISCOSITY, DEPTH)

    # route two, the vorticity coefficients recovered to velocity by Biot-Savart, on the shared orders
    generic_vorticity = torus.taylor_vorticity(torus.curl(generic), torus.VISCOSITY, ROUTE_DEPTH)
    routes_agree = True
    for step in range(ROUTE_DEPTH + 1):
        from_velocity = torus.parseval(generic_velocity[step], generic_velocity[step])
        recovered = torus.biot_savart(generic_vorticity[step])
        from_vorticity = torus.parseval(recovered, recovered)
        routes_agree = routes_agree and (from_velocity == from_vorticity)

    # the Parseval decomposition: the shell energies sum back to the total, exactly, at every order
    decomposition_holds = True
    for step in range(DEPTH + 1):
        total = torus.parseval(generic_velocity[step], generic_velocity[step])
        summed = torus.Ratio({})
        for shell in energy_shells(generic_velocity[step]):
            summed = summed.add(energy_in_shell(generic_velocity[step], shell))
        decomposition_holds = decomposition_holds and (summed == total)

    # the cascade in energy terms: which |k|^2 shells carry nonzero energy, per order, for the generic datum
    out.write("    generic datum, shells |k|^2 carrying nonzero energy (the exact zero test, no pi value):\n")
    for step in range(DEPTH + 1):
        carrying = [shell for shell in energy_shells(generic_velocity[step])
                    if not energy_in_shell(generic_velocity[step], shell).is_zero()]
        out.write("    order %d: %s\n" % (step, carrying))

    # the null: the ABC datum keeps all its energy in |k|^2 = 1 at every order
    abc_only_base = True
    for step in range(DEPTH + 1):
        carrying = [shell for shell in energy_shells(abc_velocity[step])
                    if not energy_in_shell(abc_velocity[step], shell).is_zero()]
        abc_only_base = abc_only_base and (carrying == [1])

    # the null: a corrupted route, one mode dropped, does not match the energy
    order = 2
    full = torus.parseval(generic_velocity[order], generic_velocity[order])
    dropped_axis = generic_velocity[order][0]
    some_mode = next(iter(dropped_axis.modes))
    corrupted_component = torus.Scalar({mode: poly for mode, poly in dropped_axis.modes.items()
                                        if mode != some_mode}, dropped_axis.den)
    corrupted = (corrupted_component, generic_velocity[order][1], generic_velocity[order][2])
    corruption_caught = torus.parseval(corrupted, corrupted) != full

    out.write("    energy from the velocity route equals the vorticity route, orders 0..%d: %s\n"
              % (ROUTE_DEPTH, routes_agree))
    out.write("    shell energies sum to the total at every order (Parseval): %s\n" % decomposition_holds)
    out.write("    null, ABC energy stays in |k|^2 = 1 at every order (no cascade): %s\n" % abc_only_base)
    out.write("    null, a route with one mode dropped is caught: %s\n\n" % corruption_caught)
    return routes_agree and decomposition_holds and abc_only_base and corruption_caught


def report_growth(out):
    """The coefficient growth: an exact constant rate for ABC (radius infinite), the horizon for a generic datum."""
    out.write("  the growth of the coefficients: whose limit is the reciprocal of the analyticity time\n")
    abc = torus.abc_field((1, 1), (2, 1), (3, 1))
    generic = torus.generic_field()
    abc_velocity, _ = torus.taylor_velocity(abc, torus.VISCOSITY, DEPTH)
    generic_velocity, _ = torus.taylor_velocity(generic, torus.VISCOSITY, DEPTH)

    # ABC: E(u_{m+1}) = (16 nu^2 pi^4) E(u_m), an exact ring scalar, constant in m
    rate = torus.decay_rate(torus.VISCOSITY, -4)
    rate_squared = ratio_mul(rate, rate)                 # 16 nu^2 pi^4, the energy rate
    abc_energies = [torus.parseval(abc_velocity[step], abc_velocity[step]) for step in range(DEPTH + 1)]
    law_holds = all(abc_energies[step + 1] == ratio_mul(abc_energies[step], rate_squared)
                    for step in range(DEPTH))
    rate_constant = law_holds  # the same exact factor at every order. The rate does not depend on m

    out.write("    ABC energy rate E(u_{m+1})/E(u_m) = 16 nu^2 pi^4 = %s, exact and constant in m: %s\n"
              % (rate_squared, law_holds))
    out.write("    a constant rate makes sum u_m t^m/m! = e^(-4 nu pi^2 t) u_0, entire: the radius is\n")
    out.write("    infinite and this datum never blows up (matches the closed form in the sibling file): %s\n"
              % rate_constant)

    # a generic datum: the exact per-order energies and their pi-degree, with the limit left unreached
    out.write("    generic datum, exact energy and its pi-degree per order (the coefficients grow):\n")
    degrees = []
    for step in range(DEPTH + 1):
        energy = torus.parseval(generic_velocity[step], generic_velocity[step])
        degree = pi_degree(energy)
        degrees.append(degree)
        out.write("    order %d: pi-degree %s, energy %s\n" % (step, degree, energy))
    degree_grows = all(degrees[step + 1] > degrees[step] for step in range(DEPTH))

    out.write("    the pi-degree of the energy rises every order: %s (an exact integer signal of growth)\n"
              % degree_grows)
    out.write("    the limit that fixes the analyticity radius needs infinitely many orders and a step\n")
    out.write("    outside exact arithmetic; no finite order reaches it. That is the completeness floor,\n")
    out.write("    the shape of the horizon on the zeros of zeta, and it claims nothing about (A)-(D).\n\n")
    return law_holds and rate_constant and degree_grows


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Navier-Stokes on the unit torus: the cascade and the coefficient growth, exact, nothing claimed\n\n")
    results = [
        report_front(out),
        report_energy(out),
        report_growth(out),
    ]
    if all(results):
        out.write("  every check lands: the generic datum's energy reaches a finer scale each order while the\n")
        out.write("  ABC datum stays in one shell, both routes and the Parseval sum agree to the integer, and the\n")
        out.write("  coefficient growth is an exact constant for ABC and a horizon, not a limit, for the generic datum.\n")
    else:
        out.write("  a check missed: refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
