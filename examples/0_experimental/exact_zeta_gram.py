#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-022
#
# The Riemann-Siegel theta function, the Gram points, and the sign of Z at each, by truthy and falsy
# verdicts on exact integers. Every verdict is a field, zero false and nonzero true, and a pass writes
# its verdicts for the next pass to read, as in exact_zeta_zeros.py, whose values this reads.
#
#   Usage:  python examples/0_experimental/exact_zeta_gram.py [height] [bits]
#
# This reads no corpus. It sits in 0_experimental and is an entry in the analytic number theory
# workbook, on its rail: it claims nothing about the Riemann hypothesis.
#
# THE PHASE
#
# theta(t) = Im ln Gamma(1/4 + it/2) - (t/2) ln pi. With z = 1/4 + it/2 and w = z + M,
# ln Gamma(z) = ln Gamma(w) - sum over k < M of ln(z + k), and ln Gamma(w) by Stirling's series with
# K Bernoulli terms. Its imaginary part is (M - 1/4) arg w + (t/4) ln |w|^2 - t/2, plus the imaginary
# parts of B_2j / (2j (2j - 1)) w^(1 - 2j), less every arg(z + k). Each arg is an arctangent of a
# rational, by two series that must agree: Euler's, with its own pi from Euler's identity, and the
# Taylor series about 1/2, with its own pi from Machin's. ln comes from the two series in
# exact_zeta_zeros.py, and ln pi from the logarithm of pi's floor. pi is held as its real and its
# operator: the floor at the places asked, and naturals.pi, asked again for more. Two routes run, at
# M = K = N and at 2N, and where they disagree N doubles.
#
# THE GRAM INDEX
#
# g_n is the point where theta(g_n) = n pi. At a point, the index i is theta read at its places over
# pi, and the point is decided where theta reads strictly above i pi and strictly below (i + 1) pi,
# each read toward zero at the same places. A reading of equal doubles the places. A strict order of
# two readings toward zero is the order of the reals themselves.
#
# THE WALK
#
# Up from t = 10 in cells. theta increases past t = 6.29, as the Riemann-Siegel theta article on
# Wikipedia reports, and a cell holds as many Gram points as its ends' indices differ by. An empty
# cell doubles the step, a cell holding one is a bracket, and a cell holding more splits into halves. Each bracket is then placed by bits, one pass per bit: the
# index at the midpoint gates which half the next pass reads.
#
# THE SIGN OF Z
#
# zeta(1/2 + it) = e^(-i theta) Z(t) with Z real, read by exact_zeta_zeros.py. Just below g_n,
# Im zeta has the sign of Re zeta, and just above, the opposite sign: this phase verdict ties theta,
# from Stirling, to the phase of zeta, from Euler-Maclaurin. A bracket is settled where the phase
# verdict holds at both ends, Re zeta has one nonzero sign at both, and the step verdict holds at
# both. Otherwise the bracket is cut in half by the index at its midpoint. On a settled bracket the
# sign of Re zeta is the sign of (-1)^n Z(g_n), and Gram's law is that sign positive.
#
# GRAM'S LAW AS AN AGREEMENT
#
# The signs of Z(g_n) alternate where Gram's law holds, which is agreement at lag 2 and none at lag
# 1, read by measure.shift_agreement.exact_agreement. The null is reference.shuffles.permuted: the
# same signs in drawn orders, and the count of draws that reach the live agreement at lag 2.
#
# Positive control: the Gram points g_0 to g_15 against the table the Riemann-Siegel theta article
# on Wikipedia prints, and the first failure of Gram's law at n = 126, as the same article reports
# it, both read by a web fetch. Drawn null: the Bernoulli terms left out of both routes of theta,
# where the routes do not meet at the doublings shown and no Gram index is decided.

import os
import sys
from functools import cache
from itertools import compress

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "0_experimental"))
import manifest  # noqa: E402,F401
import exact_zeta_zeros as zz  # noqa: E402
from exact_zeta_zeros import NOT, below, compare, decimal, half, holds, middle, plus, select, twice  # noqa: E402
from measure.shift_agreement import exact_agreement  # noqa: E402
from reference.shuffles import SEED, permuted  # noqa: E402
from representation.constants import naturals  # noqa: E402
from representation.exact import units  # noqa: E402

GUARD = naturals.GUARD

# The Riemann-Siegel theta article on Wikipedia, its table of the smallest Gram points, g_0 to g_15.
PUBLISHED = ("17.8455995405", "23.1702827012", "27.6701822178", "31.7179799547", "35.4671842971",
             "38.9992099640", "42.3635503920", "45.5930289815", "48.7107766217", "51.7338428133",
             "54.6752374468", "57.5451651795", "60.3518119691", "63.1018679824", "65.8008876380",
             "68.4535449175")

