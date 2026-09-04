#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Score the reading against a family whose branchings are ordered, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/dravidian_structure.py
#
# The earlier family result was scored against a tree argued from cognates, and where the reading and the
# tree disagreed nothing could say which was wrong. This asks a harder question of the same reading.
#
# Written down before the distances are computed, from the accepted account of the family: Tamil and
# Malayalam nearest each other, separated around the ninth century; Kannada beside that pair, inside South
# Dravidian but split earlier; Telugu furthest of the four, being South Central and older still. Three
# distances in a required order, not a grouping. Beside them sit three Indo-Aryan languages of the same
# subcontinent, written in related scripts, which must all fall outside the Dravidian set: if they do not,
# the reading is following the writing systems of a region and not its languages.
#
# Every text is cut to one length. Tamil arrives with nearly seven times the characters of Malayalam, and
# a reading that moves with the amount of text would put those two at opposite ends for a reason that has
# nothing to do with either language.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 480000
RANKS = 64

DRAVIDIAN = ("tamil", "malayalam", "kannada", "telugu")
INDO_ARYAN = ("hindi", "bengali", "marathi")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    held = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("drav_") and name.endswith(".txt")):
            continue
        language = name[5:-4]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(SAME_LENGTH * 2)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < SAME_LENGTH:
            out.write("  %s holds only %d characters and is left out\n" % (language, len(text)))
            continue
        # Cut to one length, so nothing here can be a reading of how much text arrived
        values = web(text[:SAME_LENGTH], RANKS)
        if values is not None:
            held[language] = values

    names = sorted(held)
    if len(names) < 5:
        out.write("  too few languages held\n")
        out.flush()
        return 0

    out.write("  every text cut to %d characters\n\n" % SAME_LENGTH)
    out.write("  %-12s %s\n" % ("", "  ".join("%-11s" % name[:11] for name in names)))
    for one in names:
        row = []
        for two in names:
            row.append("%-11.4f" % float(numpy.linalg.norm(held[one] - held[two])))
        out.write("  %-12s %s\n" % (one, "  ".join(row)))

    def apart(one, two):
        return float(numpy.linalg.norm(held[one] - held[two]))

    inside = [name for name in DRAVIDIAN if name in held]
    outside = [name for name in INDO_ARYAN if name in held]
    out.write("\n  what was predicted, and what came back\n")

    if all(name in held for name in ("tamil", "malayalam", "kannada", "telugu")):
        pair = apart("tamil", "malayalam")
        to_kannada = min(apart("kannada", "tamil"), apart("kannada", "malayalam"))
        to_telugu = min(apart("telugu", "tamil"), apart("telugu", "malayalam"))
        out.write("    tamil to malayalam            %.4f\n" % pair)
        out.write("    kannada to the nearer of them %.4f\n" % to_kannada)
        out.write("    telugu to the nearer of them  %.4f\n" % to_telugu)
        held_order = (pair < to_kannada) and (to_kannada < to_telugu)
        out.write("    the predicted order holds: %s\n" % ("yes" if held_order else "no"))

    if inside and outside:
        within = [apart(one, two) for index, one in enumerate(inside) for two in inside[index + 1:]]
        across = [apart(one, two) for one in inside for two in outside]
        out.write("\n    dravidian to dravidian        %.4f over %d pairs\n"
                  % (float(numpy.mean(within)), len(within)))
        out.write("    dravidian to indo aryan       %.4f over %d pairs\n"
                  % (float(numpy.mean(across)), len(across)))
        out.write("    the family sits apart: %s\n"
                  % ("yes" if numpy.mean(within) < numpy.mean(across) else "no"))

        strays = [name for name in inside
                  if min((apart(name, other), other) for other in names if other != name)[1]
                  not in inside]
        out.write("    every dravidian language's nearest is dravidian: %s\n"
                  % ("yes" if not strays else "no, %s leaves" % ", ".join(strays)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
