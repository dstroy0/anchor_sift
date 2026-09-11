#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Collision entropy, and the quantities the cost model reads off it.
#
#   Usage:  from measure.entropy import collision_entropy, cut_per_anchor, cascade_depth
#
# One quantity does three jobs here. It sets the rate an uninformed anchor admits candidates, the
# distance at which a needle is refuted, and the size of the bias correction. None was derived from
# another and all three were measured independently.
#
# It is also the boundary of what this part can see. Collision entropy is computed from the symbol
# counts alone, so it is permutation invariant: a corpus and its own shuffle carry identical values,
# exactly and not approximately. No entropy of this order separates a structured domain from a
# rearrangement of the same symbols. The C bench measures that failing in the open, where a corpus of
# period sixteen survives four anchors at one alignment in sixteen while this predicts one in 65536.

import math

# Occurrences a symbol needs before its gaps are worth a statistic. Below this the estimate is a
# reading of the sample size.
MIN_OCCURRENCES = 32


def collision_entropy(seats):
    """Renyi entropy of order two, in bits, from the histogram alone.

    Returns the bits, the effective alphabet 2^H2, how many distinct symbols occur, and the share
    held by the commonest. That last one is worth carrying: a low reading is a concentrated
    distribution, and the usual cause of one here is layout, since folding line endings to spaces
    gives a short lined file extra spaces and pulls the whole distribution toward that one symbol.

    Returns (None, None, count, share) where the corpus is empty.
    """
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    if not counts:
        return None, None, 0, 0.0

    total = float(len(seats))
    collision = sum((count / total) ** 2 for count in counts.values())
    if collision <= 0.0:
        return None, None, len(counts), 0.0

    top = max(counts.values()) / total
    return -math.log2(collision), 1.0 / collision, len(counts), top


def cut_per_anchor(bits):
    """How many alignments one anchor removes for each one it keeps, which is 2^H2."""
    return 2.0 ** bits


def uninformed_rate(bits, anchors=1):
    """Share of alignments surviving a cascade of anchors that read nothing about the needle.

    This is the maximum entropy case and therefore a floor: a filter selecting on symbol rarity reads
    only the marginals, so an arrangement can add correlated hits and cannot make the marginals more
    informative than independence already makes them. Structure only makes this filter worse, never
    better.
    """
    return 2.0 ** (-bits * anchors)


def cascade_depth(corpus_len, bits):
    """How many anchors bring the expected survivors down to the one true occurrence.

    Each anchor cuts by 2^-H2, so k of them leave N 2^(-k H2) and the excess reaches zero at
    log2(N) / H2. On English at N = 728751 that predicts 4.9, and the measured sweep reaches 0.5
    survivors at six anchors and 0.0 at seven.
    """
    if bits <= 0.0:
        return float("inf")
    return math.log2(corpus_len) / bits