# The same article: Gram's law first fails at index 126.
FIRST_FAILURE = 126

START = (10, 0)
LINE = (5, 1)
DRAWS = 1000


# ---- the arctangent of a rational, by two series that must agree ----

@cache
def _pi_machin(scale):
    return naturals._pi_machin(scale)


@cache
def _pi_euler(scale):
    return naturals._pi_euler(scale)


def _turned(x, y):
    """(a, c, g) with a / c = min(x/y, y/x) and g the verdict that x > y, for x, y > 0."""
    g = int(x > y)
    return x + g * (y - x), y + g * (x - y), g


def _arctan_euler(x, y, scale):
    """floor-wise arctan(x / y), x, y > 0, by Euler's series in x^2 / (x^2 + y^2), pi from Euler's identity."""
    a, c, g = _turned(x, y)
    size = a * a + c * c
    term = scale * a * c // size
    total = term
    step = 1
    while term != 0:
        term = term * 2 * step * a * a // ((2 * step + 1) * size)
        total += term
        step += 1
    return g * (_pi_euler(scale) // 2) + (1 - 2 * g) * total


def _arctan_taylor(x, y, scale):
    """floor-wise arctan(x / y), x, y > 0, as arctan(1/2) + arctan((2a - c) / (2c + a)), pi from Machin's."""
    a, c, g = _turned(x, y)
    top, bottom = 2 * a - c, 2 * c + a
    sign = compare(top, 0)
    top = abs(top)
    power = scale * top // bottom
    total = 0
    step = 0
    while power != 0:
        total += power // (2 * step + 1) * (1 - 2 * (step % 2))
        power = power * top * top // (bottom * bottom)
        step += 1
    return g * (_pi_machin(scale) // 2) + (1 - 2 * g) * (naturals._arctan_inverse(2, scale) + sign * total)


@cache
def arctan(x, y, digits):
    return naturals._agree(lambda scale: _arctan_euler(x, y, scale), lambda scale: _arctan_taylor(x, y, scale),
                           digits, "arctan %d/%d" % (x, y))


# ---- theta ----

@cache
def ln_pi(digits):
    """ln pi at `digits` places, from the floor of pi at those places: ln floor(pi 10^d) - d ln 10."""
    return zz.ln(zz.pi(digits), digits) - digits * zz.ln(10, digits)


def theta_route(t, digits, shift, terms):
    """theta(t) at `digits` places by Stirling's series at w = 1/4 + it/2 + shift, with `terms` Bernoulli terms.

    w = (a + ib) / d with a = (1 + 4 shift) 10^q, b = 2T, d = 4 10^q, for t = T / 10^q. The imaginary
    part of w^(1-2j) is Im (a - ib)^(2j-1) d^(2j-1) / (a^2 + b^2)^(2j-1), every factor an integer."""
    scale = 10 ** digits
    big_t, q = t
    unit = 10 ** q
    a, b, d = (1 + 4 * shift) * unit, 2 * big_t, 4 * unit
    size = a * a + b * b
    lead = ((4 * shift - 1) * arctan(b, a, digits) // 4
            + big_t * (zz.ln(size, digits) - 2 * zz.ln(d, digits)) // (4 * unit)
            - scale * big_t // (2 * unit))
    args = sum(arctan(2 * big_t, (1 + 4 * k) * unit, digits) for k in range(shift))
    correction = 0
    re, im = a, -b
    square_re, square_im = a * a - b * b, -2 * a * b
    d_power, size_power, factorial = d, size, 1
    for j in range(1, terms + 1):
        num, den = zz.bernoulli_over_factorial(j)
        correction += scale * num * factorial * im * d_power // (den * size_power)
        re, im = re * square_re - im * square_im, re * square_im + im * square_re
        d_power *= d * d
        size_power *= size * size
        factorial *= (2 * j - 1) * (2 * j)
    return lead + correction - args - big_t * ln_pi(digits) // (2 * unit)


def toward_zero(v):
    return compare(v, 0) * (abs(v) // 10 ** GUARD)


def theta_routes(t, places, n_sum, bernoulli=1):
    """theta at `places` by the two routes, N and 2N, each read toward zero."""
    digits = places + GUARD
    return (toward_zero(theta_route(t, digits, n_sum, n_sum * bernoulli)),
            toward_zero(theta_route(t, digits, 2 * n_sum, 2 * n_sum * bernoulli)))


def pi_times(i, big_pi):
    """i pi read toward zero at the places big_pi carries less the guard."""
    return compare(i, 0) * (abs(i) * big_pi // 10 ** GUARD)


# ---- the steering ----

class Gram:
    """The Gram index decided at each point, and what deciding it cost."""

    def __init__(self):
        self.index = {}
        self.theta = {}
        self.asked = 0
        self.deepest = 0
        self.widest = 0

    def sweep(self, points):
        """Decide each point's Gram index, pass by pass, each pass reading the last one's verdicts."""
        fresh = list(dict.fromkeys(points))
        open_points = [(p, 1, 1) for p in compress(fresh, [int(p not in self.index) for p in fresh])]
        while open_points:
            records = []
            for point, places, n_sum in open_points:
                self.asked += 1
                one, two = theta_routes(point, places, n_sum)
                agree = NOT(one - two)
                big_pi = zz.pi(places + GUARD)
                i = one * 10 ** GUARD // big_pi
                low = compare(one, pi_times(i, big_pi))
                high = compare(pi_times(i + 1, big_pi), one)
                decided = agree * ((1 + low) // 2) * ((1 + high) // 2)
                records.append((point, places, n_sum, agree, i, one, decided))
            for point, places, n_sum, _, i, one, _ in compress(records, [r[6] for r in records]):
                self.index[point] = i
                self.theta[point] = (one, places)
                self.deepest = max(self.deepest, places)
                self.widest = max(self.widest, n_sum)
            open_points = [(point, places * (1 + agree), n_sum * (2 - agree))
                           for point, places, n_sum, agree, *_ in compress(records, [NOT(r[6]) for r in records])]

    def walk(self, height):
        """Up from START. Each pass reads the indices at the open cells' ends and gates the next cells."""
        found = []
        cells = []
        low, step = START, (1, 0)
        while below(low, height) or cells:
            top = below(low, height)
            high = select(below(plus(low, step), height), plus(low, step), height)
            asked = cells + [(low, high)] * top
            self.sweep([t for cell in asked for t in cell])
            counts = [self.index[h] - self.index[lo] for lo, h in asked]
            found += [(lo, h, self.index[h]) for lo, h in compress(asked, [NOT(n - 1) for n in counts])]
            cells = [part for cell in compress(asked, [int(n > 1) for n in counts]) for part in halves(cell)]
            last = counts[-1] * top
            step = select(NOT(last), twice(step), select(int(last > 1), half(step), step))
            low = select(top, high, low)
        return sorted(found, key=lambda bracket: bracket[2])

    def cut(self, brackets):
        """Each bracket cut in half by the Gram index at its midpoint."""
        mids = [middle(lo, h) for lo, h, _ in brackets]
        self.sweep(mids)
        kept = [int(self.index[m] >= n) for m, (_, _, n) in zip(mids, brackets)]
        return [(select(v, lo, m), select(v, m, h), n) for v, m, (lo, h, n) in zip(kept, mids, brackets)]

    def place(self, brackets, bits):
        for _ in range(bits):
            brackets = self.cut(brackets)
        return brackets

    def settle(self, brackets, zeta):
        """Cut each bracket until zeta settles the sign of Re zeta(1/2 + it) on it."""
        signs, settled_brackets = {}, {}
        cuts = 0
        while brackets:
            zeta.sweep([(LINE, t) for lo, h, _ in brackets for t in (lo, h)])
            records = []
            for lo, h, n in brackets:
                a, c = (LINE, lo), (LINE, h)
                re_a, im_a = zeta.values[a][:2]
                re_c, im_c = zeta.values[c][:2]
                sign_a, sign_c = compare(re_a, 0), compare(re_c, 0)
                phase = NOT(compare(im_a, 0) - sign_a) * NOT(compare(im_c, 0) + sign_c)
                same = NOT(sign_a - sign_c)
                from_a, from_c = zeta.step(a, c, a), zeta.step(a, c, c)
                records.append(((lo, h, n), sign_a, phase * same * ((1 + from_a) // 2) * ((1 + from_c) // 2)))
            for (lo, h, n), sign, _ in compress(records, [r[2] for r in records]):
                signs[n] = sign
                settled_brackets[n] = (lo, h)
            brackets = self.cut([r[0] for r in compress(records, [NOT(r[2]) for r in records])])
            cuts += len(brackets)
        return signs, settled_brackets, cuts


def halves(cell):
    lo, h = cell
    m = middle(lo, h)
    return [(lo, m), (m, h)]


def theta_gap(t, places, n_sum, bernoulli=1):
    one, two = theta_routes(t, places, n_sum, bernoulli)
    return abs(one - two)


def main():
    out = sys.stdout
    height = units((sys.argv[1:] + ["285"])[0])
    bits = int((sys.argv[2:] + ["16"])[0])
    out.write("  the Riemann-Siegel theta function and the Gram points by truthy and falsy verdicts,"
              " in exact integers\n")
    out.write("  this reads the sign of Z at the Gram points it reaches and claims nothing about"
              " the Riemann hypothesis\n\n")

    gram = Gram()
    found = gram.walk(height)
    indices = [n for _, _, n in found]
    consecutive = NOT(len(indices) - (indices[-1] + 1)) * NOT(indices[0])
    out.write("  %d Gram points with 10 < t < %s, indices 0 to %d, each alone in its bracket: %s\n"
              % (len(found), decimal(height, height[1]), indices[-1], bool(consecutive)))
    out.flush()
    placed = gram.place(found, bits)
    out.write("  %-5s %-34s %-15s %s\n" % ("n", "placed by %d bits" % bits, "published", "holds"))
    every = 1
    for (lo, h, n), published in zip(placed, PUBLISHED):
        held = holds(lo, h, published)
        every *= held
        out.write("  %-5d [%s, %s]  %-15s %s\n" % (n, decimal(lo, 10), decimal(h, 10), published, bool(held)))
    out.write("  %d theta values asked, the deepest at %d places, the widest at N = %d\n\n"
              % (gram.asked, gram.deepest, gram.widest))
    out.flush()

    zeta = zz.Steering()
    signs, settled, cuts = gram.settle(placed, zeta)
    ordered = [signs[n] for n in indices]
    bad = list(compress(indices, [NOT(s - (-1)) for s in ordered]))
    out.write("  the sign of (-1)^n Z(g_n), from Re zeta(1/2 + i g_n) on each settled bracket:\n")
    for row in range(0, len(indices), 32):
        out.write("    %4d  %s\n" % (indices[row], "".join("+-"[(1 - s) // 2] for s in ordered[row:row + 32])))
    out.write("  Gram's law fails at n = %s\n" % (", ".join("%d" % n for n in bad) + "none" * NOT(len(bad))))
    for n in bad:
        lo, h = settled[n]
        out.write("    g_%d in [%s, %s]\n" % (n, decimal(lo, 10), decimal(h, 10)))
    out.write("  %d zeta values asked, %d further cuts, the deepest at %d places, the widest at N = %d\n"
              % (zeta.asked, cuts, zeta.deepest, zeta.widest))
    reached = int(indices[-1] >= FIRST_FAILURE)
    first = reached * NOT((bad + [-1])[0] - FIRST_FAILURE) + (1 - reached) * NOT(len(bad))
    out.write("  the first failure against the reported index %d: %s\n\n" % (FIRST_FAILURE, bool(first)))
    out.flush()

    sequence = [s * (1 - 2 * (n % 2)) for n, s in zip(indices, ordered)]
    seats = bytes((1 + s) // 2 for s in sequence)
    live_one = exact_agreement(dict(enumerate(seats)), 1)
    live_two = exact_agreement(dict(enumerate(seats)), 2)
    shuffled = [exact_agreement(dict(enumerate(permuted(seats, SEED + d))), 2) for d in range(DRAWS)]
    reach = sum(int(a >= live_two) for a in shuffled)
    plus_count = sum(seats)
    out.write("  the signs of Z(g_n), %d positive and %d negative, as a sequence\n"
              % (plus_count, len(seats) - plus_count))
    out.write("    agreement at lag 1: %d of %d, at lag 2: %d of %d\n"
              % (live_one, len(seats) - 1, live_two, len(seats) - 2))
    out.write("    %d drawn orders of the same signs, %d reaching %d at lag 2, the most %d\n"
              % (DRAWS, reach, live_two, max(shuffled)))
    enough = int(min(plus_count, len(seats) - plus_count) >= 32)
    alternates = int(live_two > max(shuffled)) * enough
    out.write("  agreement at lag 2 above every drawn order, with 32 or more of each sign: %s\n\n" % bool(alternates))
    out.flush()

    point = (20, 0)
    places = 8
    true_gaps = [theta_gap(point, places, 1 << j) for j in range(6)]
    null_gaps = [theta_gap(point, places, 1 << j, bernoulli=0) for j in range(6)]
    out.write("  drawn null at t = 20, %d places: the gap between the two routes of theta"
              " as N doubles from 1\n" % places)
    out.write("    with the Bernoulli terms:     %s\n" % true_gaps)
    out.write("    without them:                 %s\n" % null_gaps)
    apart = NOT(true_gaps[-1]) * int(null_gaps[-1] > 0)
    out.write("  without the Bernoulli terms the routes do not meet at the doublings shown: %s\n" % bool(apart))
    return 1 - consecutive * every * first * alternates * apart


if __name__ == "__main__":
    raise SystemExit(main())
