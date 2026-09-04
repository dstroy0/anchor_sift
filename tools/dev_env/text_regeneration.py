#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure what a summary puts back for text, for Section 4.11 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/text_regeneration.py
#
# The same measurement on paintings found that one number rebuilds nothing, that the angles need three
# bits and not full precision, and that the amounts have to be kept beside them. All of that was measured
# where a natural scene's falling spectrum is a strong prior, and text has no such prior: its exponent is
# 0.34 against a painting's 2.0, which is nearly flat and close to what noise gives.
#
# Text also fails differently. A picture rebuilt to a correlation of 0.97 is the picture, since a sample
# that lands a level or two off is invisible. A letter that lands one code point off is a different
# letter, and a page of them is not the page. So correlation is reported here beside the share of symbols
# that come back exactly, and it is the second one that decides whether text was regenerated.
#
# The seating matters and is left as the file has it. Nothing here reorders the alphabet to make the
# reconstruction easier, since choosing a seating to suit the measurement is the error this work has made
# in three other places.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spectral_exponent import exponent

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
CAP = 262144
BITS = (1, 2, 3, 4, 6, 8)

WANTED = (
    "english_1813_austen.sym",
    "greek_iliad.sym",
    "csource_formal.sym",
    "monkey_a08_d18_uniform.sym",
)


def agreement(left, right):
    first = left.astype(numpy.float64) - float(left.mean())
    second = right.astype(numpy.float64) - float(second_mean(right))
    spread = float(first.std() * second.std())
    return float((first * second).mean() / spread) if spread > 0.0 else 0.0


def second_mean(values):
    return float(numpy.asarray(values, dtype=numpy.float64).mean())


def exact(original, rebuilt):
    """Share of positions whose symbol comes back exactly, after rounding to a whole level."""
    landed = numpy.clip(numpy.rint(rebuilt), 0, 255).astype(numpy.uint8)
    return float((landed == original).mean())


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-24s %-9s %-14s %-14s %s\n"
              % ("corpus", "exponent", "one number", "amounts only", "angles only"))

    rng = numpy.random.default_rng(SEED)
    gathered = []
    for name in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-24s not present\n" % name[:-4])
            continue
        with open(path, "rb") as handle:
            series = numpy.frombuffer(handle.read(CAP), dtype=numpy.uint8)
        if len(series) < 65536:
            continue
        floats = series.astype(numpy.float64)
        middle = floats.mean()
        spectrum = numpy.fft.rfft(floats - middle)
        amounts = numpy.abs(spectrum)

        slope, _ = exponent(series)
        frequency = numpy.arange(len(spectrum), dtype=numpy.float64)
        frequency[0] = 1.0
        alone = numpy.fft.irfft(
            numpy.fft.rfft(rng.standard_normal(len(floats))) * (frequency ** (-(slope or 0.0) / 2.0)),
            n=len(floats))
        alone = (alone / alone.std() * floats.std()) + middle

        scrambled = numpy.fft.irfft(
            amounts * numpy.exp(1j * rng.uniform(-numpy.pi, numpy.pi, len(spectrum))),
            n=len(floats)) + middle
        flattened = numpy.fft.irfft(
            numpy.exp(1j * numpy.angle(spectrum)) * amounts.mean(), n=len(floats)) + middle

        out.write("  %-24s %-9s %-14s %-14s %s\n"
                  % (name[:-4], "%.3f" % slope if slope is not None else "none",
                     "%.3f, %.3f" % (agreement(series, alone), exact(series, alone)),
                     "%.3f, %.3f" % (agreement(series, scrambled), exact(series, scrambled)),
                     "%.3f, %.3f" % (agreement(series, flattened), exact(series, flattened))))
        gathered.append((name[:-4], series, floats, spectrum, amounts, middle))

    out.write("\n  each cell is correlation, then the share of symbols that come back exactly\n")
    out.write("\n  angles rounded to a few steps, every amount kept\n")
    out.write("  %-24s %s\n" % ("corpus", "  ".join("%13s" % ("%d bit" % bits) for bits in BITS)))
    for label, series, floats, spectrum, amounts, middle in gathered:
        angles = numpy.angle(spectrum)
        row = []
        for bits in BITS:
            steps = 1 << bits
            rounded = numpy.round(angles / (2.0 * numpy.pi) * steps) * (2.0 * numpy.pi / steps)
            rebuilt = numpy.fft.irfft(numpy.exp(1j * rounded) * amounts, n=len(floats)) + middle
            row.append("%.3f, %.3f" % (agreement(series, rebuilt), exact(series, rebuilt)))
        out.write("  %-24s %s\n" % (label, "  ".join("%13s" % cell for cell in row)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
