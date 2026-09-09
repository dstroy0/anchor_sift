#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-5-001
#
# The anchor cascade on a lattice, where the histogram bound should fail hardest.
#
#   Usage:  python examples/crystallography/5_sift/lattice_breaks_the_product_rule.py [entries]
#
# An anchor is a condition copied out of the pattern, so any position genuinely holding the pattern
# satisfies every anchor and correctness cannot turn on which anchors were chosen. What the choice
# moves is how many false candidates survive, and the usual estimate of that is the product of the
# anchors' own rates: three anchors on elements occurring at half the sites each should leave an
# eighth of the positions standing.
#
# That estimate assumes the anchors are positioned independently. A lattice is the arrangement where
# they are least independent of anything in nature, so it is the sharpest available test of how far
# the estimate can be out. src/engine/c/bench/bench_coherence.c measures the same failure on a
# synthetic period. This does it on published cells.
#
# A crystal is the single case here where the cascade needs no tolerance. A protein is a cloud of real
# valued coordinates, so two occurrences of one motif never land on identical offsets and
# examples/proteins/5_sift extends a tolerance of one voxel in each direction to get any match at
# all. Here the points are exact integers and a displacement either lands on an occupied place or
# does not. Proposition 1 is tested in the form it was stated in, with nothing relaxed.
#
# A needle is built from points the arrangement actually contains, near a seed, so the pattern is a
# shape the domain holds and not an arbitrary offset into empty space.

import io
import os
import random
import statistics
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation import exact  # noqa: E402
from representation.structure import crystal  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")

# Anchors per needle, and needles drawn per structure.
ANCHORS = 3
TRIALS = 40

# Held, which keeps a rerun reporting the same draw.
SEED = 0xC0FFEE


def cascade(points, draw):
    """Survivor counts against the product rule prediction, one ratio per needle drawn.

    An alignment survives when every displacement lands on a place holding the element the needle
    asks for. The comparison is equality between exact integers, so no near miss is admitted.
    """
    places = dict(points)
    keys = list(places)
    if len(keys) < (ANCHORS * 4):
        return []

    counts = {}
    for value in places.values():
        counts[value] = counts.get(value, 0) + 1
    total = float(len(keys))

    # Displacements are drawn from points inside this reach of the seed, measured on the widest
    # axis, keeping a needle a local shape instead of spanning the whole tiling.
    lows = [min(key[axis] for key in keys) for axis in range(3)]
    highs = [max(key[axis] for key in keys) for axis in range(3)]
    reach = max(highs[axis] - lows[axis] for axis in range(3)) // 3

    ratios = []
    for _ in range(TRIALS):
        seed = keys[draw.randrange(len(keys))]
        near = [key for key in keys
                if 0 < max(abs(key[axis] - seed[axis]) for axis in range(3)) <= reach]
        if len(near) < ANCHORS:
            continue
        picked = draw.sample(near, ANCHORS)
        offsets = [tuple(point[axis] - seed[axis] for axis in range(3)) for point in picked]
        wanted = [places[point] for point in picked]

        # Only positions where every displacement still lands inside the tiled extent are asked.
        # A needle running off the edge of a finite tiling cannot survive there whatever the
        # arrangement is, and counting those refusals reads the boundary as a failure of the
        # pattern. Measured that way the ratio came to 1.06 and said nothing about the lattice.
        askable = [key for key in keys
                   if all(lows[axis] <= (key[axis] + offset[axis]) <= highs[axis]
                          for offset in offsets for axis in range(3))]
        if len(askable) < 2:
            continue

        predicted = float(len(askable))
        for value in wanted:
            predicted *= counts[value] / total
        if predicted <= 0.0:
            continue

        survivors = 0
        for key in askable:
            for offset, value in zip(offsets, wanted):
                moved = (key[0] + offset[0], key[1] + offset[1], key[2] + offset[2])
                if places.get(moved) != value:
                    break
            else:
                survivors += 1
        # The seed itself always survives, so only what stands beyond it is evidence.
        ratios.append(max(survivors - 1, 0) / predicted)
    return ratios


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(CACHE):
        out.write("\n  nothing cached under build/cod. Run the oracle to fill it.\n\n")
        out.flush()
        return 1

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 12
    draw = random.Random(SEED)

    out.write("\n  Predicted before measuring: survivors run far above the product of the anchor\n")
    out.write("  rates, because a lattice positions its anchors as far from independently as\n")
    out.write("  anything does. A ratio near one would mean the estimate holds here.\n\n")
    out.write("  %-12s %-8s %-9s %-11s %-11s %s\n"
              % ("entry", "points", "elements", "median", "worst", "needles"))

    read = 0
    every = []
    for name in sorted(os.listdir(CACHE)):
        if read >= limit:
            break
        if not name.endswith(".cif"):
            continue
        with io.open(os.path.join(CACHE, name), encoding="utf-8", errors="replace") as handle:
            points, _ = crystal.exact_points(handle.read())
        if points is None:
            continue

        ratios = cascade(points, draw)
        if not ratios:
            continue
        read += 1
        every.extend(ratios)
        out.write("  %-12s %-8d %-9d %-11.2f %-11.2f %d\n"
                  % (name[:-4], len(points), len({value for _, value in points}),
                     statistics.median(ratios), max(ratios), len(ratios)))
        out.flush()

    if not every:
        out.write("\n  no usable needles\n\n")
        out.flush()
        return 1

    out.write("\n  %d structures, %d needles\n" % (read, len(every)))
    out.write("  median survivors over predicted: %.2f\n" % statistics.median(every))
    out.write("  the product rule is out by that factor on a published lattice, and it is a\n")
    out.write("  necessary condition either way: everything holding the pattern still survives\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
