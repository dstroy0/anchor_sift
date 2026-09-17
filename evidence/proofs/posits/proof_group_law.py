#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-011
#
# The rational points on an elliptic curve form an abelian group under the chord-tangent law, proven by
# construction in exact rational arithmetic: closure, identity, inverse, commutativity and associativity
# all hold on a curve carrying both torsion and an infinite-order point, and a law with one sign wrong
# fails associativity. This is the group structure the Birch and Swinnerton-Dyer conjecture is about, the
# exact algebraic side that the congruent-number reading rests on.
#
#   Usage:  python evidence/proofs/posits/proof_group_law.py
#
# It imports the curve and the exact rational from examples/0_experimental/exact_congruent_number.py so
# one representation carries both files, and adds no arithmetic of its own. Python integers are the
# bignum and a rational is a reduced (numerator, denominator) pair of native integers. No float, no
# fraction library, no math library.
#
# The axioms, each on the curve y^2 = x^3 - 25 x (torsion Z/2 x Z/2 at (0,0), (5,0), (-5,0), and the
# infinite-order point (-4, 6)) and the curve y^2 = x^3 + 1 (torsion Z/6 at (2, +-3), (0, +-1), (-1, 0)):
#   closure          P + Q lies on the curve for all pairs tried.
#   identity         P + O = O + P = P, O the point at infinity.
#   inverse          P + (-P) = O, with -P = (x, -y).
#   commutativity    P + Q = Q + P.
#   associativity    (P + Q) + R = P + (Q + R), the one axiom that is not obvious and the one a wrong law
#                    breaks. The classical proof is the Cayley-Bacharach theorem, equivalently
#                    Riemann-Roch on the curve; here it is verified exactly on a sample of triples.
#   Z-module         [m]([n]P) = [mn]P and [m]P + [n]P = [m+n]P, and [-1]P = -P.
#   Nagell-Lutz      a torsion point has integer coordinates. Verified on the two torsion groups, and its
#                    converse is refused: (-4, 6) is integral yet has infinite order, its double already
#                    non-integral, which makes integrality necessary and not sufficient.
#
# Positive control: every axiom holds exactly on a curve with both torsion and an infinite point. Two
# routes: associativity by the two groupings, and [6]P computed three ways, [2]([3]P), [3]([2]P) and
# [5]P + P. Drawn null: a law with the doubling and chord formula sharing one wrong sign fails
# associativity on a triple the correct law passes, and the false claim that the infinite-order point is
# torsion is refused by [k]P never returning to O. Floor: the axioms are theorems and this verifies the
# implementation realizes them on a finite sample of points, it does not reprove associativity in general.
#
# Prior art, named with respect. The group structure of the rational points is Poincare's (1901), on the
# chord-tangent construction of Diophantus and Fermat; finite generation is Mordell's (1922). The
# associativity is the Cayley-Bacharach theorem, equivalently Riemann-Roch on the genus-one curve. The
# integrality of torsion is Nagell's and Lutz's. Cited from memory of the literature, unread here; the
# file verifies only the exact rational identities. It adds no new mathematics.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "examples", "0_experimental"))

import exact_congruent_number as cn  # noqa: E402

Rational = cn.Rational
Curve = cn.Curve
INFINITY = cn.INFINITY


def point(x, y):
    return (Rational(x), Rational(y))


def broken_add(curve, first, second):
    """A chord-tangent law with one sign wrong: x_result = slope^2 - x_first + x_second. Not a group."""
    if first is INFINITY:
        return second
    if second is INFINITY:
        return first
    x_first, y_first = first
    x_second, y_second = second
    if x_first == x_second and y_first == -y_second:
        return INFINITY
    if first == second:
        slope = (Rational(3) * x_first * x_first + curve.a) / (Rational(2) * y_first)
    else:
        slope = (y_second - y_first) / (x_second - x_first)
    x_result = slope * slope - x_first + x_second           # the wrong sign on x_second
    y_result = slope * (x_first - x_result) - y_first
    return (x_result, y_result)


def prove_axioms(out):
    """Closure, identity, inverse, commutativity and associativity, exact on two curves."""
    out.write("  the group axioms: closure, identity, inverse, commutativity, associativity, exact\n")
    congruent = Curve(-25, 0)
    points = [point(-4, 6), point(0, 0), point(5, 0), point(-5, 0),
              congruent.add(point(-4, 6), point(-4, 6))]

    closure = all(congruent.on_curve(congruent.add(one, other)) for one in points for other in points)
    identity = all(congruent.add(one, INFINITY) == one and congruent.add(INFINITY, one) == one
                   for one in points)
    inverse = all(congruent.add(one, congruent.negate(one)) is INFINITY for one in points)
    commutativity = all(congruent.add(one, other) == congruent.add(other, one)
                        for one in points for other in points)
    associativity = all(
        congruent.add(congruent.add(one, other), third) == congruent.add(one, congruent.add(other, third))
        for one in points for other in points for third in points)

    # a second curve with cyclic torsion, keeping the axioms off any one group shape alone
    torsion_curve = Curve(0, 1)
    torsion_points = [point(2, 3), point(0, 1), point(-1, 0), point(2, -3), point(0, -1)]
    associativity_two = all(
        torsion_curve.add(torsion_curve.add(one, other), third)
        == torsion_curve.add(one, torsion_curve.add(other, third))
        for one in torsion_points for other in torsion_points for third in torsion_points)

    out.write("    on y^2 = x^3 - 25 x: closure %s, identity %s, inverse %s, commutative %s\n"
              % (closure, identity, inverse, commutativity))
    out.write("    associativity holds on every triple, y^2=x^3-25x: %s ; y^2=x^3+1: %s\n"
              % (associativity, associativity_two))
    return closure and identity and inverse and commutativity and associativity and associativity_two


