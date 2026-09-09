#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# What each order of context predicts that the orders below it could not, and where the reading dies.
#
#   Usage:  from measure.block_entropy import block_entropy, increments, undersampling_error
#
# Separate from collision entropy, which is order two over single symbols and is what the cost model
# is denominated in. This is Shannon entropy over blocks, and it answers a different question:
# whether the information in a sequence closes at a finite order.
#
# Written as the decomposition it names, the question is exact. The entropy of a block of n symbols
# is the sum of n conditional entropies by the chain rule, each one what that order predicts that the
# orders below it could not, and the object closes if those increments reach zero. Nothing about that
# is an analogy.
#
# What fakes the result is the counting. A block of six symbols has more possible values than a text
# has positions, so most are seen once or never and an entropy estimated from counts like that is
# biased upward in a way that looks exactly like structure at every order.
#
# The correction that works is arithmetic and not another estimate. A shuffled text's symbols are
# independent by construction. A block of n of them therefore holds exactly n times the entropy of
# one, and the gap between that and what the estimator returns is the error itself, at every order,
# exactly. Subtracting a shuffled text's measured increments instead mixes the error with whatever
# the shuffle's own estimate did, and that was the earlier arrangement.
#
# Divided by the bins seen over the samples taken, an error made only of undersampling has to be one
# curve for every text. It is one curve through order four and the eight texts leave it together from
# order five, Thai earliest because Thai has the least text. So the estimator is sound through order
# four and outside its range from order five, and that boundary belongs to the arithmetic and not to
# any language.
#
# What can be said is that the information has not closed by order four and nothing here sees past
# it. The earlier claim that it closes at a finite depth is withdrawn and nothing replaces it.

import math

import numpy


def block_entropy(coded, order, width):
    """Shannon entropy of blocks of one length, in bits, from the counts of those blocks.

    `coded` is a sequence of integers below `width`. Returns None where the sequence is shorter than
    the order.
    """
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
    """What each order adds over the orders below it, in bits per symbol.

    The first entry is the entropy of one symbol and each later one is the difference between
    successive block entropies. That is the chain rule written out.
    """
    blocks = []
    for order in range(1, orders + 1):
        value = block_entropy(coded, order, width)
        if value is None:
            break
        blocks.append(value)
    if not blocks:
        return []
    return [blocks[0]] + [blocks[index] - blocks[index - 1] for index in range(1, len(blocks))]


def undersampling_error(coded, width, order, seed=0x51F7):
    """The estimator's error at one order, measured against a case whose answer is arithmetic.

    Shuffling the sequence makes its symbols independent, and the true block entropy is then exactly
    the order times the entropy of one symbol. Whatever the estimator returns above that is the
    error, and finding it needs no second estimate.

    Returns the error in bits, and the error divided by what pure undersampling predicts, namely
    (bins seen - 1) / (2 * samples * ln 2). If the error is only undersampling, that second number
    has to trace one curve across every text. A text leaving the curve means the reading has broken
    down, not that the language is unusual.
    """
    scattered = numpy.asarray(coded).copy()
    numpy.random.default_rng(seed).shuffle(scattered)

    shares = numpy.bincount(numpy.asarray(coded), minlength=width).astype(numpy.float64)
    shares = shares[shares > 0] / float(len(coded))
    single = float(-(shares * numpy.log2(shares)).sum())

    measured = block_entropy(scattered, order, width)
    if measured is None:
        return None, None

    placed = numpy.zeros(len(scattered) - order + 1, dtype=numpy.int64)
    for step in range(order):
        placed = (placed * width) + scattered[step:len(scattered) - order + 1 + step]
    seen = int((numpy.bincount(placed) > 0).sum())
    taken = float(len(placed))

    error = (order * single) - measured
    predicted = (seen - 1) / (2.0 * taken * math.log(2.0))
    return error, (error / predicted) if predicted > 0.0 else None
