#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Glossed examples read out of a paper, which is a linguist's own analysis and not this work's.
#
#   Usage:  from oracle.language.glosses import harvest, morphemes
#
# Nothing here is measured. Everything comes out of what an author already wrote down about a
# language they studied, and none of it is derived from any reading this work takes.
#
# The interlinear format holds two halves that answer each other. An example is printed in three
# lines: the form with its morpheme boundaries, a morpheme by morpheme gloss, and a running
# translation. The second line is what the word composes. The third is what English keeps. The
# difference between them is countable. Subtracting the two takes no interpretation at all.
#
# Robertson and colleagues end their paper on Lower Chehalis asking for work that makes the literal
# content of Salish words overt, and give the example themselves: the word for people analyzes as
# many=mouths=in.a.longhouse, which no English translation of it carries. They treat that as
# something a lexicographer recovers by hand from an elder's explanation. The format already holds
# it.
#
# What this cannot see. Glossing conventions belong to authors and not to the field. Van Eijk marks
# telic reduplication with the equals sign in the same volume where Robertson marks lexical suffixes
# with it. Counting one symbol across papers therefore counts two things. Morphemes are counted
# from every boundary mark together, and the per paper question is left to a reader who opens the
# paper.
#
# The form lines came out of the PDF with the glottalized and retracted consonants dropped, which
# would ruin any measurement of the phonology. Gloss lines and translation lines are close to plain
# ASCII and came through, and those are the two lines this reads.

import re

# What a morpheme by morpheme line uses to name a grammatical category.
TAGS = re.compile(r"\b(?:[1-3](?:SG|PL|DU)|SG|PL|DU|NOM|ACC|ERG|ABS|GEN|DAT|LOC|ART|DEM|DET|"
                  r"POSS|PASS|CAUS|APPL|TR|INTR|REFL|RECIP|IMPF|PERF|PROG|ASP|TNS|PAST|FUT|"
                  r"IRR|SUBJ|IND|CONJ|NEG|Q|WH|REP|EVID|HYP|INCH|RES|REL|AUG|DIM|TEL|FACT|"
                  r"DISC|COMP|CONCL|CONF|ADH|REIN|KAT|CLF|PL\.|MID|CTR|NCTR|LEX)\b")

# What separates one morpheme from the next, across the conventions in use.
BREAKS = re.compile(r"[-=ʬ¬‧.<>{}\[\]‹›]|ˈ")

OPENERS = "‘“\"'"
CLOSERS = "’”\"'"

# How far past a gloss line the running translation may sit, since a long gloss continues onto the
# next line before the translation arrives.
LOOKAHEAD = 5


def is_gloss(line):
    """A line that names grammatical categories is the morpheme by morpheme line.

    An abbreviation key names more categories than any real example does, and it quotes a gloss
    beside each one, matching everything an example matches and matching it harder. A key chains its
    definitions with semicolons and colons, and that is what rules it out here. One volume's key was
    read as the richest example in it before this test existed.
    """
    if (line.count(";") >= 2) or (line.count(": ") >= 2):
        return False
    return len(TAGS.findall(line)) >= 2


def is_translation(line):
    """The running translation inside a line's quotation marks, or None where there is none.

    The closing mark is taken as the last one on the line. An English contraction inside a
    translation is written with the same character that closes the quote, and stopping at the first
    one turns 'I didn't sleep' into 'I didn'.
    """
    trimmed = line.strip()
    opened = -1
    for index, symbol in enumerate(trimmed):
        if symbol in OPENERS:
            opened = index
            break
    if opened < 0:
        return None
    closed = -1
    for index in range(len(trimmed) - 1, opened, -1):
        if trimmed[index] in CLOSERS:
            closed = index
            break
    if closed <= (opened + 3):
        return None
    return trimmed[opened + 1:closed].strip()


def morphemes(line):
    """How many pieces the gloss line breaks into, counting every boundary convention."""
    total = 0
    for chunk in line.split():
        if not chunk.strip():
            continue
        pieces = [one for one in BREAKS.split(chunk) if one.strip()]
        total += max(1, len(pieces))
    return total


def harvest(pages):
    """Every glossed example, as the page number, the gloss line, and the translation.

    `pages` is a sequence of (page number, text) pairs.
    """
    found = []
    for number, text in pages:
        lines = text.splitlines()
        for index, line in enumerate(lines):
            if not is_gloss(line):
                continue
            english = None
            for ahead in range(index + 1, min(index + LOOKAHEAD, len(lines))):
                english = is_translation(lines[ahead])
                if english:
                    break
            if not english:
                continue
            found.append((number, line.strip(), english))
    return found
