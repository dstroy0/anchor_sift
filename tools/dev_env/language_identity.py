#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether a language's coefficient identifies it, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/language_identity.py
#
# The spread between languages is 1.36 times the spread inside one, which says a language keeps a value of
# its own and says nothing about whether that value picks it out from every other language. Those are
# different claims and the second is the stronger one.
#
# It is also the one with a pass and a fail. Each text is held out in turn, the remaining texts of every
# language give that language a value, and the held out text is assigned to whichever language it lands
# nearest. If a language carries a constant that identifies it, its own texts come home. Guessing gets one
# in however many languages are present.
#
# One number is tested first because the claim is about one. Several are then tested together, because a
# language failing to be picked out by one quantity while being picked out by four says the identity is
# there and spread across them, which is a different result and not the same one.

import io
import math
import os
import statistics
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 200000
LEAST = 80000
BITS = 3


def seat_tightest(symbols):
    counts = {}
    for symbol in symbols:
        counts[symbol] = counts.get(symbol, 0) + 1
    ranked = sorted(counts, key=lambda symbol: -counts[symbol])
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


def features(text):
    """The coefficient, and three others measured beside it on the same text."""
    seated, distinct = seat_tightest(text)
    counts = numpy.bincount(seated).astype(numpy.float64)
    shares = counts[counts > 0] / counts.sum()
    collision = float((shares * shares).sum())
    spread = float(seated.astype(numpy.float64).std())

    # Mean distance between one occurrence of a symbol and the next, over the rare half
    places = {}
    for index, value in enumerate(seated):
        places.setdefault(int(value), []).append(index)
    gaps = []
    for value, spots in places.items():
        if len(spots) >= 32:
            steps = numpy.diff(numpy.asarray(spots, dtype=numpy.float64))
            middle = steps.mean()
            if middle > 0:
                gaps.append((len(spots), steps.std() / middle))
    gaps.sort()
    tail = statistics.fmean(value for _, value in gaps[:len(gaps) // 2]) if len(gaps) >= 8 else 0.0

    return numpy.asarray([spread / float(distinct),
                          -math.log2(collision),
                          float(distinct),
                          tail], dtype=numpy.float64)


def leave_one_out(rows, columns):
    """Assign each text to the nearest language mean built without that text."""
    languages = sorted({row[0] for row in rows})
    correct = 0
    confused = {}
    for index, (language, _, values) in enumerate(rows):
        middles = {}
        for other in languages:
            kept = [row[2][columns] for position, row in enumerate(rows)
                    if row[0] == other and position != index]
            if kept:
                middles[other] = numpy.mean(numpy.stack(kept), axis=0)
        if not middles:
            continue
        # Scaled by each column's spread across all texts, so a wide column does not decide alone
        scale = numpy.std(numpy.stack([row[2][columns] for row in rows]), axis=0)
        scale[scale <= 0.0] = 1.0
        picked = min(middles, key=lambda name: float(
            numpy.linalg.norm((values[columns] - middles[name]) / scale)))
        correct += 1 if picked == language else 0
        if picked != language:
            confused[(language, picked)] = confused.get((language, picked), 0) + 1
    return correct, len(rows), confused


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("lang_") and name.endswith(".txt")):
            continue
        language = name[5:].rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue
        rows.append((language, name[:-4], features(text)))

    if len(rows) < 8:
        out.write("  too few texts to test identity\n")
        out.flush()
        return 0

    languages = sorted({row[0] for row in rows})
    out.write("  %d texts over %d languages, so guessing gets %.1f percent\n\n"
              % (len(rows), len(languages), 100.0 / len(languages)))

    trials = (
        ("the coefficient alone", [0]),
        ("collision entropy alone", [1]),
        ("symbol count alone", [2]),
        ("gap spread alone", [3]),
        ("all four together", [0, 1, 2, 3]),
    )
    out.write("  %-26s %-12s %s\n" % ("using", "correct", "share"))
    for label, columns in trials:
        correct, total, confused = leave_one_out(rows, numpy.asarray(columns))
        out.write("  %-26s %-12s %.1f percent\n"
                  % (label, "%d of %d" % (correct, total), 100.0 * correct / total))

    correct, total, confused = leave_one_out(rows, numpy.asarray([0]))
    if confused:
        out.write("\n  where the coefficient alone sends a text, most often\n")
        for (was, went), count in sorted(confused.items(), key=lambda pair: -pair[1])[:8]:
            out.write("    %-14s taken for %-14s %d\n" % (was, went, count))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
