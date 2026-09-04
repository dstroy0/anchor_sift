#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Carry a set of any number of dimensions through one, against fields whose answer is known in advance,
# for Section 4.2 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/squash_dimensions.py
#
# Interleaving the bits of a column and a row carried a picture through a single dimension and returned
# its exponent halved, at 0.475 with a spread of 0.064 over seven paintings. Nothing in that argument is
# about two dimensions. A curve that fills a set of n dimensions covers its volume with a length, so a
# distance along the curve goes as the n-th power of a distance across the set and the exponent should
# come back divided by n.
#
# Every measurement behind that so far has been on a painting, where the true exponent is whatever the
# plane reports and there is nothing independent to check it against. Here the fields are built to a
# chosen exponent instead: white noise is shaped in the frequency domain so its power falls at a rate that
# is put in by hand, so the answer exists before the measurement and a wrong reading cannot be argued into
# agreement afterward. Fields are built in two, three and four dimensions at two different exponents, then
# read three ways: over the volume, along the interleaved index, and in storage order, which is the
# control that should fail as it fails on pictures.
#
# The reading also has to be checked at the bit width the corpora use, since a field is quantized to whole
# levels before it is read and that is where an approximate representation stops being exact.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spectral_exponent import exponent, fit_bands

SEED = 0x51F7
SIDES = {2: 512, 3: 64, 4: 24}
TARGETS = (2.0, 3.0)


def build(dims, side, slope, rng):
    """A field whose power falls at a chosen rate, quantized to whole levels the way a corpus is."""
    noise = rng.standard_normal((side,) * dims)
    spectrum = numpy.fft.fftn(noise)
    axes = numpy.meshgrid(*[numpy.fft.fftfreq(side) * side] * dims, indexing="ij")
    radius = numpy.sqrt(sum(axis ** 2 for axis in axes))
    radius[(0,) * dims] = 1.0
    shaped = spectrum * (radius ** (-slope / 2.0))
    shaped[(0,) * dims] = 0.0
    field = numpy.real(numpy.fft.ifftn(shaped))

    spread = field.std()
    if spread <= 0.0:
        return None
    # Held to eight bits, which is the width every corpus in this work is read at
    scaled = (field - field.mean()) / spread
    return numpy.clip(numpy.rint((scaled * 42.0) + 128.0), 0, 255).astype(numpy.uint8)


def volume_exponent(field):
    """Exponent of the power against radial frequency over the whole set, whatever its dimension."""
    floats = field.astype(numpy.float64)
    floats = floats - floats.mean()
    if floats.std() <= 0.0:
        return None, None
    power = numpy.abs(numpy.fft.fftshift(numpy.fft.fftn(floats))) ** 2
    side = field.shape[0]
    axes = numpy.meshgrid(*[numpy.arange(side) - (side // 2)] * field.ndim, indexing="ij")
    radius = numpy.sqrt(sum(axis.astype(numpy.float64) ** 2 for axis in axes))
    keep = radius >= 4.0
    return fit_bands(radius[keep], power[keep])


def interleave(field):
    """Read the set along an index taking one bit from each axis in turn."""
    side = field.shape[0]
    dims = field.ndim
    bits = int(numpy.ceil(numpy.log2(side)))
    axes = numpy.meshgrid(*[numpy.arange(side)] * dims, indexing="ij")

    index = numpy.zeros(field.size, dtype=numpy.uint64)
    for place in range(dims):
        coordinate = axes[place].ravel().astype(numpy.uint64)
        for bit in range(bits):
            picked = (coordinate >> numpy.uint64(bit)) & numpy.uint64(1)
            index |= picked << numpy.uint64((bit * dims) + place)
    return field.ravel()[numpy.argsort(index)]


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-6s %-7s %-8s %-10s %-11s %-11s %-9s %s\n"
              % ("dims", "side", "asked", "over set", "interleaved", "as stored",
                 "times n", "miss"))

    rng = numpy.random.default_rng(SEED)
    gathered = []
    for dims in sorted(SIDES):
        for target in TARGETS:
            field = build(dims, SIDES[dims], target, rng)
            if field is None:
                continue
            over, _ = volume_exponent(field)
            walked, _ = exponent(interleave(field))
            stored, _ = exponent(field.reshape(-1))
            if (over is None) or (walked is None) or (stored is None):
                continue
            lifted = walked * dims
            gathered.append((dims, over, walked, lifted))
            out.write("  %-6d %-7d %-8.2f %-10.3f %-11.3f %-11.3f %-9.3f %.3f\n"
                      % (dims, SIDES[dims], target, over, walked, stored, lifted, lifted - over))

    if gathered:
        misses = numpy.asarray([abs(row[3] - row[1]) for row in gathered])
        shares = numpy.asarray([row[2] / row[1] for row in gathered])
        out.write("\n  interleaved over the set, against the one over n predicted: %s\n"
                  % "  ".join("%d dims %.3f, predicted %.3f" % (row[0], row[2] / row[1], 1.0 / row[0])
                              for row in gathered[::2]))
        out.write("  miss after multiplying by n: mean %.3f, worst %.3f over %d fields\n"
                  % (float(misses.mean()), float(misses.max()), len(gathered)))
        out.write("  ratio spread across every field and dimension: %.3f\n" % float(shares.std()))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
