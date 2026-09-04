#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure how far a text's dependencies reach, without counting blocks, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/match_length_rate.py
#
# Counting blocks cannot see past order 4 here. The possible blocks grow as the alphabet raised to the
# order while a text grows in a line, so at order 5 most blocks have been seen once or never and the
# reading is measuring its own sample size. That was established by comparing against a shuffled text,
# whose block entropy is known by arithmetic: the error follows the undersampling curve exactly through
# order 4 and leaves it together, for all eight texts, from order 5.
#
# Matching does not have that wall. At each position, the shortest string starting there that has not
# already appeared in the window behind it is found, and a long match means the window held something
# that predicts what comes next. A dependency of any length shows up as a long match without any block
# ever being counted, so nothing has to be seen many times for the reading to work.
#
# The window is swept and not chosen. A rate that keeps falling as the window grows means the text still
# holds something at that distance, and a rate that settles means it does not. That is the same question
# the block reading could not reach, asked where the arithmetic allows an answer, and the sweep is what
# turns the choice of window from an assumption into the result.
#
# The shuffle is carried through as the floor. It holds nothing beyond one symbol, so its rate must not
# fall as the window grows, and any fall in it is the reading and not the text.

import io
import math
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 4000000
LEAST = 400000
WINDOWS = (1024, 4096, 16384, 65536, 262144)
SAMPLES = 4000
LONGEST = 400
SEED = 0x51F7

WANTED = (
    ("vietnamese", "para_vietnamese.txt"),
    ("arabic, the original", "source_arabic.txt"),
    ("urdu", "para_urdu.txt"),
    ("russian", "para2_russian.txt"),
    ("turkish", "para2_turkish.txt"),
    ("indonesian", "para_indonesian.txt"),
)


def rate(text, window, rng):
    """Entropy per symbol, from how long a string has to be before the window has not seen it.

    At each position the shortest string starting there that does not appear in the preceding window is
    found by doubling and then bisecting, since a text's matches are short and a scan from one upward
    would spend all its time on the common case.
    """
    if len(text) < (window * 2):
        return None
    starts = rng.integers(window, len(text) - LONGEST, size=SAMPLES)
    lengths = []
    for start in starts:
        start = int(start)
        behind = text[start - window:start]

        # Doubling to bracket the first length the window has not seen, then bisecting inside it
        low = 0
        high = 1
        while (high < LONGEST) and (text[start:start + high] in behind):
            low = high
            high *= 2
        high = min(high, LONGEST)
        while low + 1 < high:
            middle = (low + high) // 2
            if text[start:start + middle] in behind:
                low = middle
            else:
                high = middle
        lengths.append(low + 1)

    average = float(numpy.mean(lengths))
    return (math.log2(window) / average) if average > 0 else None


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  bits per symbol, as the window behind each position grows\n\n")
    header = "  ".join("%9s" % ("w %d" % window) for window in WINDOWS)
    out.write("  %-22s %-9s %s\n" % ("text", "kind", header))

    for label, name in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-22s not present\n" % label)
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue

        scattered = list(text)
        numpy.random.default_rng(SEED).shuffle(scattered)
        scattered = "".join(scattered)

        for kind, series in (("as written", text), ("shuffled", scattered)):
            rng = numpy.random.default_rng(SEED)
            row = []
            for window in WINDOWS:
                value = rate(series, window, rng)
                row.append("%9.4f" % value if value is not None else "%9s" % "short")
            out.write("  %-22s %-9s %s\n" % (label if kind == "as written" else "", kind,
                                             "  ".join(row)))
        out.flush()

    out.write("\n  a rate still falling at the widest window means the text still holds\n")
    out.write("  something at that distance; the shuffled rows must not fall at all\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
