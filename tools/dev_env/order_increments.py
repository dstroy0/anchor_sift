#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether the information in a text is a sum over orders that does not close, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/order_increments.py
#
# Saying the object is all orders at once is loose until it is written as the decomposition it names. The
# information in a sequence splits exactly, by the chain rule: the entropy of a block of n symbols is the
# sum of n conditional entropies, one for each order, and each one is what that order predicts that the
# orders below it could not. Nothing about that is an analogy, it is an identity.
#
# The claim then has a shape that can fail. If those increments fall to zero at some order, the text is
# held by a finite context and everything past it is decoration. If they keep falling without reaching
# zero, no finite order holds it and the sum over orders is the object.
#
# What would fake the result is the counting itself. A block of six symbols has more possible values than
# a text has positions, so most are seen once or never, and an entropy estimated from counts like that is
# biased upward in a way that looks exactly like structure at every order. The same text with its symbols
# shuffled has the same alphabet, the same frequencies, the same length and no structure beyond one
# symbol, so it carries the identical bias and none of the signal. Every number here is reported against
# it, and the difference is what the text holds that the shuffle does not.

import io
import math
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

# Taken as large as the texts allow. The first run capped at 400000 characters while several of these
# hold millions, and the increments went negative at order seven, which is impossible for a real
# increment and is the mark of counting blocks that were mostly never seen. Ten times the characters
# buys about one more order before that floor is reached.
CAP = 6000000
LEAST = 400000
# Held small on purpose: the count of possible blocks is this raised to the order, and an alphabet of 64
# at order 5 has more blocks than any text here has characters
RANKS = 12
ORDERS = 8
SEED = 0x51F7

WANTED = (
    ("vietnamese", "para_vietnamese.txt"),
    ("arabic, the original", "source_arabic.txt"),
    ("urdu", "para_urdu.txt"),
    ("persian", "para2_persian.txt"),
    ("russian", "para2_russian.txt"),
    ("turkish", "para2_turkish.txt"),
    ("indonesian", "para_indonesian.txt"),
    ("thai", "para2_thai.txt"),
)


def block_entropy(coded, order, width):
    """Entropy of blocks of one length, in bits, from the counts of those blocks."""
    if len(coded) <= order:
        return None
    placed = numpy.zeros(len(coded) - order + 1, dtype=numpy.int64)
    for step in range(order):
        placed = (placed * width) + coded[step:len(coded) - order + 1 + step]
    counts = numpy.bincount(placed).astype(numpy.float64)
    counts = counts[counts > 0]
    shares = counts / counts.sum()
    return float(-(shares * numpy.log2(shares)).sum())


def increments(coded, width, orders):
    """What each order predicts that the orders below it could not, in bits per symbol."""
    blocks = []
    for order in range(1, orders + 1):
        value = block_entropy(coded, order, width)
        if value is None:
            break
        blocks.append(value)
    return [blocks[0]] + [blocks[index] - blocks[index - 1] for index in range(1, len(blocks))]


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  each cell is what that order adds, in bits per symbol, over what the shuffle adds\n\n")
    header = "  ".join("%7s" % ("order %d" % (order + 1)) for order in range(ORDERS))
    out.write("  %-22s %-9s %s\n" % ("text", "symbols", header))

    for label, name in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-22s not present\n" % label)
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            out.write("  %-22s too short\n" % label)
            continue

        counts = {}
        for symbol in text:
            counts[symbol] = counts.get(symbol, 0) + 1
        ranked = sorted(counts, key=lambda symbol: -counts[symbol])[:RANKS - 1]
        seat = {symbol: place for place, symbol in enumerate(ranked)}
        # Everything past the kept ranks becomes one symbol, so the alphabet is exactly RANKS wide
        coded = numpy.asarray([seat.get(symbol, RANKS - 1) for symbol in text], dtype=numpy.int64)

        live = increments(coded, RANKS, ORDERS)
        scattered = coded.copy()
        numpy.random.default_rng(SEED).shuffle(scattered)
        dead = increments(scattered, RANKS, ORDERS)

        row = []
        for index in range(min(len(live), len(dead))):
            row.append("%7.4f" % (dead[index] - live[index]))
        out.write("  %-22s %-9d %s\n" % (label, len(coded), "  ".join(row)))

    out.write("\n  a cell near zero means that order adds nothing the shuffle does not\n")
    out.write("  a cell staying above zero means the text is still not held at that order\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
