#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-4-001
#
# What one anchor costs, read off the histogram alone.
#
#   Usage:  python examples/any_corpus/4_measure/collision_entropy.py corpus.sym [more.sym ...]
#
# An uninformed anchor admits candidates at a rate of 2^-H2. A cascade of k of them should leave
# N 2^(-k H2), and every anchor should cut by the same factor. That makes 2^H2 a prediction to check
# against a measured cut and never a quantity to fit.
#
# The entropy is computed from the symbol histogram with no probing and no sampling, so it is
# independent of everything an anchor sweep measures. Checked against a four anchor sweep on English,
# the histogram gives 3.764 bits and the sweep backs out 3.735, which agree to 0.8 percent, and a
# single histogram number carries four orders of magnitude of survivors to within 21 percent.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.entropy import cascade_depth, collision_entropy  # noqa: E402


def main():
    if len(sys.argv) < 2:
        print("usage: collision_entropy.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-32s %-8s %-10s %-9s %-9s %-9s %s\n"
              % ("corpus", "H2 bits", "cut 2^H2", "top sym", "symbols", "depth", "length"))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            out.write("  no corpus at %s\n" % path)
            continue
        with open(path, "rb") as handle:
            seats = handle.read()

        bits, cut, distinct, top = collision_entropy(seats)
        if bits is None:
            continue
        out.write("  %-32s %-8.3f %-10.2f %-9.3f %-9d %-9.2f %d\n"
                  % (os.path.basename(path)[:-4], bits, cut, top, distinct,
                     cascade_depth(len(seats), bits), len(seats)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
