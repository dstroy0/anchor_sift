#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: LNG-1-001
#
# Read a writing system at the unit it puts its context in, for Section 4.13 of
# theory/anchor_sift.
#
#   Usage:  python examples/language/1_represent/akshara_web.py
#
# Read as codepoints, four Dravidian languages come out further from each other than from Indo Aryan, and
# the pair that separated most recently reads as the widest distance in the matrix. Aligning the scripts
# changed nothing, and it could not have: the reading ranks characters by how often they occur inside each
# text, so which codepoints a script uses never entered it.
#
# The assumption underneath is about the unit. A letter sequence works for an alphabet because that is
# where an alphabet keeps its context: letters run together into morphemes and the statistics of letter
# pairs carry that. An abugida keeps its context somewhere else. A consonant carries a vowel already, a
# dependent sign changes which vowel, and a virama binds one consonant to the next, so the unit that
# means something is the whole cluster and a codepoint is a piece of one. Counting the pieces counts how a
# script decomposes, and two close languages decompose differently.
#
# So the text is cut into clusters instead: a base character with every mark that modifies it, and with
# what follows a virama, the akshara that writing system is built on. Alphabetic text is
# unaffected, since a Latin letter carries no marks and the cluster is the letter.
#
# If the family comes out at this unit and not at the other, the reading was never wrong about language,
# it was being asked at a unit that only suits one kind of writing.

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
from representation.text.clusters import aksharas  # noqa: E402

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

    plain = {}
    held = {}
    sizes = {}
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
        # The reading takes a sequence of symbols and never required a symbol to be one character
        second = web(aksharas(cut), RANKS)
        if (first is not None) and (second is not None):
            plain[language] = first
            held[language] = second
            sizes[language] = len({unit for unit in aksharas(cut)})

    names = sorted(held)
    if len(names) < 5:
        out.write("  too few languages held\n")
        out.flush()
        return 0

    out.write("  %-12s %-14s %s\n" % ("language", "codepoints", "clusters"))
    for language in names:
        with open(os.path.join(CORPORA, "drav_%s.txt" % language),
                  encoding="utf-8", errors="replace") as handle:
            cut = handle.read(SAME_LENGTH).replace("\n", " ")
        out.write("  %-12s %-14d %d\n" % (language, len(set(cut)), sizes[language]))

    out.write("\n  %-12s %s\n" % ("", "  ".join("%-11s" % name[:11] for name in names)))
    for one in names:
        row = ["%-11.4f" % float(numpy.linalg.norm(held[one] - held[two])) for two in names]
        out.write("  %-12s %s\n" % (one, "  ".join(row)))

    judge(out, plain, "read as codepoints")
    judge(out, held, "read as clusters")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
