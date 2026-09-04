#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Represent a protein by its bonds in the order the chain was assembled, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/protein_bonds.py
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from protein_dimension import WANTED, fetch
from read_dimension import best_count, roughness

SEED = 0x51F7
BACKBONE = ("N", "CA", "C")
LIMIT = 2.2


def walk(text):
    """The backbone atoms in the order the chain was assembled, one run per unbroken stretch."""
    runs = []
    current = []
    expecting = 0
    last_chain = None
    for line in text.splitlines():
        if not line.startswith("ATOM"):
            continue
        name = line[12:16].strip()
        if name not in BACKBONE:
            continue
        # An alternate location repeats an atom, and keeping both puts a zero length bond in the walk
        if line[16] not in (" ", "A"):
            continue
        chain = line[21]
        try:
            point = (float(line[30:38]), float(line[38:46]), float(line[46:54]))
        except ValueError:
            continue

        # The walk only continues where the next atom is the next one the backbone calls for
        if (name != BACKBONE[expecting]) or ((last_chain is not None) and (chain != last_chain)):
            runs.append(current)
            current = []
            expecting = 0
            if name != BACKBONE[0]:
                last_chain = chain
                continue
        current.append(point)
        expecting = (expecting + 1) % len(BACKBONE)
        last_chain = chain
    runs.append(current)
    return [numpy.asarray(run, dtype=numpy.float64) for run in runs if len(run) >= 96]


def bonds(runs):
    """Every bond vector along the walk, each piece carrying where in the cycle of three it begins.

    A run holding a break is cut, and every piece after the first then starts somewhere other than the
    first bond of a residue. Concatenating them without saying so mixes the three bond types together,
    which read 1.43, 1.43 and 1.43 on the large structures: the average of all three, three times.
    """
    vectors = []
    for run in runs:
        moves = numpy.diff(run, axis=0)
        lengths = numpy.sqrt((moves ** 2).sum(axis=1))
        broken = numpy.flatnonzero(lengths > LIMIT)
        if len(broken) == 0:
            vectors.append((moves, 0))
            continue
        start = 0
        for stop in list(broken) + [len(lengths)]:
            piece = moves[start:stop]
            if len(piece) >= 96:
                vectors.append((piece, start % 3))
            start = stop + 1
    return vectors


def sequence_period(series, longest=16):
    """The lag where the series agrees with itself best, read at every lag and not at powers of two.

    The reader used elsewhere here samples at 1, 2, 4, 8 and 16, because it was built for an index whose
    period counts bit positions. A period of three in a sequence sits at lags 3, 6 and 9, and no power of
    two is a multiple of three, so that reader cannot see this signal at all whatever the data does. The
    two are different quantities that were both being called a period of n.
    """
    floats = series.astype(numpy.float64)
    floats = floats - floats.mean()
    if (floats.std() <= 0.0) or (len(floats) < (4 * longest)):
        return None, None
    marks = {}
    for lag in range(1, longest + 1):
        left = floats[:-lag]
        right = floats[lag:]
        spread = float(left.std() * right.std())
        marks[lag] = float((left * right).mean() / spread) if spread > 0.0 else 0.0

    # Scored on a period and all of its multiples, not on the single tallest lag. A series repeating every
    # three agrees with itself at three, six, nine and twelve alike, so the tallest of those is settled by
    # noise and picking it reports a harmonic as though it were the period.
    scored = []
    for period in range(2, (longest // 2) + 1):
        family = [marks[lag] for lag in range(period, longest + 1, period)]
        outside = [value for lag, value in marks.items() if (lag % period) != 0]
        if (len(family) < 2) or (not outside):
            continue
        scored.append((float(numpy.mean(family)) - float(numpy.mean(outside)), period))
    if not scored:
        return None, None
    scored.sort(reverse=True)
    return scored[0][1], scored[0][0]


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
            text = fetch(code)
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

        spread = lengths.std()
        scaled = (lengths - lengths.mean()) / spread if spread > 0 else lengths
        levels = numpy.clip(numpy.rint((scaled * 42.0) + 128.0), 0, 255).astype(numpy.uint8)
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
