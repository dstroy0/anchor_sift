#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Which symbol follows which, as a square over frequency ranks.
#
#   Usage:  from measure.web import web, leave_one_out
#
# Four scalars were tested for whether they pick a language out of 28 and the best reached 24.5
# percent against 3.6 for guessing. That was the wrong shape of thing to test. A scalar summarizes
# the alphabet and discards the context, and the context is which symbol follows which, which is a
# square over the alphabet and not one number.
#
# Positions are frequency ranks and not code points, so the same position means the same thing in
# every language: whatever a text uses most sits first. That makes a Greek square and a Japanese one
# comparable without either being translated.
#
# This is the single most depended on module in the tree, at 32 importers, and it spent part of its
# life filed under examples while the tooling imported it. A worked example is not a dependency.

import numpy


def web(text, ranks):
    """Share of the time the symbol at one rank is followed by the symbol at another.

    Anything past the rank cutoff is dropped, which keeps a language with thousands of symbols
    comparable to one with eighty. The cells are held as shares of the whole square, keeping a
    longer text from reading as a different language.

    Returns None where the text carries no transitions at all.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ordered = sorted(counts, key=lambda symbol: -counts[symbol])[:ranks]
    seat = {symbol: place for place, symbol in enumerate(ordered)}

    grid = numpy.zeros((ranks, ranks), dtype=numpy.float64)
    previous = None
    for symbol in text:
        place = seat.get(symbol)
        if (place is not None) and (previous is not None):
            grid[previous, place] += 1.0
        previous = place

    total = grid.sum()
    if total <= 0.0:
        return None
    return (grid / total).reshape(-1)


def web_of_codes(codes, width_of):
    """The web over codes from a shared alphabet, where the codes are already integers.

    `codes` and `width_of` come from `representation.text.shared_alphabet.as_codes`. Returns None
    where the sequence is too short for the square to hold anything.
    """
    if len(codes) < (4 * width_of * width_of):
        return None
    pairs = (codes[:-1] * width_of) + codes[1:]
    grid = numpy.bincount(pairs, minlength=width_of * width_of).astype(numpy.float64)
    total = grid.sum()
    return (grid / total) if total > 0.0 else None


def squashed(text, as_codes, widths):
    """The web read at every code width at once, instead of at whichever single one was chosen.

    A width means different things in different languages. Thirty two codes hold about a hundred
    Chinese characters each and about two and a half Welsh ones, so two languages compared at one
    width are compared at two resolutions and only one of them is fine.

    Reading every width and laying them end to end takes identification from 40.0 to 45.7 percent
    and the nearest eight from 73.3 to 76.2, closing the gap to the characters from 12.8 points to
    7.1. It does not fix the families, which stay at 8 of 22.

    The widths are joined as they come. Each already sums to one, being shares of a whole text, so
    what each level holds is conserved before anything is joined. Rescaling them to a common length
    was tried and is wrong: it makes a coarse level weigh the same as a fine one, when the
    difference between them is the reason for reading several in the first place.
    """
    parts = []
    for width in widths:
        codes, width_of = as_codes(text, width)
        values = web_of_codes(codes, width_of)
        if values is not None:
            parts.append(values)
    return numpy.concatenate(parts) if parts else None


def marginal(text, ranks):
    """How often each symbol is used, and nothing about what follows what.

    The web with its structure removed, which makes it the comparison that decides whether the
    transitions are worth having. Measured over four questions, reading how often each character is
    used comes within three points of the whole square on three of them and beats it on the fourth.
    So most of what the square carries, the frequencies carry.

    Always the full width, with zeros past the symbols a text holds. A text using fifty characters
    would otherwise return fifty numbers where another returns sixty four, and the two could not be
    compared at all.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ordered = sorted(counts, key=lambda symbol: -counts[symbol])[:ranks]

    total = float(sum(counts[symbol] for symbol in ordered))
    if total <= 0.0:
        return None

    values = numpy.zeros(ranks, dtype=numpy.float64)
    for place, symbol in enumerate(ordered):
        values[place] = counts[symbol] / total
    return values


