#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# A row major file of bytes put back into the plane it came from.
#
#   Usage:  from representation.picture.raster import WIDTHS, as_grid, as_points
#
# A picture stored row by row puts two positions that sit one above each other a whole width apart in
# the file. A reader that does not know the width cannot see the second dimension at all. That made
# the bit volume return heights, and it forced every measurement since to be handed a width it should
# not have needed.
#
# The widths below are what the decoder reported when these files were fetched, so the plane is known
# here instead of guessed at. Two readings in this work set out to recover a width from the data and
# are scored against this table. Without them, a table of answers would not belong in the tree.
#
# The center crop is not a convenience either. A short read of a row major file is a thin strip, and
# a radial average over a strip is not a radial average over a picture. Reading the crop instead made
# the exponent climb from 1.21 to 2.06 on one painting with nothing else changed.

import numpy

# Reported by the decoder when these files were fetched.
WIDTHS = {
    "art_seurat": 960,
    "art_starry": 960,
    "art_whistler": 960,
    "art_turner": 960,
    "art_mondrian": 595,
    "art_hokusai": 960,
    "art_vermeer": 960,
}

# Rows or columns below this leave a piece too small for a radial average to describe.
LEAST_SIDE = 64

# Levels a picture is quantized to before its points are grouped by value. At 256 levels a value
# recurs too rarely to have neighbors of its own.
LEVELS = 32

# Longest side a thinned cloud keeps, since comparing points is quadratic in their count.
MOST_ACROSS = 200


def as_grid(data, width):
    """The file as a plane at one width, dropping whatever partial final row is left over.

    Returns None where the width leaves fewer than `LEAST_SIDE` whole rows.
    """
    rows = len(data) // width
    if rows < LEAST_SIDE:
        return None
    return data[:rows * width].reshape(rows, width)


def center_crop(grid, share):
    """The middle `share` of each side, which keeps the picture's proportions while its area changes.

    Reading the first n bytes instead gives a strip as wide as the picture and a few rows deep, and
    every reading over it describes the strip.
    """
    rows, across = grid.shape
    high = max(LEAST_SIDE, int(rows * share))
    wide = max(LEAST_SIDE, int(across * share))
    top = (rows - high) // 2
    left = (across - wide) // 2
    return grid[top:top + high, left:left + wide]


def as_points(grid, levels=LEVELS, most=MOST_ACROSS):
    """A plane as a cloud: one point per pixel kept, carrying its value at a coarser resolution.

    Thinned so the longest side is at most `most`, since a nearest neighbor search compares every
    point against every other. Returns (coordinates, values), or (None, None) where thinning leaves
    too few points to describe.
    """
    step = max(1, max(grid.shape) // most)
    thinned = grid[::step, ::step]
    rows, across = thinned.shape
    if (rows < 24) or (across < 24):
        return None, None

    down, sideways = numpy.mgrid[0:rows, 0:across]
    coords = numpy.stack([sideways.ravel(), down.ravel()], axis=1).astype(numpy.float64)
    shift = 0
    while (1 << (8 - shift)) > levels:
        shift += 1
    return coords, (thinned.ravel() >> shift).astype(numpy.int64)
