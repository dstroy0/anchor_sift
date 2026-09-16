#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-6-001
#
# Two games whose losing positions somebody else settled, read off grids generated without either
# answer, and compared against the published one.
#
#   Usage:  python examples/games/6_oracle/bouton_and_wythoff.py [heap size]
#
# The crystallography chapter's argument is that a memoryless control can only show an instrument
# does not invent structure, and that showing it finds structure that is there needs an answer from
# outside. A crystal supplies one at the cost of a database and a fetch. These two games supply one
# for the price of the arithmetic, and the answers are older: Bouton's is 1901 and Wythoff's is 1907.
#
# The two are here together because they are the same shape of game with opposite answers. Nim's
# losing positions carry a structure a shift can find. Wythoff's carry one it cannot, because the
# positions sit on a line of irrational slope and nothing on such a line ever repeats. A reader that
# reports structure on both is reporting an artefact on one of them, and this is the pair that says
# which.
#
# Neither grid is generated from the theorem it is checked against. Wythoff's is played out by the
# minimum excludant recursion and Nim's is the only one built from its closed form, which is stated
# in the module and is the reason its rows are reported as a count and not as a recovery.

import io
import os
import statistics
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.game.combinatorial import nim_losses, wythoff_losses, wythoff_pairs

# The golden ratio, which is the answer the Wythoff half is scored against and is not computed from
# anything this work measured.
PHI = (1.0 + (5.0 ** 0.5)) / 2.0


def losses_per_line(grid, heaps, heap):
    """Losing positions on each line along the first axis.

    Bouton's theorem says a position loses exactly when the heap sizes exclusive or to zero. Fix
    every heap but one and exactly one size of the free heap makes that total zero, so every line
    holds exactly one losing position. That consequence is readable off the grid by counting, with
    no exclusive or performed by the reader.
    """
    counts = []
    for rest in range(heap ** (heaps - 1)):
        found = 0
        for size in range(heap):
            if grid[size + (rest * heap)] == 0:
                found += 1
        counts.append(found)
    return counts


def main():
    heap = int(sys.argv[1]) if len(sys.argv) > 1 else 64
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    out.write("Nim, losing positions per axis line (Bouton 1901)\n")
    for heaps, side in ((2, heap), (3, heap), (4, min(heap, 32))):
        grid = nim_losses(heaps, side)
        counts = losses_per_line(grid, heaps, side)
        density = sum(1 for cell in grid if cell == 0) / float(len(grid))
        out.write("  %d heaps of %-3d  %6d lines  counts seen %s  loss density %.5f\n"
                  % (heaps, side, len(counts), sorted(set(counts)), density))
    out.write("  a set of the same density scattered over the same cells puts exactly one in a line\n"
              "  of %d with probability %.3f, so all-ones over %d lines is not what a scatter gives\n"
              % (heap, ((1.0 - (1.0 / heap)) ** (heap - 1)), heap ** 2))

    out.write("\nWythoff, losing positions (Wythoff 1907)\n")
    for side in (200, 400, 800):
        grid = wythoff_losses(side)
        upper = sorted([(left, right) for left in range(side) for right in range(side)
                        if grid[(left * side) + right] == 0 and left < right])
        published = wythoff_pairs(len(upper) + 1)[1:]
        agree = all(upper[index] == published[index] for index in range(len(upper)))
        first = [right - left for left, right in upper[:12]]
        estimate = upper[-1][0] / float(len(upper))
        out.write("  %3d square  %3d positions  played-out grid equals the 1907 closed form: %s\n"
                  % (side, len(upper), agree))
        out.write("              second minus first, first twelve: %s\n" % first)
        out.write("              a_n / n = %.6f against phi = %.6f, relative error %.2e\n"
                  % (estimate, PHI, abs(estimate - PHI) / PHI))

    gaps = []
    grid = wythoff_losses(800)
    firsts = sorted(left for left in range(800) for right in range(800)
                    if grid[(left * 800) + right] == 0 and left < right)
    gaps = [firsts[index] - firsts[index - 1] for index in range(1, len(firsts))]
    ones = gaps.count(1)
    twos = gaps.count(2)
    out.write("  gaps between successive first coordinates take %s, in ratio %.5f against phi %.5f\n"
              % (sorted(set(gaps)), twos / float(ones), PHI))
    out.write("  that word is Sturmian and has no period. What the period detector does with it is\n"
              "  examples/games/6_oracle/sturmian_convergents.py, and it is not nothing.\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
