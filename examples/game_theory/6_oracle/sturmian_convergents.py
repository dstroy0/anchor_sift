#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-6-006
#
# What the period detector returns when it is handed a sequence that has no period, and why the
# number it returns is not arbitrary.
#
#   Usage:  python examples/game_theory/6_oracle/sturmian_convergents.py
#
# Wythoff's losing positions sit on a line of slope phi. The gaps between successive ones form a
# Sturmian word, which is aperiodic: that is not a measurement, it follows from phi being irrational.
# Handed that word, sequence_period returns 8, then 13, then 21, then 34, then 55, as the window
# widens. Those are Fibonacci numbers, and the Fibonacci numbers are the denominators of the
# continued fraction convergents of phi.
#
# So the detector is not failing at random and it is not reading noise. Every margin here clears its
# own shuffle floor by six to nine times. A rotation by an irrational really does agree with itself
# at the denominator of any good rational approximation to that irrational, and the detector is
# reporting that agreement correctly. What is false is the name on the output. "Period" is the wrong
# word for it, and the workbook's crystallography rows are safe only because a lattice has a period
# for the reported number to be.
#
# The generalization is the falsifiable part and it is what this script tests. If the mechanism is
# continued fractions then the reported number should be a convergent denominator of the slope for
# any irrational slope, not only for phi. Nine slopes, seven windows each.
#
# The diagnostic that comes out of it needs no oracle at all. A true period is the same number at
# every window. These are not: none of the nine slopes gives one answer across all seven windows,
# and 115 of 115 subtraction games with a real period do.

import io
import math
import os
import random
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.periodicity import sequence_period

# Windows read. The point of the sweep is that the answer moves, so a single window would hide it.
WINDOWS = (16, 24, 32, 48, 64, 96, 128)

# Terms of the word. Long enough that the widest window still has four full candidate periods.
TERMS = 4000

# Shuffles each row is scored against.
DRAWS = 12

# Slopes read. Each is irrational and each has a different continued fraction shape: phi's is all
# ones and converges slowest, pi's has a 292 in it and converges fastest.
SLOPES = (("phi", (1.0 + (5.0 ** 0.5)) / 2.0),
          ("sqrt2", 2.0 ** 0.5),
          ("e", math.e),
          ("pi", math.pi),
          ("sqrt3", 3.0 ** 0.5),
          ("sqrt5", 5.0 ** 0.5),
          ("sqrt7", 7.0 ** 0.5),
          ("ln2+1", math.log(2.0) + 1.0),
          ("cbrt2+1", (2.0 ** (1.0 / 3.0)) + 1.0))


def sturmian(slope, terms=TERMS):
    """Gaps between successive terms of the Beatty sequence of `slope`.

    This is the same object Wythoff's first coordinates form, written for any slope. Two gap values
    appear and never a third, and the word they make is aperiodic for every irrational slope.
    """
    beatty = [int(math.floor(step * slope)) for step in range(terms + 1)]
    return [beatty[index] - beatty[index - 1] for index in range(1, len(beatty))]


def approximation_denominators(slope, depth=10):
    """Denominators of the convergents of `slope`, and of the intermediate fractions between them.

    The intermediate fractions are included because they are also best approximations from one side,
    and a detector reading agreement has no reason to prefer the two-sided ones.
    """
    rest = slope
    lower, previous = 0, 1
    out = set()
    for _ in range(depth):
        whole = int(math.floor(rest))
        for step in range(1, whole + 1):
            out.add((step * lower) + previous)
        lower, previous = (whole * lower) + previous, lower
        out.add(lower)
        fraction = rest - whole
        if fraction < 1e-12:
            break
        rest = 1.0 / fraction
    return out


def floor_from_shuffles(word, longest, draws=DRAWS):
    """The tallest margin a shuffle of the same gaps reaches."""
    best = 0.0
    for seed in range(draws):
        shuffled = list(word)
        random.Random(seed).shuffle(shuffled)
        _, margin = sequence_period(shuffled, longest=longest)
        if margin is not None:
            best = max(best, margin)
    return best


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    out.write("%-8s %-30s %s\n" % ("slope", "reported period by window", "all clear their floor"))
    for name, slope in SLOPES:
        known = approximation_denominators(slope)
        word = sturmian(slope)
        reported = []
        cleared = True
        for longest in WINDOWS:
            period, margin = sequence_period(word, longest=longest)
            floor = floor_from_shuffles(word, longest)
            cleared = cleared and (margin is not None) and (margin > floor)
            reported.append(period)
            rows.append((margin, name, longest, period, period in known, floor))
        out.write("%-8s %-30s %s\n" % (name, reported, cleared))

    inside = sum(1 for row in rows if row[4])
    out.write("\nreported period is a convergent or intermediate denominator of the slope: "
              "%d of %d rows\n" % (inside, len(rows)))
    rows.sort(key=lambda row: row[0])
    outside = [(index, row) for index, row in enumerate(rows) if not row[4]]
    for index, row in outside:
        out.write("  the exception at margin %.3f (%s, window %d, reported %d) is rank %d of %d "
                  "by margin\n" % (row[0], row[1], row[2], row[3], index, len(rows)))

    ratios = [row[0] / row[5] for row in rows if row[5] > 0.0]
    out.write("margin over its own shuffle floor: min %.1f, median %.1f\n"
              % (min(ratios), sorted(ratios)[len(ratios) // 2]))

    spread = 0
    for name, slope in SLOPES:
        word = sturmian(slope)
        answers = {sequence_period(word, longest=longest)[0] for longest in WINDOWS}
        if len(answers) == 1:
            spread += 1
    out.write("slopes giving one answer at all %d windows: %d of %d. For a real period it is all of "
              "them.\n" % (len(WINDOWS), spread, len(SLOPES)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
