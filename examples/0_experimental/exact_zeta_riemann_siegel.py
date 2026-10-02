#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-023
#
# Z(t) by the Riemann-Siegel formula, with time held as a real and the delta between 0 and 1 left
# free, by truthy and falsy verdicts on exact integers.
#
#   Usage:  python examples/0_experimental/exact_zeta_riemann_siegel.py [height] [bits]
#           python examples/0_experimental/exact_zeta_riemann_siegel.py triangle first last [cut ...]
#
# This reads no corpus. It sits in 0_experimental and is an entry in the analytic number theory
# workbook, on its rail: it claims nothing about the Riemann hypothesis.
#
# THE FORMULA, AS MATHWORLD PRINTS IT
#
# Z(t) = 2 sum over n <= N of n^(-1/2) cos(theta(t) - t ln n) + R(t), with N the floor of
# sqrt(t / 2pi), p = sqrt(t / 2pi) - N, and R(t) = (-1)^(N-1) (t / 2pi)^(-1/4) times the sum of
# c_k(p) (t / 2pi)^(-k/2). Each c_k is a sum of derivatives of
# Psi(p) = cos 2pi(p^2 - p - 1/16) / cos 2pi p over powers of pi, and c_0 to c_5 are printed.
#
# TIME AS A REAL
#
# The steer is u, and t = 2pi u^4. No square root is taken and nothing is divided by 2pi: N is the
# floor of u^2, p = u^2 - N exactly, and (t / 2pi)^(-1/4 - k/2) = u^-(2k+1), an exact rational. t is
# held as its real and its operator, pi's floor at the places asked and naturals.pi asked again for
# more. The delta p is between 0 and 1 and is never fixed; a deeper reading asks it for more places.
#
# TWO MAGNITUDES FOR ONE PHASE
#
# Each term of the sum is the pair n^(-1/2) e^(-it ln n), from exact_zeta_zeros.py, and theta turns
# the summed pair by e^(i theta). Psi is held as the pair of its numerator and its denominator, each a
# power series about p, and never divided: with d the denominator's first coefficient,
# Psi^(j)(p) / j! = r_j / d^(j+1), and r_j comes from the two series by products alone. Every c_k is
# carried times d^16 pi^10, a multiplier that is never negative, and Z with it: the sign of Z is
# the sign of the carried product. Where d reads zero at the working places, both series lose their
# first coefficient and the next one stands in: the numerator vanishes where the denominator does,
# at p = 1/4 and p = 3/4.
#
# THE VERDICTS AT A POINT
#
# theta by exact_zeta_gram.py's two routes, N doubling where they disagree. The carried Z read
# toward zero at the places asked, a reading of zero doubling the places. The last printed term,
# c_5 u^-11, read against Z at the same places: whether Z reads past the series' own last term
# there. That is a reading, recorded per point, and the series sets its own reach at that t.
#
# THE WALK
#
# exact_zeta_gram.py's walk and placing, stepping in u with theta read at t = 2pi u^4. A bracket is
# settled where Z has one nonzero sign at both ends; otherwise it is cut by the Gram index at its
# midpoint.
#
# THE BOUNDARY BETWEEN THE TWO PAIRS
#
# Two pairs follow two curves each. Riemann-Siegel and Euler-Maclaurin both give Z: Euler-Maclaurin
# over the whole strip, its two routes meeting as N doubles, and Riemann-Siegel on the line, a series in
# u that stops at c_5. Inside Riemann-Siegel, the main sum S and the remainder R split Z between them
# at nu = floor(x), x = u^2 = sqrt(t / 2pi), t = 2pi x^2.
#
# The domain is x, cut into cells [nu, nu + 1], and on each cell p = x - nu runs over [0, 1]. Psi is
# symmetric, Psi(1 - p) = Psi(p), and c_k(1) = (-1)^k c_k(0). Where x crosses nu + 1, S gains the term
# 2 (nu + 1)^(-1/2) cos(theta - t ln(nu + 1)), which is 2 (-1)^(nu+1) cos(pi/8) / u to its first order,
# and R turns from (-1)^(nu-1) sum c_k(1) u^-(2k+1) to (-1)^nu sum c_k(0) u^-(2k+1), a jump of
# 2 (-1)^nu sum over even k of c_k(0) u^-(2k+1). The two jumps meet and Z is continuous; what is left of
# them is the jump of the terms R leaves out, the seam read by `seam`.
#
# Over each cell, with D = Z_RS - Z_EM and E = S - R, three sides: a = int |D| dp, b = int |E| dp, and
# c = int |(D, E)| dp, the magnitude of the two held as one vector. c <= a + b and c >= b: the three
# close a triangle. c is read as b + delta, delta = int D^2 / (|(D, E)| + |E|) dp. c - b never
# cancels, and the angle opposite c is cos gamma = (a^2 - 2b delta - delta^2) / 2ab. Where |D| follows
# |E| across the cell the angle is right, and it is never less: the size of the integral of (|D|, |E|)
# is at most the integral of its size, which is c. a is small against b and the triangle is a needle,
# and a needle is still a triangle: its angle past right is nonzero, and two sides apart by any
# nonzero angle part without bound. The shape is the excess kappa = (c^2 - a^2 - b^2) / a^2, and the
# angle is cos gamma = -kappa a / 2b, each read at the places where it shows. Each integral is the
# trapezoid on 2^m and 2^(m+1) equal parts of p, two routes that must agree.
#
# Where S and R cross, E is zero and delta's integrand is a spike of height |D| and width |D / E'|,
# about 10^-12 of p: no grid reaches it, and the trapezoid on it grows as ln(1 / h) with every
# doubling. What grows is held as its relation. With D0 = D(p0) and k = |E'(p0)| at each crossing,
# the spike is g(u) = D0^2 / (sqrt(D0^2 + k^2 u^2) + k |u|), u = p - p0, and its integral from 0 to L is
# (L D0^2 / (sqrt(D0^2 + k^2 L^2) + kL) + (D0^2 / k) asinh(kL / |D0|)) / 2, exact. delta is the sum of
# those and the trapezoid of what is left, which no longer grows. The crossings are E's sign changes,
# read from Riemann-Siegel alone and each halved to 2^-64.
#
# EVERY C_n, HELD AS ITS REAL AND ITS OPERATOR
#
# With z = 1 - 2p and F(z) = Psi(p), Gabcke's generator (Table III and Satz 2.1.4 of his thesis) gives
# every coefficient: C_n(z) = 2^(-2n) times the sum over k of d_k^(n) F^(3n-4k)(z) / ((3n - 4k)! pi^(2n-2k)),
# with d_k^(n+1) = (3n + 1 - 4k)(3n + 2 - 4k) d_k^(n) + d_(k-1)^(n), except d_3l^(4l) = lambda_l, where
# (l + 1) lambda_(l+1) = sum over k of 2^(4k+1) |E_(2k+2)| lambda_(l-k) on the Euler numbers. Every d is an
# integer. F is entire and even, F(z) = sum phi_j z^(2j), and phi_j is the product of the series of
# cos(pi z^2 / 2 + 3pi/8) and of sec(pi z): rationals times pi^(2j - m) times sin(pi/8) or cos(pi/8), the
# two being sqrt(2 -+ sqrt 2) / 2. So each C_n is held exactly, every Taylor coefficient a sum of rationals
# times powers of pi and one of two square roots, and only reading it at a point asks for digits.
#
# A reading of C_n at a dyadic z sums its Taylor series on count and 2 count terms, the second at twice
# the extra digits, and the two must agree at the places asked; disagreement doubles count and a reading
# of zero doubles the places. The terms of the sec series grow as 4^j and cancel to F's: the extra
# digits grow with count. The zeros of C_n on [0, 1] are the sign changes read on 2^m and 2^(m+1) parts,
# m growing until the two counts agree, each then halved to the bits asked. An odd C_n is zero at 0 by
# parity, and its sign just past 0 is the sign of its z coefficient. Each zero z gives p = (1 - z) / 2 and
# (1 + z) / 2, and the term C_n u^-(2n+1) vanishes at t = 2pi (N + p)^2 in every cell N.
#
# Positive control: the Gram points g_0 to g_15 against the Riemann-Siegel theta article on
# Wikipedia, each compared with 2pi u^4 by multiplication; the first failure of Gram's law at
# n = 126, as that article reports it; and Z against Euler-Maclaurin's Re e^(i theta) zeta at the same
# real t, the gap in units of the last place. For every C_n: C_0 to C_5 against MathWorld's c_0 to c_5,
# rational for rational; d_k^(8) against Gabcke's Table II; C_0(1) to C_10(1) against the sum row of his
# Table IV at 50 places, within the spread between his Table IV and Table V; and one simple zero each in
# C_4, C_8 and C_10 on 0 < z < 1, as he reports on p. 59. Drawn null: R left out, the Gram signs and the
# gap read again.

