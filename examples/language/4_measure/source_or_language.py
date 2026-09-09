#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: LNG-4-038
#
# Decide whether the reading belongs to a language or to where the text came from, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python examples/language/4_measure/source_or_language.py
#
# Several languages are now held from four places that have nothing to do with each other: novels and
# other books, encyclopedia articles, and two separate works translated into many languages. Nothing is
# shared between them, not the subject, not the century, not the translator, not the kind of writing.
#
# That makes the question answerable directly instead of by argument. If the reading belongs to a
# language, the same language read from a novel and from an encyclopedia sits closer together than two
# different languages read from the same place. If it belongs to the source, the encyclopedia articles of
# every language sit together and the novels sit together, and the languages do not separate at all.
#
# Both distances are measured on the same texts and reported side by side. The answer is whichever is
# smaller, and it needs no threshold to read.

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

from measure.web import web  # noqa: E402
from representation.text.corpus import SOURCES, load_by_source  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 200000
LEAST = 70000
RANKS = 64


def load(maker=lambda text: web(text, RANKS)):
    """One reading per language per source, averaged where a source holds several texts."""
    gathered = {}
    for key, texts in load_by_source(CORPORA, cap=CAP, least=LEAST).items():
        rows = [values for values in (maker(text) for text in texts) if values is not None]
        if rows:
            gathered[key] = numpy.mean(numpy.stack(rows), axis=0)
    return gathered


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    gathered = load()
    sources = [source for source, _, _ in SOURCES]

    counts = {}
    for source, language in gathered:
        counts.setdefault(language, []).append(source)
    several = sorted(language for language, held in counts.items() if len(held) >= 2)
    if len(several) < 5:
        out.write("  only %d languages are held from more than one place\n" % len(several))
        out.flush()
        return 0

    out.write("  %d languages are held from more than one place\n" % len(several))
    out.write("  %-16s %s\n" % ("language", "held from"))
    for language in several:
        out.write("  %-16s %s\n" % (language, ", ".join(sorted(counts[language]))))

    # The same language from two places, against two languages from the same place
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

    out.write("\n  one language read from two places      %.4f over %d pairs\n"
              % (statistics.fmean(same_language), len(same_language)))
    out.write("  two languages read from one place      %.4f over %d pairs\n"
              % (statistics.fmean(same_source), len(same_source)))
    out.write("  the smaller of those is what the reading belongs to\n")

    # Named directly: for each language and each place it is held, whether its own reading elsewhere is
    # nearer than any other language's reading anywhere
    correct = 0
    total = 0
    wrong = []
    for source, language in sorted(gathered):
        if language not in several:
            continue
        others = [(other_source, other_language) for (other_source, other_language) in gathered
                  if other_source != source]
        if not others:
            continue
        total += 1
        marks = sorted((float(numpy.linalg.norm(gathered[(source, language)] - gathered[key])), key)
                       for key in others)
        if marks[0][1][1] == language:
            correct += 1
        else:
            wrong.append((language, source, marks[0][1][1], marks[0][1][0]))

    out.write("\n  %d of %d readings match their own language somewhere else first\n"
              % (correct, total))
    for language, source, went, went_source in wrong[:10]:
        out.write("    %-14s from %-14s matched %-14s from %s\n"
                  % (language, source, went, went_source))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
