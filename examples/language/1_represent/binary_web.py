#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: LNG-1-002
#
# Put every language into one binary alphabet and read the web there, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python examples/language/1_represent/binary_web.py
#
# Reading which symbol follows which puts 52.8 percent of texts in the right language out of 31, and it
# does that over alphabets that have nothing in common. Positions were taken by frequency rank to make
# them comparable, which works and still leaves each language in an alphabet of its own size: Chinese
# brings three thousand symbols to the comparison and Welsh brings eighty.
#
# A rank is a place in an alphabet. A rank divided by the size of that alphabet is a fraction of the
# way through it, and it means the same thing everywhere. Its leading bits are then one alphabet for
# every language, of exactly two symbols, and the count of bits kept is chosen and not inherited from
# whatever script a language happens to use. Chinese and Welsh are then comparable without either
# being translated.
#
# The web is then read over fixed windows of that bit stream. Two things are worth knowing and the test
# separates them: whether this holds up against reading the characters directly, and whether it still
# groups the languages the way philology does once the script is gone entirely.

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

from measure.web import leave_one_out, squashed, web_of_codes  # noqa: E402
from oracle.language.families import FAMILY  # noqa: E402
from representation.text.corpus import CAP, LEAST, SKIP  # noqa: E402
from representation.text.shared_alphabet import WIDTHS, as_codes  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    loaded = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("lang_") and name.endswith(".txt")):
            continue
        if name[:-4] in SKIP:
            continue
        language = name[5:].rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue
        loaded.append((language, name[:-4], text))

    if len(loaded) < 8:
        out.write("  too few texts\n")
        out.flush()
        return 0

    languages = sorted({row[0] for row in loaded})
    out.write("  %d texts over %d languages, so guessing gets %.1f percent\n"
              % (len(loaded), len(languages), 100.0 / len(languages)))
    out.write("  every character carried by one code from one alphabet, whatever its script\n\n")
    out.write("  %-22s %-14s %s\n" % ("bits per character", "correct", "share"))

    best = None
    for width in WIDTHS:
        rows = []
        for language, label, text in loaded:
            codes, width_of = as_codes(text, width)
            values = web_of_codes(codes, width_of)
            if values is not None:
                rows.append((language, label, values))
        if len(rows) < 8:
            continue
        correct, total, confused = leave_one_out(rows)
        out.write("  %-22s %-14s %.1f percent\n"
                  % ("%d bits, %d codes" % (width, 1 << width),
                     "%d of %d" % (correct, total), 100.0 * correct / total))
        # Kept on its score, since taking whichever ran last reports a width nobody chose
        if (best is None) or (correct > best[0]):
            best = (correct, width, rows, confused)

    # Every width at once, the reading that does not require one to be chosen
    rows = []
    for language, label, text in loaded:
        values = squashed(text, as_codes, WIDTHS)
        if values is not None:
            rows.append((language, label, values))
    if len(rows) >= 8:
        correct, total, confused = leave_one_out(rows)
        out.write("  %-22s %-14s %.1f percent\n"
                  % ("every width at once", "%d of %d" % (correct, total),
                     100.0 * correct / total))
        if (best is None) or (correct > best[0]):
            best = (correct, 0, rows, confused)

    if best is None:
        out.flush()
        return 0

    # As a first pass its job is to narrow the field and not to name the answer, and the test is
    # whether the right language survives into a shortlist and how short that list can be
    _, width, rows, confused = best
    out.write("\n  everything below is read %s, which scored highest\n"
              % ("at every width at once" if width == 0
                 else "at %d bits, %d codes" % (width, 1 << width)))
    languages = sorted({row[0] for row in rows})
    depths = [1, 2, 3, 5, 8]
    kept = {depth: 0 for depth in depths}
    for index, (language, _, values) in enumerate(rows):
        order = []
        for other in languages:
            keep = [row[2] for position, row in enumerate(rows)
                    if row[0] == other and position != index]
            if keep:
                order.append((float(numpy.linalg.norm(values - numpy.mean(numpy.stack(keep), axis=0))),
                              other))
        order.sort()
        for depth in depths:
            if language in [name for _, name in order[:depth]]:
                kept[depth] += 1

    out.write("\n  how often the right language survives a shortlist of the nearest few\n")
    out.write("  %-16s %-14s %-11s %s\n" % ("shortlist", "kept", "share", "field cut to"))
    for depth in depths:
        out.write("  %-16s %-14s %-11.1f %.0f percent\n"
                  % ("nearest %d" % depth, "%d of %d" % (kept[depth], len(rows)),
                     100.0 * kept[depth] / len(rows), 100.0 * depth / len(languages)))

    holding = {}
    for language, _, values in rows:
        holding.setdefault(language, []).append(values)
    names = sorted(language for language in holding if len(holding[language]) >= 2)
    middles = {name: numpy.mean(numpy.stack(holding[name]), axis=0) for name in names}

    agreed = 0
    scored = 0
    for name in names:
        marks = sorted((float(numpy.linalg.norm(middles[name] - middles[other])), other)
                       for other in names if other != name)
        here = FAMILY.get(name)
        alone = sum(1 for other in names if FAMILY.get(other) == here) < 2
        if (here is None) or alone:
            continue
        scored += 1
        agreed += 1 if FAMILY.get(marks[0][1]) == here else 0

    out.write("\n  %d of %d languages with a relative present sit nearest one, in binary\n"
              % (agreed, scored))
    if confused:
        out.write("\n  where a text still goes wrong\n")
        for (was, went), count in sorted(confused.items(), key=lambda pair: -pair[1])[:8]:
            out.write("    %-14s taken for %-14s %d\n" % (was, went, count))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
