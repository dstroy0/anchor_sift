#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Put every language into one binary alphabet and read the web there, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/binary_web.py
#
# Reading which symbol follows which puts 52.8 percent of texts in the right language out of 31, and it
# does that over alphabets that have nothing in common. Positions were taken by frequency rank to make
# them comparable, which works and still leaves each language in an alphabet of its own size: Chinese
# brings three thousand symbols to the comparison and Welsh brings eighty.
#
# A rank is a place in an alphabet, so a rank divided by the size of that alphabet is a fraction of the
# way through it and means the same thing everywhere. Its leading bits are then one alphabet for every
# language, of exactly two symbols, and the count of bits kept is chosen and not inherited from whatever
# script a language happens to use. That is what makes Chinese and Welsh comparable without either being
# translated.
#
# The web is then read over fixed windows of that bit stream. Two things are worth knowing and the test
# separates them: whether this holds up against reading the characters directly, and whether it still
# groups the languages the way philology does once the script is gone entirely.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from language_tree import FAMILY
from web_alphabet import CAP, LEAST, SKIP, leave_one_out

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

# Bits given to each character, so the shared alphabet holds two to this many codes. The web is over
# characters and the bits say which code a character carries, so one code covers exactly one character and
# a reading never straddles two of them.
WIDTHS = (3, 4, 5, 6, 7)


def as_codes(text, width):
    """Every character given a code in one alphabet shared by every language.

    A character's rank among the symbols of its own text, divided by how many there are, says how far
    through its alphabet it sits, and that is the same quantity in a language of eighty symbols and one of
    three thousand. Held to a fixed count of bits it becomes a code from a shared alphabet, so nothing is
    translated between scripts and nothing is thrown away for being past a cutoff.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ranked = sorted(counts, key=lambda symbol: -counts[symbol])
    size = float(len(ranked))
    width_of = 1 << width
    seat = {symbol: min(width_of - 1, int((place / size) * width_of))
            for place, symbol in enumerate(ranked)}
    return numpy.asarray([seat[symbol] for symbol in text], dtype=numpy.int64), width_of


def web_of_codes(codes, width_of):
    """Share of the time one character's code is followed by another's, over the whole text."""
    if len(codes) < (4 * width_of * width_of):
        return None
    pairs = (codes[:-1] * width_of) + codes[1:]
    grid = numpy.bincount(pairs, minlength=width_of * width_of).astype(numpy.float64)
    total = grid.sum()
    return (grid / total) if total > 0 else None


def squashed(text, widths=WIDTHS):
    """The web read at every width at once, instead of at whichever single one was chosen.

    A width means different things in different languages. Thirty two codes put about a hundred Chinese
    characters in each and about two and a half Welsh ones, so two languages compared at one width are
    compared at two different resolutions and the finer of them carries more of the text in every cell.
    Reading every width and laying them end to end describes a language across resolutions, which is what
    the fields needed once it turned out no single scale was the right one.

    The widths are joined as they come. Every one of them already sums to one, being shares of a whole
    text, so what each level holds is conserved before anything is joined and rescaling them to a common
    length would throw that away: a coarse level would be made to weigh the same as a fine one when the
    difference between them is the reading.
    """
    parts = []
    for width in widths:
        codes, width_of = as_codes(text, width)
        values = web_of_codes(codes, width_of)
        if values is not None:
            parts.append(values)
    return numpy.concatenate(parts) if parts else None


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

    # Every width at once, which is the reading that does not require one to be chosen
    rows = []
    for language, label, text in loaded:
        values = squashed(text)
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

    # As a first pass its job is to narrow the field and not to name the answer, so what matters is
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
