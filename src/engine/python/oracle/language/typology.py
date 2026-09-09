#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How each language builds a word and what it writes with a capital, from description and not measure.
#
#   Usage:  from oracle.language.typology import CAPITALIZES, MORPHOLOGY, SUBFAMILY
#
# These are outside answers, so they sit in the oracle part beside the family tables. Nothing here is
# derived from any corpus in this work, and none of it moves when a measurement does.
#
# CAPITALIZES decides whether a result can be read at all. German marks every noun with a capital
# mid-sentence and the other eighteen languages capitalize names alone. A reading that folds case
# therefore throws away a real channel in one language and nothing in the rest. The first run
# of the case measurement folded everything and then reported German as the most ambiguous language
# in the set, which was a fact about the preprocessing.
#
# MORPHOLOGY is the standard three way split. A fusional language packs several categories into one
# ending, an agglutinative one strings a separate piece per category, and an isolating one marks them
# with separate words. It is a description of a tendency and not a partition: English is fusional
# with most of its endings gone, and every language sits somewhere on the range instead of inside one
# box.
#
# SUBFAMILY is the long form label, carried beside a tree to check a grouping against something
# written down first. The short names in `families` answer the same question at a coarser grain. A
# caller scoring a grouping should use those; these exist to be printed.

# What a language writes with a capital letter, and which family it belongs to, in one line.
CAPITALIZES = {
    "german": "Germanic, every noun",
    "english": "Germanic, names only",
    "dutch": "Germanic, names only",
    "danish": "Germanic, names only",
    "swedish": "Germanic, names only",
    "icelandic": "Germanic, names, four cases",
    "polish": "Slavic, names only",
    "russian": "Slavic, names only",
    "croatian": "Slavic, names only",
    "slovak": "Slavic, names only",
    "ukrainian": "Slavic, names only",
    "finnish": "Uralic, names only",
    "estonian": "Uralic, names only",
    "hungarian": "Uralic, names only",
    "turkish": "Turkic, names only",
    "latvian": "Baltic, names only",
    "romanian": "Romance, names only",
    "spanish": "Romance, names only",
    "vietnamese": "Austroasiatic, names only",
}

# How a word is built, for the languages the treebanks cover.
MORPHOLOGY = {
    "german": "fusional",
    "english": "fusional, little left",
    "polish": "fusional",
    "finnish": "agglutinative",
    "estonian": "agglutinative",
    "hungarian": "agglutinative",
    "turkish": "agglutinative",
    "vietnamese": "isolating",
}

# The long form family label, for printing beside a tree.
SUBFAMILY = {
    "german": "Indo-European, Germanic",
    "english": "Indo-European, Germanic",
    "polish": "Indo-European, Slavic",
    "finnish": "Uralic, Finnic",
    "estonian": "Uralic, Finnic",
    "hungarian": "Uralic, Ugric",
    "turkish": "Turkic",
    "vietnamese": "Austroasiatic",
}


def family_of(language):
    """The family named in the first field of the capitalization note, or None where it is absent."""
    note = CAPITALIZES.get(language)
    return note.split(",")[0] if note else None
