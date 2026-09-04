#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Put back together the words the two Lyon extractions broke apart.
#
#   Usage:  from space_repair import welded, vocabulary_of, joined_words
#
# Both PDFs split words internally. staʔx̌íl arrives as sta ʔx̌íl, iskwíst as isk wíst, nʔuɬxw as
# n ʔuɬxw. Nothing in a line can find those, because a space between two words and a space inside
# one are the same character.
#
# The interlinear can find them. It prints one word to an entry. A space inside an entry is one the
# extraction put there, and taking those out gives the paper's own list of what its words really
# look like. The running text of the same story is broken in the same places, and that list repairs
# it.
#
# The list was tested before being used, on the oracle the font table was tested on: Lyon's later
# papers on the same language, whose extraction kept its characters. Of the entries holding a
# space, none has all its pieces attested there as words in their own right, in either paper: 0 of
# 252 and 0 of 319. Joined, 4% and 36% of them are attested. The pieces are not words and the joins
# are. The low rate on the first paper comes from the reference sharing little vocabulary with it,
# and not from the joins being wrong.
#
# One word already whole is never joined to its neighbor. That is what keeps iʔ sɬiqw two words: a
# join starts only from a token that is not itself in the list.

import re

from salish_marking import bare_token

NUMBERED = re.compile(r"^\((\d{1,4})\)\s*(.*)$")
QUOTED = re.compile(r"^['‘“]")
CAPS_RUN = re.compile(r"[A-Z]{2,}")

# What only the damaged orthography writes. A line inside a block holding none of it is a page
# number or an English word gloss, not a word of the language.
ORTHOGRAPHY = "@ìˇáéíóúàèòù"

# How many pieces one word may have been broken into. Four covers everything seen in either paper;
# ʔe ɬ ’caʔ is three.
LONGEST = 4


def welded(text):
    """One interlinear entry with the spaces the extraction put inside it taken out."""
    return "".join(text.split()) if text else text


def entries_of(lines):
    """Every interlinear entry in a paper: a line inside a numbered block that is one word.

    A quoted line closes the block and is the free translation. A line carrying a run of two or
    more capitals is a gloss. A line carrying none of the damaged orthography is a page number or
    the English word gloss. What is left is a word as spoken or its segmentation, one to a line.

    Written to work from the raw lines, not from a reader's parse, so that a reader and the coverage
    check build the same list. Two lists drift, and the check then reports as a hole every word one
    of them put back together and the other did not.
    """
    held = []
    inside = False
    for line in lines:
        trimmed = " ".join(line.split())
        if not trimmed or trimmed.startswith("====="):
            continue
        found = NUMBERED.match(trimmed)
        if found:
            inside = True
            trimmed = found.group(2).strip()
            if not trimmed:
                continue
        if not inside:
            continue
        if QUOTED.match(trimmed):
            inside = False
            continue
        if CAPS_RUN.search(trimmed):
            continue
        if not any(one in trimmed for one in ORTHOGRAPHY):
            continue
        held.append(trimmed)
    return held


def vocabulary_of(entries):
    """The list of true word forms, from interlinear entries that have been welded."""
    held = set()
    for one in entries:
        plain = bare_token(one)
        if plain:
            held.add(plain)
    return held


def joined_words(text, vocabulary, longest=LONGEST):
    """One line with the spaces the extraction put inside its words taken back out.

    Walks the line and, at a token that is not already a word, takes the longest run of tokens
    whose pieces spell one. Punctuation rides along: the run is looked up without it and written
    back with it, so sta ʔx̌íl. joins to staʔx̌íl. and keeps the stop.
    """
    tokens = text.split()
    out = []
    at = 0
    while at < len(tokens):
        best = None
        # A token that is already a word is left alone, which is what keeps a real boundary.
        if bare_token(tokens[at]) not in vocabulary:
            for take in range(2, min(longest, len(tokens) - at) + 1):
                candidate = "".join(tokens[at:at + take])
                if bare_token(candidate) in vocabulary:
                    best = (take, candidate)
        if best:
            out.append(best[1])
            at += best[0]
            continue
        out.append(tokens[at])
        at += 1
    return " ".join(out)
