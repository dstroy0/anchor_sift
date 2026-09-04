#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure the two channels a programming language does not need, across languages, for the symbol width
# discussion in Section 4.10 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/formal_layer.py corpus.txt [more.txt ...]
#
# A formal language states exactly what a machine requires of its text, so whatever else is present was
# put there by a person for another person. Two such channels are measurable without parsing anything.
#
#   case      the convention that an upper snake name is a macro and a lower snake name is a variable is
#             enforced by no compiler, and shows in how long the runs of capitals are
#   layout    a language that ignores its own whitespace carries indentation purely by convention, and
#             folding the line endings then changes the symbol distribution by a large amount
#
# The second channel has a control built into the sample. Some languages make layout part of the syntax:
# a recipe line in a makefile must begin with a tab, Haskell has a layout rule, and fixed form Fortran
# assigns meaning to columns. For those the whitespace is machine required and not a human layer, so if
# the reading above is right they should not behave like the languages that ignore it.

import io
import math
import os
import statistics
import sys


def collision_bits(text):
    counts = {}
    for character in text:
        counts[character] = counts.get(character, 0) + 1
    total = float(len(text))
    return -math.log2(sum((count / total) ** 2 for count in counts.values()))


def case_runs(text):
    runs = []
    current = 0
    for character in text:
        if character.isalpha() and character.isupper():
            current += 1
            continue
        if current > 0:
            runs.append(current)
            current = 0
    return runs


def indent_depths(text):
    """Leading whitespace on each line, which is the layout channel measured directly."""
    depths = []
    for line in text.splitlines():
        stripped = line.lstrip(" \t")
        if stripped:
            depths.append(len(line) - len(stripped))
    return depths


def main():
    if len(sys.argv) < 2:
        print("usage: formal_layer.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-22s %-9s %-9s %-9s %-9s %s\n"
              % ("corpus", "caps 3+", "fold dH2", "indent md", "indent sd", "tab lines"))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        if len(text) < 60000:
            continue

        runs = case_runs(text)
        caps = (sum(1 for value in runs if value >= 3) / len(runs)) if runs else float("nan")

        folded = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        shift = collision_bits(text) - collision_bits(folded)

        depths = indent_depths(text)
        median = statistics.median(depths) if depths else float("nan")
        spread = statistics.pstdev(depths) if len(depths) > 1 else float("nan")

        lines = text.splitlines()
        tabbed = (sum(1 for line in lines if line.startswith("\t")) / len(lines)) if lines else 0.0

        out.write("  %-22s %-9.3f %-9.3f %-9.1f %-9.2f %.3f\n"
                  % (os.path.basename(path)[:-4][:22], caps, shift, median, spread, tabbed))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
