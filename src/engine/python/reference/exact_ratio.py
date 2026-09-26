#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# An exact rational as two native integers, compared by cross-multiply, with no float in the path.
#
#   Usage:  from reference.exact_ratio import whole, add, sub, mul, over, compare, sign, to_float
#
# The measure layer produces rationals: a phase mean is a class sum over a class count, and the
# dispersion ratio is one energy over another. fractions.Fraction held them until now. This carries
# the same values as an explicit (numerator, denominator) pair of Python integers. Those are
# arbitrary precision and the ratio has no bit cap. The C form (fixed-width limbs, 128 by default and
# any power of two from 1 to 32768 a build selects) carries the same integers up to its declared
# width. The two forms agree because both are integers and both compare the same way.
#
# NO FLOAT IN THE ARITHMETIC. Every operation here is integer add, multiply and compare. A rational a/b
# against c/d is decided by a*d against c*b, an integer comparison, never a quotient. `to_float` is the
# one place a float appears, and it is a display boundary a caller crosses to print, never a step the
# measure reads back. Nothing here rounds, and a comparison is exact whatever the magnitudes.
#
# THE PAIR IS ALWAYS REDUCED. `reduced` divides out the greatest common divisor by a hand-written
# Euclid and keeps the denominator positive. One value has one representation and tuple equality is
# value equality. That is what lets a caller keep writing `mean[i] == (scene[i], 1)` and get the answer
# it means. No fractions, no math, no importlib: the greatest common divisor is computed here.

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
    denominator raises, the same refusal Fraction made, because a ratio over nothing is not a value.
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


def to_float(value):
    """The ratio as a float, for display only. This is the one place a float enters."""
    return value[0] / value[1]
