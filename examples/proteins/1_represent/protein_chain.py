#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-1-002
#
# Read a protein as the chain it is instead of as a cloud of points, for Section 4.2 of
# theory/anchor_sift.
#
#   Usage:  python examples/proteins/1_represent/protein_chain.py
#
# The previous attempt laid every atom into a grid and smoothed it, which threw away the property that
# makes a protein a protein. A chain has an order and a step from each residue to the next, and a grid
# keeps neither. What was measured was a scatter of unrelated points in a box that is mostly empty, and
# the reading failed because most of a line through it crosses vacuum, where no axis differs from another.
#
# The chain gives its own vectors and they need no grid. Consecutive alpha carbons sit a nearly fixed
# distance apart, so the magnitude is close to constant along the whole backbone and the structure lives
# in the directions. A helix turns by a repeating angle and a sheet runs nearly straight, so the direction
# series carries the secondary structure directly, in the order the chain was built.
#
# Three things are measured on that series. The step length and its spread say whether the chain was read
# in the right order, since a jump between chains or a gap in the model breaks it and shows up at once.
# The exponent of each component says how the directions are arranged along the chain. The dimension count
# is then read from the three components laid one after another, and that reading is checked against a
# control that keeps the same three components and destroys the order, since a period of three can be
# found in any three series taken in turn and the interleaving must not be what is being detected.

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

from measure.spectral import exponent  # noqa: E402
from partition.dimension_count import best_count, roughness  # noqa: E402
from representation.levels import to_levels  # noqa: E402
from representation.structure.protein import WANTED, backbone, fetch, steps  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Predicted: the step length is near constant, and the count comes back three.\n\n")
    out.write("  %-8s %-8s %-15s %-9s %-9s %-8s %s\n"
              % ("code", "steps", "step length", "exponent", "found", "score", "order broken"))

    rng = numpy.random.default_rng(SEED)
    hits = 0
    total = 0
    for code, _ in WANTED:
        try:
            text = fetch(code, CORPORA)
        except Exception as trouble:
            out.write("  %-8s could not fetch: %s\n" % (code, trouble))
            continue
        pieces = steps(backbone(text))
        moves = [piece[0] for piece in pieces if len(piece[0]) >= 64]
        if not moves:
            out.write("  %-8s no unbroken run long enough\n" % code)
            continue
        joined = numpy.concatenate(moves, axis=0)
        lengths = numpy.concatenate([piece[1] for piece in pieces if len(piece[0]) >= 64])

        columns = [to_levels(joined[:, axis]) for axis in range(3)]
        if any(column is None for column in columns):
            continue
        # The three components laid one after another, the chain's own interleaving
        woven = numpy.stack(columns, axis=1).reshape(-1)
        found, score, _ = best_count(roughness(woven), rng)

        # Same three components, order along the chain destroyed. A count coming from the weaving
        # alone survives here, and a count coming from the chain does not
        shuffled = numpy.stack([rng.permutation(column) for column in columns], axis=1).reshape(-1)
        broken, broken_score, _ = best_count(roughness(shuffled), rng)

        slope, _ = exponent(columns[0])
        total += 1
        hits += 1 if found == 3 else 0
        out.write("  %-8s %-8d %-15s %-9s %-9d %-8.2f %s\n"
                  % (code, len(joined), "%.2f, %.2f" % (lengths.mean(), lengths.std()),
                     "%.3f" % slope if slope is not None else "none", found, score,
                     "%d at %.2f" % (broken, broken_score) if broken is not None else "none"))

    out.write("\n  %d of %d chains returned three\n" % (hits, total))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
