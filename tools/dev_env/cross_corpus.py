#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether a language reads the same across two different works, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/cross_corpus.py
#
# Every identification measured so far compares texts to other texts of the same kind: four books of a
# language against each other, or four pieces cut from one translation. Pieces of one translation resemble
# each other for reasons that have nothing to do with the language, which is why the 83.1 percent measured
# that way was reported as inflated and not comparable.
#
# Two different works translated into the same languages remove that entirely. A language's reading from
# one work is matched against every language's reading from the other, and the two share no sentence, no
# topic and no translator. Nothing is left to carry a match except the language.
#
# This is the strictest test available here and the one the earlier numbers were standing in for. A
# reading that belongs to a language survives it. A reading that belongs to a book cannot.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from binary_web import squashed
from language_tree import FAMILY
from parallel_web import MORE
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 600000
LEAST = 60000
RANKS = 64


def load(prefix):
    """One reading per language from one work."""
    out = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith(prefix) and name.endswith(".txt")):
            continue
        language = name[len(prefix):-4]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) >= LEAST:
            out[language] = text
    return out


def main():
    io_out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    first = load("para_")
    second = load("para2_")
    shared = sorted(set(first) & set(second))
    if len(shared) < 8:
        io_out.write("  only %d languages are in both works\n" % len(shared))
        io_out.flush()
        return 0

    families = dict(FAMILY)
    families.update(MORE)

    io_out.write("  %d languages appear in both works, so guessing gets %.1f percent\n\n"
                 % (len(shared), 100.0 / len(shared)))
    io_out.write("  %-30s %-16s %s\n" % ("reading", "matched", "share"))

    for label, maker in (("characters by rank, top %d" % RANKS, lambda text: web(text, RANKS)),
                         ("one binary alphabet, every width", squashed)):
        left = {}
        right = {}
        for language in shared:
            one = maker(first[language])
            two = maker(second[language])
            if (one is not None) and (two is not None):
                left[language] = one
                right[language] = two
        names = sorted(set(left) & set(right))
        if len(names) < 8:
            continue

        correct = 0
        family_hits = 0
        family_scored = 0
        wrong = []
        for language in names:
            marks = sorted((float(numpy.linalg.norm(left[language] - right[other])), other)
                           for other in names)
            if marks[0][1] == language:
                correct += 1
            else:
                wrong.append((language, marks[0][1]))
            # Where its own reading is not first, whether the one that is comes from its family
            here = families.get(language)
            if (here is not None) and (sum(1 for other in names
                                           if families.get(other) == here) >= 2):
                family_scored += 1
                nearest_other = next(other for _, other in marks if other != language)
                if families.get(nearest_other) == here:
                    family_hits += 1

        io_out.write("  %-30s %-16s %.1f percent\n"
                     % (label, "%d of %d" % (correct, len(names)),
                        100.0 * correct / len(names)))
        io_out.write("      and %d of %d sit nearest their own family, setting themselves aside\n"
                     % (family_hits, family_scored))
        for language, went in wrong[:8]:
            io_out.write("      %-14s matched %-14s which is %s\n"
                         % (language, went, families.get(went, "unknown")))

    io_out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
