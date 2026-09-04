#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# What a reader needs where its source is the drafted page text instead of the extraction.
#
#   Usage:  from page_text import language_line, repaired, repaired_english, repaired_line,
#                                repaired_prose
#
# font_repair exists because the two Lyon papers arrive as the font's own alphabet, and it carries
# the same five function names this module does. draft_page_text.py writes that alphabet back into
# the orthography, so a reader pointed at build/papers/<stem>.page.txt is reading text the mapping
# has already been through. A reader swaps this module in for that one and changes nothing else.
#
# THE MAPPING IS NOT IDEMPOTENT
#
# Running it a second time destroys the text rather than leaving it alone. P becomes ʔ, so Papers is
# ʔapers and the gloss label APPL is AʔʔL. Q becomes ʕ, so Quilchena is ʕuilchena. @ becomes ə, so
# john.lyon@alumni.ubc.ca ends with a schwa in the middle of it. Every repair here returns its line.
#
# THE LANGUAGE TEST CANNOT PASS THROUGH
#
# font_repair's language_line asks whether a line holds a character only the damaged orthography
# writes: a bare @, an ì, a stranded caron, a capital P or Q inside a word. The page text holds none
# of those by construction, so that test answers no for every line, and a reader trusting it files a
# whole story as unclassifiable. The test below asks what the page text can answer, which is whether
# the line holds a character of the orthography itself.
#
# TEXT_SPACE and not the reader's own mark set. A reader adds the typographic apostrophe to its set
# because the damaged text writes glottalization with one, and on the page text that character is
# only ever the apostrophe of Lyon’s and Society’s. Testing on it calls his English the language.

from salish_marking import TEXT_SPACE


def repaired(text):
    """One line as it arrived. The page text is already the orthography."""
    return text


def repaired_line(text):
    """One line as it arrived, for a line the reader has no column to go on for."""
    return text


def repaired_english(text):
    """One line as it arrived, for a line the reader has already decided is English."""
    return text


def repaired_prose(text):
    """One line as it arrived, for a gloss, a translation or Lyon's own writing."""
    return text


def carries_orthography(token):
    """Whether a token holds a character of the orthography.

    The five-line reader asks this of the fourth line of a word, which is an English word for the
    word above it and which the paper does not always give. An Okanagan word standing in that slot
    means the count has slipped. font_repair's version asks after a capital P or Q inside the token,
    which the page text never has, so it answered no for tətwít as readily as for priest.
    """
    return any(mark in token for mark in TEXT_SPACE)


def language_line(text, floor=1):
    """Whether a line of the page text is the language and not a line of Lyon's English.

    One token carrying a character of the orthography is enough, for the reason font_repair gives:
    these stories wrap and leave lines as short as sámaʔ. and təmxʷúlaʔxʷ., and asking for two
    throws them out of the running text.
    """
    return sum(1 for token in text.split()
               if any(mark in token for mark in TEXT_SPACE)) >= floor
