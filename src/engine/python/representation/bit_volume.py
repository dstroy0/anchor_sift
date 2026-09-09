#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Any corpus as points in a binary volume, with no dimension assigned to it.
#
#   Usage:  from representation.bit_volume import gray_bits, spectrum_gap, spectrum_excess
#
# The first attempt at one instrument for every domain gave each domain a dimension: a line for
# text, a plane for a picture, a space for a structure. That was the defect. Choosing a picture's
# width means choosing a geometry and then measuring the choice, and it showed: reshaping at a wrong
# width shears the rows into diagonals, an orientation tensor scores a shear highest, and the sweep
# returned the height every time while the shift detector returned the width correctly.
#
# A cloud of points carries no dimension to assign. What every corpus already is, with nothing
# chosen for it, is bits. Each symbol is Gray coded before it is expanded, so two values one apart
# differ in one bit and distance in the volume means what distance in the alphabet meant. A window
# of n bits slid along the stream is a point in binary n space, and n is swept instead of guessed.
#
# The sum over n does not converge, and the divergence is the result: every arranged corpus is still climbing
# at 64 bits, the widest measured. A ceiling would therefore decide the total, so the quantity that
# does not depend on one is the exponent of the growth. The memoryless corpora are the control,
# since an estimated correlation matrix grows lopsided with its size on its own, and that bias would
# lift every corpus alike. It lifts none of them.

import math

import numpy

# Windows sampled at one width, where taking every position would be quadratic in the corpus.
WINDOWS = 40000

# The width the recorded figures were read at, and the seed they were taken with.
WIDTH = 32
SEED = 0x51F7


def gray_bits(values):
    """Gray code the symbols, then lay them out as one stream of bits."""
    coded = (values ^ (values >> 1)).astype(numpy.uint8)
    return numpy.unpackbits(coded)


def spectrum_gap(bits, width, rng):
    """How far the bit correlation spectrum sits from the even one, at one window width.

    Summing the window vectors straight gives the per bit marginals and throws away how the bits
    move together. Summing them as outer products instead gives the correlation of the n bit
    positions. Even spread is the largest entropy over that many bits, so the shortfall from it is
    the departure. Returns None where the window leaves too few live bits to correlate.
    """
    usable = len(bits) - width
    if usable < (4 * width):
        return None

    starts = numpy.arange(usable) if usable <= WINDOWS else rng.choice(usable, WINDOWS, replace=False)
    windows = bits[starts[:, None] + numpy.arange(width)[None, :]].astype(numpy.float32)

    centered = windows - windows.mean(axis=0, keepdims=True)
    spread = centered.std(axis=0)
    # A bit that never changes carries no correlation and would divide by zero
    alive = spread > 1e-6
    if int(alive.sum()) < 3:
        return None

    centered = centered[:, alive] / spread[alive]
    correlation = (centered.T @ centered) / float(len(centered))

    eigenvalues = numpy.linalg.eigvalsh(correlation)
    eigenvalues = numpy.clip(eigenvalues, 1e-12, None)
    eigenvalues = eigenvalues / eigenvalues.sum()
    entropy = -float((eigenvalues * numpy.log2(eigenvalues)).sum())
    return math.log2(len(eigenvalues)) - entropy


def spectrum_excess(values, width=WIDTH, seed=SEED):
    """The gap a corpus opens over its own permuted null, at one window width.

    Three readings carried a private copy of this, which is three places for the width or the seed
    to drift. The shuffle keeps every symbol frequency and destroys every arrangement, so what is
    left is the arrangement and cannot be the counts.

    Returns None where either arm leaves too few live bits to correlate.
    """
    live = spectrum_gap(gray_bits(values), width, numpy.random.default_rng(seed))
    shuffled = values.copy()
    numpy.random.default_rng(seed).shuffle(shuffled)
    dead = spectrum_gap(gray_bits(shuffled), width, numpy.random.default_rng(seed))
    if (live is None) or (dead is None):
        return None
    return live - dead


def load_symbols(path, cap, as_text=False):
    """A corpus as one byte per symbol, from a byte file or a text one.

    A text file is re-seated to give each distinct character one byte, the only width a logographic
    script survives. Line endings are folded, as everywhere here, keeping a publisher's wrapping out
    of the measurement.
    """
    if as_text:
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(cap)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        seating = {}
        for character in text:
            if character not in seating:
                seating[character] = len(seating) & 0xFF
        return numpy.asarray([seating[character] for character in text], dtype=numpy.uint8)

    with open(path, "rb") as handle:
        return numpy.frombuffer(handle.read(cap), dtype=numpy.uint8)
