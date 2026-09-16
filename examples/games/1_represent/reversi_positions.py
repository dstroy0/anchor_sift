#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-1-001
#
# A played board written as points carrying values, printed next to the same pieces in a drawn order.
#
#   Usage:  python examples/games/1_represent/reversi_positions.py [seed] [arm] [arm]
#
# The representation decision worth stating is what happens to an empty square. A board part way
# through a game is mostly empty, and giving emptiness a symbol of its own puts the game's clock
# into the histogram, where any measure reading counts will find it and report how far along the
# game was. Every measurement in this subject that reads values drops the empty squares. The one
# that reads the grid's shape keeps them, because a hole in a row is part of the shape.
#
# The second decision is the flattening. A board is two dimensional and a sequence is not, so
# reading one row major spends the second axis. The partition stage is where that is paid for.

import io
import os
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.game.board import ARMS, EMPTY, SIDE, occupied_seats, play, scattered

FACES = {EMPTY: ".", 1: "B", 2: "W"}


def rows(grid):
    return ["".join(FACES[grid[(row * SIDE) + column]] for column in range(SIDE))
            for row in range(SIDE)]


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    black = sys.argv[2] if len(sys.argv) > 2 else "random"
    white = sys.argv[3] if len(sys.argv) > 3 else "random"
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    seen, counts = play(ARMS[black], ARMS[white], seed=seed)
    final = seen[-1]
    drawn = scattered(final, seed)

    out.write("%s as black, %s as white, seed %d: %d positions, final %d to %d\n\n"
              % (black, white, seed, len(seen), counts[0], counts[1]))
    out.write("  %-10s   %-10s\n" % ("played", "same pieces drawn"))
    for left, right in zip(rows(final), rows(drawn)):
        out.write("  %-10s   %-10s\n" % (left, right))

    out.write("\noccupied squares: %d, and the two boards hold the same count of each colour: %s\n"
              % (len(occupied_seats(final)),
                 sorted(occupied_seats(final)) == sorted(occupied_seats(drawn))))
    out.write("Everything the rules did is in the difference between those two columns, and nothing\n"
              "that survives into the histogram is.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
