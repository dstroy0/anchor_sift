#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Take the writing system out and see whether the family comes back, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/indic_common.py
#
# Read as characters, the Dravidian family does not come out at all. Tamil and Malayalam separated around
# the ninth century and sit 0.1005 apart, which is the widest distance in the whole matrix, the four
# Dravidian languages sit further from each other than from Indo Aryan, and Telugu's nearest neighbour is
# Bengali. That is not a family failing to appear, it is the opposite of the family appearing.
#
# Every one of those languages is written in its own script, so two close languages arrive with entirely
# different character inventories. Tamil writes with a small set that does not separate voiced from
# unvoiced or mark aspiration; Malayalam writes with a large one that does both. Nothing about the reading
# can see past that, because the characters are all it has.
#
# The scripts are alignable, and not by hand. Unicode lays the Indic blocks out in parallel on purpose:
# each occupies 128 positions and the same sound sits at the same offset in every one of them, so a
# character's position inside its own block is a statement about the sound and not about the script. That
# is a transliteration with no judgement in it and no losses chosen by me.
#
# If the family appears once the scripts are aligned, the reading was following writing systems, and the
# European families it recovered earlier are suspect for the same reason: there, relatedness and shared
# alphabet travel together and nothing separates them.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dravidian_structure import DRAVIDIAN, INDO_ARYAN, RANKS, SAME_LENGTH
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

# Where each script begins. Unicode gives every one of these 128 positions with the same sounds at the
# same offsets, which is what makes an offset comparable between them.
BLOCKS = (
    (0x0900, "devanagari"), (0x0980, "bengali"), (0x0A00, "gurmukhi"), (0x0A80, "gujarati"),
    (0x0B00, "oriya"), (0x0B80, "tamil"), (0x0C00, "telugu"), (0x0C80, "kannada"),
    (0x0D00, "malayalam"), (0x0D80, "sinhala"),
)


def to_common(text):
    """Every Indic character replaced by where it sits inside its own script's block.

    A character keeps its sound and loses which script wrote it, since the blocks are laid out in
    parallel. Anything outside those blocks is kept as it is.
    """
    out = []
    for symbol in text:
        point = ord(symbol)
        placed = None
        for start, _ in BLOCKS:
            if start <= point < (start + 0x80):
                placed = point - start
                break
        out.append(chr(0xE000 + placed) if placed is not None else symbol)
    return "".join(out)


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
        second = web(to_common(cut), RANKS)
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
            within = [apart(one, two) for index, one in enumerate(inside)
                      for two in inside[index + 1:]]
            across = [apart(one, two) for one in inside for two in outside]
            out.write("    dravidian to dravidian %.4f, to indo aryan %.4f, apart: %s\n"
                      % (float(numpy.mean(within)), float(numpy.mean(across)),
                         "yes" if numpy.mean(within) < numpy.mean(across) else "no"))
            strays = [name for name in inside
                      if min((apart(name, other), other)
                             for other in source if other != name)[1] not in inside]
            out.write("    every dravidian nearest is dravidian: %s\n"
                      % ("yes" if not strays else "no, %s leaves" % ", ".join(strays)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
