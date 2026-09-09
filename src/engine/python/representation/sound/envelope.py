#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# A waveform re-sliced to the scale its units actually occupy.
#
#   Usage:  from representation.envelope import envelope
#
# The vocalizations were first measured at 8 kHz with one byte a sample. That slice is wrong by four
# orders of magnitude. A whale song unit runs one to three seconds and its phrases run longer,
# and a wolf howl is seconds. A statistic over the gaps between rare amplitudes at 8 kHz reads inside
# a single call and never sees how calls are arranged.
#
# Correcting it changed the answer. At sample scale the animals and the people interleaved: whale
# 0.25, dawn chorus 0.30, human speech 0.42 and 0.43, wolf 0.46, with two of three animals departing
# further from the null than a person reading aloud. At one symbol every 10 ms the same recordings
# give whale 0.44, dawn chorus 0.45 and wolf 0.49 against 0.56 and 0.72 for two human recordings,
# which separates without overlap.
#
# True unit scale is still not reachable with those recordings. At one symbol every 50 ms a one
# minute clip gives 1053 symbols for the whale, 566 for the wolf and 281 for one bird, and measuring
# the arrangement of units needs tens of minutes.
#
# The envelope is spread over the range each recording actually uses. Without that, a quiet
# recording would be compressed into a few levels and compared against a loud one that was not.

import math

# Samples per envelope symbol. At 8 kHz this is one symbol every 10 ms, which is about one phoneme
# for speech and a small fraction of a call for an animal.
BLOCK = 80

# Where silence sits in an unsigned byte sample.
MIDPOINT = 128


def envelope(seats, block=BLOCK, midpoint=MIDPOINT):
    """Root mean square deviation from the midpoint per block, spread back over a byte.

    Returns an empty result where the input is shorter than one block. The spreading is what allows
    two recordings to be compared, and it also leaves an envelope of a silent passage meaningless:
    with no range to spread over, the function returns the raw levels instead of inventing one.
    """
    out = bytearray()
    for start in range(0, len(seats) - block + 1, block):
        total = 0
        for index in range(start, start + block):
            offset = seats[index] - midpoint
            total += offset * offset
        out.append(int(math.sqrt(total / float(block))))

    if not out:
        return out

    low = min(out)
    high = max(out)
    if high <= low:
        return out
    return bytearray(1 + int(254 * (value - low) / float(high - low)) for value in out)


def symbols_per_second(sample_rate, block=BLOCK):
    """How many envelope symbols one second of real time becomes.

    Worth computing instead of assuming. Several of the archival recordings are time compressed by
    a factor written into the file name, and a measurement of arrangement belongs against real time
    instead of a playback convenience.
    """
    return sample_rate / float(block)
