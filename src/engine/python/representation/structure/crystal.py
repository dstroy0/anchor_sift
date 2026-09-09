#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# A published crystal cell tiled into the arrangement it describes, and voxelized.
#
#   Usage:  from representation.structure.crystal import parse_cif, voxel_grid, VOXEL
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


def parse_cif(text):
    """Cell edges and fractional atom sites, for a cell whose angles are all right.

    Returns (cell, sites) where cell maps a, b, c, alpha, beta, gamma to floats and each site is
    (fx, fy, fz, element). Returns (None, None) where the cell is absent or is not right angled.
    """
    cell = {}
    for key in ("a", "b", "c", "alpha", "beta", "gamma"):
        tag = ("length_" + key) if len(key) == 1 else ("angle_" + key)
        found = re.search(r"_cell_%s\s+(\S+)" % tag, text)
        if not found:
            return None, None
        try:
            cell[key] = number(found.group(1))
        except ValueError:
            return None, None
    for angle in ("alpha", "beta", "gamma"):
        if abs(cell[angle] - 90.0) > RIGHT_ANGLE_SLACK:
            return None, None
    if min(cell["a"], cell["b"], cell["c"]) <= 0.0:
        return None, None

    lines = text.splitlines()
    sites = []
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
        wanted = ("_atom_site_fract_x", "_atom_site_fract_y", "_atom_site_fract_z")
        if not all(name in headers for name in wanted):
            continue
        spots = [headers.index(name) for name in wanted]
        kind = headers.index("_atom_site_type_symbol") if "_atom_site_type_symbol" in headers \
            else None
        while index < len(lines):
            row = lines[index].strip()
            if (not row) or row.startswith(("_", "#", "loop_", "data_")):
                break
            parts = row.split()
            if len(parts) >= len(headers):
                try:
                    sites.append((number(parts[spots[0]]), number(parts[spots[1]]),
                                  number(parts[spots[2]]),
                                  parts[kind] if kind is not None else "X"))
                except ValueError:
                    pass
            index += 1
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
