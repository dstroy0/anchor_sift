#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every Indic script read at one set of distinctions, so an inventory stops deciding the answer.
#
#   Usage:  from representation.text.indic import collapsed
#
# In the same length of text Tamil uses 149 distinct codepoints and Malayalam 524, because Malayalam
# took Sanskrit phonology into its writing and Tamil did not. A reading over codepoints was measuring
# which distinctions each script chose to record, and it put the two closest languages in the family
# at the widest distance in the matrix.
#
# The inventories go onto one footing without anyone deciding by hand what matches what. Every Indic
# block lays its consonants out in the inherited order, in rows of five: unvoiced, unvoiced
# aspirated, voiced, voiced aspirated, nasal. Collapsing each row of four stops onto the first of
# them keeps exactly the distinctions Tamil script keeps, and applying it to all seven languages asks
# every one of them the same question.
#
# This is a coarsening and a stipulation, in the sense the partition part uses: the rule is stated in
# advance, it has one answer, and it adds no information. A character keeps which sound it is and
# loses which script wrote it.

# The first codepoint of each Indic block. Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil,
# Telugu, Kannada, Malayalam, Sinhala.
STARTS = (0x0900, 0x0980, 0x0A00, 0x0A80, 0x0B00, 0x0B80, 0x0C00, 0x0C80, 0x0D00, 0x0D80)

# A block is 128 codepoints wide, and the consonants run from this offset in rows of five, the
# inherited ordering every block keeps.
BLOCK = 0x80
FIRST_CONSONANT = 0x15
ROWS = 5
LAST_CONSONANT = FIRST_CONSONANT + (ROWS * ROWS)

# Private use codepoints, keeping a folded symbol from colliding with anything the source held.
FIRST_SEAT = 0xE000


def collapsed(text, keep_aspiration=False):
    """Every Indic character reduced to its offset, with the stop rows folded onto their first.

    Anything outside the Indic blocks is left alone, and a text mixing scripts keeps its Latin.

    With `keep_aspiration` set the rows are not folded and only the script identity goes. That is
    the intermediate reading: one alphabet, every distinction any of them records.
    """
    out = []
    for symbol in text:
        point = ord(symbol)
        offset = None
        for start in STARTS:
            if start <= point < (start + BLOCK):
                offset = point - start
                break
        if offset is None:
            out.append(symbol)
            continue
        if (not keep_aspiration) and (FIRST_CONSONANT <= offset < LAST_CONSONANT):
            place = offset - FIRST_CONSONANT
            # The fifth of each row is the nasal and is its own sound, so only the four stops fold
            if (place % ROWS) != 4:
                offset = FIRST_CONSONANT + ((place // ROWS) * ROWS)
        out.append(chr(FIRST_SEAT + offset))
    return "".join(out)