import glob
import os
import shutil
import subprocess
import sys
import time
from functools import cache
from itertools import compress
from math import comb, factorial, gcd

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "0_experimental"))
import manifest  # noqa: E402,F401
import exact_zeta_gram as gram  # noqa: E402
import exact_zeta_zeros as zz  # noqa: E402
from exact_zeta_zeros import COS_SIGN, NOT, SIN_SIGN, compare, decimal  # noqa: E402
from representation.constants import naturals  # noqa: E402
from representation.exact import units  # noqa: E402

GUARD = naturals.GUARD
LINE = (5, 1)

# MathWorld, Riemann-Siegel Formula, equations (8) to (13): each c_k as its terms
# (signed numerator, denominator, j, m), a term being numerator / denominator Psi^(j)(p) / pi^(2m).
COEFFICIENTS = (
    ((1, 1, 0, 0),),
    ((-1, 96, 3, 1),),
    ((1, 64, 2, 1), (1, 18432, 6, 2)),
    ((-1, 64, 1, 1), (-1, 3840, 5, 2), (-1, 5308416, 9, 3)),
    ((1, 128, 0, 1), (19, 24576, 4, 2), (11, 5898240, 8, 3), (1, 2038431744, 12, 4)),
    ((-5, 3072, 3, 2), (-901, 82575360, 7, 3), (-7, 849346560, 11, 4), (-1, 978447237120, 15, 5)),
)
DEGREE = 15
PI_POWER = 10
START = (12, 1)
POINTS = ((12, 1), (15, 1), (18, 1), (21, 1), (24, 1), (26, 1))


