#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Backgrounds built out of the data by removing one property.
#
#   Usage:  from reference.shuffles import permuted, block_shuffled, scrambled_within
#
# The results in this work that held were measured against a background built by deleting something
# from the data itself. Such a background cannot be wrong about the property it removes, because it
# is the same data with that property gone. The results that failed were measured against a
# background that was assumed: the product rule assumed independence, the Zipf reading assumed a
# memoryless process would not reproduce it, the frequent half comparison assumed corpus length did
# not enter.
#
# Drawing uniformly from the arrangements of a fixed multiset is the least committal distribution
# consistent with the observed histogram, so it asserts nothing beyond the quantity already
# measured. That is Jaynes's principle reached from the permutation side, and it is why this one
# background cannot be wrong while every model can.
#
# The three here are graded, each deleting a different amount. A full permutation destroys every
# arrangement at once and cannot say which span the structure lives at. A block shuffle keeps every
# arrangement shorter than the block and destroys every one longer, and a sweep of the block width
# then locates where a measure's
# signal sits. Scrambling inside blocks does the reverse: it keeps how the composition drifts from
# one part of a text to another and destroys only the order, which separates a dependency reaching
# across a text from the text simply changing subject.

import random

# The seed the recorded figures were taken at.
SEED = 0x51F7


def permuted(seats, seed=SEED):
    """The same symbols in a uniformly drawn order, which preserves every count exactly.

    This and a memoryless source are not the same object and the difference is finite sample. A
    shuffle fixes the counts exactly and makes the positions exchangeable; a memoryless source fixes
    them only in expectation. The two agree in the limit.
    """
    out = bytearray(seats)
    random.Random(seed).shuffle(out)
    return out


def block_shuffled(seats, span, seed=SEED):
    """Blocks of `span` symbols reordered, each block keeping its own order.

    Every arrangement shorter than the span survives and every arrangement longer than it is
    destroyed. A word boundary recurs every few symbols and should return at a small span; a rare
    symbol clusters because a passage is about the thing it names, which is an arrangement spanning
    a passage, and should need a much larger one.
    """
    blocks = [seats[start:start + span] for start in range(0, len(seats), span)]
    random.Random(seed).shuffle(blocks)

    out = bytearray()
    for block in blocks:
        out.extend(block)
    return out


def scrambled_within(seats, span, seed=SEED):
    """Symbols reordered inside each block, so every block keeps exactly the symbols it held.

    How the corpus drifts from block to block survives untouched and nothing inside a block follows
    anything for a reason. This is the null that answers whether a long match is a real
    dependency or a page sharing vocabulary with the page before it, and the concern turns out to be
    sound and worth little at character width: letter frequencies barely move within a book. At
    word level it would be worth more.
    """
    rng = random.Random(seed)
    out = bytearray()
    for start in range(0, len(seats), span):
        chunk = list(seats[start:start + span])
        rng.shuffle(chunk)
        out.extend(chunk)
    return out
