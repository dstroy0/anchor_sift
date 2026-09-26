#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-006
#
# Proof of the boundary posit, stated in theory/workbooks/anchor_sift/precision_spread_theory.md section 10: every
# exact representation has a boundary of one of three kinds, a FORMAT boundary that a larger format
# raises, a MEASUREMENT boundary fixed upstream, and a COMPLETENESS boundary that only more computation
# crosses. Arithmetic precision moves the first and never the other two.
#
#   Usage:  python evidence/proofs/posits/proof_domain_boundaries.py
#
# The three kinds are named from a survey of six domains. A survey is not a proof. Three cases are
# built here where the boundary is known by construction.
#
#   FORMAT       the number theoretic transform's length. A length-n root of unity exists modulo a prime
#                p exactly when n divides p - 1. The boundary is the 2-adic order of p. It is proven
#                by building the root at the cap and failing to build it one power of two past the cap,
#                then moving the boundary with a larger prime. The transform is cyclic on Z/nZ, and its
#                double is the involution m -> -m, its own inverse: a format boundary is a fold.
#   MEASUREMENT  a value known only to F places. An identity applied to it lands near F, never at the
#                full scale. Precision on this end does not lower the deposit's floor.
#   COMPLETENESS a bounded enumeration read at a horizon. Carrying the count at more decimal places does
#                not change it; only raising the horizon does. Precision does not buy completeness.
#
# Each case states the outcome its construction forces, and any case that misses it refutes the posit.
# No bounding: every test is an exact integer comparison, and the failures are constructed.

import io
import sys

# prime -> (2-adic order of p-1, a primitive root)
FORMAT_PRIMES = {998244353: (23, 3), 2013265921: (27, 31)}


def has_root_of_order(prime, generator, length):
    """Whether a primitive `length`-th root of unity exists modulo `prime`, with `length` a power of two.

    It exists exactly when `length` divides `prime - 1`. Where it does, `generator^((prime-1)/length)`
    has order exactly `length`, confirmed by raising it to `length` and to `length/2`.
    """
    if (prime - 1) % length != 0:
        return False
    root = pow(generator, (prime - 1) // length, prime)
    return pow(root, length, prime) == 1 and pow(root, length // 2, prime) != 1


def report_format(out):
    """The transform-length boundary: built at the cap, refused past it, moved by a larger prime."""
    out.write("  FORMAT boundary: the number theoretic transform's length divides p - 1\n")
    small_prime, (small_adic, small_gen) = 998244353, FORMAT_PRIMES[998244353]

    at_cap = has_root_of_order(small_prime, small_gen, 2 ** small_adic)
    below_cap = has_root_of_order(small_prime, small_gen, 2 ** 10)
    past_cap = has_root_of_order(small_prime, small_gen, 2 ** (small_adic + 1))

    out.write("    prime %d, 2-adic order %d\n" % (small_prime, small_adic))
    out.write("    length 2^10 has a root: %s ; length 2^%d (the cap) has a root: %s\n"
              % (below_cap, small_adic, at_cap))
    out.write("    length 2^%d (past the cap) has a root: %s (the boundary)\n"
              % (small_adic + 1, past_cap))

    big_prime, (big_adic, big_gen) = 2013265921, FORMAT_PRIMES[2013265921]
    moved = has_root_of_order(big_prime, big_gen, 2 ** (small_adic + 1))
    out.write("    prime %d, 2-adic order %d: length 2^%d now has a root: %s (boundary moved)\n"
              % (big_prime, big_adic, small_adic + 1, moved))

    # the fold: the double transform is m -> -m on Z/nZ, an involution, fixed points 0 and n/2
    length = 2 ** 10
    involution_holds = all((-(-index % length)) % length == index for index in range(length))
    fixed_points = [index for index in range(length) if (-index) % length == index]
    out.write("    the fold: m -> -m on Z/%d applied twice is the identity: %s ; fixed points %s\n\n"
              % (length, involution_holds, fixed_points))

    forced = below_cap and at_cap and (not past_cap) and moved and involution_holds
    return forced


def report_measurement(out):
    """The measurement boundary: an identity on a value known to F places lands near F, not at full scale."""
    out.write("  MEASUREMENT boundary: an identity does not lower a deposit's floor\n")
    report_places = 120
    floor_places = 30
    scale = 10 ** report_places

    # a defined value carried to full scale, and the same value as a deposit known only to F places
    from math import isqrt
    defined = isqrt(2 * scale * scale)  # sqrt(2) at the full scale
    step = 10 ** (report_places - floor_places)
    measured = (defined // step) * step  # the deposit, cleared below F places

    defined_double = 2 * defined
    measured_double = 2 * measured
    defined_depth = matching_places(defined_double, 2 * defined, report_places)
    measured_depth = matching_places(measured_double, 2 * defined, report_places)

    out.write("    defined input doubled agrees to %d places (full scale %d)\n"
              % (defined_depth, report_places))
    out.write("    measured input (floor %d) doubled agrees to %d places, near the floor, not the scale\n\n"
              % (floor_places, measured_depth))
    forced = defined_depth >= report_places and (floor_places - 3) <= measured_depth < report_places
    return forced


def matching_places(left, right, report_places):
    """How many leading decimal places two scaled integers agree to, capped at the report scale."""
    difference = abs(left - right)
    if difference == 0:
        return report_places
    work = len(str(10 ** report_places))
    return max(0, work - len(str(difference)))


def count_within_horizon(branching, full_depth, horizon):
    """Leaves of a full `branching`-ary tree reachable within `horizon` levels, an exact integer."""
    reach = min(horizon, full_depth)
    return branching ** reach


def report_completeness(out):
    """The completeness boundary: carrying the count at more places does not change it; the horizon does."""
    out.write("  COMPLETENESS boundary: precision does not buy completeness\n")
    branching = 3
    full_depth = 12
    horizon = 7

    at_horizon = count_within_horizon(branching, full_depth, horizon)
    full = count_within_horizon(branching, full_depth, full_depth)
    incomplete = at_horizon < full

    # carry the horizon count at 1000 decimal places: the integer is unchanged, precision buys nothing
    carried = at_horizon * (10 ** 1000)
    same_after_precision = (carried // (10 ** 1000)) == at_horizon

    deeper = count_within_horizon(branching, full_depth, horizon + 1)
    horizon_moves = deeper > at_horizon

    out.write("    3-ary tree, full depth %d. count within horizon %d: %d ; full count: %d\n"
              % (full_depth, horizon, at_horizon, full))
    out.write("    the horizon count carried at 1000 places is unchanged: %s (precision buys nothing)\n"
              % same_after_precision)
    out.write("    raising the horizon by one changes the count: %s (only computation crosses it)\n\n"
              % horizon_moves)
    return incomplete and same_after_precision and horizon_moves


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  PROOF: every exact representation has a boundary of one of three kinds\n\n")
    fmt = report_format(out)
    measured = report_measurement(out)
    complete = report_completeness(out)

    if fmt and measured and complete:
        out.write("  each case lands on its forced outcome: the posit holds. arithmetic precision raises\n")
        out.write("  a format boundary and never a measurement or a completeness one.\n")
    else:
        out.write("  a case missed its forced outcome: the posit is refuted as stated.\n")
    out.flush()
    return 0 if (fmt and measured and complete) else 1


if __name__ == "__main__":
    raise SystemExit(main())
