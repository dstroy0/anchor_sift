#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Read a protein as the chain it is instead of as a cloud of points, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/protein_chain.py
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from protein_dimension import WANTED, fetch
from read_dimension import best_count, roughness
from spectral_exponent import exponent

SEED = 0x51F7
BOND_LOW = 3.4
BOND_HIGH = 4.4


def backbone(text):
    """Alpha carbons in the order the file lists them, split where the chain is not continuous."""
    runs = []
    current = []
    last_chain = None
    for line in text.splitlines():
        if (not line.startswith("ATOM")) or (line[12:16].strip() != "CA"):
            continue
        # The alternate location marker repeats a residue, and taking both puts a zero step in the chain
        if line[16] not in (" ", "A"):
            continue
        chain = line[21]
        try:
            point = (float(line[30:38]), float(line[38:46]), float(line[46:54]))
        except ValueError:
            continue
        if (last_chain is not None) and (chain != last_chain):
            runs.append(current)
            current = []
        current.append(point)
        last_chain = chain
    runs.append(current)
    return [numpy.asarray(run, dtype=numpy.float64) for run in runs if len(run) >= 64]


def steps(runs):
    """The step from each residue to the next, kept only where the chain is unbroken."""
    kept = []
    for run in runs:
        moves = numpy.diff(run, axis=0)
        lengths = numpy.sqrt((moves ** 2).sum(axis=1))
        good = (lengths >= BOND_LOW) & (lengths <= BOND_HIGH)
        kept.append((moves[good], lengths[good]))
    return kept


def to_levels(series):
    """One component of the steps, held to eight bits the way every corpus here is read."""
    spread = series.std()
    if spread <= 0.0:
        return None
    scaled = (series - series.mean()) / spread
    return numpy.clip(numpy.rint((scaled * 42.0) + 128.0), 0, 255).astype(numpy.uint8)


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
            text = fetch(code)
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
        # The three components laid one after another, which is the chain's own interleaving
        woven = numpy.stack(columns, axis=1).reshape(-1)
        found, score, _ = best_count(roughness(woven), rng)

        # Same three components, order along the chain destroyed, so a count coming from the weaving
        # alone survives here and a count coming from the chain does not
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
