#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# A published crystal cell tiled into the arrangement it describes, as exact points.
#
#   Usage:  from representation.structure.crystal import exact_points, parse_cif, voxel_grid
#
# THE POINTS ARE EXACT AND THE GRID IS NOT
#
# exact_points is the reading. A deposit writes its numbers as decimal text, 4.76050(5) and
# 0.35216(3), and that text is carried here as integers: a numerator and a count of decimal places,
# multiplied as integers, scaled as integers. A python integer is arbitrary precision. A position is
# therefore the deposited one and stays the deposited one. Nothing rounds and nothing is bounded.
#
# voxel_grid is the earlier reading and it is lossy by construction. It answers a cell edge to
# 0.0124 angstroms on average where the exact points answer it with an error of zero, and the
# difference is entirely the grid. Two bounds live in it. VOXEL fixes a resolution the deposit never
# asked for, and LONGEST_SIDE caps the tiling because a dense grid grows as the cube. Both are
# choices made here about somebody else's number.
#
# It is kept because the ledger's crystal numbers were measured through it and a superseded result
# has to stay readable. Nothing new should read a crystal that way.
#
# No other positive control in this work carries an answer nobody here produced. The
# Crystallography Open Database publishes the cell edge for every entry, so the
# periodicity is not inferred from the measurement: it is a number someone else measured, refereed
# and wrote down. Tiling a published cell reproduces the real arrangement, and the instrument is
# then handed the voxels and asked to return the edge with nothing told to it.
#
# Why that matters more than another memoryless control. A memoryless process can only show that an
# instrument does not invent structure. It cannot show that the instrument finds structure that is
# there, and this work reported a protein as unstructured twice before that distinction was drawn.
#
# Only cells with right angles are used. The fractional to Cartesian conversion is then a scaling
# per axis and no crystallographic machinery is needed to get the geometry right. A triclinic cell
# would need the full metric tensor, and getting that wrong quietly would put an error into the one
# control that is supposed to be beyond doubt.
#
# The voxel is the resolution the instrument is allowed. It is deliberately coarser than the edge is
# precise, because the claim being tested is that quantization moves the true period into the ratio
# between two lags instead of destroying it.

import re

import numpy

from representation import exact

# The column names a CIF gives fractional coordinates. A CIF names its columns in the loop header
# and their order is not fixed, so both readings below find them by name. Reading by position
# returns the occupancy where the z fraction should be on any entry carrying a Wyckoff letter.
FRACTIONS = ("_atom_site_fract_x", "_atom_site_fract_y", "_atom_site_fract_z")

# Tiles per axis for the exact reading. One cell holds one period, and one period cannot be told
# from noise. There is no cap on this one: the points are sparse, so the cost is linear in the tile
# count and not the cube of a grid side.
EXACT_TILES = 4

# Angstroms per voxel. Deliberately coarser than the published precision.
VOXEL = 0.25

# Voxels along the longest axis of the tiled grid. A cell is tiled as many times as fits under this,
# which keeps a large cell from asking for a grid nothing can hold.
LONGEST_SIDE = 320

# Tiles along each axis, before the cap above is applied. Three periods is the fewest that shows a
# period as a period instead of as an edge effect.
LEAST_TILES = 3
MOST_TILES = 6

# How far a cell angle may sit from a right angle and still be treated as one.
RIGHT_ANGLE_SLACK = 0.01


def number(text):
    """A CIF value carries its uncertainty in brackets, which is not part of the number."""
    return float(re.sub(r"\(.*?\)", "", text).strip())


def cell_text(text):
    """The six cell parameters as the strings the deposit wrote, or None where one is absent.

    Both readings start here. A change to how a cell is found then reaches the exact path and the
    voxel path together.
    """
    held = {}
    for key in ("a", "b", "c", "alpha", "beta", "gamma"):
        tag = ("length_" + key) if len(key) == 1 else ("angle_" + key)
        found = re.search(r"_cell_%s\s+(\S+)" % tag, text)
        if not found:
            return None
        held[key] = found.group(1)
    return held


def site_text(text):
    """Every atom site as the strings the deposit wrote: (x, y, z, element).

    The loop header is walked for the column names, and a site whose row is short of the header is
    skipped. An entry with no element column gets X, which keeps every site distinguishable from an
    empty place without inventing a chemistry for it.
    """
    lines = text.splitlines()
    rows = []
    index = 0
    while index < len(lines):
        if lines[index].strip() != "loop_":
            index += 1
            continue
        index += 1
        headers = []
        while index < len(lines) and lines[index].strip().startswith("_"):
            headers.append(lines[index].strip())
            index += 1
        if not all(name in headers for name in FRACTIONS):
            continue
        spots = [headers.index(name) for name in FRACTIONS]
        kind = headers.index("_atom_site_type_symbol") if "_atom_site_type_symbol" in headers \
            else None
        while index < len(lines):
            row = lines[index].strip()
            if (not row) or row.startswith(("_", "#", "loop_", "data_")):
                break
            parts = row.split()
            if len(parts) >= len(headers):
                rows.append((parts[spots[0]], parts[spots[1]], parts[spots[2]],
                             parts[kind] if kind is not None else "X"))
            index += 1
    return rows


