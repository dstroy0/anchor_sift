#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Take the writing system out and see whether the family comes back, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python examples/language/4_measure/indic_common.py
#
# Read as characters, the Dravidian family does not come out at all. Tamil and Malayalam separated around
# the ninth century and sit 0.1005 apart, the widest distance in the whole matrix, the four
# Dravidian languages sit further from each other than from Indo Aryan, and Telugu's nearest neighbor is
# Bengali. That is not a family failing to appear, it is the opposite of the family appearing.
#
# Every one of those languages is written in its own script, so two close languages arrive with entirely
# different character inventories. Tamil writes with a small set that does not separate voiced from
# unvoiced or mark aspiration; Malayalam writes with a large one that does both. Nothing about the reading
# can see past that, because the characters are all it has.
#
# The scripts are alignable, and not by hand. Unicode lays the Indic blocks out in parallel by design:
# each occupies 128 positions and the same sound sits at the same offset in every one of them. A
# character's position inside its own block is a statement about the sound and never about the script. That
# is a transliteration with no judgement in it and no losses chosen by me.
#
# If the family appears once the scripts are aligned, the reading was following writing systems, and the
# European families it recovered earlier are suspect for the same reason: there, relatedness and shared
# alphabet travel together and nothing separates them.

import io
import os
import sys

import numpy

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

    held = {}
    plain = {}
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
        first = web(cut, RANKS)
        # Every distinction any of the scripts records is kept; only which script wrote it goes
        second = web(collapsed(cut, keep_aspiration=True), RANKS)
        if (first is not None) and (second is not None):
            plain[language] = first
            held[language] = second

    names = sorted(held)
    if len(names) < 5:
        out.write("  too few languages held\n")
        out.flush()
        return 0

    out.write("  with the scripts aligned by where each character sits in its own block\n\n")
    out.write("  %-12s %s\n" % ("", "  ".join("%-11s" % name[:11] for name in names)))
    for one in names:
        row = ["%-11.4f" % float(numpy.linalg.norm(held[one] - held[two])) for two in names]
        out.write("  %-12s %s\n" % (one, "  ".join(row)))

    for label, source in (("as written", plain), ("scripts aligned", held)):
        judge(out, source, label)

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
