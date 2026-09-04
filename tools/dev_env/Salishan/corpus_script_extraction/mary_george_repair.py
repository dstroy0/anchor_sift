#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The inserted-space repair the Mary George narratives need.
#
#   Usage:  from mary_george_repair import repaired
#
# Held in one file because the reader, the hand extraction check and the coverage check all apply it.
# Two copies drift, and a check then reports as a hole every word one copy put together.
#
# THE GRAVE IS GLOTTALIZATION HERE, NOT STRESS
#
# The shared repair in inserted_space.py leaves the space after a grave or an acute open. It has to:
# a word can end in a stressed vowel, and LaFontaine and Janzen has ntes neʔé e sqyéytn, where
# closing after neʔé gives neʔée.
#
# This paper's phonetic transcriptions use the two marks for two different jobs. The acute is stress
# and sits over a vowel: qʌ́χ, nʌ́mʔ, tʌ́s. The grave is glottalization and sits over a consonant:
# k̀wʊt, t̀al, q̀atçw, č̀yε, p̀aap̀εm. No vowel in the paper carries a grave, so the shared rule's
# reason for leaving it open does not reach this paper, and the space after every grave is inserted.
#
# q̀ waq̀ wθəm in story 5 line 31 is the case that found it. The paper prints it with a space after
# each grave, and the hand extraction records the one word q̀waq̀wθəm that Mary George said.
#
# The acute stays excluded. Closing after it would weld the stressed vowel ending one word to the
# word after it, which is the defect the shared repair exists to avoid.

import unicodedata

# The marks this paper leaves a space after. The acute is deliberately not here.
JOINING = "̀̓̌̕"


def closed_spaces(line):
    """One line with the space the PDF left after a glottalization mark taken out.

    A lone space after a mark is the inserted one. Two spaces are a column boundary the extraction
    kept, and one of them survives so the columns stay apart.
    """
    out = []
    at = 0
    while at < len(line):
        symbol = line[at]
        if ((symbol == " ") and out and (out[-1] in JOINING)
                and (((at + 1) >= len(line)) or (line[at + 1] != " "))):
            at += 1
            continue
        out.append(symbol)
        at += 1
    return "".join(out)


def composed(line):
    """One line with each accented vowel written the single way Unicode composes it."""
    return unicodedata.normalize("NFC", line)


def repaired(line):
    """One source line with its spaces closed and its accents composed, in that order.

    The spaces close first, while the marks whose space was inserted are still separate characters.
    NFC runs last: composing a with a combining grave into à would take that grave out of the
    joining set and leave the space it was holding open behind.
    """
    return composed(closed_spaces(line))
