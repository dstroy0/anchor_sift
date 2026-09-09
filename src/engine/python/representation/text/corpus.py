#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Text corpora read off disk as symbols on a line.
#
#   Usage:  from representation.text.corpus import load_language_texts, load_by_source
#
# Four separate scripts carried their own copy of this loading loop, character for character, and a
# copy is a place for two of them to disagree. One of them already did: the exclusion below was
# applied in three of the four and missing from the fourth. A Greek to English lexicon therefore
# stood in one reading of Greek after it had been removed from the others.
#
# Nothing here computes where the repository is. A caller passes the directory in, which keeps the
# engine from knowing anything about the tree it happens to be checked out into.

import os

# Symbols read from any one text. A longer read is a different measurement, and any comparison
# across texts holds this fixed and says so.
CAP = 200000

# A text shorter than this is left out. An estimate over fewer symbols than this is a reading of the
# sample size, which this work has recorded happening four separate times.
LEAST = 80000

# A Greek to English lexicon of the New Testament, 21.2 percent Greek letters and 78.8 percent Latin
# ones. It was one of four Greek texts and stood inside every Greek reading in this work until a
# first line was read by accident. Excluded by name and not deleted, so what it was and why it is
# gone stays on the record.
SKIP = ("lang_greek_40935",)

# Where a language may be held from, as (name, file prefix, whether the file names carry a number).
# Nothing is shared between these four: not the subject, not the century, not the translator, not the
# kind of writing. The question is therefore answerable directly. If a reading belongs to a
# language, one language read from a novel and from an encyclopedia sits closer than two languages
# read from the same place, and neither distance needs a threshold to compare.
SOURCES = (
    ("books", "lang_", True),
    ("encyclopedia", "wiki_", True),
    ("one work", "para_", False),
    ("another work", "para2_", False),
)


def fold_lines(text):
    """Line endings folded to spaces, since a publisher chose the wrapping and not the author.

    Correct for prose and wrong for source. A programming language ignores its own whitespace, so
    every line break in one was put there by a person for another person, and folding it discards
    the authored layer and keeps the part the compiler reads. Pass source through unfolded.
    """
    return text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")


def load_language_texts(corpora, prefix="lang_", cap=CAP, least=LEAST, skip=SKIP, numbered=True):
    """Every text under one prefix, as (language, label, text), folded and cut to one length.

    A file is named <prefix><language>_<number>.txt where numbered is true, and <prefix><language>
    otherwise. The first form is a catalog holding several texts per language; the second is a
    parallel corpus holding one.
    """
    held = []
    for name in sorted(os.listdir(corpora)):
        if not (name.startswith(prefix) and name.endswith(".txt")):
            continue
        if name[:-4] in skip:
            continue
        stem = name[len(prefix):-4]
        language = stem.rsplit("_", 1)[0] if numbered else stem
        with open(os.path.join(corpora, name), encoding="utf-8", errors="replace") as handle:
            text = fold_lines(handle.read(cap))
        if len(text) < least:
            continue
        held.append((language, name[:-4], text))
    return held


def load_by_source(corpora, sources=SOURCES, cap=CAP, least=LEAST, skip=SKIP):
    """Every text held, as {(source, language): [text, ...]}, folded and cut to one length.

    A language appearing under several prefixes lands under several keys, letting a reading of it
    from one collection be compared against a reading of it from another.
    """
    gathered = {}
    for source, prefix, numbered in sources:
        for language, _, text in load_language_texts(corpora, prefix, cap, least, skip, numbered):
            gathered.setdefault((source, language), []).append(text)
    return gathered
