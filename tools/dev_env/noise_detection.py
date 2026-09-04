#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Corrupt a corpus at known rates and report what each detector sees, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/noise_detection.py corpus.sym
#
# Two quantities in this work respond to different things and neither is a checksum. Collision entropy is
# computed from the histogram, so it is permutation invariant and cannot depend on where corruption sits,
# only on how much of it there is. Dispersion against a permutation null is computed from the positions,
# so it responds to arrangement and is blind to a change that leaves the counts alone.
#
# Corruption is applied two ways to separate them. Scattered draws land uniformly across the corpus and
# a contiguous block lands in one place, and both replace the same number of symbols, so a detector that
# reports the same figure for both is reading composition and one that does not is reading position.
#
# The natural spread of collision entropy over ten English texts spanning 1609 to 1861 is 3.693 to 3.891
# bits, so a shift is only evidence once it leaves that band.

import io
import math
import os
import random
import statistics
import sys

MIN_OCCURRENCES = 32
RATES = (0.0, 0.0001, 0.001, 0.01, 0.05, 0.10, 0.25, 0.50)


def collision_bits(seats):
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    total = float(len(seats))
    return -math.log2(sum((count / total) ** 2 for count in counts.values()))


def dispersion_by_symbol(seats):
    seen = {}
    for index, value in enumerate(seats):
        seen.setdefault(value, []).append(index)
    out = {}
    for value, positions in seen.items():
        if len(positions) < MIN_OCCURRENCES:
            continue
        gaps = [positions[step] - positions[step - 1] for step in range(1, len(positions))]
        mean = statistics.fmean(gaps)
        if mean > 0.0:
            out[value] = statistics.pstdev(gaps) / mean
    return out


def tail_ratio(seats, seed):
    """Mean permutation null ratio over the rare half of the symbols."""
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    live = dispersion_by_symbol(seats)
    shuffled = bytearray(seats)
    random.Random(seed).shuffle(shuffled)
    dead = dispersion_by_symbol(shuffled)

    rows = []
    for value, spread in live.items():
        if (value in dead) and (spread > 0.0):
            rows.append((counts[value], dead[value] / spread))
    if len(rows) < 4:
        return float("nan")
    rows.sort(reverse=True)
    return statistics.fmean(row[1] for row in rows[len(rows) // 2:])


def corrupt(seats, rate, alphabet, seed, contiguous):
    """Replace a share of the symbols with uniform draws, scattered or in one run."""
    out = bytearray(seats)
    count = int(len(seats) * rate)
    rng = random.Random(seed)
    if count <= 0:
        return out
    if contiguous:
        start = rng.randrange(0, max(1, len(seats) - count))
        spots = range(start, start + count)
    else:
        spots = rng.sample(range(len(seats)), count)
    for index in spots:
        out[index] = rng.choice(alphabet)
    return out


def locate(seats, window, clean_bits):
    """Collision entropy per window, which is where a global statistic regains a position.

    Collision entropy is permutation invariant over whatever span it is computed on, so a single figure
    for a whole corpus cannot say where anything is. Computed window by window it can, and a corruption
    that is a small share of a corpus is a large share of the one window holding it.
    """
    marks = []
    for start in range(0, len(seats) - window + 1, window):
        marks.append(collision_bits(seats[start:start + window]))
    if not marks:
        return None
    worst = max(range(len(marks)), key=lambda index: marks[index])
    return marks, worst, statistics.fmean(marks), statistics.pstdev(marks)


def main():
    if len(sys.argv) < 2:
        print("usage: noise_detection.py corpus.sym")
        return 1
    path = sys.argv[1]
    if not os.path.isfile(path):
        print("no corpus at %s" % path)
        return 1

    with open(path, "rb") as handle:
        seats = bytearray(handle.read())
    alphabet = sorted(set(seats))

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-9s %-10s %-10s %-10s %-10s\n"
              % ("rate", "H2 spread", "H2 block", "tail spread", "tail block"))

    for rate in RATES:
        scattered = corrupt(seats, rate, alphabet, 0x1E, False)
        blocked = corrupt(seats, rate, alphabet, 0x1E, True)
        out.write("  %-9.4f %-10.3f %-10.3f %-10.3f %-10.3f\n"
                  % (rate, collision_bits(scattered), collision_bits(blocked),
                     tail_ratio(scattered, 0x51F7), tail_ratio(blocked, 0x51F7)))
    # Whether a global figure that moved by nothing can still be placed, window by window
    clean_bits = collision_bits(seats)
    window = 4096
    out.write("\n  localizing one contiguous block, window %d symbols\n" % window)
    out.write("  %-9s %-11s %-11s %-11s %-9s %s\n"
              % ("rate", "global H2", "worst win", "median win", "sigma", "block found"))

    for rate in (0.0, 0.0002, 0.001, 0.005, 0.02):
        spoiled = corrupt(seats, rate, alphabet, 0x1E, True)
        marks, worst, mean, sigma = locate(spoiled, window, clean_bits)
        # Where the block was written, so a claim of having found it can be checked and not asserted
        count = int(len(seats) * rate)
        placed = -1
        for index in range(len(marks)):
            if marks[index] > mean + 4.0 * sigma:
                placed = index
                break
        out.write("  %-9.4f %-11.3f %-11.3f %-11.3f %-9.3f %s\n"
                  % (rate, collision_bits(spoiled), marks[worst],
                     statistics.median(marks), sigma,
                     "no" if count == 0 else ("window %d" % placed if placed >= 0 else "not above 4 sigma")))

    # How far the same operation recurses. The contrast should not depend on the window, since a window
    # inside the block is entirely corrupt whatever its size, but the estimate is taken from the window's
    # own symbols and an alphabet cannot be estimated from fewer draws than it has letters
    spoiled = corrupt(seats, 0.005, alphabet, 0x1E, True)
    out.write("\n  the same sieve at every window, one block at 0.005, alphabet %d\n" % len(alphabet))
    out.write("  %-9s %-11s %-11s %-9s %-11s %-11s %s\n"
              % ("window", "worst win", "median win", "sigma", "separation", "loss", "loss ratio"))

    # Printed to five places because the quantity of interest is the difference between successive rows,
    # and a difference of two numbers rounded to one place carries more error than the difference does
    span = 8192
    ladder = []
    while span >= 16:
        found = locate(spoiled, span, clean_bits)
        if found is not None:
            marks, worst, mean, sigma = found
            median = statistics.median(marks)
            apart = (marks[worst] - median) / sigma if sigma > 0.0 else float("inf")
            ladder.append((span, marks[worst], median, sigma, apart))
        span //= 2

    for index, row in enumerate(ladder):
        loss = "" if index == 0 else "%.5f" % (ladder[index - 1][4] - row[4])
        ratio = ""
        if index >= 2:
            before = ladder[index - 2][4] - ladder[index - 1][4]
            now = ladder[index - 1][4] - row[4]
            if abs(before) > 1e-9:
                ratio = "%.4f" % (now / before)
        out.write("  %-9d %-11.5f %-11.5f %-9.5f %-11.5f %-11s %s\n"
                  % (row[0], row[1], row[2], row[3], row[4], loss, ratio))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
