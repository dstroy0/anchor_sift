#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-4-008
#
# Whether a summary is a dense representation or only a description.
#
#   Usage:  python examples/any_corpus/4_measure/what_a_summary_returns.py corpus.sym [more.sym ...]
#
# Every quantity refined in this work reduces a set to a few numbers, and whether that is a
# representation or a description turns on whether the set comes back from it. That question has an
# answer instead of an opinion.
#
# A frequency decomposition splits any set into how much of each frequency and where each sits.
# One number rebuilds nothing. Every amount with the positions thrown away rebuilds nothing. Every
# position with the amounts flattened rebuilds a great deal. Keeping both is the whole set and costs
# everything, and nothing was found in between.
#
# That is this work's own first proposition turning up as a measurement. A cheap invariant is a
# necessary condition, so it can reject quickly and can never reconstruct, and a summary that could
# do both would refute the propositions the rest of this rests on.
#
# Text fails differently and the difference decides how the number is read. A picture rebuilt to a
# correlation of 0.97 is the picture, since a sample landing a level or two off is invisible. A
# letter landing one code point off is a different letter, so the share of symbols returned exactly
# is the only measure that means anything for text, and it is far behind the correlation.
#
# The seating is swept too, because a share returned that moves when the alphabet is renumbered is
# not a property of the corpus. The Iliad returns the least of anything measured at 0.056, and the
# reason is that polytonic Greek needs 141 code points laid across a wide range.

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

from representation.seating import spread_of, tightest  # noqa: E402

CAP = 262144
BITS = (1, 2, 3, 4, 6, 8)
SEED = 0x51F7


def rebuilt_from_angles(series, bits):
    """The series rebuilt with every angle held to a few steps around the circle."""
    floats = series.astype(numpy.float64)
    middle = floats.mean()
    spectrum = numpy.fft.rfft(floats - middle)
    steps = 1 << bits
    angles = numpy.angle(spectrum)
    rounded = numpy.round(angles / (2.0 * numpy.pi) * steps) * (2.0 * numpy.pi / steps)
    return numpy.fft.irfft(numpy.exp(1j * rounded) * numpy.abs(spectrum), n=len(floats)) + middle


def agreement(original, rebuilt):
    first = original.astype(numpy.float64)
    first = first - first.mean()
    second = numpy.asarray(rebuilt, dtype=numpy.float64)
    second = second - second.mean()
    spread = float(first.std() * second.std())
    return float((first * second).mean() / spread) if spread > 0.0 else 0.0


def exactly(original, rebuilt):
    landed = numpy.clip(numpy.rint(rebuilt), 0, 255).astype(numpy.uint8)
    return float((landed == original).mean())


def main():
    if len(sys.argv) < 2:
        print("usage: what_a_summary_returns.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  each cell is the correlation, then the share of symbols returned exactly\n")
    out.write("  angles held to a few steps around the circle, every amount kept\n\n")
    out.write("  %-24s %-9s %s\n"
              % ("corpus", "spread", "  ".join("%13s" % ("%d bit" % bits) for bits in BITS)))

    gathered = []
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            series = numpy.frombuffer(handle.read(CAP), dtype=numpy.uint8)
        if len(series) < 65536:
            continue

        row = []
        for bits in BITS:
            rebuilt = rebuilt_from_angles(series, bits)
            row.append("%.3f, %.3f" % (agreement(series, rebuilt), exactly(series, rebuilt)))
        out.write("  %-24s %-9.2f %s\n"
                  % (os.path.basename(path)[:-4], spread_of(series),
                     "  ".join("%13s" % cell for cell in row)))
        gathered.append((os.path.basename(path)[:-4], series))

    if not gathered:
        out.flush()
        return 0

    out.write("\n  the same under the numbering the corpus converges to, which is the value a\n")
    out.write("  reading has to be taken at before it belongs to the corpus and not the file\n")
    out.write("  %-24s %-11s %-11s %-11s %s\n"
              % ("corpus", "spread as is", "tightest", "returned as is", "returned tightest"))
    for label, series in gathered:
        seated = tightest(series)
        was = exactly(series, rebuilt_from_angles(series, 3))
        now = exactly(seated, rebuilt_from_angles(seated, 3))
        out.write("  %-24s %-11.2f %-11.2f %-11.3f %.3f\n"
                  % (label, spread_of(series), spread_of(seated), was, now))

    out.write("\n  the correlation is worthless for text and the exact share is not. A sample\n")
    out.write("  landing two levels off cannot be seen; a letter landing one code point off\n")
    out.write("  is a different letter\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
