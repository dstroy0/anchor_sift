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
# line cannot hold everything about a plane whatever path it takes. A Hilbert curve never jumps.
# Measuring along both separates the two: the jumps account for about 0.43 of the shortfall and the
# remaining 0.57 survives a curve with nothing to blame.
#
# The two do not have one winner. The Hilbert curve is the better reading of the exponent and the
# worse reading of the dimension count, because a jump is a block completing and which block
# completes is which axis just turned over. Removing the jumps removes the dimension count with them.
#
# A set here is (cells, shape): the cells in row major order, the last axis fastest, with the shape
# beside them, the form measure/period.py reads a volume in. Every index is built from the cell's
# whole coordinates by shifts, masks and ors on Python integers, which have no width to overflow. A
# cell's place along a curve is its index's rank among all the indices. Two cells share an index only
# in interleaved past a side of 65536, where spread_bits reads the low 16 bits, and the tie keeps
# row major order.

import itertools
import operator


def _bits(side):
    """Bits to hold every coordinate below `side`: the least b with 2^b >= side."""
    return (side - 1).bit_length()


def _cells_in_order(shape):
    """The whole coordinates of every cell, in row major order."""
    return itertools.product(*[range(extent) for extent in shape])


def _rank(indices):
    """Positions 0 to n - 1 ordered by their index, smallest first."""
    return sorted(range(len(indices)), key=indices.__getitem__)


def spread_bits(values):
    """Open a run of 16 bit values so each bit sits in every second place.

    That leaves the odd places empty for a second axis, letting two coordinates interleave into one
    index. Each value is an integer, and only its low 16 bits are read.
    """
    out = []
    for value in values:
        value = operator.index(value) & 0x0000FFFF
        value = (value | (value << 8)) & 0x00FF00FF
        value = (value | (value << 4)) & 0x0F0F0F0F
        value = (value | (value << 2)) & 0x33333333
        value = (value | (value << 1)) & 0x55555555
        out.append(value)
    return out


def interleaved(grid):
    """A two dimensional grid read along an index taking alternate bits from column and row.

    `grid` is (cells, (rows, columns)). Returns the cells in that order, as a list.
    """
    cells, (rows, columns) = grid
    down = [row for row in range(rows) for _ in range(columns)]
    across = [column for _ in range(rows) for column in range(columns)]
    index = [one | (two << 1) for one, two in zip(spread_bits(across), spread_bits(down))]
    return [cells[place] for place in _rank(index)]


def interleave(field):
    """The same for a set of any number of dimensions, one bit from each axis in turn.

    A curve filling a set of n dimensions covers its volume with a length. A distance along the
    curve therefore goes as the n-th power of a distance across the set, and a scaling exponent read
    along it comes back divided by n. Measured against fields built to a known exponent, the ratio
    returns
    0.469, 0.285 and 0.185 in two, three and four dimensions against the half, third and quarter
    predicted, with the shortfall growing as the dimensions do.

    `field` is (cells, shape) with every side equal. Returns the cells in that order, as a list.
    """
    cells, shape = field
    side = shape[0]
    dims = len(shape)
    bits = _bits(side)
    index = []
    for coordinates in _cells_in_order((side,) * dims):
        value = 0
        for place, coordinate in enumerate(coordinates):
            for bit in range(bits):
                value |= ((coordinate >> bit) & 1) << ((bit * dims) + place)
        index.append(value)
    return [cells[place] for place in _rank(index)]


def hilbert_order(side, dims):
    """Position of every cell along a Hilbert curve, by Skilling's transform.

    Consecutive positions along it are always neighbors in the set. Interleaving lacks that
    property. Each cell is carried through the transform on its own, over bits and axes, both few.
    Returns the row major positions of the cells in curve order, as a list.
    """
    bits = _bits(side)
    top = 1 << (bits - 1)
    index = []
    for coordinates in _cells_in_order((side,) * dims):
        coords = list(coordinates)

        # Undo the excess work, which turns the plain binary corner into the Hilbert one
        step = top
        while step > 1:
            mask = step - 1
            for place in range(dims):
                carried = (coords[0] ^ coords[place]) & mask
                if coords[place] & step:
                    coords[0] ^= mask
                else:
                    coords[0] ^= carried
                    coords[place] ^= carried
            step >>= 1

        for place in range(1, dims):
            coords[place] ^= coords[place - 1]

        trailing = 0
        step = top
        while step > 1:
            if coords[dims - 1] & step:
                trailing ^= step - 1
            step >>= 1
        for place in range(dims):
            coords[place] ^= trailing

        value = 0
        for bit in range(bits):
            for place in range(dims):
                value |= ((coords[place] >> bit) & 1) << ((bit * dims) + (dims - 1 - place))
        index.append(value)
    return _rank(index)
