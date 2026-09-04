#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Read every Indic language at one set of distinctions, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/phoneme_lexer.py
#
# Four Dravidian languages came out further from each other than from Indo Aryan, and the pair that
# separated most recently came out the widest apart of the seven. The cause is in their inventories: in
# the same length of text Tamil uses 149 distinct codepoints and Malayalam 524, because Malayalam took
# Sanskrit phonology into its script and Tamil did not. The reading was measuring which distinctions each
# script chose to write down.
#
# Those inventories can be put on one footing, and not by hand. Every Indic block lays its consonants out
# in the inherited order, in rows of five: unvoiced, unvoiced aspirated, voiced, voiced aspirated, nasal.
# Collapsing each row of four stops onto the first of them keeps exactly the distinctions Tamil script
# keeps, and applying it to all seven languages asks every one of them the same question.
#
# The claim being tested is that the trouble was never the measure but the unit it was asked at. If the
# family appears once the languages are read at one set of distinctions, that claim holds here. If it
# does not, the measure is reading something else and no choice of unit repairs it.

import io
import os
import sys
import unicodedata

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dravidian_structure import DRAVIDIAN, INDO_ARYAN, RANKS, SAME_LENGTH
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

STARTS = (0x0900, 0x0980, 0x0A00, 0x0A80, 0x0B00, 0x0B80, 0x0C00, 0x0C80, 0x0D00, 0x0D80)
# The consonants run from this offset in rows of five, which is the inherited ordering every block keeps
FIRST_CONSONANT = 0x15
ROWS = 5
LAST_CONSONANT = FIRST_CONSONANT + (ROWS * 5)


def collapsed(text, keep_aspiration=False):
    """Every Indic character reduced to its offset, with the stop rows folded onto their first member.

    A character keeps which sound it is and loses which script wrote it and which finer distinctions that
    script chose to record. Anything outside the Indic blocks is left alone.
    """
    out = []
    for symbol in text:
        point = ord(symbol)
        offset = None
        for start in STARTS:
            if start <= point < (start + 0x80):
                offset = point - start
                break
        if offset is None:
            out.append(symbol)
            continue
        if (not keep_aspiration) and (FIRST_CONSONANT <= offset < LAST_CONSONANT):
            place = offset - FIRST_CONSONANT
            # The fifth of each row is the nasal and is its own sound, so only the four stops fold
            if (place % ROWS) != 4:
                offset = FIRST_CONSONANT + ((place // ROWS) * ROWS)
        out.append(chr(0xE000 + offset))
    return "".join(out)


def judge(out, source, label):
    def apart(one, two):
        return float(numpy.linalg.norm(source[one] - source[two]))

    inside = [name for name in DRAVIDIAN if name in source]
    outside = [name for name in INDO_ARYAN if name in source]
    out.write("\n  %s\n" % label)
    if all(name in source for name in ("tamil", "malayalam", "kannada", "telugu")):
        pair = apart("tamil", "malayalam")
        near_kannada = min(apart("kannada", "tamil"), apart("kannada", "malayalam"))
        near_telugu = min(apart("telugu", "tamil"), apart("telugu", "malayalam"))
        out.write("    tamil to malayalam %.4f, kannada %.4f, telugu %.4f, order holds: %s\n"
                  % (pair, near_kannada, near_telugu,
                     "yes" if (pair < near_kannada < near_telugu) else "no"))
    if inside and outside:
        within = [apart(one, two) for index, one in enumerate(inside) for two in inside[index + 1:]]
        across = [apart(one, two) for one in inside for two in outside]
        out.write("    dravidian to dravidian %.4f, to indo aryan %.4f, apart: %s\n"
                  % (float(numpy.mean(within)), float(numpy.mean(across)),
                     "yes" if numpy.mean(within) < numpy.mean(across) else "no"))
        strays = [name for name in inside
                  if min((apart(name, other), other)
                         for other in source if other != name)[1] not in inside]
        out.write("    every dravidian nearest is dravidian: %s\n"
                  % ("yes" if not strays else "no, %s leaves" % ", ".join(strays)))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    readings = {"as written": {}, "one alphabet": {}, "one set of distinctions": {}}
    inventory = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("drav_") and name.endswith(".txt")):
            continue
        language = name[5:-4]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(SAME_LENGTH * 2)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < SAME_LENGTH:
            continue
        cut = text[:SAME_LENGTH]

        kept = collapsed(cut, keep_aspiration=True)
        folded = collapsed(cut, keep_aspiration=False)
        for label, series in (("as written", cut), ("one alphabet", kept),
                              ("one set of distinctions", folded)):
            values = web(series, RANKS)
            if values is not None:
                readings[label][language] = values
        inventory[language] = (len(set(cut)), len(set(kept)), len(set(folded)))

    if len(readings["as written"]) < 5:
        out.write("  too few languages held\n")
        out.flush()
        return 0

    out.write("  distinct symbols in the same length of text\n")
    out.write("  %-12s %-14s %-14s %s\n"
              % ("language", "as written", "one alphabet", "one set"))
    for language in sorted(inventory):
        out.write("  %-12s %-14d %-14d %d\n" % ((language,) + inventory[language]))

    for label in ("as written", "one alphabet", "one set of distinctions"):
        judge(out, readings[label], label)

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
