#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-006
#
# Reject a trend the outliers cannot drag: the slope the majority of pairs agree on (Theil-Sen).
#
#   Usage:  python examples/0_experimental/theil_sen_robust_trend.py
#
# This reads no corpus. It sits in 0_experimental: an algorithm shown working, a robust-regression
# filter beside the signal ones. The invariant here is a linear trend, and the consensus is the slope
# the majority of point PAIRS agree on: the Theil-Sen estimator takes the median of every pairwise
# slope, and the intercept as the median of the residual offsets. It is application logic and not an
# engine primitive, for the same reason the collaborative filter is -- a trend estimate is what a
# reading is measured INTO, not the null it stands against.
#
# Why it is in the family. Two points from a clean line give exactly the line's slope; a point pulled
# off the line by an outlier gives a slope that is nearly anything. So the clean pairs all agree on one
# slope and the corrupted pairs scatter, and the median lands on the value the clean majority carries,
# exactly as the phase consensus lands on the value the clean members of a class carry. It rejects the
# trend robustly: subtract the Theil-Sen line and the residual is the signal with its trend gone, and a
# handful of outliers did not move the trend.
#
# TWO ROUTES THAT GENUINELY DISAGREE, AND THE DISAGREEMENT IS THE FINDING. Least-squares fits the same
# line by minimising squared error, and a single outlier drags it because a square rewards the fit for
# chasing the far point. Theil-Sen and least-squares therefore return DIFFERENT slopes on the same data
# whenever an outlier is present, and that gap is not a bug to reconcile: it is the measurement of what
# a square costs. Where the data is clean the two agree; where it is not, the robust route
# kept the slope and the square is the wrong reference.
#
# NOTHING IS BOUNDED HERE. The slope is a median, a rank, not a residual threshold chosen by anyone. The
# arithmetic is exact rational. A clean line is recovered to the last digit. The floor is stated and
# swept: Theil-Sen's slope breaks near a bit under a third of the points being outliers, the published
# breakdown point, and the sweep shows it move.

import io
import os
import random
import sys
from fractions import Fraction


def median(values):
    """The exact median of a list, the lower-and-upper average on an even count, kept rational."""
    ordered = sorted(values)
    count = len(ordered)
    middle = count // 2
    if count % 2:
        return Fraction(ordered[middle])
    return (Fraction(ordered[middle - 1]) + Fraction(ordered[middle])) / 2


def theil_sen(xs, ys):
    """The median of every pairwise slope, and the median residual offset. Exact rational."""
    slopes = []
    for i in range(len(xs)):
        for j in range(i + 1, len(xs)):
            if xs[j] != xs[i]:
                slopes.append(Fraction(ys[j] - ys[i], xs[j] - xs[i]))
    slope = median(slopes)
    intercept = median([Fraction(ys[i]) - slope * xs[i] for i in range(len(xs))])
    return slope, intercept


def least_squares(xs, ys):
    """The least-squares slope and intercept, exact rational: the non-robust route an outlier drags."""
    n = len(xs)
    sx = sum(xs); sy = sum(ys)
    sxx = sum(x * x for x in xs); sxy = sum(xs[i] * ys[i] for i in range(n))
    slope = Fraction(n * sxy - sx * sy, n * sxx - sx * sx)
    intercept = Fraction(sy) / n - slope * Fraction(sx, n)
    return slope, intercept


def build(n, slope, intercept, outliers, seed):
    xs = list(range(n))
    ys = [slope * x + intercept for x in xs]
    clean = list(ys)
    rng = random.Random(seed)
    for pos in rng.sample(range(n), outliers):
        ys[pos] = ys[pos] + rng.choice([-1, 1]) * rng.randint(200, 400)   # pulled far off the line
    return xs, ys, clean


