#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Report the collision entropy of a corpus and the cut per anchor it predicts, for Section 4.4 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/collision_entropy.py corpus.sym [more.sym ...]
#
# Section 4.4 holds that an uninformed anchor admits candidates at a rate of $2^{-H_2}$, so a cascade of
# k anchors should leave $N 2^{-k H_2}$ of them and every anchor should cut by the same factor. That
# makes $2^{H_2}$ a prediction to check against a measured cut and not a quantity to fit.
#
# The entropy is computed from the symbol histogram alone, with no probing and no sampling, so it is
# independent of everything the anchor sweep measures.

import io
import math
import os
import sys


def collision_entropy(seats):
    """Renyi entropy of order two, from the histogram. -log2 of the collision probability."""
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    total = float(len(seats))
    collision = sum((count / total) ** 2 for count in counts.values())
    if collision <= 0.0:
        return None, None, len(counts)
    # The share held by the commonest symbol, since a low H2 is a concentrated distribution and the
    # usual cause of one here is layout: folding line endings to spaces gives a short lined file extra
    # spaces and pulls the whole distribution toward that one symbol
    top = max(counts.values()) / total
    return -math.log2(collision), 1.0 / collision, len(counts), top


def main():
    if len(sys.argv) < 2:
        print("usage: collision_entropy.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-32s %-8s %-10s %-9s %-9s %s\n"
              % ("corpus", "H2 bits", "cut 2^H2", "top sym", "symbols", "length"))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            out.write("  no corpus at %s\n" % path)
            continue
        with open(path, "rb") as handle:
            seats = handle.read()
        bits, cut, distinct, top = collision_entropy(seats)
        if bits is None:
            continue
        out.write("  %-32s %-8.3f %-10.2f %-9.3f %-9d %d\n"
                  % (os.path.basename(path)[:-4], bits, cut, top, distinct, len(seats)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
