#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Score a corpus against nulls that preserve structure up to a stated span, for Section 7.4 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/block_shuffle_null.py corpus.sym [more.sym ...]
#
# The null used everywhere else shuffles single symbols, which preserves how often each symbol occurs
# and destroys every arrangement of them at once. That cannot say which span the structure lives at.
#
# Cutting the corpus into blocks of B symbols and shuffling the blocks keeps every arrangement shorter
# than B and destroys every arrangement longer than it. Sweeping B says where a measure's signal sits.
# The word boundary recurs every few symbols, so it should return at a small B. A rare symbol clusters
# because a passage is about the thing it names, which is an arrangement spanning a passage, so it
# should need a much larger B.

import os
import random
import statistics
import sys

MIN_OCCURRENCES = 32
BLOCKS = (1, 8, 32, 128, 512, 2048, 8192)


def dispersion_by_symbol(seats):
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


def block_shuffled(seats, span, seed):
    """The corpus with its blocks of `span` symbols reordered, keeping each block's own order."""
    blocks = [seats[start:start + span] for start in range(0, len(seats), span)]
    random.Random(seed).shuffle(blocks)
    out = bytearray()
    for block in blocks:
        out.extend(block)
    return out


def halves(seats, reference):
    """Mean ratio of the reference dispersion to the live one, over each half of the symbols."""
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1

    live = dispersion_by_symbol(seats)
    rows = []
    for value, spread in live.items():
        if (value not in reference) or (spread <= 0.0):
            continue
        rows.append((counts[value], reference[value] / spread))
    if len(rows) < 4:
        return None, None

    rows.sort(reverse=True)
    cut = len(rows) // 2
    return (statistics.fmean(row[1] for row in rows[:cut]),
            statistics.fmean(row[1] for row in rows[cut:]))


def report(path):
    with open(path, "rb") as handle:
        seats = bytearray(handle.read())

    live = dispersion_by_symbol(seats)
    print("%s" % os.path.basename(path))
    print("  %-8s %-8s %-8s" % ("block", "head", "tail"))

    for span in BLOCKS:
        null = dispersion_by_symbol(block_shuffled(seats, span, 0x51F7))
        head, tail = halves(seats, null)
        if head is None:
            continue
        print("  %-8d %-8.3f %-8.3f" % (span, head, tail))
    return 0


def main():
    if len(sys.argv) < 2:
        print("usage: block_shuffle_null.py corpus.sym [more.sym ...]")
        return 1
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            print("no corpus at %s" % path)
            continue
        report(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
