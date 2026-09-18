#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The Bloom filter, which is this tree's own sift theorem standing in the field of databases.
#
#   Usage:  from sift.bloom import build, contains, false_positive_rate
#
# A Bloom filter answers whether an item is in a set using far less room than the set, by keeping only
# a bit array. Each item sets a few bits chosen by hashing it; a query reports the item present when all
# of its bits are set. A member sets its own bits on the way in. A member's bits are always set and
# the filter NEVER says a member is absent. A non-member can find every one of its bits set by
# accident. The filter sometimes says a non-member is present. The error is one-directional: false
# positives happen, false negatives cannot.
#
# That is the sift's theorem, in another field and with the same proof. anchors.py keeps a subset of a
# pattern's points as a necessary condition: a position genuinely holding the pattern satisfies every
# anchor. No arrangement of anchors can lose a true occurrence, and the only error is a false
# candidate that survives. A Bloom filter keeps a hash of an item as a necessary condition: a member
# sets every one of its bits. No choice of hashes can lose a member, and the only error is a
# non-member that survives. Both are sound necessary conditions with a one-directional error, and in
# both the SOUNDNESS does not depend on the rule while the COST does. Change the hashes, or change which
# anchors are chosen, and not one true item is lost; only the count of false survivors moves. The two
# are the same object, and nothing was ported between them because there was nothing to port.
#
# NOTHING IS BOUNDED HERE
#
# The size of the bit array and the number of hashes are declared inputs, reported with every reading,
# not tolerances chosen until the output looked right. The false-positive rate is not a threshold that
# is set; it is a consequence of those two inputs and the item count, and it is measured and reported
# beside its own arithmetic prediction. The hashing is exact integer arithmetic, an FNV-1a hash over
# the item's bytes with two seeds combined. The filter is deterministic and depends on no library.

FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK = (1 << 64) - 1


def _fnv1a(data, seed):
    """A 64-bit FNV-1a hash of `data`, a bytes-like, started from `seed`. Deterministic, no imports."""
    value = (FNV_OFFSET ^ seed) & MASK
    for byte in data:
        value = ((value ^ byte) * FNV_PRIME) & MASK
    return value


def _as_bytes(item):
    """An item as bytes. Any hashable of a known encoding can be stored. Strings go through UTF-8."""
    if isinstance(item, (bytes, bytearray)):
        return bytes(item)
    if isinstance(item, str):
        return item.encode("utf-8")
    return repr(item).encode("utf-8")


def positions(item, bits, hashes, seed=0):
    """The `hashes` bit positions an item occupies, by double hashing into a table of `bits` bits.

    Two independent FNV hashes are combined as one plus a step, which gives as many positions as wanted
    from two hashes. `seed` selects a whole independent family of hashes, the knob the demos
    turn to show soundness does not depend on it.
    """
    data = _as_bytes(item)
    first = _fnv1a(data, seed)
    second = _fnv1a(data, seed ^ 0x9E3779B97F4A7C15) or 1
    return [(first + step * second) % bits for step in range(hashes)]


def build(items, bits, hashes, seed=0):
    """A filter over `items`, as an integer used as a bit array of `bits` bits.

    A Python integer is the bit array: arbitrary precision. No length is fixed in advance and the
    whole structure is one exact number. Each item sets its positions, and a member's positions are set
    by construction, the whole guarantee.
    """
    table = 0
    for item in items:
        for place in positions(item, bits, hashes, seed):
            table |= 1 << place
    return table


def contains(table, item, bits, hashes, seed=0):
    """Whether every one of an item's positions is set: present, meaning member or false positive.

    True for every member without exception, because a member set these same bits when it was added.
    True for a non-member only when all of its bits were set by other items, the false
    positive. Never false for a member, the soundness.
    """
    return all((table >> place) & 1 for place in positions(item, bits, hashes, seed))


def false_positive_rate(table, absent, bits, hashes, seed=0):
    """The share of items known to be absent that the filter nonetheless reports present.

    The measured floor, drawn from items that were never added, not a rate assumed from the arithmetic.
    The caller prints it beside the predicted rate so the two can be compared.
    """
    absent = list(absent)
    if not absent:
        return 0.0
    passed = sum(1 for item in absent if contains(table, item, bits, hashes, seed))
    return passed / float(len(absent))
