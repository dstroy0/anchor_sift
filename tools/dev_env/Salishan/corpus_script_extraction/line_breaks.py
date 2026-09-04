#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Put back together a word 2012_Robertson's extraction broke across two lines.
#
#   Usage:  from line_breaks import joined
#
# That paper's extraction ends a line in the middle of a word and carries on under it, 42 times.
# Some of the breaks fall inside an interlinear gloss: A above UG-, s above ick, gr above eet, hu
# above man.being. Left alone they put half-words in the corpus and lose the other half.
#
# Two shapes have to be told apart and the leading whitespace of the line under the fragment is what
# tells them. A word the extraction cut in half continues at column 0, so it closes up: ma above
# ximal is maximal. A column that wrapped is indented to its own column, so it keeps the space that
# was between the two words: oh above four spaces and then EP is oh EP.
#
# The alphabet tables are where a join would be wrong. Chinuk pipa's letter names wa, wi and waw sit
# one to a line and joining them invents words nobody wrote. They are refused by length: the line
# under a fragment has to carry something before the join is taken.
#
# This lives in its own file because coverage_check.py has to apply it too. That check compares the
# source against the extraction and its own header says both sides go through the same
# transformation first, so a join the reader makes and the check does not report every welded word
# as a hole.

import re

# A line of a numbered stanza. The number is stepped over before the rest is measured.
NUMBERED = re.compile(r"^(\d{1,3})\s+(\S.*)$")

PAGE = re.compile(r"^===== page \d+ =====$")

# How short a run has to be before it reads as half of a broken word. Every fragment these breaks
# leave in the paper is five characters or fewer.
FRAGMENT_LETTERS = 5

# How much the line under a fragment has to carry before the join is taken. The alphabet tables set
# wa above wi above yu, and four characters is what separates those from gr above eet -?.
JOIN_FLOOR = 4


def fragment(trimmed):
    """Whether a line is half of something the extraction broke across a line break.

    Two shapes. A bare stanza number, which is how Text 2 sets stanza 1: the 1 is alone and patah is
    under it. And a short run with a letter in it, with any stanza number stepped over first, which
    is how Text 1 sets the same stanza: 1 o above l ha l kukpi.

    Letters alone is too narrow for the second one. The morphemic row opens a root with a slash and
    stanza 5's broke at /té above km w -s, so a fragment required to be all letters leaves it.
    """
    if trimmed.isdigit():
        return True
    body = trimmed
    found = NUMBERED.match(trimmed)
    if found:
        body = found.group(2)
    return (bool(body) and (len(body) <= FRAGMENT_LETTERS)
            and not any(one.isspace() for one in body)
            and any(one.isalpha() for one in body))


def joined(lines):
    """The lines with each broken word put back together, and the welds it made.

    Takes the lines with their leading whitespace, because that is what says whether a break is
    inside a word or between two columns. Returns the repaired lines trimmed, and the welds as
    (line number, fragment, what followed it), so a caller can report every join it took.
    """
    held = []
    welds = []
    at = 0
    while at < len(lines):
        raw = lines[at + 1] if (at + 1) < len(lines) else ""
        trimmed = " ".join(lines[at].split())
        following = " ".join(raw.split())
        if (trimmed and fragment(trimmed) and (len(following) >= JOIN_FLOOR)
                and not PAGE.match(following)):
            between = " " if raw[:1].isspace() else ""
            held.append("%s%s%s" % (trimmed, between, following))
            welds.append((at + 1, trimmed, following))
            at += 2
            continue
        held.append(trimmed)
        at += 1
    return held, welds
