#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Run only the halving ladder from tools/dev_env/noise_detection.py, over many corpora, so the loss
# ratio can be plotted against collision entropy.
#
#   Usage:  python tools/dev_env/ladder_sweep.py corpus.sym [more.sym ...]
#
# One corpus gave a loss ratio of 1.600 with a standard error of 0.107, an interval containing several
# named constants and identifying none. Three more gave 1.049, 1.388 and 2.352, which rules out a
# constant and leaves an ordering with the alphabet weight over four points. This runs the ladder alone,
# without the corruption rate sweep and the permutation nulls, so every corpus already fetched can be
# measured and the ordering either survives twelve points or does not.

import io
import math
import os
import random
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

WINDOWS = (4096, 2048, 1024, 512, 256, 128, 64, 32, 16)
RATE = 0.005

# Where the corrupted block lands. It is settable because a quantity computed from these rows is only
# a property of the corpora if it survives moving the block, and one that moves with the seed is a
# property of the draw
SEED = int(os.environ.get("LADDER_SEED", "30"))


def collision_bits(seats):
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    total = float(len(seats))
    return -math.log2(sum((count / total) ** 2 for count in counts.values()))


def corrupt_block(seats, rate, alphabet, seed):
    out = bytearray(seats)
    count = int(len(seats) * rate)
    if count <= 0:
        return out
    rng = random.Random(seed)
    start = rng.randrange(0, max(1, len(seats) - count))
    for index in range(start, start + count):
        out[index] = rng.choice(alphabet)
    return out


def separation(seats, window):
    marks = [collision_bits(seats[start:start + window])
             for start in range(0, len(seats) - window + 1, window)]
    if len(marks) < 4:
        return None
    sigma = statistics.pstdev(marks)
    if sigma <= 0.0:
        return None
    return (max(marks) - statistics.median(marks)) / sigma