def right_angled(raw):
    """Whether a raw cell's three angles all sit inside RIGHT_ANGLE_SLACK of a right angle.

    A right angled cell converts fractional to Cartesian by a scaling per axis. A triclinic one
    needs the full metric tensor, and getting that wrong quietly would put an error into the one
    control in this work that is supposed to be beyond doubt.
    """
    try:
        return all(abs(number(raw[angle]) - 90.0) <= RIGHT_ANGLE_SLACK
                   for angle in ("alpha", "beta", "gamma"))
    except ValueError:
        return False


def exact_points(text, tiles=EXACT_TILES, digits=exact.SCALE_DIGITS):
    """A deposited cell tiled into exact integer points carrying an element.

    Each point is ((a, b, c), element) with the coordinates integers at representation.exact.SCALE.
    A fractional coordinate plus a whole tile, times a cell edge, is a product of two decimals. It
    is carried through as integers, leaving a position that is the deposited one and not an
    approximation of it. There is no grid, no voxel, no truncation and no nearest anything.

    Returns (points, edges) with the published edges as exact integers at the same scale, the form
    an oracle compares against. Returns (None, None) where the cell is absent, is not right angled,
    holds no sites, or is written in something other than plain decimal text.

    Raises exact.WillNotFit where `digits` is too small to hold the deposit. That one is not caught
    and turned into a missing entry, because a scale dropping digits has to be visible as a scale
    dropping digits.
    """
    raw = cell_text(text)
    if (raw is None) or (not right_angled(raw)):
        return None, None
    rows = site_text(text)
    if not rows:
        return None, None

    try:
        edges = [exact.units(raw[key]) for key in ("a", "b", "c")]
        if any(edge[0] <= 0 for edge in edges):
            return None, None
        points = []
        for step_a in range(tiles):
            for step_b in range(tiles):
                for step_c in range(tiles):
                    offsets = (step_a, step_b, step_c)
                    for row in rows:
                        along = []
                        for axis in range(3):
                            fraction = exact.shifted(exact.units(row[axis]), offsets[axis])
                            along.append(exact.at_scale(*exact.product(fraction, edges[axis]),
                                                        digits=digits))
                        points.append(((along[0], along[1], along[2]), row[3]))
        published = tuple(exact.at_scale(*edge, digits=digits) for edge in edges)
    except exact.WillNotFit:
        raise
    except ValueError:
        return None, None
    return points, published


def parse_cif(text):
    """Cell edges and fractional atom sites, for a cell whose angles are all right.

    The float reading, kept for the voxel path below and for everything already written against it.
    New work reaches for exact_points.

    Returns (cell, sites) where cell maps a, b, c, alpha, beta, gamma to floats and each site is
    (fx, fy, fz, element). Returns (None, None) where the cell is absent or is not right angled.
    """
    raw = cell_text(text)
    if (raw is None) or (not right_angled(raw)):
        return None, None
    cell = {}
    for key, value in raw.items():
        try:
            cell[key] = number(value)
        except ValueError:
            return None, None
    if min(cell["a"], cell["b"], cell["c"]) <= 0.0:
        return None, None

    sites = []
    for along_a, along_b, along_c, element in site_text(text):
        try:
            sites.append((number(along_a), number(along_b), number(along_c), element))
        except ValueError:
            pass
    return cell, sites


def tiles_for(cell, voxel=VOXEL, longest=LONGEST_SIDE):
    """How many times to tile the cell along each axis, capped so the grid stays affordable.

    Returns None where even the fewest tiles would not fit, which is a cell too large to read at
    this voxel.
    """
    widest = max(cell["a"], cell["b"], cell["c"])
    room = int(longest * voxel / widest)
    if room < LEAST_TILES:
        return None
    return min(room, MOST_TILES)


def voxel_grid(cell, sites, voxel=VOXEL, tiles=None):
    """The tiled cell as a grid of element codes, zero where nothing sits.

    A later site landing on an occupied voxel overwrites it. The dictionary this replaced did the
    same, and it reads honestly: at this resolution the two atoms are one voxel.

    Returns (grid, codes) where codes maps an element symbol to the value standing for it, or
    (None, None) where the cell cannot be tiled.
    """
    if tiles is None:
        tiles = tiles_for(cell, voxel)
    if (tiles is None) or (not sites):
        return None, None

    shape = tuple(max(1, int(round(tiles * cell[axis] / voxel))) for axis in ("a", "b", "c"))
    if min(shape) < 8:
        return None, None

    codes = {}
    for _, _, _, element in sites:
        if element not in codes:
            # Zero stands for an empty voxel, so the first element takes one.
            codes[element] = (len(codes) % 255) + 1

    grid = numpy.zeros(shape, dtype=numpy.uint8)
    edges = (cell["a"], cell["b"], cell["c"])

    for step_a in range(tiles):
        for step_b in range(tiles):
            for step_c in range(tiles):
                offsets = (step_a, step_b, step_c)
                for fractions in (sites,):
                    for site in fractions:
                        placed = []
                        for axis in range(3):
                            along = (site[axis] + offsets[axis]) * edges[axis] / voxel
                            placed.append(int(along) % shape[axis])
                        grid[placed[0], placed[1], placed[2]] = codes[site[3]]
    return grid, codes
