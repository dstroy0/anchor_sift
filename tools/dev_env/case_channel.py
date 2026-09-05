#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure letter case as a channel, for the symbol width discussion in Section 4.10 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/case_channel.py corpus.txt [more.txt ...]
#
# A byte slice keeps upper and lower case as separate symbols and treats them as unrelated, which is
# right for prose and loses something in a source file. In C the case of an identifier is what says
# which kind of thing it is: an upper snake name is a macro, a leading capital is a type, a lower snake
# name is a variable. So case is a second channel carried on the same symbols, and it is legible from
# the run lengths alone without knowing any identifier.
#
# Prose uses a capital at the start of a sentence and inside a name, so its runs are almost all of
# length one. A language that names macros in upper case has long runs, and the distribution separates
# the two without reading a word.

import io
import os
import statistics
import sys


def case_runs(text):
    """Lengths of maximal runs of upper case letters."""
    runs = []
    current = 0
    for character in text:
        if character.isalpha() and character.isupper():
            current += 1
            continue
        if current > 0:
            runs.append(current)
            current = 0
    if current > 0:
        runs.append(current)
    return runs


def main():
    if len(sys.argv) < 2:
        print("usage: case_channel.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-8s %-9s %-9s %-9s %s\n"
              % ("corpus", "runs", "share 1", "share 3+", "median", "longest"))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        runs = case_runs(text)
        if len(runs) < 20:
            continue
        singles = sum(1 for value in runs if value == 1) / len(runs)
        longs = sum(1 for value in runs if value >= 3) / len(runs)
        out.write("  %-26s %-8d %-9.3f %-9.3f %-9.1f %d\n"
                  % (os.path.basename(path)[:-4], len(runs), singles, longs,
                     statistics.median(runs), max(runs)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
