#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How often a sequence carries the same symbol a fixed distance apart, read at every distance.
#
#   Usage:  from measure.sequence_match import match_rate_at_lag, coincidence_floor
#
# The one operation is equality. Two positions either carry the same symbol or they do not, and the
# match rate at a lag is the fraction of positions whose symbol equals the one that many places ahead.
# No order on the symbols, no distance between them, no alphabet: the same contract the sift kernel
# reads a field through, and a symbol here can be an element, a letter or a chess move without the
# measure knowing which.
#
# periodicity.py scores a single period out of a numeric series by autocorrelation, and it is the
# right tool where one period exists and the symbols are magnitudes. This is for the other case: a
# categorical sequence, and a recurrence that need not sit at one lag. A profile of the match rate
# over the lags shows every distance the sequence repeats at, and where several stand up the sequence
# has several periods, not one.
#
# The floor is what a shuffle of the same symbols reaches at any lag, and it is not optional. A rate
# is only structure to the extent it stands above the rate the counts alone force. coincidence_floor
# is that rate exactly, computed from the census, and a peak is read against it and never on its own.

def match_rate_at_lag(sequence, longest=None):
    """The fraction of positions carrying the same symbol `lag` places ahead, for each lag.

    Returns a dict from lag to fraction, over lags 1 through `longest`, defaulting to half the length
    so the widest lag still has half the sequence behind it. Returns an empty dict where the sequence
    is too short to read one lag. `sequence` is any indexable of symbols compared by equality.
    """
    length = len(sequence)
    if longest is None:
        longest = length // 2
    longest = min(longest, length - 1)
    rates = {}
    for lag in range(1, longest + 1):
        agree = sum(1 for at in range(length - lag) if sequence[at] == sequence[at + lag])
        rates[lag] = agree / (length - lag)
    return rates


def coincidence_floor(sequence):
    """The match rate a uniform shuffle of these symbols reaches at any lag, from the census alone.

    Two distinct positions of a random permutation carry the same symbol with probability
    sum(count * (count - 1)) / (length * (length - 1)), summed over the symbols. That is the rate a
    peak in `match_rate_at_lag` has to clear before it is structure and not the counts repeating
    themselves. Returns 0.0 for a sequence shorter than two symbols.
    """
    length = len(sequence)
    if length < 2:
        return 0.0
    counts = {}
    for symbol in sequence:
        counts[symbol] = counts.get(symbol, 0) + 1
    same = sum(count * (count - 1) for count in counts.values())
    return same / (length * (length - 1))
