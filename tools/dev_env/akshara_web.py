#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Read a writing system at the unit it puts its context in, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/akshara_web.py
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
# what follows a virama, which is the akshara that writing system is built on. Alphabetic text is
# unaffected, since a Latin letter carries no marks and the cluster is the letter.
#
# If the family comes out at this unit and not at the other, the reading was never wrong about language,
# it was being asked at a unit that only suits one kind of writing.

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

# Each Indic block puts its virama at the same offset, which is what binds two consonants into one unit
VIRAMAS = frozenset(start + 0x4D for start in
                    (0x0900, 0x0980, 0x0A00, 0x0A80, 0x0B00, 0x0B80, 0x0C00, 0x0C80, 0x0D00, 0x0D80))


def aksharas(text):
    """The text as clusters: a base with its marks, and with whatever a virama binds to it."""
    out = []
    current = []
    joining = False
    for symbol in text:
        if not current:
            current.append(symbol)
            joining = ord(symbol) in VIRAMAS
            continue
        if unicodedata.category(symbol).startswith("M") or joining:
            current.append(symbol)
            joining = ord(symbol) in VIRAMAS
            continue
        out.append("".join(current))
        current = [symbol]
        joining = ord(symbol) in VIRAMAS
    if current:
        out.append("".join(current))
    return out


def clustered_web(text, ranks):
    """The same reading, taken over clusters instead of over codepoints."""
    units = aksharas(text)
    counts = {}
    for unit in units:
        counts[unit] = counts.get(unit, 0) + 1
    ordered = sorted(counts, key=lambda unit: -counts[unit])[:ranks]
    seat = {unit: place for place, unit in enumerate(ordered)}

    grid = numpy.zeros((ranks, ranks), dtype=numpy.float64)
    previous = None
    for unit in units:
        place = seat.get(unit)
        if (place is not None) and (previous is not None):
            grid[previous, place] += 1.0
        previous = place
    total = grid.sum()
    return (grid / total).reshape(-1) if total > 0 else None


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
        second = clustered_web(cut, RANKS)
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
