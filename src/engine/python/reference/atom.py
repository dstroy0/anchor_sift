#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The atom: a field n by n of vector magnitudes, read by presence. Core at the center, bands radiating out.
#
#   Usage:  from reference.atom import bands, occupancy, occupied_bands, valence
#
# The primitive is shaped like a physical atom. The dense core sits at the center of an n by n field.
# Each cell carries a vector from the core, and the squared magnitude of that vector is an exact integer.
# Cells that share a squared magnitude form a band, a shell radiating outward. The object writes a vector
# magnitude into each cell. A magnitude of zero is nothing and reads falsy. A nonzero magnitude is
# something and reads truthy. The engine does not store what the object is. It measures the presence
# pattern over the bands and reads the outermost band that holds something. That band is the valence.
#
# The squared magnitude is the exact quantum the inspection holds. Its root is irrational and is the
# continuum the quanta sample; the engine never takes the root. The field's configuration space is
# hyper-exponential, so the packed presence is a bignum and never a fixed width.

from reference.bitfield import pack, present


def position_vector(n, row, col):
    """The vector from the core at the center to a cell, in doubled integer coordinates.

    Doubling keeps the center exact for every n, odd or even, so a component is always an integer.
    """
    return (2 * row - (n - 1), 2 * col - (n - 1))


def radial_magnitude_squared(n, row, col):
    """The squared magnitude of a cell's position vector. An exact integer; its root is the continuum."""
    down, across = position_vector(n, row, col)
    return down * down + across * across


def bands(n):
    """The cells of an n by n field grouped into bands by squared radial magnitude, the core first.

    Returns a list of cell-index lists, innermost band first. A cell index is row times n plus column.
    """
    grouped = {}
    for row in range(n):
        for col in range(n):
            magnitude = radial_magnitude_squared(n, row, col)
            grouped.setdefault(magnitude, []).append(row * n + col)
    return [grouped[magnitude] for magnitude in sorted(grouped)]


def occupancy(magnitudes):
    """The cells the object filled with something, packed one bit per cell. A zero magnitude is nothing."""
    return pack(index for index, magnitude in enumerate(magnitudes) if magnitude != 0)


def occupied_bands(cells, band_list):
    """Bit b set iff band b holds something. Presence per shell, read from the occupancy field."""
    field = 0
    for position, members in enumerate(band_list):
        for cell in members:
            if cells & (1 << cell):
                field |= 1 << position
                break
    return field


def full_bands(cells, band_list):
    """Bit b set iff every cell in band b holds something. A shell fully occupied, an exact fact.

    Scattered noise fills a whole outer shell only by an accident a drawn null rarely reaches, so a full
    band that survives a shuffle is genuine shell structure, not coincidence.
    """
    field = 0
    for position, members in enumerate(band_list):
        if members and all(cells & (1 << cell) for cell in members):
            field |= 1 << position
    return field


def valence(cells, band_list):
    """The outermost band that holds something, read by measuring. Returns -1 when nothing is present."""
    occupied = occupied_bands(cells, band_list)
    if not present(occupied):
        return -1
    return occupied.bit_length() - 1
