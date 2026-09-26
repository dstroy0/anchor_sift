#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Natural constants, computed to a declared precision and never stored. A constant here is not a table of
# digits copied from somewhere. It is a computation run to whatever precision the caller asks for, and the
# check that it is right is two independent routes reaching the same digits. A stored expansion is an
# oracle, an answer from outside the sample. A natural constant is derivable from within, and here it is
# derived; matching a pasted expansion is not the test. The two routes agreeing is the test.
#
#   Usage:  from representation.constants.naturals import pi, euler_e, root_two, ln_two, golden_ratio
#           pi(1000)                       ->  the integer floor(pi * 10**1000)
#           python naturals.py --places 1000 [name ...]  ->  print the named constants to n places
#
# Every function takes the number of decimal places and returns floor(C * 10**places) as an exact Python
# integer, the constant held to n places with no fractional part discarded silently. There is no ceiling
# on n: the series and the recurrences run to whatever scale is asked, and a caller pins the constant as
# far as it wants to wait. A float never appears. A display at some fixed width is the caller's boundary,
# taken from this integer, and it is not stored here.
#
# Each public function computes both of its routes and refuses to return unless they agree at the
# requested precision. That is the positive control run on every call: a route with a bug, or a series
# stopped too early, disagrees with the other and raises instead of returning a wrong digit. The drawn
# null lives in the posit beside this file (evidence/proofs/posits/proof_constants_two_routes.py), which
# feeds a deliberately wrong series and shows the disagreement caught.

import sys

# Extra digits computed and then dropped, keeping the last returned digit clear of a truncation artifact
# of the series. The routes are accurate to the full working scale; the guard lets the two agree exactly
# after the drop instead of differing in the final place.
GUARD = 20