def main():
    if len(sys.argv) < 2:
        print("usage: ladder_sweep.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-30s %-8s %-12s %-8s %s\n" % ("corpus", "H2", "loss ratio", "stderr", "rows"))

    rows = []
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            seats = bytearray(handle.read())
        if len(seats) < 4096 * 8:
            continue
        alphabet = sorted(set(seats))
        spoiled = corrupt_block(seats, RATE, alphabet, SEED)

        ladder = []
        for window in WINDOWS:
            apart = separation(spoiled, window)
            if apart is not None:
                ladder.append(apart)
        if len(ladder) < 5:
            continue

        losses = [ladder[index - 1] - ladder[index] for index in range(1, len(ladder))]
        ratios = [losses[index] / losses[index - 1]
                  for index in range(1, len(losses)) if abs(losses[index - 1]) > 1e-9]
        if len(ratios) < 3:
            continue

        mean = statistics.fmean(ratios)
        stderr = statistics.pstdev(ratios) / math.sqrt(len(ratios))
        bits = collision_bits(seats)
        rows.append((bits, mean, stderr, len(ratios), os.path.basename(path)[:-4]))

    for bits, mean, stderr, count, name in sorted(rows):
        out.write("  %-30s %-8.3f %-12.4f %-8.4f %d\n" % (name, bits, mean, stderr, count))

    # Whether a line through these means anything. Reported unweighted and weighted by each point's own
    # precision, since the standard errors here span an order of magnitude and an unweighted fit lets the
    # least certain points pull hardest
    def fit(points, weights):
        total = sum(weights)
        mean_x = sum(w * x for (x, _), w in zip(points, weights)) / total
        mean_y = sum(w * y for (_, y), w in zip(points, weights)) / total
        sxx = sum(w * (x - mean_x) ** 2 for (x, _), w in zip(points, weights))
        sxy = sum(w * (x - mean_x) * (y - mean_y) for (x, y), w in zip(points, weights))
        syy = sum(w * (y - mean_y) ** 2 for (_, y), w in zip(points, weights))
        if (sxx <= 0.0) or (syy <= 0.0):
            return None
        slope = sxy / sxx
        rsq = (sxy * sxy) / (sxx * syy)
        # Standard error of the slope from the residual scatter, and the t it implies
        residual = sum(w * (y - mean_y - slope * (x - mean_x)) ** 2
                       for (x, y), w in zip(points, weights))
        degrees = len(points) - 2
        if degrees <= 0:
            return None
        slope_err = math.sqrt((residual / degrees) / sxx)
        return slope, rsq, slope_err, (slope / slope_err if slope_err > 0.0 else float("inf"))

    # A slope, a standard error and a t are only meaningful if the residuals are normal, and the
    # quantity here was already described as heavy tailed. Skewness and excess kurtosis give the
    # Jarque-Bera statistic, which is chi square on two degrees of freedom, so 5.99 is the five percent
    # point and 9.21 the one percent point
    def normality(values):
        count = len(values)
        if count < 8:
            return None
        mean = statistics.fmean(values)
        spread = statistics.pstdev(values)
        if spread <= 0.0:
            return None
        skew = sum(((value - mean) / spread) ** 3 for value in values) / count
        kurtosis = sum(((value - mean) / spread) ** 4 for value in values) / count - 3.0
        statistic = count * ((skew * skew) / 6.0 + (kurtosis * kurtosis) / 24.0)
        return skew, kurtosis, statistic

    marks = [mean for _, mean, _, _, _ in rows]
    got = normality(marks)
    if got is not None:
        skew, kurtosis, statistic = got
        out.write("\n  is the loss ratio normal, over %d corpora\n" % len(marks))
        out.write("    skew %+7.4f  excess kurtosis %+8.4f  Jarque-Bera %8.3f  %s\n"
                  % (skew, kurtosis, statistic,
                     "normal not rejected" if statistic < 5.99 else
                     ("rejected at 5%" if statistic < 9.21 else "rejected at 1%")))

    points = [(bits, mean) for bits, mean, _, _, _ in rows]
    flat = [1.0] * len(points)
    sharp = [1.0 / (stderr ** 2) if stderr > 1e-9 else 1.0 for _, _, stderr, _, _ in rows]

    out.write("\n  a line through %d points, loss ratio against H2\n" % len(points))
    for label, weights in (("unweighted", flat), ("weighted", sharp)):
        got = fit(points, weights)
        if got is None:
            continue
        slope, rsq, slope_err, tstat = got
        out.write("    %-12s slope %+8.4f  stderr %7.4f  t %+6.2f  r2 %.4f\n"
                  % (label, slope, slope_err, tstat, rsq))

    # A line from the origin through one point has slope ratio/H2. Points sharing a line share that
    # slope, so if the corpora fall into families each with its own proportionality the slopes cluster
    # by family and scatter within it
    def family(name):
        if name.startswith("monkey"):
            return "memoryless"
        if name.startswith("morse"):
            return "percussive"
        if ("keystream" in name) or ("repeatkey" in name) or ("substitute" in name):
            return "ciphered"
        if name.startswith("csource"):
            return "formal"
        return "natural"

    groups = {}
    for bits, mean, stderr, _, name in rows:
        groups.setdefault(family(name), []).append(mean / bits)

    out.write("\n  slope from the origin, by family\n")
    out.write("    %-12s %-6s %-10s %-10s %s\n" % ("family", "n", "mean k", "spread", "range"))
    for label in sorted(groups):
        marks = groups[label]
        if len(marks) < 2:
            continue
        out.write("    %-12s %-6d %-10.4f %-10.4f %.4f to %.4f\n"
                  % (label, len(marks), statistics.fmean(marks), statistics.pstdev(marks),
                     min(marks), max(marks)))

    everything = [value for marks in groups.values() for value in marks]
    out.write("    %-12s %-6d %-10.4f %-10.4f %.4f to %.4f\n"
              % ("all", len(everything), statistics.fmean(everything),
                 statistics.pstdev(everything), min(everything), max(everything)))

    # Written out so the same numbers can be analyzed with tools that carry proper tests, since the
    # statistics reachable in this file assume a normality these values reject
    target = os.path.join(ROOT, "build", "ladder.csv")
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("corpus,family,h2,ratio,stderr,rows\n")
        for bits, mean, stderr, count, name in sorted(rows):
            handle.write("%s,%s,%.6f,%.6f,%.6f,%d\n" % (name, family(name), bits, mean, stderr, count))
    out.write("\n  wrote %s with %d rows\n" % (target, len(rows)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
