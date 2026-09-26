#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How regularly a symbol recurs, scored against the same corpus with its positions destroyed.
#
#   Usage:  from measure.dispersion import dispersion_by_symbol, halves, rare_half
#
# This is the measure most of this work's findings rest on, and five separate scripts carried their
# own copy of the first function below.
#
# Every quantity here is a departure and none is a value. A dispersion of 0.28 says nothing; the
# same dispersion against a shuffle of the same bytes says the positions carry something. The
# shuffle preserves how often each symbol occurs and destroys where. A ratio away from one is
# therefore structure in the positions, and it cannot be in the counts.
#
# The split into halves is not cosmetic. Under a Zipf distribution the head carries the token count
# and the tail carries the information, since the surprisal of a symbol is -log p and the many rare
# symbols each contribute more of it. Measured, the rare half departs from the null in every kind of
# writing and the frequent half does not, and the frequent half's apparent signal tracked corpus
# size almost monotonically until every corpus was cut to one length.
#
# What this cannot do is establish that a corpus was made by a person. The gaps between primes
# return 0.93, outside the band every memoryless arm occupies, and nothing authored the primes.

import random
import statistics

# Occurrences a symbol needs before its gaps carry a statistic. Below this the coefficient of
# variation is a reading of how few times the symbol turned up.
MIN_OCCURRENCES = 32

# The seed the recorded figures were taken at. Reseeding moves the measure by about one percent of
# its value. That one percent is the floor every separation in this work is quoted against.
SEED = 0x51F7


def dispersion_by_symbol(seats, least=MIN_OCCURRENCES):
    """Coefficient of variation of the gaps between one symbol's occurrences, per symbol.

    A symbol recurring at even spacing gives a low value and one arriving in bursts gives a high
    one. Symbols occurring fewer than `least` times are left out entirely instead of being reported
    with a wide error, since a thin estimate here has been read as a finding before.
    """
    seen = {}
    for index, value in enumerate(seats):
        seen.setdefault(value, []).append(index)

    out = {}
    for value, positions in seen.items():
        if len(positions) < least:
            continue
        gaps = [positions[step] - positions[step - 1] for step in range(1, len(positions))]
        mean = statistics.fmean(gaps)
        if mean > 0.0:
            out[value] = statistics.pstdev(gaps) / mean
    return out


def halves(seats, null=None, seed=SEED, least=MIN_OCCURRENCES):
    """Mean null-to-live dispersion ratio over the frequent half and the rare half of the symbols.

    Pass `null` to score against a background built elsewhere, such as a block shuffle that keeps
    structure up to a stated span. Left as None it builds the plain null permutation, which destroys
    every arrangement at once and therefore cannot say which span the structure lives at.

    Returns (frequent, rare), or (None, None) where too few symbols cleared the occurrence floor.
    """
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1

    live = dispersion_by_symbol(seats, least)
    if null is None:
        shuffled = bytearray(seats)
        random.Random(seed).shuffle(shuffled)
        null = dispersion_by_symbol(shuffled, least)

    rows = []
    for value, spread in live.items():
        if (value in null) and (spread > 0.0):
            rows.append((counts[value], null[value] / spread))
    if len(rows) < 4:
        return None, None

    rows.sort(reverse=True)
    cut = len(rows) // 2
    return (statistics.fmean(row[1] for row in rows[:cut]),
            statistics.fmean(row[1] for row in rows[cut:]))


def rare_half(seats, null=None, seed=SEED, least=MIN_OCCURRENCES):
    """The rare half alone. This is the figure this work quotes.

    A memoryless corpus returns 1.00 because its distance from the reference is zero by
    construction, and every one of ten parameter arms sits between 0.99 and 1.01. Natural text runs
    0.48 to 0.76. Returns None where too few symbols cleared the floor.
    """
    return halves(seats, null, seed, least)[1]
