#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Deleting exactly one channel of a writing system and leaving every other one in place.
#
#   Usage:  from representation.text.marks import strip_marks, every_mark, TONE, QUALITY
#
# Most controls in this work delete a property by shuffling, which removes an arrangement without
# choosing which one. This removes a named channel while every letter stays on the page, which is a
# far sharper instrument and is available in exactly one place.
#
# Three of the languages held here carry tone and none of them lets it be taken out. Chinese fuses it
# into the character, so removing it removes the word. Thai spreads it across marks and the class of
# the initial consonant together, so no set of codepoints is the tone. Japanese never writes its
# pitch accent at all.
#
# Vietnamese writes six tones as marks on a Latin base, and those marks are separate from the ones
# setting vowel quality. The tone can therefore be deleted on its own, and no other language here
# allows that. A Vietnamese syllable carries six meanings under six tones, so removing the marks
# collapses six words into one and destroys much of the language while leaving every letter in place.
#
# What that measured is the first thing in this work to clear the floor everything else sank under.
# Deleting the tone moves the reading 0.0949. Every other language stripped of all its marks moves
# less: Czech 0.0779, Romanian 0.0723, Turkish 0.0582, Spanish 0.0409, French 0.0369. And the control
# decides it: two unrelated passages of Vietnamese sit 0.0874 apart, so deleting the tone makes a
# text less like itself than a different part of the same language is.
#
# For comparison, the writer is worth 7 to 11 percent, the century 1, and four hundred years of
# changing orthography 5, and all of it is swamped by two books being two books.

import unicodedata

# The five combining marks that are tone in Vietnamese.
TONE = ("́", "̀", "̉", "̃", "̣")

# The three that set vowel quality and are not tone. These have to survive a tone deletion.
QUALITY = ("̂", "̆", "̛")


def every_mark(text):
    """Every combining mark the text actually uses. A tone deletion is scored against this.

    Stripping all of a language's marks is what the other languages get, so the comparison is one
    channel against a whole inventory and the difference is what that channel was worth.
    """
    opened = unicodedata.normalize("NFD", text)
    return tuple(sorted({symbol for symbol in opened
                         if unicodedata.category(symbol) == "Mn"}))


def strip_marks(text, wanted):
    """The text with the named combining marks removed and every other mark left alone.

    Decomposed first, letting a precomposed character have one of its marks taken off, then
    recomposed, leaving the remainder written the way the language writes it.
    """
    opened = unicodedata.normalize("NFD", text)
    kept = "".join(symbol for symbol in opened if symbol not in wanted)
    return unicodedata.normalize("NFC", kept)


def to_bare(text):
    """The text reduced to the twenty six letters every Latin alphabet shares.

    The sharpest version of a mark deletion: it removes the alphabet. Polish loses its slashed l,
    Hungarian its long double accents, Turkish its dotless i, Vietnamese all six tones. No language
    then holds a symbol another lacks, so nothing can be named by its inventory.

    That test was worth running because a milder one had already moved fourteen of twenty languages
    to a different nearest neighbor, which read as the family signal being spelling. Removing the
    alphabet entirely gives 13 of 22 languages nearest a relative, against 13 of 22 for reading every
    character they actually use. The alphabet is worth nothing to the family result, and the earlier
    reading of that milder test was an overclaim.

    Stripping it also corrects some pairings, and that part is worth keeping. Latvian moves from
    Czech to Lithuanian, Baltic finding Baltic. Polish moves from Slovenian to Czech, West Slavic
    finding West Slavic. The orthography had been interfering.

    Only for languages already written in this alphabet. Stripping a Greek or Indic text would mean
    transliterating it, which is a judgement about sounds and puts back exactly what this removes.
    """
    opened = unicodedata.normalize("NFD", text.lower())
    kept = []
    for symbol in opened:
        if unicodedata.category(symbol) == "Mn":
            continue
        if "a" <= symbol <= "z":
            kept.append(symbol)
        elif symbol.isspace():
            kept.append(" ")
    return " ".join("".join(kept).split())


def latin_share(text):
    """What share of the text's letters are bare Latin, which says whether `to_bare` applies.

    Below about 0.8 the text is written in something else and stripping it would be a
    transliteration.
    """
    letters = sum(1 for symbol in text if symbol.isalpha())
    if letters == 0:
        return 0.0
    latin = sum(1 for symbol in unicodedata.normalize("NFD", text)
                if "a" <= symbol.lower() <= "z")
    return latin / float(letters)


def marks_per_letter(text, wanted):
    """How many of the named marks the text carries for each letter, which says how much is at stake.

    Vietnamese carries 0.209 marks per letter and that count is tone alone.
    """
    opened = unicodedata.normalize("NFD", text)
    carried = sum(1 for symbol in opened if symbol in wanted)
    letters = sum(1 for symbol in text if symbol.isalpha())
    return carried / float(max(letters, 1))
