#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-2-001
#
# What a flattened board gives back when it is asked for its own width, and when that answer is the
# width.
#
#   Usage:  python examples/games/2_partition/board_width.py [games]
#
# Reading a grid row major spends its second axis, and the partition stage is where that is paid
# for. The claim being tested is the one the picture work already makes: an image read as a byte
# sequence returns its own width. A board is the same shape of object with a width nobody has to
# look up.
#
# Reversi returns 8, read across the rows and read down the columns, on both a weak arm and a strong
# one, at a margin seven to fifteen times what a scatter of the same pieces reaches.
#
# Then the second half, which is where the claim stops. A flattened grid does not carry one period.
# It carries the repeat along each of its axes at once, at lags of the width and of whatever repeats
# inside a row, and a detector returning a single number returns whichever family scored higher. A
# Grundy grid of a two-heap subtraction game has a short period along the row, and on 315 of those
# the flattened answer is the width on 108, the width off by one on 68, the game's own Grundy period
# on 96, and a combination on the remaining 43.
#
# Reversi is in the first group because nothing repeats along a Reversi row. That is a property of
# the corpus and not of the reader, and a reader handed a grid with structure on both axes has no
# way to know which number it returned. The rule that comes out is to read the axes separately where
# the caller knows there are two, and to treat a single flattened period as ambiguous where it does
# not.

import io
import itertools
import os
import random
import sys
from collections import Counter

HERE = os.path.abspath(os.path.dirname(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.periodicity import sequence_period
from representation.game.board import (ARMS, SIDE, play, scattered, seats_column_major,
                                       seats_row_major)
from representation.game.combinatorial import grundy_subtraction, subtraction_period

# Widths the two-heap grids are laid out at.
WIDTHS = (12, 16, 20, 24, 32)


def two_heap(moves, width):
    """Grundy values of two independent heaps under one move set, as a square grid.

    The value of a sum of independent games is the exclusive or of their values, which is the
    Sprague-Grundy theorem and is not something measured here.
    """
    values = grundy_subtraction(moves, width)
    return [values[left] ^ values[right] for left in range(width) for right in range(width)]


def main():
    games = int(sys.argv[1]) if len(sys.argv) > 1 else 120
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    out.write("Reversi, %d final positions concatenated, true width %d\n" % (games, SIDE))
    for arm in ("random", "corner"):
        readings = {"row major": bytearray(), "column major": bytearray(),
                    "scattered null": bytearray()}
        for seed in range(games):
            final = play(ARMS[arm], ARMS[arm], seed=seed)[0][-1]
            readings["row major"] += seats_row_major(final)
            readings["column major"] += seats_column_major(final)
            readings["scattered null"] += seats_row_major(scattered(final, seed))
        for label, data in readings.items():
            period, margin = sequence_period(list(data), longest=24)
            out.write("  %-7s %-16s period %-5s margin %s\n"
                      % (arm, label, period, "none" if margin is None else "%.4f" % margin))

    out.write("\ntwo-heap subtraction grids, laid out at a known width\n")
    games_swept = [moves for count in range(1, 4)
                   for moves in itertools.combinations(range(1, 8), count)]
    tally = Counter()
    for moves in games_swept:
        own, _ = subtraction_period(grundy_subtraction(moves, 512))
        for width in WIDTHS:
            period, _ = sequence_period(two_heap(moves, width), longest=2 * width)
            if period == width:
                tally["the width"] += 1
            elif period in (width - 1, width + 1):
                tally["the width off by one, which is diagonal content"] += 1
            elif own and ((period % own == 0) or (own % period == 0)):
                tally["the game's own Grundy period"] += 1
            else:
                tally["a combination of the two"] += 1
    total = sum(tally.values())
    for label, count in tally.most_common():
        out.write("  %-46s %3d of %d\n" % (label, count, total))

    hits = 0
    for moves in games_swept[:20]:
        for width in WIDTHS:
            grid = two_heap(moves, width)
            random.Random(width).shuffle(grid)
            if sequence_period(grid, longest=2 * width)[0] == width:
                hits += 1
    out.write("  the same grids shuffled return the width on %d of %d, which is the chance rate\n"
              % (hits, 20 * len(WIDTHS)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
