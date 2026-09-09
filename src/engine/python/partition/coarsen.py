#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Keeping fewer distinctions, so how few a result survives on can be measured instead of assumed.
#
#   Usage:  from partition.coarsen import coarsen
#
# Nothing is deleted here. The positions stay, the sequence keeps its own length, and only the
# number of distinctions falls. Everything past the commonest few symbols becomes one symbol. That
# makes the partition coarser in the plainest way available.
#
# A sweep of it turns a choice of alphabet from an assumption into a result. Removing three
# letters from every language moved the closest pairing measured by 0.0002, which says the reading
# rests on no particular letter and invites the opposite question: how much of a writing system can
# go before a relationship stops being visible.
#
# What is watched at each step is the ordering and never the distance. Distances shrink as symbols
# are folded for arithmetic reasons alone, so the raw numbers say nothing on their own. A pair known
# to be close is measured against a pair known not to be, and the level where the close pair stops
# being the closer of the two is where the relationship stops surviving.
#
# Measured, the answer is two. At every level down to two the close pairs stay closer, and at two
# the only distinction left is whether a character is the commonest one. For most of these languages
# the commonest character is the space, so the text becomes a record of word lengths alone, and the
# lengths line up with the pairings exactly: Zulu 5.70 against Xhosa 5.88, Spanish 4.41 against
# French 4.66. Finnish at 6.41 puts it away from Spanish.
#
# So at the bottom of the sweep the reading is a single magnitude per language and not a relation
# between quantities. One comparison is void at that level and it was not noticed until the
# commonest characters were listed: Shona and Somali have the letter a as their commonest and not
# the space, so their two symbol reading records where a falls and not where words end.

# Private use codepoints, keeping a coarsened symbol from colliding with anything the source held.
FIRST_SEAT = 0xE000


def coarsen(text, keep):
    """The text with only its `keep` commonest symbols told apart and everything else made one.

    Returns a string over a private use alphabet of at most `keep` symbols. The lumped symbol is
    distinct from every kept one, which keeps a reading from confusing the residue with a real
    character.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1

    ordered = sorted(counts, key=lambda symbol: -counts[symbol])[:keep - 1]
    seat = {symbol: chr(FIRST_SEAT + place) for place, symbol in enumerate(ordered)}
    lump = chr(FIRST_SEAT + keep)
    return "".join(seat.get(symbol, lump) for symbol in text)


def commonest(text, how_many=1):
    """The `how_many` commonest symbols. A two symbol coarsening turns entirely on these.

    Worth checking before reading a coarsened result. Where the commonest symbol is the space, a two
    symbol text records word lengths. Where it is a letter, the same reading records where that
    letter falls, and a distance between the two cases compares unlike quantities.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    return sorted(counts, key=lambda symbol: -counts[symbol])[:how_many]
