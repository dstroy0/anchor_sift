#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find how few symbols a language relationship survives on, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/minimum_alphabet.py
#
# Removing c, x and q from every language changed the closest pairing measured here by 0.0002, so the
# reading is not resting on any particular letter. That invites the opposite question: how much of a
# writing system can be taken away before a relationship stops being visible at all.
#
# The alphabet is cut down by keeping the commonest few symbols of each text and folding everything else
# into one, which is a coarsening and not a deletion: the positions stay, the text stays its own length,
# and only the number of distinctions falls. Swept from thirty two down to two, where two is whether a
# character is the commonest one or not.
#
# What is watched at each step is not the distance but whether it still separates. A pair known to be
# close is measured against a pair known not to be, and the level where the close pair stops being the
# closer of the two is where the relationship stops surviving. Distances shrink as symbols are removed for
# arithmetic reasons alone, so the raw numbers say nothing on their own and the ordering says everything.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 500000
LEVELS = (32, 24, 16, 12, 8, 6, 4, 3, 2)

HELD = (
    ("zulu", "afr_zulu.txt"),
    ("xhosa", "afr_xhosa.txt"),
    ("shona", "afr_shona.txt"),
    ("somali", "afr_somali.txt"),
    ("spanish", "para_spanish.txt"),
    ("french", "para_french.txt"),
    ("german", "para_german.txt"),
    ("finnish", "para_finnish.txt"),
)

# Pairs known to be close, and pairs known not to be, so the question is which stays closer
CLOSE = (("zulu", "xhosa"), ("spanish", "french"))
FAR = (("zulu", "somali"), ("spanish", "finnish"))


def coarsen(text, keep):
    """The text with only its commonest symbols told apart and everything else made one."""
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ordered = sorted(counts, key=lambda symbol: -counts[symbol])[:keep - 1]
    seat = {symbol: chr(0xE000 + place) for place, symbol in enumerate(ordered)}
    lump = chr(0xE000 + keep)
    return "".join(seat.get(symbol, lump) for symbol in text)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    held = {}
    for label, name in HELD:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            continue
        text, _ = load(path, cap=SAME_LENGTH * 2, clean=False)
        if text and (len(text) >= SAME_LENGTH // 2):
            held[label] = text[:SAME_LENGTH]

    if len(held) < 6:
        out.write("  only %d languages held\n" % len(held))
        out.flush()
        return 0

    out.write("  distances shrink as symbols are folded together, so what matters is whether\n")
    out.write("  the close pair is still closer than the far pair at each level\n\n")
    out.write("  %-8s %-15s %-15s %-15s %-15s %s\n"
              % ("symbols", "zulu, xhosa", "zulu, somali", "spanish, french",
                 "spanish, finnish", "both still hold"))

    for keep in LEVELS:
        cut = {label: coarsen(text, keep) for label, text in held.items()}
        ranks = min(keep, 64)
        reading = {}
        for label, text in cut.items():
            values = web(text, ranks)
            if values is not None:
                reading[label] = values

        def apart(one, two):
            if (one not in reading) or (two not in reading):
                return None
            return float(numpy.linalg.norm(reading[one] - reading[two]))

        marks = []
        for pair in CLOSE + FAR:
            marks.append(apart(*pair))
        if any(mark is None for mark in marks):
            continue
        upheld = (marks[0] < marks[2]) and (marks[1] < marks[3])
        out.write("  %-8d %-15.5f %-15.5f %-15.5f %-15.5f %s\n"
                  % (keep, marks[0], marks[2], marks[1], marks[3],
                     "yes" if upheld else "no"))

    out.write("\n  the lowest level where both still hold is the fewest symbols a relationship\n")
    out.write("  of this kind survives on\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
