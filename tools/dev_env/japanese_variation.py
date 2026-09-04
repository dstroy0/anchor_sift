#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Repeat outside Indo-European the one decomposition that was only done inside it, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/japanese_variation.py
#
# What separates two German books came out at 11 percent for the author, 1 percent for the century and 88
# percent for the book itself, over 1244 texts. That is a strong result and it describes Germanic prose,
# which is one branch of one family, and it was written down as though it described writing.
#
# Japanese is the corpus that can carry the same question from outside. It is not Indo-European, it writes
# with three systems at once, it marks no word boundaries, and its pitch accent never reaches the page at
# all. If the shares come back near the German ones, the decomposition is about writing. If they do not,
# it was about Germanic and the earlier entry needs the qualification it already carries made stronger.
#
# One difference is expected and is worth naming before the numbers arrive. How much Chinese-derived
# character a Japanese writer uses against how much syllabary is a choice, of register and of period and
# of the writer, with no Germanic equivalent. So the author share should come out higher here, and if it
# does, that is a fact about Japanese writing and not a correction to the German figure.

import io
import os
import statistics
import sys
import unicodedata

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 30000
RANKS = 64


def script_mix(text):
    """How the three writings are shared out, which is a choice a Japanese writer makes."""
    kinds = {"CJK": 0, "HIRAGANA": 0, "KATAKANA": 0}
    total = 0
    for symbol in text:
        try:
            name = unicodedata.name(symbol)
        except ValueError:
            continue
        for kind in kinds:
            if name.startswith(kind):
                kinds[kind] += 1
                total += 1
                break
    if total < 100:
        return None
    return numpy.asarray([kinds[kind] / float(total) for kind in ("CJK", "HIRAGANA", "KATAKANA")],
                         dtype=numpy.float64)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("jp_") and name.endswith(".txt")):
            continue
        author = name[3:].rsplit("_", 2)[0]
        text, _ = load(os.path.join(CORPORA, name), cap=SAME_LENGTH * 3, clean=False)
        if (text is None) or (len(text) < SAME_LENGTH):
            continue
        cut = text[:SAME_LENGTH]
        square = web(cut, RANKS)
        mix = script_mix(cut)
        if (square is not None) and (mix is not None):
            rows.append((author, square, mix))

    authors = sorted({row[0] for row in rows})
    repeated = [author for author in authors if sum(1 for row in rows if row[0] == author) >= 2]
    out.write("  %d works by %d writers, %d of them with more than one work here\n"
              % (len(rows), len(authors), len(repeated)))
    out.write("  each cut to %d characters\n" % SAME_LENGTH)

    if len(repeated) < 4:
        out.write("\n  too few writers with more than one work\n")
        out.flush()
        return 0

    for label, place in (("which character follows which", 1), ("how the three writings are mixed", 2)):
        same = []
        different = []
        for index, one in enumerate(rows):
            for two in rows[index + 1:]:
                distance = float(numpy.linalg.norm(one[place] - two[place]))
                if one[0] == two[0]:
                    same.append(distance)
                else:
                    different.append(distance)
        if (len(same) < 10) or (len(different) < 10):
            continue
        inside = statistics.fmean(same)
        outside = statistics.fmean(different)
        out.write("\n  %s\n" % label)
        out.write("    two works by one writer     %.4f over %d pairs\n" % (inside, len(same)))
        out.write("    two works by two writers    %.4f over %d pairs\n" % (outside, len(different)))
        out.write("    the writer accounts for %.0f percent of the distance\n"
                  % (100.0 * (outside - inside) / outside))
        out.write("    what remains is             %.0f percent\n" % (100.0 * inside / outside))

    out.write("\n  the German corpus gave the writer 11 percent and the rest 88\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
