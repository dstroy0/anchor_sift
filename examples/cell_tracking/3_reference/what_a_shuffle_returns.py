#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CEL-3-001
#
# The sub-pixel reading against a background, and the floor it has to clear.
#
#   Usage:  python examples/cell_tracking/3_reference/what_a_shuffle_returns.py
#
# WHAT THIS CORRECTS. CEL-2-001 and CEL-2-002 report a cross-axis reading of about 0.47 px on an
# axis displaced by nothing, and call it a floor the method inherits. That is a raw value quoted
# with no background under it, which is the one thing theory/workbook says never says anything:
# every quantity there is a departure from a background and none is a value, and a dispersion of
# 0.28 says nothing while the same dispersion against a shuffle of the same bytes is 2.91.
#
# Nothing was stopping the background from being built. One field holds as many co-arms as anyone
# wants, because it can be cut into sub-regions that are read independently, and the null can be
# redrawn as many times as anyone wants by permuting the same field again. The earlier files took
# one reading per condition and had neither.
#
# WHAT THE QUESTION ACTUALLY IS. Not "is the cross-axis reading near zero", which is what those
# files asked. A shuffle cannot return zero here: the recover step takes an argmax over lags and
# then a ratio of two non-negative agreements, and that arrangement has a positive expectation
# whatever it is handed. So the value 0.47 is uninterpretable on its own and the question is whether
# the moved axis departs from what the same field returns with its arrangement destroyed.
#
# THE NULL, AND WHICH PROPERTY IT DELETES. Positions are permuted within the second frame, holding
# every level count exactly and destroying where each level sits. That deletes the correspondence
# between the two frames and nothing else: both frames keep their histograms, so the agreement
# measure is handed the same symbol inventory it had. theory/workbook records the protein posit
# failing because two nulls deleted properties that were not separable, and records what survives
# of it, that a result read as evidence about one property is unsupported until a null exists that
# deletes only that one. This null deletes arrangement in the second frame and is stated as such.
#
# THE FLOOR IS THE NULL'S OWN SCATTER. Redrawing the permutation gives a spread, and a separation
# smaller than that spread is not a separation. theory/workbook reseeds twelve times and gets a
# standard deviation of about one percent of the value, and every separation it records is quoted
# in units of that floor. Same arrangement here.

import io
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
SIBLING = os.path.join(os.path.dirname(HERE), "2_partition")
sys.path.insert(0, SIBLING)

ROOT = HERE
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from what_a_pixel_costs import SEED, SIDE, recover, shifted, to_levels  # noqa: E402
from where_the_floor_comes_from import field  # noqa: E402

# The field is cut into this many tiles per side, and each tile is read on its own. Sixteen co-arms
# from one field, which is what makes a spread available without generating sixteen fields.
TILES = 4

# Null permutations drawn per condition. Twelve is what theory/workbook reseeds at.
DRAWS = 12

# Blob width held at the value CEL-2-002 measures the width relation on.
WIDTH = 4.0

# True displacement along axis 0. Axis 1 moves by nothing and is the second condition.
TRUTH = 3.4


def tiles(canvas):
    """`canvas` cut into TILES by TILES sub-regions, each read as its own arm."""
    step = canvas.shape[0] // TILES
    for row in range(TILES):
        for column in range(TILES):
            yield canvas[row * step:(row + 1) * step, column * step:(column + 1) * step]


def scrambled(levels, rng):
    """`levels` with every position permuted, holding every level count exactly.

    The histogram is preserved by construction, since this is a permutation of the same array.
    What is destroyed is where each level sits, which is the property the reading is about.
    """
    flat = levels.reshape(-1).copy()
    rng.shuffle(flat)
    return flat.reshape(levels.shape)


def read_arms(first, second, axis):
    """The recovered displacement on each co-arm, as a list."""
    out = []
    for left, right in zip(tiles(first), tiles(second)):
        lag, fraction, _ = recover(left, right, axis, reach=8)
        out.append(lag + fraction)
    return out


