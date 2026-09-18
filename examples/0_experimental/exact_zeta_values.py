#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-014
#
# The Riemann zeta function at the even integers, computed exactly: zeta(2k) = c_k * pi^(2k) with c_k
# an exact rational from the Bernoulli numbers, cross-checked by Euler's convolution identity, which is
# exact and free of pi.
#
#   Usage:  python examples/0_experimental/exact_zeta_values.py
#
# This reads no corpus. It sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. It is the first entry of an analytic-number-theory workbook, and it claims nothing about any
# open problem. The Riemann hypothesis concerns the ZEROS of zeta(s) in the critical strip; this file
# touches none of them. It computes the VALUES at the even integers, which have a closed form Euler
# found, and it uses the engine's exact arithmetic to carry them with no rounding and to check them by a
# second route that does not go through pi at all.
#
# Two routes. The values come from zeta(2k) = |B_{2k}| (2 pi)^{2k} / (2 (2k)!), the Bernoulli numbers
# computed as exact rationals. The check is Euler's identity, sum_{j=1}^{k-1} zeta(2j) zeta(2k-2j) =
# (k + 1/2) zeta(2k): every term carries pi^{2k}. The factor cancels and the identity becomes an
# exact rational statement about the c_k, derived a different way than the Bernoulli formula. The two
# agreeing is the positive control. Drawn null: a wrong coefficient, zeta(4) = pi^4/80 in place of /90,
# fails the identity. No bounding: the coefficients are exact rationals and the high-precision values
# are exact scaled integers built on pi computed two ways.

import io
import sys
from fractions import Fraction
from math import comb, factorial

REPORT_DIGITS = 80
GUARD_DIGITS = 20
WORK_DIGITS = REPORT_DIGITS + GUARD_DIGITS
SCALE = 10 ** WORK_DIGITS
HIGHEST = 8  # compute zeta(2), zeta(4), ..., zeta(2*HIGHEST)


def bernoulli_numbers(upto):
    """The Bernoulli numbers B_0..B_upto as exact rationals, by the standard recurrence."""
    numbers = [Fraction(0)] * (upto + 1)
    numbers[0] = Fraction(1)
    for index in range(1, upto + 1):
        total = sum(Fraction(comb(index + 1, j)) * numbers[j] for j in range(index))
        numbers[index] = -total / (index + 1)
    return numbers


def zeta_coefficient(twice_k, bernoulli):
    """The exact rational c with zeta(twice_k) = c * pi^(twice_k), for even twice_k."""
    return abs(bernoulli[twice_k]) * Fraction(2 ** (twice_k - 1), factorial(twice_k))


def arctan_reciprocal(whole):
    """arctan(1/whole) at WORK_DIGITS places."""
    total = 0
    sign = 1
    power = whole
    whole_squared = whole * whole
    index = 0
    while True:
        term = SCALE // ((2 * index + 1) * power)
        if term == 0:
            break
        total += sign * term
        sign = -sign
        index += 1
        power *= whole_squared
    return total


def pi_machin():
    """pi at WORK_DIGITS places by Machin's formula."""
    return 16 * arctan_reciprocal(5) - 4 * arctan_reciprocal(239)


def pi_euler():
    """pi at WORK_DIGITS places by Euler's formula, the second route."""
    return 4 * (arctan_reciprocal(2) + arctan_reciprocal(3))


def scaled_power(base_scaled, exponent):
    """base_scaled raised to `exponent`, kept at WORK_DIGITS places."""
    result = SCALE
    for _ in range(exponent):
        result = (result * base_scaled) // SCALE
    return result


def convolution_identity_holds(coefficients):
    """Euler's identity as an exact rational check on the c_k: sum c_j c_{k-j} = (k + 1/2) c_k."""
    for twice_k in range(4, 2 * HIGHEST + 1, 2):
        k = twice_k // 2
        left = sum(coefficients[2 * j] * coefficients[twice_k - 2 * j] for j in range(1, k))
        right = (Fraction(k) + Fraction(1, 2)) * coefficients[twice_k]
        if left != right:
            return False
    return True


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  zeta at the even integers, exact, and Euler's identity as a pi-free check\n")
    out.write("  this touches the VALUES, not the zeros; it claims nothing about the Riemann hypothesis\n\n")

    bernoulli = bernoulli_numbers(2 * HIGHEST)
    coefficients = {twice_k: zeta_coefficient(twice_k, bernoulli)
                    for twice_k in range(2, 2 * HIGHEST + 1, 2)}

    machin = pi_machin()
    euler = pi_euler()
    pi_agrees = abs(machin - euler) < 10 ** GUARD_DIGITS
    out.write("  pi by Machin and Euler agree to %d places: %s\n\n" % (REPORT_DIGITS, pi_agrees))

    out.write("  %-9s %-16s %s\n" % ("s", "coefficient c", "zeta(s), first digits"))
    pi_powers = {2: (machin * machin) // SCALE}
    for twice_k in range(2, 2 * HIGHEST + 1, 2):
        pi_powers[twice_k] = scaled_power(machin, twice_k)
        value = (coefficients[twice_k].numerator * pi_powers[twice_k]) // coefficients[twice_k].denominator
        digits = str(value)[:REPORT_DIGITS // 4]  # a readable prefix of the scaled value
        out.write("  zeta(%-3d) %-16s %s...\n"
                  % (twice_k, "%d/%d" % (coefficients[twice_k].numerator, coefficients[twice_k].denominator),
                     "1." + str(value % SCALE).zfill(WORK_DIGITS)[:18]))

    identity = convolution_identity_holds(coefficients)
    out.write("\n  Euler's convolution identity holds on the exact coefficients: %s\n" % identity)

    # the null: a wrong coefficient for zeta(4) breaks the identity
    wrong = dict(coefficients)
    wrong[4] = Fraction(1, 80)  # the true value is 1/90
    wrong_identity = convolution_identity_holds(wrong)
    out.write("  with zeta(4) = pi^4/80 in place of /90, the identity holds: %s (refused)\n" % wrong_identity)
    out.flush()

    return 0 if (pi_agrees and identity and not wrong_identity) else 1


if __name__ == "__main__":
    raise SystemExit(main())
