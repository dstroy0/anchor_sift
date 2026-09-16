#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: SND-4-004
#
# The Hampel outlier filter with the magic number removed: the band is drawn from the neighbours.
#
#   Usage:  python examples/sound/4_measure/outliers_removed_without_a_threshold.py
#
# The Hampel identifier is the standard rank test for an impulse: window a point, take the median and
# the median absolute deviation, and flag the point when it sits more than a chosen number of MADs
# away. That number is the whole difficulty. It is a constant the author picks, and it is exactly the
# judgement-picked tolerance this tree forbids: move it and the outlier count moves, and nothing in the
# data said what it should be.
#
# Here the band is drawn instead of chosen. A point's neighbours already show a spread around their own
# median; a clean point sits inside it because it is one more neighbour, and an impulse leaves it
# because it came from somewhere else. So the band a point must clear is the largest deviation its
# neighbours reach from their median, with the point left out so it cannot widen its own band. No
# constant appears. measure/local_outlier draws the band and reference/windowed supplies the median the
# flagged point is replaced with.
#
# On a piecewise-constant signal the neighbours agree exactly, so the band is zero and any impulse is
# unmistakable, and the window median is the block value exactly, so the restoration is bit-exact. That
# is the positive control. Two floors are stated, both inherited honestly rather than tuned away: two
# impulses in one window let one widen the band that should have caught the other, the Hampel breakdown,
# and a signal that varies inside the window is restored to the local median rather than to itself, so
# the recovery is exact only where the signal is locally flat.
#
# Two routes take the median, a sort and a counting select, and a clean signal and a smoothly varying
# one are both required to draw no flags, so the filter is shown not to scrub what it was not built to
# remove. A native-C route is the natural hardening and is not claimed here.

import io
import os
import random
import sys
from fractions import Fraction

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.local_outlier import outliers  # noqa: E402
from reference.windowed import (window_median, window_median_counted,  # noqa: E402
                                median_filtered, restore_at)

# Declared inputs, printed with every reading.
BLOCK = 20
LEVELS = (50, 120, 200, 80)
RADIUS = 3               # window is 2*RADIUS+1 = 7
SEED = 0x0111


def piecewise(levels, block):
    signal = []
    for level in levels:
        signal += [level] * block
    return signal


def scatter(signal, count, radius, block, seed, spaced=True):
    """Replace `count` samples with a value from nowhere, away from block edges.

    With `spaced` the impulses are kept more than a window apart, so every window holds at most one and
    the positive control is a control. Without it they are allowed to crowd, which is the floor.
    """
    rng = random.Random(seed)
    out = list(signal)
    edges = set()
    for start in range(0, len(signal), block):
        for step in range(radius + 1):
            edges.add(start + step)
            edges.add(start + block - 1 - step)
    picked = []
    order = list(range(len(signal)))
    rng.shuffle(order)
    for position in order:
        if position in edges:
            continue
        if spaced and any(abs(position - other) <= 2 * radius + 1 for other in picked):
            continue
        value = rng.randrange(256)
        if value == out[position]:
            value = (value + 7) % 256
        out[position] = value
        picked.append(position)
        if len(picked) >= count:
            break
    return out, picked


def reduction(noisy, cleaned, clean):
    injected = sum((Fraction(noisy[n]) - clean[n]) ** 2 for n in range(len(clean)))
    left = sum((Fraction(cleaned[n]) - clean[n]) ** 2 for n in range(len(clean)))
    if injected == 0:
        return Fraction(1)
    return Fraction(1) - left / injected


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    clean = piecewise(LEVELS, BLOCK)
    out.write("  outliers removed without a threshold\n")
    out.write("  declared inputs: block=%d levels=%s radius=%d seed=0x%X\n\n"
              % (BLOCK, LEVELS, RADIUS, SEED))

    dirty, impulses = scatter(clean, 6, RADIUS, BLOCK, SEED, spaced=True)

    # two routes for the median must land on the same integer on every window
    med_routes = all(window_median(dirty, i, RADIUS) == window_median_counted(dirty, i, RADIUS)
                     for i in range(len(dirty)))
    out.write("  reject: sort and counting median routes agree on every window: %s\n" % med_routes)

    flagged = outliers(dirty, RADIUS)
    restored = restore_at(dirty, RADIUS, flagged)
    exact = restored == clean
    nrr = reduction(dirty, restored, clean)
    out.write("  identify: band drawn from neighbours; flagged == the impulses: %s\n"
              % (flagged == set(impulses)))
    out.write("  reject: restored equals the clean signal as integers: %s\n" % exact)
    out.write("  reject: impulses %d, reduction %s = %.4f%%\n\n"
              % (len(impulses), nrr, float(nrr) * 100.0))

    # negative controls: must not flag what it was not built to remove
    out.write("  negative controls: the filter must draw no flags on a clean signal.\n")
    out.write("  %-28s %-12s %s\n" % ("case", "flags", "outcome"))
    out.write("  %-28s %-12d %s\n" % ("no noise (piecewise flat)", len(outliers(clean, RADIUS)),
                                      "untouched: %s" % (restore_at(clean, RADIUS, outliers(clean, RADIUS)) == clean)))
    ramp = [20 + index for index in range(len(clean))]            # varies smoothly, no discontinuity
    ramp_flags = outliers(ramp, RADIUS)
    out.write("  %-28s %-12d %s\n" % ("smooth ramp, no impulses", len(ramp_flags),
                                      "untouched: %s" % (restore_at(ramp, RADIUS, ramp_flags) == ramp)))

    # floor: crowding (masking) and a varying signal
    out.write("\n  floor: crowded impulses mask each other, and a varying signal restores to the median\n")
    out.write("  %-28s %-14s %s\n" % ("case", "reduction", "why"))
    for count in (6, 12, 20):
        crowd, hits = scatter(clean, count, RADIUS, BLOCK, SEED, spaced=False)
        got = restore_at(crowd, RADIUS, outliers(crowd, RADIUS))
        out.write("  %-28s %-14.4f %s\n"
                  % ("%d impulses, allowed to crowd" % len(hits), float(reduction(crowd, got, clean)) * 100.0,
                     "two in a window mask one" if count > 6 else "still sparse"))
    ramp_dirty, ramp_hits = scatter(ramp, 6, RADIUS, BLOCK, SEED, spaced=True)
    ramp_got = restore_at(ramp_dirty, RADIUS, outliers(ramp_dirty, RADIUS))
    out.write("  %-28s %-14.4f %s\n"
              % ("impulses on the ramp", float(reduction(ramp_dirty, ramp_got, ramp)) * 100.0,
                 "median is not the exact ramp value"))

    out.write("\n  the positive control is bit-exact because the neighbours agree exactly, so the band is\n")
    out.write("  zero and the median is the block value. the floors are the Hampel breakdown and a\n")
    out.write("  varying signal, both stated rather than removed by a number nobody could justify.\n")
    out.flush()
    return 0 if (med_routes and exact and flagged == set(impulses)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
