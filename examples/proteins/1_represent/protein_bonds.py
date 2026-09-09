#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-1-001
#
# Represent a protein by its bonds in the order the chain was assembled, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python examples/proteins/1_represent/protein_bonds.py
#
# Two representations have failed here and both failed by discarding something. Laying every atom into a
# grid discarded the order, leaving a scatter of points in a box that is mostly empty. Taking the step
# from one alpha carbon to the next kept the order and discarded the bonds, since an alpha carbon is
# already a summary of a residue and the step between two of them is not a bond at all.
#
# The bonds are the connections and the chain is assembled in one direction, so the representation is the
# backbone walked as it was built: nitrogen to alpha carbon, alpha carbon to carbon, carbon to the
# nitrogen of the next residue, and around again. Each of those is a real bond with a vector and a
# magnitude, and the three lengths are fixed by chemistry near 1.46, 1.52 and 1.33 angstroms.
#
# That gives this test something the earlier ones lacked, which is an answer known before the measurement
# and not supplied by the measurement. The bond lengths must cycle with a period of three, at those three
# values, in every protein ever deposited. So the period is checked against chemistry first, and only then
# is the same series handed to the reader that has been failing, to see whether it recovers a period that
# is known to be there.

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

from measure.periodicity import sequence_period  # noqa: E402
from partition.dimension_count import best_count, roughness  # noqa: E402
from representation.levels import to_levels  # noqa: E402
from representation.structure.protein import WANTED, bonds, fetch, walk  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Chemistry says the bond lengths repeat every three at 1.46, 1.52 and 1.33.\n\n")
    out.write("  %-8s %-8s %-30s %-9s %-8s %s\n"
              % ("code", "bonds", "lengths by position in three", "found", "score", "matches chemistry"))

    rng = numpy.random.default_rng(SEED)
    hits = 0
    total = 0
    for code, _ in WANTED:
        try:
            text = fetch(code, CORPORA)
        except Exception as trouble:
            out.write("  %-8s could not fetch: %s\n" % (code, trouble))
            continue
        pieces = bonds(walk(text))
        if not pieces:
            out.write("  %-8s no unbroken backbone run long enough\n" % code)
            continue

        # Gathered by each piece's own place in the cycle, so pieces starting mid residue still land in
        # the right one of the three
        gathered = [[], [], []]
        for piece, offset in pieces:
            sizes = numpy.sqrt((piece ** 2).sum(axis=1))
            for place in range(3):
                gathered[(place + offset) % 3].append(sizes[place::3])
        phases = [numpy.concatenate(part) for part in gathered if part]
        if len(phases) < 3:
            out.write("  %-8s could not be split into three phases\n" % code)
            continue
        joined = numpy.concatenate([piece for piece, _ in pieces], axis=0)
        lengths = numpy.sqrt((joined ** 2).sum(axis=1))
        spelled = ", ".join("%.2f" % float(phase.mean()) for phase in phases)

        seen = sorted(float(phase.mean()) for phase in phases)
        agrees = all(abs(value - target) < 0.06
                     for value, target in zip(seen, sorted((1.46, 1.52, 1.33))))

        levels = to_levels(lengths)
        found, score = None, None
        if levels is not None:
            found, score, _ = best_count(roughness(levels), rng)
        direct, direct_score = sequence_period(lengths)
        total += 1
        hits += 1 if direct == 3 else 0
        out.write("  %-8s %-8d %-30s %-9s %-11s %s\n"
                  % (code, len(joined), spelled,
                     "%d at %.2f" % (found, score) if found is not None else "none",
                     "%d at %.2f" % (direct, direct_score) if direct is not None else "none",
                     "yes" if agrees else "no"))

    out.write("\n  %d of %d proteins returned three from every lag; the powers of two cannot.\n"
              % (hits, total))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
