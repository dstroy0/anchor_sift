#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-018
#
# The congruent number problem, the oldest question that sits on the Birch and Swinnerton-Dyer
# conjecture, read in exact integer and rational arithmetic. It runs the two things BSD makes exactly
# computable: Tunnell's criterion, a pure integer count of a ternary quadratic form, and the rational
# points on the curve C_n : y^2 = x^3 - n^2 x, whose group law is exact rational arithmetic. It claims
# nothing about the conjecture. It shows which side of it is exact and which side is a computed real.
#
#   Usage:  python examples/0_experimental/exact_congruent_number.py
#
# This reads no corpus, so it sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. The arithmetic is the engine's own: Python integers as the bignum, and an exact rational
# carried as a reduced (numerator, denominator) pair of native integers, reduced by a hand-written
# Euclid. No float, no fraction library, no math library; the one square root needed is an integer
# Newton iteration on native integers.
#
# WHAT THE PROBLEM IS. A congruent number is a squarefree positive integer that is the area of a right
# triangle with rational sides. Fibonacci was challenged with n = 5 and found the triangle (3/2, 20/3,
# 41/6). Fermat proved n = 1 is not congruent. The problem, in the words of Wiles's Clay statement,
# reduces to the rational points on C_n : y^2 = x^3 - n^2 x: n is congruent exactly when C_n(Q) is
# infinite, which BSD ties to L(C_n, 1) = 0.
#
# THE TWO EXACT HANDLES.
#   Tunnell's count   For n odd and squarefree, Tunnell proved unconditionally that if n is congruent
#                     then A(n) = 2 B(n), where A(n) = #{(x,y,z) in Z^3 : 2x^2 + y^2 + 8z^2 = n} and
#                     B(n) = #{(x,y,z) : 2x^2 + y^2 + 32z^2 = n}. These are exact integer counts. The
#                     contrapositive is unconditional: A(n) != 2 B(n) proves n is not congruent, and it
#                     reproduces Fermat's n = 1. The converse, that the equality implies congruent, is
#                     conditional on BSD, and that is the floor, stated and not crossed.
#   the group law     C_n(Q) is a finitely generated abelian group under the chord-tangent law, which is
#                     exact rational arithmetic. A rational point whose coordinates are not integers is
#                     not torsion, by Nagell-Lutz; it then has infinite order, C_n(Q) is infinite, and n
#                     is congruent, and this direction needs no BSD. For n = 5 the point (-4, 6) is
#                     integral and on the curve, and its double is not integral, which proves it has
#                     infinite order and certifies n = 5 unconditionally.
#
# Positive control: Fermat's n = 1 recovered as not congruent by the exact count, and the point (-4, 6)
# verified on C_5 with the triangle (3/2, 20/3, 41/6) an exact area-5 right triangle. Two routes: n = 5
# certified congruent both by the infinite-order point and by the Tunnell equality; and each theta count
# taken twice over two different bounding boxes, agreeing. Drawn null: n = 1 and n = 3, where the count
# is unequal and the criterion correctly refuses congruence, and a torsion point (on y^2 = x^3 + 1) that
# is integral and of finite order, the contrast to the infinite-order witness. Floor: the converse of
# Tunnell's criterion is conditional on BSD, and a bounded search for a triangle or a point bounds
# nothing about its absence.
#
# Prior art, named with respect. The problem is in Diophantus and the Arab manuscripts of the tenth
# century; Fibonacci found the n = 5 triangle and Fermat proved n = 1 is not congruent and introduced
# descent. The reduction to C_n and the group law are Poincare's and Mordell's (finite generation, 1922),
# on the chord-tangent construction of Diophantus and Fermat. Nagell and Lutz gave the integrality of
# torsion. Tunnell's criterion is J. Tunnell, "A classical Diophantine problem and modular forms of
# weight 3/2", Invent. Math. 72 (1983). The statement and its sets are Wiles's Clay description, read in
# full. Cited from that document and from memory of the literature; this file verifies only the exact
# integer and rational quantities and rests on no unread result. It adds no new mathematics.

import io
import sys


def gcd(first, second):
    """The greatest common divisor by Euclid, on absolute values."""
    first, second = abs(first), abs(second)
    while second:
        first, second = second, first % second
    return first


