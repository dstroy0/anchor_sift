#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-3-001
#
# The background a cell reaches with its arrangement deleted, read both ways.
#
#   Usage:  python examples/crystallography/3_reference/what_a_grid_invents.py [how many entries]
#
# A reference is the most a corpus reaches once the thing being looked for is removed from it, built
# out of the corpus alone. Which property is deleted decides the question, and two are deleted here
# separately.
#
# Scattering the points keeps every element and destroys every position. Shuffling the values keeps
# every position and destroys which element sits where. A crystal is ordered in both, and each null
# says how much of the reading rests on the one it took away.
#
# The exact reading returns zero on both deletions. Scattered points never agree, because two
# arbitrary positions on a continuum are never equal and no tolerance is extended to them. Shuffled
# elements never agree either, because a coordinate carries the whole arrangement standing at it and
# a permutation breaks all of it at once. Against a live count of 6 planes, both backgrounds are 0.
#
# The grid returns neither. Measured on three entries it reads 0.79 live, 0.003 scattered, and 0.39
# with the elements shuffled. The scattered figure is small and the shuffled one is not, and the
# shuffled one is the floor that matters. A cell holds two or three elements, and a permutation of
# them agrees at about one in k by counting alone. A share of voxels carrying the same code is most
# of what the grid was reporting. Half its live reading is a number a shuffle also reaches.
#
# That floor was never subtracted from any grid result in this work. The exact reading needs no
# subtraction, since there is nothing under it to subtract.

import io
import os
import random
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

import numpy  # noqa: E402
from measure.shift_agreement import exact_agreement, lattice_agreement  # noqa: E402
from representation import exact  # noqa: E402
from representation.structure import crystal  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")

# Held, which keeps a rerun reporting the same background. The draw belongs to the universe and not
# to the run.
SEED = 0x51F7


def best_exact(points, axis):
    """The most any lag agrees with, along one axis, over the whole difference set.

    Every difference between two occupied coordinates is a candidate, so nothing here bounds what
    the background is allowed to reach.
    """
    seen = exact.along(points, axis)
    if len(seen) < 3:
        return 0, 0
    ordered = sorted(seen)
    best = 0
    for at, first in enumerate(ordered):
        for second in ordered[at + 1:]:
            best = max(best, exact_agreement(seen, second - first))
    return best, len(seen)


def scattered(points, draw):
    """The same elements over positions drawn across the same extent. Deletes the arrangement."""
    lows = [min(place[axis] for place, _ in points) for axis in range(3)]
    highs = [max(place[axis] for place, _ in points) for axis in range(3)]
    return [(tuple(draw.randint(lows[axis], highs[axis]) for axis in range(3)), value)
            for _, value in points]


def reassigned(points, draw):
    """The same positions carrying a permutation of the elements. Deletes the composition."""
    values = [value for _, value in points]
    draw.shuffle(values)
    return [(place, value) for (place, _), value in zip(points, values)]


def grid_arm(cell, sites, draw):
    """Best agreement on the voxel grid, live and with the same two properties deleted."""
    tiles = crystal.tiles_for(cell)
    if tiles is None:
        return None
    grid, _ = crystal.voxel_grid(cell, sites, crystal.VOXEL, tiles)
    if grid is None:
        return None

    def peak(volume):
        # Axis a only. The exact arm reads that axis too, which keeps the two columns answering one
        # question. A full volume comparison at every lag makes this the slow arm.
        reach = min(int((cell["a"] / crystal.VOXEL) * 2.0) + 6, volume.shape[0] - 1)
        found = 0.0
        for lag in range(1, max(2, reach)):
            found = max(found, lattice_agreement(volume, 0, lag))
        return found

    live = peak(grid)

    # Scattering on the grid means the same count of occupied voxels placed anywhere in it. That
    # matches the deletion the exact arm performs, and the grid can express no other.
    #
    # Drawn with replacement and deduplicated. Drawing without replacement asks numpy for a
    # permutation of every voxel in the volume, which is thirty two million entries to place about a
    # thousand points, and it does not finish in any useful time.
    occupied = numpy.argwhere(grid != 0)
    values = grid[grid != 0]
    empty = numpy.zeros_like(grid)
    draw_rng = numpy.random.default_rng(SEED)
    flat = numpy.unique(draw_rng.integers(0, empty.size, len(values)))
    numpy.put(empty, flat, values[:len(flat)])
    scatter = peak(empty)

    shuffled = grid.copy()
    held = shuffled[shuffled != 0]
    numpy.random.default_rng(SEED).shuffle(held)
    shuffled[shuffled != 0] = held
    reassign = peak(shuffled)
    return live, scatter, reassign, len(occupied)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(CACHE):
        out.write("\n  nothing cached under build/cod. Run the oracle to fill it.\n\n")
        out.flush()
        return 1

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    draw = random.Random(SEED)

    out.write("\n  Agreement reached with the arrangement deleted, per entry. Exact counts are\n")
    out.write("  planes that match; grid shares are the fraction of occupied voxels that match.\n\n")
    out.write("  %-12s %-7s %-24s %s\n"
              % ("entry", "planes", "exact: live scatter shuffle", "grid: live scatter shuffle"))

    read = 0
    exact_scatter_peak = 0
    grid_scatter_total = 0.0
    grid_entries = 0
    for name in sorted(os.listdir(CACHE)):
        if read >= limit:
            break
        if not name.endswith(".cif"):
            continue
        with io.open(os.path.join(CACHE, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        points, _ = crystal.exact_points(text)
        if points is None:
            continue
        read += 1

        live, planes = best_exact(points, 0)
        scatter, _ = best_exact(scattered(points, draw), 0)
        reassign, _ = best_exact(reassigned(points, draw), 0)
        exact_scatter_peak = max(exact_scatter_peak, scatter)

        cell, sites = crystal.parse_cif(text)
        arm = grid_arm(cell, sites, draw) if cell else None
        if arm is None:
            shown = "cap refused the cell"
        else:
            grid_live, grid_scatter, grid_reassign, _ = arm
            grid_scatter_total += grid_scatter
            grid_entries += 1
            shown = "%.3f      %.3f      %.3f" % (grid_live, grid_scatter, grid_reassign)

        out.write("  %-12s %-7d %-6d %-8d %-9d %s\n"
                  % (name[:-4], planes, live, scatter, reassign, shown))
        out.flush()

    out.write("\n  %d entries read\n" % read)
    out.write("  exact, scattered points: the most any lag reached anywhere was %d\n"
              % exact_scatter_peak)
    if grid_entries:
        out.write("  grid, scattered points: mean best agreement %.3f over %d entries\n"
                  % (grid_scatter_total / grid_entries, grid_entries))
        out.write("  that share is the floor the grid puts under every reading taken on it\n")
    out.write("\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
