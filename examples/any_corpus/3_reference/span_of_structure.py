#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Which span a measure's signal lives at, by varying how much the background destroys.
#
#   Usage:  python examples/any_corpus/3_reference/span_of_structure.py corpus.sym [more.sym ...]
#
# The null used everywhere else shuffles single symbols, which preserves how often each symbol
# occurs and destroys every arrangement at once. That cannot say which span the structure lives at.
#
# Cutting the corpus into blocks of B symbols and shuffling the blocks keeps every arrangement
# shorter than B and destroys every arrangement longer than it. Varying B says where the signal
# sits. A word boundary recurs every few symbols and should return at a small B. A rare symbol
# clusters because a passage is about the thing it names, which is an arrangement spanning a
# passage, so it should need a much larger one.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.dispersion import dispersion_by_symbol, halves  # noqa: E402
from reference.shuffles import block_shuffled  # noqa: E402

SPANS = (1, 8, 32, 128, 512, 2048, 8192)


def main():
    if len(sys.argv) < 2:
        print("usage: span_of_structure.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            out.write("  no corpus at %s\n" % path)
            continue
        with open(path, "rb") as handle:
            seats = bytearray(handle.read())

        out.write("%s\n" % os.path.basename(path))
        out.write("  %-10s %-10s %-10s %s\n" % ("block", "head", "tail", "keeps"))
        for span in SPANS:
            null = dispersion_by_symbol(block_shuffled(seats, span))
            head, tail = halves(seats, null)
            if head is None:
                continue
            out.write("  %-10d %-10.4f %-10.4f everything shorter than %d\n"
                      % (span, head, tail, span))
        out.write("\n")

    out.write("  a block of one destroys every arrangement, which is the plain permutation null\n")
    out.write("  the span where the reading returns to that value is where its signal lives\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
