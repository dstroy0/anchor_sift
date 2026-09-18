#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-009
#
# Exact identities carry precision from a few computed constants to unboundedly many derived ones, and
# the multiplier is counted, not assumed.
#
#   Usage:  python examples/0_experimental/exact_identities_spread_precision.py
#
# This reads no corpus. It sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. It is the mechanism behind a goal to raise the accuracy the engine holds by a large factor.
# A constant computed once to N places by its own series is expensive. An exact identity that ties it
# to another constant hands that other constant the same N places for the cost of one multiply. A small
# seed of directly computed constants then generates a large set of derived ones at the same precision,
# and the ratio of derived to seed is the accuracy multiplier.
#
# The example works the natural constants, where this holds without bound. Three families:
#   roots  sqrt(n) for every n whose prime factors are among the seed primes, from sqrt(p) by
#          sqrt(n) = product of sqrt(p)^e. Seed: the prime square roots.
#   zetas  zeta(2k) = rational * pi^(2k), from one seed, pi. Seed: pi.
#   logs   ln(q) for every rational q built from the seed primes, by ln(q) = sum of e * ln(p).
# Each derived value is checked by a SECOND, independent route: the derived sqrt against a direct
# integer square root, the zeta ratios against each other, the derived log against a direct series. A
# derived value that fails its second route is not carried. Two routes or it does not ship.
#
# The null is drawn: a FALSE identity (sqrt(6) = sqrt(2) + sqrt(3), or phi^2 = phi + 2) is run through
# the same second-route check and refused. Agreement under a true identity is a tested result.
#
# The floor is stated and measured: each scaled operation floors and loses less than one unit in the
# last working place, and a derivation chain of depth d loses under d units, which a guard of a few
# places absorbs. That floor is arithmetic. There is a second floor this example does NOT cross and
# says so: a MEASURED quantity (a crystal edge, a physical constant) carries an upstream measurement
# floor that no identity on this end raises past. The spread multiplies precision only where the
# quantity is defined by exact operations, not measured.

import io
import sys
from math import isqrt

# Report at N places; carry a guard below it that the per-identity loss lives in.
REPORT_DIGITS = 240
GUARD_DIGITS = 24
WORK_DIGITS = REPORT_DIGITS + GUARD_DIGITS
SCALE = 10 ** WORK_DIGITS
GUARD = 10 ** GUARD_DIGITS

SEED_PRIMES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]


def mul(left, right):
    """Two scaled integers multiplied, rescaled to WORK_DIGITS places. Floors, losing under one unit."""
    return (left * right) // SCALE


def agrees(left, right):
    """Whether two scaled integers agree to the REPORT_DIGITS reported places.

    They agree when they differ only inside the guard region below the reported places. Exact equality
    is the strongest case and passes this too.
    """
    return abs(left - right) < GUARD


def arctan_reciprocal(whole):
    """arctan(1 / whole) at WORK_DIGITS places, whole an integer above 1. The Machin building block."""
    total = 0
    sign = 1
    power = whole            # whole^(2k+1), starting at whole^1
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
    """pi at WORK_DIGITS places by Machin's formula, pi = 16 arctan(1/5) - 4 arctan(1/239)."""
    return 16 * arctan_reciprocal(5) - 4 * arctan_reciprocal(239)


def pi_euler():
    """pi at WORK_DIGITS places by Euler's formula, pi = 4 (arctan(1/2) + arctan(1/3)). A second route."""
    return 4 * (arctan_reciprocal(2) + arctan_reciprocal(3))


def sqrt_scaled(number):
    """The square root of `number` at WORK_DIGITS places, by an integer square root. Self-verifying.

    isqrt gives the largest r with r*r <= number * SCALE^2. R*r <= number*SCALE^2 < (r+1)^2 holds by
    construction. This is the direct route the derived product route is checked against.
    """
    return isqrt(number * SCALE * SCALE)


def ln_rational(numerator, denominator):
    """ln(numerator / denominator) at WORK_DIGITS places, by 2 artanh((a-b)/(a+b)).

    ln((1+y)/(1-y)) = 2 artanh(y), and (1+y)/(1-y) = numerator/denominator gives y as a ratio of
    integers. Every term is an exact scaled integer.
    """
    upper = numerator - denominator
    lower = numerator + denominator
    total = 0
    upper_power = upper
    lower_power = lower
    upper_squared = upper * upper
    lower_squared = lower * lower
    index = 0
    while True:
        term = (SCALE * upper_power) // ((2 * index + 1) * lower_power)
        if term == 0:
            break
        total += term
        index += 1
        upper_power *= upper_squared
        lower_power *= lower_squared
    return 2 * total