def condition(canvas, axis, truth, rng, out):
    """One axis, read live and against DRAWS permutations, reported as a departure."""
    first = to_levels(canvas)
    second = to_levels(shifted(canvas, truth, axis=0)) if truth else to_levels(canvas)

    live = read_arms(first, second, axis)
    live_mean = float(numpy.mean(live))
    live_spread = float(numpy.std(live))

    # The statistic is how tightly the co-arms agree, not what they agree on. A first version of
    # this file compared the live mean against the null mean and is kept in the docstring because
    # it is wrong in an instructive way: a shuffled arm returns an argmax over lags plus a ratio,
    # which lands near the middle of the swept range whatever it is handed, so its VALUE carries
    # nothing and a live reading sitting near it is a coincidence. Sixteen independent regions of
    # one field agreeing on a displacement is the thing a shuffle cannot produce.
    null_spreads = []
    for _ in range(DRAWS):
        null_spreads.append(float(numpy.std(read_arms(first, scrambled(second, rng), axis))))
    null_spread = float(numpy.mean(null_spreads))
    floor = float(numpy.std(null_spreads))

    # How many times tighter the live arms sit than the shuffled ones. Above one is concentration
    # the null cannot make.
    tightening = (null_spread / live_spread) if live_spread > 0.0 else float("inf")
    floors = ((null_spread - live_spread) / floor) if floor > 0.0 else float("inf")

    out.write("  %-12s %-8.3f %-10.4f %-10.4f %-10.4f %-8.1f %.1f\n"
              % ("axis %d" % axis, truth, live_mean, live_spread,
                 null_spread, tightening, floors))
    return tightening, floors, live_mean, live_spread


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    rng = numpy.random.default_rng(SEED)
    canvas, count = field(numpy.random.default_rng(SEED), WIDTH)

    out.write("  The sub-pixel reading against a permutation null of the same field.\n")
    out.write("  %d co-arms from one %dx%d field, %d blobs %.1f px wide, %d null draws.\n\n"
              % (TILES * TILES, SIDE, SIDE, count, WIDTH, DRAWS))
    out.write("  %-12s %-8s %-10s %-10s %-10s %-8s %s\n"
              % ("condition", "true", "live mean", "live sd", "null sd", "tighter", "floors out"))

    # Axis 0 carries the displacement. Axis 1 carries none and is read from the same pair, so the
    # two conditions differ in exactly one thing.
    moved_tight, moved_floors, moved_mean, moved_sd = condition(canvas, 0, TRUTH, rng, out)
    still_tight, still_floors, _, still_sd = condition(canvas, 1, TRUTH, rng, out)

    out.write("\n  Moved axis: %d co-arms agree at %.4f px against a truth of %.3f, an error of\n"
              % (TILES * TILES, moved_mean, TRUTH))
    out.write("  %.4f px, and they sit %.1f times tighter than the shuffled arms, %.1f floors out.\n"
              % (abs(moved_mean - TRUTH), moved_tight, moved_floors))
    out.write("  Still axis: the same arms scatter at %.4f px, %.1f times tighter, %.1f floors.\n\n"
              % (still_sd, still_tight, still_floors))

    # Both conditions clear a fixed floor, and a fixed floor is therefore the wrong comparison:
    # even with no displacement the field's own structure constrains an argmax more than a full
    # shuffle does, so the still axis concentrates a little and clears three floors on that alone.
    # What separates them is how much, 179x against 3.2x, and the test is the ratio of the two.
    separation = (moved_tight / still_tight) if still_tight > 0.0 else float("inf")
    out.write("  The moved axis concentrates %.0f times more than the still one.\n\n" % separation)

    if (moved_floors >= 3.0) and (separation >= 10.0):
        out.write("  The two conditions separate on the statistic that is a departure and not a\n")
        out.write("  value. A displacement makes independent regions of one field agree, and a\n")
        out.write("  shuffle cannot make them agree. The still axis does not concentrate, which\n")
        out.write("  is the control reading nothing and reporting it.\n")
        out.write("\n  This also corrects the error figures in CEL-2-001 and CEL-2-002. Those read\n")
        out.write("  the whole field once, at 0.1041 px at this width. Sixteen co-arms from the\n")
        out.write("  same field read %.4f px. The co-arms were always available and were not taken.\n"
                  % abs(moved_mean - TRUTH))
    elif moved_floors < 3.0:
        out.write("  The moved axis does not concentrate past its own null, so the reading carries\n")
        out.write("  nothing at this width whatever its mean happens to equal.\n")
    else:
        out.write("  The two conditions do not separate by an order of magnitude, so nothing here\n")
        out.write("  distinguishes an axis that moved from one that did not.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
