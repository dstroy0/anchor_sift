#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-026
#
# The phase of the Riemann zeta function read finer than its reader: three sign verdicts give an eighth
# of a turn, and the same three verdicts under evenly spaced jitter give the phase to any fraction of it.
#
#   Usage:  python examples/0_experimental/exact_zeta_phase.py [jitters]
#
# This reads no corpus. It sits in 0_experimental and is an entry in the analytic number theory
# workbook, on its rail: it claims nothing about the Riemann hypothesis. It reads the phase at the
# points it is asked for and stops there.
#
# THE READER
#
# exact_zeta_zeros.py reads zeta at a point through three sign verdicts: the sign of the real part, the
# sign of the imaginary part, and the sign of |Re| - |Im|. Together they name the eighth of a turn zeta
# sits in. The reader never forms an angle and never divides.
#
# THE JITTER
#
# Rotate the value by j / J of an eighth turn for j = 0 .. J - 1 and read each rotation with the same
# three verdicts. With the phase u counted in eighths, reading j is floor(u + j / J), and Hermite's
# identity sums them exactly:
#
#     sum over j < J of floor(u + j / J) = floor(J u).
#
# The mean of J coarse readings is the phase to 1 / J of an eighth, an equality and not an estimate.
# Each jitter adds its verdict and none is discarded. The jitter has to be evenly spaced across one
# whole eighth: the same offset read J times returns the coarse reading J times, and offsets spread
# across half an eighth bias the mean toward the step they never reach.
#
# THE TURN BETWEEN JITTERS
#
# Euler's e^(ia) turns the value one way at a known rate, and across all J jitters it turns less than
# an eighth. The lifted reading is therefore 0 up to one crossing and 1 after it, and two jitters that
# read alike read alike at every jitter between them. The crossing is found by bisection in log2 J + 1
# readings in place of J, and the sum is J k0 + J - j*. Both routes run in the control and must agree.
#
# THE DEPTH
#
# The value is read at a count of places by exact_zeta_zeros.py's two routes, N doubling until they
# agree. The jittered index is read at those places and again at twice them, and the places double
# until the two indices agree. The reader cannot draw more out of a value than the value holds, and
# the depth each point needs is decided by that agreement, not assigned in advance.
#
# THE LINE
#
# On Re(s) = 1/2, zeta = e^(-i theta) Z with Z real, and the phase of zeta is -theta up to a half turn.
# theta comes by a second route, Stirling's series in exact_zeta_gram.py, which shares nothing with the
# sign reader. Where Z changes sign the phase jumps a half turn, and each published zero falls inside
# a step where the jittered phase jumps.
#
# Positive control: e^(i pi / 3), whose phase is 4/3 of an eighth, read as floor(4J / 3) / J for every
# J; and the line against -theta. Drawn nulls: the repeated offset and the half spread, each blind to
# the third of an eighth above the step.

import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "0_experimental"))
import manifest  # noqa: E402,F401
from exact_zeta_gram import theta_routes  # noqa: E402
from exact_zeta_zeros import GUARD, PUBLISHED, agreed_value, below, compare, cos_sin, decimal, pair, pi  # noqa: E402
from representation.exact import units  # noqa: E402


