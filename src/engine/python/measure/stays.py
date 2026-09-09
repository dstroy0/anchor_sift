#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How long a corpus holds near a value, and how sharply it leaves.
#
#   Usage:  from measure.stays import mean_stay, noise_level, steady
#
# Only some corpora move when their symbols are renumbered, and the property behind it was narrowed
# twice by things that turned out not to be it. Ordered values was wrong, since recorded speech is
# as ordered as a greyscale level and holds. Nearness between neighbors was wrong on its own, since
# speech sits at 0.54 and whale song at 0.48 and only one of them moves.
#
# What the moving corpora have is not small steps but long stays. A picture is flat regions with
# edges between them, and a row crossing a stretch of sky holds near one value for a long run.
# Whale song is sustained calls holding a tone. Speech has small steps and never stays anywhere,
# because articulation never stops moving, and text has neither.
#
# The band is a share of each corpus's own spread and not a fixed count of levels. A fixed band is
# wide for a corpus using few levels and narrow for one using many, which read a picture spread over
# 160 levels as having no stays while it had the strongest dependence in the set, and read a corpus
# of eight symbols as one run covering all 120000 positions.

import numpy

# The band, as a share of the corpus's own spread of values.
BAND_SHARE = 0.25


def mean_stay(values, band):
    """Mean run length before the value leaves a band around where the run started.

    A flat region gives that and an oscillation does not, however smooth the oscillation is. The same count on a shuffle of the corpus is the floor, since a band of any
    width catches some positions by chance.
    """
    total = 0
    runs = 0
    index = 0
    limit = len(values)

    while index < limit:
        start = values[index]
        walk = index + 1
        while (walk < limit) and (abs(int(values[walk]) - int(start)) <= band):
            walk += 1
        total += walk - index
        runs += 1
        index = walk
    return (total / float(runs)) if runs else 0.0


def band_for(values, share=BAND_SHARE):
    """The band width to use for one corpus, scaled to its own spread."""
    return max(1.0, share * float(numpy.asarray(values, dtype=numpy.float64).std()))


def noise_level(floats):
    """Standard deviation of the uncorrelated part, from the median of the second differences.

    A second difference cancels any straight run, so what it leaves is noise plus the real edges.
    The edges are sparse, so the median is set by the noise alone and a surface full of hard
    crossings does not inflate the estimate. A second difference of pure noise has six times its
    variance.

    This settles a reading that was made and then reversed. The high frequency part of a painting
    was called the grain of the photograph, which would have made an ordering an artifact of how
    each canvas was shot. What decides it is what averaging does: anything uncorrelated falls as one
    over the square root of the block, and not one of seven paintings falls that way.
    """
    second = floats[2:] - (2.0 * floats[1:-1]) + floats[:-2]
    return 1.4826 * float(numpy.median(numpy.abs(second))) / numpy.sqrt(6.0)


def steady(floats):
    """The series with isolated spikes removed and its edges intact, by a median of every three."""
    stacked = numpy.stack([floats[:-2], floats[1:-1], floats[2:]])
    return numpy.median(stacked, axis=0)


def abruptness(values, authored_only=False):
    """Share of steps larger than the corpus's own spread, optionally with the grain removed.

    A picture holds two kinds of abruptness and only one belongs to whoever made it. The raw share
    counts every crossing, brushwork and sensor grain alike, and a dark surface carries noise in its
    shadows that lands in the count as if it had been painted.

    Abruptness does not cross families. English text is the most abrupt corpus measured anywhere at
    0.4903 and does not depend on its numbering at all, while every painting measured lies between
    0.0064 and 0.1709. It orders magnitude only among corpora already inside the smooth regime.
    """
    floats = numpy.asarray(values, dtype=numpy.float64)
    spread = float(floats.std())
    if spread <= 0.0:
        return 0.0
    series = steady(floats) if authored_only else floats
    return float((numpy.abs(numpy.diff(series)) > spread).mean())
