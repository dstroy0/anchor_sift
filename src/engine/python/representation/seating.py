#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Numbering a corpus to keep a reading of it belonging to the corpus instead of to the numbering.
#
#   Usage:  from representation.seating import tightest, spread_of
#
# A quantity that moves when the alphabet is renumbered is not a coefficient of the corpus. That is
# not a worry, it is a measurement: the share of symbols a reconstruction returns exactly is ordered
# by how far the values spread at rho -1.000 over fifteen corpora, which makes the spread the
# coefficient and makes it useless as one, because the spread belongs to the numbering. The Iliad
# returned the least of anything measured at 0.056, and the reason is that polytonic Greek needs 141
# code points laid across a wide range. The same poem under a tighter numbering returns four times
# as much without a word of it changing.
#
# The repair is to stop reading at whatever numbering a file arrived in and take the value it
# converges to. That is reached and not approached: minimizing a weighted spread over whole
# positions has a known answer, since the spread weights each position by how often it is used, so
# the commonest symbol belongs at the middle and the rest go outward in order of frequency.
#
# Under it, Greek moves from a spread of 31.44 to 7.83 and from 0.056 returned to 0.222, Finnish
# gains the most at 0.250, and English gains 0.194. That the numbering was being read is itself
# measurable: the ordering as given and the ordering at the tightest numbering agree only at rho
# 0.825.
#
# Which channel does the work is separable. The mechanism survives the change at rho -0.996 between
# the tightest spread and what it returns, while the count of symbols falls to -0.664, so what packs
# the mass is the frequency distribution and not the size of the alphabet.

import numpy


def spread_of(series):
    """Standard deviation of the values as numbered. A reconstruction error scales with this."""
    return float(numpy.asarray(series, dtype=numpy.float64).std())


def tightest(series, width=256):
    """The corpus renumbered so its values spread as little as any numbering allows.

    Nothing about the sequence changes, only which number each symbol carries. Positions are taken
    from the middle outward, which is where the weight wants them.

    Nothing is estimated here. The rule fixes a frame and adds no information. Choosing a seating to
    suit a measurement is an error this work has made in three other places, and the defense here is
    that the rule is stated in advance and has one answer.
    """
    values = numpy.asarray(series, dtype=numpy.int64)
    counts = numpy.bincount(values, minlength=width)
    present = numpy.flatnonzero(counts)
    ordered = present[numpy.argsort(-counts[present])]

    middle = len(ordered) // 2
    places = [middle]
    for step in range(1, len(ordered)):
        if (middle + step) < len(ordered):
            places.append(middle + step)
        if (middle - step) >= 0:
            places.append(middle - step)
    places = places[:len(ordered)]

    seating = numpy.zeros(width, dtype=numpy.uint8)
    for symbol, place in zip(ordered, places):
        seating[symbol] = place
    return seating[values]
