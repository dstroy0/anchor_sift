#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Whitespace a PDF extraction invented, and the tests for where it invented it.
#
#   Usage:  from whitespace import closed_after_marks, closed_after_bracket, stacked_but_not, any_of
#
# A typesetter setting a combining mark leaves room after it, and the extraction reads that room as a
# space. It is the most common single kind of damage in this archive and it is the one every reader
# has to undo before anything downstream sees a word.
#
# ONE LONE SPACE IS INSERTED, TWO ARE A BOUNDARY
#
# Where a real word or column boundary follows a stacked mark, these extractions print two spaces.
# That is what keeps the two columns of Table A1 apart at č̓ ə́šay̓  č̓ əsáy̓, and what keeps
# lə́ x̌ ləx̌  ‘intelligent’ from swallowing its own gloss. Only a lone space closes, and one of a
# pair survives. Every paper here that prints a two-column table depends on it.
#
# WHICH MARKS HOLD A SPACE OPEN IS PER PAPER
#
# That is the whole of what differs between these papers, which is why it is an argument and not a
# constant. Two tests cover every paper in the tree. stacked_but_not reads the Unicode combining
# class and takes an exclusion, which is what a paper needs when a word can end in a stressed vowel:
# closing after the accent in ntes neʔé e sqyéytn gives neʔée, which the language does not have.
# any_of names a set outright, which is what a paper needs when its own layout makes closing after an
# accent safe, and the double-space rule above is what makes it safe.
#
# ʷ is in neither test and is not a stacked mark. It is a spacing modifier letter on the baseline and
# the typesetter never has to make room after one, so every space following a ʷ is a real boundary:
# bəlkʷ ‘return’, wix̌ʷ x̌il, sčədadxʷ sʔuladxʷ. Reading the combining class keeps it out without
# anyone having to remember to exclude it.

import unicodedata


def closed_after_marks(holds_open):
    """One line with the lone space a PDF left after a stacked mark taken out.

    holds_open is a test on one character saying whether the typesetter had to make room after it.
    """
    def closed(line):
        out = []
        at = 0
        while at < len(line):
            symbol = line[at]
            if ((symbol == " ") and out and holds_open(out[-1])
                    and (((at + 1) >= len(line)) or (line[at + 1] != " "))):
                at += 1
                continue
            out.append(symbol)
            at += 1
        return "".join(out)
    return closed


def closed_after_bracket():
    """One line with the space an extraction left after an opening square bracket taken out.

    A bracket is how a paper says whether a string is a cluster or a segment. Mellesmoen and Kye
    cites a cluster as [ k̓ʷd] and a segment as [ ə]; left open, the bracket is one token and the
    thing it encloses is another, and the cluster then matches nothing.
    """
    def closed(line):
        return line.replace("[ ", "[")
    return closed


def stacked_but_not(exclude):
    """Every stacked mark except the named ones, read off the Unicode combining class.

    Reading the class instead of a list is what keeps this current. The papers between them leave a
    space after the comma above, the comma above right, the caron, the dot below and the hook above,
    and a hand-kept list of those went stale the first time a new paper arrived.
    """
    def holds_open(symbol):
        return bool(unicodedata.combining(symbol)) and (symbol not in exclude)
    return holds_open


def any_of(marks):
    """Exactly the named marks, for a paper whose layout makes closing after an accent safe."""
    def holds_open(symbol):
        return symbol in marks
    return holds_open
