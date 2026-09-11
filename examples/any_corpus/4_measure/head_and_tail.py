#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-4-002
#
# The null permutation ratio for every symbol, so the head and the tail can be compared directly.
#
#   Usage:  python examples/any_corpus/4_measure/head_and_tail.py corpus.sym [more.sym ...]
#
# The boundary detector in the bench returns one symbol, the one whose gaps are most regular, and it
# rejects any candidate occurring less often than once in 64 symbols. That rejection can only ever
# return a frequent symbol, so every result it has produced describes the head of the distribution.
#
# Under a Zipf distribution the head carries the token count and the tail carries the information,
# since the surprisal of a symbol is -log p and the many rare symbols each contribute more of it.
# This reads every symbol instead of one, so the two halves can be set beside each other.

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
from reference.shuffles import permuted  # noqa: E402


def main():
    if len(sys.argv) < 2:
        print("usage: head_and_tail.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-32s %-10s %-10s %-9s %s\n"
              % ("corpus", "head", "tail", "scored", "what it means"))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            out.write("  no corpus at %s\n" % path)
            continue
        with open(path, "rb") as handle:
            seats = bytearray(handle.read())

        head, tail = halves(seats)
        if head is None:
            out.write("  %-32s too few symbols cleared the occurrence floor\n"
                      % os.path.basename(path)[:-4])
            continue

        scored = len(dispersion_by_symbol(seats))
        note = "at the null" if abs(tail - 1.0) < 0.02 else (
            "clustered" if tail < 1.0 else "more even than chance")
        out.write("  %-32s %-10.4f %-10.4f %-9d %s\n"
                  % (os.path.basename(path)[:-4], head, tail, scored, note))

    out.write("\n  a memoryless corpus returns 1.00 on both, because its distance from the\n")
    out.write("  reference is zero by construction. Natural text returns 0.48 to 0.76 on the tail\n")
    out.write("  and the head is not comparable between corpora of different lengths\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
