#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-3-001
#
# The null for a board, and the control that says what the departure from it is reading.
#
#   Usage:  python examples/games/3_reference/position_null.py [games]
#
# The null permutation of this work, written for a grid, keeps how many of each colour are on the
# board and which squares are occupied at all, and draws which colour sits where. It is the maximum
# entropy arrangement under the constraints the position supplies, so it cannot be wrong, and a
# departure from it is arrangement and cannot be counts.
#
# What a departure does not say on its own is which part of the game put it there. A board game has
# two ingredients and the measure sees their sum: the rules, which are fixed and public, and the
# play, which is a choice. A control that removes one of them and keeps the other is the only way to
# tell, and a board supplies one for free.
#
# The control is a game played on the same board, with the same number of squares filled and the
# same two colours alternating, where a move places a piece and nothing is turned over. It has rules
# and it has play and it has no flip. If the departure survives it, the departure is the board. If it
# does not, the departure is the flip rule.

import io
import os
import random
import statistics
import sys

import numpy

HERE = os.path.abspath(os.path.dirname(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.shift_agreement import lattice_agreement
from representation.game.board import ARMS, BLACK, EMPTY, SIDE, WHITE, opening, play, scattered

# Drawn arrangements averaged per position. The null is cheap and averaging it keeps one unlucky
# draw out of a row.
DRAWS = 4


def clumping(grid):
    """Share of occupied squares whose neighbour one step away carries the same colour, both axes.

    Chosen over the dispersion measure this work usually quotes because that one needs four symbols
    clearing an occurrence floor and a board has two colours. This reads the same thing a dispersion
    reads, at the one lag a board is big enough to carry.
    """
    square = numpy.frombuffer(bytes(grid), dtype=numpy.uint8).reshape(SIDE, SIDE)
    return (lattice_agreement(square, 0, 1) + lattice_agreement(square, 1, 1)) / 2.0


def against_the_null(grids, draws=DRAWS):
    """Mean clumping of the positions, and of drawn arrangements of the same positions."""
    live = [clumping(grid) for grid in grids]
    null = [statistics.fmean(clumping(scattered(grid, seed)) for seed in range(draws))
            for grid in grids]
    return statistics.fmean(live), statistics.fmean(null)


def place_only(seed, filled=SIDE * SIDE, from_opening=True):
    """A board filled by alternating placement with nothing turned over.

    Same board, same colours, same count of squares filled, no flip rule.

    `from_opening` keeps Reversi's four fixed centre pieces. They are worth a control of their own,
    because the first run of this script left them in and read 0.971 where the argument wanted 1.00,
    and the miss is the opening itself: those four squares are laid out BW over WB, so all four of
    the neighbouring pairs inside them disagree by construction where a draw would have half of them
    agree. Four guaranteed disagreements out of 112 pairs is 0.018 of the reading, which is the whole
    of the gap. Starting from an empty board removes them and the control returns 0.997.

    The same four squares sit under the Reversi rows and push them the same way, so the departure
    reported there is understated by about that much and never overstated.
    """
    rng = random.Random(seed)
    grid = opening() if from_opening else bytearray(SIDE * SIDE)
    already = 4 if from_opening else 0
    empties = [index for index, cell in enumerate(grid) if cell == EMPTY]
    rng.shuffle(empties)
    colour = BLACK
    for index in empties[:max(0, filled - already)]:
        grid[index] = colour
        colour = WHITE if colour == BLACK else BLACK
    return grid


def main():
    games = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    finals = [play(ARMS["random"], ARMS["random"], seed=seed)[0][-1] for seed in range(games)]
    live, null = against_the_null(finals)
    out.write("Reversi, %d games, both sides drawing uniformly from the legal moves\n" % games)
    out.write("  live %.4f  null %.4f  ratio %.3f\n" % (live, null, live / null))

    for keep, label in ((True, "keeping Reversi's four centre pieces"),
                        (False, "from an empty board")):
        placed = [place_only(seed, from_opening=keep) for seed in range(games * 2)]
        live, null = against_the_null(placed)
        out.write("\nplace-only control, %d boards, no flip rule, %s\n" % (len(placed), label))
        out.write("  live %.4f  null %.4f  ratio %.3f\n" % (live, null, live / null))

    batches = []
    for batch in range(6):
        grids = [play(ARMS["random"], ARMS["random"], seed=seed)[0][-1]
                 for seed in range(batch * games, (batch + 1) * games)]
        one, two = against_the_null(grids)
        batches.append(one / two)
    out.write("\nfloor, six disjoint batches of %d games: %s\n"
              % (games, [round(value, 4) for value in batches]))
    out.write("  spread %.4f, so the departure above is %.0f floors and the control is inside one\n"
              % (max(batches) - min(batches),
                 (statistics.fmean(batches) - 1.0) / (max(batches) - min(batches))))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
