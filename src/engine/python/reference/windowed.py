#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The background a neighbourhood allows: the value its window agrees on, read as a rank.
#
#   Usage:  from reference.windowed import window_median, median_filtered, restore_at
#
# A rank background groups by neither position nor content but by NEARNESS: a value is estimated from
# the window around it. The estimate is the median, the middle value of the window, which is the rank
# statistic a majority of the window agrees on and the one an impulse cannot move, because dragging the
# middle takes more than half the window rather than one large value. That is why a median rejects the
# replacement noise a mean cannot: the mean is the first moment and one impulse owns it, the median is
# the middle rank and one impulse is just one more vote.
#
# This is the background under the medians and rank filters, and the piece measure/local_outlier reads
# a departure against. The median is an exact integer, taken as the lower of the two middle values on
# an even window, a declared rule and not a tolerance. Nothing here is bounded: the window radius is a
# declared input the caller reports, and the rank is a position in a sorted list, not a threshold.
#
# Two routes take the median and share no code: one sorts the window and reads the middle, the other
# counts the values and walks the counts to the middle rank. A sort and a counting select reach the
# same integer by different work. The two agreeing is a check. A native-C route is the natural
# hardening and is not claimed here.


def _window(values, index, radius, include_center):
    low = max(0, index - radius)
    high = min(len(values), index + radius + 1)
    if include_center:
        return values[low:high]
    return values[low:index] + values[index + 1:high]


def window_median(values, index, radius, include_center=True):
    """The median of the window around `index`, by sorting. The lower middle on an even count.

    `include_center` false reads the window with the center left out, which is what an outlier test
    wants: the value the neighbours agree on, uncontaminated by the sample under test.
    """
    window = sorted(_window(values, index, radius, include_center))
    return window[(len(window) - 1) // 2]


def window_median_counted(values, index, radius, include_center=True):
    """The same median, by counting the values and walking to the middle rank. The second route.

    It builds a tally and advances through the values in order until it passes the middle. It shares
    no sort with window_median. The two must return the same integer on every window.
    """
    window = _window(values, index, radius, include_center)
    target = (len(window) - 1) // 2
    tally = {}
    for value in window:
        tally[value] = tally.get(value, 0) + 1
    seen = 0
    for value in sorted(tally):
        seen += tally[value]
        if seen > target:
            return value
    return None


def median_filtered(values, radius, route=window_median):
    """Every position replaced by its window median: the plain median filter.

    Smooths and removes impulses together, at the cost of a signal that varies inside the window, which
    it flattens toward the local middle. `restore_at` is the gentler use, replacing only where an
    outlier was found rather than everywhere.
    """
    return [route(values, index, radius) for index in range(len(values))]


def restore_at(values, radius, flagged):
    """The signal with only the `flagged` positions replaced by their neighbours' median.

    The reject step for the Hampel-style filter: a clean sample is left exactly as it is, and only a
    flagged outlier is replaced, by the median of its window with itself left out so the impulse does
    not vote on its own replacement. This preserves every value the detector did not flag, which a
    plain median filter does not.
    """
    flagged = set(flagged)
    out = list(values)
    for index in flagged:
        out[index] = window_median(values, index, radius, include_center=False)
    return out
