#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The symmetry operations a deposit publishes, applied exactly.
#
#   Usage:  from representation.structure.symmetry import operations, expand, SYM_SCALE
#
# WHAT A DEPOSIT LEAVES OUT AND WHY IT MATTERS HERE
#
# A CIF does not list every atom in the cell. It lists the asymmetric unit, the smallest part from
# which the rest follows, and it publishes the operations that generate the rest in
# _symmetry_equiv_pos_as_xyz: 'x,y,z', '-y,x-y,z', 'x+1/2,-y+1/2,z'. The full cell is the asymmetric
# unit carried through every one of them.
#
# Reading the atom site loop alone therefore reads a fraction of the structure. For doping that is
# not a detail. Two elements can be published on one asymmetric site and be obvious, or they can be
# published on sites that only become the same place after an operation is applied, and the second
# kind is invisible to anything that does not expand.
#
# A THIRD HAS NO DECIMAL, AT ANY SCALE
#
# This is the whole reason this module carries its own scale instead of using representation.exact
# directly. A translation of 1/2 is 0.5 exactly. A translation of 1/3 is not a decimal at all:
# 10**D factors into 2**D and 5**D and three divides neither, so no number of decimal places holds
# a third. The scale in exact.py is enormous and it does not help, because the problem is not size.
#
# A trigonal or hexagonal space group is full of thirds. '-y,x-y,z' with 'x+2/3,y+1/3,z+1/3' is an
# ordinary R centred operation, and the corpus is full of R-3 and R-3c. Carrying those through a
# decimal scale would round them, and a rounded symmetry copy lands next to the atom it should have
# landed on rather than on it, so two sites that are one place stop comparing equal and the doping
# at that place disappears. The failure would be silent and would look like an absence of doping.
#
# So coordinates here are integers in units of 1/(UNITS * 10**SCALE_DIGITS). The deposit's decimals
# are exact at 10**SCALE_DIGITS and the symmetry translations are exact at UNITS, and every value in
# the path is an integer in the product of the two.
#
# WHY UNITS IS 24 AND WHAT HAPPENS WHEN IT IS NOT ENOUGH
#
# Space group translations are built from halves, thirds, quarters, sixths and eighths. The eighths
# are real and easy to forget: Fd-3m in its second origin choice carries 1/8. The least common
# multiple of 1, 2, 3, 4, 6 and 8 is 24, so 24 holds every translation the 230 space groups use in
# their standard settings.
#
# A denominator that does not divide 24 raises rather than rounding. That is the same rule
# exact.WillNotFit follows one module over and for the same reason: a setting this does not cover is
# a setting this must refuse, because the alternative is a quiet displacement that nothing
# downstream can see.

import re

from representation import exact

# Denominator the translations are carried over. See the header for why 24 and not 12.
UNITS = 24

# One whole cell edge, in the units this module works in. A coordinate is reduced modulo this, since
# a symmetry copy one cell over is the same place in the arrangement.
SYM_SCALE = UNITS * (10 ** exact.SCALE_DIGITS)

# The tag a CIF gives its operations under. Both spellings occur: the first is the current one and
# the second is what older deposits wrote, and the corpus holds plenty of both.
TAGS = ("_space_group_symop_operation_xyz", "_symmetry_equiv_pos_as_xyz")

TERM = re.compile(r"([+-]?)\s*(?:(\d+)\s*/\s*(\d+)|(\d*\.\d+)|(\d+)|([xyz]))")


class WillNotDivide(ValueError):
    """A translation whose denominator does not divide UNITS.

    Its own class so a caller can tell it from unparsable text, exactly as exact.WillNotFit is kept
    apart from a ValueError. Unparsable text is an operation this does not understand. This is an
    operation it understands and a scale that cannot hold it, and the two want opposite responses.
    """


