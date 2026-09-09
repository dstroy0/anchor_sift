#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Carry a plane through a single dimension by interleaving its coordinates, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python examples/art/2_partition/morton_squash.py
#
# The single instrument failed on pictures for one reason. A picture stored row by row puts two positions
# that sit one above each other a whole width apart in the file. A reader that does not know the width
# cannot see the second dimension at all. The bit volume returned heights for that reason, and every
# measurement since has had to be handed a width it should not have needed.
#
# Interleaving the coordinates removes the need. Taking one bit from the column, then one from the row,
# then the next from each, gives an index where positions close in the plane are close in the index, and
# the count of bits doubles because each position now spends alternate bits on each axis. The plane is
# then carried inside one dimension with nothing thrown away and no width supplied to the reader.
#
# The test is whether a reading taken along that index recovers what the plane gives. Three exponents are
# measured on the same seven paintings: over the plane, along the interleaved index, and along the file as
# it is stored. The plane is the answer, the interleaved index is the claim, and the stored order is the
# control that is expected to fail, since it is what failed before.

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

from measure.spectral import exponent, exponent_plane  # noqa: E402
from partition.curves import interleaved  # noqa: E402
from representation.picture.raster import WIDTHS, as_grid  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-16s %-11s %-11s %-11s %-9s %s\n"
              % ("picture", "plane", "interleaved", "as stored", "fit r2", "interleaved vs plane"))

    gathered = []
    for label in sorted(WIDTHS):
        path = os.path.join(CORPORA, "%s.sym" % label)
        if not os.path.isfile(path):
            out.write("  %-16s not present\n" % label)
            continue
        width = WIDTHS[label]
        with open(path, "rb") as handle:
            whole = numpy.frombuffer(handle.read(), dtype=numpy.uint8)
        grid = as_grid(whole, width)
        if (grid is None) or (grid.shape[0] < 128):
            continue

        plane, _ = exponent_plane(grid.reshape(-1), width)
        walk, quality = exponent(interleaved(grid))
        stored, _ = exponent(grid.reshape(-1))
        if (plane is None) or (walk is None) or (stored is None):
            continue
        gathered.append((plane, walk, stored))
        out.write("  %-16s %-11.3f %-11.3f %-11.3f %-9.3f %.3f\n"
                  % (label, plane, walk, stored,
                     quality if quality is not None else float("nan"), walk / plane))

    if len(gathered) >= 5:
        planes = numpy.asarray([row[0] for row in gathered])
        walks = numpy.asarray([row[1] for row in gathered])
        stored = numpy.asarray([row[2] for row in gathered])

        # A curve that fills a plane covers an area with a length. A distance along it goes as the
        # square of a distance across the picture, and the exponent should come back halved
        share = walks / planes
        out.write("\n  interleaved over plane: mean %.3f, spread %.3f over %d paintings\n"
                  % (float(share.mean()), float(share.std()), len(gathered)))
        out.write("  %-16s %-13s %-13s %s\n" % ("picture", "twice walked", "plane", "miss"))
        for (plane, walk, _), label in zip(gathered, sorted(WIDTHS)):
            out.write("  %-16s %-13.3f %-13.3f %.3f\n" % (label, 2.0 * walk, plane, (2.0 * walk) - plane))

        for title, series in (("interleaved", walks), ("as stored", stored)):
            first = numpy.argsort(numpy.argsort(planes))
            second = numpy.argsort(numpy.argsort(series))
            out.write("\n  %s against the plane over %d paintings: rho %.3f"
                      % (title, len(gathered), float(numpy.corrcoef(first, second)[0, 1])))
        out.write("\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
