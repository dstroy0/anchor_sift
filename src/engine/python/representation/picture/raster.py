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
# The widths below are what the decoder reported when these files were fetched. The plane is known
# here instead of guessed at. Two readings in this work set out to recover a width from the data and
# are scored against this table. Without them, a table of answers would not belong in the tree.
#
# The center crop is not a convenience either. A short read of a row major file is a thin strip, and
# a radial average over a strip is not a radial average over a picture. Reading the crop instead made
# the exponent climb from 1.21 to 2.06 on one painting with nothing else changed.
#
# A grid here is (cells, shape): the bytes row by row, and (rows, width) beside them, the form
# measure/period.py reads a volume in. Every step is integer arithmetic on those bytes.

import operator

from reference.exact_ratio import reduced

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

    `data` is the file's bytes. Returns (cells, (rows, width)) with `cells` the whole rows as bytes,
    or None where the width leaves fewer than `LEAST_SIDE` whole rows.
    """
    rows = len(data) // width
    if rows < LEAST_SIDE:
        return None
    return bytes(data[:rows * width]), (rows, width)


def center_crop(grid, share):
    """The middle `share` of each side, which keeps the picture's proportions while its area changes.

    Reading the first n bytes instead gives a strip as wide as the picture and a few rows deep, and
    every reading over it describes the strip.

    `grid` is (cells, (rows, width)) and `share` is an exact ratio, a (numerator, denominator) pair of
    integers. A side keeps the whole number of rows or columns at or below its share, and never
    fewer than `LEAST_SIDE`. A float share raises TypeError.
    """
    cells, (rows, across) = grid
    numerator, denominator = reduced(operator.index(share[0]), operator.index(share[1]))
    high = max(LEAST_SIDE, (rows * numerator) // denominator)
    wide = max(LEAST_SIDE, (across * numerator) // denominator)
    top = (rows - high) // 2
    left = (across - wide) // 2
    # A slice past either end stops at the end, the way a slice of the rows and columns did
    kept_rows = range(rows)[top:top + high]
    kept_columns = range(across)[left:left + wide]
    start = kept_columns.start if kept_columns else 0
    cropped = b"".join(
        cells[(row * across) + start:(row * across) + start + len(kept_columns)]
        for row in kept_rows)
    return cropped, (len(kept_rows), len(kept_columns))


def as_points(grid, levels=LEVELS, most=MOST_ACROSS):
    """A plane as a cloud: one point per pixel kept, carrying its value at a coarser resolution.

    Thinned so the longest side is at most `most`, since a nearest neighbor search compares every
    point against every other. `grid` is (cells, (rows, width)). Returns (coordinates, values), each
    coordinate an integer pair (column, row) in the thinned plane and each value an integer, or
    (None, None) where thinning leaves too few points to describe.
    """
    cells, (rows, across) = grid
    step = max(1, max(rows, across) // most)
    kept_rows = range(0, rows, step)
    kept_columns = range(0, across, step)
    if (len(kept_rows) < 24) or (len(kept_columns) < 24):
        return None, None

    shift = 0
    while (1 << (8 - shift)) > levels:
        shift += 1
    coords = []
    values = []
    for down, row in enumerate(kept_rows):
        for sideways, column in enumerate(kept_columns):
            coords.append((sideways, down))
            values.append(cells[(row * across) + column] >> shift)
    return coords, values
