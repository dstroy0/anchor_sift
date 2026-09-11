#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# One alphabet for every script, putting a logographic language and a Celtic one in one code space.
#
#   Usage:  from representation.text.shared_alphabet import as_codes
#
# Taking positions by frequency rank makes alphabets comparable and still leaves each language in an
# alphabet of its own size: Chinese brings three thousand symbols to a comparison and Welsh brings
# eighty. A rank divided by the size of that alphabet says how far through it a symbol sits, the
# same quantity everywhere, and held to a fixed count of bits it becomes a code from one shared
# alphabet with nothing dropped for falling past a cutoff.
#
# The first attempt returned 12.4 percent and put 2 of 22 languages nearest a relative, against 52.8
# and 15 for reading the characters directly. The fault was not the idea. It slid windows of three to
# six bits along a stream carrying ten bits per character, so every window mixed the end of one
# character's code with the start of the next and measured neither. One code to one character
# returns 40.0 percent at 32 codes and 13 of 22.
#
# The trade. It loses about 13 points of identification and two families against reading the
# characters as they come. In exchange it needs nothing said about any script, drops no symbols,
# and puts every language in the same codes.
#
# Where it loses is worth knowing before reaching for it. Telling two languages apart needs the shape
# of a distribution, which binning by rank keeps. Knowing that two languages are related rests on the
# particular letters they share, and binning three thousand characters or eighty into 32 codes merges
# exactly those. The shared alphabet keeps what separates languages and loses what connects them.

import numpy

# Bits given to each character, so the shared alphabet holds two to this many codes.
WIDTHS = (3, 4, 5, 6, 7)


def as_codes(text, width):
    """Every character given a code in one alphabet shared by every language.

    One code covers exactly one character, and a reading over them never straddles two. Returns the
    codes and how many there are.
    """
    counts = {}
    for symbol in text:
        counts[symbol] = counts.get(symbol, 0) + 1
    ranked = sorted(counts, key=lambda symbol: -counts[symbol])

    size = float(len(ranked))
    width_of = 1 << width
    seat = {symbol: min(width_of - 1, int((place / size) * width_of))
            for place, symbol in enumerate(ranked)}
    return numpy.asarray([seat[symbol] for symbol in text], dtype=numpy.int64), width_of
