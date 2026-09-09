#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Real numbers held to the eight bits every corpus in this work is read at.
#
#   Usage:  from representation.levels import to_levels
#
# A protein arrives as coordinates in angstroms and a shaped field arrives as floating point, while
# every text and every painting here arrives as bytes. Measuring one at full precision and the other
# at eight bits compares two different measurements, and the difference would sit in whichever
# result was more convenient.
#
# Five places carried this same arithmetic before it was one function. The corpus loader in this same
# part was written after one such copy went wrong: one of its four copies was missing an exclusion
# the other three had, and a Greek to English lexicon stood inside a reading of Greek because of it.
#
# Three standard deviations fills the byte range. At three the value lands on 2 or 254, so the levels
# use almost all of what a byte holds and clipping reaches only the tail beyond three. All five
# copies had already made that trade.

import numpy

# Levels per standard deviation. Three standard deviations then span 2 to 254.
PER_DEVIATION = 42.0

# The level a value at the mean lands on, halfway through what a byte holds.
MIDDLE = 128.0


def to_levels(series, per_deviation=PER_DEVIATION, middle=MIDDLE):
    """A run of real numbers as whole levels in a byte, centered on the mean.

    Returns None where the series does not vary, since there is no spread to scale by and every
    value would land on the same level.
    """
    floats = numpy.asarray(series, dtype=numpy.float64)
    spread = floats.std()
    if spread <= 0.0:
        return None
    scaled = (floats - floats.mean()) / spread
    return numpy.clip(numpy.rint((scaled * per_deviation) + middle), 0, 255).astype(numpy.uint8)
