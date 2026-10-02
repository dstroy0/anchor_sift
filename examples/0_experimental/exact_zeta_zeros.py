#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-021
#
# The zeros of the Riemann zeta function, counted and placed by truthy falsy steering in exact
# integers. Every decision is a bit, and a bit that is not yet decided steers: it raises the scale
# at one point or splits one edge. No precision, region or step is assigned in advance.
#
#   Usage:  python examples/0_experimental/exact_zeta_zeros.py [zeros] [bits]
#
# This reads no corpus. It sits in 0_experimental and is an entry in the analytic number theory
# workbook, on its rail: it claims nothing about the Riemann hypothesis. It counts the zeros up to the
# height it walks to and stops there.
#
# THE BITS
#
# A value of zeta is carried as an integer bracket at scale 2^-b. The two bits asked of it are
# Re > 0 and Im > 0. A bracket holding zero leaves a bit undecided, and the point asks again at
# twice the scale. A point stops at the first scale where both bits are decided, and each point
# finds its own. Near a zero the scale climbs; away from one it stays at the first.
#
# The bits of the corners of a box give the quadrant of zeta there. Along an edge, one more bit is
# asked: does the bracket of zeta over the whole edge stay on one side of a line through zero? Where
# it does, the quadrant moves at most one step along that edge, and the step is read from the two
# end quadrants. Where it does not, the edge splits at its midpoint and each half asks the same bit,
# at the scale its ends needed. The quarter turns around the box sum to four times the zeros inside
# (the argument principle). The count is an integer read from sign bits alone.
#
# THE LINE, BY SYMMETRY
#
# Every box is symmetric about Re(s) = 1/2. zeta_zero_symmetry.py verifies the group behind this:
# s -> 1 - conj(s) takes a zero to a zero, and its fixed set is the critical line. A zero off the line
# brings its mirror into the same box. A symmetric box that counts one therefore holds a zero on the
# line, and no other function is needed to say so.
#
# THE STEERING
#
# The walk climbs the strip from t = 1 in boxes whose sides are the strip's own edges, Re(s) = 0 and
# Re(s) = 1. A box that counts zero doubles the next step. A box that counts two or more halves it. A
# box that counts one is a zero. Each zero is then placed one bit at a time: the box splits at half
# its height, and the bit is whether the lower half counts one. The bits are the binary digits of the
# zero's height, read off the boundary. A placing box is a square on the line, its width its height.
#
# THE VALUES
#
# zeta is summed by Euler-Maclaurin: the terms below N, the integral of the rest, N^(1-s)/(s-1),
# half the last term, and ten Bernoulli corrections. The remainder has a proven bound,
# |s + 2m + 1| / (Re(s) + 2m + 1) times the first term left out, and the bracket carries it. N doubles
# while doubling it still halves that bound. Logarithms come from artanh, pi from Machin's formula
# and checked by Euler's, cosine and sine from Taylor series with the last term as the bound. All of
# it is integers with one denominator per value.
#
# Positive control: the walk's zeros against the first ten ordinates of Odlyzko's published table,
# printed there to nine places. Each placed bracket has to hold its published value. Drawn null:
# zeta without the integral of the rest, N^(1-s)/(s-1), counts a zero between t = 1 and t = 10, where
# there is none, and eleven below t = 50, where there are ten. The infinity that term carries is
# what the sum needs subtracted.

import sys
from math import comb, gcd, isqrt

# The scale every point asks at first. A point needing more raises its own.
FIRST_BITS = 24

# Bernoulli corrections in the Euler-Maclaurin sum.
TERMS = 10

# Odlyzko's table of zeta zeros, the first ten ordinates as printed there.
PUBLISHED = ("14.134725142", "21.022039639", "25.010857580", "30.424876126", "32.935061588",
             "37.586178159", "40.918719012", "43.327073281", "48.005150881", "49.773832478")


