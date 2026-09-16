#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The lag a sequence agrees with itself at, read at every lag.
#
#   Usage:  from measure.periodicity import sequence_period, stable_period
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
# A second failure was caught later and on a different kind of object, and stable_period at the
# bottom of this file is what came out of it. Handed a sequence with no period at all, this function
# returns a number, and that number is not weak: on nine aperiodic words it cleared a shuffle floor
# by three to twenty nine times, so no margin test refuses it. It is the denominator of a continued
# fraction convergent of the word's slope, because a rotation by an irrational really does agree with
# itself at the denominator of a good rational approximation to that irrational. The agreement is
# real, the lag is real, and only the word "period" on the output is false.
#
# What separates the two is that a period is a property of a sequence and an approximation is a
# property of a sequence and a window together. Widening the window moves the second and not the
# first: 115 of 115 subtraction games with a proved period gave one answer across five windows, and
# 0 of 9 aperiodic words gave one across seven. theory/game_theory carries the table.
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


# Windows `stable_period` reads at. Four of them, roughly doubling, so a sequence agreeing with
# itself at a growing lag has room to move and a real period has no reason to.
WINDOWS = (16, 32, 64, 128)


def stable_period(series, windows=WINDOWS):
    """The period only where widening the window does not change the answer.

    `sequence_period` returns a number on a sequence that has no period, the number clears a shuffle
    floor by three to twenty nine times, and it is still not a period. A word built from a rotation
    by an irrational agrees with itself at the denominator of any good rational approximation to that
    irrational, so the detector finds a real agreement at a real lag and only the name on the output
    is wrong. No margin test refuses those readings, because nothing is weak about them.

    A period is a property of a sequence. An approximation is a property of a sequence and a window
    together. So widen the window: 115 of 115 subtraction games with a true period give one answer
    across five windows, and 0 of 9 aperiodic words give one across seven.

    Returns (period, margin at the widest window that read it) where every window agreed, and
    (None, None) where they did not. A caller wanting the older behavior calls sequence_period, which
    is unchanged; this is a second question and not a correction to that one.

    Windows shorter than the series can support are skipped rather than counted as disagreement,
    since sequence_period needs four full periods and returns None below that. Where fewer than two
    windows could read at all the answer is None, because one window agreeing with itself is not the
    test.
    """
    answers = []
    for longest in windows:
        period, margin = sequence_period(series, longest=longest)
        if period is not None:
            answers.append((period, margin))

    if len(answers) < 2:
        return None, None
    if len({period for period, _ in answers}) != 1:
        return None, None
    return answers[-1]
