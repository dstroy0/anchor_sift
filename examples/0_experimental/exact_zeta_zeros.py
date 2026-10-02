#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-021
#
# The zeros of the Riemann zeta function, counted and placed by truthy and falsy vector magnitudes.
# Every verdict is a field, zero false and nonzero true. AND is PRODUCT, NOT is 1 - |COMPARE(v, 0)|,
# and a value is gated by PRODUCT(value, verdict). A pass writes its verdicts and the next pass reads
# them. No precision, region, step or term count is assigned in advance.
#
#   Usage:  python examples/0_experimental/exact_zeta_zeros.py [height] [bits]
#
# This reads no corpus. It sits in 0_experimental and is an entry in the analytic number theory
# workbook, on its rail: it claims nothing about the Riemann hypothesis. It counts the zeros below the
# height it is asked to walk to and stops there.
#
# THE VALUES
#
# A value is an exact integer at a count of decimal places, the form representation.exact holds. pi
# comes from representation.constants.naturals, where Machin's and Euler's identities agree, and ln n
# from two series that must agree the same way: k ln 2 plus an artanh against j ln 3 plus another.
# zeta is summed by Euler-Maclaurin: the terms below N, the integral of the rest N^(1-s)/(s-1), half
# the last term, and N Bernoulli corrections, every coefficient an exact rational, and zeta' from the
# same sum differentiated term by term. Two routes run, one at N and one at 2N, each at its places
# plus naturals.GUARD, and the guard is dropped with each value read toward zero.
#
# THE VERDICTS AT A POINT
#
# Each point carries four fields: whether the two routes agree, and the signs of Re zeta, Im zeta and
# |Re zeta| - |Im zeta|. Where the routes disagree, N doubles; where they agree and a sign is zero,
# the places double. A point is decided where every field is nonzero, and its three signs give the
# eighth of a turn zeta sits in. A point asked for more places than representation.exact holds raises
# WillNotFit and does not round.
#
# THE COUNT
#
# Along a closed path of points the eighth turns sum to eight times the zeros inside (the argument
# principle). Each edge is read end to end and through its midpoint, and each half carries two kinds
# of verdict: COMPARE of the smaller |zeta|^2 at its ends against its chord, and at each end COMPARE
# of |zeta|^2 against |zeta'|^2 times the step squared. Zero doubles the places it reads. A negative
# verdict, or two readings that disagree, puts the midpoint into the path. An edge is decided where
# the readings agree and every verdict is positive, and the next pass reads the rest again.
#
# THE LINE, BY SYMMETRY
#
# Every box is symmetric about Re(s) = 1/2. zeta_zero_symmetry.py verifies the group behind this:
# s -> 1 - conj(s) takes a zero to a zero, and its fixed set is the critical line. A zero off the line
# brings its mirror into the same box. A symmetric box that counts one holds a zero on the line.
#
# THE WALK
#
# The boxes climb the strip from t = 1 with Re(s) from 0 to 1. A box counting zero doubles the next
# step, one counting one is a zero, and one counting two or more splits into halves and halves the
# step. Each zero is placed one bit per pass, in squares centred on the line: the lower half counts
# one or zero, and that verdict gates which half the next pass reads.
#
# Positive control: zeta(2) against pi^2/6, and the zeros against the first ordinates of Odlyzko's
# published table, read through representation.exact.units. Drawn null: the integral of the rest left
# out of both routes, where the two routes move apart as N doubles and no point is ever decided.

import os
import sys
from functools import cache
from itertools import compress
from math import comb, gcd

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
import manifest  # noqa: E402,F401
from representation.constants import naturals  # noqa: E402
from representation.exact import at_scale, units  # noqa: E402

GUARD = naturals.GUARD

# Odlyzko's table of zeta zeros, zeros1, the first forty ordinates as printed there.
PUBLISHED = ("14.134725142", "21.022039639", "25.010857580", "30.424876126", "32.935061588",
             "37.586178159", "40.918719012", "43.327073281", "48.005150881", "49.773832478",
             "52.970321478", "56.446247697", "59.347044003", "60.831778525", "65.112544048",
             "67.079810529", "69.546401711", "72.067157674", "75.704690699", "77.144840069",
             "79.337375020", "82.910380854", "84.735492981", "87.425274613", "88.809111208",
             "92.491899271", "94.651344041", "95.870634228", "98.831194218", "101.317851006",
             "103.725538040", "105.446623052", "107.168611184", "111.029535543", "111.874659177",
             "114.320220915", "116.226680321", "118.790782866", "121.370125002", "122.946829294")