def ratio(num, den=1):
    """A rational as (numerator, denominator), reduced, the denominator positive."""
    if den < 0:
        num, den = -num, -den
    g = gcd(num, den) or 1
    return (num // g, den // g)


def ratio_sum(x, y):
    return ratio(x[0] * y[1] + y[0] * x[1], x[1] * y[1])


def ratio_middle(x, y):
    return ratio(x[0] * y[1] + y[0] * x[1], 2 * x[1] * y[1])


def ratio_difference(x, y):
    return ratio(x[0] * y[1] - y[0] * x[1], x[1] * y[1])


def from_decimal(text):
    """Decimal text as a rational, every digit kept."""
    whole, _, places = text.partition(".")
    return ratio(int(whole + places), 10 ** len(places))


def lift(x, y, b):
    """The rational range between x and y as integers at scale 2^-b, rounded outward."""
    lo = min((x[0] << b) // x[1], (y[0] << b) // y[1])
    hi = max(-((-(x[0] << b)) // x[1]), -((-(y[0] << b)) // y[1]))
    return (lo, hi)


def whole(n, b):
    return (n << b, n << b)


def add(a, c):
    return (a[0] + c[0], a[1] + c[1])


def sub(a, c):
    return (a[0] - c[1], a[1] - c[0])


def neg(a):
    return (-a[1], -a[0])


def mul(a, c, b):
    products = (a[0] * c[0], a[0] * c[1], a[1] * c[0], a[1] * c[1])
    return (min(products) >> b, -((-max(products)) >> b))


def times(a, num, den):
    """A bracket times the rational num/den, den positive."""
    ends = (a[0] * num, a[1] * num)
    return (min(ends) // den, -((-max(ends)) // den))


def widen(a, r):
    return (a[0] - r, a[1] + r)


def divide_positive(a, c, b):
    lo = min((x << b) // y for x in a for y in c)
    hi = max(-((-(x << b)) // y) for x in a for y in c)
    return (lo, hi)


def reach(a):
    return max(abs(a[0]), abs(a[1]))


KEPT = {}


def kept(name, b, make):
    """A constant asked at a scale, made once at that scale."""
    if (name, b) not in KEPT:
        KEPT[(name, b)] = make(b)
    return KEPT[(name, b)]


def artanh_ratio(num, den, b):
    """artanh(num/den) for 0 < num/den <= 1/3. The tail past a term below one unit is under two units."""
    total = (0, 0)
    k = 0
    while True:
        e = 2 * k + 1
        term = lift(ratio(num ** e, den ** e * e), ratio(num ** e, den ** e * e), b)
        if term[1] <= 1:
            return widen(total, 3)
        total = add(total, term)
        k += 1


def arctan_inverse(k, b):
    """arctan(1/k). The series alternates and the tail is under the first term left out."""
    total = (0, 0)
    j = 0
    while True:
        e = 2 * j + 1
        term = lift(ratio(1, e * k ** e), ratio(1, e * k ** e), b)
        if term[1] <= 1:
            return widen(total, 2)
        total = add(total, term) if j % 2 == 0 else sub(total, term)
        j += 1


def pi_machin(b):
    return kept("pi", b, lambda b: sub(times(arctan_inverse(5, b + 8), 16, 1 << 8),
                                       times(arctan_inverse(239, b + 8), 4, 1 << 8)))


def pi_euler(b):
    return times(add(arctan_inverse(2, b), arctan_inverse(3, b)), 4, 1)


def log_of(n, b):
    """log n = k log 2 + 2 artanh((n - 2^k) / (n + 2^k)), with 2^k the power of two at or below n."""
    def make(b):
        k = n.bit_length() - 1
        base = times(times(artanh_ratio(1, 3, b), 2, 1), k, 1)
        num, den = n - (1 << k), n + (1 << k)
        if num == 0:
            return base
        g = gcd(num, den)
        return add(base, times(artanh_ratio(num // g, den // g, b), 2, 1))
    return kept(("log", n), b, make)


def exp_at(v, b):
    """exp(v 2^-b): halved until under one half, Taylor until a term is under one unit, squared back."""
    j = 0
    while abs(v) >> j > (1 << (b - 1)):
        j += 1
    x = (v >> j, -((-v) >> j))
    total = term = whole(1, b)
    k = 1
    while True:
        term = times(mul(term, x, b), 1, k)
        total = add(total, term)
        if reach(term) <= 1:
            break
        k += 1
    total = widen(total, k + 2)
    for _ in range(j):
        total = mul(total, total, b)
    return total


def exp_over(a, b):
    """exp over a bracket, by the value at each end."""
    return (exp_at(a[0], b)[0], exp_at(a[1], b)[1])


def cos_sin_small(x, b):
    c, s, term = whole(1, b), x, x
    k = 2
    while True:
        term = times(mul(term, x, b), 1, k)
        step = k % 4
        if step == 0:
            c = add(c, term)
        elif step == 1:
            s = add(s, term)
        elif step == 2:
            c = sub(c, term)
        else:
            s = sub(s, term)
        if reach(term) <= 1:
            break
        k += 1
    return widen(c, k + 2), widen(s, k + 2)


def cos_sin(a, b):
    """cos and sin over a bracket: the value at its middle, widened by its half width, since both
    slopes are at most one. The middle is reduced by whole turns, halved, and doubled back."""
    middle = (a[0] + a[1]) >> 1
    half_width = max(middle - a[0], a[1] - middle) + 1
    turn = times(pi_machin(b), 2, 1)
    turns = middle // ((turn[0] + turn[1]) >> 1)
    x = sub((middle, middle), times(turn, turns, 1))
    j = 0
    while reach(x) >> j > (1 << (b - 1)):
        j += 1
    x = (x[0] >> j, -((-x[1]) >> j))
    c, s = cos_sin_small(x, b)
    for _ in range(j):
        c, s = sub(mul(c, c, b), mul(s, s, b)), times(mul(s, c, b), 2, 1)
    return widen(c, half_width), widen(s, half_width)


def complex_add(z, w):
    return (add(z[0], w[0]), add(z[1], w[1]))


def complex_mul(z, w, b):
    return (sub(mul(z[0], w[0], b), mul(z[1], w[1], b)), add(mul(z[0], w[1], b), mul(z[1], w[0], b)))


def complex_times(z, num, den):
    return (times(z[0], num, den), times(z[1], num, den))


def complex_divide(z, w, b):
    size = add(mul(w[0], w[0], b), mul(w[1], w[1], b))
    size = (max(size[0], 1), size[1])
    top = complex_mul(z, (w[0], neg(w[1])), b)
    return (divide_positive(top[0], size, b), divide_positive(top[1], size, b))


def complex_reach(z, b):
    """An upper bound on the modulus over the bracket, at scale b."""
    squared = -((-(reach(z[0]) ** 2 + reach(z[1]) ** 2)) >> b)
    return isqrt(squared << b) + 1


def bernoulli(upto):
    """B_0 .. B_upto as reduced integer pairs, by the standard recurrence."""
    found = [(1, 1)]
    for n in range(1, upto + 1):
        num, den = 0, 1
        for j in range(n):
            a, c = found[j]
            num, den = num * c + comb(n + 1, j) * a * den, den * c
            g = gcd(num, den)
            num, den = num // g, den // g
        found.append(ratio(-num, den * (n + 1)))
    return found


BERNOULLI = bernoulli(2 * TERMS + 2)
FACTORIAL = [1]
for _k in range(1, 2 * TERMS + 3):
    FACTORIAL.append(FACTORIAL[-1] * _k)


def power_minus_s(n, sig, t, b):
    """n^-s = exp(-sig log n) (cos(t log n) - i sin(t log n)), over the bracket."""
    log_n = log_of(n, b)
    size = exp_over(neg(mul(sig, log_n, b)), b)
    c, s = cos_sin(mul(t, log_n, b), b)
    return (mul(size, c, b), neg(mul(size, s, b)))


def euler_maclaurin(sig, t, b, n_sum, with_integral=True):
    """zeta over the bracket at scale b, and the proven bound on the remainder left out."""
    total = ((0, 0), (0, 0))
    for n in range(1, n_sum):
        total = complex_add(total, power_minus_s(n, sig, t, b))
    last = power_minus_s(n_sum, sig, t, b)
    if with_integral:
        total = complex_add(total, complex_divide(complex_times(last, n_sum, 1), (sub(sig, whole(1, b)), t), b))
    total = complex_add(total, complex_times(last, 1, 2))
    rising = (sig, t)
    term = None
    for k in range(1, TERMS + 2):
        num, den = BERNOULLI[2 * k]
        term = complex_times(complex_mul(last, rising, b), num, den * FACTORIAL[2 * k] * n_sum ** (2 * k - 1))
        if k == TERMS + 1:
            break
        total = complex_add(total, term)
        rising = complex_mul(rising, (add(sig, whole(2 * k - 1, b)), t), b)
        rising = complex_mul(rising, (add(sig, whole(2 * k, b)), t), b)
    shifted = (add(sig, whole(2 * TERMS + 1, b)), t)
    floor = sig[0] + ((2 * TERMS + 1) << b)
    left_out = -((-(complex_reach(shifted, b) * complex_reach(term, b))) // floor) + 1
    return total, left_out


SUMMED = {}


def zeta(sig, t, b, with_integral=True):
    """zeta over the bracket. N doubles while doubling it still halves what is left out."""
    key = (b, reach(t) >> b, with_integral)
    n_sum = SUMMED.get(key, 4)
    total, left_out = euler_maclaurin(sig, t, b, n_sum, with_integral)
    while left_out > 16:
        more, more_left = euler_maclaurin(sig, t, b, 2 * n_sum, with_integral)
        if 2 * more_left > left_out:
            break
        n_sum, total, left_out = 2 * n_sum, more, more_left
    SUMMED[key] = n_sum
    return (widen(total[0], left_out), widen(total[1], left_out))


def sign_bits(z):
    """(Re > 0, Im > 0), each True, False, or None where the bracket holds zero."""
    re, im = z
    return (True if re[0] > 0 else False if re[1] < 0 else None,
            True if im[0] > 0 else False if im[1] < 0 else None)


QUADRANT = {(True, True): 0, (False, True): 1, (False, False): 2, (True, False): 3}


class Steering:
    """The walk's state: the points already asked, and what asking cost."""

    def __init__(self, with_integral=True):
        self.with_integral = with_integral
        self.points = {}
        self.asked = 0
        self.deepest = FIRST_BITS

    def point(self, sig, t, b=FIRST_BITS):
        """A point and its quadrant. Where a bit is undecided the point raises its own scale."""
        if (sig, t) not in self.points:
            while True:
                self.asked += 1
                bits = sign_bits(zeta(lift(sig, sig, b), lift(t, t, b), b, self.with_integral))
                if None not in bits:
                    break
                b *= 2
            self.deepest = max(self.deepest, b)
            self.points[(sig, t)] = (sig, t, QUADRANT[bits], b)
        return self.points[(sig, t)]

    def one_side(self, a, c, b):
        """The edge's bit: does zeta over the whole edge stay on one side of a line through zero?"""
        self.asked += 1
        bits = sign_bits(zeta(lift(a[0], c[0], b), lift(a[1], c[1], b), b, self.with_integral))
        return bits != (None, None)

    def quarter_turns(self, a, c):
        """Quarter turns of zeta along the edge a -> c. An undecided edge splits at its midpoint."""
        b = max(a[3], c[3])
        if self.one_side(a, c, b):
            step = (c[2] - a[2]) % 4
            if step == 2:
                raise ArithmeticError("opposite quadrants on one side of a line")
            return {0: 0, 1: 1, 3: -1}[step]
        middle = self.point(ratio_middle(a[0], c[0]), ratio_middle(a[1], c[1]), b)
        return self.quarter_turns(a, middle) + self.quarter_turns(middle, c)

    def count(self, low, high, left=ratio(0), right=ratio(1)):
        """Zeros of zeta in the box [left, right] x [low, high], by its winding around the edge."""
        corners = [self.point(left, low), self.point(right, low), self.point(right, high), self.point(left, high)]
        turns = sum(self.quarter_turns(corners[k], corners[(k + 1) % 4]) for k in range(4))
        if turns % 4:
            raise ArithmeticError("the turns around a closed edge are not whole")
        return turns // 4

    def walk(self, wanted, low=ratio(1)):
        """Up the strip. An empty box doubles the step, a crowded box halves it, a box of one is a zero."""
        found = []
        step = ratio(1)
        while len(found) < wanted:
            high = ratio_sum(low, step)
            n = self.count(low, high)
            if n == 1:
                found.append((low, high))
                low = high
            elif n == 0:
                low, step = high, ratio_sum(step, step)
            else:
                step = ratio(step[0], step[1] * 2)
        return found

    def place(self, low, high, bits):
        """One bit per count, in squares centred on the line: is the zero in the lower half?"""
        path = []
        for _ in range(bits):
            middle = ratio_middle(low, high)
            half = ratio(middle[0] * low[1] - low[0] * middle[1], 2 * middle[1] * low[1])
            left, right = ratio_difference(ratio(1, 2), half), ratio_sum(ratio(1, 2), half)
            if self.count(low, middle, left, right) == 1:
                high = middle
                path.append("0")
            else:
                low = middle
                path.append("1")
        return low, high, "".join(path)


def holds(low, high, published):
    """Whether [low, high] meets the published value's own bracket, half a unit in its last place."""
    value = from_decimal(published)
    unit = ratio(1, 2 * 10 ** len(published.partition(".")[2]))
    below, above = ratio_difference(value, unit), ratio_sum(value, unit)
    return low[0] * above[1] <= above[0] * low[1] and below[0] * high[1] <= high[0] * below[1]


def decimal(x, places):
    return "%d.%0*d" % (x[0] // x[1], places, (x[0] % x[1]) * 10 ** places // x[1])


def main():
    out = sys.stdout
    wanted = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    bits = int(sys.argv[2]) if len(sys.argv) > 2 else 16
    out.write("  zeros of zeta counted and placed by sign bits, in exact integers\n")
    out.write("  this counts the zeros it reaches and claims nothing about the Riemann hypothesis\n\n")

    machin, euler = pi_machin(64), pi_euler(64)
    pi_agrees = machin[0] <= euler[1] and euler[0] <= machin[1]
    two = zeta(whole(2, 64), (0, 0), 64)
    sixth = times(mul(machin, machin, 64), 1, 6)
    zeta_two = two[0][0] <= sixth[0] and sixth[1] <= two[0][1]
    out.write("  pi by Machin and by Euler overlap: %s\n" % pi_agrees)
    out.write("  zeta(2) holds pi^2/6: %s\n\n" % zeta_two)

    steering = Steering()
    found = steering.walk(wanted)
    out.write("  %d zeros above t = 1, each alone in a box symmetric about Re(s) = 1/2\n" % len(found))
    out.write("  %-36s %-14s %s\n" % ("placed by %d bits" % bits, "published", "holds"))
    every = len(found) == wanted
    for index, (low, high) in enumerate(found):
        low, high, path = steering.place(low, high, bits)
        published = PUBLISHED[index] if index < len(PUBLISHED) else None
        held = holds(low, high, published) if published else None
        every = every and held is not False
        out.write("  [%s, %s]  %-14s %s   %s\n" % (decimal(low, 8), decimal(high, 8), published or "-", held, path))
        out.flush()
    out.write("  %d values asked, the deepest point at scale 2^-%d\n\n" % (steering.asked, steering.deepest))

    null = Steering(with_integral=False)
    empty = null.count(ratio(1), ratio(10))
    below_fifty = null.count(ratio(1), ratio(50))
    out.write("  drawn null, zeta without N^(1-s)/(s-1): %d zero(s) in 1 < t < 10, %d below t = 50\n"
              % (empty, below_fifty))
    true_count = Steering().count(ratio(1), ratio(50))
    out.write("  with it: 0 in 1 < t < 10 is %s, %d below t = 50\n" % (Steering().count(ratio(1), ratio(10)) == 0, true_count))
    null_refused = empty != 0 or below_fifty != true_count
    out.flush()

    return 0 if (pi_agrees and zeta_two and every and null_refused and true_count == 10) else 1


if __name__ == "__main__":
    raise SystemExit(main())