def prove_module(out):
    """[m]([n]P) = [mn]P, [m]P + [n]P = [m+n]P, and [6]P three ways."""
    out.write("  the Z-module laws: [m][n]P = [mn]P, [m]P + [n]P = [m+n]P, and [6]P by three routes\n")
    curve = Curve(-25, 0)
    base = point(-4, 6)

    nested = all(curve.multiply(m, curve.multiply(n, base)) == curve.multiply(m * n, base)
                 for m in range(0, 4) for n in range(0, 4))
    additive = all(curve.add(curve.multiply(m, base), curve.multiply(n, base)) == curve.multiply(m + n, base)
                   for m in range(0, 5) for n in range(0, 5))
    negation = curve.multiply(-1, base) == curve.negate(base)

    # [6]P three ways: [2]([3]P), [3]([2]P), and [5]P + P
    route_one = curve.multiply(2, curve.multiply(3, base))
    route_two = curve.multiply(3, curve.multiply(2, base))
    route_three = curve.add(curve.multiply(5, base), base)
    three_routes = route_one == route_two == route_three

    out.write("    [m][n]P = [mn]P for m,n in 0..3: %s\n" % nested)
    out.write("    [m]P + [n]P = [m+n]P for m,n in 0..4: %s\n" % additive)
    out.write("    [-1]P = -P: %s ; [6]P by [2][3]P, [3][2]P, [5]P+P all agree: %s\n"
              % (negation, three_routes))
    return nested and additive and negation and three_routes


def order_of(curve, base, cap):
    """The least positive k with [k]base = O, up to cap, or None if none is found."""
    running = INFINITY
    for k in range(1, cap + 1):
        running = curve.add(running, base)
        if running is INFINITY:
            return k
    return None


def prove_nagell_lutz(out):
    """Torsion points have integer coordinates; the converse is refused by an integral infinite point."""
    out.write("  Nagell-Lutz: torsion is integral, and integrality alone does not prove torsion\n")
    torsion_curve = Curve(0, 1)
    base = point(2, 3)
    order = order_of(torsion_curve, base, 12)
    torsion_integral = True
    running = INFINITY
    for _ in range(order or 1):
        running = torsion_curve.add(running, base)
        if running is not INFINITY:
            torsion_integral = torsion_integral and running[0].is_integer() and running[1].is_integer()
    finite_order = order == 6

    # the converse refused: (-4, 6) is integral yet infinite order, its double already non-integral
    congruent = Curve(-25, 0)
    infinite_point = point(-4, 6)
    integral_base = infinite_point[0].is_integer() and infinite_point[1].is_integer()
    doubled = congruent.add(infinite_point, infinite_point)
    double_non_integral = not (doubled[0].is_integer() and doubled[1].is_integer())
    no_finite_order = order_of(congruent, infinite_point, 40) is None

    out.write("    (2,3) on y^2=x^3+1 has order %s, every multiple integral: %s\n" % (order, torsion_integral))
    out.write("    the torsion order is 6: %s\n" % finite_order)
    out.write("    (-4,6) integral: %s, its double non-integral: %s, no order up to 40: %s (infinite)\n"
              % (integral_base, double_non_integral, no_finite_order))
    out.write("    so integrality is necessary for torsion and not sufficient (the converse is refused)\n")
    return torsion_integral and finite_order and integral_base and double_non_integral and no_finite_order


def prove_broken_law_fails(out):
    """A law with one wrong sign is not associative: the drawn null."""
    out.write("  the drawn null: a chord-tangent law with one wrong sign fails associativity\n")
    curve = Curve(-25, 0)
    one, other, third = point(-4, 6), point(0, 0), point(5, 0)

    correct = curve.add(curve.add(one, other), third) == curve.add(one, curve.add(other, third))

    left = broken_add(curve, broken_add(curve, one, other), third)
    right = broken_add(curve, one, broken_add(curve, other, third))
    broken_associative = left == right
    # the broken law also leaves the curve. The wrong sign is on x_second, and the pair needs a
    # nonzero second x for it to bite; (-4,6) + (5,0) is such a pair, where (-4,6) + (0,0) is not.
    broken_leaves_curve = not curve.on_curve(broken_add(curve, one, third))

    out.write("    the correct law is associative on this triple: %s\n" % correct)
    out.write("    the wrong-sign law is associative on this triple: %s (refused)\n" % broken_associative)
    out.write("    the wrong-sign sum lands off the curve: %s\n" % broken_leaves_curve)
    return correct and (not broken_associative) and broken_leaves_curve


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  PROOF: the rational points of an elliptic curve are an abelian group, exact\n\n")
    results = [
        prove_axioms(out),
        prove_module(out),
        prove_nagell_lutz(out),
        prove_broken_law_fails(out),
    ]
    out.write("\n")
    if all(results):
        out.write("  all four hold: the chord-tangent law is an abelian group with the Z-module structure,\n")
        out.write("  torsion is integral, and a law with one wrong sign fails associativity. This is the exact\n")
        out.write("  algebraic side of Birch and Swinnerton-Dyer, and it claims nothing about the conjecture.\n")
    else:
        out.write("  a part missed its forced outcome: refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
