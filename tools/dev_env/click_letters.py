#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether the one clean success rests on a shared spelling habit, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/click_letters.py
#
# Zulu and Xhosa read 0.0756 apart, the closest pair measured anywhere here, and that was recorded as the
# one test with no confound left in it: a close pair, one script, one text, one set of translators.
#
# There is a confound and it is in the script after all. Nguni languages write their click consonants with
# c, x and q, which is a use of those letters no other language here makes, and clicks are common in
# ordinary Nguni words. So the two languages share a spelling convention that nothing else in the corpus
# shares, and three letters carrying wholly unlike frequencies from every other Latin alphabet is exactly
# the kind of surface this reading has followed everywhere else.
#
# Two things are measured. How often those letters are used, against every other language written in the
# Latin alphabet here, which says whether the convention is as distinctive as it should be. Then the same
# pair read with those three letters removed from every language equally, which says whether the pairing
# survives losing them.
#
# If it survives, the pairing was about the languages and the earlier claim stands. If it does not, the
# closest pair measured in this work is two spelling systems agreeing, and there was never a test here
# without a confound in it.

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
CLICKS = "cxq"

AFRICAN = ("zulu", "xhosa", "shona", "somali", "wolof", "afrikaans")
# Latin written languages held on the same translated text, for what those letters usually do
BESIDE = ("para_english", "para_spanish", "para_french", "para_german", "para_swedish",
          "para_indonesian", "para_vietnamese", "para_romanian", "para_albanian")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    held = {}
    for name in AFRICAN:
        path = os.path.join(CORPORA, "afr_%s.txt" % name)
        if os.path.isfile(path):
            text, _ = load(path, cap=SAME_LENGTH * 2, clean=False)
            if text and (len(text) >= SAME_LENGTH // 2):
                held[name] = text[:SAME_LENGTH]
    for name in BESIDE:
        path = os.path.join(CORPORA, "%s.txt" % name)
        if os.path.isfile(path):
            text, _ = load(path, cap=SAME_LENGTH * 2, clean=False)
            if text and (len(text) >= SAME_LENGTH // 2):
                held[name[5:]] = text[:SAME_LENGTH]

    if len(held) < 6:
        out.write("  only %d languages held\n" % len(held))
        out.flush()
        return 0

    out.write("  how often c, x and q are used, per thousand letters\n")
    out.write("  %-14s %-9s %-9s %-9s %s\n" % ("language", "c", "x", "q", "the three together"))
    shares = {}
    for name in sorted(held):
        text = held[name].lower()
        letters = sum(1 for symbol in text if symbol.isalpha())
        if letters < 1000:
            continue
        row = [1000.0 * text.count(letter) / letters for letter in CLICKS]
        shares[name] = sum(row)
        out.write("  %-14s %-9.2f %-9.2f %-9.2f %.2f\n" % ((name,) + tuple(row) + (sum(row),)))

    nguni = [name for name in ("zulu", "xhosa") if name in shares]
    others = [name for name in shares if name not in ("zulu", "xhosa")]
    if nguni and others:
        out.write("\n  the two nguni languages use them %.1f times as often as the rest\n"
                  % (float(numpy.mean([shares[name] for name in nguni]))
                     / float(numpy.mean([shares[name] for name in others]))))

    out.write("\n  the pairing, with those letters kept and with them gone from every language\n")
    out.write("  %-26s %-11s %s\n" % ("", "as written", "c, x, q removed"))

    for label, pair in (("zulu to xhosa", ("zulu", "xhosa")),
                        ("zulu to shona", ("zulu", "shona")),
                        ("zulu to somali", ("zulu", "somali")),
                        ("xhosa to wolof", ("xhosa", "wolof")),
                        ("english to german", ("english", "german")),
                        ("spanish to french", ("spanish", "french"))):
        if not all(name in held for name in pair):
            continue
        first = [web(held[name], RANKS) for name in pair]
        stripped = ["".join(symbol for symbol in held[name] if symbol.lower() not in CLICKS)
                    for name in pair]
        second = [web(text, RANKS) for text in stripped]
        if any(values is None for values in first + second):
            continue
        out.write("  %-26s %-11.4f %.4f\n"
                  % (label, float(numpy.linalg.norm(first[0] - first[1])),
                     float(numpy.linalg.norm(second[0] - second[1]))))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
