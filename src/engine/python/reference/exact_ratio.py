#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# An exact rational as two native integers, compared by cross-multiply, with no float in the path.
#
#   Usage:  from reference.exact_ratio import whole, add, sub, mul, over, compare, sign, ratio_text,
#                                             to_float
#
# The measure layer produces rationals: a phase mean is a class sum over a class count, and the
# dispersion ratio is one energy over another. This carries them as an explicit (numerator,
# denominator) pair of Python integers. Those are arbitrary precision and the ratio has no bit cap.
# The C form (fixed-width limbs, 128 by default and
# any power of two from 1 to 32768 a build selects) carries the same integers up to its declared
# width. The two forms agree because both are integers and both compare the same way.
#
# NO FLOAT IN THE ARITHMETIC. Every operation here is integer add, multiply and compare. A rational a/b
# against c/d is decided by a*d against c*b, an integer comparison, never a quotient. `to_float` is the
# only place a float appears, and it is a display boundary a caller crosses to print, never a step the
# measure reads back. Nothing here rounds, and a comparison is exact whatever the magnitudes.
#
# THE PAIR IS ALWAYS REDUCED. `reduced` divides out the greatest common divisor by a hand-written
# Euclid and keeps the denominator positive. One value has one representation and tuple equality is
# value equality. Because of that, a caller can keep writing `mean[i] == (scene[i], 1)` and get the answer
# it means. No fractions, no math, no importlib: the greatest common divisor is computed here.
#
# ONE PRINTER. `ratio_text` writes a ratio to a stated number of decimal places in integers alone,
# truncated toward zero, the convention of sim_ratio_print in src/engine/sims/sim.h, whose port it is.
# A Python reading and the sim beside it therefore print the same digits for the same ratio.

# The widest scaled value sim_ratio_print holds, its 64 bit word.
_PRINT_MOST = 0xFFFFFFFFFFFFFFFF

def _gcd(first, second):
    """The greatest common divisor of two integers, by Euclid, on their magnitudes."""
    first = first if first >= 0 else -first
    second = second if second >= 0 else -second
    while second:
        first, second = second, first % second
    return first


def reduced(numerator, denominator):
    """A ratio in lowest terms with a positive denominator, as an integer pair.

    One value then has one representation. Two ratios are equal exactly when their pairs are. A zero
    denominator raises, the same error Fraction made, because a ratio over nothing is not a value.
    """
    if denominator == 0:
        raise ZeroDivisionError("exact ratio with a zero denominator")
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    divisor = _gcd(numerator, denominator)
    if divisor > 1:
        numerator //= divisor
        denominator //= divisor
    return (numerator, denominator)


def whole(integer):
    """An integer as a ratio. Its denominator is one. It needs no reduction."""
    return (integer, 1)


def add(left, right):
    """The exact sum of two ratios."""
    return reduced(left[0] * right[1] + right[0] * left[1], left[1] * right[1])


def sub(left, right):
    """The exact difference left minus right."""
    return reduced(left[0] * right[1] - right[0] * left[1], left[1] * right[1])


def mul(left, right):
    """The exact product of two ratios."""
    return reduced(left[0] * right[0], left[1] * right[1])


def over(left, right):
    """The exact quotient left divided by right. Right must not be zero."""
    return reduced(left[0] * right[1], left[1] * right[0])


def compare(left, right):
    """-1, 0 or 1 as left is below, equal to or above right, by cross-multiply.

    Both denominators are positive after `reduced`. The sign of left_num*right_den - right_num*left_den
    is the sign of the difference, an exact integer comparison with no quotient taken.
    """
    here = left[0] * right[1]
    there = right[0] * left[1]
    return (here > there) - (here < there)


def sign(value):
    """-1, 0 or 1 as the ratio is negative, zero or positive. The denominator is positive."""
    return (value[0] > 0) - (value[0] < 0)


def ratio_text(numerator, denominator, places):
    """sim_ratio_print: the ratio to `places` decimals, truncated toward zero, with the header's words."""
    if denominator == 0 or places > 18:
        return "undefined"
    negative = (numerator < 0) != (denominator < 0) and numerator != 0
    scaled = min((abs(numerator) * (10 ** places)) // abs(denominator), _PRINT_MOST)
    unit = 10 ** places
    text = ("-" if negative else "") + "%d" % (scaled // unit)
    if places > 0:
        text += ".%0*d" % (places, scaled % unit)
    return text


def to_float(value):
    """The ratio as a float, for display only. This is the only place a float enters."""
    return value[0] / value[1]
