#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Count constructs whose two halves sit at a variable distance, for the symbol width discussion in
# Section 4.10 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/bracket_pairs.py corpus.txt [more.txt ...]
#
# slice a corpus at one symbol per byte assumes the meaningful unit is a byte. A programming language
# breaks that in a way prose does not: a conditional expression is written with its two halves apart,
# and the distance between them is whatever the middle expression happens to be. So the construct is one
# unit at a separation the slice cannot see, and the two halves appear as unrelated symbols.
#
# Reported here is how much of a source file is made of such constructs and how far apart their halves
# sit, since a correlation at a variable distance is exactly what a product of marginals cannot model
# and what a permutation null does detect.

import io
import os
import statistics
import sys

# Opening and closing halves that a byte slice separates
PAIRS = (("?", ":"), ("(", ")"), ("{", "}"), ("[", "]"))


def spans(text, opener, closer, limit=4000):
    """Distances from each opener to the next closer, which is a lower bound on the true nesting."""
    out = []
    at = 0
    while True:
        start = text.find(opener, at)
        if start < 0:
            break
        stop = text.find(closer, start + 1)
        if stop < 0:
            break
        if (stop - start) <= limit:
            out.append(stop - start)
        at = start + 1
    return out


def main():
    if len(sys.argv) < 2:
        print("usage: bracket_pairs.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()

        out.write("%s, %d bytes\n" % (os.path.basename(path), len(text)))
        out.write("  %-8s %-9s %-11s %-11s %s\n"
                  % ("pair", "count", "median gap", "mean gap", "share of bytes"))
        for opener, closer in PAIRS:
            gaps = spans(text, opener, closer)
            if not gaps:
                continue
            out.write("  %-8s %-9d %-11.1f %-11.1f %.3f%%\n"
                      % (opener + closer, len(gaps), statistics.median(gaps),
                         statistics.fmean(gaps), 100.0 * 2 * len(gaps) / len(text)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
