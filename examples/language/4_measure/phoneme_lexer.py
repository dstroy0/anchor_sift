#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: LNG-4-030
#
# Read every Indic language at one set of distinctions, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python examples/language/4_measure/phoneme_lexer.py
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

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.web import web  # noqa: E402
from oracle.language.families import dravidian_check  # noqa: E402
from representation.text.indic import collapsed  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

# Every text cut to one length, since Tamil arrives with nearly seven times the characters of
# Malayalam and a reading that moves with the amount of text would separate those two for that.
SAME_LENGTH = 480000
RANKS = 64


def judge(out, source, label):
    """The family's own prediction, scored in the engine and written out here."""
    found = dravidian_check(source)
    out.write("\n  %s\n" % label)
    if found["pair"] is not None:
        out.write("    tamil to malayalam %.4f, kannada %.4f, telugu %.4f, order holds: %s\n"
                  % (found["pair"], found["kannada"], found["telugu"],
                     "yes" if found["order_holds"] else "no"))
    if found["within"] is not None:
        out.write("    dravidian to dravidian %.4f, to indo aryan %.4f, apart: %s\n"
                  % (found["within"], found["across"], "yes" if found["apart_holds"] else "no"))
    if found["strays"] is not None:
        out.write("    every dravidian nearest is dravidian: %s\n"
                  % ("yes" if not found["strays"] else "no, %s leaves" % ", ".join(found["strays"])))


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
