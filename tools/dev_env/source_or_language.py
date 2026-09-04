#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Decide whether the reading belongs to a language or to where the text came from, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/source_or_language.py
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_alphabet import SKIP, web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 200000
LEAST = 70000
RANKS = 64

SOURCES = (
    ("books", "lang_", True),
    ("encyclopedia", "wiki_", True),
    ("one work", "para_", False),
    ("another work", "para2_", False),
)


def load():
    """One reading per language per source, averaged where a source holds several texts."""
    gathered = {}
    for source, prefix, numbered in SOURCES:
        held = {}
        for name in sorted(os.listdir(CORPORA)):
            if not (name.startswith(prefix) and name.endswith(".txt")):
                continue
            if name[:-4] in SKIP:
                continue
            stem = name[len(prefix):-4]
            language = stem.rsplit("_", 1)[0] if numbered else stem
            with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
                text = handle.read(CAP)
            text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
            if len(text) < LEAST:
                continue
            values = web(text, RANKS)
            if values is not None:
                held.setdefault(language, []).append(values)
        for language, rows in held.items():
            gathered[(source, language)] = numpy.mean(numpy.stack(rows), axis=0)
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
