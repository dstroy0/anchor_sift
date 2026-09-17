#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# A structure as packed bits in one arbitrary-precision integer, read by presence, never as a scale.
#
#   Usage:  from reference.bitfield import pack, whole_range, present, count, only_in, shared, same
#
# The engine has no scale, dimension, unit or form. A reading is which quanta are present, not how much
# of a continuum they cover. A structure is a set of positions, packed one bit per position into a
# Python int, which is an arbitrary-precision bignum with native AND, OR, XOR, NOT and bit_count. Two
# structures compare by set operations: what the object holds that its shuffle does not is
# only_in(object, shuffle), and its size is a popcount, a cardinality of quanta. Nothing here divides,
# rounds, holds a ratio, or compares a magnitude.
#
# A continuum, a mean or a proportion, is never a value here. Where a reference needs a mean to decide a
# bit-exact match, the mean is computed from the integer parts at that point and discarded; the value
# that survives is the bit. A continuum can be a constituent of a larger reading. It cannot be a
# constituent of the quanta themselves.


def pack(positions):
    """Set one bit per position index. The structure is the set of positions, as a bignum."""
    field = 0
    for index in positions:
        field |= 1 << index
    return field


def whole_range(length):
    """The full field of `length` positions, every bit set: the structure nothing is missing from."""
    return (1 << length) - 1


def present(field):
    """Truthy when any quantum is present."""
    return field != 0


def count(field):
    """How many quanta are present. A cardinality, not a magnitude."""
    return field.bit_count()


def only_in(field, other):
    """The quanta the field holds that other does not: field AND NOT other."""
    return field & ~other


def shared(field, other):
    """The quanta present in both: field AND other."""
    return field & other


def same(field, other):
    """Bit-exact equality of two structures. The exactness reading, a boolean, never a distance."""
    return field == other
