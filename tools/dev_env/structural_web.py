#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Take the frequencies out of the reading and leave what follows what, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/structural_web.py
#
# The reading of which character follows which holds two things at once. There are the frequencies, which
# say how often each character is used and are a property of a script and its conventions before they are
# a property of a language. And there is what follows what given those frequencies, which is the part that
# is about how the language is built.
#
# Every result in this section says the first of those dominates. Two Chinese texts of one language in two
# character sets sit twice as far apart as two in the same set. Tamil and Malayalam, the closest pair in
# their family, sit widest apart of seven because Malayalam took Sanskrit letters into its writing and
# Tamil did not. Seven English writers sharing one alphabet are barely told apart at all.
#
# Dividing the joint counts by the product of the two marginals removes exactly that first part. What is
# left is how far each pair departs from what the frequencies alone would predict, which is zero
# everywhere for a text with no structure beyond its letter counts, and is the structure otherwise.
#
# Written before running, from what the earlier results say the frequencies are carrying: Tamil to
# Malayalam should close up, the two Chinese character sets should close up, Zulu to Xhosa should hold
# since their closeness is not a matter of inventory, and the seven writers should improve if what
# separates them is structural and not.

import io
import math
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

RANKS = 48
SMOOTH = 0.5


def structural(text, ranks=RANKS):
    """What follows what, with the frequencies divided out.

    Each cell is how far that pair departs from what the two frequencies alone would give, in logs, so a
    text whose letters follow one another for no reason reads zero everywhere. The count added to every
    cell keeps a pair never seen from being infinitely surprising, which it is not: it is unobserved.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ordered = sorted(counts, key=lambda symbol: -counts[symbol])[:ranks]
    seat = {symbol: place for place, symbol in enumerate(ordered)}

    grid = numpy.full((ranks, ranks), SMOOTH, dtype=numpy.float64)
    previous = None
    for symbol in text:
        place = seat.get(symbol)
        if (place is not None) and (previous is not None):
            grid[previous, place] += 1.0
        previous = place

    total = grid.sum()
    if total <= 0:
        return None
    joint = grid / total
    down = joint.sum(axis=1, keepdims=True)
    across = joint.sum(axis=0, keepdims=True)
    expected = down @ across
    return numpy.log2(joint / expected).reshape(-1)


def gather(prefix, strip, cap, cut):
    """One reading of each kind for every corpus under a prefix."""
    plain = {}
    built = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith(prefix) and name.endswith(".txt")):
            continue
        label = name[strip:-4]
        text, _ = load(os.path.join(CORPORA, name), cap=cap, clean=False)
        if (text is None) or (len(text) < cut):
            continue
        first = web(text[:cut], RANKS)
        second = structural(text[:cut])
        if (first is not None) and (second is not None):
            plain[label] = first
            built[label] = second
    return plain, built


def compare(out, title, plain, built, pairs):
    """The named distances under both readings, each divided by that reading's own average."""
    def spread(source):
        names = sorted(source)
        marks = [float(numpy.linalg.norm(source[one] - source[two]))
                 for index, one in enumerate(names) for two in names[index + 1:]]
        return float(numpy.mean(marks)) if marks else 1.0

    one_scale = spread(plain)
    two_scale = spread(built)
    out.write("\n  %s\n" % title)
    out.write("    %-30s %-11s %s\n" % ("", "as counts", "frequencies out"))
    for left, right, note in pairs:
        if (left in plain) and (right in plain):
            first = float(numpy.linalg.norm(plain[left] - plain[right])) / one_scale
            second = float(numpy.linalg.norm(built[left] - built[right])) / two_scale
            moved = "closer" if second < first else "further"
            out.write("    %-30s %-11.3f %.3f  %s  %s\n"
                      % ("%s to %s" % (left[:12], right[:12]), first, second, moved, note))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  distances are given against the average distance of their own reading,\n")
    out.write("  since the two readings are not in the same units\n")

    plain, built = gather("drav_", 5, 900000, 300000)
    compare(out, "the family whose scripts diverged", plain, built, (
        ("tamil", "malayalam", "closest pair in the family"),
        ("kannada", "malayalam", "same family, further off"),
        ("tamil", "hindi", "different family"),
    ))

    plain, built = gather("afr_", 4, 1400000, 700000)
    compare(out, "the family whose script is shared", plain, built, (
        ("zulu", "xhosa", "closest pair, and it was found"),
        ("zulu", "shona", "same family, further off"),
        ("zulu", "somali", "different family"),
    ))

    plain, built = gather("sinitic_", 8, 200000, 45000)
    compare(out, "one language in two character sets", plain, built, (
        ("simplified", "traditional", "same language, characters swapped"),
        ("traditional", "hongkong", "same language, same characters"),
    ))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
