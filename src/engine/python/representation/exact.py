#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Ingestion that keeps every digit the source wrote, for any domain.
#
#   Usage:  from representation.exact import units, scaled, product, placed, along
#
# Every reader in this part turns a file into points carrying values, and until now each one bounded
# the values on the way in. levels.py holds a protein's angstroms and a shaped field's floating point
# to the 256 levels a byte carries. crystal.py rounded a published cell edge onto a grid of 0.25
# angstroms. Both bounds were chosen here and neither came from the source, and the crystal one is
# measurable: it answers a published edge to 0.0124 angstroms on average where the same points read
# exactly answer it with an error of zero.
#
# A source writes decimal text. 4.76050, 0.35216, 12.4. That text is a numerator and a count of
# decimal places, and both are integers, so the number arrives here with nothing lost and no float
# or Decimal in the path. Python integers are arbitrary precision, so they stay that way through
# addition and multiplication however large the scale gets.
#
# NO QUANTUM IS IMPOSED FROM THIS END
#
# A quantum is a human decision about the smallest difference worth telling apart. The voxel was
# one and the byte in levels.py is another. Nothing measured set either of them. They were set here.
# Whatever is being read goes on varying below them and the choice decides in advance that the
# variation does not exist.
#
# The scale below is set so that this part never makes that decision. It does not claim a source
# carries a thousand digits and it does not make a deposited number truer. An uncertainty like the 5
# in 4.76050(5) is a quantum already fixed upstream by the people who measured it, and dropping it is
# all that can be done with it here. The scale buys one thing: no second quantum underneath.
#
# This part is also not allowed to choose a scale in the sense partition means, and this is not that
# kind of choice. A partition decides what can be read and a reading is undetermined until it is
# fixed. SCALE_DIGITS only says where the decimal point sits in an integer, and scaled() raises
# instead of rounding where a value would not survive it. A scale set too small is then an error and
# never a quiet loss.
#
# How many digits a reading needs is a property of the operations between the source and the answer,
# not of the source. Measured on the crystal corpus, every scale from 8 digits to 16384 returns the
# same 180 of 180 axes. That is a fact about that path and not about the scale: it multiplies each
# coordinate by an edge once, so the decimal places of the two operands add and eleven of them is
# the whole requirement.
#
# Places grow with every operation, and a path with division, accumulation, or composed transforms
# grows them faster than one multiplication does. A cell that is not right angled needs cosines
# through a metric tensor, and a cosine has no exact decimal at any scale. The headroom keeps those
# paths reachable. The crystal measurement is the cheapest possible case and not the case the scale
# was set for.
#
# WHY THE SCALE IS SET SO HIGH
#
# The usual reason to bound a value on the way in is memory, and on a sparse point set it does not
# apply. The scale is set far past any conceivable source so that sensitivity is never the limit and
# truncation is never possible, and the cost of that is measurable and small.
#
# A python integer of 1024 decimal digits occupies 480 bytes. A crystal cell tiled four times an
# axis is about 1280 points, so all three coordinates of the whole arrangement come to 1.76 MB. The
# dense grid that crystal.py used to build for the same cell is 320 cubed at a byte a voxel, which
# is 31.25 MB, and 0.0039 percent of it is occupied. The exact reading is eighteen times smaller
# than the grid it replaces and it rounds nothing, while the grid spent that memory holding empty
# space and rounded anyway.
#
# Time behaves the same way over the range that matters and stops behaving that way past it. On 180
# crystal axes, 8 digits takes 0.13 seconds and 1024 takes 0.37, which is 128 times the digits for
# 2.8 times the time. Past there it turns: 4096 takes 1.96 seconds and 16384 takes 13.70, because
# big integer multiplication and hashing both grow with the digit count, and past some width that
# growth dominates the run. The scale is cheap and not free. 1024 sits inside the cheap part and
# buys more headroom than any source is going to need.

# Decimal places an ingested value is carried at. 1e-1024 of whatever unit the source wrote in, and
# no source in this work or outside it writes past a few tens of places. Raising it further costs
# bytes per point and changes no result; lowering it is the only direction that can lose anything.
SCALE_DIGITS = 1024
SCALE = 10 ** SCALE_DIGITS


