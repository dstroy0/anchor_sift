#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Carrying a set of any number of dimensions through one, without being told its shape.
#
#   Usage:  from partition.curves import interleaved, hilbert_order, spread_bits
#
# A reader handed a picture row by row cannot see the second dimension, because a pixel and the one
# below it sit a whole width apart in the file. Every measurement here was handed a width to work
# around that, and being handed a width means choosing a geometry and then measuring the choice. The
# picture reader returned heights instead of widths until the assignment was removed.
#
# Interleaving removes the need to supply one. Taking one bit from the column, then one from the row,
# then the next from each, gives an index where positions close in the set are close in the index.
# The set is then carried inside one dimension with nothing thrown away and no width supplied.
#
# What it costs is measured and is in two parts. Interleaving jumps whenever it crosses a block
# boundary, and a jump puts a step into the reading that no part of the set put there. Separately, a
# line cannot hold everything about a plane whatever path it takes. A Hilbert curve never jumps, so
# measuring along both separates the two: the jumps account for about 0.43 of the shortfall and the
# remaining 0.57 survives a curve with nothing to blame.
#
# The two do not have one winner. The Hilbert curve is the better reading of the exponent and the
# worse reading of the dimension count, because a jump is a block completing and which block
# completes is which axis just turned over. Removing the jumps removes the dimension count with them.

import numpy


def spread_bits(values):
    """Open a run of 16 bit values so each bit sits in every second place.

    That leaves the odd places empty for a second axis, letting two coordinates interleave into one
    index.
    """
    values = values.astype(numpy.uint64) & numpy.uint64(0x0000FFFF)
    values = (values | (values << numpy.uint64(8))) & numpy.uint64(0x00FF00FF)
    values = (values | (values << numpy.uint64(4))) & numpy.uint64(0x0F0F0F0F)
    values = (values | (values << numpy.uint64(2))) & numpy.uint64(0x33333333)
    values = (values | (values << numpy.uint64(1))) & numpy.uint64(0x55555555)
    return values


def interleaved(grid):
    """A two dimensional grid read along an index taking alternate bits from column and row."""
    rows, columns = grid.shape
    down, across = numpy.mgrid[0:rows, 0:columns]
    index = spread_bits(across.ravel()) | (spread_bits(down.ravel()) << numpy.uint64(1))
    return grid.ravel()[numpy.argsort(index)]


def interleave(field):
    """The same for a set of any number of dimensions, one bit from each axis in turn.

    A curve filling a set of n dimensions covers its volume with a length. A distance along the
    curve therefore goes as the n-th power of a distance across the set, and a scaling exponent read
    along it comes back divided by n. Measured against fields built to a known exponent, the ratio
    returns
    0.469, 0.285 and 0.185 in two, three and four dimensions against the half, third and quarter
    predicted, with the shortfall growing as the dimensions do.
    """
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


def hilbert_order(side, dims):
    """Position of every cell along a Hilbert curve, by Skilling's transform.

    Consecutive positions along it are always neighbors in the set. Interleaving lacks that
    property. The loops run over bits and axes, both few, while every cell is carried through them
    at once.
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