def build_competing(n, slope, intercept, competitors, comp_slope, comp_intercept, seed):
    """Replace `competitors` points with points on a DIFFERENT line, an adversarial conspiracy that
    fakes a second trend. When its pairs outnumber the clean ones the median
    slope follows it -- the honest breakdown, a majority of pairs agreeing on the wrong slope."""
    xs = list(range(n))
    ys = [slope * x + intercept for x in xs]
    rng = random.Random(seed)
    for pos in rng.sample(range(n), competitors):
        ys[pos] = comp_slope * xs[pos] + comp_intercept
    return xs, ys


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Theil-Sen: reject a trend the outliers cannot drag (median of pairwise slopes)\n")
    out.write("  declared inputs: n=30, true slope 3, intercept 7\n\n")

    true_slope, true_intercept = 3, 7
    xs, ys, clean = build(30, true_slope, true_intercept, outliers=6, seed=0x7E15)

    ts_slope, ts_intercept = theil_sen(xs, ys)
    ls_slope, ls_intercept = least_squares(xs, ys)
    out.write("  positive control: 30 points, 6 outliers\n")
    out.write("    Theil-Sen slope %s (true %d): exact: %s\n"
              % (ts_slope, true_slope, ts_slope == true_slope))
    out.write("    least-squares slope %s: dragged off the truth: %s\n"
              % (ls_slope, ls_slope != true_slope))
    out.write("    the two routes disagree, and the disagreement is what a square costs.\n\n")

    # no noise: both routes recover exactly and agree
    xc, yc, _ = build(30, true_slope, true_intercept, outliers=0, seed=0)
    cs, ci = theil_sen(xc, yc)
    ls2, li2 = least_squares(xc, yc)
    out.write("  no noise: Theil-Sen %s and least-squares %s both equal the true slope: %s\n\n"
              % (cs, ls2, cs == true_slope and ls2 == true_slope))

    # drawn null: shuffle y against x, destroying the trend -> the consensus slope collapses to zero
    rng = random.Random(0x99)
    yn = list(ys); rng.shuffle(yn)
    ns, _ = theil_sen(xs, yn)
    out.write("  drawn null: with y shuffled against x the trend is gone; Theil-Sen slope %s (near 0)\n\n"
              % ns)

    # two floors. First: scattered outliers cancel. The median holds well past a third -- a real
    # robustness, since a value from nowhere is a different nowhere each time.
    out.write("  floor A, scattered outliers (pull each way, they cancel):\n")
    out.write("  %-16s %-16s %s\n" % ("outlier share", "Theil-Sen slope", "still exact"))
    for outliers in (6, 12, 15):
        xf, yf, _ = build(30, true_slope, true_intercept, outliers=outliers, seed=0x100 + outliers)
        fs, _ = theil_sen(xf, yf)
        out.write("  %-16s %-16s %s\n"
                  % ("%d/30 = %d%%" % (outliers, outliers * 100 // 30), str(fs), fs == true_slope))

    # Second: an ADVERSARIAL conspiracy on a competing line. When its pairs outnumber the clean ones
    # the median follows the wrong slope -- the breakdown, the majority of pairs agreeing on a lie.
    out.write("  floor B, a conspiracy faking a competing slope of -2:\n")
    out.write("  %-16s %-16s %s\n" % ("conspiracy share", "Theil-Sen slope", "still exact"))
    for competitors in (10, 14, 16, 18):
        xf, yf = build_competing(30, true_slope, true_intercept, competitors, -2, 500, seed=0x200 + competitors)
        fs, _ = theil_sen(xf, yf)
        out.write("  %-16s %-16s %s\n"
                  % ("%d/30 = %d%%" % (competitors, competitors * 100 // 30), str(fs), fs == true_slope))

    out.write("\n  the clean pairs all agree on the true slope and scattered outliers cancel. The\n")
    out.write("  median lands on the truth while least-squares chases the far points -- that is the\n")
    out.write("  phase consensus again, over pairwise slopes instead of a phase class. the breakdown is\n")
    out.write("  floor B: a conspiracy whose pairs outnumber the clean ones makes the median follow the\n")
    out.write("  wrong slope, the one accident a consensus cannot refuse -- the same shape as ROBIN's\n")
    out.write("  conspiring outliers winning the clique.\n")
    out.flush()
    ok = (ts_slope == true_slope) and (ls_slope != true_slope) and (cs == true_slope)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