def component(text):
    """One component of an operation, as (cx, cy, cz, translation in units of 1/UNITS).

    'x' gives (1, 0, 0, 0). '-y' gives (0, -1, 0, 0). 'x-y' gives (1, -1, 0, 0).
    'y+2/3' gives (0, 1, 0, 16), since two thirds is sixteen twenty fourths.

    Raises WillNotDivide where a denominator does not divide UNITS, and ValueError where the text is
    not an operation component at all.
    """
    body = text.strip().lower().replace(" ", "")
    if not body:
        raise ValueError("%r is not an operation component" % text)

    axes = {"x": 0, "y": 0, "z": 0}
    translation = 0
    seen = 0
    for sign, top, bottom, decimal, whole, axis in TERM.findall(body):
        seen += 1
        way = -1 if sign == "-" else 1
        if axis:
            axes[axis] += way
        elif bottom:
            denominator = int(bottom)
            if denominator == 0:
                raise ValueError("%r divides by zero" % text)
            if (UNITS % denominator) != 0:
                raise WillNotDivide(
                    "%r has denominator %d, which does not divide %d"
                    % (text, denominator, UNITS))
            translation += way * int(top) * (UNITS // denominator)
        elif decimal:
            # A deposit occasionally writes 0.5 where it means 1/2. Carried through the same exact
            # path: the decimal is read exactly and then required to land on a whole unit.
            numerator, places = exact.units(decimal)
            scaled = numerator * UNITS
            if (scaled % (10 ** places)) != 0:
                raise WillNotDivide("%r is not a whole %dth" % (text, UNITS))
            translation += way * (scaled // (10 ** places))
        elif whole:
            translation += way * int(whole) * UNITS

    if not seen:
        raise ValueError("%r is not an operation component" % text)
    return axes["x"], axes["y"], axes["z"], translation


def operations(text):
    """Every symmetry operation the deposit publishes, as three components each.

    Returns a list of operations, each a tuple of three (cx, cy, cz, translation) rows, one per
    output axis. An entry publishing no operations gets the identity alone, which is the honest
    reading: the deposit said nothing, so the only copy known is the one written down.

    Duplicate operations are dropped. A deposit repeating 'x,y,z' does not have two identities.
    """
    found = []
    for tag in TAGS:
        # The operations sit in a loop, one per line, usually quoted. Both the quoted and bare
        # spellings occur and the corpus holds both.
        block = re.search(r"%s\s*\n(.*?)(?=\n\s*(?:loop_|_|$))" % re.escape(tag), text,
                          re.DOTALL)
        if not block:
            continue
        for line in block.group(1).splitlines():
            row = line.strip().strip("'\"").strip()
            if (not row) or row.startswith(("#", "_", "loop_", "data_")):
                continue
            # A leading ordinal is common: "1 x,y,z".
            row = re.sub(r"^\d+\s+", "", row)
            parts = row.split(",")
            if len(parts) != 3:
                continue
            try:
                found.append(tuple(component(one) for one in parts))
            except WillNotDivide:
                raise
            except ValueError:
                continue
        if found:
            break

    if not found:
        found = [((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0))]

    kept = []
    for one in found:
        if one not in kept:
            kept.append(one)
    return kept


def at_symmetry_scale(value):
    """A coordinate that is an exact integer at exact.SCALE_DIGITS, in this module's units."""
    return value * UNITS


def expand(points, ops):
    """Every point carried through every operation, reduced into one cell.

    `points` is an iterable of ((a, b, c), value) with the coordinates exact integers at
    representation.exact.SCALE_DIGITS, which is what crystal.site_table plus exact.scaled produces.
    Returns the same shape with coordinates in this module's units, reduced modulo SYM_SCALE.

    A point on a special position maps to itself under some operations and the repeats are dropped,
    so the result holds each distinct (place, value) once. That matters for a doping reading: a
    position holding one element that simply appears four times is not contested, and a position
    holding two elements is, however many operations put them there.
    """
    made = set()
    for position, value in points:
        along = [at_symmetry_scale(one) for one in position]
        for op in ops:
            moved = []
            for cx, cy, cz, translation in op:
                # Integer arithmetic throughout. The coefficients are whole, the coordinates are
                # integers in this scale, and the translation is already in these units multiplied
                # up by the decimal scale.
                total = (cx * along[0]) + (cy * along[1]) + (cz * along[2])
                total += translation * (10 ** exact.SCALE_DIGITS)
                moved.append(total % SYM_SCALE)
            made.add(((moved[0], moved[1], moved[2]), value))
    return [(place, value) for place, value in made]
