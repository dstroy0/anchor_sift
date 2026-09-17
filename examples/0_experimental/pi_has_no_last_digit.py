#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-012
#
# What is the last digit of pi at the floor. The answer is that there is no last digit, because there is
# no floor, and this shows it by naming the digit at any floor asked for and then naming one below it.
#
#   Usage:  python examples/0_experimental/pi_has_no_last_digit.py
#
# This reads no corpus and sits in 0_experimental: an arithmetic result shown working, ahead of any stage
# reading. Pi is transcendental, and its decimal expansion never ends and never repeats. A floor is a
# scale, 10^-N, and pi truncated to that floor has a definite last digit, its Nth decimal digit, exact
# and computable. But N has no ceiling on this engine, and raising the floor always turns up another
# digit. The last digit at the floor exists for every floor and is never the last, the same claim the
# precision document beside this file makes, shown on the most familiar irrational.
#
# The digits come from representation/constants/naturals.py, which computes pi to any precision and returns
# a value only when two independent routes, Machin and Euler, agree at that precision. That agreement is
# the positive control, and it consults no stored expansion: a natural constant is derived, never looked
# up. The posit evidence/proofs/posits/proof_constants_two_routes.py drives the two routes apart on a wrong
# series and shows the disagreement caught. Drawn null here: computing at a deeper floor keeps every digit
# above the old floor and moves only the last one, the shape "no floor" takes from inside. No bounding: the
# floor is a declared input, and the arithmetic is exact integers throughout.

import io
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
from representation.constants import naturals  # noqa: E402

# The floors to name pi's digit at. The last is deep enough to make the point and quick to reach.
FLOORS = [1, 10, 100, 1000, 5000, 10000]
DEEPEST = FLOORS[-1]


def digit_at_floor(floor):
    """pi's last decimal digit at scale 10^-floor, its floor-th decimal digit.

    naturals.pi(floor) is floor(pi * 10^floor), an exact integer, and its last digit is pi's floor-th
    decimal place.
    """
    return naturals.pi(floor) % 10


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  the last digit of pi at the floor: there is none, because there is no floor\n\n")

    # pi to the deepest floor. naturals.pi returns only when Machin and Euler agree, and a value at all is
    # the two-route positive control, with no published expansion consulted.
    pi_deep = naturals.pi(DEEPEST)
    out.write("  pi computed to %d places, Machin and Euler agreeing, no stored expansion consulted\n\n"
              % DEEPEST)

    out.write("  %-14s %s\n" % ("floor (place)", "pi's last digit at that floor"))
    for floor in FLOORS:
        out.write("  %-14d %d\n" % (floor, digit_at_floor(floor)))

    # The drawn null: go deeper and show every digit above the old floor is unchanged, only the last one
    # moved, the shape "no floor" takes from inside.
    deeper = DEEPEST + 5
    pi_deeper = naturals.pi(deeper)
    above_old_floor = pi_deeper // (10 ** (deeper - DEEPEST))   # pi at DEEPEST, read from the deeper value
    prefix_stable = above_old_floor == pi_deep                 # every digit above DEEPEST is unchanged
    old_digit = pi_deep % 10
    new_digit = pi_deeper % 10

    out.write("\n  raise the floor to %d places: every digit above place %d is unchanged (%s), the digit\n"
              % (deeper, DEEPEST, prefix_stable))
    out.write("  at place %d is still %d, and a new last digit appears at place %d, the value %d. the floor\n"
              % (DEEPEST, old_digit, deeper, new_digit))
    out.write("  dropped and pi handed up another digit. there is no bottom, and there is no last digit.\n")
    out.flush()

    return 0 if prefix_stable else 1


if __name__ == "__main__":
    raise SystemExit(main())
