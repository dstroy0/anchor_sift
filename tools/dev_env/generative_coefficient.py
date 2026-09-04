#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find what sets the cost of putting a symbol sequence back, for Section 4.11 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/generative_coefficient.py
#
# Held to three steps of angle, a memoryless corpus of eight symbols returns 62.7 percent of them exactly
# and English returns 9.7, while the correlation for both is 0.975. Something other than the writing sets
# that, since the corpus recovering six times better is the one with no structure in it at all.
#
# The generated corpora are the place to settle it, because their alphabet and their distribution were
# chosen when they were made instead of being inferred afterward. Ten of them cover alphabets of 8, 26 and
# 64, uniform and geometric weightings at two rates and an English weighting, at three chain depths.
#
# The prediction is exact and follows from the seating. Symbols sit at whole levels one apart, so the gap
# a reconstruction has to stay inside is one level in every corpus. The error left by rounding the angles
# scales with how far the values spread, which an alphabet of eight does not do and an alphabet across
# ASCII does. So the share returned should follow the spread alone, and the alphabet count, the weighting
# and the chain depth should matter only through it. If a corpus with the same spread as another returns a
# different share, the spread is not what governs it.

import io
import math
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
CAP = 262144
BITS = 3

EXTRA = (
    "english_1813_austen.sym",
    "greek_iliad.sym",
    "csource_formal.sym",
    "finnish_1849_kalevala.sym",
    "german_1808_goethe.sym",
)


def recovered(series, bits):
    """Share of symbols returned exactly when every angle is held to a few steps."""
    floats = series.astype(numpy.float64)
    middle = floats.mean()
    spectrum = numpy.fft.rfft(floats - middle)
    steps = 1 << bits
    angles = numpy.angle(spectrum)
    rounded = numpy.round(angles / (2.0 * numpy.pi) * steps) * (2.0 * numpy.pi / steps)
    rebuilt = numpy.fft.irfft(numpy.exp(1j * rounded) * numpy.abs(spectrum), n=len(floats)) + middle
    landed = numpy.clip(numpy.rint(rebuilt), 0, 255).astype(numpy.uint8)
    return float((landed == series).mean()), float(numpy.abs(rebuilt - floats).std())


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-9s %-11s %-9s %-11s %s\n"
              % ("corpus", "symbols", "effective", "spread", "returned", "predicted"))

    names = sorted(name for name in os.listdir(CORPORA)
                   if name.startswith("monkey_") and name.endswith(".sym"))
    gathered = []
    for name in list(names) + list(EXTRA):
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            series = numpy.frombuffer(handle.read(CAP), dtype=numpy.uint8)
        if len(series) < 65536:
            continue

        counts = numpy.bincount(series, minlength=256).astype(numpy.float64)
        shares = counts[counts > 0] / counts.sum()
        effective = 1.0 / float((shares * shares).sum())
        spread = float(series.astype(numpy.float64).std())
        share, error = recovered(series, BITS)

        # A symbol survives when the error stays inside half the one level between symbols, and the
        # error is normal enough for that to be an ordinary tail
        guess = math.erf(0.5 / (error * math.sqrt(2.0))) if error > 0.0 else 1.0
        gathered.append((name[:-4], len(shares), effective, spread, share, guess))
        out.write("  %-26s %-9d %-11.1f %-9.2f %-11.3f %.3f\n"
                  % (name[:-4], len(shares), effective, spread, share, guess))

    if len(gathered) >= 6:
        spreads = numpy.asarray([row[3] for row in gathered])
        shares = numpy.asarray([row[4] for row in gathered])
        guesses = numpy.asarray([row[5] for row in gathered])
        counts = numpy.asarray([float(row[1]) for row in gathered])

        def ranked(left, right):
            return float(numpy.corrcoef(numpy.argsort(numpy.argsort(left)),
                                        numpy.argsort(numpy.argsort(right)))[0, 1])

        out.write("\n  returned against the spread: rho %.3f\n" % ranked(spreads, shares))
        out.write("  returned against the symbol count: rho %.3f\n" % ranked(counts, shares))
        out.write("  returned against the prediction from the spread alone: rho %.3f\n"
                  % ranked(guesses, shares))
        out.write("  worst miss of that prediction: %.3f\n" % float(numpy.abs(guesses - shares).max()))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
