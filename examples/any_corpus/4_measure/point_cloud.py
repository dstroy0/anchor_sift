#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-4-006
#
# One representation and one reduction for every corpus in this work, for Section 4.2 of
# theory/anchor_sift.
#
#   Usage:  python examples/any_corpus/4_measure/point_cloud.py
#
# Two instruments are in use in this work and three separate claims merged them, because both return a
# ratio near one for nothing and a departure for something. A row in a table does not carry which
# produced it. The cause is that each domain got its own reader: a sequence for text, a raster for a
# picture, a voxel grid for a structure.
#
# None of that is necessary. Every corpus here is already a cloud of points carrying values. Text is
# positions along a line holding symbols, sound is the same holding amplitudes, a picture is positions on
# a plane, a structure is positions in space. Writing them all that way leaves one instrument.
#
# The reduction is a sum over vectors. Each point takes the displacement to the nearest point holding the
# same value, and those displacements are summed in two ways, because one of them cancels and the other
# does not. Their lengths give a spread. Their directions cancel when summed straight, since if one point
# reaches its neighbor then that neighbor usually reaches back and the two vectors are opposite, so the
# directions are summed as outer products instead, which are unchanged when a vector flips sign. That sum
# is the orientation tensor and its eigenvalues report whether the displacements share a direction.
#
# On a line there is only one direction and the tensor is the constant one, so the orientation channel is
# undefined below two dimensions and is reported as absent instead of as zero. The length channel is
# defined everywhere. The null is the same one used throughout: the values are permuted over the points and
# every coordinate stays.

import io
import math
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.point_cloud import reduce_cloud, reduce_sequence  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(ROOT, "build", "point_cloud.csv")

CAP = 200000

# Levels the picture is quantized to, letting a value recur often enough to have neighbors of its own.
PICTURE_LEVELS = 32


def load_sequence(path):
    with open(path, "rb") as handle:
        raw = handle.read(CAP)
    return numpy.frombuffer(raw, dtype=numpy.uint8).astype(numpy.int64)


def load_text(path):
    """A text file as points on a line holding characters, the only width Chinese survives."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read(CAP)
    # Line endings folded, as everywhere here, to keep a publisher's wrapping out of the measurement
    text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
    seating = {}
    for character in text:
        if character not in seating:
            seating[character] = len(seating)
    return numpy.asarray([seating[character] for character in text], dtype=numpy.int64), len(seating)


def load_picture(path):
    """A byte file holding a square picture, reconstructed at the side its length implies."""
    with open(path, "rb") as handle:
        raw = handle.read()
    side = int(math.isqrt(len(raw)))
    if (side * side) != len(raw) or side < 64:
        return None, None
    step = max(1, side // 200)
    grid = numpy.frombuffer(raw, dtype=numpy.uint8).reshape(side, side)[::step, ::step]
    rows, cols = grid.shape
    ys, xs = numpy.mgrid[0:rows, 0:cols]
    coords = numpy.stack([xs.ravel(), ys.ravel()], axis=1).astype(numpy.float64)
    # Quantized to let a value recur often enough to have neighbors of its own
    return coords, (grid.ravel() >> 3).astype(numpy.int64)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    names = sorted(name for name in os.listdir(CORPORA)
                   if name.endswith(".sym") or name.endswith(".txt"))

    rows = []
    for name in names:
        path = os.path.join(CORPORA, name)
        label = name[:-4]
        if os.path.getsize(path) < 20000:
            continue

        if label.startswith("art_") or label.startswith("img_"):
            coords, values = load_picture(path)
            if coords is None:
                continue
            found = reduce_cloud(coords, values, PICTURE_LEVELS, 2)
            if found is None:
                continue
            rows.append((label, 2, len(values), found[1], found[0], found[2]))
            continue

        if name.endswith(".txt"):
            values, width = load_text(path)
        else:
            values, width = load_sequence(path), 256
        if len(values) < 20000:
            continue
        found = reduce_sequence(values, width)
        if found is None:
            continue
        rows.append((label, 1, len(values), found[1], found[0], None))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("corpus,dims,points,values,length,orientation\n")
        for label, dims, points, scored, length, bias in rows:
            handle.write("%s,%d,%d,%d,%.6f,%s\n"
                         % (label, dims, points, scored, length,
                            ("%.6f" % bias) if bias is not None else ""))

    families = {}
    for label, dims, _, _, length, bias in rows:
        families.setdefault(label.split("_")[0], []).append((length, bias, dims))

    out.write("  %-12s %-7s %-5s %-16s %s\n"
              % ("family", "corpora", "dims", "length mean, sd", "orientation"))
    for family in sorted(families):
        members = families[family]
        lengths = numpy.asarray([row[0] for row in members])
        biases = [row[1] for row in members if row[1] is not None]
        out.write("  %-12s %-7d %-5d %-16s %s\n"
                  % (family, len(members), members[0][2],
                     "%.3f, %.3f" % (lengths.mean(), lengths.std()),
                     ("%.3f" % numpy.mean(biases)) if biases else "not defined on a line"))

    # The rare half of a large alphabet is a rarer population than the rare half of a small one. A
    # channel that tracks the alphabet size is comparing inventories and never corpora
    scored = numpy.asarray([row[3] for row in rows], dtype=numpy.float64)
    lengths = numpy.asarray([row[4] for row in rows], dtype=numpy.float64)
    ranked = numpy.corrcoef(numpy.argsort(numpy.argsort(scored)),
                            numpy.argsort(numpy.argsort(lengths)))[0, 1]
    out.write("\n  alphabet size against the length channel, over %d corpora: rho %.3f\n"
              % (len(rows), ranked))
    out.write("  values scored run %d to %d\n" % (int(scored.min()), int(scored.max())))

    out.write("\n  wrote %s with %d rows\n" % (TARGET, len(rows)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