def deep_web(text, orders):
    """Which run of symbols follows which, at several lengths, laid end to end.

    `orders` is a sequence of (order, ranks) pairs. The alphabet narrows as the order grows because
    the count of cells is the ranks raised to the order, and 64 symbols at order four is sixteen
    million. That trades breadth for depth deliberately.

    Why the depth is worth reaching for. The plain web holds 4096 numbers standing in for a whole
    language, and everything else is discarded: every dependency longer than one symbol, the entire
    tail of the alphabet past rank 64, where a symbol sits inside a word, and all word and morpheme
    structure. The seven percent margin by which a language beats its own source is what remains
    after all that, and it is not a measure of what a language is worth.

    Every order emits its full width whether or not the text fills it. A text short of symbols at
    one order would otherwise return a shorter reading than another text and the two could not be
    compared. An order the text cannot support comes back as zeros, reporting honestly that the text
    holds none of those runs.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ranked = sorted(counts, key=lambda symbol: -counts[symbol])

    parts = []
    for order, ranks in orders:
        width = ranks ** order
        seat = {symbol: place for place, symbol in enumerate(ranked[:ranks])}
        coded = numpy.asarray([seat.get(symbol, -1) for symbol in text], dtype=numpy.int64)
        keep = coded >= 0

        # A run counts only where every symbol in it is inside the kept ranks
        placed = numpy.zeros(len(coded), dtype=numpy.int64)
        alive = numpy.ones(len(coded), dtype=bool)
        for step in range(order):
            shifted = numpy.roll(coded, -step)
            alive &= numpy.roll(keep, -step)
            placed = (placed * ranks) + numpy.where(shifted >= 0, shifted, 0)
        placed = placed[:len(coded) - order + 1]
        alive = alive[:len(coded) - order + 1]

        grid = numpy.zeros(width, dtype=numpy.float64)
        if int(alive.sum()) >= 1000:
            grid = numpy.bincount(placed[alive], minlength=width).astype(numpy.float64)
            total = grid.sum()
            if total > 0.0:
                grid = grid / total
        parts.append(grid)

    return numpy.concatenate(parts) if parts else None


def structural(text, ranks, smooth=0.5):
    """The same web with the frequencies divided out, leaving what follows what.

    Each cell is how far a pair departs from what the two frequencies alone would give, in logs. A
    text whose letters follow one another for no reason reads zero everywhere. The count added to
    every cell keeps a pair never seen from being infinitely surprising, which it is not: it is
    unobserved.

    Why this exists. The plain web holds two things at once. The frequencies say how often each
    character is used and belong to a script and its conventions before they belong to a language.
    What follows what given those frequencies is about how the language is built. Every result in
    this work says the first dominates: two Chinese texts of one language in two character sets sit
    twice as far apart as two in the same set, and Tamil and Malayalam, the closest pair in their
    family, sit widest apart of seven because Malayalam took Sanskrit letters into its writing.

    What dividing them out actually did, measured, is worth knowing before reaching for it. Half the
    prediction held: the two script driven distances closed up as expected. The other half is the
    answer. Every distance above the average fell and every distance below it rose, and all eight
    landed near 1.0. That is compression and not correction. The marginals were never only script,
    since a language with many vowels or heavy affixation has different letter counts for reasons
    that are the language, and the ratio weights rare pairs most, where the estimate is worst.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ordered = sorted(counts, key=lambda symbol: -counts[symbol])[:ranks]
    seat = {symbol: place for place, symbol in enumerate(ordered)}

    grid = numpy.full((ranks, ranks), smooth, dtype=numpy.float64)
    previous = None
    for symbol in text:
        place = seat.get(symbol)
        if (place is not None) and (previous is not None):
            grid[previous, place] += 1.0
        previous = place

    total = grid.sum()
    if total <= 0.0:
        return None

    joint = grid / total
    down = joint.sum(axis=1, keepdims=True)
    across = joint.sum(axis=0, keepdims=True)
    return numpy.log2(joint / (down @ across)).reshape(-1)


def leave_one_out(rows):
    """Assign each reading to the label whose remaining readings it lands nearest.

    Each row is (label, name, values). Holding a text out and describing its label from the texts
    that remain keeps a reading from being scored against itself. Scoring a reading against itself
    inflated every identification figure this work first produced.

    Returns how many landed on their own label, how many were scored, and a count per confusion.
    """
    labels = sorted({row[0] for row in rows})
    correct = 0
    confused = {}

    for index, (label, _, values) in enumerate(rows):
        best = None
        picked = None
        for other in labels:
            kept = [row[2] for position, row in enumerate(rows)
                    if row[0] == other and position != index]
            if not kept:
                continue
            middle = numpy.mean(numpy.stack(kept), axis=0)
            distance = float(numpy.linalg.norm(values - middle))
            if (best is None) or (distance < best):
                best = distance
                picked = other
        if picked is None:
            continue
        if picked == label:
            correct += 1
        else:
            confused[(label, picked)] = confused.get((label, picked), 0) + 1

    return correct, len(rows), confused
