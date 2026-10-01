#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The whole ban table, in the order a hit is reported through.
#

from .bans_detected import DETECTED
from .bans_outright import OUTRIGHT
from .bans_probe import PROBE
from .bans_register import REGISTER
from .bans_shapes import SHAPES
from .locale import LOCALE



# The tokens the writing standard bans outright, and the British spellings it bans by pattern.
#
# LOCALE is spliced in and is the single copy of the British patterns. The order of the groups is
# the order a hit is reported through: where two patterns overlap a site, whichever group BANNED
# reaches first names it. Reordering these changes which pattern a finding is attributed to.
BANNED = OUTRIGHT + LOCALE + REGISTER + SHAPES + PROBE + DETECTED



# ====================================================================
# WITHDRAWN: THE UNBOUNDED WORD BANS THAT ARE DELIBERATELY NOT IN FORCE
# ====================================================================
#
# Named rather than left absent, because an absence reads as an oversight and gets filled in. Every
# entry here is a bare word ban that must not be added, with the rule that excludes it.
#
# THE RULE THAT EXCLUDES THEM. code-documentation section 143: "a word that reads as a tic in one
# construction only is bounded to that construction: paradigm shift is banned where paradigm is
# not." And the escape immediately before it: "A term the field owns stays."
#
# THE TEST IS MECHANICAL. Neither standard bans any of these. Both standards USE eleven of them as
# ordinary technical English, in the same documents that authorize this checker:
#
#   carries      code-documentation:145  "carries this list as regexes"
#   holds        code-comments:208       "holds the list as regexes"
#   reads        code-comments:208       "reads .c and .h comments and docstrings"
#   spends       code-documentation:84   "it spends a reader's trust before it wastes their time"
#   buys         code-documentation:85   "breaks the line the prose is walking and buys nothing"
#   construction code-comments:199       "are essay construction, not comment construction"
#   costs        code-documentation:108  the register a rule applied wrongly costs a paragraph
#   carry        code-documentation:104  "A documented pointer with no token is an unanswered
#                                        question"; :161 "correct when carried by a real name"
#   slot         code-comments:195       "Name a Handle by Its Slots" -- a handle slot is this
#                                        tree's own term of art, named in a section heading
#   earns        code-documentation:114  "each one earned its place by measurement"
#   book         code-documentation:158  "A name already sitting in the tree is not evidence"
#
# A bare ban on any of these flags the standard that authorizes this checker, in the standard's own
# running prose, outside any code span. A rule that reports the document stating it is transcribed
# wrong.
#
# WHY NONE OF THEM CAN BE BOUNDED THE WAY paradigm shift IS. The construction they read as a tic in
# is an inanimate subject taking a human verb, and no regex separates it from the correct technical
# use. "The header carries the checksum" and "the buffer holds the segment" are the right verbs in
# a network stack, and they are character for character the shape a bare ban is after. What IS
# bounded is the is-what-VERB construction near the head of this tuple, which both standards name,
# and that is where these belong.
#
# THE COST OF GETTING IT WRONG IS RECALL, not precision. A bare ban on this class buries a report
# under correct technical English, and the true findings go down with it. Measure per word before
# adding one: the weight sits on hold, carry and read, and a ban on those three alone can be the
# majority of a whole report.
#
# Each entry is the word, what it was after, and the sentence that removed it.
WITHDRAWN = {
    "carry": "the verb in every inflection, banned, a digest would be said to be listed in a "
    "manifest instead. Both standards use it and code-documentation:145 uses it about "
    "this file. 518 hits in idemIP/src at 29a808c.",
    "hold": "added when the repair pass for carry wrote hold everywhere instead. Chasing a "
    "synonym is the sign that the rule is on a word and not on a shape. 658 hits in "
    "idemIP/src at 29a808c, the single largest pattern in the table.",
    "read": "a fold does not read and a person does, which is true and is not what \\breads\\b "
    'tests. code-comments:208 writes "reads .c and .h comments". 337 hits.',
    "slot": "nothing in the theory research papers has slots, which is a house naming rule about one "
    "directory. code-comments:195 makes a handle slot a term of art in a section "
    "heading. 134 hits.",
    "cost": "say the number and its units. The instruction is right and the ban is not: a cost "
    "is what a number measures. 66 hits.",
    "buy": 'the transaction metaphor. code-documentation:85 writes "buys nothing the reader '
    'asked for" and code-comments:178 writes "The letter buys explicitness". 1 hit.',
    "pay": "the same metaphor, one verb over. 2 hits.",
    "spend": 'the same again. code-documentation:84 writes "it spends a reader\'s trust". 6 hits.',
    "earn": 'the same again. code-documentation:114 writes "each one earned its place by '
    'measurement", the sentence that justifies half this table. 1 hit.',
    "afford": "the same again, and one of the three that fired nowhere in idemIP/src at all.",
    "win": "an arm does not win. True, and the word has a plain use the ban could not see. 3 hits.",
    "price": "added, a repair pass could not swap cost for it. A ban added to close the exit "
    "from another ban is the shape of a rule that is chasing words. 0 hits.",
    "book": "these are theories, which is a naming rule about this tree's own vocabulary and "
    "carries no claim about register at all.",
    "construction": 'it is a method. Same shape as book, and code-comments:199 writes "essay '
    'construction, not comment construction" while stating a rule this file '
    "implements.",
}
