#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CEL-2-002
#
# Whether the sub-pixel floor belongs to the feature width or to the mechanism.
#
#   Usage:  python examples/cell_tracking/2_partition/where_the_floor_comes_from.py
#
# CEL-2-001 measures the fraction between two straddling lags carrying part of a sub-pixel
# displacement and not all of it: 0.1479 px mean against 0.2222 px for the whole lag alone, and a
# residual that is largest at whole-number displacements and near zero at the half. The reading
# offered there for that floor is feature width, that a blob six pixels across still agrees
# substantially at the neighbouring lag when the displacement is exact.
#
# THAT IS A GUESS UNTIL IT IS SWEPT, and this file sweeps it. theory/workbook records ten separate
# bounds in this work that had to come back off, each one a quantity chosen because something had to
# be chosen, and the rule it ends with is that what works is not choosing better but sweeping the
# quantity and letting the data say where it stops mattering. Blob width was chosen once, by this
# author, on no evidence.
#
# THE TWO OUTCOMES, WRITTEN BEFORE THE RUN. If the error falls as the blobs narrow, the floor is the
# feature width, the reading in CEL-2-001 was right, and the figure quotable for microscopy is
# whatever it reaches at a nucleus's real width. If the error holds flat across the sweep, the floor
# is the mechanism, the feature-width reading is refuted, and 1.5x against rounding is the honest
# ceiling for two frames with no tile series in them.
#
# WHERE THE SWEEP STOPS BEING VALID, AND IT IS NOT AT THE EDGE OF THE TABLE. The ground truth here
# is a Fourier shift, which moves a band-limited field by a real number exactly. A blob narrower
# than about two pixels is not band-limited on this grid, its spectrum reaches the Nyquist fold, and
# the shift stops being exact. Below that width the truth column is no longer a truth and the error
# it produces belongs to the generator. The narrow rows are swept anyway and marked, because a
# boundary reported is worth more than a table that stops short of it without saying why.

import io
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ROOT = HERE
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from what_a_pixel_costs import SEED, SIDE, TRUTHS, recover, shifted, to_levels  # noqa: E402

# Blob widths swept, in pixels. The narrow end sits below what a Fourier shift can carry exactly and
# is marked rather than omitted. The wide end is past any nucleus in the 2D challenge sets.
WIDTHS = (1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0)

# Below this width the field is not band-limited on this grid and the generator's own shift is no
# longer exact.
BAND_LIMIT = 2.0

# Held fixed across the sweep so the only thing moving is the width. Density matters: narrow blobs
# at a fixed count light fewer pixels, and a measure scored on occupied positions then reads fewer
# of them. The count is raised with the narrowing so the lit area stays about constant.
LIT_TARGET = 40 * 6.0 * 6.0


def field(rng, width):
    """A flat background carrying Gaussian blobs of `width`, at about a constant lit area."""
    count = max(4, int(round(LIT_TARGET / (width * width))))
    rows, columns = numpy.mgrid[0:SIDE, 0:SIDE]
    canvas = numpy.zeros((SIDE, SIDE), dtype=numpy.float64)
    margin = max(3.0 * width, 4.0)
    for _ in range(count):
        centre_row = rng.uniform(margin, SIDE - margin)
        centre_column = rng.uniform(margin, SIDE - margin)
        brightness = rng.uniform(0.5, 1.0)
        canvas += brightness * numpy.exp(
            -(((rows - centre_row) ** 2) + ((columns - centre_column) ** 2))
            / (2.0 * width * width))
    return canvas, count


def one_width(width):
    """Mean and worst error at one blob width, with the whole-lag background and the control."""
    rng = numpy.random.default_rng(SEED)
    canvas, count = field(rng, width)
    first = to_levels(canvas)
    errors = []
    plain = []
    cross = []
    for truth in TRUTHS:
        second = to_levels(shifted(canvas, truth, axis=0))
        lag, fraction, _ = recover(first, second, axis=0)
        errors.append(abs((lag + fraction) - truth))
        plain.append(abs(lag - truth))
        cross_lag, cross_fraction, _ = recover(first, second, axis=1)
        cross.append(abs(cross_lag + cross_fraction))
    return {
        "count": count,
        "mean": sum(errors) / len(errors),
        "worst": max(errors),
        "plain": sum(plain) / len(plain),
        "cross": sum(cross) / len(cross),
    }


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Does the sub-pixel floor fall with the feature width, or hold?\n")
    out.write("  Lit area held near constant. Only the width moves.\n\n")
    out.write("  %-8s %-8s %-10s %-10s %-10s %-10s %s\n"
              % ("width", "blobs", "mean err", "worst err", "whole lag", "cross axis", "valid"))

    rows = []
    for width in WIDTHS:
        result = one_width(width)
        rows.append((width, result))
        out.write("  %-8.1f %-8d %-10.4f %-10.4f %-10.4f %-10.4f %s\n"
                  % (width, result["count"], result["mean"], result["worst"],
                     result["plain"], result["cross"],
                     "yes" if width >= BAND_LIMIT else "NOT BAND-LIMITED"))

    valid = [(width, result) for width, result in rows if width >= BAND_LIMIT]
    narrow = min(valid, key=lambda row: row[0])
    wide = max(valid, key=lambda row: row[0])
    out.write("\n  Over the band-limited rows only, %.1f px to %.1f px:\n"
              % (narrow[0], wide[0]))
    out.write("    narrowest  mean %.4f px, cross axis %.4f px\n"
              % (narrow[1]["mean"], narrow[1]["cross"]))
    out.write("    widest     mean %.4f px, cross axis %.4f px\n"
              % (wide[1]["mean"], wide[1]["cross"]))

    moved = wide[1]["mean"] - narrow[1]["mean"]
    out.write("\n  The error moves %.4f px across a %.0fx change in width.\n"
              % (moved, wide[0] / narrow[0]))
    if abs(moved) < 0.02:
        out.write("  That is flat. The floor is the mechanism and not the feature width, and the\n")
        out.write("  reading offered in CEL-2-001 is refuted by its own sweep.\n")
    elif moved > 0.0:
        out.write("  The error falls as the blobs narrow. The floor is the feature width and\n")
        out.write("  a figure quoted for microscopy has to be quoted at a nucleus's real width.\n")
    else:
        out.write("  The error RISES as the blobs narrow, which neither outcome predicted and\n")
        out.write("  which nothing in this file explains. It is reported and not accounted for.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
