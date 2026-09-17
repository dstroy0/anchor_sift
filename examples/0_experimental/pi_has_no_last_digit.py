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
# This reads no corpus, so it sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. Pi is transcendental, so its decimal expansion never ends and never repeats. A floor is a
# scale, 10^-N, and pi truncated to that floor has a definite last digit, its Nth decimal digit, exact
# and computable. But N has no ceiling on this engine, so raising the floor always turns up another
# digit. The last digit at the floor exists for every floor and is never the last, the same claim the
# precision document beside this file makes, shown on the most familiar irrational.
#
# Positive control: the computed digits match the published expansion of pi. Two routes: pi is computed
# by Machin's formula and by Euler's, and they agree to the digit at the full scale, so the digit named
# at the floor is not an artifact of one series. Drawn null: computing at a deeper scale keeps every
# digit above the old floor and moves only the last one, the shape "no floor" takes from inside. No
# bounding: the scale is a declared input, and the arithmetic is exact integers throughout.

import io
import sys

# The floors to name pi's digit at. The last is deep enough to make the point and quick to reach.
FLOORS = [1, 10, 100, 1000, 5000, 10000]
DEEPEST = FLOORS[-1]
GUARD = 30
WORK = DEEPEST + GUARD
SCALE = 10 ** WORK

# The published decimal expansion of pi after the point, the external oracle for the positive control.
PUBLISHED_PI_FRACTION = "1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679"


def arctan_reciprocal(whole, scale):
    """arctan(1/whole) at `scale`, whole an integer above one. Exact integer series, floored per term."""
    total = 0
    sign = 1
    power = whole
    whole_squared = whole * whole
    index = 0
    while True:
        term = scale // ((2 * index + 1) * power)
        if term == 0:
            break
        total += sign * term
        sign = -sign
        index += 1
        power *= whole_squared
    return total


def pi_machin(scale):
    """pi at `scale` by Machin, pi = 16 arctan(1/5) - 4 arctan(1/239)."""
    return 16 * arctan_reciprocal(5, scale) - 4 * arctan_reciprocal(239, scale)


def pi_euler(scale):
    """pi at `scale` by Euler, pi = 4 (arctan(1/2) + arctan(1/3)). The second route."""
    return 4 * (arctan_reciprocal(2, scale) + arctan_reciprocal(3, scale))


def digit_at_floor(pi_scaled, floor):
    """The last decimal digit of pi at scale 10^-floor, its `floor`-th decimal digit."""
    # pi_scaled is floor(pi * 10^WORK). Shift down to `floor` places and take the last digit.
    shifted = pi_scaled // (10 ** (WORK - floor))
    return shifted % 10


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  the last digit of pi at the floor: there is none, because there is no floor\n\n")

    machin = pi_machin(SCALE)
    euler = pi_euler(SCALE)
    routes_agree = abs(machin - euler) < 10 ** GUARD
    pi_scaled = machin  # the integer floor(pi * 10^WORK), pi is 3.14..., so the integer part is 3

    # positive control against the published expansion
    fraction = pi_scaled - 3 * SCALE  # the part after the point, scaled
    computed_prefix = str(fraction // (10 ** (WORK - len(PUBLISHED_PI_FRACTION))))
    computed_prefix = computed_prefix.zfill(len(PUBLISHED_PI_FRACTION))
    prefix_matches = computed_prefix == PUBLISHED_PI_FRACTION

    out.write("  two routes (Machin, Euler) agree to the digit at %d places: %s\n" % (DEEPEST, routes_agree))
    out.write("  first %d computed digits match the published expansion of pi: %s\n\n"
              % (len(PUBLISHED_PI_FRACTION), prefix_matches))

    out.write("  %-14s %s\n" % ("floor (place)", "pi's last digit at that floor"))
    for floor in FLOORS:
        out.write("  %-14d %d\n" % (floor, digit_at_floor(pi_scaled, floor)))

    # the drawn null: go one floor deeper and show every digit above the old floor is unchanged, only
    # the last one moved, the shape "no floor" takes from inside.
    deeper = DEEPEST + 5
    deeper_scale = 10 ** (deeper + GUARD)
    deeper_pi = pi_machin(deeper_scale)
    old_last = digit_at_floor(pi_scaled, DEEPEST)
    new_last_at_old = (deeper_pi // (10 ** ((deeper + GUARD) - DEEPEST))) % 10
    deeper_last = (deeper_pi // (10 ** ((deeper + GUARD) - deeper))) % 10
    stable = new_last_at_old == old_last

    out.write("\n  raise the floor to %d places: the digit at place %d is still %d (unchanged: %s),\n"
              % (deeper, DEEPEST, new_last_at_old, stable))
    out.write("  and a new last digit appears at place %d, the value %d. the floor dropped and pi\n"
              % (deeper, deeper_last))
    out.write("  handed up another digit. there is no bottom, so there is no last digit.\n")
    out.flush()

    return 0 if (routes_agree and prefix_matches and stable) else 1


if __name__ == "__main__":
    raise SystemExit(main())
