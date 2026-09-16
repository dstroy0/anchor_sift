#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Mathematical morphology: opening removes bright speckle, closing fills dark speckle, by rank alone.
#
#   Usage:  python examples/0_experimental/morphology_opening_and_closing.py
#
# This reads no corpus, so it sits in 0_experimental: an algorithm shown working, an image-morphology
# filter beside the signal ones. Erosion takes the minimum over a structuring element, dilation the
# maximum; opening is an erosion then a dilation, closing a dilation then an erosion. Opening removes a
# bright feature narrower than the element and leaves everything wider untouched; closing does the same
# for a dark feature. It is a rank operator, so like the windowed median it rejects a replacement noise
# a mean cannot, and it needs no threshold: the element width is a declared input and min and max are
# positions in a sorted window, not tolerances.
#
# It is application logic rather than an engine primitive, and for the reason the collaborative filter
# is: opening TRANSFORMS the reading into a different reading of itself. It is not a null a departure is
# measured against, so it is not a reference-stage object; it is an operator, and operators live in the
# example until the ladder has a place for them.
#
# Two routes take the min and the max with no shared code: one sorts the window and reads an end, the
# other walks the window tracking a running extreme. The floor is stated: a real feature narrower than
# the element is removed with the speckle, because rank alone cannot tell a one-pixel spike that is
# signal from one that is noise.

import io
import os
import sys


def window(values, index, radius):
    return values[max(0, index - radius):min(len(values), index + radius + 1)]


def erode_sorted(values, radius):
    return [sorted(window(values, i, radius))[0] for i in range(len(values))]


def dilate_sorted(values, radius):
    return [sorted(window(values, i, radius))[-1] for i in range(len(values))]


def erode_running(values, radius):
    out = []
    for i in range(len(values)):
        low = None
        for value in window(values, i, radius):
            low = value if (low is None or value < low) else low
        out.append(low)
    return out


def dilate_running(values, radius):
    out = []
    for i in range(len(values)):
        high = None
        for value in window(values, i, radius):
            high = value if (high is None or value > high) else high
        out.append(high)
    return out


def opening(values, radius, erode=erode_sorted, dilate=dilate_sorted):
    return dilate(erode(values, radius), radius)


def closing(values, radius, erode=erode_sorted, dilate=dilate_sorted):
    return erode(dilate(values, radius), radius)


def plateaus(widths, levels):
    signal = []
    for width, level in zip(widths, levels):
        signal += [level] * width
    return signal


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    radius = 2                                                  # element width 2*radius+1 = 5
    out.write("  morphology: opening removes bright speckle, closing fills dark speckle\n")
    out.write("  declared inputs: structuring element radius=%d (width %d)\n\n" % (radius, 2 * radius + 1))

    clean = plateaus([15, 15, 15, 15], [50, 200, 50, 200])

    # bright speckle inside the low plateaus; dark speckle inside the high plateaus
    bright = list(clean)
    for pos in (4, 8, 34, 38):
        bright[pos] = 255
    dark = list(clean)
    for pos in (18, 22, 48, 52):
        dark[pos] = 0

    # two routes for the min/max must agree
    routes_agree = (erode_sorted(bright, radius) == erode_running(bright, radius)
                    and dilate_sorted(bright, radius) == dilate_running(bright, radius))
    out.write("  reject: sort and running routes agree on erosion and dilation: %s\n" % routes_agree)

    opened = opening(bright, radius)
    closed = closing(dark, radius)
    open_exact = opened == clean
    close_exact = closed == clean
    out.write("  opening removed the bright speckle exactly: %s\n" % open_exact)
    out.write("  closing filled the dark speckle exactly:    %s\n" % close_exact)

    # negative control: a clean signal with no speckle is left as it is by the interior
    interior_ok = opening(clean, radius)[radius:-radius] == clean[radius:-radius]
    out.write("\n  negative control: opening a clean signal leaves its interior untouched: %s\n" % interior_ok)

    # floor: a real feature narrower than the element is removed with the speckle
    narrow = plateaus([15, 3, 15], [50, 200, 50])              # the middle plateau is width 3 < 5
    opened_narrow = opening(narrow, radius)
    lost = opened_narrow != narrow
    out.write("  floor: a real feature narrower than the element (width 3 < %d) is removed too: %s\n"
              % (2 * radius + 1, lost))
    out.write("\n  opening and closing reject a speckle by rank, with no threshold: the element width is\n")
    out.write("  the one declared input. the floor is honest -- a spike narrower than the element is\n")
    out.write("  removed whether it was noise or signal, because rank alone cannot tell them apart.\n")
    out.flush()
    return 0 if (routes_agree and open_exact and close_exact and interior_ok and lost) else 1


if __name__ == "__main__":
    raise SystemExit(main())