def octant(re, im):
    """The reader: three sign verdicts name the eighth of a turn, or None where any of them is zero."""
    sign_re, sign_im = compare(re, 0), compare(im, 0)
    sign_size = compare(abs(re), abs(im))
    if not (sign_re and sign_im and sign_size):
        return None
    quadrant = (1 - sign_im) + (1 - sign_re * sign_im) // 2
    return 2 * quadrant + ((1 - sign_size) // 2 + quadrant) % 2


class Rotated:
    """re + i im at `places`, read by the three verdicts after a rotation by j / J of numerator /
    denominator of an eighth. Counts the readings it takes."""

    def __init__(self, re, im, places, jitters, numerator=1, denominator=1):
        self.digits = places + GUARD
        self.re, self.im = re * 10 ** GUARD, im * 10 ** GUARD
        self.step = numerator * pi(self.digits) // (4 * jitters * denominator)
        self.jitters = jitters
        self.readings = 0

    def lift(self, j, first):
        """The reading at jitter j, lifted onto the first: 0 or 1, or None where a verdict is zero."""
        self.readings += 1
        scale = 10 ** self.digits
        c, s = cos_sin(j * self.step, self.digits)
        reading = octant((self.re * c - self.im * s) // scale, (self.re * s + self.im * c) // scale)
        if reading is None or (first is not None and (reading - first) % 8 > 1):
            return None
        return reading if first is None else (reading - first) % 8


def jittered_every(rotated):
    """Hermite's sum by reading every jitter, j = 0 .. J - 1. None where a verdict is zero."""
    first = rotated.lift(0, None)
    if first is None:
        return None
    lifts = [rotated.lift(j, first) for j in range(1, rotated.jitters)]
    if None in lifts:
        return None
    return rotated.jitters * first + sum(lifts)


def jittered(rotated):
    """Hermite's sum by bisection. The rotation e^(ia) turns the phase one way and by less than an
    eighth over all J jitters. The lifted reading is 0 up to one crossing and 1 after it: two
    jitters that read alike read alike at every jitter between them. The crossing j* is found in
    log2 J readings and the sum is J k0 + J - j*. None where a verdict is zero."""
    first = rotated.lift(0, None)
    if first is None:
        return None
    low, high = 0, rotated.jitters
    while high - low > 1:
        middle_jitter = (low + high) // 2
        lift = rotated.lift(middle_jitter, first)
        if lift is None:
            return None
        low, high = (middle_jitter, high) if lift == 0 else (low, middle_jitter)
    return rotated.jitters * first + rotated.jitters - high


def phase_at(sigma, t, jitters, places=8):
    """The jittered index of zeta at sigma + i t, at the shallowest places where it agrees with the
    index read at twice the places. Returns the index, in 1 / J of an eighth, and those places."""
    while True:
        one, _, _ = agreed_value(sigma, t, places)
        two, _, _ = agreed_value(sigma, t, 2 * places)
        index = jittered(Rotated(one[0], one[1], places, jitters))
        if index is not None and index == jittered(Rotated(two[0], two[1], 2 * places, jitters)):
            return index, places
        places *= 2


def theta_at(t, places):
    """theta at `places` by Stirling's two routes, N doubling until they agree."""
    n_sum = 1
    one, two = theta_routes(t, places, n_sum)
    while one != two:
        n_sum *= 2
        one, two = theta_routes(t, places, n_sum)
    return two


def turns(index, jitters, places=6):
    return decimal(pair(index * 10 ** places // (8 * jitters), places), places)


def report_control(out, top):
    """Section one: e^(i pi / 3) read at every J against floor(4J / 3), and the two nulls."""
    places = 30
    digits = places + GUARD
    c, s = cos_sin(pi(digits) // 3, digits)
    re, im = c // 10 ** GUARD, s // 10 ** GUARD
    out.write("  control: e^(i pi / 3), its phase 4/3 of an eighth, in eighths\n")
    out.write("  %-6s %-12s %-12s %-16s %-16s %-14s %s\n"
              % ("J", "bisected", "floor(4J/3)", "every jitter", "readings", "same offset", "half spread"))
    exact = blind = True
    jitters = 1
    while jitters <= top:
        bisect = Rotated(re, im, places, jitters)
        every = Rotated(re, im, places, jitters)
        index, swept = jittered(bisect), jittered_every(every)
        same = jitters * jittered(Rotated(re, im, places, 1))
        narrow = jittered(Rotated(re, im, places, jitters, 1, 2))
        exact = exact and index == swept == 4 * jitters // 3
        blind = blind and same == narrow == jitters
        out.write("  %-6d %-12s %-12s %-16s %-16s %-14s %s\n"
                  % (jitters, "%d/%d" % (index, jitters), "%d/%d" % (4 * jitters // 3, jitters),
                     "%d/%d" % (swept, jitters), "%d against %d" % (bisect.readings, every.readings),
                     "%d/%d" % (same, jitters), "%d/%d" % (narrow, jitters)))
        jitters *= 4
    out.write("\n  bisection and the full sweep both equal floor(4J/3) at every J: %s. the same offset and\n" % exact)
    out.write("  the half spread stay on the coarse reading at every J: %s.\n\n" % blind)
    return exact and blind


def report_line(out, top):
    """Section two: the phase on the line through the first zero, every J, against -theta."""
    out.write("  the line Re(s) = 1/2 from t = 14 to t = 15, the phase of zeta in turns\n")
    columns = [4 ** k for k in range(8) if 4 ** k <= top]
    out.write("  %-6s %s  %s\n" % ("t", " ".join("%-10s" % ("J=%d" % j) for j in columns), "-theta"))
    agree = True
    for step in range(11):
        t = pair(140 + step, 1)
        readings = [phase_at((5, 1), t, j)[0] for j in columns]
        theta = theta_at(t, 40)
        half_turn = pi(40)
        index_theta = 4 * columns[-1] * ((-theta) % half_turn) // half_turn
        held = readings[-1] % (4 * columns[-1]) == index_theta
        agree = agree and held
        out.write("  %-6s %s  %s\n" % (decimal(t, 1), " ".join("%-10s" % turns(r, j) for r, j in zip(readings, columns)),
                                       "agrees" if held else "FAIL"))
    out.write("\n  every point agrees with -theta up to a half turn at J = %d: %s\n\n" % (columns[-1], agree))
    return agree


def report_flips(out, jitters):
    """Section three: the half-turn jumps from t = 14 to t = 26, each holding one published zero."""
    out.write("  the flips: steps of a quarter from t = 14 to t = 26 where the phase jumps a half turn\n")
    quarter = 8 * jitters // 4
    last = None
    brackets = []
    t = pair(14, 0)
    while below(t, pair(26, 0)) or t == pair(26, 0):
        index, _ = phase_at((5, 1), t, jitters)
        if last is not None:
            jump = (index - last[1]) % (8 * jitters)
            if quarter < jump < 3 * quarter:
                brackets.append((last[0], t))
        last = (t, index)
        t = pair(t[0] * 10 ** (2 - t[1]) + 25, 2)
    held = []
    for low, high in brackets:
        inside = [p for p in PUBLISHED if below(low, units(p)) and below(units(p), high)]
        held.append(len(inside) == 1)
        out.write("  [%s, %s]  holds %s\n" % (decimal(low, 2), decimal(high, 2), ", ".join(inside) or "none"))
    published = [p for p in PUBLISHED if below(pair(14, 0), units(p)) and below(units(p), pair(26, 0))]
    every = all(held) and len(brackets) == len(published)
    out.write("\n  %d flips, each holding one of the %d published zeros in the span: %s\n" % (len(brackets), len(published), every))
    return every


def main():
    out = sys.stdout
    top = int((sys.argv[1:] + ["64"])[0])
    out.write("  the phase of zeta read finer than its reader, by evenly spaced jitter and Hermite's identity\n")
    out.write("  it claims nothing about the Riemann hypothesis\n\n")
    control = report_control(out, top)
    line = report_line(out, top)
    flips = report_flips(out, 16)
    out.flush()
    return 0 if (control and line and flips) else 1


if __name__ == "__main__":
    raise SystemExit(main())