class WillNotFit(ValueError):
    """A value carries more decimal places than the scale holds.

    Its own class because a reader has to tell it apart from text it could not parse. Both are
    ValueError and the two mean opposite things: unparsable text is a source this does not
    understand, and this is a source it understands and a scale set too small to hold. Catching them
    together is how a scale that was silently dropping digits looked like a corpus of unreadable
    entries.
    """


def units(text):
    """Decimal text as (numerator, decimal places). The pair holds the number with nothing lost.

    A bracketed uncertainty is not part of the number and is dropped. Raises ValueError on anything
    that is not plain decimal text, exponent notation included, since silently accepting one would
    put a rounding back in the path this exists to keep clear.
    """
    body = str(text).strip()
    opened = body.find("(")
    if opened >= 0:
        body = body[:opened] + body[body.find(")") + 1:] if ")" in body else body[:opened]
    body = body.strip()

    sign = 1
    if body[:1] in ("+", "-"):
        sign = -1 if body[0] == "-" else 1
        body = body[1:]

    whole, point, part = body.partition(".")
    if point and not part:
        part = ""
    digits = whole + part
    if (not digits) or (not digits.isdigit()):
        raise ValueError("%r is not plain decimal text" % text)
    return sign * int(digits), len(part)


def at_scale(numerator, places, digits=SCALE_DIGITS):
    """A (numerator, places) pair as an exact integer at `digits` decimal places.

    Raises WillNotFit where the value carries more places than the scale holds. Rounding is what a
    smaller scale would have to do there, and nothing here rounds.
    """
    if places > digits:
        raise WillNotFit("%d decimal places will not fit a scale of %d" % (places, digits))
    return numerator * (10 ** (digits - places))


def scaled(text, digits=SCALE_DIGITS):
    """Decimal text straight to an exact integer at `digits` decimal places."""
    numerator, places = units(text)
    return at_scale(numerator, places, digits)


def product(left, right):
    """Two (numerator, places) pairs multiplied, exactly.

    The places add. Two numbers of five and six places make one of eleven, and no digit of either is
    dropped to make room. The product stays exact for that reason and no other.
    """
    return left[0] * right[0], left[1] + right[1]


def shifted(value, whole):
    """A (numerator, places) pair with a whole number added to it, exactly.

    The whole number is raised to the pair's own place count first, so the sum stays one decimal
    quantity. Used where a point is repeated at a step, as tiling a cell repeats a site.
    """
    numerator, places = value
    return numerator + (whole * (10 ** places)), places


def placed(points):
    """Points carrying values as a lookup from an exact position to the value at it.

    `points` is any iterable of (position, value), the position an integer or a tuple of integers at
    one scale. A position landing twice keeps the last value, matching a reader that overwrites.

    This is the form the exact measures read. It carries no dimension, no extent and no domain: a
    text is positions on a line, a picture positions on a plane, a structure positions in space, and
    every one of them arrives here as the same thing.
    """
    return {position: value for position, value in points}


def along(points, axis):
    """A multi-axis point set read along one axis, as a lookup from coordinate to arrangement.

    Every point sitting at one coordinate on `axis` is gathered, and what that coordinate carries is
    the arrangement of those points on the remaining axes together with their values, sorted so two
    coordinates holding the same arrangement compare equal.

    That comparison lets a shift measure read a structure without knowing it is one. A lattice
    repeats whole planes. A period along an axis is then a coordinate whose plane matches the plane
    one period away, and the values have to sit in the arrangement for it to count as a match. A
    rocksalt cell reads at half its published edge when they are left out, because its two
    sublattices interleave and the positions alone do repeat at a/2.

    Returns a dict, the same form `placed` returns and the exact measures take.
    """
    gathered = {}
    for position, value in points:
        rest = tuple(one for at, one in enumerate(position) if at != axis)
        gathered.setdefault(position[axis], []).append(rest + (value,))
    return {where: tuple(sorted(what)) for where, what in gathered.items()}
