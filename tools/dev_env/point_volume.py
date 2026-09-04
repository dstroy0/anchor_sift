#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# One volume and one reduction for every corpus, with no dimension assigned to any of them, for Section
# 4.2 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/point_volume.py
#
# The earlier attempt at a single instrument gave each domain a dimension: a line for text, a plane for a
# picture, a space for a structure. That was the defect. Choosing a picture's width means choosing a
# geometry and then measuring the choice, and it showed: reshaping at a wrong width shears the rows into
# diagonals, an orientation tensor scores a shear highest, and the sweep returned the height every time
# while the shift detector returned the width correctly on all three pictures.
#
# A cloud of points carries no dimension to assign. What every corpus already is, without anything being
# chosen for it, is bits. So the volume is built in bit space and the same construction runs over text,
# sound, pictures and structures alike.
#
# Each symbol is Gray coded before it is expanded, so two values one apart differ in one bit and distance
# in the volume means what distance in the alphabet meant. The bits concatenate into one stream, and a
# window of n bits slid along it is a point in binary n space. The width n is not a property of the
# corpus and is not guessed at; it is swept, and the result is summed over it.
#
# The reduction is a sum over vectors. Summing the window vectors straight gives the per bit marginals and
# throws away how the bits move together, so they are summed as outer products, which is the correlation
# of the n bit positions. The eigenvalues of that sum describe the shape of the occupied volume: spread
# evenly when the bits are independent, concentrated when they are not. The statistic is how far that
# spectrum sits from the even one, measured against the null used throughout, which permutes the symbols
# and keeps their frequencies.

import io
import math
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(ROOT, "build", "point_volume.csv")

CAP = 120000
WINDOWS = 40000
# Swept to where the data runs out, not stopped at a chosen ceiling, because the volume has no bound to
# pick and the sum is over every width. A ceiling is only allowed once the tail is shown to vanish.
WIDTHS = tuple(range(2, 65))
SEED = 0x51F7


def gray_bits(values):
    """Gray code the symbols, then lay them out as one stream of bits."""
    coded = (values ^ (values >> 1)).astype(numpy.uint8)
    return numpy.unpackbits(coded)


def spectrum_gap(bits, width, rng):
    """How far the bit correlation spectrum sits from the even one, at one window width."""
    usable = len(bits) - width
    if usable < (4 * width):
        return None
    starts = numpy.arange(usable) if usable <= WINDOWS else rng.choice(usable, WINDOWS, replace=False)
    windows = bits[starts[:, None] + numpy.arange(width)[None, :]].astype(numpy.float32)

    centered = windows - windows.mean(axis=0, keepdims=True)
    spread = centered.std(axis=0)
    # A bit that never changes carries no correlation and would divide by zero
    alive = spread > 1e-6
    if int(alive.sum()) < 3:
        return None
    centered = centered[:, alive] / spread[alive]
    correlation = (centered.T @ centered) / float(len(centered))

    eigenvalues = numpy.linalg.eigvalsh(correlation)
    eigenvalues = numpy.clip(eigenvalues, 1e-12, None)
    eigenvalues = eigenvalues / eigenvalues.sum()
    # Even spread is the largest possible entropy over this many bits, so the shortfall is the departure
    entropy = -float((eigenvalues * numpy.log2(eigenvalues)).sum())
    return math.log2(len(eigenvalues)) - entropy


def measure(values):
    """The excess over the permuted null at every window width, returned as the curve over the width.

    The curve is what decides whether the sum over every width exists. A term that decays leaves a total
    that does not depend on where the sweep was stopped. A term that does not decay leaves a total that is
    whatever ceiling was chosen, which is a property of the choice and not of the corpus.
    """
    live_bits = gray_bits(values)
    shuffled = values.copy()
    numpy.random.default_rng(SEED).shuffle(shuffled)
    dead_bits = gray_bits(shuffled)

    curve = []
    for width in WIDTHS:
        live = spectrum_gap(live_bits, width, numpy.random.default_rng(SEED))
        dead = spectrum_gap(dead_bits, width, numpy.random.default_rng(SEED))
        if (live is None) or (dead is None):
            continue
        curve.append((width, live - dead))
    return curve if curve else None


def load(path, name):
    if name.endswith(".txt"):
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        # Line endings folded, as everywhere here, so a publisher's wrapping is not measured
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        seating = {}
        for character in text:
            if character not in seating:
                seating[character] = len(seating) & 0xFF
        return numpy.asarray([seating[character] for character in text], dtype=numpy.uint8)
    with open(path, "rb") as handle:
        return numpy.frombuffer(handle.read(CAP), dtype=numpy.uint8)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    names = sorted(name for name in os.listdir(CORPORA)
                   if name.endswith(".sym") or name.endswith(".txt"))

    # One corpus per family, since convergence has to be settled before any total is worth computing
    chosen = {}
    for name in names:
        path = os.path.join(CORPORA, name)
        if os.path.getsize(path) < 20000:
            continue
        chosen.setdefault(name.split("_")[0], name)

    out.write("  %-12s %-9s %-11s %-11s %-11s %s\n"
              % ("family", "widths", "peak width", "excess 8", "excess 32", "excess 64"))

    rows = []
    for family in sorted(chosen):
        name = chosen[family]
        values = load(os.path.join(CORPORA, name), name)
        if len(values) < 20000:
            continue
        curve = measure(values)
        if curve is None:
            continue

        widths = numpy.asarray([point[0] for point in curve], dtype=numpy.float64)
        excess = numpy.asarray([point[1] for point in curve], dtype=numpy.float64)
        peak = int(widths[int(numpy.argmax(excess))])
        readings = {}
        for probe in (8, 32, 64):
            hits = numpy.flatnonzero(widths == probe)
            readings[probe] = float(excess[hits[0]]) if len(hits) else float("nan")
        rows.append((name[:-4], widths, excess))
        out.write("  %-12s %-9d %-11d %-11.4f %-11.4f %.4f\n"
                  % (family, len(curve), peak, readings[8], readings[32], readings[64]))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("corpus,width,excess\n")
        for label, widths, excess in rows:
            for width, value in zip(widths, excess):
                handle.write("%s,%d,%.6f\n" % (label, int(width), value))

    # The excess does not fall off with the width, so the sum over every width has no value and the
    # quantity that does not depend on the ceiling is the exponent the growth follows. The memoryless
    # corpora are the control: an estimate of a correlation matrix grows lopsided with its size on its
    # own, and that would lift every corpus alike, so a corpus staying flat while others climb is what
    # separates real correlation at length from the arithmetic of estimating it.
    out.write("\n  growth of the excess with the window width, fitted over the widths above 8 bits\n")
    out.write("  %-26s %-11s %-11s %s\n" % ("corpus", "exponent", "fit r2", "excess at 64"))
    for label, widths, excess in rows:
        keep = (widths >= 8.0) & (excess > 0.0)
        if int(keep.sum()) < 12:
            out.write("  %-26s %-11s %-11s %.4f\n"
                      % (label, "flat", "no growth", float(excess[-1])))
            continue
        logs = numpy.log(widths[keep])
        values = numpy.log(excess[keep])
        exponent, intercept = numpy.polyfit(logs, values, 1)
        predicted = (exponent * logs) + intercept
        spread = float(((values - values.mean()) ** 2).sum())
        quality = 1.0 - (float(((values - predicted) ** 2).sum()) / spread) if spread > 0 else 0.0
        out.write("  %-26s %-11.3f %-11.3f %.4f\n"
                  % (label, float(exponent), quality, float(excess[-1])))

    out.write("\n  wrote %s with %d curves\n" % (TARGET, len(rows)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
