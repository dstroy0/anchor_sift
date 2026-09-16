#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-4-002
#
# Whether the departure a board shows is the rules or the play, asked by varying one and holding the
# other.
#
#   Usage:  python examples/games/4_measure/rules_and_play.py [games per pairing]
#
# Every corpus in this work holds two things welded together. A text carries its grammar and its
# author at once and no amount of measuring separates them, because there is no way to obtain the
# same author under different grammar. A board separates them for nothing: three players of
# different strength on one fixed rule set give nine corpora that differ in the play alone, and the
# rule set's contribution is in every one of them.
#
# The three arms are the textbook ones. Drawing uniformly from the legal moves knows the rules and
# nothing else. Taking the move that turns over the most pieces is the standard weak heuristic and is
# weak here too. Taking a corner where one is offered, and otherwise turning over the fewest pieces,
# is the standard improvement: a corner cannot be flipped back and a small flip leaves the opponent
# fewer replies.
#
# The strength ordering is not asserted, it is played out. The win share in the last column is the
# independent quantity the departure is scored against, and it is not a reading of the departure.
#
# What came out is a negative and it is the point of the script. The departure separates the rules
# from a scatter by 21 percent and 25 floors, and it does not order the three arms at all: the
# correlation between the departure and the win share over the nine pairings is 0.07.

import io
import itertools
import os
import statistics
import sys

import numpy

HERE = os.path.abspath(os.path.dirname(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.clustering import correlation
from measure.shift_agreement import lattice_agreement
from representation.game.board import ARMS, SIDE, play, scattered

# Drawn arrangements averaged per position.
DRAWS = 4

# Arms, weakest first by the win shares this script prints.
ORDER = ("random", "greedy", "corner")


def clumping(grid):
    """Share of occupied squares whose neighbour one step away carries the same colour, both axes."""
    square = numpy.frombuffer(bytes(grid), dtype=numpy.uint8).reshape(SIDE, SIDE)
    return (lattice_agreement(square, 0, 1) + lattice_agreement(square, 1, 1)) / 2.0


def pairing(black, white, games):
    """Departure from the null and black's share of the wins, over one pairing."""
    live = []
    null = []
    won = 0.0
    for seed in range(games):
        positions, counts = play(ARMS[black], ARMS[white], seed=seed)
        final = positions[-1]
        live.append(clumping(final))
        null.append(statistics.fmean(clumping(scattered(final, draw)) for draw in range(DRAWS)))
        won += 1.0 if counts[0] > counts[1] else (0.5 if counts[0] == counts[1] else 0.0)
    return statistics.fmean(live), statistics.fmean(null), won / games


def main():
    games = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    out.write("%d games per pairing, Reversi on %d squares\n\n" % (games, SIDE * SIDE))
    out.write("%-18s %8s %8s %8s %10s\n" % ("black v white", "live", "null", "ratio", "black wins"))

    ratios = []
    wins = []
    for black, white in itertools.product(ORDER, repeat=2):
        live, null, share = pairing(black, white, games)
        ratios.append(live / null)
        wins.append(share)
        out.write("%-18s %8.4f %8.4f %8.3f %10.3f\n"
                  % (black + " v " + white, live, null, live / null, share))

    out.write("\ndeparture from the null, over all nine: %.3f to %.3f, mean %.3f\n"
              % (min(ratios), max(ratios), statistics.fmean(ratios)))
    out.write("correlation between the departure and the win share: %.3f\n"
              % correlation(ratios, wins))
    out.write("\nThe rules are in every row and the play is in none of them. The flip rule turns over\n"
              "a bracketed run whoever picked the move, so a strong player and a weak one leave the\n"
              "same kind of trace and differ in where they put it. This measure reads what was done\n"
              "to the board and not who chose it.\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
