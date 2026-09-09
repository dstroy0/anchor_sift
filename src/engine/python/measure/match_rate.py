#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Entropy per symbol read by matching, which has no wall where counting has one.
#
#   Usage:  from measure.match_rate import match_rate
#
# Counting blocks cannot see past order four. The possible blocks grow as the alphabet raised to the
# order while a text grows in a line, so from order five most blocks have been seen once or never
# and the reading is measuring its own sample size. That is not an opinion: a shuffled text's block
# entropy is known by arithmetic, being exactly n times the entropy of one symbol, and the gap
# between that and what the estimator returns is the error itself. Eight texts follow the
# undersampling curve to within a few percent through order four and leave it together at order
# five, and Thai leaves earliest because Thai has the least text.
#
# Matching has no such wall. At each position the shortest string that the window behind it has not
# already seen is found. A dependency of any length therefore shows as a long match, and nothing
# needs to be seen many times. Where counting could see four symbols, this sees a quarter of a
# million and is still finding something.
#
# The window is swept and not chosen, which turns the choice from an assumption into the result. A
# rate still falling at the widest window means the text holds something at that distance.
#
# The shuffle is carried as the floor and it is not optional. Both arms rise with the window, from
# 3.71 to 4.19 bits on the shuffled rows, and a shuffle holds nothing beyond one symbol, so that
# rise is the estimator and not the text. It spoils the absolute rates and leaves the widening
# distance between the two arms standing.
#
# None of this is a separate technique from compression. The entropy rate of a source is the rate an
# ideal compressor reaches on it. An instrument that compresses therefore sees dependencies that an
# instrument that counts cannot reach.

import math

import numpy

# Positions sampled per window.
SAMPLES = 4000

# The longest match the search will bracket. A text's matches are short, so the search doubles to
# bracket and then bisects, instead of scanning up from one.
LONGEST = 400


def match_rate(text, window, rng, samples=SAMPLES, longest=LONGEST):
    """Bits per symbol, from how long a string must be before the window behind it has not seen it.

    Returns None where the text is too short to hold two windows. `text` is a string or any sequence
    supporting the `in` test on slices.
    """
    if len(text) < (window * 2):
        return None

    starts = rng.integers(window, len(text) - longest, size=samples)
    lengths = []
    for start in starts:
        start = int(start)
        behind = text[start - window:start]

        low = 0
        high = 1
        while (high < longest) and (text[start:start + high] in behind):
            low = high
            high *= 2
        high = min(high, longest)
        while low + 1 < high:
            middle = (low + high) // 2
            if text[start:start + middle] in behind:
                low = middle
            else:
                high = middle
        lengths.append(low + 1)

    average = float(numpy.mean(lengths))
    return (math.log2(window) / average) if average > 0 else None
