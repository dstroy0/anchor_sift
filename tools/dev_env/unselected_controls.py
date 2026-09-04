#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Generate structured domains that no process selected, as controls for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/unselected_controls.py
#
# Every corpus in this work that departs from a permutation null was made by a person, so the measure
# detecting human production and the measure detecting arrangement are not separated by anything
# measured. The control has to be a domain with structure and no author.
#
# A genome will not serve. The selective pressure that shaped language shaped the organism reading it, so
# a biological sequence is not independent of the hypothesis, and all biology shares one machinery in any
# case. What is needed is a domain under no selection at all.
#
# Mathematics supplies two. The digits of an irrational are fully determined and conjectured to be normal,
# so they should carry no arrangement to find. The gaps between primes are equally determined and are not
# structureless: they carry real arithmetic regularity, and nothing chose them.

import math
import os
import sys

# Converting a 600000 digit integer to text trips an interpreter guard meant for accidental conversions
sys.set_int_max_str_digits(2 * 600000)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "corpora")

DIGITS = 600000
SIEVE = 12000000


def sqrt_two_digits(count):
    """Digits of the square root of two, from one integer square root."""
    root = math.isqrt(2 * 10 ** (2 * count))
    return str(root)[:count]


def prime_gaps(limit):
    """Gaps between successive primes below limit, as one byte each."""
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
            gap = value - previous
            # Gaps are even above 2 and grow slowly, so half the gap fits a byte for this range
            out.append(min(255, gap // 2))
        previous = value
    return out


def main():
    os.makedirs(OUT, exist_ok=True)

    digits = sqrt_two_digits(DIGITS)
    # Seated at 1 to 10 so no symbol lands on zero, matching the other corpora
    body = bytearray(ord(character) - ord("0") + 1 for character in digits)
    with open(os.path.join(OUT, "math_sqrt2_digits.sym"), "wb") as handle:
        handle.write(body)
    print("  math_sqrt2_digits    %d symbols over %d distinct" % (len(body), len(set(body))))

    gaps = prime_gaps(SIEVE)
    seated = bytearray(value + 1 for value in gaps)
    with open(os.path.join(OUT, "math_prime_gaps.sym"), "wb") as handle:
        handle.write(seated)
    print("  math_prime_gaps      %d symbols over %d distinct" % (len(seated), len(set(seated))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
