#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Score every coset of a corpus at a stated stride and average them, for Section 7.4 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/supersample_cosets.py stride corpus.sym [more.sym ...]
#
# A repeating key of length k sends one plaintext symbol to k ciphertext symbols by position, so a
# measurement over the whole ciphertext sees the structure divided k ways and reports almost nothing.
# The positions sharing a key offset were enciphered by one substitution, so each of the k cosets
# carries the structure undivided, at one kth of the length.
#
# Taking one coset therefore trades the division for a shorter sample and recovers part of the signal.
# Taking all k of them and averaging spends no length at all: every symbol of the corpus lands in
# exactly one coset, so the k scores together read the whole text. This is why a repeating key leaks
# whatever its length, and the control is the same procedure applied to a key as long as the message,
# where there are no cosets to find and the average has to stay flat.

import os
import statistics
import sys
import random

MIN_OCCURRENCES = 32

# Symbols per coset to score, or 0 to use whatever the stride leaves. Set from the command line as
# cap=N, and needed whenever scans at different strides are compared to each other.
CAP = 0


def dispersion_by_symbol(seats):
    """Coefficient of variation of the gaps between occurrences, per symbol."""
    seen = {}
    for index, value in enumerate(seats):
        seen.setdefault(value, []).append(index)

    out = {}
    for value, positions in seen.items():
        if len(positions) < MIN_OCCURRENCES:
            continue
        gaps = [positions[step] - positions[step - 1] for step in range(1, len(positions))]
        mean = statistics.fmean(gaps)
        if mean <= 0.0:
            continue
        out[value] = statistics.pstdev(gaps) / mean
    return out


def halves(seats, seed):
    """Mean permutation null ratio over the frequent half and the rare half of the symbols."""
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1

    live = dispersion_by_symbol(seats)
    shuffled = bytearray(seats)
    random.Random(seed).shuffle(shuffled)
    dead = dispersion_by_symbol(shuffled)

    rows = []
    for value, spread in live.items():
        if (value not in dead) or (spread <= 0.0):
            continue
        rows.append((counts[value], dead[value] / spread))
    if len(rows) < 4:
        return None, None

    rows.sort(reverse=True)
    cut = len(rows) // 2
    return (statistics.fmean(row[1] for row in rows[:cut]),
            statistics.fmean(row[1] for row in rows[cut:]))


def main():
    if len(sys.argv) < 3:
        print("usage: supersample_cosets.py stride corpus.sym [more.sym ...]")
        return 1

    global CAP
    stride = int(sys.argv[1])
    paths = []
    for argument in sys.argv[2:]:
        if argument.startswith("cap="):
            CAP = int(argument[4:])
            continue
        paths.append(argument)

    print("  %-46s %-8s %-8s %s" % ("corpus", "head", "tail", "cosets"))

    for path in paths:
        if not os.path.isfile(path):
            print("  no corpus at %s" % path)
            continue
        with open(path, "rb") as handle:
            seats = bytearray(handle.read())

        heads = []
        tails = []
        for offset in range(stride):
            coset = seats[offset::stride]
            # Each coset holds one stride'th of the corpus, so a scan over strides compares estimates
            # taken from different amounts of data and from whatever symbols cleared the occurrence
            # floor at that length. Truncating every coset to one length removes both
            if CAP > 0:
                if len(coset) < CAP:
                    continue
                coset = coset[:CAP]
            head, tail = halves(coset, 0x51F7 + offset)
            if head is None:
                continue
            heads.append(head)
            tails.append(tail)

        if not heads:
            print("  %-46s too few symbols scored" % os.path.basename(path))
            continue

        print("  %-46s %-8.3f %-8.3f %d"
              % (os.path.basename(path), statistics.fmean(heads), statistics.fmean(tails),
                 len(heads)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
