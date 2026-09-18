#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Exact invariance over a partition, read as packed bits: which cells the object holds exactly that a
# drawn null never reaches.
#
#   Usage:  from measure.invariance import invariant_cells, null_union, surviving, phase_partition
#
# The engine measures departure from a shuffle of an object's own parts. This measure reads that
# departure as quanta, never as a magnitude. A partition groups the positions into cells. A cell is
# exactly invariant when every member holds one value, a bit-exact fact, one bit per cell in a bignum.
# The object's inspection is exact; the object itself stays a probability distribution. A single
# inspection rarely fills every cell. The null is drawn as the union of many shuffles of the same
# values under the same partition: any cell chance makes invariant is folded into the union. What the
# object holds that the union never reached is the structure. The reading is presence and a popcount, a
# cardinality of quanta. Nothing here divides, holds a ratio, compares an energy, or crosses a band.
#
# Two routes build the invariant-cell field and must agree: one tests every member against the first,
# the other tests the value the cell agrees on against every member. A route pair that cannot disagree
# is not evidence.

from reference.bitfield import only_in
from reference.shuffles import permuted, SEED


def phase_partition(length, period):
    """A partition of `length` positions into `period` cells by index modulo the period."""
    cells = [[] for _ in range(period)]
    for index in range(length):
        cells[index % period].append(index)
    return cells


def invariant_cells(values, cells):
    """Route A: bit c set iff every member of cell c holds the same value. Bit-exact, no reference value."""
    field = 0
    for position, members in enumerate(cells):
        if not members:
            continue
        first = values[members[0]]
        if all(values[index] == first for index in members):
            field |= 1 << position
    return field


def invariant_cells_by_consensus(values, cells):
    """Route B: bit c set iff the value the cell agrees on is held by every member. The same fact.

    The agreed value is the cell's most common member, a value the cell actually holds, never a mean.
    """
    field = 0
    for position, members in enumerate(cells):
        if not members:
            continue
        held = [values[index] for index in members]
        agreed = max(set(held), key=held.count)
        if held.count(agreed) == len(held):
            field |= 1 << position
    return field


def null_union(values, cells, draws, seed=SEED):
    """The union over `draws` shuffles of the invariant-cell field: every cell chance can make invariant.

    Each shuffle permutes the object's own values and reads the same partition. The null is drawn from
    the object. Drawing more shuffles can only grow the union. The surviving field
    can only shrink, the safe direction for a claim of structure.
    """
    union = 0
    for step in range(draws):
        shuffled = list(permuted(values, seed + step))
        union |= invariant_cells(shuffled, cells)
    return union


def surviving(values, cells, draws, seed=SEED):
    """The exact invariant cells the object holds that no shuffle in the drawn null ever reached."""
    return only_in(
        invariant_cells(values, cells), null_union(values, cells, draws, seed)
    )