COS_SIGN = (1, 0, -1, 0)
SIN_SIGN = (0, 1, 0, -1)


def compare(a, b):
    return (a > b) - (a < b)


def NOT(v):
    return 1 - abs(compare(v, 0))


# ---- (numerator, places) pairs, as representation.exact holds them ----

def pair(numerator, places):
    """A pair with its trailing zeros dropped, as units() drops them. One value has one key."""
    digits = str(abs(numerator))
    zeros = min(places, len(digits) - len(digits.rstrip("0"))) * abs(compare(numerator, 0)) + places * NOT(numerator)
    return (numerator // 10 ** zeros, places - zeros)


def common(a, b):
    places = max(a[1], b[1])
    return a[0] * 10 ** (places - a[1]), b[0] * 10 ** (places - b[1]), places


def plus(a, b):
    x, y, places = common(a, b)
    return pair(x + y, places)


def minus(a, b):
    x, y, places = common(a, b)
    return pair(x - y, places)


def half(a):
    return pair(a[0] * 5, a[1] + 1)


def twice(a):
    return pair(a[0] * 2, a[1])


def middle(a, b):
    return half(plus(a, b))


def select(verdict, a, b):
    """a where the verdict is truthy and b where it is falsy, by PRODUCT and SUM."""
    x, y, places = common(a, b)
    return pair(x * verdict + y * (1 - verdict), places)


def below(a, b):
    x, y, _ = common(a, b)
    return int(x < y)


# ---- ln n and pi, each by two routes that must agree ----

def _artanh(numerator, denominator, scale):
    """floor-wise sum of (n/d)^(2k+1) / (2k+1) at `scale`, for 0 <= n/d < 1."""
    total = 0
    power = scale * numerator // denominator
    step = 0
    while power != 0:
        total += power // (2 * step + 1)
        power = power * numerator * numerator // (denominator * denominator)
        step += 1
    return total


def _ln_by_two(n, scale):
    """ln n = k ln 2 + 2 artanh((n - 2^k) / (n + 2^k)), 2^k the power of two at or below n."""
    k = n.bit_length() - 1
    return k * naturals._ln_two_artanh(scale) + 2 * _artanh(n - (1 << k), n + (1 << k), scale)


def _ln_by_three(n, scale):
    """ln n = j ln 3 + 2 artanh((n - 3^j) / (n + 3^j)), with ln 3 = 2 artanh(1/2)."""
    j, power = 0, 1
    while power * 3 <= n:
        j, power = j + 1, power * 3
    return j * 2 * _artanh(1, 2, scale) + 2 * _artanh(n - power, n + power, scale)


@cache
def ln(n, digits):
    return naturals._agree(lambda scale: _ln_by_two(n, scale), lambda scale: _ln_by_three(n, scale),
                           digits, "ln %d" % n)


@cache
def pi(digits):
    return naturals.pi(digits)


# ---- n^-s at a point ----

def exp_of(x, digits):
    """exp(x) at `digits` places: x = r - k ln 2 with 0 < r <= ln 2, a Taylor series in r."""
    scale = 10 ** digits
    ln_two = ln(2, digits)
    k = (-x) // ln_two + 1
    r = x + k * ln_two
    total = term = scale
    step = 1
    while term != 0:
        term = term * r // (scale * step)
        total += term
        step += 1
    return total * (1 << max(-k, 0)) // (1 << max(k, 0))


def cos_sin(y, digits):
    """cos y and sin y at `digits` places, y reduced to [-pi, pi) by whole turns first."""
    scale = 10 ** digits
    half_turn = pi(digits)
    y = y % (2 * half_turn)
    y -= 2 * half_turn * (y >= half_turn)
    c = s = 0
    term, step = scale, 0
    while term != 0:
        c += term * COS_SIGN[step % 4]
        s += term * SIN_SIGN[step % 4]
        step += 1
        term = term * y // (scale * step)
    return c, s


def power_minus_s(n, sigma, t, digits):
    """n^-s = exp(-sigma ln n) (cos(t ln n) - i sin(t ln n)) at `digits` places, and its
    derivative in s, -ln n n^-s."""
    scale = 10 ** digits
    log = ln(n, digits)
    size = exp_of(-(sigma[0] * log) // 10 ** sigma[1], digits)
    c, s = cos_sin(t[0] * log // 10 ** t[1], digits)
    re, im = size * c // scale, -(size * s // scale)
    return re, im, -(log * re) // scale, -(log * im) // scale


# ---- Euler-Maclaurin, every coefficient an exact rational ----

BERNOULLI = [(1, 1)]


def bernoulli_over_factorial(k):
    """B_2k / (2k)! as a reduced integer pair, the Bernoulli numbers by the standard recurrence."""
    while len(BERNOULLI) <= 2 * k:
        n = len(BERNOULLI)
        num, den = 0, 1
        for j in range(n):
            a, c = BERNOULLI[j]
            num, den = num * c + comb(n + 1, j) * a * den, den * c
            g = gcd(num, den)
            num, den = num // g, den // g
        g = gcd(num, den * (n + 1))
        BERNOULLI.append((-num // g, den * (n + 1) // g))
    num, den = BERNOULLI[2 * k]
    factorial = 1
    for j in range(2, 2 * k + 1):
        factorial *= j
    g = gcd(num, den * factorial)
    return num // g, den * factorial // g


def complex_add(a, b):
    re, im, den = a[0] * b[2] + b[0] * a[2], a[1] * b[2] + b[1] * a[2], a[2] * b[2]
    g = gcd(gcd(re, im), den)
    return re // g, im // g, den // g


def tail_coefficient(sigma, t, n_sum, integral):
    """C and its derivative C' in s, each an exact (re, im, den), where C N^-s is the tail.

    C is N/(s-1) gated by `integral`, plus 1/2, plus the sum of B_2k/(2k)! s(s+1)...(s+2k-2)
    N^(1-2k) for k = 1 .. N. The rising product and its derivative are carried together."""
    xs, xt, places = common(sigma, t)
    unit = 10 ** places
    shifted = xs - unit
    size = shifted * shifted + xt * xt
    total = complex_add((1, 0, 2), (integral * n_sum * unit * shifted, -integral * n_sum * unit * xt, size))
    slope = (-integral * n_sum * unit * unit * (shifted * shifted - xt * xt),
             2 * integral * n_sum * unit * unit * shifted * xt, size * size)
    rising_re, rising_im, rising_den = xs, xt, unit
    turning_re, turning_im = unit, 0
    for k in range(1, n_sum + 1):
        bn, bd = bernoulli_over_factorial(k)
        den = bd * rising_den * n_sum ** (2 * k - 1)
        total = complex_add(total, (bn * rising_re, bn * rising_im, den))
        slope = complex_add(slope, (bn * turning_re, bn * turning_im, den))
        for j in (2 * k - 1, 2 * k):
            re = xs + j * unit
            turning_re, turning_im = (turning_re * re - turning_im * xt + rising_re * unit,
                                      turning_re * xt + turning_im * re + rising_im * unit)
            rising_re, rising_im = rising_re * re - rising_im * xt, rising_re * xt + rising_im * re
            rising_den *= unit
    return total, slope


def times_rational(a, b, c):
    """(a + i b) times the exact complex rational c = (re, im, den)."""
    return (a * c[0] - b * c[1]) // c[2], (a * c[1] + b * c[0]) // c[2]


def zeta_at(sigma, t, n_sum, integral, powers):
    """zeta(sigma + i t) and zeta'(sigma + i t) by Euler-Maclaurin cut at N = n_sum, powers[n - 1]
    holding n^-s and its derivative."""
    head = [sum(p[j] for p in powers[:n_sum - 1]) for j in range(4)]
    a, b, da, db = powers[n_sum - 1]
    total, slope = tail_coefficient(sigma, t, n_sum, integral)
    re, im = times_rational(a, b, total)
    d1, d2 = times_rational(a, b, slope)
    d3, d4 = times_rational(da, db, total)
    return head[0] + re, head[1] + im, head[2] + d1 + d3, head[3] + d2 + d4


def routes(sigma, t, places, n_sum, integral=1):
    """The two routes at `places`: N and 2N, each at places + GUARD with the guard dropped, as zeta
    and zeta' from each route in turn.

    Each value is read toward zero, its sign times the floor of its size. A floor is monotone. A
    nonzero COMPARE between two sizes read this way is the order of the sizes themselves, and a
    value read as zero is one the places cannot sign."""
    digits = places + GUARD
    powers = [power_minus_s(n, sigma, t, digits) for n in range(1, 2 * n_sum + 1)]
    one = zeta_at(sigma, t, n_sum, integral, powers)
    two = zeta_at(sigma, t, 2 * n_sum, integral, powers)
    drop = 10 ** GUARD
    return [compare(v, 0) * (abs(v) // drop) for v in one + two]


# ---- the steering ----

class Steering:
    """The points already decided, and what deciding them cost."""

    def __init__(self):
        self.decided = {}
        self.values = {}
        self.wanted = {}
        self.asked = 0
        self.deepest = 0
        self.widest = 0

    def sweep(self, points):
        """Decide every point's eighth of a turn, pass by pass, each pass reading the last one's verdicts.

        A point is asked again where a chord asked it for more places than it holds."""
        held = [(p, self.values.get(p, (0, 0, 0, 1)), self.wanted.get(p, 1)) for p in dict.fromkeys(points)]
        open_points = [(p, wanted, v[3]) for p, v, wanted in compress(held, [int(v[2] < w) for _, v, w in held])]
        while open_points:
            records = []
            for point, places, n_sum in open_points:
                self.asked += 1
                re_one, im_one, d_re, d_im, re_two, im_two, _, _ = routes(point[0], point[1], places, n_sum)
                at_scale(re_one, places)
                agree = NOT(re_one - re_two) * NOT(im_one - im_two)
                sign_re, sign_im = compare(re_one, 0), compare(im_one, 0)
                sign_size = compare(abs(re_one), abs(im_one))
                records.append((point, places, n_sum, agree, (re_one, im_one, d_re, d_im), sign_re, sign_im,
                                sign_size, agree * abs(sign_re) * abs(sign_im) * abs(sign_size)))
            for point, places, n_sum, _, (re, im, d_re, d_im), sign_re, sign_im, sign_size, _ in compress(
                    records, [r[8] for r in records]):
                quadrant = (1 - sign_im) + (1 - sign_re * sign_im) // 2
                self.decided[point] = 2 * quadrant + ((1 - sign_size) // 2 + quadrant) % 2
                self.values[point] = (re, im, places, n_sum, d_re, d_im)
                self.deepest = max(self.deepest, places)
                self.widest = max(self.widest, n_sum)
            open_points = [(point, places * (1 + agree), n_sum * (2 - agree))
                           for point, places, n_sum, agree, *_ in compress(records, [NOT(r[8]) for r in records])]

    def turn(self, a, c):
        """Eighth turns of zeta from point a to point c, read as the shorter way round."""
        return (self.decided[c] - self.decided[a] + 4) % 8 - 4

    def short(self, a, c):
        """Two verdicts on a chord: its ends at the same places, and COMPARE(smaller |zeta|^2, chord^2).

        The second is truthy and positive where the chord |zeta(c) - zeta(a)| is under the smaller of
        |zeta(a)| and |zeta(c)|, which keeps the angle between them under a sixth of a turn; negative
        where it is not; zero where the places cannot tell."""
        ra, ia, pa = self.values[a][:3]
        rc, ic, pc = self.values[c][:3]
        size = min(ra * ra + ia * ia, rc * rc + ic * ic)
        return NOT(pa - pc), compare(size, (rc - ra) ** 2 + (ic - ia) ** 2)

    def step(self, a, c, end):
        """COMPARE(|zeta|^2, |zeta'|^2 |c - a|^2) at one end of the step from a to c.

        Positive where the step moves zeta less than its own size, read from the derivative at that
        end. Two values alone cannot see zeta wind once between them and land where it began; the
        derivative sees how fast it turns."""
        re, im, _, _, d_re, d_im = self.values[end]
        x, y, places = common(minus(c[0], a[0]), minus(c[1], a[1]))
        return compare((re * re + im * im) * 10 ** (2 * places), (d_re * d_re + d_im * d_im) * (x * x + y * y))

    def deeper(self, points, places):
        """Ask each point again at the places given."""
        for p in points:
            self.wanted[p] = places

    def count(self, boxes):
        """Zeros in each box [left, right] x [low, high], by the winding of zeta around its edge.

        Each edge is read twice, end to end and through its midpoint, and each half carries its chord's
        verdict and a step verdict at each end. Ends at different places are asked again at the deeper
        one. A verdict of zero doubles the places it reads. An edge whose two readings disagree, or
        with a negative verdict on either half, takes its midpoint into the path. An edge is decided
        where the readings agree and every verdict on both halves is positive. The next pass reads
        every edge the same way."""
        paths = [box_corners(box) for box in boxes]
        counts = [None] * len(boxes)
        active = list(range(len(boxes)))
        while active:
            edges = {k: [(a, (middle(a[0], c[0]), middle(a[1], c[1])), c)
                         for a, c in zip(paths[k], paths[k][1:] + paths[k][:1])] for k in active}
            self.sweep([p for k in active for edge in edges[k] for p in edge])
            verdicts = []
            for k in active:
                fine = [(self.turn(a, m), self.turn(m, c)) for a, m, c in edges[k]]
                agree = [NOT(self.turn(a, c) - f1 - f2) for (a, m, c), (f1, f2) in zip(edges[k], fine)]
                settled, split = [], []
                for (a, m, c), v in zip(edges[k], agree):
                    positive, kept = v, v
                    for x, y in ((a, m), (m, c)):
                        same, chord = self.short(x, y)
                        places = max(self.values[x][2], self.values[y][2])
                        self.deeper(compress((x, y), (NOT(same),) * 2), places)
                        self.deeper(compress((x, y), (same * NOT(chord),) * 2), 2 * places)
                        from_x, from_y = self.step(x, y, x), self.step(x, y, y)
                        self.deeper(compress((x,), (NOT(from_x),)), 2 * self.values[x][2])
                        self.deeper(compress((y,), (NOT(from_y),)), 2 * self.values[y][2])
                        positive *= same * ((1 + chord) // 2) * ((1 + from_x) // 2) * ((1 + from_y) // 2)
                        kept *= (1 - same * ((1 - chord) // 2)) * (1 - (1 - from_x) // 2) * (1 - (1 - from_y) // 2)
                    settled.append(positive)
                    split.append(1 - kept)
                counts[k] = sum(f1 + f2 for f1, f2 in fine) // 8
                verdicts.append(min(settled))
                paths[k] = [p for (a, m, _), s in zip(edges[k], split) for p in compress((a, m), (1, s))]
            active = list(compress(active, [NOT(v) for v in verdicts]))
        return counts

    def walk(self, height):
        """Up the strip. Each pass counts the open boxes and its verdicts gate the next pass's boxes."""
        found = []
        boxes = []
        low, step = (1, 0), (1, 0)
        while below(low, height) or boxes:
            top = below(low, height)
            high = select(below(plus(low, step), height), plus(low, step), height)
            asked = boxes + [((0, 0), (1, 0), low, high)] * top
            counts = self.count(asked)
            one = [NOT(n - 1) for n in counts]
            many = [int(n > 1) for n in counts]
            found += compress(asked, one)
            boxes = [half_box for box in compress(asked, many) for half_box in halves(box)]
            last = counts[-1] * top
            step = select(NOT(last), twice(step), select(int(last > 1), half(step), step))
            low = select(top, high, low)
        depth = max([box[2][1] for box in found] + [0])
        return sorted(found, key=lambda box: box[2][0] * 10 ** (depth - box[2][1]))

    def place(self, found, bits):
        """One bit per pass for every zero at once: does the lower square centred on the line count one?"""
        brackets = [(box[2], box[3]) for box in found]
        paths = [""] * len(brackets)
        for _ in range(bits):
            squares = []
            for low, high in brackets:
                centre = middle(low, high)
                reach = half(minus(centre, low))
                squares.append((minus((5, 1), reach), plus((5, 1), reach), low, centre))
            lower = [NOT(n - 1) for n in self.count(squares)]
            brackets = [(select(v, low, middle(low, high)), select(v, middle(low, high), high))
                        for v, (low, high) in zip(lower, brackets)]
            paths = [path + "01"[1 - v] for v, path in zip(lower, paths)]
        return brackets, paths


def box_corners(box):
    left, right, low, high = box
    return [(left, low), (right, low), (right, high), (left, high)]


def refined(path):
    """The path with a midpoint in every edge."""
    out = []
    for k, a in enumerate(path):
        c = path[(k + 1) % len(path)]
        out += [a, (middle(a[0], c[0]), middle(a[1], c[1]))]
    return out


def halves(box):
    left, right, low, high = box
    centre = middle(low, high)
    return [(left, right, low, centre), (left, right, centre, high)]


def holds(low, high, published):
    """Whether [low, high] meets the published value's own bracket, half a unit in its last place."""
    value = units(published)
    unit = (5, value[1] + 1)
    return int(NOT(below(plus(value, unit), low)) * NOT(below(high, minus(value, unit))))


def decimal(a, places):
    whole, part = divmod(a[0] * 10 ** places // 10 ** a[1], 10 ** places)
    return "%d.%0*d" % (whole, places, part)


def gap(sigma, t, places, n_sum, integral=1):
    """How far apart the two routes land at N = n_sum, in units of the last place."""
    re_one, im_one, _, _, re_two, im_two, _, _ = routes(sigma, t, places, n_sum, integral)
    return abs(re_one - re_two) + abs(im_one - im_two), (re_one, im_one)


def agreed_value(sigma, t, places):
    """zeta where the two routes agree at `places`, N doubling while they do not, and each gap."""
    n_sum = 1
    gaps = [gap(sigma, t, places, n_sum)]
    while gaps[-1][0]:
        n_sum *= 2
        gaps.append(gap(sigma, t, places, n_sum))
    return gaps[-1][1], n_sum, [g for g, _ in gaps]


def main():
    out = sys.stdout
    height = units((sys.argv[1:] + ["50"])[0])
    bits = int((sys.argv[2:] + ["16"])[0])
    out.write("  zeros of zeta counted and placed by truthy and falsy verdicts, in exact integers\n")
    out.write("  this counts the zeros it reaches and claims nothing about the Riemann hypothesis\n\n")

    places = 30
    value, n_sum, _ = agreed_value((2, 0), (0, 0), places)
    digits = places + GUARD
    sixth = pi(digits) * pi(digits) // (6 * 10 ** digits) // 10 ** GUARD
    zeta_two = NOT(value[0] - sixth) * NOT(value[1])
    out.write("  zeta(2) at %d places, routes agreeing at N = %d, equals pi^2/6 from naturals.pi: %s\n\n"
              % (places, n_sum, bool(zeta_two)))
    out.flush()

    steering = Steering()
    found = steering.walk(height)
    out.write("  %d zeros with 1 < t < %s, each alone in a box symmetric about Re(s) = 1/2\n"
              % (len(found), decimal(height, height[1])))
    brackets, paths = steering.place(found, bits)
    out.write("  %-36s %-14s %s\n" % ("placed by %d bits" % bits, "published", "holds"))
    every = int(len(found) >= 1)
    for (low, high), path, published in zip(brackets, paths, PUBLISHED):
        held = holds(low, high, published)
        every *= held
        out.write("  [%s, %s]  %-14s %s   %s\n" % (decimal(low, 8), decimal(high, 8), published, bool(held), path))
    for (low, high), path in zip(brackets[len(PUBLISHED):], paths[len(PUBLISHED):]):
        out.write("  [%s, %s]  %-14s %s   %s\n" % (decimal(low, 8), decimal(high, 8), "-", "-", path))
    out.write("  %d values asked, the deepest point at %d places, the widest at N = %d\n\n"
              % (steering.asked, steering.deepest, steering.widest))

    point = ((5, 1), (20, 0))
    _, n_true, true_gaps = agreed_value(*point, places=4)
    null_gaps = [gap(*point, 4, 1 << j, integral=0)[0] for j in range(len(true_gaps) + 4)]
    out.write("  drawn null at s = 1/2 + 20i, 4 places: the gap between the two routes as N doubles from 1\n")
    out.write("    with N^(1-s)/(s-1):    %s, agreeing at N = %d\n" % (true_gaps, n_true))
    out.write("    without it:            %s\n" % null_gaps)
    apart = int(null_gaps[-1] > null_gaps[-2] > 0)
    out.write("  without the integral of the rest the routes move apart and nothing is decided: %s\n" % bool(apart))
    out.flush()

    published_below = sum(below(units(p), height) for p in PUBLISHED)
    covered = below(height, units(PUBLISHED[-1]))
    counted = covered * NOT(len(found) - published_below) + (1 - covered) * int(len(found) >= len(PUBLISHED))
    out.write("  the count against the published table below t = %s: %s\n" % (decimal(height, height[1]), bool(counted)))
    return 1 - zeta_two * every * apart * counted


if __name__ == "__main__":
    raise SystemExit(main())
