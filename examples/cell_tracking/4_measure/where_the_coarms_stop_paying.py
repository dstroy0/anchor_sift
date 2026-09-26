#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CEL-4-002
#
# The co-arm count swept instead of chosen, and the lag reach with it.
#
#   Usage:  python examples/cell_tracking/4_measure/where_the_coarms_stop_paying.py
#
# WHY THIS FILE EXISTS. CEL-3-001 cuts one field into sixteen co-arms and reads 0.0295 px where the
# whole field read 0.1041 px. Sixteen was chosen by this author on no evidence, the defect
# theory/workbooks/anchor_sift records ten separate times in one sitting: a bound is chosen because something has
# to be chosen, the measurement returns a number, and the number describes the choice. A dimension
# assigned per domain returned heights instead of widths. A sum stopped at 24 bits was still
# climbing at 64. A band fixed at eight levels read a picture spread over 160 of them as having no
# structure. Every one of those had to come back off, and the entry ends by saying what works is not
# choosing better but sweeping the quantity and letting the data say where it stops mattering.
#
# So sixteen is swept here, and so is the lag reach, which was also chosen and never justified.
#
# WHAT A SWEEP CAN SHOW THAT A POINT CANNOT. Three outcomes and they are not the same finding. The
# error may fall and flatten, which names a working count and makes the figure quotable at it. It
# may fall and keep falling to the edge of the table, in which case the total belongs to the edge
# and not to the method, which is how the bit-volume divergence in theory/workbooks/anchor_sift was found at all.
# Or it may fall and then rise, which locates a real optimum and says what sets it.
#
# WHAT SETS THE FAR END. Co-arms are cut from one field. More of them means smaller ones, and a
# tile eventually holds too few features to carry a reading. That turnover is a property of the
# field and the feature width together and is not imposed here. It is what the sweep is for.

import io
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "2_partition"))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "3_reference"))

ROOT = HERE
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(
    os.path.join(ROOT, "src", "engine")
):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from what_a_pixel_costs import (
    SEED,
    SIDE,
    TRUTHS,
    recover,
    shifted,
    to_levels,
)  # noqa: E402
from where_the_floor_comes_from import field  # noqa: E402

# Swept, not chosen. The far end puts eight pixels in a tile, which is two feature widths, and the
# sweep is expected to have failed before it.
COUNTS = (1, 2, 4, 8, 16, 32)

# Also swept. The lag reach was set to 8 and then to 12 in two earlier files with no reason given
# for either, and a reach below the true displacement cannot return it.
REACHES = (5, 8, 16, 32)

WIDTH = 4.0
TRUTH = 3.4


def arms(canvas, count, reach, axis, truth):
    """Every co-arm's reading at one tile count and one reach."""
    first = to_levels(canvas)
    second = to_levels(shifted(canvas, truth, axis=0)) if truth else to_levels(canvas)
    step = canvas.shape[0] // count
    out = []
    for row in range(count):
        for column in range(count):
            piece = (
                slice(row * step, (row + 1) * step),
                slice(column * step, (column + 1) * step),
            )
            lag, fraction, _ = recover(first[piece], second[piece], axis, reach=reach)
            out.append(lag + fraction)
    return out


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    canvas, blobs = field(numpy.random.default_rng(SEED), WIDTH)

    out.write("  Co-arm count and lag reach swept and not chosen.\n")
    out.write(
        "  %dx%d field, %d blobs %.1f px wide, true displacement %.3f px.\n\n"
        % (SIDE, SIDE, blobs, WIDTH, TRUTH)
    )
    out.write(
        "  %-8s %-8s %-8s %-11s %-11s %s\n"
        % ("arms", "tile px", "reach", "mean", "error", "spread")
    )

    best = None
    for count in COUNTS:
        tile = SIDE // count
        for reach in REACHES:
            # A reach shorter than the displacement cannot return it, and a reach longer than the
            # tile has no positions left to score. Both are stated and not silently skipped,
            # because a row missing without a reason reads as a row that was not run.
            if reach >= tile:
                out.write(
                    "  %-8d %-8d %-8d %s\n"
                    % (count * count, tile, reach, "reach exceeds tile, not run")
                )
                continue
            # Averaged over every truth in the sweep, not read at one. CEL-3-001 compared its
            # sixteen-arm figure at a single displacement of 3.4 against CEL-2-002's mean over
            # nine displacements from 3.0 to 4.0, called the difference a gain from co-arming,
            # and the difference was the comparison. 3.4 sits near the half, where the fraction
            # is most accurate. A single reading there flatters whatever took it.
            errors = []
            spreads = []
            for truth in TRUTHS:
                readings = arms(canvas, count, reach, 0, truth)
                errors.append(abs(float(numpy.mean(readings)) - truth))
                spreads.append(float(numpy.std(readings)))
            mean = float(numpy.mean([e for e in errors]))
            spread = float(numpy.mean(spreads))
            error = mean
            out.write(
                "  %-8d %-8d %-8d %-11.4f %-11.4f %.4f\n"
                % (count * count, tile, reach, mean, error, spread)
            )
            if (best is None) or (error < best[0]):
                best = (error, count, reach, spread)

    out.write(
        "\n  best: %d co-arms at reach %d, error %.4f px, spread %.4f px.\n"
        % (best[1] * best[1], best[2], best[0], best[3])
    )
    out.write(
        "\n  The whole-field row is the 1 arm row and is what CEL-2-002 quoted at this\n"
    )
    out.write("  width. Every row below it that improves on it was available then.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
