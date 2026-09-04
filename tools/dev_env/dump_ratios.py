#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Dump the per symbol ratios this work is built on, for the heavy tail posit in
# docs/research/anchor-sift-ledger.md.
#
#   Usage:  python tools/dev_env/dump_ratios.py corpus.sym [more.sym ...]
#
# The posit says the quantities here are heavy tailed as a rule, and it came from two derived figures: a
# loss ratio whose Jarque-Bera reached 800 against a one percent point of 9.21, and a product rule error
# where one draw in twenty five carried 96% of a mean. Both were built on top of the core measure and
# neither is the core measure.
#
# What matters is whether the underlying per symbol ratio is heavy tailed as well. If it is, every mean
# and deviation quoted in this work needs checking. If it is not, the posit is narrow and applies only to
# the quantities derived from it. The values are written out so a tool carrying proper tests can decide.

import math
import os
import statistics
import sys

MIN_OCCURRENCES = 32


def dispersion(seats):
    seen = {}
    for index, value in enumerate(seats):
        seen.setdefault(value, []).append(index)
    out = {}
    for value, spots in seen.items():
        if len(spots) < MIN_OCCURRENCES:
            continue
        gaps = [spots[step] - spots[step - 1] for step in range(1, len(spots))]
        mean = statistics.fmean(gaps)
        if mean > 0.0:
            out[value] = statistics.pstdev(gaps) / mean
    return out


def main():
    if len(sys.argv) < 2:
        print("usage: dump_ratios.py corpus.sym [more.sym ...]")
        return 1

    import random

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    target = os.path.join(root, "build", "ratios.csv")

    rows = 0
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("corpus,symbol,count,ratio\n")
        for path in sys.argv[1:]:
            if not os.path.isfile(path):
                continue
            with open(path, "rb") as source:
                seats = source.read()
            if len(seats) < 200000:
                continue

            counts = {}
            for value in seats:
                counts[value] = counts.get(value, 0) + 1
            live = dispersion(seats)
            shuffled = bytearray(seats)
            random.Random(0x51F7).shuffle(shuffled)
            dead = dispersion(shuffled)

            name = os.path.basename(path)[:-4]
            for value, spread in live.items():
                if (value not in dead) or (spread <= 0.0):
                    continue
                handle.write("%s,%d,%d,%.6f\n" % (name, value, counts[value], dead[value] / spread))
                rows += 1

    print("  wrote %s with %d rows" % (target, rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
