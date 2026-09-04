#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Look at what is actually in these files before theorizing about them again, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/drav_inventory.py
#
# Malayalam carries 524 distinct codepoints in the same length of text where Tamil carries 149, and that
# difference is doing the damage: the two closest languages in the family read as the widest apart. Three
# explanations were proposed for it and all three failed. Aligning the scripts moved nothing, which it
# could not have, since the reading ranks by frequency and never sees a codepoint. Reading whole clusters
# made it worse. Folding the aspirate and voiced stops onto their plain forms, which is the distinction
# set Tamil script keeps, removed 67 symbols of 524 and left the rest standing.
#
# That last number is the point. If the surplus were Sanskrit consonants, folding them would have taken
# most of it. It took an eighth. So the surplus is something else and it has not been looked at, which is
# the step that should have come first and did not.
#
# This counts what is there by script and by category, and prints the commonest symbols that Tamil does
# not use, so the difference is read off the files and not guessed at a fourth time.

import io
import os
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 480000


def family_of(symbol):
    """Which writing a character belongs to, by the name Unicode gives it."""
    try:
        name = unicodedata.name(symbol)
    except ValueError:
        return "unnamed"
    return name.split(" ")[0]


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
            continue
        held[language] = text[:SAME_LENGTH]

    out.write("  what each file is made of, by share of its characters\n")
    out.write("  %-12s %-8s %-30s %s\n" % ("language", "distinct", "its own script", "everything else"))
    for language in sorted(held):
        text = held[language]
        counts = {}
        for symbol in text:
            counts[family_of(symbol)] = counts.get(family_of(symbol), 0) + 1
        total = float(len(text))
        ordered = sorted(counts.items(), key=lambda pair: -pair[1])
        own = ordered[0][1] / total if ordered else 0.0
        others = "  ".join("%s %.3f" % (part, count / total) for part, count in ordered[1:5])
        out.write("  %-12s %-8d %-30s %s\n"
                  % (language, len(set(text)), "%s %.3f" % (ordered[0][0], own), others))

    if ("malayalam" in held) and ("tamil" in held):
        out.write("\n  the commonest symbols in malayalam, with what each is\n")
        counts = {}
        for symbol in held["malayalam"]:
            counts[symbol] = counts.get(symbol, 0) + 1
        ordered = sorted(counts, key=lambda symbol: -counts[symbol])
        shown = 0
        for symbol in ordered:
            if symbol.isspace():
                continue
            try:
                name = unicodedata.name(symbol)
            except ValueError:
                name = "unnamed"
            out.write("      %-8s %-9d %-6s %s\n"
                      % (hex(ord(symbol)), counts[symbol], unicodedata.category(symbol), name[:58]))
            shown += 1
            if shown >= 22:
                break

        out.write("\n  how many of malayalam's distinct symbols are of each category\n")
        by_kind = {}
        for symbol in set(held["malayalam"]):
            by_kind[unicodedata.category(symbol)] = by_kind.get(unicodedata.category(symbol), 0) + 1
        for kind, count in sorted(by_kind.items(), key=lambda pair: -pair[1]):
            out.write("      %-6s %d\n" % (kind, count))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
