#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The three repairs the Mellesmoen and Kye extraction needs.
#
#   Usage:  from mellesmoen_kye_repair import repaired
#
# Held in one file because three things apply them: the reader, the hand extraction check, and the
# coverage check. Two copies of a repair drift, and the check then reports as a hole every word one
# copy put together and the other did not.
#
# THE INSERTED SPACE
#
# The PDF sets a stacked diacritic by leaving room after it, and the extraction reads that room as a
# space. c̓ íx̌ id is the one word c̓íx̌id, x̌ ə́ k̓ ʷəd is x̌ə́k̓ʷəd, and there are 186 lines of it.
#
# ʷ is left out of the joining set. It is a spacing modifier letter on the baseline, and the PDF
# never has to make room after one. Every space following a ʷ in this paper is a real word boundary:
# bəlkʷ ‘return’, wix̌ʷ x̌il, sčədadxʷ sʔuladxʷ, tíləxʷ ʔəsxʷák̓ʷilbids. Including it welded thirteen
# pairs of words, among them the first two words of Annie Jack's opening sentence.
#
# The extraction prints two spaces where a real boundary follows a stacked mark. That is what keeps
# the two columns of Table A1 apart at č̓ ə́šay̓  č̓ əsáy̓. Only a lone space gets closed.
#
# One join is wrong and is known to be. Line 1349 cites the palatal series in prose as /ǰ č č̓  š/.
# ǰ ends in a caron with one space after it, exactly as a broken word does, and it comes out /ǰč
# č̓ š/. Nothing in either line separates that case from c̓ əq̓ c ‘spear’, which is the one word c̓əq̓c.
# The reader flags ǰč instead of pretending the repair got it. It costs a prose line and no word of
# the language: ǰ, č, č̓ and š are each in the corpus from other lines.
#
# THE EJECTIVE WRITTEN TWO WAYS
#
# The body writes the ejective with COMBINING COMMA ABOVE and the appendices write it with COMBINING
# COMMA ABOVE RIGHT. č̓ƛ̓aʔ ‘rock’ is printed four times with the first mark and once, in Appendix B,
# with the second. One paper prints one word both ways, which makes the second mark the same mark.
# The same holds for l̓: the body writes c̓əbə́l̓qid with COMBINING COMMA ABOVE and Appendix B writes
# x̌ʷul̕-b with COMBINING COMMA ABOVE RIGHT.
#
# Eight tokens carry the second mark, all of them in the two appendices. Left alone, ƛ̓ and ƛ̕ are two
# different letters to everything downstream, and the corpus holds Annie Jack's ƛ̕u= apart from the
# ƛ̓ of every other paper.
#
# EVERY ACCENTED VOWEL WRITTEN TWO WAYS
#
# The paper writes á as one character in some places and as a with a combining acute in others, and
# the same for í, à and ù. It writes ǰ as j with a combining caron throughout. Both forms of á render
# identically and no reading of the paper finds the difference. The hand extraction did not find it:
# thirteen of its rows were reported as forms the paper does not hold until this ran.
#
# c̓ágʷačiʔb ‘wash hands’ is the case to look at. Table 7 prints it one way and the prose about
# Figure 3 prints it the other. One word of one paper is then two words to anything comparing
# strings, and a corpus built without this holds both of them.
#
# NFC fixes it, and it is the one repair here that is not a judgment about this paper. Unicode
# defines canonical equivalence: a with a combining acute and á are the same character under that
# definition, and NFC is its composed form. Nothing else moves. There is no precomposed schwa with
# an acute, no x with a caron and no k with a comma above, so ə́, x̌ and k̓ come through untouched.

import unicodedata

# The marks the extraction leaves a space after. ʷ is deliberately not here.
JOINING = "̓̌́̀̕"

# What the appendices write the ejective as, and what the body writes it as.
COMMA_ABOVE_RIGHT = "̕"
COMMA_ABOVE = "̓"


def closed_spaces(line):
    """One line with the space the PDF left after a stacked diacritic taken out.

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


def one_ejective(line):
    """One line with both of the paper's ejective marks written as the one the body uses."""
    return line.replace(COMMA_ABOVE_RIGHT, COMMA_ABOVE)


def closed_brackets(line):
    """One line with the space the extraction left after an opening square bracket taken out.

    §3.2.2 cites a cluster as [ k̓ʷd] and a segment as [ ə], and the bracket is how the paper says
    which of the two a string is. Left open, the bracket is one token and the thing it encloses is
    another, so the cluster comes out as k̓ʷd] and matches nothing.
    """
    return line.replace("[ ", "[")


def composed(line):
    """One line with each accented vowel written the single way Unicode composes it."""
    return unicodedata.normalize("NFC", line)


def repaired(line):
    """One source line put through all three repairs, in the order they have to run.

    The spaces close first, while the marks whose space was inserted are still separate characters.
    NFC runs last: composing a with a combining acute into á would otherwise take that acute out of
    the joining set and leave the space it was holding open behind.
    """
    return composed(one_ejective(closed_brackets(closed_spaces(line))))
