#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Separate what a curve costs from what folding dimensions costs, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/curve_floor.py
#
# Reading a set of n dimensions along an index that interleaves its coordinates returns the exponent
# divided by n, and every reading comes back low: 0.469, 0.285 and 0.185 against the half, third and
# quarter predicted, with the shortfall growing as the dimensions do.
#
# Two different things could be behind that and they have different consequences. Interleaving jumps
# whenever it crosses a block boundary, sometimes across the whole set, and a jump puts a step into the
# reading that no part of the field put there. That is a fault of the particular curve. Separately, a line
# cannot hold everything about a plane whatever path it takes, and that cost belongs to the folding and
# not to any curve.
#
# They come apart because a Hilbert curve never jumps: consecutive positions along it are always
# neighbours in the set, which is the property interleaving lacks. Measuring the same fields along both
# leaves the difference as what the jumps cost and the remainder as what folding costs. A floor that
# survives the better curve is the part a single dimension cannot carry.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spectral_exponent import exponent
from squash_dimensions import SIDES, TARGETS, build, interleave, volume_exponent

SEED = 0x51F7


def hilbert_order(side, dims):
    """Position of every cell along a Hilbert curve, by Skilling's transform.

    The loops run over bits and axes, which are few, while every cell is carried through them at once.
    """
    bits = int(numpy.ceil(numpy.log2(side)))
    axes = numpy.meshgrid(*[numpy.arange(side, dtype=numpy.uint64)] * dims, indexing="ij")
    coords = [axis.ravel().copy() for axis in axes]

    # Undo the excess work, which turns the plain binary corner into the Hilbert one
    step = numpy.uint64(1) << numpy.uint64(bits - 1)
    while step > 1:
        mask = step - numpy.uint64(1)
        for place in range(dims):
            swap = (coords[place] & step) != 0
            carried = (coords[0] ^ coords[place]) & mask
            coords[0] = numpy.where(swap, coords[0] ^ mask, coords[0] ^ carried)
            coords[place] = numpy.where(swap, coords[place], coords[place] ^ carried)
        step >>= numpy.uint64(1)

    for place in range(1, dims):
        coords[place] ^= coords[place - 1]

    trailing = numpy.zeros_like(coords[0])
    step = numpy.uint64(1) << numpy.uint64(bits - 1)
    while step > 1:
        trailing ^= numpy.where((coords[dims - 1] & step) != 0, step - numpy.uint64(1),
                                numpy.uint64(0))
        step >>= numpy.uint64(1)
    for place in range(dims):
        coords[place] ^= trailing

    index = numpy.zeros_like(coords[0])
    for bit in range(bits):
        for place in range(dims):
            picked = (coords[place] >> numpy.uint64(bit)) & numpy.uint64(1)
            index |= picked << numpy.uint64((bit * dims) + (dims - 1 - place))
    return numpy.argsort(index)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-6s %-8s %-10s %-11s %-11s %-11s %s\n"
              % ("dims", "asked", "over set", "interleaved", "hilbert", "predicted", "floor left"))

    rng = numpy.random.default_rng(SEED)
    remaining = []
    for dims in (2, 3):
        walk = hilbert_order(SIDES[dims], dims)
        for target in TARGETS:
            field = build(dims, SIDES[dims], target, rng)
            if field is None:
                continue
            over, _ = volume_exponent(field)
            morton, _ = exponent(interleave(field))
            hilbert, _ = exponent(field.reshape(-1)[walk])
            if (over is None) or (morton is None) or (hilbert is None):
                continue
            predicted = over / dims
            remaining.append((dims, target, predicted - morton, predicted - hilbert))
            out.write("  %-6d %-8.2f %-10.3f %-11.3f %-11.3f %-11.3f %.3f\n"
                      % (dims, target, over, morton, hilbert, predicted, predicted - hilbert))

    if remaining:
        jumps = numpy.asarray([row[2] for row in remaining])
        folds = numpy.asarray([row[3] for row in remaining])
        out.write("\n  shortfall while interleaving: mean %.3f\n" % float(jumps.mean()))
        out.write("  shortfall on a curve that never jumps: mean %.3f\n" % float(folds.mean()))
        out.write("  share of it the jumps were responsible for: %.3f\n"
                  % (1.0 - (float(folds.mean()) / float(jumps.mean())) if jumps.mean() else 0.0))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
