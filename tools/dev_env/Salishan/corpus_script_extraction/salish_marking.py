#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The T and N marking convention shared by every per-paper Salish extractor.
#
#   Usage:  from salish_marking import rendered, tagged_spans, is_mixed
#
# Every paper is read by its own extractor, because the papers are laid out differently and one rule
# across all of them takes whichever layout it was written for and mangles the rest without reporting it.
# What the extractors do share is how a line is marked once it has been found, and that lives here so the
# convention cannot drift between files.
#
# T is the target language. N is anything else. A line is never cut into separate rows: a speaker who
# moves between her languages inside one sentence said one sentence, so the spans are marked in place and
# in order and the line keeps its identity. That also leaves the switches grouped by line and sortable,
# which is where the boundaries of the morphological system show.
#
# Two English-looking tokens in a row are required to open an N span. Several clitics of these languages
# are written in plain letters, and a single plain token is as likely to be one of those as it is to be
# English. Leaving a word inside T is the harmless direction to be wrong in, and a word wrongly pulled out
# of her sentence is not.

# The marked characters these orthographies are written with. A token holding any of them is the
# language. Both ɬ and ł are here: papers differ on which they use for the lateral fricative, and
# LaFontaine and Janzen write ł throughout where Hall and Phillips write ɬ. Carrying only one makes
# every token of the other paper invisible to the marking and to any coverage check built on it.
import re

MARKED = "ʔʕɬłƛəχ"

# A run of two or more capitals is a gloss label or an acronym, and none of these orthographies
# writes a word that way: APPL, INCEPT, 1SG.POSS, D/C, NMLZ. Finding one in a line that should hold
# a word is how every reader here tells that it has lost its place in a block.
CAPS_RUN = re.compile(r"[A-Z]{2,}")

PUNCTUATION = ".,!?;:“”‘’\"'()[]…"

# Typographic ligatures, which are one codepoint standing for two or three letters concatenated
# mid-word. 476 of them are in five of these papers. They are not a decision about a glyph the way
# the font substitutions are: ﬁ is fi and nothing else, so this is applied without a test.
#
# Left alone they put ﬁve into a corpus and make a word fail to match itself, which is how this was
# found: a case-sensitive match against the pure corpus turned up five against ﬁve.
LIGATURES = (("ﬃ", "ffi"), ("ﬄ", "ffl"), ("ﬁ", "fi"), ("ﬂ", "fl"),
             ("ﬀ", "ff"), ("ﬅ", "st"), ("ﬆ", "st"))


def unligatured(text):
    """One line with its typographic ligatures written back out as the letters they stand for."""
    for was, becomes in LIGATURES:
        text = text.replace(was, becomes)
    return text


def bare_token(token):
    """A token with the punctuation around it taken off."""
    return token.strip(PUNCTUATION)


# Some of these languages are written in a practical orthography that uses plain keyboard
# characters. St'át'imcets writes the glottal stop as the digit 7, so Cw7aoz, skúza7 and ts7ásas
# carry none of the marks above and are invisible to a test built only on them. A digit inside a
# word does not occur in English, which makes it a reliable mark where a paper uses it.
PRACTICAL = "7"

# Every character these orthographies write their languages with, as one set. This is the space a
# Salishan text is represented in, and a test built on one paper's alphabet instead reads the others
# as holding no language and then reports nothing missing from them either.
#
# What the three above do not carry: ̓ ̔ ̕ are the glottalization marks a paper stacks on a
# consonant, ʷ is labialization, and ˽ is the raised space Nater sets a clitic boundary with.
#
# Two files had their own copy of this union spelled out, salish_unsorted and hand_extraction's
# papers, and MARKED was the default wherever a caller passed nothing. Both are read from here now.
# A per-paper set is written as this plus what that paper adds, never as its own alphabet.
TEXT_SPACE = MARKED + PRACTICAL + "̓̔̕ʷ˽"


def looks_english(token, marks=MARKED):
    """A token with no marked character, long enough and vowelled enough to be an English word.

    Two letters is the length of several clitics written in plain letters, so the floor is three.
    """
    plain = bare_token(token)
    if (len(plain) < 3) or (not plain.isascii()) or (not plain.isalpha()):
        return False
    if any(mark in token for mark in marks):
        return False
    return any(vowel in plain.lower() for vowel in "aeiou")


def tagged_spans(text, marks=MARKED):
    """The line as consecutive spans, each marked T for the target language or N for anything else."""
    tokens = text.split()
    if not tokens:
        return []
    flags = [looks_english(one, marks) for one in tokens]

    # A lone English-looking token joins the target span around it
    for index in range(len(flags)):
        if not flags[index]:
            continue
        before = flags[index - 1] if index > 0 else False
        after = flags[index + 1] if (index + 1) < len(flags) else False
        if not (before or after):
            flags[index] = False

    spans = []
    held = [tokens[0]]
    current = flags[0]
    for index in range(1, len(tokens)):
        if flags[index] == current:
            held.append(tokens[index])
            continue
        spans.append(("N" if current else "T", " ".join(held)))
        held = [tokens[index]]
        current = flags[index]
    spans.append(("N" if current else "T", " ".join(held)))
    return spans


SPOKEN = "spoken"
DERIVED = "derived"

# Where a line goes when the extractor cannot say what it is. It carries the language, so it is not
# discardable, and nothing is known about it, so it is not ingestible either. Naming the category
# after the tool's own limit keeps that honest: it says a program failed to sort this, not that the
# line is doubtful. Each extractor writes these to a file of their own beside its output. A person
# can then work through them, and they are held out of the pure stream until someone has.
UNCLASSIFIED = "unclassifiable by tool"


def rendered(text, layer=None, subcategory=None, marks=MARKED):
    """One line written as its tagged spans, in the order they were spoken.

    Three things are marked. T or N says which language a span is. The layer says whether it was
    said or worked out afterward. The subcategory says what the line is doing.

    The layer is the one that has to be right. Both of these papers state that their segmentation
    line normalizes each morpheme to an underlying form while only the transcription line presents
    words as they were uttered. A segmentation line is target-language material and belongs in the
    record, and it holds forms nobody said. A corpus of spoken language built without that
    distinction is seeded with invented words. The English translations are marked spoken where the
    speaker made them herself, which both papers say she did, and the gloss is always derived.
    """
    parts = [one for one in (layer, subcategory) if one]
    if not parts:
        return ", ".join("%s:{%s}" % (mark, run) for mark, run in tagged_spans(text, marks))
    tail = ".".join(parts)
    return ", ".join("%s.%s:{%s}" % (mark, tail, run) for mark, run in tagged_spans(text, marks))


def switches(text, marks=MARKED):
    """How many times a line crosses between languages.

    Takes a marking set for the reason tagged_spans does, and had no way to take one until now. The
    1983 typescript writes the glottal stop as ? and the schwa as ~, and Lyon's two papers arrive in
    the TeX font's own codes. Neither holds a character of the set below, so every line of all three
    came back as one English span and this returned 0 for the whole of them.
    """
    return max(0, len(tagged_spans(text, marks)) - 1)


def is_mixed(text, marks=MARKED):
    """Whether a line in the target language also holds words said in another one.

    The marking set is passed in for the same reason tagged_spans takes one. A paper writing the
    glottal stop as 7 carries none of the marked consonants, and a test built on the default set
    reads every line of it as English.
    """
    return any(mark == "N" for mark, run in tagged_spans(text, marks))
