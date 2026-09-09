#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Give the reading more of the language to work with, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python examples/language/4_measure/deeper_web.py
#
# One language read from two unrelated places sits 0.0867 apart and two languages read from the same place
# sit 0.0936 apart, so where a text came from carries nearly as much as what language it is in. That was
# recorded as a fact about languages and it is a fact about the reading.
#
# What the reading holds is which of the commonest 64 characters follows which, and that is 4096 numbers
# standing in for a whole language. Everything else is discarded: every dependency longer than one
# character, the entire tail of the alphabet past rank 64, where a character sits inside a word, and all
# word and morpheme structure. A margin of seven percent is what is left after that. It is not what
# a language is worth.
#
# So the reading is extended in the one direction that recovers dependencies instead of resolution. Pairs
# see one character back, triples see two, quadruples see three, and a language's habits live at those
# lengths: the letters that may follow each other, the endings it inflects with, the clusters it forbids.
# The alphabet is narrowed as the order grows so the count of numbers stays manageable, which trades
# breadth for depth deliberately, and it is stated here because it is a choice.
#
# The test is the same one that produced the seven percent, run again unchanged. If the margin widens, the
# reading was destroying the language. If it does not, the language really is only marginally there.

import io
import os
import statistics
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.web import deep_web, web  # noqa: E402
from representation.text.corpus import SOURCES, load_by_source  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 200000
LEAST = 70000
RANKS = 64

# Order of the reading and how many ranks it keeps. The alphabet narrows as the order grows because the
# count of cells is the ranks raised to the order, and 64 characters at order four is sixteen million.
ORDERS = ((1, 96), (2, 48), (3, 20), (4, 11), (5, 8), (6, 6), (7, 5))


def load(maker):
    """One reading per language per source, averaged where a source holds several texts."""
    gathered = {}
    for key, texts in load_by_source(CORPORA, cap=CAP, least=LEAST).items():
        rows = [values for values in (maker(text) for text in texts) if values is not None]
        if rows:
            gathered[key] = numpy.mean(numpy.stack(rows), axis=0)
    return gathered


def judge(gathered, out, label):
    sources = [source for source, _, _ in SOURCES]
    counts = {}
    for source, language in gathered:
        counts.setdefault(language, []).append(source)
    several = sorted(language for language, held in counts.items() if len(held) >= 2)
    if len(several) < 5:
        return

    same_language = []
    for language in several:
        held = [gathered[(source, language)] for source in sources
                if (source, language) in gathered]
        for index, one in enumerate(held):
            for two in held[index + 1:]:
                same_language.append(float(numpy.linalg.norm(one - two)))

    same_source = []
    for source in sources:
        here = [gathered[(source, language)] for language in several
                if (source, language) in gathered]
        for index, one in enumerate(here):
            for two in here[index + 1:]:
                same_source.append(float(numpy.linalg.norm(one - two)))

    correct = 0
    total = 0
    for source, language in sorted(gathered):
        if language not in several:
            continue
        others = [key for key in gathered if key[0] != source]
        if not others:
            continue
        total += 1
        nearest = min(others, key=lambda key: float(
            numpy.linalg.norm(gathered[(source, language)] - gathered[key])))
        correct += 1 if nearest[1] == language else 0

    one = statistics.fmean(same_language)
    two = statistics.fmean(same_source)
    out.write("  %-26s %-11.4f %-11.4f %-9.3f %d of %d\n"
              % (label, one, two, one / two, correct, total))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-11s %-11s %-9s %s\n"
              % ("reading", "one lang", "one source", "ratio", "matched"))
    out.write("  %-26s %-11s %-11s %-9s %s\n"
              % ("", "two places", "two langs", "lower wins", "own language"))

    judge(load(lambda text: web(text, RANKS)), out, "pairs of 64, as before")

    # Swept instead of stopped, so where the reading stops improving is measured and not chosen
    for depth in range(2, len(ORDERS) + 1):
        orders = ORDERS[:depth]
        judge(load(lambda text, orders=orders: deep_web(text, orders)), out,
              "runs of one to %d" % orders[-1][0])

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
