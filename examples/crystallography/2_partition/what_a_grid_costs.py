#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-2-001
#
# Two partitions of the same cell, and what each one decides before anything is measured.
#
#   Usage:  python examples/crystallography/2_partition/what_a_grid_costs.py [how many entries]
#
# A partition is the unit and the scale the points are read at, and a reading is undetermined until
# it is fixed. This subject had two of them fixed inside its reader, where neither could be seen.
#
# The grid partition sets a voxel of 0.25 angstroms and caps the tiled side at 320 voxels. The first
# decides the smallest difference the reading can hold. The second decides which cells can be read at
# all, because a dense grid grows as the cube of its side and a large cell will not fit under the cap.
#
# The exact partition sets neither. Points are integers at 1e-1024 angstroms and only the occupied
# places are held. A large cell then costs what its sites cost, and nothing decides a smallest
# difference.
#
# Both arms are swept here against the published edges, and the scale is swept on top of the exact
# arm to show where a scale stops mattering. That sweep is the estimated form of fixing a partition:
# take the value where the answer stops moving. It stops moving early, and the reason is in the
# arithmetic and not in the scale. One multiplication takes a fraction's decimal places plus an
# edge's, which is about eleven, and every scale above that carries the same answer.
#
# What that leaves is the honest split between the two bounds. The voxel was buying error. The scale
# was buying headroom for paths with more arithmetic in them than this one has.

import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.shift_agreement import recover_exact_period, recover_lattice_period  # noqa: E402
from representation import exact  # noqa: E402
from representation.structure import crystal  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")

# Scales the exact arm is swept over. The smallest sits below what a deposit carries, and has to
# raise instead of rounding.
SCALES = (4, 8, 16, 64, 256, 1024, 4096)


def grid_arm(text):
    """Every axis of one entry read on the voxel grid, as (published, recovered) in angstroms."""
    cell, sites = crystal.parse_cif(text)
    if (cell is None) or (len(sites) < 2):
        return None
    tiles = crystal.tiles_for(cell)
    if tiles is None:
        # The cap refused this cell. A refusal is part of what the partition costs, so it is
        # reported and not skipped past.
        return []
    grid, _ = crystal.voxel_grid(cell, sites, crystal.VOXEL, tiles)
    if grid is None:
        return []

    found = []
    for axis, name in enumerate(("a", "b", "c")):
        reach = min(int((cell[name] / crystal.VOXEL) * 2.0) + 6, grid.shape[axis] - 1)
        if reach < 4:
            continue
        lag, fraction, _ = recover_lattice_period(grid, axis, reach)
        if lag is None:
            continue
        found.append((cell[name], (lag + (fraction or 0.0)) * crystal.VOXEL))
    return found


def exact_arm(text, digits):
    """Every axis of one entry read exactly at `digits`, as (published, recovered) integers.

    Returns None where the deposit will not fit the scale. A small scale would have rounded through
    that case instead of raising.
    """
    try:
        points, published = crystal.exact_points(text, digits=digits)
    except exact.WillNotFit:
        return None
    if points is None:
        return []
    found = []
    for axis in range(3):
        period, _ = recover_exact_period(exact.along(points, axis))
        if period is None:
            continue
        found.append((published[axis], period))
    return found


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(CACHE):
        out.write("\n  nothing cached under build/cod. Run the oracle to fill it.\n\n")
        out.flush()
        return 1

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 60
    held = []
    for name in sorted(os.listdir(CACHE)):
        if len(held) >= limit:
            break
        if not name.endswith(".cif"):
            continue
        with io.open(os.path.join(CACHE, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        if crystal.cell_text(text) and crystal.right_angled(crystal.cell_text(text)):
            held.append(text)

    out.write("\n  %d right angled entries from the cache\n" % len(held))

    out.write("\n  THE VOXEL. What the reading can tell apart, set at 0.25 angstroms here.\n\n")
    axes = 0
    inside = 0
    landed = 0
    total = 0.0
    worst = 0.0
    refused = 0
    for text in held:
        arm = grid_arm(text)
        if arm is None:
            continue
        if not arm:
            refused += 1
            continue
        for published, recovered in arm:
            axes += 1
            error = abs(recovered - published)
            total += error
            worst = max(worst, error)
            if error <= crystal.VOXEL:
                inside += 1
            if error == 0.0:
                landed += 1
    if axes:
        out.write("    %d axes, %d inside one voxel, mean absolute error %.4f, worst %.4f\n"
                  % (axes, inside, total / axes, worst))
        out.write("    %d of %d land on the published edge exactly\n" % (landed, axes))
    out.write("    %d entries the 320 voxel cap refused outright\n" % refused)

    out.write("\n  THE SCALE. What an exact reading is carried at, swept.\n\n")
    out.write("    %8s %7s %7s %9s %s\n" % ("digits", "axes", "wrong", "seconds", "refused"))
    for digits in SCALES:
        started = time.time()
        axes = 0
        wrong = 0
        raised = 0
        for text in held:
            arm = exact_arm(text, digits)
            if arm is None:
                raised += 1
                continue
            for published, recovered in arm:
                axes += 1
                if recovered != published:
                    wrong += 1
        out.write("    %8d %7d %7d %9.2f %d\n"
                  % (digits, axes, wrong, time.time() - started, raised))

    out.write("\n  A scale too small raises and is counted under refused. It never rounds, so no\n")
    out.write("  row above is a quiet loss. The voxel had no such column: it rounded every site.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
