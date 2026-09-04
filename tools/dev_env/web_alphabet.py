#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether a language is identified by which symbol follows which, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/web_alphabet.py
#
# Four separate scalars were tested for whether they pick a language out of 28 and the best of them
# reached 24.5 percent against 3.6 for guessing. That was the wrong shape of thing to test. A scalar
# summarizes the alphabet and throws away the context, and the context of a language is which symbol
# follows which, which is a square of numbers over the alphabet and not one number.
#
# So the quantity here is that square. Each text gives the share of the time symbol i is followed by
# symbol j, and two texts are compared by the distance between their squares. Alphabets differ between
# languages, so positions are taken by frequency rank: the first position is whatever symbol that text
# uses most, the second the next, and so on down to a fixed count. That makes a Greek square and a
# Japanese square comparable without either being translated into the other.
#
# The test is the one the scalars failed. Each text is held out, every language is described by the texts
# that remain, and the held out text goes to the nearest. If which symbol follows which is what carries a
# language, its own texts come home and the scalars were measuring a shadow of it.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 200000
LEAST = 80000
RANKS = (8, 16, 32, 64)

# A Greek to English lexicon of the New Testament, which is 21.2 percent Greek letters and 78.8 percent
# Latin ones. It is one of four Greek texts and has been standing in every Greek reading in this work.
# Excluded by name and not deleted, so what it was and why it is gone stays on the record.
SKIP = ("lang_greek_40935",)


def web(text, ranks):
    """Share of the time the symbol at one rank is followed by the symbol at another.

    Positions are frequency ranks and not code points, so the same position means the same thing in every
    language: whatever that text uses most sits first. Anything past the rank cutoff is dropped, which
    keeps a language with thousands of symbols comparable to one with eighty.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ordered = sorted(counts, key=lambda symbol: -counts[symbol])[:ranks]
    seat = {symbol: place for place, symbol in enumerate(ordered)}

    grid = numpy.zeros((ranks, ranks), dtype=numpy.float64)
    previous = None
    for symbol in text:
        place = seat.get(symbol)
        if (place is not None) and (previous is not None):
            grid[previous, place] += 1.0
        previous = place
    total = grid.sum()
    if total <= 0.0:
        return None
    # Held as shares of the whole square, so a longer text does not read as a different language
    return (grid / total).reshape(-1)


def leave_one_out(rows):
    """Assign each text to the language whose remaining texts it lands nearest."""
    languages = sorted({row[0] for row in rows})
    correct = 0
    confused = {}
    for index, (language, _, values) in enumerate(rows):
        best = None
        picked = None
        for other in languages:
            kept = [row[2] for position, row in enumerate(rows)
                    if row[0] == other and position != index]
            if not kept:
                continue
            middle = numpy.mean(numpy.stack(kept), axis=0)
            distance = float(numpy.linalg.norm(values - middle))
            if (best is None) or (distance < best):
                best = distance
                picked = other
        if picked is None:
            continue
        correct += 1 if picked == language else 0
        if picked != language:
            confused[(language, picked)] = confused.get((language, picked), 0) + 1
    return correct, len(rows), confused


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    loaded = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("lang_") and name.endswith(".txt")):
            continue
        if name[:-4] in SKIP:
            continue
        language = name[5:].rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue
        loaded.append((language, name[:-4], text))

    if len(loaded) < 8:
        out.write("  too few texts\n")
        out.flush()
        return 0

    languages = sorted({row[0] for row in loaded})
    out.write("  %d texts over %d languages, so guessing gets %.1f percent\n\n"
              % (len(loaded), len(languages), 100.0 / len(languages)))
    out.write("  %-22s %-14s %s\n" % ("ranks kept", "correct", "share"))

    last = None
    for ranks in RANKS:
        rows = []
        for language, label, text in loaded:
            values = web(text, ranks)
            if values is not None:
                rows.append((language, label, values))
        if len(rows) < 8:
            continue
        correct, total, confused = leave_one_out(rows)
        out.write("  %-22s %-14s %.1f percent\n"
                  % ("the top %d symbols" % ranks, "%d of %d" % (correct, total),
                     100.0 * correct / total))
        last = confused

    if last:
        out.write("\n  where a text still goes wrong, at the widest square\n")
        for (was, went), count in sorted(last.items(), key=lambda pair: -pair[1])[:8]:
            out.write("    %-14s taken for %-14s %d\n" % (was, went, count))
    else:
        out.write("\n  no text was placed in the wrong language at the widest square\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
