#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Separate descent from contact using a family that has one without the other, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/uralic_test.py
#
# The European family result cannot tell descent from contact, because in Europe they travel together:
# every pair the reading grouped correctly shares an alphabet and a thousand years of borrowing. Dravidian
# has the descent without the contact and the reading inverted the family there, though that turned out to
# be untranslated English in the files.
#
# Uralic is the case that separates the two cleanly. Finnish and Estonian sit on the Baltic among Germanic
# and Baltic neighbours. Hungarian sits in central Europe surrounded by Slavic, German and Turkic, two
# thousand kilometres from its nearest relative, and has been for a thousand years. They are one family by
# descent and share almost nothing by contact, which is why the relationship took a long argument to
# establish and still surprises people.
#
# So the prediction is sharp in both directions. If the reading follows contact, Hungarian goes to its
# neighbours, German or Polish or Czech, and Finnish goes to Swedish, which it did once already in an
# earlier run here. If it follows descent, Hungarian goes to Finnish or Estonian across all that distance.
#
# Every corpus is taken through the gate, which is where the check for foreign writing now lives, because
# the last family that came out inverted came out that way from English sitting in the files.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import SKIP, web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 90000
RANKS = 64

URALIC = ("finnish", "estonian", "hungarian")
# The neighbours each of them borrowed from, which is what a reading of contact would go to instead
NEIGHBORS = ("swedish", "german", "russian", "polish", "czech", "slovenian", "romanian",
             "turkish", "danish", "norwegian", "dutch")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    wanted = set(URALIC) | set(NEIGHBORS)
    held = {}
    notes = []
    for name in sorted(os.listdir(CORPORA)):
        if not name.endswith(".txt"):
            continue
        if name[:-4] in SKIP:
            continue
        stem = name.rsplit(".", 1)[0]
        for prefix in ("lang_", "wiki_", "para2_", "para_", "cc_"):
            if stem.startswith(prefix):
                stem = stem[len(prefix):]
                break
        language = stem.rsplit("_", 1)[0] if stem.rsplit("_", 1)[-1].isdigit() else stem
        if language not in wanted:
            continue

        text, note = load(os.path.join(CORPORA, name), cap=SAME_LENGTH * 3, clean=True)
        if text is None:
            notes.append("%s refused by the gate: %s" % (name, note))
            continue
        if len(text) < SAME_LENGTH:
            # Said plainly, because printing the gate's note here read as though the gate had rejected a
            # file it had passed, and several clean files were being dropped for length under that label
            notes.append("%s passed the gate and holds only %d characters, under the %d needed"
                         % (name, len(text), SAME_LENGTH))
            continue
        values = web(text[:SAME_LENGTH], RANKS)
        if values is not None:
            held.setdefault(language, []).append(values)

    middles = {language: numpy.mean(numpy.stack(rows), axis=0)
               for language, rows in held.items() if rows}
    present = sorted(middles)
    uralic = [name for name in URALIC if name in middles]
    if len(uralic) < 2:
        out.write("  only %d uralic languages held\n" % len(uralic))
        out.flush()
        return 0

    out.write("  %d languages held, %d of them uralic, each read from %d characters\n\n"
              % (len(present), len(uralic), SAME_LENGTH))
    for note in notes[:6]:
        out.write("  %s\n" % note)

    out.write("  %-12s %-14s %-10s %s\n" % ("language", "nearest", "distance", "what that is"))
    for language in uralic:
        marks = sorted((float(numpy.linalg.norm(middles[language] - middles[other])), other)
                       for other in present if other != language)
        distance, nearest = marks[0]
        out.write("  %-12s %-14s %-10.4f %s\n"
                  % (language, nearest, distance,
                     "its own family" if nearest in URALIC else "a neighbour it borrowed from"))
        second = marks[1] if len(marks) > 1 else None
        if second:
            out.write("      then %s at %.4f\n" % (second[1], second[0]))

    if len(uralic) >= 2:
        within = [float(numpy.linalg.norm(middles[one] - middles[two]))
                  for index, one in enumerate(uralic) for two in uralic[index + 1:]]
        across = [float(numpy.linalg.norm(middles[one] - middles[two]))
                  for one in uralic for two in present if two not in URALIC]
        out.write("\n  uralic to uralic       %.4f over %d pairs\n"
                  % (float(numpy.mean(within)), len(within)))
        out.write("  uralic to its neighbours %.4f over %d pairs\n"
                  % (float(numpy.mean(across)), len(across)))
        out.write("  descent beats contact here: %s\n"
                  % ("yes" if numpy.mean(within) < numpy.mean(across) else "no"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
