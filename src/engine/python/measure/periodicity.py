#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The lag a sequence agrees with itself at, read at every lag.
#
#   Usage:  from measure.periodicity import sequence_period
#
# The dimension count reads roughness at 1, 2, 4, 8 and 16, because it was built for an interleaved
# index whose repeat counts bit positions. A period of three sits at lags 3, 6 and 9, and no power of
# two is a multiple of three, so that reader cannot see a period of three whatever the data does.
# Both quantities were being called a period of n, and one of them was measured with an instrument
# blind to it.
#
# The failure was caught on protein backbones, where chemistry fixes the answer at three before any
# measurement: nitrogen to alpha carbon, alpha carbon to carbon, carbon to the next nitrogen, at
# 1.46, 1.52 and 1.33 angstroms. A reader that returns something other than three there is wrong, and
# there is no argument available afterward about what the sequence really does.
#
# Scoring a period against all of its multiples is what the first version lacked. A sequence
# repeating every three agrees with itself at three, six, nine and twelve alike, so which of those
# stands tallest is settled by noise, and taking the tallest lag reports a harmonic as the period
# about as often as it reports the period.

import numpy

# Lags read. A period beyond half of this cannot be scored, since it has one multiple inside the
# range and a family of one is the single tallest lag again.
LONGEST = 16


def sequence_period(series, longest=LONGEST):
    """The period whose own multiples agree most, and how far it beat the lags outside the family.

    Returns (None, None) where the series does not vary or is too short to read at `longest`, which
    takes four full periods so that the longest candidate still has something to average.
    """
    floats = numpy.asarray(series, dtype=numpy.float64)
    floats = floats - floats.mean()
    if (floats.std() <= 0.0) or (len(floats) < (4 * longest)):
        return None, None

    marks = {}
    for lag in range(1, longest + 1):
        left = floats[:-lag]
        right = floats[lag:]
        spread = float(left.std() * right.std())
        marks[lag] = float((left * right).mean() / spread) if spread > 0.0 else 0.0

    scored = []
    for period in range(2, (longest // 2) + 1):
        family = [marks[lag] for lag in range(period, longest + 1, period)]
        outside = [value for lag, value in marks.items() if (lag % period) != 0]
        if (len(family) < 2) or (not outside):
            continue
        scored.append((float(numpy.mean(family)) - float(numpy.mean(outside)), period))

    if not scored:
        return None, None
    scored.sort(reverse=True)
    return scored[0][1], scored[0][0]
