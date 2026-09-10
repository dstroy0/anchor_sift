#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Which hand extraction goes with which paper and which record.
#
#   Usage:  from papers import EVERY
#
# One table, read by both checks. Two copies of it drift, and then the check that grades a reader
# against a hand extraction is grading it against a different paper than the check that grades the
# hand extraction against its source.
#
# It happened here. This file held the alphabets and coverage_check.py held the same alphabets
# written out a second time as literals, and the two disagreed on the repair for two papers before
# anyone noticed. Both now read corpus_script_extraction/paper_config.py, the only file where a
# paper is described: who spoke it, what it is written with, and which grains its extraction carries.
#
# What stays here is the shape the two checks want, and the one fact that belongs to the checks and
# not to the papers: which extractions are not what their page says.

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                "corpus_script_extraction"))

from paper_config import PAPERS  # noqa: E402

# Papers whose text extraction is not what the page says. Both are TeX Type1 with a custom encoding
# and no ToUnicode map, and pypdf and pypdfium2 lose the same things: the page prints cítxʷsəlx uɬ ti
# nyʕip and the text holds cítxws@lx uì ’ti ny ’Qip, with the ejective mark landing in front of its
# letter instead of over it.
#
# draft_page_text.py writes build/papers/<stem>.page.txt for these, line for line with the
# extraction, and the checks read that instead. Every rule it applies came off a rendered page, but
# one of them guesses: page kʷ and page wist both arrive as w, and the draft labializes a w after the
# consonants that take it. Until a person has read the pages, .page.txt is a draft and these two
# papers are still listed here.
NOT_FAITHFUL = ("19-Lyon_ICSNL50_final-78", "2013_Lindley_Lyon")

# What to read for a paper whose extraction is not the page.
PAGE_TEXT = "%s.page.txt"

# Papers whose extraction holds none of the orthography and which have no drafted page text either.
# These are OCR of typed pages, not a font encoding, so there is no mapping to invert: the scan lost
# the marks and nothing in the file records what they were.
#
# Counted over the nine marks the corpus uses, in every registered paper's text. These four hold
# zero schwa, zero barred l, zero barred lambda, zero c and s with caron, zero raised w, zero comma
# above, zero caron and zero dot below. 1975_Hilbert_Hess writes taqWsablu where the page prints
# taqʷšəblu, and 1967_Hess writes "The Lorph I-(e)bl in Snohomish" for "The Morph /-(ə)b/ in
# Snohomish". 1967_Elmendorf loses the English too, printing TES'l'S OF A HYPOfBESIS and dating
# itself 1961.
#
# All three papers of ICSNL 2 read here so far are in this state, which is a fact about the 1967
# typescripts and not about any one of them. Registering 1967_Hamp without this entry put 338
# disagreements into the tree in one step, every one of them the scan and none of them the reader.
#
# 19-Lyon_ICSNL50_final-78 and 2013_Lindley_Lyon count zero on the same nine and are not here,
# because draft_page_text.py can put their orthography back from the font encoding. 1983_Hilbert
# counts zero as well and is not here either: its text encodes the orthography another way, its
# entry declares that alphabet as DAMAGED, and its hand extraction was written to match.
#
# A hand extraction of one of these cannot be checked against its paper's text, because that text is
# not the paper. Reporting the difference as disagreements grades a correct reading against a file
# the reading is right to differ from. The check states the condition instead and counts nothing.
# What would settle them is a page text transcribed from the scan, the way the two Lyon papers have
# one generated.
ORTHOGRAPHY_ABSENT = ("1975_Hilbert_Hess", "1967_Hess", "1967_Elmendorf", "1967_Hamp")

# The oracle's filename, the paper's stem in build/papers, the record the reader wrote, the repair
# that reader applies to its source, what that paper writes its language with, and whether its
# extraction breaks words across lines. The last one is the gate coverage_check.py already applies:
# line_breaks.py repairs one paper's defect and welds words in the papers that do not have it.
EVERY = tuple((one.oracle, one.stem, one.record, one.repair, one.marks, ("line joins" in (one.coverage or ()))) for one in PAPERS)
