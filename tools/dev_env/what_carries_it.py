#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find what the reading is actually keying on when it names a language, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/what_carries_it.py
#
# Hungarian is detected here, and the field's own settings say Hungarian wants shorter character runs than
# anything else measured, which is the opposite of what its morphology should need. Both cannot be about
# the same thing, so the question is what the detection is using.
#
# The obvious candidate is the inventory. Hungarian writes with characters almost nothing else uses, and a
# reading that names a language by the characters in it would name Hungarian perfectly while knowing
# nothing about Hungarian. That is not a small distinction: it is the difference between recognizing a
# language and recognizing an alphabet.
#
# So the features carrying each language are found first, by asking which characters that language uses
# far more than everything else does. Then those characters are removed and the naming is run again. What
# survives was structure. What does not was inventory.
#
# The test is run on every language held from one collection, so the content is fixed and only the
# languages vary.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 300000
RANKS = 64
STRIP = 8

WANTED = ("hungarian", "finnish", "estonian", "czech", "polish", "german", "french",
          "spanish", "italian", "swedish", "danish", "dutch", "romanian", "turkish",
          "indonesian", "vietnamese", "albanian", "lithuanian", "latvian", "slovenian")


def rare_elsewhere(texts, language, how_many=STRIP):
    """The characters this language uses far more than the others do."""
    mine = {}
    for symbol in texts[language]:
        mine[symbol] = mine.get(symbol, 0) + 1
    total = float(len(texts[language]))

    others = {}
    other_total = 0.0
    for other, text in texts.items():
        if other == language:
            continue
        for symbol in text:
            others[symbol] = others.get(symbol, 0) + 1
        other_total += len(text)

    marks = []
    for symbol, count in mine.items():
        if symbol.isspace() or not symbol.isalpha():
            continue
        here = count / total
        there = others.get(symbol, 0) / max(other_total, 1.0)
        if here > 0.0005:
            marks.append((here / (there + 1e-9), symbol, here))
    marks.sort(reverse=True)
    return [symbol for _, symbol, _ in marks[:how_many]], marks[:how_many]


def name_it(readings, held_out):
    """Which language a text is nearest, with itself set aside."""
    best = None
    picked = None
    for other, values in readings.items():
        if other == held_out:
            continue
        distance = float(numpy.linalg.norm(readings[held_out] - values))
        if (best is None) or (distance < best):
            best = distance
            picked = other
    return picked, best


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    texts = {}
    for language in WANTED:
        for prefix in ("para_", "para2_", "gn_"):
            path = os.path.join(CORPORA, "%s%s.txt" % (prefix, language))
            if os.path.isfile(path):
                text, _ = load(path, cap=SAME_LENGTH * 2, clean=True)
                if text and (len(text) >= SAME_LENGTH):
                    texts[language] = text[:SAME_LENGTH]
                    break

    if len(texts) < 8:
        out.write("  only %d languages held\n" % len(texts))
        out.flush()
        return 0

    out.write("  %d languages, all from one collection where possible\n\n" % len(texts))
    out.write("  %-12s %-30s %s\n" % ("language", "characters it uses far more", "how much more"))
    strips = {}
    for language in sorted(texts):
        symbols, marks = rare_elsewhere(texts, language)
        strips[language] = set(symbols)
        out.write("  %-12s %-30s %s\n"
                  % (language, " ".join(symbols),
                     " ".join("%.0fx" % ratio for ratio, _, _ in marks[:4])))

    # Every language loses its own distinctive characters, so none is handicapped against the others
    plain = {}
    stripped = {}
    for language, text in texts.items():
        plain[language] = web(text, RANKS)
        cut = "".join(symbol for symbol in text if symbol not in strips[language])
        stripped[language] = web(cut, RANKS)

    out.write("\n  each language paired with its nearest, before and after those characters go\n")
    out.write("  %-12s %-22s %-22s %s\n" % ("language", "nearest as written", "nearest without them",
                                            "moved"))
    changed = 0
    for language in sorted(texts):
        first, first_distance = name_it(plain, language)
        second, second_distance = name_it(stripped, language)
        if first != second:
            changed += 1
        out.write("  %-12s %-22s %-22s %s\n"
                  % (language, "%s %.4f" % (first, first_distance),
                     "%s %.4f" % (second, second_distance),
                     "yes" if first != second else ""))

    out.write("\n  %d of %d languages find a different nearest once their own characters are gone\n"
              % (changed, len(texts)))
    out.write("  a language whose nearest does not move was not being named by its inventory\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