def isqrt(value):
    """The integer square root of a non-negative integer, by Newton's iteration on native integers."""
    if value < 0:
        raise ValueError("isqrt of a negative integer")
    if value == 0:
        return 0
    guess = value
    step = (guess + 1) // 2
    while step < guess:
        guess = step
        step = (guess + value // guess) // 2
    return guess


class Rational:
    """An exact rational as a reduced (numerator, denominator) pair of native integers, denominator > 0."""
    __slots__ = ("num", "den")

    def __init__(self, num, den=1):
        if den == 0:
            raise ZeroDivisionError("rational with zero denominator")
        if den < 0:
            num, den = -num, -den
        divisor = gcd(num, den) or 1
        self.num = num // divisor
        self.den = den // divisor

    def __add__(self, other):
        other = as_rational(other)
        return Rational(self.num * other.den + other.num * self.den, self.den * other.den)

    def __sub__(self, other):
        other = as_rational(other)
        return Rational(self.num * other.den - other.num * self.den, self.den * other.den)

    def __mul__(self, other):
        other = as_rational(other)
        return Rational(self.num * other.num, self.den * other.den)

    def __truediv__(self, other):
        other = as_rational(other)
        return Rational(self.num * other.den, self.den * other.num)

    def __neg__(self):
        return Rational(-self.num, self.den)

    def __eq__(self, other):
        other = as_rational(other)
        return self.num == other.num and self.den == other.den

    def __ne__(self, other):
        return not self == other

    def is_integer(self):
        return self.den == 1

    def is_square(self):
        """Whether a non-negative rational is the square of a rational: numerator and denominator both squares."""
        if self.num < 0:
            return False
        root_num = isqrt(self.num)
        root_den = isqrt(self.den)
        return root_num * root_num == self.num and root_den * root_den == self.den

    def sqrt(self):
        """The rational square root, defined only where is_square holds."""
        return Rational(isqrt(self.num), isqrt(self.den))

    def __repr__(self):
        return str(self.num) if self.den == 1 else "%d/%d" % (self.num, self.den)


def as_rational(value):
    return value if isinstance(value, Rational) else Rational(value)


# a point is either INFINITY (the identity O) or a tuple (Rational x, Rational y)
INFINITY = None


class Curve:
    """The elliptic curve y^2 = x^3 + a x + b over Q, with the exact chord-tangent group law."""

    def __init__(self, a, b):
        self.a = as_rational(a)
        self.b = as_rational(b)

    def on_curve(self, point):
        if point is INFINITY:
            return True
        x, y = point
        return y * y == x * x * x + self.a * x + self.b

    def negate(self, point):
        if point is INFINITY:
            return INFINITY
        x, y = point
        return (x, -y)

    def add(self, first, second):
        if first is INFINITY:
            return second
        if second is INFINITY:
            return first
        x_first, y_first = first
        x_second, y_second = second
        if x_first == x_second and y_first == -y_second:
            return INFINITY
        if first == second:
            # the tangent: doubling. slope = (3 x^2 + a) / (2 y)
            slope = (as_rational(3) * x_first * x_first + self.a) / (as_rational(2) * y_first)
        else:
            # the chord through two distinct points
            slope = (y_second - y_first) / (x_second - x_first)
        x_result = slope * slope - x_first - x_second
        y_result = slope * (x_first - x_result) - y_first
        return (x_result, y_result)

    def multiply(self, count, point):
        """[count] point by double and add, count any integer."""
        if count < 0:
            return self.multiply(-count, self.negate(point))
        result = INFINITY
        addend = point
        while count:
            if count & 1:
                result = self.add(result, addend)
            addend = self.add(addend, addend)
            count >>= 1
        return result


def theta_count(coefficient_z, target):
    """#{(x, y, z) in Z^3 : 2 x^2 + y^2 + coefficient_z z^2 = target}, an exact integer count."""
    total = 0
    x_bound = isqrt(target // 2)
    for x in range(-x_bound, x_bound + 1):
        after_x = target - 2 * x * x
        if after_x < 0:
            continue
        z_bound = isqrt(after_x // coefficient_z)
        for z in range(-z_bound, z_bound + 1):
            remainder = after_x - coefficient_z * z * z
            if remainder < 0:
                continue
            root = isqrt(remainder)
            if root * root == remainder:
                total += 2 if root != 0 else 1  # y = +root and y = -root, or y = 0 once
    return total


def theta_count_boxed(coefficient_z, target):
    """The same count taken with the loops nested the other way, a second route to the same integer."""
    total = 0
    y_bound = isqrt(target)
    for y in range(-y_bound, y_bound + 1):
        after_y = target - y * y
        if after_y < 0:
            continue
        z_bound = isqrt(after_y // coefficient_z)
        for z in range(-z_bound, z_bound + 1):
            remainder = after_y - coefficient_z * z * z
            if remainder < 0 or remainder % 2 != 0:
                continue
            half = remainder // 2
            root = isqrt(half)
            if root * root == half:
                total += 2 if root != 0 else 1
    return total


def tunnell(target):
    """A(n) and B(n): #{2x^2+y^2+8z^2=n} and #{2x^2+y^2+32z^2=n}, exact integer counts."""
    return theta_count(8, target), theta_count(32, target)


# the status known independently, as (is congruent, note); the run is read against the truth.
# 15 is congruent by the triangle (15/2, 4, 17/2), area 15; the earlier label of not congruent was wrong.
KNOWN = {1: (False, "Fermat"), 3: (False, "n = 3"), 5: (True, "Fibonacci"),
         7: (True, "n = 7"), 13: (True, "n = 13"), 15: (True, "legs 15/2, 4")}


def report_tunnell(out):
    """Tunnell's exact integer criterion, unconditional where the counts are unequal."""
    out.write("  Tunnell's criterion: an exact integer count, unconditional when the counts disagree\n")
    out.write("    n odd squarefree congruent => A(n) = 2 B(n), A = #{2x^2+y^2+8z^2=n}, B = #{...+32z^2=n}\n")
    checks = []
    routes_agree = True
    for n in (1, 3, 5, 7, 13, 15):
        first, second = tunnell(n)
        # second route: recount both forms with the loops nested the other way
        first_route = theta_count_boxed(8, n)
        second_route = theta_count_boxed(32, n)
        routes_agree = routes_agree and first == first_route and second == second_route
        equal = first == 2 * second
        # the unconditional reading: unequal proves not congruent; equal is consistent with congruent
        verdict = "consistent with congruent" if equal else "NOT congruent (unconditional)"
        is_congruent, note = KNOWN[n]
        # the count agrees with the known status on this sample: equal exactly when congruent
        sound = (equal == is_congruent)
        checks.append(sound)
        out.write("    n=%2d: A=%d, 2B=%d, equal=%-5s -> %-28s [known %scongruent: %s]\n"
                  % (n, first, 2 * second, str(equal), verdict,
                     "" if is_congruent else "not ", note))
    fermat = tunnell(1)[0] != 2 * tunnell(1)[1]  # A(1) != 2 B(1): 1 is not congruent
    out.write("    Fermat recovered: A(1) != 2 B(1), 1 is not congruent: %s\n" % fermat)
    out.write("    both theta counts agree across the two bounding-box routes: %s\n" % routes_agree)
    out.write("    floor: the converse (equality => congruent) is conditional on BSD; only the\n")
    out.write("    inequality direction is unconditional, and a count is proof only when it disagrees.\n\n")
    return all(checks) and fermat and routes_agree


def report_witness(out):
    """The n = 5 witness: an exact right triangle and a rational point of infinite order on C_5."""
    out.write("  the n = 5 witness: a point of infinite order on C_5, unconditional, no BSD needed\n")
    n = 5
    curve = Curve(-n * n, 0)  # C_5 : y^2 = x^3 - 25 x

    # the triangle Fibonacci found: legs 3/2 and 20/3, hypotenuse 41/6
    leg_one = Rational(3, 2)
    leg_two = Rational(20, 3)
    hypotenuse = Rational(41, 6)
    right_triangle = (leg_one * leg_one + leg_two * leg_two) == (hypotenuse * hypotenuse)
    area = leg_one * leg_two / Rational(2)
    area_is_five = area == Rational(5)

    # the base point, integral and on the curve
    base = (Rational(-4), Rational(6))
    on_curve = curve.on_curve(base)
    base_integral = base[0].is_integer() and base[1].is_integer()

    # its double is not integral; the base point is then not torsion (Nagell-Lutz) and has infinite order
    doubled = curve.add(base, base)
    double_on_curve = curve.on_curve(doubled)
    double_not_integral = not (doubled[0].is_integer() and doubled[1].is_integer())

    # the doubled x-coordinate is (hypotenuse / 2)^2, tying the triangle to the point exactly
    x_from_triangle = (hypotenuse / Rational(2)) * (hypotenuse / Rational(2))
    triangle_matches_point = doubled[0] == x_from_triangle

    # a stronger check that the base point is not torsion: no small multiple returns to O
    no_small_order = all(curve.multiply(order, base) is not INFINITY for order in range(1, 13))

    out.write("    triangle (3/2, 20/3, 41/6): right triangle %s, area %s (= 5: %s)\n"
              % (right_triangle, area, area_is_five))
    out.write("    base point %s on C_5: %s, integral: %s\n"
              % ((str(base[0]), str(base[1])), on_curve, base_integral))
    out.write("    its double %s on C_5: %s, not integral: %s\n"
              % ((str(doubled[0]), str(doubled[1])), double_on_curve, double_not_integral))
    out.write("    the doubled x equals (hypotenuse/2)^2 = %s: %s (triangle and point are one witness)\n"
              % (x_from_triangle, triangle_matches_point))
    out.write("    no multiple [k] for k=1..12 returns to O: %s (infinite order; C_5(Q) is infinite)\n"
              % no_small_order)

    # the null: a torsion point on y^2 = x^3 + 1 is integral and of finite order, certifying nothing
    torsion_curve = Curve(0, 1)
    torsion_point = (Rational(2), Rational(3))
    torsion_on_curve = torsion_curve.on_curve(torsion_point)
    sixth = torsion_curve.multiply(6, torsion_point)
    torsion_finite = sixth is INFINITY
    torsion_integral_along = all(
        (curve_point is INFINITY) or (curve_point[0].is_integer() and curve_point[1].is_integer())
        for curve_point in (torsion_curve.multiply(k, torsion_point) for k in range(1, 7)))
    out.write("    null, (2,3) on y^2=x^3+1: on curve %s, [6] = O %s, every multiple integral %s\n"
              % (torsion_on_curve, torsion_finite, torsion_integral_along))
    out.write("    (Nagell-Lutz: torsion is integral; a non-integral multiple proves infinite order)\n\n")

    return (right_triangle and area_is_five and on_curve and base_integral and double_on_curve
            and double_not_integral and triangle_matches_point and no_small_order
            and torsion_on_curve and torsion_finite and torsion_integral_along)


def report_two_routes(out):
    """n = 5 certified congruent by two independent routes: the point and the Tunnell equality."""
    out.write("  two routes to n = 5 congruent, and the boundary between exact and computed\n")
    n = 5
    curve = Curve(-n * n, 0)
    base = (Rational(-4), Rational(6))
    # route one: an infinite-order point exists (unconditional)
    by_point = not (curve.add(base, base)[0].is_integer())
    # route two: Tunnell's equality holds (its converse is BSD-conditional)
    first, second = tunnell(n)
    by_tunnell = first == 2 * second
    out.write("    route one, a point of infinite order on C_5 exists: %s (unconditional)\n" % by_point)
    out.write("    route two, Tunnell's A(5) = 2 B(5) holds: %s (converse conditional on BSD)\n" % by_tunnell)
    out.write("    the exact side is the group law and the integer count; the analytic side, L(C_n, 1),\n")
    out.write("    the real period and the regulator, is a computed real this file does not touch, the\n")
    out.write("    completeness and measurement floor of the precision document. It claims nothing about BSD.\n\n")
    return by_point and by_tunnell


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  The congruent number problem on Birch and Swinnerton-Dyer, exact, nothing claimed\n\n")
    results = [
        report_tunnell(out),
        report_witness(out),
        report_two_routes(out),
    ]
    if all(results):
        out.write("  every check lands: Tunnell's count reproduces Fermat's n = 1 and refuses n = 3, the\n")
        out.write("  n = 5 triangle and the infinite-order point are one exact witness, and both the point\n")
        out.write("  and the count certify n = 5, with the analytic side left as the stated floor.\n")
    else:
        out.write("  a check missed: refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
