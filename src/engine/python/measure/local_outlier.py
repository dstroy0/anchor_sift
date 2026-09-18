#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Whether a sample is an outlier, decided by the spread its own neighbors show.
#
#   Usage:  from measure.local_outlier import band_top, is_outlier, outliers
#
# The Hampel identifier is the standard rank test for an outlier: take the window around a point, its
# median and its median absolute deviation, and flag the point when it sits more than a few MADs from
# the median. The "few" is the whole problem. It is a constant the author picks, 1.4826 times some
# chosen number of deviations, and it is exactly the judgement-picked tolerance this tree does not
# allow. Change it and the count of outliers changes, and nothing in the data said what it should be.
#
# The fix is the tree's standing move: draw the boundary from the data instead of choosing it. The
# neighbors of a point already show a spread around their own median. A clean point sits inside that
# spread, because it is one more neighbor. An impulse leaves it, because it was drawn from somewhere
# else. So the band a point must clear is the largest deviation its neighbors reach from their median,
# with the point itself left out so it cannot widen its own band. No constant is chosen; the band is
# whatever the neighbourhood shows.
#
# This inherits the Hampel breakdown honestly. That is the floor, the
# same floor a MAD test has, and it is a property of a window holding more than one outlier and not of
# the boundary being drawn. Where a window holds at most one, the test is exact and needs no number.
#
# The window radius is a declared input, reported by the caller. Everything here is integer comparison;
# there is no tolerance and no scale.

from reference.windowed import _window, window_median


def neighbour_median(values, index, radius):
    """The median of the window around `index` with the sample at `index` left out.

    The value the neighbors agree on, which the sample under test does not get to vote on.
    """
    return window_median(values, index, radius, include_center=False)


def band_top(values, index, radius):
    """The largest distance any neighbor sits from the neighbors' median: the drawn band.

    The spread the neighbourhood shows on its own. A sample inside this band is one the neighbors
    could have produced; a sample beyond it is one they could not. Returns 0 where the neighbors all
    agree, the case that makes a lone impulse unmistakable.
    """
    middle = neighbour_median(values, index, radius)
    neighbors = _window(values, index, radius, include_center=False)
    if not neighbors:
        return 0
    return max(abs(value - middle) for value in neighbors)


def is_outlier(values, index, radius):
    """Whether the sample at `index` sits beyond the band its neighbors draw.

    True when the sample's distance from the neighbors' median is larger than any neighbor's. The
    neighbourhood could not have produced it. Interior only: a point without a full window on both
    sides is an edge and is never flagged, a declared choice.
    """
    if (index < radius) or (index + radius >= len(values)):
        return False
    middle = neighbour_median(values, index, radius)
    return abs(values[index] - middle) > band_top(values, index, radius)


def outliers(values, radius):
    """Every interior position whose sample sits beyond the band its neighbors draw."""
    return {index for index in range(len(values)) if is_outlier(values, index, radius)}
