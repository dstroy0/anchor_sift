#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: LNG-6-002
#
# Pull the glossed examples out of an extracted proceedings volume and measure what the English
# translation throws away, for Section 4.13 of theory/anchor_sift.
#
#   Usage:  python examples/language/6_oracle/gloss_harvest.py icsnl2016
#
# Robertson and colleagues end their paper on Lower Chehalis asking for work that makes the literal
# content of Salish words overt, and give the example themselves: the word for people analyzes as
# many=mouths=in.a.longhouse, which no English translation of it carries. They treat that as something a
# lexicographer would recover by hand from an elder's explanation.
#
# It does not have to be recovered by hand, because the interlinear format already holds both halves. An
# example is printed in three lines: the form with its morpheme boundaries, a morpheme by morpheme gloss,
# and a running translation. The second line is what the word composes. The third is what English keeps.
# The difference between them is the metaphor, and it comes out by subtraction.
#
# That difference is countable. A word built from five morphemes and translated by one English word has
# four morphemes of scene that the translation discarded, and the ratio of morphemes composed to words
# retained says how much of the picture a reader of the English never sees. It is a lower bound on the
# metaphor and not a measure of it, since a translation can also keep the scene and just be long.
#
# The form lines came out of the PDF with the glottalized and retracted consonants dropped, which would
# ruin any measurement of the phonology. Gloss lines and translation lines are close to plain ASCII and
# came through, and those are the two lines this needs.
#
# What this cannot see: glossing conventions belong to authors and not to the field. Van Eijk marks telic
# reduplication with the equals sign in this same volume where Robertson marks lexical suffixes with it,
# and a count of one symbol across papers counts two different things. Morphemes are therefore counted
# from every boundary mark together, and the per-paper question is left to a reader who opens the paper.

import io
import os
import re
import statistics
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from oracle.language.glosses import harvest, morphemes  # noqa: E402

PAPERS = os.path.join(ROOT, "build", "papers")


def main():
    if len(sys.argv) < 2:
        print("usage: gloss_harvest.py <volume name>")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    volume = sys.argv[1]
    source = os.path.join(PAPERS, "%s.txt" % volume)
    if not os.path.isfile(source):
        out.write("  no %s, run icsnl_probe.py first\n" % source)
        out.flush()
        return 1

    with open(source, encoding="utf-8", errors="replace") as handle:
        blob = handle.read()
    parts = re.split(r"\n===== page (\d+) =====\n", blob)
    pages = []
    walk = 1
    while walk + 1 <= len(parts) - 1:
        pages.append((int(parts[walk]), parts[walk + 1]))
        walk += 2

    found = harvest(pages)
    out.write("  %d pages read, %d glossed examples found\n" % (len(pages), len(found)))
    if not found:
        out.flush()
        return 0

    target = os.path.join(PAPERS, "%s_glosses.tsv" % volume)
    ratios = []
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("page\tmorphemes\tenglish_words\tratio\tgloss\ttranslation\n")
        for number, gloss, english in found:
            pieces = morphemes(gloss)
            words = len([one for one in english.split() if one.strip()])
            if words < 1:
                continue
            ratio = pieces / float(words)
            ratios.append(ratio)
            handle.write("%d\t%d\t%d\t%.3f\t%s\t%s\n"
                         % (number, pieces, words, ratio, gloss, english))

    out.write("  written to %s\n" % target)
    out.write("\n  morphemes composed against English words kept\n")
    out.write("  median %.3f, mean %.3f, over %d examples\n"
              % (statistics.median(ratios), statistics.fmean(ratios), len(ratios)))
    out.write("  a ratio above one means the morphology carries more pieces than the\n")
    out.write("  translation keeps words, which is where the scene is being discarded\n")

    steep = sorted(zip(ratios, found), key=lambda pair: -pair[0])[:8]
    out.write("\n  the examples that lose the most, by that ratio\n")
    for ratio, (number, gloss, english) in steep:
        out.write("  %-6.2f page %-4d %s\n" % (ratio, number, english[:66]))
        out.write("         %s\n" % gloss[:100])

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
