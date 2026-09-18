#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CEL-4-001
#
# The level count swept, because it is this reader's voxel and nothing else set it.
#
#   Usage:  python examples/cell_tracking/4_measure/what_the_levels_buy.py
#
# WHERE THIS QUESTION COMES FROM. examples/crystallography/2_partition measures two partitions of
# the same cell and names what each one decides before anything is measured. The grid arm sets a
# voxel of 0.25 angstroms and carries a mean absolute error of 0.0124 with a bias of -0.0067 that
# the reading could not account for. The exact arm carries sites as integers at 1e-1024 angstroms,
# sets no smallest difference, and returns the published edge on 453 of 453 axes as an equality
# between integers. That file's own summary of the split is that the voxel was buying error.
#
# Every file in examples/cell_tracking quantizes to 32 levels. Nothing chose 32 but this author, it
# is the same kind of bound as the voxel, and it has never been swept.
#
# WHY THE ANSWER IS NOT OBVIOUS IN EITHER DIRECTION, AND WHY THAT MAKES IT WORTH RUNNING. The
# agreement measure is an exact equality between two positions' values, which is what Section 2.1 of
# the construction permits and all it permits. Raising the level count makes each comparison finer
# and ought to carry more. It also makes an exact match rarer, and at enough levels two samples of a
# real field never carry the same value at all, which is precisely the failure theory/workbook
# records on proteins: coordinates voxelised at two angstroms and required to agree exactly, where
# two occurrences of one motif never land on identical offsets, because nature does not supply exact
# repeats. So the grid buys error at one end and the exactness buys emptiness at the other.
#
# If the error falls all the way to the top of the sweep, the quantization was buying error here as
# it was there, and the level count should come off. If it falls and then rises, there is a real
# optimum, and what sets it is the thing to name. If it is flat, 32 was harmless and the sweep says
# so, which is worth as much and costs the same.

import io
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "2_partition"))

ROOT = HERE
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from what_a_pixel_costs import SEED, TRUTHS, recover, shifted  # noqa: E402
from where_the_floor_comes_from import field  # noqa: E402

# Swept over eleven doublings. The top is past any microscope's bit depth and is included so the
# sweep runs off the end of what a real image could carry, rather than stopping where this author
# guessed it would stop mattering.
LEVELS = (4, 8, 16, 32, 64, 128, 256, 1024, 4096, 16384, 65536)

WIDTH = 4.0


def to_levels(canvas, levels):
    """The field as integer levels, scaled to its own range. `levels` is the swept quantity."""
    low = float(canvas.min())
    high = float(canvas.max())
    if high <= low:
        return numpy.zeros(canvas.shape, dtype=numpy.int64)
    scaled = (canvas - low) / (high - low)
    return numpy.clip((scaled * levels).astype(numpy.int64), 0, levels - 1)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    canvas, blobs = field(numpy.random.default_rng(SEED), WIDTH)

    out.write("  The level count swept. It is this reader's voxel and nothing else set it.\n")
    out.write("  %d blobs %.1f px wide, mean over %d displacements.\n\n"
              % (blobs, WIDTH, len(TRUTHS)))
    out.write("  %-10s %-12s %-12s %s\n" % ("levels", "mean error", "worst error", "lit share"))

    rows = []
    for levels in LEVELS:
        first = to_levels(canvas, levels)
        errors = []
        for truth in TRUTHS:
            second = to_levels(shifted(canvas, truth, axis=0), levels)
            lag, fraction, _ = recover(first, second, axis=0, reach=8)
            errors.append(abs((lag + fraction) - truth))
        # How much of the field is above the bottom level. As the levels multiply, the background
        # spreads across several of them and stops being one value, which changes what `occupied`
        # means without anyone deciding to change it.
        lit = float((first > 0).sum()) / float(first.size)
        mean = float(numpy.mean(errors))
        rows.append((levels, mean))
        out.write("  %-10d %-12.4f %-12.4f %.4f\n" % (levels, mean, max(errors), lit))

    best = min(rows, key=lambda row: row[1])
    first_error = rows[0][1]
    last_error = rows[-1][1]
    out.write("\n  best at %d levels, %.4f px.\n" % (best[0], best[1]))
    out.write("  coarsest %d levels: %.4f px. finest %d levels: %.4f px.\n"
              % (rows[0][0], first_error, rows[-1][0], last_error))

    if best[0] == rows[-1][0]:
        out.write("\n  The error is still falling at the top of the sweep. The total belongs to\n")
        out.write("  the ceiling and not to the method. The level count comes off, the way the\n")
        out.write("  voxel came off the crystal reading.\n")
    elif best[0] == rows[0][0]:
        out.write("\n  The coarsest slice wins outright, which nothing here predicted and nothing\n")
        out.write("  here explains. Reported and not accounted for.\n")
    else:
        out.write("\n  There is an optimum inside the sweep and both ends are worse than it. The\n")
        out.write("  grid buys error below it and exact matching runs out of matches above it,\n")
        out.write("  which is the protein failure and the crystal voxel meeting in one curve.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
