#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure how much of a set a summary can put back, for Section 4.11 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/regeneration_limit.py
#
# Everything measured in this work reduces a set to a few numbers: an exponent, a count of dimensions, a
# period. Whether that is a dense representation or only a description turns on whether the set can be
# built back from it, and that is a question with an answer instead of an opinion.
#
# A transform splits any set into how much of each frequency it holds and where each frequency sits. The
# exponent measured throughout here is a summary of the first of those and says nothing at all about the
# second. Oppenheim and Lim showed in 1981 that for pictures the second carries nearly everything: a
# picture rebuilt from its own positions and flat amounts stays recognizable, and one rebuilt from its own
# amounts and scrambled positions does not.
#
# So four reconstructions are compared against the original. One keeps only the exponent, which is the
# summary this work has been refining, and is the cheapest at a single number. One keeps every amount and
# discards the positions. One keeps every position and discards the amounts. One keeps both, which is the
# whole set and costs everything.
#
# The comparison is a correlation against the original, and beside it the count of numbers each rebuild
# needed. That ratio is the answer to how densely a set can be held and put back.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spectral_exponent import WIDTHS, exponent_plane

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
# Steps around the circle each angle is rounded to, since an angle is knowable and the question is at what
# precision it has to be held
BITS = (1, 2, 3, 4, 6)


def agreement(left, right):
    """Correlation between two grids, which is how much of one the other put back."""
    first = left.astype(numpy.float64).ravel()
    second = right.astype(numpy.float64).ravel()
    first = first - first.mean()
    second = second - second.mean()
    spread = float(first.std() * second.std())
    return float((first * second).mean() / spread) if spread > 0.0 else 0.0


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-16s %-9s %-12s %-12s %-12s %s\n"
              % ("picture", "exponent", "one number", "amounts only", "positions only", "numbers kept"))

    rng = numpy.random.default_rng(SEED)
    gathered = []
    for label in sorted(WIDTHS):
        path = os.path.join(CORPORA, "%s.sym" % label)
        if not os.path.isfile(path):
            continue
        width = WIDTHS[label]
        with open(path, "rb") as handle:
            whole = numpy.frombuffer(handle.read(), dtype=numpy.uint8)
        rows = len(whole) // width
        if rows < 128:
            continue
        grid = whole[:rows * width].reshape(rows, width).astype(numpy.float64)
        slope, _ = exponent_plane(grid.reshape(-1).astype(numpy.uint8), width)
        if slope is None:
            continue

        spectrum = numpy.fft.fft2(grid - grid.mean())
        amounts = numpy.abs(spectrum)
        positions = numpy.exp(1j * numpy.angle(spectrum))

        # A field built to the same exponent and nothing else, which is one number of storage
        down = numpy.fft.fftfreq(rows) * rows
        across = numpy.fft.fftfreq(width) * width
        radius = numpy.sqrt((down[:, None] ** 2) + (across[None, :] ** 2))
        radius[0, 0] = 1.0
        seeded = numpy.fft.fft2(rng.standard_normal(grid.shape))
        alone = numpy.real(numpy.fft.ifft2(seeded * (radius ** (-slope / 2.0))))

        # Every amount kept and every position thrown away, then the reverse
        scrambled = numpy.real(numpy.fft.ifft2(
            amounts * numpy.exp(1j * rng.uniform(-numpy.pi, numpy.pi, grid.shape))))
        flattened = numpy.real(numpy.fft.ifft2(positions * amounts.mean()))

        out.write("  %-16s %-9.3f %-12.3f %-12.3f %-12.3f %d against %d\n"
                  % (label, slope, agreement(grid, alone), agreement(grid, scrambled),
                     agreement(grid, flattened), 1, grid.size))
        gathered.append((label, grid, spectrum, amounts))

    out.write("\n  One number and every amount both rebuild the roughness and none of the picture.\n")
    out.write("  Positions carry it, and the question left is at what precision.\n\n")

    # An angle is knowable and the earlier claim that positions cost as much as the whole set assumed
    # every angle at full precision. Rounding each to a few steps around the circle is the cheaper claim
    # and it is measurable: the cost is bits for each coefficient, not one number for the set.
    out.write("  positions rounded to a few steps around the circle, amounts kept flat\n")
    out.write("  %-16s %s\n" % ("picture", "  ".join("%9s" % ("%d bit" % bits) for bits in BITS)))
    for label, grid, spectrum, amounts in gathered:
        angles = numpy.angle(spectrum)
        row = []
        for bits in BITS:
            steps = 1 << bits
            rounded = numpy.round(angles / (2.0 * numpy.pi) * steps) * (2.0 * numpy.pi / steps)
            rebuilt = numpy.real(numpy.fft.ifft2(numpy.exp(1j * rounded) * amounts.mean()))
            row.append(agreement(grid, rebuilt))
        out.write("  %-16s %s\n" % (label, "  ".join("%9.3f" % value for value in row)))

    out.write("\n  positions rounded the same way, with every amount kept\n")
    out.write("  %-16s %s\n" % ("picture", "  ".join("%9s" % ("%d bit" % bits) for bits in BITS)))
    for label, grid, spectrum, amounts in gathered:
        angles = numpy.angle(spectrum)
        row = []
        for bits in BITS:
            steps = 1 << bits
            rounded = numpy.round(angles / (2.0 * numpy.pi) * steps) * (2.0 * numpy.pi / steps)
            rebuilt = numpy.real(numpy.fft.ifft2(numpy.exp(1j * rounded) * amounts))
            row.append(agreement(grid, rebuilt))
        out.write("  %-16s %s\n" % (label, "  ".join("%9.3f" % value for value in row)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
