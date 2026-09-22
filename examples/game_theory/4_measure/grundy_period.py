#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-4-002
#
# Ask the period detector for a subtraction game's Grundy period, on every move set in a sweep, with
# the answer to each row computed separately and exactly.
#
#   Usage:  python examples/game_theory/4_measure/grundy_period.py [largest move] [most moves]
#
# This exists to close a hole the workbook names in its own words. Every reach claim in this work is
# empirical, quantified over a set nobody has enumerated, and the workbook states that getting from
# a list of instances to a statement about a domain takes a controlled series inside that domain
# with an outside answer attached, which it then says is years of work because obtaining the rows
# costs money and a database.
#
# Impartial games remove the cost. A subtraction game with a finite move set has an eventually
# periodic Grundy sequence, proved, and the period is a quantity a dull exact routine computes by
# comparison. So a row is free, the number of rows is a choice, and no row's answer came from the
# detector being tested. That is the whole of what this subject is for.
#
# The detector is `measure.periodicity.sequence_period` and it is the one the crystallography chapter
# uses on cell edges. It knows nothing about games. It is handed a list of small integers.
#
# One rule has to be respected and it is the detector's own. A period is scored against its
# multiples, so a period beyond half the window has a family of one inside the window and is the
# single tallest lag again. Rows whose true period exceeds half the window are therefore out of
# range by construction and are counted separately rather than counted as failures.

import io
import itertools
import os
import random
import statistics
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.periodicity import sequence_period
from representation.game.combinatorial import grundy_subtraction, subtraction_period

# Positions generated per game. Long enough that the longest period in the sweep still repeats
# dozens of times past its preperiod.
POSITIONS = 2048

# Windows the same rows are read at. A true period is the same number at all of them and that is a
# separate finding, recorded here because it is the only test that separates a period from the
# self-similarity the oracle script measures.
WINDOWS = (16, 24, 32, 48, 64)

# Reseeds of the shuffle each row is scored against. The floor quoted is the tallest margin any of
# them reached, not the average, so the separation is against the best a null permutation managed.
DRAWS = 12


def read(values, longest):
    """The measured period and its margin over the lags outside its family."""
    return sequence_period(values, longest=longest)


def floor_from_shuffles(values, longest, draws=DRAWS):
    """The tallest margin a shuffle of the same values reaches at this window.

    The shuffle keeps every Grundy value and destroys which position carries it, so whatever it
    reaches is what the detector reads off the histogram alone.
    """
    best = 0.0
    for seed in range(draws):
        shuffled = list(values)
        random.Random(seed).shuffle(shuffled)
        _, margin = sequence_period(shuffled, longest=longest)
        if margin is not None:
            best = max(best, margin)
    return best


def main():
    largest = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    most = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    games = []
    for count in range(1, most + 1):
        games.extend(itertools.combinations(range(1, largest + 1), count))

    rows = []
    for moves in games:
        values = grundy_subtraction(moves, POSITIONS)
        exact, start = subtraction_period(values)
        rows.append((moves, values, exact, start))

    settled = [row for row in rows if row[2] is not None]
    out.write("%d move sets, exact period found for %d of them\n" % (len(rows), len(settled)))
    out.write("periods present: %s\n\n" % sorted(set(row[2] for row in settled)))

    out.write("%-8s %8s %8s %8s\n" % ("window", "in range", "exact", "out of range"))
    for longest in WINDOWS:
        inside = [row for row in settled if row[2] <= (longest // 2)]
        hit = sum(1 for row in inside if read(row[1], longest)[0] == row[2])
        out.write("%-8d %8d %8d %8d\n" % (longest, len(inside), hit, len(settled) - len(inside)))

    # The margin against the floor, at the widest window, on every row that window can read.
    longest = WINDOWS[-1]
    inside = [row for row in settled if row[2] <= (longest // 2)]
    margins = []
    for moves, values, exact, start in inside:
        _, margin = read(values, longest)
        floor = floor_from_shuffles(values, longest)
        margins.append((margin, floor, moves, exact))

    live = [row[0] for row in margins]
    null = [row[1] for row in margins]
    ratios = [row[0] / row[1] for row in margins if row[1] > 0.0]
    out.write("\nat window %d, %d rows\n" % (longest, len(margins)))
    out.write("  live margin   min %.3f  median %.3f  max %.3f\n"
              % (min(live), statistics.median(live), max(live)))
    out.write("  shuffle floor min %.3f  median %.3f  max %.3f\n"
              % (min(null), statistics.median(null), max(null)))
    out.write("  ratio         min %.2f  median %.2f\n" % (min(ratios), statistics.median(ratios)))
    out.write("  rows where the live margin did not clear its own floor: %d\n"
              % sum(1 for row in margins if row[0] <= row[1]))

    # Window invariance. A true period is one number at every window; the oracle script shows what
    # an aperiodic sequence does here instead.
    short = [row for row in settled if row[2] <= (min(WINDOWS) // 2)]
    stable = sum(1 for row in short
                 if {read(row[1], longest)[0] for longest in WINDOWS} == {row[2]})
    out.write("\nrows with a period readable at every window: %d, of which the answer was the same "
              "number at all %d windows: %d\n" % (len(short), len(WINDOWS), stable))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
