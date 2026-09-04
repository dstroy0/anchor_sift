#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure several texts per language at character width, to test whether a language carries a constant,
# for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/language_constant.py
#
# The claim is that every language has an idiom of its own and that the idiom is constant. It predicts
# that two texts in one language agree more closely with each other than either does with a text in
# another, so the test is whether the spread within a language is smaller than the spread between them.
#
# Everything here works on codepoints and not on bytes. A Chinese novel carries thousands of distinct
# characters, which no byte seating holds, and character width is also where its symbols are morphemes
# instead of parts of one. Measuring at that width is the only way the logographic case is comparable to
# the alphabetic ones at all.

import collections
import io
import math
import os
import random
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
MIN_OCCURRENCES = 32


def dispersion(symbols):
    seen = {}
    for index, value in enumerate(symbols):
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


def measure(text):
    """Collision entropy, the commonest symbol's share, and the rare half against a permutation null."""
    symbols = list(text)
    counts = collections.Counter(symbols)
    total = float(len(symbols))
    collision = sum((count / total) ** 2 for count in counts.values())
    bits = -math.log2(collision)
    top = max(counts.values()) / total

    live = dispersion(symbols)
    shuffled = list(symbols)
    random.Random(0x51F7).shuffle(shuffled)
    dead = dispersion(shuffled)

    rows = []
    for value, spread in live.items():
        if (value in dead) and (spread > 0.0):
            rows.append((counts[value], dead[value] / spread))
    if len(rows) < 8:
        return None
    rows.sort(reverse=True)
    tail = statistics.fmean(row[1] for row in rows[len(rows) // 2:])
    return bits, 1.0 / top, tail, len(counts)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    target = os.path.join(ROOT, "build", "language_constant.csv")

    gathered = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("lang_") and name.endswith(".txt")):
            continue
        language = name[5:].rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            # Line endings folded, as everywhere here, so a publisher's wrapping is not measured
            text = handle.read().replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < 80000:
            continue
        found = measure(text)
        if found is None:
            continue
        bits, gap, tail, distinct = found
        gathered.append((language, name[:-4], bits, gap, tail, distinct))

    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("language,text,h2,gap,tail,distinct\n")
        for row in gathered:
            handle.write("%s,%s,%.6f,%.6f,%.6f,%d\n" % row)

    out.write("  %-11s %-6s %-16s %-16s %-16s %s\n"
              % ("language", "texts", "H2 mean, sd", "gap mean, sd", "tail mean, sd", "symbols"))
    for language in sorted({row[0] for row in gathered}):
        rows = [row for row in gathered if row[0] == language]
        if len(rows) < 2:
            continue
        out.write("  %-11s %-6d %-16s %-16s %-16s %d\n"
                  % (language, len(rows),
                     "%.3f, %.3f" % (statistics.fmean(r[2] for r in rows),
                                     statistics.pstdev(r[2] for r in rows)),
                     "%.3f, %.3f" % (statistics.fmean(r[3] for r in rows),
                                     statistics.pstdev(r[3] for r in rows)),
                     "%.3f, %.3f" % (statistics.fmean(r[4] for r in rows),
                                     statistics.pstdev(r[4] for r in rows)),
                     int(statistics.fmean(r[5] for r in rows))))

    out.write("\n  wrote %s with %d rows\n" % (target, len(gathered)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
