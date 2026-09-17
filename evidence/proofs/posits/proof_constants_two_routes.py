#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-015
#
# The natural constants are computed, not stored, and the check that each is right is two routes agreeing,
# not a pasted expansion. A stored expansion is an oracle, an answer from outside the sample, and a natural
# constant is not that: it is derivable from within to any precision. Here it is derived, and the two
# derivations meeting is the test. This exercises representation/constants/naturals.py at a precision no table would
# carry and shows the agreement, the algebraic identities that give a third independent check where one
# exists, and a wrong series caught.
#
#   Usage:  python evidence/proofs/posits/proof_constants_two_routes.py
#
# Positive control: pi, e, sqrt(2), ln(2) and the golden ratio, each to 2000 places, by two independent
# routes that agree to the digit. pi by Machin and by Euler; e by its Taylor series and by its continued
# fraction; sqrt(2) by integer Newton and by its continued fraction; ln(2) by the 1/(k 2^k) series and by
# 2 artanh(1/3); the golden ratio by the square-root form and by the ratio of Fibonacci numbers.
#
# Third route where an algebraic identity gives one, independent of both series: floor(sqrt(2) * S)^2 lands
# in the unit interval below 2 S^2, and the golden ratio satisfies phi^2 = phi + 1 at the working scale.
# These are derived relations. Each adds a route and holds no stored value.
#
# Drawn null: a Machin identity with one coefficient wrong (16 arctan(1/5) - 3 arctan(1/239) instead of 4)
# is a plausible wrong series. It disagrees with the true value, and the two-route check raises instead
# of returning a wrong digit. A check that cannot fail is not a check; this one fails on the wrong series.
#
# Floor: this verifies the implementation reaches each constant by two routes and refuses a wrong one. It
# does not reprove the classical identities the routes rest on (Machin 1706, Euler, the continued fractions),
# which are named and used, not derived here.

import io
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
from representation.constants import naturals  # noqa: E402

DIGITS = 2000


def positive_control(out):
    """Each constant to DIGITS places by its two routes, shown agreeing. The routes are called directly."""
    out.write("  positive control: each constant to %d places, two routes, shown agreeing\n" % DIGITS)
    scale = 10 ** (DIGITS + naturals.GUARD)
    drop = 10 ** naturals.GUARD
    pairs = (
        ("pi", naturals._pi_machin, naturals._pi_euler),
        ("e", naturals._e_taylor, naturals._e_continued_fraction),
        ("sqrt(2)", naturals._root_two_newton, naturals._root_two_continued_fraction),
        ("ln(2)", naturals._ln_two_reciprocal_powers, naturals._ln_two_artanh),
        ("golden", naturals._golden_from_root, naturals._golden_from_fibonacci),
    )
    all_agree = True
    for name, route_one, route_two in pairs:
        value_one = route_one(scale) // drop
        value_two = route_two(scale) // drop
        agree = value_one == value_two
        all_agree = all_agree and agree
        out.write("    %-9s routes agree to %d places: %s\n" % (name, DIGITS, agree))
    out.write("\n")
    return all_agree


def algebraic_identities(out):
    """A third route where an identity supplies one: sqrt(2)^2 and phi^2 = phi + 1, at the working scale."""
    out.write("  algebraic identity as a third route, independent of the series\n")
    scale = 10 ** DIGITS

    root = naturals.root_two(DIGITS)               # floor(sqrt(2) * scale)
    # floor(sqrt(2) * scale) is the greatest integer whose square does not pass 2 scale^2.
    root_ok = (root * root <= 2 * scale * scale) and ((root + 1) * (root + 1) > 2 * scale * scale)
    out.write("    sqrt(2)^2 brackets 2 at scale: %s\n" % root_ok)

    phi = naturals.golden_ratio(DIGITS)            # floor(phi * scale)
    # phi^2 = phi + 1 gives phi^2 * scale = (phi + 1) * scale^2; in floored integers the two sides land
    # within a couple of units, since each factor is floored once.
    left = phi * phi
    right = (phi + scale) * scale
    phi_ok = abs(left - right) <= 2 * scale
    out.write("    phi^2 equals phi + 1 at scale (within rounding): %s\n" % phi_ok)
    out.write("\n")
    return root_ok and phi_ok


def _pi_machin_wrong(scale):
    """A plausible wrong Machin identity: the second coefficient is 3 where it should be 4."""
    return 16 * naturals._arctan_inverse(5, scale) - 3 * naturals._arctan_inverse(239, scale)


def drawn_null(out):
    """A wrong series disagrees, and the two-route check raises instead of returning a wrong digit."""
    out.write("  drawn null: a Machin identity with one coefficient wrong is refused\n")
    scale = 10 ** (DIGITS + naturals.GUARD)
    drop = 10 ** naturals.GUARD
    true_value = naturals._pi_machin(scale) // drop
    wrong_value = _pi_machin_wrong(scale) // drop
    disagree = true_value != wrong_value

    # Name the first place the wrong series diverges, making the disagreement concrete.
    true_text = str(true_value)
    wrong_text = str(wrong_value)
    first = next((position for position in range(min(len(true_text), len(wrong_text)))
                  if true_text[position] != wrong_text[position]), None)
    out.write("    true and wrong pi differ: %s, first at decimal place %s\n" % (disagree, first))

    refused = False
    try:
        naturals._agree(naturals._pi_machin, _pi_machin_wrong, DIGITS, "pi (null)")
    except ValueError:
        refused = True
    out.write("    the two-route check raises on the wrong series: %s\n" % refused)
    out.write("\n")
    return disagree and refused


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  natural constants: computed to %d places, checked by two routes, not by a stored table\n\n"
              % DIGITS)
    control = positive_control(out)
    identities = algebraic_identities(out)
    null = drawn_null(out)
    out.write("  positive control passed: %s\n" % control)
    out.write("  algebraic identities held: %s\n" % identities)
    out.write("  wrong series refused:     %s\n" % null)
    out.flush()
    return 0 if (control and identities and null) else 1


if __name__ == "__main__":
    raise SystemExit(main())
