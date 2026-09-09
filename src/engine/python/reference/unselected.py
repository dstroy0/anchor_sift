#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Structured domains that nobody produced. This work went longest without a control of this kind.
#
#   Usage:  from reference.unselected import sqrt_two_digits, prime_gaps
#
# Every corpus in this work that departs from a permutation null was made by a person, so the
# measure detecting arrangement and the measure detecting human production were never separated by
# anything measured. The control has to be a domain with structure and no author.
#
# A genome will not serve. The selection that shaped language shaped the organism, leaving a
# biological sequence dependent on the hypothesis, and all biology shares one machinery in any case.
# What is needed is a domain under no selection at all, and mathematics supplies two.
#
# What they settled, and it refuted the strong claim. The digits of the square root of two return
# 1.00, sitting at the null as a number conjectured normal should. The gaps between primes return
# 0.93, outside the 0.99 to 1.01 band every one of ten memoryless arms occupies. Nothing authored
# the primes and the measure sees them. So the measure reads arrangement, and human production was
# never intrinsic to it.
#
# The claim that holds is weaker and quantitative: the primes depart by 0.07 where human corpora depart
# by 0.22 to 0.68, three to ten times further, and the square root digits confirm that determinism
# alone is not what it responds to. Part of that 0.07 may be the encoding, since the gaps are stored
# as half the gap capped at one byte.

import math
import sys

# Digits taken of the irrational.
DIGITS = 600000

# Sieve limit for the prime gaps.
SIEVE = 12000000


def sqrt_two_digits(count=DIGITS):
    """Digits of the square root of two, from one integer square root.

    Fully determined and conjectured normal, so it should carry no arrangement to find. It returns
    1.00 and that is the reading working correctly on a domain that holds nothing.

    Writing the root out passes an interpreter guard that refuses to render an integer wider than
    4300 digits, which exists to catch an accidental conversion of a huge number. This one is not
    accidental. The limit is lifted for the call and restored after, leaving a caller's own setting.
    """
    root = math.isqrt(2 * 10 ** (2 * count))
    held = sys.get_int_max_str_digits()
    try:
        sys.set_int_max_str_digits(max(held, count + 64))
        return str(root)[:count]
    finally:
        sys.set_int_max_str_digits(held)


def prime_gaps(limit=SIEVE):
    """Gaps between successive primes below `limit`, as one byte each.

    Equally determined and not structureless: these carry real arithmetic regularity and nothing
    chose them. Gaps are even above 2 and grow slowly, so half the gap fits a byte for this range,
    and that encoding is stated because part of the departure may belong to it.
    """
    flags = bytearray([1]) * limit
    flags[0] = flags[1] = 0
    for value in range(2, math.isqrt(limit) + 1):
        if flags[value]:
            flags[value * value::value] = bytearray(len(flags[value * value::value]))

    out = bytearray()
    previous = None
    for value in range(2, limit):
        if not flags[value]:
            continue
        if previous is not None:
            out.append(min(255, (value - previous) // 2))
        previous = value
    return out


def seated(values, base=1):
    """The values moved off zero, matching how every other corpus here is seated."""
    return bytearray(value + base for value in values)
