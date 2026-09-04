#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether two numbers do what four thousand were doing, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/word_length_families.py
#
# Coarsening the alphabet down to two symbols left the close pairs closer than the far pairs, and at two
# symbols the only distinction is whether a character is the commonest one, which for most of these
# languages is the space. So what survived the reduction was word length, and the lengths matched the
# pairings: Zulu 5.70 against Xhosa 5.88, Spanish 4.41 against French 4.66, with Finnish at 6.41 which is
# what separates it from Spanish.
#
# If that is what the reading rests on, then word length alone should do what the reading does, and the
# four thousand numbers of a character square are carrying a signal that two numbers hold. Worth knowing
# either way: if the square wins, it holds something the lengths do not, and if it does not, most of the
# machinery in this section was unnecessary.
#
# Three descriptions of the same texts are compared on the same question. How long the words are, as a
# mean and a spread, which is two numbers. How the lengths are distributed, which is twenty. And which
# character follows which, which is four thousand ninety six.
#
# Word length needs a writing that marks where words end, so Chinese, Japanese and Thai cannot take part
# at all. That is not a gap in the corpus, it is the measure failing to exist for those writing systems,
# and it is the plainest case of this reading not being one reading across all of them.

import io
import os
import re
import statistics
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from parallel_web import MORE
from language_tree import FAMILY
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 400000
RANKS = 64
LONGEST_WORD = 20
NO_SPACES = ("chinese", "japanese", "thai", "burmese", "khmer", "lao")


def word_lengths(text):
    """How long the words are, as a spread over lengths and as a mean with its deviation."""
    words = [word for word in re.split(r"\s+", text) if word]
    if len(words) < 5000:
        return None, None
    lengths = numpy.asarray([min(len(word), LONGEST_WORD) for word in words], dtype=numpy.float64)
    spread = numpy.bincount(lengths.astype(numpy.int64), minlength=LONGEST_WORD + 1)
    spread = spread.astype(numpy.float64) / spread.sum()
    return (numpy.asarray([float(lengths.mean()), float(lengths.std())], dtype=numpy.float64),
            spread)


def family_score(reading, families):
    """How many languages with a relative present sit nearest one of their own."""
    names = sorted(reading)
    right = 0
    scored = 0
    misses = []
    for name in names:
        here = families.get(name)
        if (here is None) or (sum(1 for other in names if families.get(other) == here) < 2):
            continue
        scored += 1
        nearest = min((float(numpy.linalg.norm(reading[name] - reading[other])), other)
                      for other in names if other != name)[1]
        if families.get(nearest) == here:
            right += 1
        else:
            misses.append((name, nearest))
    return right, scored, misses


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    families = dict(FAMILY)
    families.update(MORE)

    two = {}
    twenty = {}
    many = {}
    left_out = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("para_") and name.endswith(".txt")):
            continue
        language = name[5:-4]
        if language in NO_SPACES:
            left_out.append(language)
            continue
        text, _ = load(os.path.join(CORPORA, name), cap=SAME_LENGTH * 2, clean=True)
        if (text is None) or (len(text) < SAME_LENGTH):
            continue
        text = text[:SAME_LENGTH]
        pair, spread = word_lengths(text)
        square = web(text, RANKS)
        if (pair is None) or (square is None):
            continue
        two[language] = pair
        twenty[language] = spread
        many[language] = square

    if len(two) < 10:
        out.write("  only %d languages held\n" % len(two))
        out.flush()
        return 0

    out.write("  %d languages, and %d left out for marking no word boundaries: %s\n\n"
              % (len(two), len(left_out), ", ".join(left_out)))
    out.write("  %-34s %-9s %-14s %s\n" % ("description", "numbers", "found", "share"))

    for label, count, reading in (("how long the words are", 2, two),
                                  ("how the lengths are spread", LONGEST_WORD + 1, twenty),
                                  ("which character follows which", RANKS * RANKS, many)):
        right, scored, misses = family_score(reading, families)
        if scored:
            out.write("  %-34s %-9d %-14s %.1f percent\n"
                      % (label, count, "%d of %d" % (right, scored), 100.0 * right / scored))

    out.write("\n  where each one goes wrong\n")
    for label, reading in (("the lengths", twenty), ("the square", many)):
        _, _, misses = family_score(reading, families)
        out.write("    %s: %s\n"
                  % (label, ", ".join("%s to %s" % pair for pair in misses[:7]) or "nowhere"))

    out.write("\n  mean word length and its spread, for the families that failed the square\n")
    for language in sorted(two):
        if families.get(language) in ("dravidian", "uralic", "bantu", "indic"):
            out.write("    %-14s %-12s %.2f, %.2f\n"
                      % (language, families.get(language), two[language][0], two[language][1]))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
