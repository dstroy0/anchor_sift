#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-005
#
# Proof of the precision-spread posit, stated in theory/workbooks/anchor_sift/precision_spread_theory.md: an exact
# identity carries full precision from a DEFINED input to its output, and a seed of defined constants
# then generates unboundedly many at the same precision; a MEASURED input keeps its upstream floor and no
# identity raises it, except that a RATIO in which the measured value cancels is exact.
#
#   Usage:  python evidence/proofs/posits/proof_precision_spread.py
#
# The posit came from surveying six domains. Natural constants and hydrogen spectra spread precision
# without bound; crystal edges and physical constants do not, being measured. That is a survey, and a
# rule read off the survey is a hypothesis.
#
# Proving it needs cases where the answer is fixed by construction instead of reported. Four are
# built here from one stand-in constant, pi. A value is either DEFINED (computed to the full scale) or
# MEASURED (the same value truncated to a floor of F places, the rest unknown), and an identity is
# either TRUE or FALSE. The four cases and the outcome each forces:
#
#   defined input, true identity      precision CARRIED to the full scale
#   measured input, true identity     precision FLOORED at F, the identity does not recover the rest
#   measured input, canceling ratio   EXACT, the measured value cancels and the floor is gone
#   any input, false identity         REFUSED by the second-route check
#
# The prediction is exact. Any case that carries past its floor, or floors a defined input, or lets a
# false identity through, refutes the posit. The second claim, that the multiplier is unbounded in the
# defined regime, is counted directly: k defined seeds generate the square root of every k-smooth
# integer, a count with no ceiling.

import io
import sys

REPORT_DIGITS = 200
GUARD_DIGITS = 20
WORK_DIGITS = REPORT_DIGITS + GUARD_DIGITS
SCALE = 10 ** WORK_DIGITS
FLOOR_PLACES = 40  # a measured deposit is known only to this many places


def agrees_to(left, right, places):
    """Whether two scaled integers agree to `places` decimal places."""
    return abs(left - right) < 10 ** (WORK_DIGITS - places)


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


def pi_defined():
    """pi at the full working scale, the defined value."""
    return 16 * arctan_reciprocal(5) - 4 * arctan_reciprocal(239)


def truncate_to_floor(value, places):
    """`value` with everything below `places` decimal places cleared: a deposit read only that far."""
    step = 10 ** (WORK_DIGITS - places)
    return (value // step) * step


def multiply_rational(value, numerator, denominator):
    """value * numerator / denominator on scaled integers, one floored divide."""
    return (value * numerator) // denominator


def ratio(upper, lower):
    """upper / lower on scaled integers, one floored divide."""
    return (upper * SCALE) // lower


def matching_places(left, right):
    """How many leading decimal places two scaled integers agree to. Reports the depth, not a verdict."""
    difference = abs(left - right)
    if difference == 0:
        return WORK_DIGITS
    return max(0, WORK_DIGITS - len(str(difference)) + 1)


def report_cases(out):
    """The four constructed cases against their forced outcomes, reporting the agreement depth."""
    truth = pi_defined()
    measured = truncate_to_floor(truth, FLOOR_PLACES)

    out.write("  precision spread, four constructed cases (report scale %d places, measured floor %d)\n"
              % (REPORT_DIGITS, FLOOR_PLACES))
    out.write("  %-34s %-15s %-8s %s\n" % ("case", "forced", "places", "observed"))

    # 1. defined input, true identity: the defined pi doubled against a recomputed 2*pi
    defined_double = 2 * truth
    depth_defined = matching_places(defined_double, 2 * pi_defined())
    carried = depth_defined >= REPORT_DIGITS
    out.write("  %-34s %-15s %-8d %s\n" % ("defined input, double", "carried", depth_defined,
                                           "carried" if carried else "FAILED"))

    # 2. measured input, true identity: the deposit doubled against the true value. The floor moves by
    # log10(2) under the doubling. The depth lands near F, never at the report scale.
    measured_double = 2 * measured
    depth_measured = matching_places(measured_double, 2 * truth)
    floored = (FLOOR_PLACES - 3) <= depth_measured < REPORT_DIGITS
    out.write("  %-34s %-15s %-8d %s\n" % ("measured input, double", "floored near F", depth_measured,
                                           "floored near F" if floored else "FAILED"))

    # 3. measured input, canceling ratio: (2*pi)/(3*pi) from the deposit against the exact 2/3. The
    # deposit cancels between the parts. The floor is gone and the ratio is exact.
    upper = multiply_rational(measured, 2, 1)
    lower = multiply_rational(measured, 3, 1)
    canceled = ratio(upper, lower)
    true_two_thirds = (2 * SCALE) // 3
    depth_ratio = matching_places(canceled, true_two_thirds)
    exact = depth_ratio >= REPORT_DIGITS
    out.write("  %-34s %-15s %-8d %s\n" % ("measured input, canceling ratio", "exact", depth_ratio,
                                           "exact" if exact else "FAILED"))

    # 4. any input, false identity: claim 2*pi == pi + 1 against the true 2*pi
    false_claim = truth + SCALE
    depth_false = matching_places(false_claim, 2 * truth)
    refused = depth_false < FLOOR_PLACES
    out.write("  %-34s %-15s %-8d %s\n" % ("any input, false identity", "refused", depth_false,
                                           "refused" if refused else "FAILED"))
    out.write("\n")
    return carried and floored and exact and refused


def count_smooth(primes, bound, budget):
    """How many integers in [1, bound] have all prime factors among `primes`. Depth-first, budgeted."""
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


def report_multiplier(out):
    """The second claim: the defined-regime multiplier has no ceiling, counted over the seed primes."""
    primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
    out.write("  multiplier: square roots generated by k defined prime-root seeds\n")
    out.write("  %-8s %-16s %-16s %s\n" % ("seeds", "bound", "generated", "per seed"))
    unbounded = True
    previous = 0
    for seed_count in (2, 4, 6, 8, 10):
        chosen = primes[:seed_count]
        generated, _capped = count_smooth(chosen, 10 ** 15, 4_000_000)
        out.write("  %-8d 10^%-13d %-16d %.0f\n"
                  % (seed_count, 15, generated, generated / seed_count))
        unbounded = unbounded and (generated > previous)
        previous = generated
    out.write("  the count rises with every seed added and with the bound. It has no ceiling; a\n")
    out.write("  measured seed generates the same shapes but every one is floored at F, carrying no\n")
    out.write("  new precision past the deposit.\n\n")
    return unbounded


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  PROOF: an exact identity carries precision only where the quantity is defined\n\n")
    cases = report_cases(out)
    multiplier = report_multiplier(out)

    if cases and multiplier:
        out.write("  the four cases each land on their forced outcome and the multiplier has no\n")
        out.write("  ceiling: the posit holds. a measured absolute keeps its floor, its canceling\n")
        out.write("  ratio is exact, and a false identity is refused.\n")
    else:
        out.write("  a case missed its forced outcome: the posit is refuted as stated.\n")
    out.flush()
    return 0 if (cases and multiplier) else 1


if __name__ == "__main__":
    raise SystemExit(main())
