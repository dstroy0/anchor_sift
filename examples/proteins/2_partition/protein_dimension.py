#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Read the dimension count off real structures instead of made ones, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python examples/proteins/2_partition/protein_dimension.py
#
# Eleven of twelve readings recovered the dimension count from a single line, and every one of those sets
# was built here, with a correlation length put along each axis by hand to make the axes tellable apart.
# That is the friendliest possible case and it proves the method works on sets shaped to suit it.
#
# A protein is the honest version. It occupies three dimensions, nobody here chose its shape, and its axes
# differ because a folded chain is longer one way than another and packs differently along each. If the
# count comes back as three from a line drawn through a structure that was measured in a laboratory, the
# claim holds outside the fields written to demonstrate it.
#
# The atoms are laid into a grid and smoothed, which is not a convenience. A structure is observed as a
# density and deposited atoms with no smoothing give a grid that is almost entirely empty, so the readings
# would describe the emptiness. Smoothing to a few voxels is what the measurement that produced these
# coordinates actually resolves.
#
# Nothing about the structure is given to the reader. It receives one line of bytes.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.spectral import exponent, exponent_volume  # noqa: E402
from partition.curves import interleave  # noqa: E402
from partition.dimension_count import best_count, roughness  # noqa: E402
from representation.structure.protein import WANTED, atoms, density, fetch  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
SIDE = 64
# Swept, because the first run smoothed by 1.6 voxels and put every structure at an exponent of 5.8 to
# 7.5, where the reading along the line is the curve's own floor and carries nothing about the structure
BLURS = (0.3, 0.5, 0.8, 1.2, 1.6)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Predicted before measuring: three, at whatever smoothing puts the exponent in range.\n\n")
    out.write("  %-8s %-6s %-8s %-10s %-9s %-8s %s\n"
              % ("code", "blur", "atoms", "over set", "line", "found", "score"))

    rng = numpy.random.default_rng(SEED)
    hits = 0
    total = 0
    for code, note in WANTED:
        try:
            text = fetch(code, CORPORA)
        except Exception as trouble:
            out.write("  %-8s could not fetch: %s\n" % (code, trouble))
            continue
        points = atoms(text)
        if len(points) < 400:
            out.write("  %-8s only %d atoms\n" % (code, len(points)))
            continue

        for blur in BLURS:
            field = density(points, SIDE, blur)
            if field is None:
                continue
            series = interleave(field)
            found, score, _ = best_count(roughness(series), rng)
            over, _ = exponent_volume(field)
            along, _ = exponent(series)
            if found is None:
                continue
            # Counted only where the set sits in the range the synthetic fields established
            inside = (over is not None) and (over <= 3.5)
            if inside:
                total += 1
                hits += 1 if found == 3 else 0
            out.write("  %-8s %-6.1f %-8d %-10s %-9s %-8d %-8.2f %s\n"
                      % (code, blur, len(points),
                         "%.3f" % over if over is not None else "none",
                         "%.3f" % along if along is not None else "none",
                         found, score, "in range" if inside else ""))
        out.write("\n")

    out.write("  %d of %d readings inside the workable range returned three\n" % (hits, total))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
