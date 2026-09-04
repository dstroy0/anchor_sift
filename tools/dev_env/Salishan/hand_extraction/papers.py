#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
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
# That is what happened. This file held the alphabets and coverage_check.py held the same alphabets
# written out a second time as literals, and the two disagreed on the repair for two papers before
# anyone noticed. Both now read corpus_script_extraction/paper_config.py, which is the one place a
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

# The oracle's filename, the paper's stem in build/papers, the record the reader wrote, the repair
# that reader applies to its source, and what that paper writes its language with.
EVERY = tuple((one.oracle, one.stem, one.record, one.repair, one.marks) for one in PAPERS)
