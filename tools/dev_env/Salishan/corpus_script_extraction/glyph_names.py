#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Turn the glyph names 2012_Robertson's extraction prints back into the characters they name.
#
#   Usage:  from glyph_names import decoded
#
# This paper is on the list in docs/research/Salishan/refs.md of PDFs whose fonts renumber their
# codes and declare no /ToUnicode map, and it is the one on that list where nothing was lost. The
# extractor could not resolve a glyph, so it printed the glyph's name with a leading slash and
# carried on. Page 30 sets the morphemic line
#
#   ʔoo  ɬ  /xéʔ  -ɬ-  /kʷú[·kʷ]piʔ
#
# and build/papers/2012_Robertson.txt holds
#
#   /uni0294oo  /uni026C  /xé/uni0294  -/uni026C-  /kwú[·kw]pi/uni0294
#
# A uniXXXX name carries the code point it stands for, so that half of the recovery is arithmetic
# and exact. The named marks are a short table, below, and it is short because 8 uniXXXX names and
# 2 mark names cover all 75 unresolved glyphs in the paper.
#
# WHAT THIS DOES NOT RECOVER
#
# Labialization, for the same reason it is lost in the two Lyon papers. The page writes a raised w
# and the text gives a plain one, so page kʷú and page nšawa both hold a w and nothing in the file
# separates them. The prose loses it with a space instead: page (č, š, xʷ) arrives as ( č, š, x w).
#
# A slash the table does not claim is the paper's own. Robertson writes phonemic forms between
# slashes throughout, so /xéʔ opens with one and /k’/ and /q’/ are a pair of them. Only the names
# below and the uniXXXX pattern are consumed, and every other slash is left where it stands.

import re
import unicodedata

# A glyph name the extractor printed because it could not resolve the glyph. uniXXXX is matched on
# exactly four hex digits, which is what keeps /uni0294w from being read as a name ending in w: the
# w is the next letter of the word and belongs to the text.
UNICODE_NAME = re.compile(r"/uni([0-9A-Fa-f]{4})")

# The named glyphs that are not written uniXXXX. Both are combining marks and both follow the letter
# they sit on, which is the order Unicode wants and the order the extraction already has: page 30's
# x̣əƛ’ arrives as /x/combiningdotbelow/uni0259/uni019B’.
#
# Longest first, because the replacement is done in this order and /combiningacuteaccent starts with
# no shorter name in this table. Adding one that prefixes another means sorting this list.
NAMED = (
    ("/combiningacuteaccent", "́"),
    ("/combiningdotbelow", "̣"),
)


def decoded(line):
    """One line of the extraction with every printed glyph name turned back into its character.

    NFC at the end, for the reason coverage_check.py gives: two strings are the same string only
    after it, and a letter written as a base plus a combining mark has to compose before anything
    compares it against a table typed at a keyboard.
    """
    for name, symbol in NAMED:
        line = line.replace(name, symbol)
    line = UNICODE_NAME.sub(lambda found: chr(int(found.group(1), 16)), line)
    return unicodedata.normalize("NFC", line)
