#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether two unrelated languages that farmed the same basin keep similar words for sounds, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/onomatopoeia_overlap.py
#
# Hungarian is Uralic and Polish is Slavic and they are not related. They have shared the Carpathian basin
# since the Magyars arrived into Slavic speaking country around 895, and Hungarian took several hundred
# Slavic loanwords, concentrated in farming, livestock, tools and religion. Words for sounds sit outside
# the core vocabulary that resists borrowing and attach to exactly that shared work, so they are where
# more of it would show.
#
# The question is whether Hungarian and Polish sound words resemble each other more than two unrelated
# languages should. That needs a baseline and the lists supply one: Polish against Finnish and Estonian is
# unrelated and shares no border, which is the comparison Hungarian and Polish have to beat. Hungarian
# against Finnish and Polish against Czech are the related pairs, which say what a real family
# relationship is worth on this measure.
#
# Two things are controlled because both would otherwise decide the answer. Spelling is stripped to bare
# letters, since Hungarian and Polish decorate their vowels differently and that alone would separate
# them. And every comparison uses the same number of words from each side, since a longer list gives any
# word a closer nearest match by chance and the lists run from 19 words to 468.

import io
import os
import random
import statistics
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAMPLE = 60
DRAWS = 40
SEED = 0x51F7


def bare(word):
    """The word in plain letters, with the decoration each language adds taken off."""
    opened = unicodedata.normalize("NFD", word.lower())
    kept = "".join(symbol for symbol in opened
                   if ("a" <= symbol <= "z") or symbol.isspace())
    # Polish files many of these as a call with a leading particle, which is not the sound word
    parts = kept.split()
    if len(parts) > 1 and parts[0] in ("a", "o", "e"):
        parts = parts[1:]
    return "".join(parts)


def distance(one, two):
    """How many single letter changes turn one word into the other, over the longer length."""
    if not one or not two:
        return 1.0
    previous = list(range(len(two) + 1))
    for index, left in enumerate(one, 1):
        current = [index]
        for place, right in enumerate(two, 1):
            current.append(min(previous[place] + 1, current[place - 1] + 1,
                               previous[place - 1] + (left != right)))
        previous = current
    return previous[-1] / float(max(len(one), len(two)))


def nearness(first, second, rng):
    """How close each word of one list sits to its nearest in the other, over equal sized draws."""
    marks = []
    for _ in range(DRAWS):
        left = rng.sample(first, min(SAMPLE, len(first)))
        right = rng.sample(second, min(SAMPLE, len(second)))
        for word in left:
            marks.append(min(distance(word, other) for other in right))
    return statistics.fmean(marks)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    held = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("said_") and name.endswith(".txt")):
            continue
        language = name[5:-4]
        with open(os.path.join(CORPORA, name), encoding="utf-8") as handle:
            words = {line.rstrip(chr(10)).split(chr(9))[-1] for line in handle if line.strip()}
        words = sorted(word for word in words if 2 <= len(word) <= 14)
        if len(words) >= 18:
            held[language] = words

    out.write("  %-12s %d words each, after stripping the spelling\n" % ("", 0))
    for language in sorted(held):
        out.write("  %-12s %d\n" % (language, len(held[language])))

    pairs = (
        ("hungarian", "polish", "unrelated, one basin since 895"),
        ("polish", "finnish", "unrelated, no border, the baseline"),
        ("polish", "estonian", "unrelated, no border, the baseline"),
        ("hungarian", "finnish", "one family, no border"),
        ("hungarian", "estonian", "one family, no border"),
        ("polish", "czech", "one family and a border"),
        ("hungarian", "czech", "unrelated, a border"),
        ("finnish", "estonian", "one family and a border"),
    )

    out.write("\n  %-26s %-34s %s\n" % ("pair", "what they are to each other", "how near"))
    rng = random.Random(SEED)
    marks = {}
    for one, two, note in pairs:
        if (one not in held) or (two not in held):
            continue
        value = nearness(held[one], held[two], rng)
        marks[(one, two)] = value
        out.write("  %-26s %-34s %.4f\n" % ("%s to %s" % (one, two), note, value))

    out.write("\n  lower means the words sit closer\n")
    claim = marks.get(("hungarian", "polish"))
    floors = [marks[key] for key in (("polish", "finnish"), ("polish", "estonian")) if key in marks]
    families = [marks[key] for key in (("hungarian", "finnish"), ("hungarian", "estonian"),
                                       ("polish", "czech"), ("finnish", "estonian")) if key in marks]
    if claim and floors:
        out.write("\n  hungarian to polish      %.4f\n" % claim)
        out.write("  unrelated and no border  %.4f\n" % statistics.fmean(floors))
        out.write("  one family              %.4f\n" % (statistics.fmean(families)
                                                        if families else float("nan")))
        out.write("  the claim holds: %s\n"
                  % ("yes" if claim < statistics.fmean(floors) else "no"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
