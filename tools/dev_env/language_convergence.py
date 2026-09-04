#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether languages converge once their numbering is taken away, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/language_convergence.py
#
# Four languages under the tightest numbering landed between 4.76 and 7.84 where they had spanned 15.61 to
# 31.44 as the files carried them, and Greek with 141 symbols sat on the same value as German with 73.
# Four is not enough to say anything and all four write in the same alphabet, so a single writing system
# measured four times would look exactly like that.
#
# Everything here works on characters and not on bytes. A Chinese novel carries thousands of distinct
# characters, which no byte seating holds, and character width is also where its symbols are morphemes
# instead of pieces of one. The earlier tools assumed eight bits throughout and could not have included it.
#
# Chinese is the case that decides this. If the tightest spread is set by how many symbols an alphabet
# has, it must sit far outside every alphabetic language. If it is set only by how the weight falls across
# whatever symbols there are, it can sit inside the same band. The prediction is not obvious either way
# and both outcomes are worth having, so it is measured and not argued.

import io
import math
import os
import statistics
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(ROOT, "build", "language_convergence.csv")

CAP = 200000
LEAST = 80000
BITS = 3


def seat_tightest(symbols):
    """Number the symbols so their spread is the least any numbering gives.

    The spread weights each position by how often it is used, so the commonest symbol takes the middle
    and the rest go outward by frequency. This is the value the coefficient converges to and it is
    reached, not approached.
    """
    order = {}
    for symbol in symbols:
        order[symbol] = order.get(symbol, 0) + 1
    ranked = sorted(order, key=lambda symbol: -order[symbol])

    middle = len(ranked) // 2
    places = [middle]
    for step in range(1, len(ranked)):
        if (middle + step) < len(ranked):
            places.append(middle + step)
        if (middle - step) >= 0:
            places.append(middle - step)

    seating = {}
    for symbol, place in zip(ranked, places[:len(ranked)]):
        seating[symbol] = place
    return numpy.asarray([seating[symbol] for symbol in symbols], dtype=numpy.int64), len(ranked)


def returned(series, bits):
    """Share of symbols coming back exactly when every angle is held to a few steps.

    Held in symbol positions and not in bytes, so an alphabet of three thousand is treated the same way
    as one of seventy.
    """
    floats = series.astype(numpy.float64)
    middle = floats.mean()
    spectrum = numpy.fft.rfft(floats - middle)
    steps = 1 << bits
    angles = numpy.angle(spectrum)
    rounded = numpy.round(angles / (2.0 * numpy.pi) * steps) * (2.0 * numpy.pi / steps)
    rebuilt = numpy.fft.irfft(numpy.exp(1j * rounded) * numpy.abs(spectrum), n=len(floats)) + middle
    landed = numpy.rint(rebuilt).astype(numpy.int64)
    return float((landed == series).mean())


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    gathered = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("lang_") and name.endswith(".txt")):
            continue
        language = name[5:].rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        # Line endings folded, as everywhere here, so a publisher's wrapping is not measured
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue

        seated, distinct = seat_tightest(text)
        counts = numpy.bincount(seated).astype(numpy.float64)
        shares = counts[counts > 0] / counts.sum()
        effective = 1.0 / float((shares * shares).sum())
        spread = float(seated.astype(numpy.float64).std())
        # As a share of the positions the alphabet occupies, since there is no fixed width to quote a
        # spread in levels against. An alphabet of 3150 needs about 11.6 bits and one of 90 needs 6.5, so
        # the same number of levels means different things in the two and only the fraction compares.
        gathered.append((language, name[:-4], distinct, effective, spread,
                         spread / float(distinct), returned(seated, BITS)))

    if not gathered:
        out.write("  no language corpora long enough were found\n")
        out.flush()
        return 0

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("language,text,symbols,effective,spread,share,returned\n")
        for row in gathered:
            handle.write("%s,%s,%d,%.4f,%.4f,%.6f,%.6f\n" % row)

    out.write("  %-14s %-7s %-9s %-11s %-11s %-15s %s\n"
              % ("language", "texts", "symbols", "effective", "in levels", "of the range",
                 "returned"))
    summary = []
    for language in sorted({row[0] for row in gathered}):
        rows = [row for row in gathered if row[0] == language]
        shares = [row[5] for row in rows]
        summary.append((language, len(rows), statistics.fmean(shares),
                        statistics.fmean(row[6] for row in rows)))
        out.write("  %-14s %-7d %-9d %-11.1f %-11.2f %-15s %.3f\n"
                  % (language, len(rows), int(statistics.fmean(row[2] for row in rows)),
                     statistics.fmean(row[3] for row in rows),
                     statistics.fmean(row[4] for row in rows),
                     "%.4f, %.4f" % (statistics.fmean(shares),
                                     statistics.pstdev(shares) if len(shares) > 1 else 0.0),
                     statistics.fmean(row[6] for row in rows)))

    # Convergence is a variance question: if a language has a value of its own, the spread inside one
    # language is small against the spread between them, and if they converge the between falls toward
    # the within instead
    alphabetic = [row for row in summary if row[0] != "chinese"]
    if len(alphabetic) >= 4:
        for label, column in (("in levels", 4), ("as a share of the range", 5)):
            inside = statistics.fmean(
                statistics.pstdev([row[column] for row in gathered if row[0] == language])
                for language, count, _, _ in alphabetic if count > 1)
            middles = [statistics.fmean([row[column] for row in gathered if row[0] == language])
                       for language, _, _, _ in alphabetic]
            between = statistics.pstdev(middles)
            out.write("\n  %s, over %d languages other than Chinese\n" % (label, len(alphabetic)))
            out.write("    within a language %.4f, between languages %.4f, ratio %.2f\n"
                      % (inside, between, (between / inside) if inside > 0 else float("nan")))
            out.write("    they run %.4f to %.4f\n" % (min(middles), max(middles)))

            chinese = [row[column] for row in gathered if row[0] == "chinese"]
            if chinese and (inside > 0):
                middle = statistics.fmean(middles)
                out.write("    chinese at %.4f, %.1f within-language deviations out\n"
                          % (statistics.fmean(chinese),
                             abs(statistics.fmean(chinese) - middle) / inside))

    out.write("\n  wrote %s with %d texts\n" % (TARGET, len(gathered)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
