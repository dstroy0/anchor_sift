#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The one grain nearly every paper here carries: a space left after a stacked diacritic.
#
#   Usage:  from inserted_space import closed_spaces
#
# Every one of these PDFs sets a combining mark by leaving room after it, and the extraction reads
# that room as a space. One word arrives as two tokens. Six of the papers with readers carry it, and
# the counts are not small: 996 in Hall and Phillips, 943 in Garcia, 478 in LaFontaine and Janzen,
# 298 in Mellesmoen and Kye, 169 in Matthewson and Redan, 159 in Mary George.
#
# The mechanism moved to repairs.py, where it sits beside the other kinds of damage these extractions
# do. What stays here is this grain's own evidence and the one decision it turns on, because both are
# facts about these papers and not about the mechanism.
#
# THE COVERAGE CHECK CANNOT SEE THIS
#
# coverage_check.py puts the source and the extraction through the same repair before comparing. A
# word broken in the source and broken in the extraction matches itself, and the paper reports 100
# percent while its corpus holds K̓ and weswapáw̓ as two words of St'át'imcets.
#
# What found it was the hand extraction. A person read Cw7aoz káti7 láti7 ku naxwít off the page,
# wrote K̓weswapáw̓ down as the one word it is, and reader_check.py then reported 91 of that paper's
# 102 forms as forms the reader does not produce.
#
# ʷ IS NOT A STACKED MARK
#
# It is a spacing modifier letter on the baseline, and the typesetter never has to make room after
# one. Every space following a ʷ is a real word boundary: bəlkʷ ‘return’, wix̌ʷ x̌il, sčədadxʷ
# sʔuladxʷ, tíləxʷ ʔəsxʷák̓ʷilbids. Closing those welded thirteen pairs of words in one paper alone,
# among them the first two words of Annie Jack's opening sentence. Reading the Unicode combining
# class is what keeps it out without anyone having to remember to exclude it.

from whitespace import closed_after_marks, stacked_but_not

# The stress accents. A word can end in a stressed vowel, and closing the space after one welds it
# to the word after it. LaFontaine and Janzen has ntes neʔé e sqyéytn, where neʔé ends in a stressed
# vowel and e is the next word: closing there gives neʔée, which the language does not have.
#
# This is the whole of what separates the general grain from the wider one. A paper whose own layout
# makes closing after an accent safe declares its own mark set instead, and Mellesmoen and Kye and
# Davis and Mellesmoen are the two that do. Both print two spaces at a real boundary, which leaves a
# lone space after an acute as the inserted one every time.
STRESS = "́̀"

# Every stacked mark except those. One word arrives as two tokens wherever one of these is followed
# by a lone space.
closed_spaces = closed_after_marks(stacked_but_not(STRESS))
