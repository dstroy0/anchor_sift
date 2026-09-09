#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The unit a writing system keeps its context in, which is not always the codepoint.
#
#   Usage:  from representation.text.clusters import aksharas
#
# A letter sequence works for an alphabet because that is where an alphabet keeps its context:
# letters run together into morphemes and the statistics of letter pairs carry that. An abugida keeps
# its context somewhere else. A consonant carries a vowel already, a dependent sign changes which
# vowel, and a virama binds one consonant to the next. The meaningful unit there is the whole
# cluster, and a codepoint is a piece of one.
#
# Counting the pieces counts how a script decomposes, and two close languages decompose differently.
# Read as codepoints, four Dravidian languages came out further from each other than from Indo-Aryan,
# and the pair that separated most recently read as the widest distance in the matrix.
#
# Alphabetic text passes through unchanged, since a Latin letter carries no marks and its cluster is
# the letter. A reading taken over clusters can therefore be compared against one taken over
# codepoints without the alphabet moving underneath it.

import unicodedata

# Each Indic block puts its virama at the same offset. The virama binds two consonants into one
# unit. Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam, Sinhala.
VIRAMAS = frozenset(start + 0x4D for start in
                    (0x0900, 0x0980, 0x0A00, 0x0A80, 0x0B00, 0x0B80, 0x0C00, 0x0C80, 0x0D00,
                     0x0D80))


def aksharas(text):
    """The text as clusters: a base with its marks, and with whatever a virama binds to it.

    Returns a list of strings. A reading that takes a sequence of symbols takes this list unchanged,
    since what it does with each entry never depended on the entry being one character.
    """
    out = []
    current = []
    joining = False
    for symbol in text:
        if not current:
            current.append(symbol)
            joining = ord(symbol) in VIRAMAS
            continue
        if unicodedata.category(symbol).startswith("M") or joining:
            current.append(symbol)
            joining = ord(symbol) in VIRAMAS
            continue
        out.append("".join(current))
        current = [symbol]
        joining = ord(symbol) in VIRAMAS
    if current:
        out.append("".join(current))
    return out
