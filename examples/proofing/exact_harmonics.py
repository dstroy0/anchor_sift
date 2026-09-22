"""Spherical harmonics in fixed point, so the reading has no floor but the one it is given.

The boundary readings in this tree were computed in float64 and reported a residual near 1e-16 under
rotations that must leave them unchanged. That number was called the format's floor, which was true
and also an excuse: the format was chosen. Nothing in a spherical harmonic requires a float.

    cosine and sine      Taylor series with argument reduction, exact in fixed point
    square root          Newton, which the engine already carries, multiplies and shifts only
    Legendre             a three-term recurrence, polynomial, so exact with no series at all

So the whole evaluation is integer arithmetic at whatever width is asked for, and the residual under
a rotation that changes nothing drops with the width instead of stopping at 1e-16. That is the test
this module exists to make possible: a floor that MOVES when the width moves belongs to the format,
and one that does not belongs to the object.

Every value here is an integer scaled by two to the `places`. Nothing is a float at any point.

    python examples/proofing/exact_harmonics.py --check
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import digit_engine


def pi_at(places):
    """Pi scaled by 2^places, from the engine's own series."""
    digits = int(places * 0.302) + 20
    whole = digit_engine.chudnovsky(digits)
    return (whole << places) // (10 ** digits)


def cosine(angle, places):
    """cos of a fixed-point angle, by Taylor after reduction into [-pi, pi].

    The series converges fast once the argument is reduced, and every term is an exact integer
    division of the one before it, so nothing rounds except the single truncation each term makes.
    """
    scale = 1 << places
    two_pi = 2 * pi_at(places)
    angle = angle % two_pi
    if angle > two_pi // 2:
        angle -= two_pi

    term = scale
    total = scale
    square = (angle * angle) >> places
    step = 1
    while term != 0:
        term = (term * square) >> places
        term = term // ((2 * step - 1) * (2 * step))
        total = total - term if (step % 2 == 1) else total + term
        step += 1
        if step > 200:
            break
    return total


def sine(angle, places):
    """sin, as cos of the angle less a quarter turn, so only one series is carried."""
    quarter = pi_at(places) // 2
    return cosine(angle - quarter, places)


def legendre(degree, order, cos_theta, places):
    """The associated Legendre value P_l^m(cos theta), by the standard recurrence.

    Polynomial in cos theta and in the sine, so with the sine supplied this is exact fixed point
    arithmetic with no series anywhere. The recurrence is the textbook one and is stable upward in
    degree, which is the direction it is used.
    """
    scale = 1 << places
    # sin theta from the identity, by Newton's root in the engine.
    square = (cos_theta * cos_theta) >> places
    sin_square = scale - square
    sin_theta = digit_engine.root_scaled(sin_square, 0) if sin_square > 0 else 0
    if sin_square > 0:
        # root_scaled works in decimal places; do the binary root directly instead.
        sin_theta = binary_root(sin_square, places)
    else:
        sin_theta = 0

    # P_m^m = (-1)^m (2m-1)!! (sin theta)^m
    value = scale
    for step in range(1, order + 1):
        value = -(value * ((2 * step - 1) * sin_theta)) >> places
    if degree == order:
        return value

    # P_(m+1)^m = cos theta (2m+1) P_m^m
    previous = value
    current = ((2 * order + 1) * ((cos_theta * value) >> places))
    if degree == order + 1:
        return current

    for level in range(order + 2, degree + 1):
        nxt = (((2 * level - 1) * ((cos_theta * current) >> places))
               - ((level + order - 1) * previous)) // (level - order)
        previous, current = current, nxt
    return current


def binary_root(value, places):
    """Square root of a fixed-point value, by Newton, in the same fixed point. No float, no divide
    beyond the exact halving the iteration needs."""
    if value <= 0:
        return 0
    scale = 1 << places
    guess = 1 << ((value.bit_length() + places) // 2)
    for _ in range(200):
        if guess == 0:
            return 0
        nxt = (guess + ((value << places) // guess)) >> 1
        if nxt == guess or nxt == guess - 1:
            return nxt
        guess = nxt
    return guess


def _check():
    print("=" * 74)
    print("  GATE: the fixed-point evaluation against values that are known exactly")
    print("=" * 74)
    print()
    failures = 0
    for places in (64, 128, 256):
        scale = 1 << places
        pi = pi_at(places)
        # cos(0) = 1, cos(pi) = -1, cos(pi/2) = 0, sin(pi/2) = 1. All exact, so the error is the
        # arithmetic's and nothing else.
        checks = [
            ("cos 0", cosine(0, places), scale),
            ("cos pi", cosine(pi, places), -scale),
            ("cos pi/2", cosine(pi // 2, places), 0),
            ("sin pi/2", sine(pi // 2, places), scale),
        ]
        worst = 0
        for name, got, want in checks:
            error = abs(got - want)
            worst = max(worst, error)
        # The error should fall as the width rises. That is the whole claim.
        relative_bits = places - worst.bit_length() if worst else places
        print("    %4d bits   worst absolute error 2^%-4d   accurate to %d bits"
              % (places, worst.bit_length() if worst else 0, relative_bits))
        if relative_bits < places - 12:
            failures += 1

    print()
    if failures:
        print("    FAILED: the error does not fall with the width, so something is not exact.")
        return 1
    print("    The error falls with the width, which is what fixed point is for and what a float")
    print("    cannot do. A reading built on this has the floor it is given, not one at 1e-16.")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Fixed-point spherical harmonic pieces.")
    parser.add_argument("--check", action="store_true")
    given = parser.parse_args()
    if given.check:
        return _check()
    print(__doc__)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