def toward_zero(v):
    return compare(v, 0) * (abs(v) // 10 ** GUARD)


def time_of(u, digits):
    """t = 2pi u^4 at `digits` places, as a pair: pi's floor at those places times 2u^4."""
    big_u, q = u
    return 2 * big_u ** 4 * zz.pi(digits) // 10 ** (4 * q), digits


def phase(u, places, n_sum):
    """theta's two routes at t = 2pi u^4, for exact_zeta_gram.py's walk."""
    return gram.theta_routes(time_of(u, places + GUARD), places, n_sum)


# ---- Psi as a pair, by products ----

def series_times(a, b, scale):
    out = [0] * len(a)
    for i, x in enumerate(a):
        for j, y in enumerate(b[:len(a) - i]):
            out[i + j] += x * y
    return [v // scale for v in out]


def psi_carried(p, digits):
    """Psi^(j)(p) d^16 for j = 0 .. 15, and d^16, each at `digits`.

    The numerator is cos(phi + alpha h + beta h^2) and the denominator cos(2pi p + 2pi h), each a power
    series in h. With Psi^(j) / j! = r_j / d^(j+1),
    r_k = n_k d^k - sum over j < k of r_j d_(k-j) d^(k-1-j), products alone. Where d reads zero, both
    series start one coefficient later."""
    scale = 10 ** digits
    big_pi = zz.pi(digits)
    x, q = p
    unit = 10 ** q
    phi = 2 * big_pi * (16 * x * x - 16 * x * unit - unit * unit) // (16 * unit * unit)
    alpha = 2 * big_pi * (2 * x - unit) // unit
    cos_phi, sin_phi = zz.cos_sin(phi, digits)
    cos_d, sin_d = zz.cos_sin(2 * big_pi * x // unit, digits)
    length = DEGREE + 2
    delta = [0, alpha, 2 * big_pi] + [0] * (length - 3)
    power = [scale] + [0] * (length - 1)
    cos_part, sin_part = power[:], [0] * length
    factorial = 1
    for m in range(1, length):
        power = series_times(power, delta, scale)
        factorial *= m
        cos_part = [c + COS_SIGN[m % 4] * v // factorial for c, v in zip(cos_part, power)]
        sin_part = [s + SIN_SIGN[m % 4] * v // factorial for s, v in zip(sin_part, power)]
    numerator = [(cos_phi * c - sin_phi * s) // scale for c, s in zip(cos_part, sin_part)]
    grown = [scale]
    for k in range(1, length):
        grown.append(grown[-1] * 2 * big_pi // (scale * k))
    denominator = [(cos_d * COS_SIGN[k % 4] - sin_d * SIN_SIGN[k % 4]) * g // scale for k, g in enumerate(grown)]
    gone = NOT(toward_zero(denominator[0]))
    numerator = [numerator[k] * (1 - gone) + numerator[k + 1] * gone for k in range(DEGREE + 1)]
    denominator = [denominator[k] * (1 - gone) + denominator[k + 1] * gone for k in range(DEGREE + 1)]
    d = denominator[0]
    powers = [scale]
    for _ in range(DEGREE + 1):
        powers.append(powers[-1] * d // scale)
    r = []
    for k in range(DEGREE + 1):
        r.append(numerator[k] * powers[k] // scale
                 - sum(r[j] * denominator[k - j] // scale * powers[k - 1 - j] // scale for j in range(k)))
    factorial = 1
    carried = []
    for j in range(DEGREE + 1):
        factorial *= max(j, 1)
        carried.append(factorial * r[j] * powers[DEGREE - j] // scale)
    return carried, powers[DEGREE + 1]


# ---- Z at a point ----

def theta_at(t, digits):
    """theta at `digits` by exact_zeta_gram.py's two routes, N doubling until they agree with the guard dropped."""
    n_sum = 1
    one, two = (gram.theta_route(t, digits, n, n) for n in (1, 2))
    while toward_zero(one) - toward_zero(two):
        n_sum *= 2
        one, two = (gram.theta_route(t, digits, n, n) for n in (n_sum, 2 * n_sum))
    return two, n_sum


def rs_parts(nu, p, inv_root, digits):
    """The main sum S, the terms of R each times d^16 pi^10, that multiplier, and theta's N, at x = nu + p.

    t = 2pi x^2, the main sum runs to n = nu, and u^-(2k+1) = inv_root x^-k, inv_root being x^(-1/2) at
    `digits`. At p = 1 the cell's own nu holds, the limit from inside it."""
    scale = 10 ** digits
    big_p, q = p
    unit = 10 ** q
    big_x = nu * unit + big_p
    t = 2 * big_x * big_x * zz.pi(digits) // (unit * unit), digits
    theta, theta_n = theta_at(t, digits)
    cos_theta, sin_theta = zz.cos_sin(theta, digits)
    terms = [zz.power_minus_s(n, LINE, t, digits)[:2] for n in range(1, nu + 1)]
    re, im = sum(a for a, _ in terms), sum(b for _, b in terms)
    main_sum = 2 * (cos_theta * re - sin_theta * im) // scale
    carried, d_power = psi_carried(p, digits)
    big_pi = zz.pi(digits)
    pi_powers = [scale]
    for _ in range(PI_POWER):
        pi_powers.append(pi_powers[-1] * big_pi // scale)
    multiplier = d_power * pi_powers[PI_POWER] // scale
    sign = 1 - 2 * ((nu - 1) % 2)
    tail = []
    for k, parts in enumerate(COEFFICIENTS):
        c = sum(s * carried[j] * pi_powers[PI_POWER - 2 * m] // (scale * den) for s, den, j, m in parts)
        tail.append(sign * c * inv_root * unit ** k // (scale * big_x ** k))
    return main_sum, tail, multiplier, theta_n


def z_carried(u, places, remainder=1):
    """Z d^16 pi^10, the last term c_5 u^-11 times the same, and that multiplier, at places + GUARD.

    The work runs at places + 2 GUARD and one guard is dropped toward zero."""
    digits = places + 2 * GUARD
    scale = 10 ** digits
    big_u, q = u
    unit = 10 ** q
    n_top = big_u * big_u // (unit * unit)
    p = zz.pair(big_u * big_u - n_top * unit * unit, 2 * q)
    main_sum, tail, multiplier, theta_n = rs_parts(n_top, p, scale * unit // big_u, digits)
    total = main_sum * multiplier // scale + remainder * sum(tail)
    return toward_zero(total), toward_zero(remainder * tail[-1]), toward_zero(multiplier), n_top, theta_n


class Riemann:
    """The sign of Z decided at each point u, the reach of its last term there, and what deciding them cost."""

    def __init__(self, remainder=1):
        self.remainder = remainder
        self.sign = {}
        self.reach = {}
        self.asked = 0
        self.deepest = 0
        self.widest = 0

    def sweep(self, points):
        fresh = list(dict.fromkeys(points))
        open_points = [(p, 1) for p in compress(fresh, [int(p not in self.sign) for p in fresh])]
        while open_points:
            records = []
            for point, places in open_points:
                self.asked += 1
                total, last, _, n_top, _ = z_carried(point, places, self.remainder)
                read, read_last = toward_zero(total), toward_zero(last)
                records.append((point, places, compare(read, 0), compare(abs(read), abs(read_last)), n_top))
            for point, places, sign, reach, n_top in compress(records, [abs(r[2]) for r in records]):
                self.sign[point] = sign
                self.reach[point] = reach
                self.deepest = max(self.deepest, places)
                self.widest = max(self.widest, n_top)
            open_points = [(point, 2 * places) for point, places, *_ in compress(records, [NOT(r[2]) for r in records])]

    def settle(self, brackets, walk):
        """Cut each bracket by the Gram index until Z has one nonzero sign at both ends."""
        signs, settled, cuts = {}, {}, 0
        while brackets:
            self.sweep([u for lo, h, _ in brackets for u in (lo, h)])
            verdicts = [NOT(self.sign[lo] - self.sign[h]) for lo, h, _ in brackets]
            for lo, h, n in compress(brackets, verdicts):
                signs[n] = self.sign[lo] * (1 - 2 * (n % 2))
                settled[n] = (lo, h)
            brackets = walk.cut(list(compress(brackets, [NOT(v) for v in verdicts])))
            cuts += len(brackets)
        return signs, settled, cuts


# ---- comparisons by multiplication ----

def at_least(u, value, digits=40):
    """The verdict that 2pi u^4 >= value, by products: 2 U^4 times pi's floor against the value."""
    big_u, q = u
    big_v, w = value
    return int(2 * big_u ** 4 * zz.pi(digits) * 10 ** w >= big_v * 10 ** (4 * q + digits))


def at_most(u, value, digits=40):
    """The verdict that 2pi u^4 <= value, by products: 2 U^4 times pi's floor plus one against the value."""
    big_u, q = u
    big_v, w = value
    return int(2 * big_u ** 4 * (zz.pi(digits) + 1) * 10 ** w <= big_v * 10 ** (4 * q + digits))


def holds(lo, h, published):
    """Whether [2pi lo^4, 2pi h^4] meets the published value's own bracket, half a unit in its last place."""
    value = units(published)
    unit = (5, value[1] + 1)
    return at_most(lo, zz.plus(value, unit)) * at_least(h, zz.minus(value, unit))


def u_of(height, places=4):
    """The least u at `places` with 2pi u^4 >= height, one bit a pass, by products."""
    low, high = 0, 10 ** places
    while NOT(at_least((high, places), height)):
        high *= 2
    while high - low > 1:
        mid = (low + high) // 2
        v = at_least((mid, places), height)
        low, high = low + (1 - v) * (mid - low), high - v * (high - mid)
    return zz.pair(high, places)


@cache
def euler_maclaurin(u, places):
    """Re e^(i theta) zeta(1/2 + it) at t = 2pi u^4, by exact_zeta_zeros.py's two routes, read at `places`."""
    digits = places + GUARD
    t = time_of(u, digits + GUARD)
    theta, _ = theta_at(t, digits + GUARD)
    cos_theta, sin_theta = (v // 10 ** GUARD for v in zz.cos_sin(theta, digits + GUARD))
    (re, im), _, _ = zz.agreed_value(LINE, t, digits)
    return toward_zero((cos_theta * re - sin_theta * im) // 10 ** digits)


def gap(u, places, remainder=1):
    """Z by Riemann-Siegel less Z by Euler-Maclaurin at t = 2pi u^4, in units of the last place."""
    total, _, multiplier, _, _ = z_carried(u, places, remainder)
    return toward_zero(total * 10 ** (places + GUARD) // multiplier) - euler_maclaurin(u, places)


# ---- the tail coefficient on the device ----

TAIL_BUILD = os.path.join(ROOT, "examples", "0_experimental", "exact_zeta_tail.sh")


def _signed_bits(value):
    return abs(value).bit_length() + 1


def _two(value, bits):
    return value % (1 << bits)


class DeviceTail:
    """Euler-Maclaurin's C at many points at once, one lane a point, swept on the device by exact_zeta_tail.cu.

    The records are laid out here and the program is built there from N and the wrap width W. W is the bits of a
    bound on every tau and on the two turns between them, at the scale S:
    |tau_k| <= |B_2k / (2k)!| (|t| + 1)(|t| + 2) ... (|t| + 2k - 1) / N^(2k - 1), with |t| taken up to the power of
    two above it. The widths then hold across passes, and a program, compiled once, is read from the cache after."""

    def __init__(self, work):
        self.work = work
        self.binary = None
        self.checked = set()
        self.swept = 0

    def build(self):
        """The binary's path, built by exact_zeta_tail.sh under the bash the path names first. On Windows a bare
        "bash" given to a process is found in System32 before the path, and that one is another system's."""
        sources = (TAIL_BUILD, os.path.join(os.path.dirname(TAIL_BUILD), "exact_zeta_tail.cu"))
        built = sorted(glob.glob(os.path.join(ROOT, "build", "*_exact_zeta_tail", "exact_zeta_tail*")),
                       key=os.path.getmtime)
        fresh = [b for b in built[-1:] if os.path.getmtime(b) > max(os.path.getmtime(s) for s in sources)]
        if fresh:
            return fresh[0]
        made = subprocess.run([shutil.which("bash"), TAIL_BUILD], capture_output=True, text=True)
        lines = made.stdout.strip().splitlines()
        self.binary = lines[-1] if (made.returncode == 0 and lines) else None
        return self.binary

    def records(self, ts, n_sum, digits):
        scale = 10 ** digits
        big_ts = [t[0] * scale // 10 ** t[1] for t in ts]
        top = 1 << (max(abs(v) for v in big_ts) // scale + 1).bit_length()
        rho = []
        for k in range(2, n_sum + 1):
            num_k, den_k = zz.bernoulli_over_factorial(k)
            num_j, den_j = zz.bernoulli_over_factorial(k - 1)
            num, den = num_k * den_j, den_k * num_j * n_sum * n_sum
            rho.append(compare(num * den, 0) * (abs(num) * scale // abs(den)))
        bound, widest = 0, 0
        for k in range(1, n_sum + 1):
            num, den = zz.bernoulli_over_factorial(k)
            grown = 1
            for j in range(2 * k - 1):
                grown *= top + j + 1
            bound = abs(num) * grown * scale // (den * n_sum ** (2 * k - 1)) + 1
            widest = max(widest, bound * (top + 2 * k + 2) ** 2)
        width = _signed_bits(widest) + 2
        bits = [_signed_bits(top * scale), scale.bit_length() + 1, scale.bit_length() + 1]
        bits += [max(_signed_bits(v) for v in rho + [1])] * (n_sum - 1)
        offsets = [0, 0, bits[1]]
        for b in bits[2:-1]:
            offsets.append(offsets[-1] + b)
        point_limbs = (bits[0] + 31) // 32
        shared_bits = offsets[-1] + bits[-1]
        shared_limbs = (shared_bits + 31) // 32
        shared = scale + ((scale // 2) << offsets[2])
        for k, value in enumerate(rho):
            shared += _two(value, bits[3 + k]) << offsets[3 + k]
        lines = ["%d %d" % (n_sum, width), "fields %d" % len(bits)]
        lines += ["%d %d" % (b, o) for b, o in zip(bits, offsets)]
        lines.append("in_limbs %d %d" % (point_limbs, shared_limbs))
        lines.append("points %d" % len(ts))
        for v in big_ts:
            word = _two(v, bits[0])
            lines.append(" ".join("%x" % ((word >> (32 * i)) & 0xFFFFFFFF) for i in range(point_limbs)))
        lines.append(" ".join("%x" % ((shared >> (32 * i)) & 0xFFFFFFFF) for i in range(shared_limbs)))
        return "\n".join(lines) + "\n"

    def coefficients(self, ts, n_sum, digits):
        """C at each t, each (re, im) at `digits`, and whether the device's records equal the host's."""
        self.binary = self.binary or self.build()
        given = os.path.join(self.work, "tail_in_%d_%d.txt" % (n_sum, digits))
        taken = os.path.join(self.work, "tail_out_%d_%d.txt" % (n_sum, digits))
        with open(given, "w") as handle:
            handle.write(self.records(ts, n_sum, digits))
        ran = subprocess.run([self.binary, given, taken], capture_output=True, text=True)
        with open(taken) as handle:
            lines = handle.read().split("\n")
        out_limbs = int(lines[0].split()[1])
        re_offset, re_bits, im_offset, im_bits = (int(v) for v in lines[1].split()[1:])
        values = []
        for line in lines[2:2 + len(ts)]:
            word = sum(int(v, 16) << (32 * i) for i, v in enumerate(line.split()[:out_limbs]))
            parts = []
            for offset, bits in ((re_offset, re_bits), (im_offset, im_bits)):
                v = (word >> offset) & ((1 << bits) - 1)
                parts.append(v - (v >> (bits - 1) << bits))
            values.append(tuple(parts))
        same = int(lines[2 + len(ts)].split()[1])
        self.swept += len(ts)
        return values, same * NOT(ran.returncode), ran.stdout

    def check(self, t, n_sum, digits, value):
        """The device's C at one point against zz.tail_coefficient's exact rational, in units of the scale."""
        (re, im, den), _ = zz.tail_coefficient(LINE, t, n_sum, 1)
        scale = 10 ** digits
        return abs(value[0] - re * scale // den) + abs(value[1] - im * scale // den)


# ---- the triangle between the two pairs, one cell of x = u^2 at a time ----

def em_at(key):
    """Re e^(i theta) zeta(1/2 + it) at t = 2pi x^2, x = nu + p, by exact_zeta_zeros.py's two routes, at `digits`."""
    nu, p, digits = key
    big_p, q = p
    unit = 10 ** q
    big_x = nu * unit + big_p
    deep = digits + GUARD
    t = 2 * big_x * big_x * zz.pi(deep) // (unit * unit), deep
    theta, _ = theta_at(t, deep)
    cos_theta, sin_theta = (v // 10 ** GUARD for v in zz.cos_sin(theta, deep))
    (re, im), _, _ = zz.agreed_value(LINE, t, digits)
    return (cos_theta * re - sin_theta * im) // 10 ** digits


def rs_at(key):
    """S and R at x = nu + p, each at `digits`, the work one guard deeper.

    R is the carried tail over d^16 pi^10, and near p = 1/4 and 3/4 d is small and that multiplier
    carries fewer digits than the work. How many it lost is a property of p and not of the work:
    the work is set once to digits + GUARD + lost, and asked again while it is short of that."""
    nu, p, digits = key
    big_p, q = p
    unit = 10 ** q
    wanted, short = digits + GUARD, 1
    while short:
        work = wanted
        scale = 10 ** work
        inv_root = naturals._integer_sqrt(scale * scale * unit // (nu * unit + big_p))
        main_sum, tail, multiplier, _ = rs_parts(nu, p, inv_root, work)
        wanted = digits + GUARD + max(len(str(scale)) - len(str(multiplier)), 0)
        short = int(work < wanted)
    drop = 10 ** (work - digits)
    remainder = sum(tail) * scale // multiplier
    return compare(main_sum, 0) * (abs(main_sum) // drop), compare(remainder, 0) * (abs(remainder) // drop)


def seam(nu, digits):
    """The jumps of S, of R and of Z_RS where x crosses nu + 1, each at `digits`.

    From inside the cell S runs to nu with p = 1, and from the next it runs to nu + 1 with p = 0. Z is
    continuous there: the jump of Z_RS is the jump of the terms R leaves out, carried with the sign
    and the size of their first."""
    s_in, r_in = rs_at((nu, (1, 0), digits))
    s_out, r_out = rs_at((nu + 1, (0, 0), digits))
    return s_out - s_in, r_out - r_in, s_out - s_in + r_out - r_in


def em_on_device(tail, keys):
    """Re e^(i theta) zeta(1/2 + it) at every key of one pass, each at its `digits`, with C from the device.

    The routes at N and 2N are entry 4's, each a head of powers on the host and C N^-s, C swept on the device for every
    open point at once. A point whose two routes read alike with the guard dropped is done; the rest double N. Returns
    the values and whether every sweep's device records equaled the host's."""
    digits = keys[0][2]
    work = digits + GUARD
    scale = 10 ** work
    ts, turns = [], []
    for nu, p, _ in keys:
        big_p, q = p
        unit = 10 ** q
        big_x = nu * unit + big_p
        t = 2 * big_x * big_x * zz.pi(work) // (unit * unit), work
        ts.append(t)
        turns.append(zz.cos_sin(theta_at(t, work)[0], work))
    values, same = {}, 1
    open_points, n_sum = list(range(len(keys))), 1
    while open_points:
        routes = []
        for n in (n_sum, 2 * n_sum):
            coefficients, held, _ = tail.coefficients([ts[i] for i in open_points], n, work)
            same *= held
            routes.append(coefficients)
        records = []
        for at, i in enumerate(open_points):
            reads = []
            for n, coefficients in zip((n_sum, 2 * n_sum), routes):
                powers = [zz.power_minus_s(m, LINE, ts[i], work)[:2] for m in range(1, n + 1)]
                a, b = powers[-1]
                c_re, c_im = coefficients[at]
                re = sum(x for x, _ in powers[:-1]) + (a * c_re - b * c_im) // scale
                im = sum(y for _, y in powers[:-1]) + (a * c_im + b * c_re) // scale
                reads.append((re, im))
            agree = NOT(toward_zero(reads[0][0]) - toward_zero(reads[1][0])) * NOT(toward_zero(reads[0][1])
                                                                                  - toward_zero(reads[1][1]))
            records.append((i, agree, reads[1]))
        for i, _, (re, im) in compress(records, [r[1] for r in records]):
            cos_theta, sin_theta = turns[i]
            values[keys[i]] = toward_zero((cos_theta * re - sin_theta * im) // scale)
        open_points = [r[0] for r in compress(records, [NOT(r[1]) for r in records])]
        n_sum *= 2
    return values, same


SPIKE_BITS = 64


def ln_at(v, scale):
    """ln(v / scale) for v >= scale, at `scale`: k ln 2 + 2 artanh((v - 2^k) / (v + 2^k)) against
    j ln 3 + 2 artanh((v - 3^j) / (v + 3^j)). Returns the second and whether the two agree with the
    guard dropped."""
    k = (v // scale).bit_length() - 1
    two = k * naturals._ln_two_artanh(scale) + 2 * zz._artanh(v - (scale << k), v + (scale << k), scale)
    j, power = 0, 1
    while power * 3 * scale <= v:
        j, power = j + 1, power * 3
    three = j * 2 * zz._artanh(1, 2, scale) + 2 * zz._artanh(v - power * scale, v + power * scale, scale)
    return three, NOT(toward_zero(two) - toward_zero(three))


def spike_at(d0, k, u, scale):
    """g(u) = D0^2 / (sqrt(D0^2 + k^2 u^2) + k |u|) at `scale`."""
    ku = k * abs(u) // scale
    return d0 * d0 // (naturals._integer_sqrt(d0 * d0 + ku * ku) + ku + NOT(d0) * NOT(ku))


def spike_integral(d0, k, ell, scale):
    """The integral of g over u from 0 to L, exactly: (L D0^2 / (sqrt(D0^2 + k^2 L^2) + kL)
    + (D0^2 / k) asinh(kL / |D0|)) / 2, written so that nothing cancels. asinh(y) = ln(y + sqrt(y^2 + 1))."""
    kl = k * ell // scale
    first = ell * d0 * d0 // ((naturals._integer_sqrt(d0 * d0 + kl * kl) + kl + NOT(d0) * NOT(kl)) * scale)
    y = kl * scale // (abs(d0) + NOT(d0))
    log, _ = ln_at(y + naturals._integer_sqrt(y * y + scale * scale), scale)
    return (first + d0 * d0 * log // ((k + NOT(k)) * scale)) // 2


class Triangle:
    """The three sides over a cell, from values each asked once, the Euler-Maclaurin ones with C from the device."""

    def __init__(self, tail, cut=None, em=None):
        """R through MathWorld's c_5 where `cut` is None, and through C_cut from the exact curves
        otherwise. `em` may be shared between triangles: Euler-Maclaurin does not depend on the cut."""
        self.tail = tail
        self.at = [lambda key: rs_cut_at(key, cut), rs_at][int(cut is None)]
        self.em = em if em is not None else {}
        self.rs = {}
        self.same = 1
        self.crossed = {}

    def fill(self, keys):
        keys = list(dict.fromkeys(keys))
        fresh = [k for k in keys if k not in self.em]
        if fresh:
            values, same = em_on_device(self.tail, fresh)
            self.em.update(values)
            self.same *= same
        self.rs.update((k, self.at(k)) for k in keys if k not in self.rs)

    def e_at(self, nu, j, bits, digits):
        """E = S - R at p = j / 2^bits, from Riemann-Siegel alone."""
        key = (nu, zz.pair(j * 5 ** bits, bits), digits)
        self.rs[key] = self.rs.get(key) or self.at(key)
        s, r = self.rs[key]
        return s - r

    def crossings(self, nu, digits, start=8, bits=SPIKE_BITS):
        """Where S and R cross in the cell, each as (p0 over 2^bits, D there, |E'| there), at `digits`.

        E's sign changes are read on 2^m and 2^(m+1) parts, m growing until the two counts agree, and
        each is halved to 2^-bits. |E'| is read from the last bracket and D at p0 from both pairs."""
        if (nu, digits) in self.crossed:
            return self.crossed[(nu, digits)]
        m = start
        row, finer = ([self.e_at(nu, j, mm, digits) > 0 for j in range((1 << mm) + 1)] for mm in (m, m + 1))
        while len(changes(row)) - len(changes(finer)):
            m += 1
            row, finer = finer, [self.e_at(nu, j, m + 1, digits) > 0 for j in range((1 << (m + 1)) + 1)]
        found = []
        for j in changes(finer):
            lo, depth, left = j, m + 1, finer[j]
            while depth < bits:
                lo, depth = 2 * lo, depth + 1
                lo += int((self.e_at(nu, lo + 1, depth, digits) > 0) == left)
            slope = abs(self.e_at(nu, lo + 1, bits, digits) - self.e_at(nu, lo, bits, digits)) << bits
            found.append((lo, (nu, zz.pair(lo * 5 ** bits, bits), digits), slope))
        self.fill([key for _, key, _ in found])
        self.crossed[(nu, digits)] = [(lo, sum(self.rs[key]) - self.em[key], slope) for lo, key, slope in found]
        return self.crossed[(nu, digits)]

    def sides(self, nu, digits, m):
        """a, b and delta over p in [0, 1], by the trapezoid on 2^m equal parts, at `digits`.

        D = Z_RS - Z_EM and E = S - R at each point. a = int |D|, b = int |E|, and the third side
        c = int |(D, E)| = b + delta, delta = int D^2 / (|(D, E)| + |E|). c - b never cancels.

        Where S and R cross, E is zero and delta's integrand is a spike of height |D| and width |D / E'|,
        far below any grid: the trapezoid on it grows as ln(1 / h) and stops only where h reaches that
        width. Each spike is held by its relation instead, g(p) = D0^2 / (sqrt(D0^2 + k^2 u^2) + k |u|) with
        u = p - p0, D0 = D(p0) and k = |E'(p0)|, whose integral over the cell is exact (`spike_integral`).
        delta is the sum of those integrals and the trapezoid of what is left, f minus every g."""
        scale = 10 ** digits
        spikes = self.crossings(nu, digits)
        steps = 1 << m
        keys = [(nu, zz.pair(j * 5 ** m, m), digits) for j in range(steps + 1)]
        self.fill(keys)
        a = b = delta = 0
        for j, key in enumerate(keys):
            s, r = self.rs[key]
            d, e = s + r - self.em[key], s - r
            root = naturals._integer_sqrt(d * d + e * e)
            weight = 2 - NOT(j) - NOT(j - steps)
            a += weight * abs(d)
            b += weight * abs(e)
            held = sum(spike_at(d0, k, ((j << (SPIKE_BITS - m)) - lo) * scale >> SPIKE_BITS, scale)
                       for lo, d0, k in spikes)
            delta += weight * (d * d // (root + abs(e) + NOT(root + abs(e))) - held)
        exact = sum(spike_integral(d0, k, lo * scale >> SPIKE_BITS, scale)
                    + spike_integral(d0, k, ((1 << SPIKE_BITS) - lo) * scale >> SPIKE_BITS, scale)
                    for lo, d0, k in spikes)
        return a // (2 * steps), b // (2 * steps), delta // (2 * steps) + exact

    def excess(self, a, b, delta, places):
        """kappa = (c^2 - a^2 - b^2) / a^2 = (2b delta + delta^2 - a^2) / a^2, read toward zero at `places`.

        cos gamma = -kappa a / 2b. kappa is the shape with the scale a / b taken out: zero where |D| follows
        |E| across the cell, and positive otherwise."""
        scale = 10 ** (places + GUARD)
        return toward_zero((2 * b * delta + delta * delta - a * a) * scale // (a * a + NOT(a)))

    def angle(self, a, b, delta):
        """cos gamma = (a^2 - 2b delta - delta^2) / 2ab, read toward zero at the places where it first reads
        nonzero, and those places. A reading of zero doubles them."""
        numerator, denominator = a * a - 2 * b * delta - delta * delta, 2 * a * b + NOT(a * b)
        places, read = 1, 0
        while NOT(read):
            read = toward_zero(numerator * 10 ** (places + GUARD) // denominator)
            places *= 1 + NOT(read)
        return read, places

    def cell(self, nu):
        """The triangle over [nu, nu + 1], decided where a and delta each carry places + GUARD digits, kappa
        reads nonzero at `places`, and the routes at 2^m and 2^(m+1) parts agree on it. Each verdict that
        fails doubles its own count: the depth, the places, or the parts."""
        places, depth, m = 1, GUARD, 1
        decided = 0
        while NOT(decided):
            digits = places + GUARD + depth
            one = self.sides(nu, digits, m)
            two = self.sides(nu, digits, m + 1)
            floor = 10 ** (places + GUARD)
            deep = abs(compare(two[0] // floor, 0)) * abs(compare(two[2] // floor, 0))
            kappa_one, kappa_two = self.excess(*one, places), self.excess(*two, places)
            agree = NOT(kappa_one - kappa_two)
            read = abs(compare(kappa_two, 0))
            decided = deep * agree * read
            depth *= 2 - deep
            m += deep * (1 - agree)
            places *= 1 + deep * agree * (1 - read)
        return two, kappa_two, places, digits, m + 1


# ---- every C_n, held as its real and its operator ----

EULER = [1]
LAMBDA = [1]
D_ROWS = [[1]]

# Gabcke, Table II: d_k^(8) as printed, in primes.
TABLE_II_ROW_8 = (2 ** 15 * 5 ** 3 * 7 ** 2 * 11 ** 2 * 13 * 17 * 19 * 23, 2 ** 14 * 5 ** 2 * 7 ** 2 * 11 * 13 * 17 * 19 * 23,
                  2 ** 11 * 5 * 7 * 11 * 13 * 19 * 587, 2 ** 9 * 11 * 88651, 2 ** 4 * 5 ** 2 * 5281, 2 ** 3 * 3 * 7 * 61, 2 * 41)

# Gabcke, Table IV, the sum row under each C_n: C_n(1) at 50 places, as printed.
TABLE_IV_AT_ONE = (
    "0.92387953251128675612818318939678828682241662586366",
    "-0.03059730649970626546068192245966280080837903996856",
    "0.00126887416458910500666051884940376436169297025221",
    "-0.00019868520940530243222929405399643439118283446391",
    "-0.00000507858983165002468419342114936835424875429909",
    "-0.00007396543141241629733408848615411272753191792498",
    "0.00000187256420886912251262001682842629296424868174",
    "-0.00001001778245912224981642747644926784077639093882",
    "-0.00000001500360185507754523780375237281525837598888",
    "-0.00000248337616645216969898765435537919977772834558",
    "0.00000001501251599634484404172738666926505568514695",
)
# The sum rows of Table IV and Table V, two routes to the same C_n(1), differ by up to 5 units of the
# 50th place, and that is the bar.
TABLE_SPREAD = 5
TOP_C = 24
ZERO_BITS = 128


def euler_abs(k):
    """|E_2k|, the Euler numbers by sum over j of C(2n, 2j) E_2j = 0."""
    while len(EULER) <= k:
        n = len(EULER)
        EULER.append(-sum(comb(2 * n, 2 * j) * e for j, e in enumerate(EULER)))
    return abs(EULER[k])


def lam(l):
    """lambda_l: (l + 1) lambda_(l+1) = sum over k of 2^(4k+1) |E_(2k+2)| lambda_(l-k), lambda_0 = 1."""
    while len(LAMBDA) <= l:
        n = len(LAMBDA) - 1
        LAMBDA.append(sum(2 ** (4 * k + 1) * euler_abs(k + 1) * LAMBDA[n - k] for k in range(n + 1)) // (n + 1))
    return LAMBDA[l]


def d_row(n):
    """d_k^(n) for k = 0 .. floor(3n / 4): d_k^(n+1) = (3n + 1 - 4k)(3n + 2 - 4k) d_k^(n) + d_(k-1)^(n), and
    where 3(n + 1) = 4k the entry is lambda_(k/3) instead."""
    while len(D_ROWS) <= n:
        m = len(D_ROWS) - 1
        prev = D_ROWS[-1] + [0]
        row = []
        for k in range(3 * (m + 1) // 4 + 1):
            edge = NOT(3 * (m + 1) - 4 * k)
            grown = (3 * m + 1 - 4 * k) * (3 * m + 2 - 4 * k) * prev[k] + prev[k - 1] * (1 - NOT(k))
            row.append(edge * lam((m + 1) // 4) + (1 - edge) * grown)
        D_ROWS.append(row)
    return D_ROWS[n]


def phi_terms(j):
    """The coefficient of z^(2j) in F, as (power of pi, root, numerator, denominator).

    F(z) = cos(pi z^2 / 2 + 3pi/8) sec(pi z), and the product of the two series puts
    sign |E_2(j-m)| / (2^m m! (2(j - m))!) pi^(2j - m) at each m, times sin(pi/8) where m is even and
    cos(pi/8) where m is odd, the sign running +, -, -, + in m mod 4."""
    out = []
    for m in range(j + 1):
        num, den = euler_abs(j - m), 2 ** m * factorial(m) * factorial(2 * (j - m))
        g = gcd(num, den)
        out.append((2 * j - m, m % 2, (1, -1, -1, 1)[m % 4] * num // g, den // g))
    return out


class Curve:
    """The Taylor coefficients of every C_n about z = 0, read at `digits`.

    pi from naturals, and sin(pi/8), cos(pi/8) = sqrt(2 -+ sqrt 2) / 2 by integer square roots."""

    def __init__(self, digits):
        self.digits = digits
        self.scale = scale = 10 ** digits
        self.big_pi = zz.pi(digits)
        root_two = naturals._integer_sqrt(2 * scale * scale)
        self.root = (naturals._integer_sqrt((2 * scale - root_two) * scale) // 2,
                     naturals._integer_sqrt((2 * scale + root_two) * scale) // 2)
        self.up, self.down, self.phi = [scale], [scale], []

    def pi_power(self, e):
        while len(self.up) <= abs(e):
            self.up.append(self.up[-1] * self.big_pi // self.scale)
            self.down.append(self.down[-1] * self.scale // self.big_pi)
        return [self.up, self.down][int(e < 0)][abs(e)]

    def phi_at(self, j):
        while len(self.phi) <= j:
            self.phi.append(sum(num * self.pi_power(e) * self.root[w] // (den * self.scale)
                                for e, w, num, den in phi_terms(len(self.phi))))
        return self.phi[j]

    def gamma(self, n, count):
        """The first `count` coefficients: 2^(-2n) sum over k of d_k C(i + m, m) pi^(2k - 2n) phi at
        z^(i + m), m = 3n - 4k, zero where i + m is odd."""
        out = []
        for i in range(count):
            total = 0
            for k, dk in enumerate(d_row(n)):
                m = 3 * n - 4 * k
                total += (1 - (i + m) % 2) * dk * comb(i + m, m) * self.pi_power(2 * k - 2 * n) \
                    * self.phi_at((i + m) // 2) // self.scale
            out.append(total >> (2 * n))
        return out


CURVES = {}
GAMMAS = {}


def c_value(n, count, digits, a, bits):
    """C_n(a / 2^bits) at `digits` by its first `count` Taylor terms, Horner's rule on integers."""
    key = (n, count, digits)
    GAMMAS[key] = GAMMAS.get(key) or CURVES.setdefault(digits, Curve(digits)).gamma(n, count)
    acc = 0
    for g in reversed(GAMMAS[key]):
        acc = (acc * a >> bits) + g
    return acc


def c_at(n, num, den, digits):
    """C_n(num / den), |num / den| <= 1, at digits + GUARD: count and 2 count Taylor terms, the second at
    twice the extra digits, agreeing with the guard dropped; disagreement doubles count. An odd C_n
    turns sign with z, and the series is read at |z|."""
    sign = 1 - 2 * (n % 2) * int(num < 0)
    num = abs(num)
    count, decided = 64, 0
    while NOT(decided):
        reads = []
        for terms in (count, 2 * count):
            work = digits + GUARD + terms + 3 * n
            key = (n, terms, work)
            GAMMAS[key] = GAMMAS.get(key) or CURVES.setdefault(work, Curve(work)).gamma(n, terms)
            acc = 0
            for g in reversed(GAMMAS[key]):
                acc = acc * num // den + g
            reads.append(c_read(acc, work, digits + GUARD))
        decided = NOT(toward_zero(reads[0]) - toward_zero(reads[1]))
        count *= 2 - decided
    return sign * reads[1]


def rs_cut_at(key, cut):
    """S and R at x = nu + p, each at `digits`, with R through C_cut from the exact curves:
    R = (-1)^(nu-1) sum over n <= cut of C_n(1 - 2p) u^-(2n+1), u^-(2n+1) = x^(-1/2) x^-n."""
    nu, p, digits = key
    work = digits + GUARD
    scale = 10 ** work
    big_p, q = p
    unit = 10 ** q
    big_x = nu * unit + big_p
    t = 2 * big_x * big_x * zz.pi(work) // (unit * unit), work
    theta, _ = theta_at(t, work)
    cos_theta, sin_theta = zz.cos_sin(theta, work)
    terms = [zz.power_minus_s(n, LINE, t, work)[:2] for n in range(1, nu + 1)]
    main_sum = 2 * (cos_theta * sum(a for a, _ in terms) - sin_theta * sum(b for _, b in terms)) // scale
    inv_root = naturals._integer_sqrt(scale * scale * unit // big_x)
    remainder = sum(c_at(n, unit - 2 * big_p, unit, digits) * inv_root * unit ** n // (scale * big_x ** n)
                    for n in range(cut + 1)) * (1 - 2 * ((nu - 1) % 2))
    return toward_zero(main_sum), toward_zero(remainder)


def c_read(v, digits, places):
    return compare(v, 0) * (abs(v) // 10 ** (digits - places))


def c_verdict(n, a, bits, places=24):
    """C_n(a / 2^bits) read at `places` by count and 2 count terms, the second at twice the extra
    digits, which must agree; disagreement doubles count and a reading of zero doubles the places."""
    count, decided = 64, 0
    while NOT(decided):
        extra = count + 3 * n
        one = c_read(c_value(n, count, places + GUARD + extra, a, bits), places + GUARD + extra, places)
        two = c_read(c_value(n, 2 * count, places + GUARD + 2 * extra, a, bits), places + GUARD + 2 * extra, places)
        agree, read = NOT(one - two), abs(compare(two, 0))
        decided = agree * read
        count *= 2 - agree
        places *= 1 + agree * (1 - read)
    return two, places


class Vanishing:
    """Where each C_n changes sign on [0, 1], by verdicts at dyadic z."""

    def __init__(self):
        self.signs = {}

    def sign_at(self, n, a, bits):
        while bits * NOT(a % 2):
            a, bits = a // 2, bits - 1
        key = (n, a, bits)
        self.signs[key] = self.signs.get(key) or compare(c_verdict(n, a, bits)[0], 0)
        return self.signs[key]

    def past_zero(self, n, a, bits):
        """An odd C_n is zero at 0 by parity; the sign just past 0 is the sign of its z coefficient,
        read at digits and twice them until the two agree and read nonzero."""
        digits, decided = 40, 0
        while NOT(decided):
            one = c_read(Curve(digits).gamma(n, 2)[1], digits, digits // 2)
            two = c_read(Curve(2 * digits).gamma(n, 2)[1], 2 * digits, digits // 2)
            decided = NOT(one - two) * abs(compare(two, 0))
            digits *= 2
        return compare(two, 0)

    def row(self, n, m):
        first = [self.sign_at, self.past_zero][n % 2]
        return [first(n, 0, m)] + [self.sign_at(n, j, m) for j in range(1, 2 ** m + 1)]

    def zeros(self, n, bits, start=6):
        """The sign changes on 2^m and 2^(m+1) parts, m growing until the two counts agree, each halved
        to `bits`. Returns the left ends, a over 2^bits, and m."""
        m = start
        row, finer = self.row(n, m), self.row(n, m + 1)
        while len(changes(row)) - len(changes(finer)):
            m += 1
            row, finer = finer, self.row(n, m + 1)
        found = []
        for j in changes(finer):
            lo, depth = j, m + 1
            left = self.sign_at(n, lo, depth)
            while depth < bits:
                lo, depth = 2 * lo, depth + 1
                lo += int(self.sign_at(n, lo + 1, depth) == left)
            found.append(lo)
        return found, m

    def edge(self, n, parts=14):
        """The count of sign changes on [1 - 2^-6, 1] at 2^parts and 2^(parts+1) parts of [0, 1]: the zeros
        of the even C_n crowd toward z = 1, and two between neighbors of the coarse grid would not show there."""
        counts = []
        for m in (parts, parts + 1):
            base = (1 << m) - (1 << (m - 6))
            counts.append(len(changes([self.sign_at(n, base + j, m) for j in range((1 << (m - 6)) + 1)])))
        return counts


def seam_against_c(nu, digits=20, top=16):
    """The seam of Z_RS at x = nu + 1, and the jump of the terms R leaves out, from the exact C_k(1):
    -2 (-1)^nu sum over even k from 6 to `top` of C_k(1) u^-(2k+1), u = sqrt(nu + 1). Returns both."""
    scale = 10 ** digits
    root = naturals._integer_sqrt((nu + 1) * scale * scale)
    predicted = 0
    for k in range(6, top + 1, 2):
        inv = scale
        for _ in range(2 * k + 1):
            inv = inv * scale // root
        predicted += -2 * (1 - 2 * (nu % 2)) * c_verdict(k, 1, 0, places=digits)[0] * inv // scale
    return seam(nu, digits)[2], predicted


def changes(row):
    return [j for j in range(len(row) - 1) if row[j] - row[j + 1]]


def dyadic(a, bits, places):
    return "0.%0*d" % (places, a * 10 ** places >> bits)


def main():
    out = sys.stdout
    height = units((sys.argv[1:] + ["285"])[0])
    bits = int((sys.argv[2:] + ["16"])[0])
    out.write("  Z(t) by the Riemann-Siegel formula with t = 2pi u^4 held as a real, by truthy and falsy verdicts\n")
    out.write("  this reads the sign of Z at the Gram points it reaches and claims nothing about"
              " the Riemann hypothesis\n\n")

    begun = time.perf_counter_ns()
    walk = gram.Gram(phase=phase, start=START, step=(1, 0))
    top = u_of(height)
    found = walk.walk(top)
    indices = [n for _, _, n in found]
    consecutive = NOT(len(indices) - (indices[-1] + 1)) * NOT(indices[0])
    placed = walk.place(found, bits)
    out.write("  %d Gram points with 1.2 < u < %s, t < %s, indices 0 to %d, each alone in its bracket: %s\n"
              % (len(found), decimal(top, 4), decimal(height, height[1]), indices[-1], bool(consecutive)))
    out.write("  %-5s %-28s %-15s %s\n" % ("n", "u placed by %d bits" % bits, "published t", "2pi u^4 holds"))
    every = 1
    for (lo, h, n), published in zip(placed, gram.PUBLISHED):
        held = holds(lo, h, published)
        every *= held
        out.write("  %-5d [%s, %s]  %-15s %s\n" % (n, decimal(lo, 10), decimal(h, 10), published, bool(held)))
    out.write("  %d theta values asked, the deepest at %d places, the widest at N = %d\n\n"
              % (walk.asked, walk.deepest, walk.widest))
    out.flush()

    riemann = Riemann()
    signs, settled, cuts = riemann.settle(placed, walk)
    ordered = [signs[n] for n in indices]
    bad = list(compress(indices, [NOT(s + 1) for s in ordered]))
    spent = (time.perf_counter_ns() - begun) // 1000000
    out.write("  the sign of (-1)^n Z(g_n) by Riemann-Siegel:\n")
    for row in range(0, len(indices), 32):
        out.write("    %4d  %s\n" % (indices[row], "".join("+-"[(1 - s) // 2] for s in ordered[row:row + 32])))
    out.write("  Gram's law fails at n = %s\n" % (", ".join("%d" % n for n in bad) + "none" * NOT(len(bad))))
    for n in bad:
        lo, h = settled[n]
        out.write("    g_%d in u [%s, %s]\n" % (n, decimal(lo, 10), decimal(h, 10)))
    ends = [u for n in indices for u in settled[n]]
    short = sum(NOT(riemann.reach[u] - 1) for u in ends)
    out.write("  %d values of Z asked, %d further cuts, the deepest at %d places, the main sum at most %d terms\n"
              % (riemann.asked, cuts, riemann.deepest, riemann.widest))
    out.write("  at %d of the %d settled ends Z reads past the last term c_5 u^-11\n" % (short, len(ends)))
    out.write("  the walk, the placing and the signs in %d ms\n" % spent)
    reached = int(indices[-1] >= gram.FIRST_FAILURE)
    first = reached * NOT((bad + [-1])[0] - gram.FIRST_FAILURE) + (1 - reached) * NOT(len(bad))
    out.write("  the first failure against the reported index %d: %s\n\n" % (gram.FIRST_FAILURE, bool(first)))
    out.flush()

    out.write("  Z by Riemann-Siegel less Re e^(i theta) zeta by Euler-Maclaurin, in units of the last place\n")
    out.write("  %-6s %-8s %-30s %s\n" % ("u", "t", "with R, at 2, 4 and 8 places", "R left out, at 2, 4 and 8"))
    kept, bare = [], []
    for u in POINTS:
        with_r = [gap(u, places) for places in (2, 4, 8)]
        without = [gap(u, places, remainder=0) for places in (2, 4, 8)]
        kept.append(with_r)
        bare.append(without)
        out.write("  %-6s %-8s %-30s %s\n" % (decimal(u, 1), decimal(time_of(u, 2), 2), with_r, without))
    narrower = int(all(abs(a[1]) < abs(b[1]) for a, b in zip(kept, bare)))
    out.write("  at 4 places the gap with R is narrower than without it at every u shown: %s\n\n" % bool(narrower))
    out.flush()

    null = Riemann(remainder=0)
    null_signs, _, _ = null.settle(placed, walk)
    flipped = list(compress(indices, [1 - NOT(null_signs[n] - signs[n]) for n in indices]))
    out.write("  drawn null, R left out: the sign of (-1)^n Z(g_n) differs at n = %s\n"
              % (", ".join("%d" % n for n in flipped) + "none" * NOT(len(flipped))))
    out.flush()

    begun = time.perf_counter_ns()
    out.write("\n  every C_n by Gabcke's generator, each an exact sum of rationals times powers of pi and"
              " sqrt(2 -+ sqrt 2) / 2\n")
    mathworld = 1
    for n, parts in enumerate(COEFFICIENTS):
        mine = {}
        for k, dk in enumerate(d_row(n)):
            m = 3 * n - 4 * k
            num, den = dk * (1 - 2 * (m % 2)), 2 ** (2 * n + m) * factorial(m)
            g = gcd(num, den)
            mine[(m, n - k)] = (num // g, den // g)
        mathworld *= int(mine == {(j, m): (s, den) for s, den, j, m in parts})
    table_two = int(tuple(d_row(8)) == TABLE_II_ROW_8)
    out.write("  C_0 to C_5 against MathWorld's c_0 to c_5, rational for rational: %s\n" % bool(mathworld))
    out.write("  d_k^(8) against Gabcke's Table II: %s, and lambda_0 to lambda_4 = %s\n"
              % (bool(table_two), [lam(l) for l in range(5)]))
    apart = []
    for n, printed in enumerate(TABLE_IV_AT_ONE):
        read, _ = c_verdict(n, 1, 0, places=50)
        whole = printed.lstrip("-")
        apart.append(read - int(whole[2:]) * (1 - 2 * printed.startswith("-")))
    table_four = int(max(abs(a) for a in apart) <= TABLE_SPREAD)
    out.write("  C_0(1) to C_10(1) less Gabcke's Table IV, in units of the 50th place: %s, within %d: %s\n"
              % (apart, TABLE_SPREAD, bool(table_four)))
    vanishing = Vanishing()
    out.write("  the zeros of C_n on (0, 1), z = 1 - 2p, each halved to 2^-%d, and the p in a cell where"
              " C_n vanishes\n" % ZERO_BITS)
    counts = []
    for n in range(TOP_C + 1):
        found, m = vanishing.zeros(n, ZERO_BITS)
        counts.append(len(found))
        text = "  ".join("z %s p %s, %s" % (dyadic(lo, ZERO_BITS, 30), dyadic((1 << ZERO_BITS) - lo - 1, ZERO_BITS + 1, 12),
                                           dyadic((1 << ZERO_BITS) + lo, ZERO_BITS + 1, 12)) for lo in found)
        out.write("    C_%-3d %d  parts 2^%d  %s\n" % (n, len(found), m + 1, text))
    edges = [vanishing.edge(n) for n in range(TOP_C + 1)]
    out.write("  sign changes on [63/64, 1] at 2^14 and 2^15 parts, C_0 to C_%d: %s\n" % (TOP_C, edges))
    out.write("  the seam of Z_RS at x = nu + 1 against -2 (-1)^nu sum over even k from 6 to 16 of"
              " C_k(1) u^-(2k+1), at 20 places:\n")
    for nu in range(1, 9):
        jump, predicted = seam_against_c(nu)
        out.write("    x = %d  seam %d  from the C_k %d  ratio %s\n"
                  % (nu + 1, jump, predicted, decimal(zz.pair(jump * 10 ** 8 // predicted, 8), 8)))
    gabcke = int([counts[n] for n in (4, 8, 10)] == [1, 1, 1])
    out.write("  one simple zero each in C_4, C_8 and C_10 on 0 < z < 1, as Gabcke reports (p. 59): %s\n"
              % bool(gabcke))
    out.write("  every C_n in %d ms\n" % ((time.perf_counter_ns() - begun) // 1000000))
    return 1 - consecutive * every * first * narrower * mathworld * table_two * table_four * gabcke


def signed(v, places):
    """v at `places`, its sign written apart, since decimal() floors."""
    return "-" * int(v < 0) + decimal(zz.pair(abs(v), places), places)


def triangle_main(first, last, cuts):
    """The triangle over cells first to last, with C from the device, one line a cell for each cut.
    A cut of -1 is MathWorld's c_0 to c_5; any other is R through C_cut from the exact curves.
    Euler-Maclaurin is shared between the cuts."""
    out = sys.stdout
    tail = DeviceTail(os.path.join(ROOT, "build"))
    out.write("  the triangle between the two pairs, C on the device from %s\n" % tail.build())
    em, same = {}, 1
    for cut in cuts:
        triangle = Triangle(tail, cut=[cut, None][int(cut < 0)], em=em)
        for nu in range(first, last + 1):
            begun = time.perf_counter_ns()
            (a, b, delta), kappa, places, digits, parts = triangle.cell(nu)
            read, at = triangle.angle(a, b, delta)
            out.write("  cut %d  cell %d  a %s  b %s  c - b %s  kappa %s  a/b %s  cos gamma %s  parts 2^%d"
                      "  points %d  crossings %d  device equals host %s  %d ms\n"
                      % (cut, nu, signed(a, digits), signed(b, digits), signed(delta, digits),
                         signed(kappa, places), signed(a * 10 ** 12 // b, 12), signed(read, at), parts,
                         len(triangle.em), len(triangle.crossed.get((nu, digits), [])), bool(triangle.same),
                         (time.perf_counter_ns() - begun) // 1000000))
            out.flush()
        same *= triangle.same
    return 1 - same


if __name__ == "__main__":
    if sys.argv[1:2] == ["triangle"]:
        raise SystemExit(triangle_main(int(sys.argv[2]), int(sys.argv[3]),
                                       [int(c) for c in sys.argv[4:]] or [-1]))
    raise SystemExit(main())