def _integer_sqrt(value):
    """floor(sqrt(value)) for a non-negative integer, by integer Newton iteration. No float, no library."""
    if value < 0:
        raise ValueError("integer square root of a negative number")
    if value < 2:
        return value
    guess = 1 << ((value.bit_length() + 1) // 2)
    while True:
        stepped = (guess + value // guess) // 2
        if stepped >= guess:
            return guess
        guess = stepped


def _arctan_inverse(denominator, scale):
    """floor(scale * arctan(1 / denominator)) by the alternating series, in integers.

    arctan(1/x) = 1/x - 1/(3 x^3) + 1/(5 x^5) - ..., every term an exact integer division of `scale`. The
    walk stops when the running power floors to zero, the full precision `scale` can carry.
    """
    total = 0
    power = scale // denominator          # scale / denominator^1
    squared = denominator * denominator
    step = 0
    while power != 0:
        term = power // (2 * step + 1)
        total += term if (step % 2 == 0) else -term
        power //= squared                 # scale / denominator^(2 step + 3)
        step += 1
    return total


# ---- pi: two Machin-like arctangent identities ----

def _pi_machin(scale):
    """pi by Machin's identity, pi = 16 arctan(1/5) - 4 arctan(1/239)."""
    return 16 * _arctan_inverse(5, scale) - 4 * _arctan_inverse(239, scale)


def _pi_euler(scale):
    """pi by Euler's identity, pi = 4 (arctan(1/2) + arctan(1/3))."""
    return 4 * (_arctan_inverse(2, scale) + _arctan_inverse(3, scale))


# ---- e: the Taylor series against the continued fraction ----

def _e_taylor(scale):
    """e by its Taylor series, sum over k of 1/k!, each term an exact integer."""
    total = 0
    term = scale
    factor = 0
    while term != 0:
        total += term
        factor += 1
        term //= factor
    return total


def _e_continued_fraction(scale):
    """e by the convergents of its continued fraction [2; 1, 2, 1, 1, 4, 1, 1, 6, ...].

    The partial quotient at index i is 2*(i+1)/3 when i is 2 mod 3 and 1 otherwise. The convergents run
    until the denominator passes the working scale, the point past which the convergent's error is below
    one unit at that scale and floor(e * scale) is exact.
    """
    def quotient(index):
        if index == 0:
            return 2
        return 2 * ((index + 1) // 3) if index % 3 == 2 else 1

    numerator_prev, numerator = 1, quotient(0)
    denominator_prev, denominator = 0, 1
    index = 1
    while denominator <= scale:
        quo = quotient(index)
        numerator_prev, numerator = numerator, quo * numerator + numerator_prev
        denominator_prev, denominator = denominator, quo * denominator + denominator_prev
        index += 1
    return (numerator * scale) // denominator


# ---- root two: integer Newton against the continued fraction [1; 2, 2, 2, ...] ----

def _root_two_newton(scale):
    """sqrt(2) held to `scale` as floor(sqrt(2) * scale) = floor(sqrt(2 * scale^2))."""
    return _integer_sqrt(2 * scale * scale)


def _root_two_continued_fraction(scale):
    """sqrt(2) by the convergents of [1; 2, 2, 2, ...], run until the denominator passes the scale."""
    numerator_prev, numerator = 1, 1      # a_0 = 1
    denominator_prev, denominator = 0, 1
    while denominator <= scale:
        numerator_prev, numerator = numerator, 2 * numerator + numerator_prev
        denominator_prev, denominator = denominator, 2 * denominator + denominator_prev
    return (numerator * scale) // denominator


# ---- ln two: the 1/(k 2^k) series against 2 artanh(1/3) ----

def _ln_two_reciprocal_powers(scale):
    """ln 2 by sum over k>=1 of 1/(k 2^k), each term an exact integer division of `scale`."""
    total = 0
    step = 1
    power_two = 2
    while True:
        term = scale // (step * power_two)
        if term == 0:
            break
        total += term
        step += 1
        power_two *= 2
    return total


def _ln_two_artanh(scale):
    """ln 2 = 2 artanh(1/3) = 2 sum over k>=0 of 1/((2k+1) 3^(2k+1))."""
    total = 0
    power = scale // 3                     # scale / 3^1
    nine = 9
    step = 0
    while power != 0:
        total += power // (2 * step + 1)
        power //= nine
        step += 1
    return 2 * total


# ---- golden ratio: (1 + sqrt 5)/2 against the ratio of consecutive Fibonacci numbers ----

def _golden_from_root(scale):
    """phi = (1 + sqrt 5)/2, held to `scale` through the integer square root of 5."""
    return (scale + _integer_sqrt(5 * scale * scale)) // 2


def _golden_from_fibonacci(scale):
    """phi as the ratio of consecutive Fibonacci numbers, run until the smaller passes the scale."""
    smaller, larger = 1, 1
    while smaller <= scale:
        smaller, larger = larger, smaller + larger
    return (larger * scale) // smaller


def _agree(route_one, route_two, places, name):
    """Compute both routes at places+GUARD, drop the guard, and return the value only if they agree."""
    if places < 1:
        raise ValueError("places must be at least 1")
    scale = 10 ** (places + GUARD)
    drop = 10 ** GUARD
    value_one = route_one(scale) // drop
    value_two = route_two(scale) // drop
    if value_one != value_two:
        raise ValueError("%s: the two routes disagree at %d places" % (name, places))
    return value_one


def pi(places):
    """floor(pi * 10**places), by Machin's and Euler's identities agreeing."""
    return _agree(_pi_machin, _pi_euler, places, "pi")


def euler_e(places):
    """floor(e * 10**places), by the Taylor series and the continued fraction agreeing."""
    return _agree(_e_taylor, _e_continued_fraction, places, "e")


def root_two(places):
    """floor(sqrt(2) * 10**places), by integer Newton and the continued fraction agreeing."""
    return _agree(_root_two_newton, _root_two_continued_fraction, places, "root_two")


def ln_two(places):
    """floor(ln(2) * 10**places), by two independent series agreeing."""
    return _agree(_ln_two_reciprocal_powers, _ln_two_artanh, places, "ln_two")


def golden_ratio(places):
    """floor(phi * 10**places), by the square-root form and the Fibonacci ratio agreeing."""
    return _agree(_golden_from_root, _golden_from_fibonacci, places, "golden_ratio")


def _decimal_string(value, places):
    """Render floor(C * 10**places) as its decimal string, one integer part and n places.

    A display convenience for a caller printing a constant. It does no arithmetic on the value and reads
    nothing back in. It marks the display boundary and makes no second copy of the number.
    """
    text = str(value).rjust(places + 1, "0")
    return "%s.%s" % (text[:-places], text[-places:])


CONSTANTS = {
    "pi": pi,
    "e": euler_e,
    "root_two": root_two,
    "ln_two": ln_two,
    "golden_ratio": golden_ratio,
}


def main(argv):
    import io
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    places = 60
    chosen = []
    args = list(argv)
    while args:
        token = args.pop(0)
        if token in ("--places", "-p"):
            if not args:
                out.write("  --places needs a number\n")
                out.flush()
                return 2
            places = int(args.pop(0))
        elif token.startswith("--places="):
            places = int(token.split("=", 1)[1])
        elif token in CONSTANTS:
            chosen.append(token)
        else:
            out.write("  unknown argument %r; constants are %s\n" % (token, ", ".join(CONSTANTS)))
            out.flush()
            return 2
    if places < 1:
        out.write("  places must be at least 1\n")
        out.flush()
        return 2
    names = chosen if chosen else ["pi", "e", "root_two", "ln_two", "golden_ratio"]
    out.write("  natural constants to %d places, each by two agreeing routes, nothing stored\n\n" % places)
    for name in names:
        value = CONSTANTS[name](places)
        out.write("  %-14s %s\n" % (name, _decimal_string(value, places)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
