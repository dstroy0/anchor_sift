#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Compare languages at the unit that carries meaning, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/morpheme_convergence.py
#
# Taken as a share of the positions its alphabet occupies, the tightest spread runs 0.0610 to 0.0736 over
# eleven languages written in an alphabet, and Chinese sits at 0.0855, which is 5.6 deviations outside
# them. Quoting it in levels instead put Chinese 565.9 deviations out, so the normalizing was most of the
# distance and something smaller is left.
#
# What is left is that the comparison is between unlike units. A Chinese character stands for a morpheme.
# A Latin letter stands for a piece of one, and it takes several to reach anything that means something.
# Measuring one symbol on each side measures meaning on one and fragments on the other, and two languages
# could agree perfectly about how their meaning is distributed while disagreeing here.
#
# So the alphabetic languages are read at word width, which is the closest unit to a morpheme that can be
# taken without a dictionary for each language, and Chinese stays at character width where its symbols
# already are morphemes. Neither is exactly a morpheme: an inflected word carries several and a Chinese
# word often runs to two characters. That error is stated and not corrected, since correcting it needs a
# morphological analyzer per language and the point here is whether moving to the right order of unit
# closes a gap that character width could not.

import io
import os
import re
import statistics
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(ROOT, "build", "morpheme_convergence.csv")

CAP = 400000
LEAST = 120000
BY_CHARACTER = ("chinese", "japanese")
WORD = re.compile(r"\w+", re.UNICODE)


def seat_tightest(units):
    """Number the units so their spread is the least any numbering gives."""
    counts = {}
    for unit in units:
        counts[unit] = counts.get(unit, 0) + 1
    ranked = sorted(counts, key=lambda unit: -counts[unit])

    middle = len(ranked) // 2
    places = [middle]
    for step in range(1, len(ranked)):
        if (middle + step) < len(ranked):
            places.append(middle + step)
        if (middle - step) >= 0:
            places.append(middle - step)

    seating = {}
    for unit, place in zip(ranked, places[:len(ranked)]):
        seating[unit] = place
    return numpy.asarray([seating[unit] for unit in units], dtype=numpy.int64), len(ranked)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    gathered = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("lang_") and name.endswith(".txt")):
            continue
        language = name[5:].rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue

        if language in BY_CHARACTER:
            units = [character for character in text if character.strip()]
        else:
            units = WORD.findall(text.lower())
        if len(units) < 8000:
            continue

        seated, distinct = seat_tightest(units)
        spread = float(seated.astype(numpy.float64).std())
        gathered.append((language, name[:-4], len(units), distinct, spread,
                         spread / float(distinct)))

    if not gathered:
        out.write("  nothing long enough was found\n")
        out.flush()
        return 0

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("language,text,units,distinct,spread,share\n")
        for row in gathered:
            handle.write("%s,%s,%d,%d,%.4f,%.8f\n" % row)

    out.write("  %-14s %-7s %-10s %-10s %-11s %s\n"
              % ("language", "texts", "units", "distinct", "in levels", "of the range"))
    middles = {}
    for language in sorted({row[0] for row in gathered}):
        rows = [row for row in gathered if row[0] == language]
        shares = [row[5] for row in rows]
        middles[language] = statistics.fmean(shares)
        out.write("  %-14s %-7d %-10d %-10d %-11.1f %.4f, %.4f\n"
                  % (language, len(rows), int(statistics.fmean(row[2] for row in rows)),
                     int(statistics.fmean(row[3] for row in rows)),
                     statistics.fmean(row[4] for row in rows),
                     statistics.fmean(shares),
                     statistics.pstdev(shares) if len(shares) > 1 else 0.0))

    apart = [language for language in middles if language in BY_CHARACTER]
    rest = [language for language in middles if language not in BY_CHARACTER]
    if len(rest) >= 4:
        inside = statistics.fmean(
            statistics.pstdev([row[5] for row in gathered if row[0] == language])
            for language in rest if len([row for row in gathered if row[0] == language]) > 1)
        between = statistics.pstdev([middles[language] for language in rest])
        out.write("\n  over %d languages read at word width\n" % len(rest))
        out.write("    within a language %.5f, between languages %.5f, ratio %.2f\n"
                  % (inside, between, (between / inside) if inside > 0 else float("nan")))
        out.write("    they run %.4f to %.4f\n"
                  % (min(middles[language] for language in rest),
                     max(middles[language] for language in rest)))
        middle = statistics.fmean([middles[language] for language in rest])
        for language in apart:
            out.write("    %s read at character width sits at %.4f, %.1f deviations out\n"
                      % (language, middles[language],
                         abs(middles[language] - middle) / inside if inside > 0 else 0.0))

    out.write("\n  wrote %s with %d texts\n" % (TARGET, len(gathered)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
