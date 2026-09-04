#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find formatting damage by matching case-sensitively against a corpus known to be right.
#
#   Usage:  python tools/dev_env/case_delta.py
#
# Case carries meaning. Essen capitalized mid-sentence is not essen, and none of these orthographies
# capitalizes at random either: a capital in the middle of a word is labialization in one paper's
# convention, a glottal stop in another's damaged font, and a sentence boundary in neither.
#
# So match twice. A token that the pure corpus holds exactly is right. A token the pure corpus holds
# only once case is folded away is the same word written wrong, and the difference between the two
# counts is the formatting damage in a paper, measured and not guessed at.
#
# This needs the oracle to be true, which is why it runs against the .pure.txt files and not against
# the papers. Those came out of nine readers written line by line against nine layouts.

import glob
import io
import os
import sys

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
CORPORA = os.path.join(ROOT, "build", "corpora")
SIFTED = os.path.join(CORPORA, "sifted")

EDGES = ".,!?;:“”‘’\"'()[]…«»{}"


def pure_vocabulary():
    """Every word form the hand-read corpora hold, kept as written and folded."""
    exact = set()
    folded = {}
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                for token in line.split():
                    plain = token.strip(EDGES)
                    if len(plain) < 2:
                        continue
                    exact.add(plain)
                    folded.setdefault(plain.casefold(), set()).add(plain)
    return exact, folded


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    exact, folded = pure_vocabulary()
    if not exact:
        out.write("  no pure corpus to match against, run the nine readers first\n")
        out.flush()
        return 1
    out.write("  oracle: %d forms, %d once case is folded\n" % (len(exact), len(folded)))

    rows = []
    shown = []
    for path in sorted(glob.glob(os.path.join(SIFTED, "*.sifted.tsv"))):
        right = 0
        wrong = 0
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("#") or line.startswith("page\t"):
                    continue
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 5:
                    continue
                for token in parts[4].split():
                    plain = token.strip(EDGES)
                    if len(plain) < 2:
                        continue
                    if plain in exact:
                        right += 1
                        continue
                    others = folded.get(plain.casefold())
                    if others:
                        wrong += 1
                        if len(shown) < 16:
                            shown.append((plain, sorted(others)[0],
                                          os.path.basename(path)[:-11]))
        if right or wrong:
            rows.append((wrong, right, os.path.basename(path)[:-11]))

    rows.sort(reverse=True)
    out.write("\n  %-44s %-10s %s\n" % ("paper", "as written", "wrong case"))
    for wrong, right, stem in rows[:16]:
        out.write("  %-44s %-10d %d\n" % (stem[:44], right, wrong))

    out.write("\n  %d papers share a form with the oracle, %d forms match as written, "
              "%d only once case is folded\n"
              % (len(rows), sum(one[1] for one in rows), sum(one[0] for one in rows)))
    if shown:
        out.write("\n  what the case match caught\n")
        for got, want, stem in shown:
            out.write("    %-22s the oracle writes %-22s %s\n" % (got, want, stem[:34]))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
