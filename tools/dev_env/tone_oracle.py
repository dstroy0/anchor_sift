#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure how much of a language is its tone, where the tone can be deleted exactly, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/tone_oracle.py
#
# Three languages here carry tone and none of them lets it be taken out. Chinese fuses it into the
# character, so removing it means removing the word. Thai spreads it across marks and the class of the
# initial consonant together, so no set of codepoints is the tone. Japanese never writes its pitch accent
# at all.
#
# Vietnamese writes six tones as marks on a Latin base, and those marks are separate from the ones that
# set vowel quality. Acute, grave, hook above, tilde and dot below are the tone. Circumflex, breve and
# horn are the vowel and must survive. So the tone can be deleted and nothing else, which no other
# language here allows, and what the reading loses is what tone was worth to it.
#
# That matters because a syllable in Vietnamese carries six meanings under six tones, so removing the
# marks collapses six words into one and destroys a great deal of the language while leaving every letter
# in place. If the reading barely moves, it was never reading anything that tone carries.
#
# Every other language is stripped of its own marks the same way, as a control. Losing the accents of
# French removes far less, since French accents distinguish few words, and the difference between those
# two losses is the measure of what tone is worth.

import io
import os
import sys
import unicodedata

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 400000
RANKS = 64

# The five that are tone in Vietnamese
TONE = ("́", "̀", "̉", "̃", "̣")
# The three that are vowel quality and are not tone
QUALITY = ("̂", "̆", "̛")

HELD = (
    ("vietnamese", "para_vietnamese.txt", "six tones, written as marks"),
    ("french", "para_french.txt", "accents, distinguishing few words"),
    ("spanish", "para_spanish.txt", "accents, mostly stress"),
    ("czech", "para2_czech.txt", "marks for sounds, not tone"),
    ("turkish", "para2_turkish.txt", "marks for sounds, not tone"),
    ("romanian", "para_romanian.txt", "marks for sounds, not tone"),
)


def strip_marks(text, wanted):
    """The text with certain combining marks removed and every other mark left alone."""
    opened = unicodedata.normalize("NFD", text)
    kept = "".join(symbol for symbol in opened if symbol not in wanted)
    return unicodedata.normalize("NFC", kept)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-12s %-30s %-9s %-9s %s\n"
              % ("language", "what its marks do", "marks", "distinct", "reading moves"))

    for label, name, note in HELD:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-12s not present\n" % label)
            continue
        text, _ = load(path, cap=SAME_LENGTH * 2, clean=False)
        if (text is None) or (len(text) < SAME_LENGTH):
            continue
        text = text[:SAME_LENGTH]

        # For Vietnamese the tone alone, for every other language all of its marks
        wanted = TONE if label == "vietnamese" else None
        if wanted is None:
            opened = unicodedata.normalize("NFD", text)
            wanted = tuple(sorted({symbol for symbol in opened
                                   if unicodedata.category(symbol) == "Mn"}))
        stripped = strip_marks(text, wanted)

        opened = unicodedata.normalize("NFD", text)
        carried = sum(1 for symbol in opened if symbol in wanted)
        letters = sum(1 for symbol in text if symbol.isalpha())

        before = web(text, RANKS)
        after = web(stripped, RANKS)
        if (before is None) or (after is None):
            continue
        moved = float(numpy.linalg.norm(before - after))
        out.write("  %-12s %-30s %-9.3f %-9d %.4f\n"
                  % (label, note, carried / float(max(letters, 1)),
                     len(set(text)) - len(set(stripped)), moved))
        out.flush()

    out.write("\n  the marks column is how many marks there are per letter\n")
    out.write("  the distinct column is how many characters the language loses\n")
    out.write("  vietnamese is stripped of its tone only, every other language of all its marks\n")

    # What the loss costs where it can be checked: whether the stripped text still reads as itself
    path = os.path.join(CORPORA, "para_vietnamese.txt")
    if os.path.isfile(path):
        text, _ = load(path, cap=SAME_LENGTH * 3, clean=False)
        if text and (len(text) >= SAME_LENGTH * 2):
            first = web(text[:SAME_LENGTH], RANKS)
            second = web(text[SAME_LENGTH:SAME_LENGTH * 2], RANKS)
            toneless = web(strip_marks(text[:SAME_LENGTH], TONE), RANKS)
            if all(values is not None for values in (first, second, toneless)):
                out.write("\n  vietnamese against another part of itself   %.4f\n"
                          % float(numpy.linalg.norm(first - second)))
                out.write("  vietnamese against itself with tone gone    %.4f\n"
                          % float(numpy.linalg.norm(first - toneless)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
