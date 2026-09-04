#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Ask whether the reading follows the language or the writing, with one held fixed at a time, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/script_or_language.py
#
# Every earlier test moved both at once. Dravidian changed the script and kept the family, Uralic changed
# the contact and kept the descent, and neither could say which of the two the reading was answering.
# Chinese holds one fixed at a time.
#
# Simplified and traditional are one language written in two character sets. The words are the same, the
# grammar is the same, and a reader of one can often not read the other on sight. That is a change of
# writing with no change of language, and both sides come from the same software translations so the
# subject matter is fixed as well, which makes it the cleanest comparison available here.
#
# Cantonese against Mandarin is the other half, two languages that are not mutually intelligible and are
# written in largely the same characters. That comparison carries a fault that cannot be removed with what
# is available: the Cantonese is subtitles and the Mandarin beside it is not from the same collection, so a
# difference between them is also a difference of subject. It is reported and marked, not leaned on.
#
# What the script pair alone can settle: if one language in two character sets reads as far apart as two
# unrelated languages do, the reading is following the writing.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 45000
RANKS = 64

HELD = (
    ("simplified", "sinitic_simplified.txt", "one language, simplified characters"),
    ("traditional", "sinitic_traditional.txt", "one language, traditional characters"),
    ("hongkong", "sinitic_hongkong.txt", "one language, traditional characters"),
    ("cantonese", "sinitic_cantonese.txt", "another language, same characters"),
    ("mandarin", "para_chinese.txt", "another collection entirely"),
    ("mandarin2", "para2_chinese.txt", "another collection entirely"),
    ("japanese", "para_japanese.txt", "another language, some shared characters"),
    ("korean", "para_korean.txt", "another language, no shared characters"),
)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    held = {}
    for label, name, note in HELD:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-14s not present\n" % label)
            continue
        text, gate = load(path, cap=SAME_LENGTH * 4, clean=False)
        if text is None:
            out.write("  %-14s refused by the gate: %s\n" % (label, gate))
            continue
        if len(text) < SAME_LENGTH:
            # The gate's note here read as though the gate had rejected a file it passed
            out.write("  %-14s passed the gate and holds %d characters, under the %d needed\n"
                      % (label, len(text), SAME_LENGTH))
            continue
        values = web(text[:SAME_LENGTH], RANKS)
        if values is not None:
            held[label] = (values, note)

    names = sorted(held)
    if len(names) < 4:
        out.write("  too few held\n")
        out.flush()
        return 0

    out.write("  each read from %d characters\n\n" % SAME_LENGTH)
    out.write("  %-14s %s\n" % ("", "  ".join("%-12s" % name[:12] for name in names)))
    for one in names:
        row = ["%-12.4f" % float(numpy.linalg.norm(held[one][0] - held[two][0])) for two in names]
        out.write("  %-14s %s\n" % (one, "  ".join(row)))

    def apart(one, two):
        return float(numpy.linalg.norm(held[one][0] - held[two][0]))

    out.write("\n  one language, two character sets, one collection\n")
    if ("simplified" in held) and ("traditional" in held):
        out.write("    simplified to traditional      %.4f\n" % apart("simplified", "traditional"))
    if ("traditional" in held) and ("hongkong" in held):
        out.write("    traditional to hong kong       %.4f  both traditional, a control\n"
                  % apart("traditional", "hongkong"))

    out.write("\n  against other languages, for scale\n")
    for one, two in (("simplified", "cantonese"), ("simplified", "mandarin"),
                     ("simplified", "japanese"), ("simplified", "korean"),
                     ("cantonese", "mandarin")):
        if (one in held) and (two in held):
            out.write("    %-14s to %-14s %.4f\n" % (one, two, apart(one, two)))

    if all(name in held for name in ("simplified", "traditional", "hongkong")):
        script_change = apart("simplified", "traditional")
        same_script = apart("traditional", "hongkong")
        others = [apart("simplified", other) for other in
                  ("cantonese", "mandarin", "japanese", "korean") if other in held]
        out.write("\n    changing the characters costs %.4f\n" % script_change)
        out.write("    keeping them costs             %.4f\n" % same_script)
        if others:
            out.write("    another language costs         %.4f on average\n"
                      % float(numpy.mean(others)))
            out.write("    the writing matters more than the language: %s\n"
                      % ("yes" if script_change > float(numpy.mean(others)) else "no"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
