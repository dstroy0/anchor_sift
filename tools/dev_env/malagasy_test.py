#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Ask the descent against contact question a second time, on a family separated by an ocean, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/malagasy_test.py
#
# Uralic answered this once and answered contact. Finnish went to Swedish, which ruled it for six
# centuries, Hungarian went to Czech, and not one of the three found a relative. That test had one fault
# worth repeating better: its languages came from books, encyclopedia articles and translated works mixed
# together, so the collection a text came from was moving alongside everything else.
#
# Malagasy sets the same question up by geography. It is Austronesian, spoken in Madagascar, and its
# nearest relatives are in Borneo across the Indian Ocean. Everything it has borrowed from since is
# African and French. Descent points several thousand kilometres east and contact points at the coast it
# sits off, and nothing here confounds the two the way everything in Europe does.
#
# Every language below comes from one collection, so the content is fixed across all of them and the
# fault in the Uralic run is not repeated.
#
# What is missing and cannot be fixed from this collection: Swahili, which is the African contact language
# that matters most for Madagascar, is 1195 characters here. So contact is represented by French, which is
# real but is colonial and recent, and the Bantu side of the question is not asked.

import io
import os
import statistics
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 400000
RANKS = 64

HELD = (
    ("malagasy", "aus_malagasy.txt", "austronesian, in madagascar"),
    ("indonesian", "gn_indonesian.txt", "austronesian, its family"),
    ("malay", "gn_malay.txt", "austronesian, its family"),
    ("tagalog", "gn_tagalog.txt", "austronesian, its family"),
    ("maori", "gn_maori.txt", "austronesian, far off"),
    ("french", "gn_french.txt", "what it borrowed from"),
    ("portuguese", "gn_portuguese.txt", "a control"),
    ("amharic", "gn_amharic.txt", "the region, unrelated"),
)
FAMILY = ("indonesian", "malay", "tagalog", "maori")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    held = {}
    for label, name, why in HELD:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-12s not present\n" % label)
            continue
        text, gate = load(path, cap=SAME_LENGTH * 2, clean=False)
        if text is None:
            out.write("  %-12s refused by the gate: %s\n" % (label, gate))
            continue
        if len(text) < (SAME_LENGTH // 3):
            # Said as itself. Printing the gate's note here read as though the gate had rejected a file
            # it passed, and Tagalog was reported as having no script known when it was simply short.
            out.write("  %-12s passed the gate and holds %d characters, under the %d needed\n"
                      % (label, len(text), SAME_LENGTH // 3))
            continue
        values = web(text[:SAME_LENGTH], RANKS)
        if values is not None:
            held[label] = values

    names = sorted(held)
    if ("malagasy" not in held) or (len(names) < 5):
        out.write("  not enough held\n")
        out.flush()
        return 0

    out.write("  %d languages, all from one collection, each read from %d characters\n\n"
              % (len(names), SAME_LENGTH))
    out.write("  %-12s %s\n" % ("", "  ".join("%-11s" % name[:11] for name in names)))
    for one in names:
        row = ["%-11.4f" % float(numpy.linalg.norm(held[one] - held[two])) for two in names]
        out.write("  %-12s %s\n" % (one, "  ".join(row)))

    def apart(one, two):
        return float(numpy.linalg.norm(held[one] - held[two]))

    marks = sorted((apart("malagasy", other), other) for other in names if other != "malagasy")
    out.write("\n  what malagasy is nearest, in order\n")
    for distance, other in marks:
        why = next(note for label, _, note in HELD if label == other)
        out.write("    %-12s %-10.4f %s\n" % (other, distance, why))

    relatives = [apart("malagasy", other) for other in FAMILY if other in held]
    strangers = [apart("malagasy", other) for other in names
                 if other not in FAMILY and other != "malagasy"]
    if relatives and strangers:
        out.write("\n    to its family      %.4f over %d\n"
                  % (statistics.fmean(relatives), len(relatives)))
        out.write("    to everything else %.4f over %d\n"
                  % (statistics.fmean(strangers), len(strangers)))
        out.write("    descent beats the rest: %s\n"
                  % ("yes" if statistics.fmean(relatives) < statistics.fmean(strangers) else "no"))
        out.write("    its nearest is %s, which is %s\n"
                  % (marks[0][1], "its family" if marks[0][1] in FAMILY else "not its family"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
