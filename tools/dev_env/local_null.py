#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Separate dependency at distance from a text simply changing subject, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/local_null.py
#
# Matching against a growing window found every text still gaining on its shuffle at 262144 characters,
# and that was recorded as structure reaching that far. The null it was measured against is wrong for the
# question.
#
# Shuffling a whole text destroys two things at once. It destroys every sequential dependency, which is
# what was wanted. It also destroys the fact that a book is not one distribution: chapters change
# vocabulary, characters speak differently from the narrator, an argument moves from one subject to
# another. Entropy is concave, so a single pooled distribution over a whole book has more entropy than
# the book's parts have on average, and shuffling the whole book measures against that inflated figure.
# A matcher then finds long matches near each position simply because a page shares vocabulary with the
# page before it, and that is the book changing subject, not a dependency reaching across it.
#
# The null that answers the question keeps the composition and destroys only the order. Symbols are
# shuffled inside blocks, so every block holds exactly the letters it held before in a scrambled order,
# and how the text drifts from block to block survives untouched. What still separates the text from that
# is dependency. What does not was drift.
#
# The block size is swept, because a block is a claim about the distance at which composition stops
# changing and that is not known in advance.

import io
import math
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 2000000
LEAST = 400000
WINDOW = 65536
BLOCKS = (256, 2048, 16384)
SAMPLES = 1200
LONGEST = 300
SEED = 0x51F7

WANTED = (
    ("vietnamese", "para_vietnamese.txt"),
    ("arabic, the original", "source_arabic.txt"),
    ("urdu", "para_urdu.txt"),
    ("russian", "para2_russian.txt"),
    ("indonesian", "para_indonesian.txt"),
)


def scramble_within(text, block, rng):
    """The same text with the letters inside each block put in another order.

    Every block keeps exactly the letters it had, so how the text drifts from one part to another is
    untouched, and nothing inside a block follows anything for a reason any more.
    """
    pieces = []
    for start in range(0, len(text), block):
        chunk = list(text[start:start + block])
        rng.shuffle(chunk)
        pieces.append("".join(chunk))
    return "".join(pieces)


def rate(series, window, rng):
    """Bits per symbol, from how long a string must be before the window behind it has not seen it."""
    if len(series) < (window * 3):
        return None
    picked = rng.integers(window, len(series) - LONGEST, size=SAMPLES)
    lengths = []
    for start in picked:
        start = int(start)
        behind = series[start - window:start]
        low = 0
        high = 1
        while (high < LONGEST) and (series[start:start + high] in behind):
            low = high
            high *= 2
        high = min(high, LONGEST)
        while low + 1 < high:
            middle = (low + high) // 2
            if series[start:start + middle] in behind:
                low = middle
            else:
                high = middle
        lengths.append(low + 1)
    average = float(numpy.mean(lengths))
    return (math.log2(window) / average) if average > 0 else None


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  bits per symbol at a window of %d, against nulls that keep more and more\n\n" % WINDOW)
    out.write("  %-22s %-9s %-11s %s\n"
              % ("text", "as written", "shuffled", "  ".join("%-11s" % ("in %d" % block)
                                                             for block in BLOCKS)))

    import random
    for label, name in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-22s not present\n" % label)
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue

        here = rate(text, WINDOW, numpy.random.default_rng(SEED))
        whole = list(text)
        numpy.random.default_rng(SEED).shuffle(whole)
        flat = rate("".join(whole), WINDOW, numpy.random.default_rng(SEED))

        row = []
        for block in BLOCKS:
            kept = scramble_within(text, block, random.Random(SEED))
            value = rate(kept, WINDOW, numpy.random.default_rng(SEED))
            row.append("%-11.4f" % value if value is not None else "%-11s" % "short")
        out.write("  %-22s %-9.4f %-11.4f %s\n" % (label, here, flat, "  ".join(row)))
        out.flush()

    out.write("\n  the shuffled column destroys order and composition together\n")
    out.write("  the block columns keep the composition and destroy only the order\n")
    out.write("  a text near its block columns was never reaching across that distance\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