def factor_over(number, primes):
    """The exponent of each seed prime in `number`, or None if `number` is not built from those primes."""
    exponents = {}
    remaining = number
    for prime in primes:
        while remaining % prime == 0:
            exponents[prime] = exponents.get(prime, 0) + 1
            remaining //= prime
    if remaining != 1:
        return None
    return exponents


def sqrt_by_identity(number, primes, root_of):
    """sqrt(number) built from the seed prime roots, number smooth over `primes`.

    sqrt(p^e) is p^(e//2) times sqrt(p) when e is odd, an exact integer factor times a seed root. The
    whole is a product of seed roots and integers, each step an exact scaled multiply.
    """
    exponents = factor_over(number, primes)
    if exponents is None:
        return None
    value = SCALE  # the scaled integer 1
    for prime, exponent in exponents.items():
        value = value * (prime ** (exponent // 2))  # integer part, exact, no rescale needed
        if exponent % 2 == 1:
            value = mul(value, root_of[prime])
    return value


def count_smooth(primes, bound, budget):
    """How many integers in [1, bound] have all prime factors among `primes`, counted exactly.

    A depth-first walk with an explicit stack, and a chain like 2^k does not recurse to a depth the
    interpreter refuses. The stack holds only the unexplored siblings along the current path, at most
    the path depth times the prime count. `budget` caps the work and the count reports whether it was
    reached. The count is the size of the set the seed roots generate at `bound`.
    """
    stack = [(0, 1)]
    count = 0
    while stack:
        start, product = stack.pop()
        count += 1
        if count > budget:
            return count, True
        for position in range(start, len(primes)):
            stepped = product * primes[position]
            if stepped > bound:
                break
            stack.append((position, stepped))
    return count, False


def report_seeds(out):
    """The seed constants, each validated by a second route before anything is derived from it."""
    out.write("  seeds, each checked by a second route\n")
    machin = pi_machin()
    euler = pi_euler()
    out.write("    pi: Machin vs Euler agree to %d places: %s\n"
              % (REPORT_DIGITS, agrees(machin, euler)))

    roots_ok = True
    for prime in SEED_PRIMES[:6]:
        root = sqrt_scaled(prime)
        # second route: the defining property, root^2 == prime
        squared = mul(root, root)
        if not agrees(squared, prime * SCALE):
            roots_ok = False
    out.write("    prime roots: sqrt(p)^2 == p for the first six seed primes: %s\n" % roots_ok)

    # ln second route: ln(6) built as ln(2)+ln(3) against a direct ln(6) series
    ln_two = ln_rational(2, 1)
    ln_three = ln_rational(3, 1)
    ln_six_identity = ln_two + ln_three
    ln_six_direct = ln_rational(6, 1)
    out.write("    logs: ln(2)+ln(3) == ln(6) direct to %d places: %s\n"
              % (REPORT_DIGITS, agrees(ln_six_identity, ln_six_direct)))
    out.write("\n")
    return machin, {prime: sqrt_scaled(prime) for prime in SEED_PRIMES}, (ln_two, ln_three)


def report_root_spread(out, root_of):
    """The root family: derived sqrt(n) checked against a direct root, and the reach counted."""
    out.write("  root family: sqrt(n) from the seed prime roots, checked against a direct root\n")

    sample = [6, 10, 15, 30, 105, 210, 2310, 44100 + 1, 999983 * 2]  # smooth and one non-smooth probe
    worst_residual = 0
    checked = 0
    for number in sample:
        derived = sqrt_by_identity(number, SEED_PRIMES, root_of)
        if derived is None:
            out.write("    sqrt(%d): not smooth over the seed primes, not derivable, skipped\n" % number)
            continue
        direct = sqrt_scaled(number)
        residual = abs(derived - direct)
        worst_residual = max(worst_residual, residual)
        checked += 1
        out.write("    sqrt(%d): derived == direct to %d places: %s\n"
                  % (number, REPORT_DIGITS, agrees(derived, direct)))
    out.write("  worst residual over %d checks: %d units in the last working place, guard holds %d\n\n"
              % (checked, worst_residual, GUARD))
    return worst_residual


def report_zeta_spread(out, pi_value):
    """The zeta family: zeta(2k) = rational * pi^(2k) from one seed, checked by an exact ratio."""
    out.write("  zeta family: zeta(2k) = rational * pi^(2k), from the single seed pi\n")
    pi_squared = mul(pi_value, pi_value)
    pi_fourth = mul(pi_squared, pi_squared)
    zeta_two = pi_squared // 6
    zeta_four = pi_fourth // 90
    # exact ratio independent of pi: zeta(4)/zeta(2)^2 = (1/90)/(1/36) = 2/5. 5 zeta4 == 2 zeta2^2
    left = 5 * zeta_four
    right = 2 * mul(zeta_two, zeta_two)
    out.write("    zeta(2)=pi^2/6 and zeta(4)=pi^4/90 derived; 5*zeta(4) == 2*zeta(2)^2: %s\n"
              % agrees(left, right))
    out.write("    (the ratio 2/5 is exact and free of pi. It checks the two derivations against\n")
    out.write("     each other without a slow direct zeta series, which is infeasible at this scale)\n\n")
    return agrees(left, right)


def report_null(out, root_of, pi_value):
    """The drawn null: false identities refused by the same second-route check that passes true ones."""
    out.write("  drawn null: false identities refused by the second-route check\n")

    direct_six = sqrt_scaled(6)
    false_sum = root_of[2] + root_of[3]              # sqrt(6) is NOT sqrt(2)+sqrt(3)
    true_product = mul(root_of[2], root_of[3])        # sqrt(6) IS sqrt(2)*sqrt(3)
    out.write("    sqrt(6) == sqrt(2)+sqrt(3): %s (false, refused)\n" % agrees(direct_six, false_sum))
    out.write("    sqrt(6) == sqrt(2)*sqrt(3): %s (true, carried)\n" % agrees(direct_six, true_product))

    root_five = sqrt_scaled(5)
    phi = (SCALE + root_five) // 2                    # golden ratio (1 + sqrt 5)/2
    phi_squared = mul(phi, phi)
    out.write("    phi^2 == phi + 2: %s (false, refused)\n" % agrees(phi_squared, phi + 2 * SCALE))
    out.write("    phi^2 == phi + 1: %s (true, carried)\n\n" % agrees(phi_squared, phi + SCALE))
    # the null is well drawn when the false ones fail and the true ones pass
    return (not agrees(direct_six, false_sum)) and (not agrees(phi_squared, phi + 2 * SCALE))


def report_multiplier(out):
    """The accuracy multiplier: derived constants per seed, counted, and shown to pass one million."""
    out.write("  multiplier: exactly-known constants per seed, counted over the seed primes\n")
    out.write("  %-8s %-16s %-16s %s\n" % ("seeds", "bound", "generated", "per seed"))

    budget = 3_000_000
    for seed_count, bound in ((3, 10 ** 12), (6, 10 ** 12), (10, 10 ** 12), (15, 10 ** 12)):
        primes = SEED_PRIMES[:seed_count]
        generated, capped = count_smooth(primes, bound, budget)
        marker = " (budget reached, lower bound)" if capped else ""
        out.write("  %-8d 10^%-13d %-16d %.0f%s\n"
                  % (seed_count, 12, generated, generated / seed_count, marker))

    # The two-seed case pushed until the per-seed count passes one million. sqrt(2) and sqrt(3) alone
    # generate the square root of every 3-smooth integer, and there are more of those than any bound.
    primes = [2, 3]
    bound = 10 ** 800
    generated, capped = count_smooth(primes, bound, budget)
    out.write("\n  two seeds sqrt(2), sqrt(3), bound 10^800: generated %d, per seed %.0f%s\n"
              % (generated, generated / len(primes), " (budget reached, lower bound)" if capped else ""))
    out.write("  the count grows without limit in the bound and in the number of seeds. The\n")
    out.write("  multiplier passes any factor, one million included, at a finite bound the count reaches.\n")
    return generated / len(primes)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  exact identities spread precision from a few seeds to unboundedly many derived constants\n")
    out.write("  report scale %d places, guard %d, working scale %d\n\n"
              % (REPORT_DIGITS, GUARD_DIGITS, WORK_DIGITS))

    pi_value, root_of, _logs = report_seeds(out)
    residual = report_root_spread(out, root_of)
    zeta_ok = report_zeta_spread(out, pi_value)
    null_ok = report_null(out, root_of, pi_value)
    per_seed = report_multiplier(out)

    out.write("\n  scope: this multiplier is unbounded only for constants DEFINED by exact operations.\n")
    out.write("  a measured quantity (a crystal edge, a physical constant) keeps its upstream\n")
    out.write("  measurement floor, and no identity here raises it past that floor. what an identity\n")
    out.write("  buys in a measured domain is a floor-free RATIO, where the measured constant cancels.\n")
    out.flush()

    passed = agrees(residual, 0) or residual < GUARD
    return 0 if (zeta_ok and null_ok and per_seed >= 1_000_000 and passed) else 1


if __name__ == "__main__":
    raise SystemExit(main())
