#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The test with no excuse left in it, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/nguni_test.py
#
# Every failure so far had somewhere to hide. Tamil and Malayalam are close and came out the widest apart
# of seven, and their scripts encode different distinctions. Uralic lost its family, and its members have
# had a thousand years of unlike neighbours. Chinese showed the collection a text came from moving the
# reading more than the language does, and those collections were different works.
#
# Zulu and Xhosa remove all of it. Both are Nguni, close enough to be partly mutually intelligible. Both
# are written in the same Latin alphabet. Both come from the same translated work as the other 43
# languages here, so the content, the register and the translators' brief are fixed. Shona is Bantu and
# further off, which gives the family a shape and not just a pair, and Somali, Amharic and Wolof are three
# other families of the same continent, which is what the pair has to beat.
#
# There is no confound left to name. If the reading pairs Zulu with Xhosa it can see a close relationship
# when nothing about the writing interferes. If it does not, the earlier failures were never about scripts
# and it does not read language.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 700000
RANKS = 64

FAMILY = {
    "zulu": "bantu", "xhosa": "bantu", "shona": "bantu",
    "somali": "cushitic", "amharic": "semitic", "wolof": "atlantic",
    "afrikaans": "germanic",
}
NGUNI = ("zulu", "xhosa")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    held = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("afr_") and name.endswith(".txt")):
            continue
        language = name[4:-4]
        text, gate = load(os.path.join(CORPORA, name), cap=SAME_LENGTH * 2, clean=False)
        if text is None:
            out.write("  %-12s refused: %s\n" % (language, gate))
            continue
        if len(text) < SAME_LENGTH:
            out.write("  %-12s holds %d characters, under the %d wanted, used at its length\n"
                      % (language, len(text), SAME_LENGTH))
        values = web(text[:SAME_LENGTH], RANKS)
        if values is not None:
            held[language] = values

    names = sorted(held)
    if len(names) < 5:
        out.write("  too few languages held\n")
        out.flush()
        return 0

    out.write("\n  %-12s %s\n" % ("", "  ".join("%-11s" % name[:11] for name in names)))
    for one in names:
        row = ["%-11.4f" % float(numpy.linalg.norm(held[one] - held[two])) for two in names]
        out.write("  %-12s %s\n" % (one, "  ".join(row)))

    def apart(one, two):
        return float(numpy.linalg.norm(held[one] - held[two]))

    out.write("\n  %-12s %-14s %-10s %s\n" % ("language", "nearest", "distance", "same family"))
    right = 0
    scored = 0
    for language in names:
        marks = sorted((apart(language, other), other) for other in names if other != language)
        distance, nearest = marks[0]
        here = FAMILY.get(language)
        if sum(1 for other in names if FAMILY.get(other) == here) >= 2:
            scored += 1
            hit = FAMILY.get(nearest) == here
            right += 1 if hit else 0
            out.write("  %-12s %-14s %-10.4f %s\n"
                      % (language, nearest, distance, "yes" if hit else "no"))
        else:
            out.write("  %-12s %-14s %-10.4f only one of its family here\n"
                      % (language, nearest, distance))

    if all(name in held for name in NGUNI):
        pair = apart(*NGUNI)
        others = [apart(one, two) for one in NGUNI for two in names
                  if two not in NGUNI]
        out.write("\n  zulu to xhosa                 %.4f\n" % pair)
        out.write("  either of them to anything else %.4f on average, %.4f at closest\n"
                  % (float(numpy.mean(others)), float(min(others))))
        out.write("  the closest pair in the family is the closest pair measured: %s\n"
                  % ("yes" if pair < min(others) else "no"))

    out.write("\n  %d of %d languages with a relative present sit nearest one\n" % (right, scored))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
