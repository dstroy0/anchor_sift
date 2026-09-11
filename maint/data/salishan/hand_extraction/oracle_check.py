#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Check a hand extraction against the paper it was read off.
#
#   Usage:  python maint/data/salishan/hand_extraction/oracle_check.py
#
# The hand extraction is the control every reader is graded against, which puts the whole weight of
# the corpus on it being right. A person reading a thirty-seven page paper into a table skips rows
# and mistypes marks, and neither shows up later as anything but a corpus that quietly disagrees
# with the paper.
#
# So the table is checked against the paper both ways. Every form written down has to be findable in
# the source, which catches a mistyped mark and an invented row. Every word in the source has to
# appear in some form written down, which catches a skipped row and a table read only halfway. The
# second direction finds omissions, and omissions are what a person reading by hand
# actually produces.
#
# Both sides go through the paper's repairs first, for the reason coverage_check.py states: comparing
# a repaired hand extraction against an unrepaired source reports every correctly repaired word as
# missing.

import io
import os
import sys
import unicodedata

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
HERE = os.path.dirname(os.path.abspath(__file__))

# The hand extractions are evidence and not tooling, so they live in the research body beside the
# prose that cites them. The language in them belongs to the people who spoke it, and their names
# open every table and the README beside them.
ORACLES = os.path.join(ROOT, "build", "oracles")

sys.path.insert(0, os.path.join(os.path.dirname(HERE), "corpus_script_extraction"))

# Imported under another name because this file already binds `joined` as a local, for the token
# welded out of a run of pieces. Two different joins, and shadowing one with the other reads as a
# missing value at run time. It is a name collision.
from line_breaks import joined as joined_lines  # noqa: E402
from salish_unsorted import is_language_token  # noqa: E402

from papers import EVERY, NOT_FAITHFUL, ORTHOGRAPHY_ABSENT, PAGE_TEXT  # noqa: E402

EDGES = ".,!?;:“”\"()[]…«»{}/*•→≤≥"

# Hall and Phillips write the null third person clitic with a symbol font, and the extraction
# carries that glyph through as a private use character. It stands where a morpheme is not
# pronounced, so it is never part of a form, and it sits inside a token as often as at the end of
# one: cw-[n]-t-<glyph>-és=us is one word with one unpronounced morpheme in the middle of it.
NULL_CLITIC = ""

# The single quote is not in EDGES because several of these orthographies write with it. ’ is the
# glottalization mark in Nuxalk and in Lyon's Okanagan, and stripping it turned the enclitic ˽c’
# into ˽c, a string neither the paper nor the hand extraction holds. It comes off only as one half
# of a pair around a gloss.
PAIRED = (("‘", "’"), ("'", "'"), ("“", "”"))

# How many tokens one broken word may arrive as. A pair covers the papers that break before a
# marked letter, where các l̓ep is two. Lyon's break more than once: nt̓ə k̓ʷt̓í k̓ʷləx is three
# pieces of one word and s- m̓ y̓- m̓ y̓-á y̓-s is five, and a table holding the whole word had every
# piece of it reported as a word no row covers.
#
# Six is where these two papers stop. Reading it higher costs a longer join list and a larger
# chance that some run of tokens accidentally spells a form the table wrote down wrongly, the only
# thing direction one exists to catch.
PIECES = 6

# The mark Lyon opens every parsed root with.
ROOT_MARK = "√"

# What stands in front of a √ inside one parse. yaQ•√yáQt is a reduplicant and its root, n+√ ’ks+tan
# a preposition and its root: one form each. A √ with anything else in front of it is the point
# where the extraction ran a surface line into the parse line under it.
INSIDE_PARSE = "+-•="


def surface_parse_join(token):
    """Where a token runs a form into its own parse, the position the parse starts at, else -1."""
    at = token.find(ROOT_MARK)
    if (at <= 0) or (token[at - 1] in INSIDE_PARSE):
        return -1
    return at

# The Latin ligatures a PDF sets f-words with. None of these orthographies uses one, so every
# occurrence is the typesetter's and the letters underneath are what the paper says. Lyon's
# translations carry ﬁnish, ﬁll and ﬁrst, and a table typed at a keyboard holds none of them.
LIGATURES = (("ﬁ", "fi"), ("ﬂ", "fl"), ("ﬀ", "ff"), ("ﬃ", "ffi"), ("ﬄ", "ffl"))

# The three spellings of one apostrophe, folded to the plain one. A typesetter sets ’ where a
# person at a keyboard types ', and NFC does not unify them because they are separate characters
# and not normalization variants. ICSNL58_Givens_Hall_final holds 39 plain apostrophes in its form
# column against 62 typographic ones in the paper, and the checker could never match those rows.
#
# This folds and never strips. ’ is the glottalization mark in Nuxalk and in Lyon's Okanagan, and
# taking it off is the fault the PAIRED note below was written about. Folding leaves the mark on
# the form and only settles which codepoint it is written with, so a glottalized form still has to
# meet a glottalized form and can never match a plain one.
QUOTES = (("’", "'"), ("‘", "'"))


# A footnote number, a second closing quote, and a mangled one. All three sit past the sentence's
# own punctuation: tuʔúʔt.6 puts the marker after the period, yéyeʔ?”’ closes the inner quote after
# the outer one, and tea.̓ is a ’ the PDF left as a bare combining mark. Peeling any of them off the
# end of a word outright takes the glottalization off ˽c’ and the 3 off a 3OBJ gloss. Each comes off
# only where an EDGES character stands in front of it.
def trailing_marker(plain):
    """One token with a footnote marker and a doubled closing quote off the end of it."""
    while len(plain) > 1:
        at = len(plain)
        while (at > 0) and plain[at - 1].isdigit():
            at -= 1
        # A footnote marker set against a word that ends in a stacked mark, as Hall and Phillips'
        # nhén̓4 is. 7 is the glottal stop in the van Eijk orthography. A run that is only 7 is
        # the word's own last letter and stays.
        if ((at < len(plain)) and (at > 0) and (plain[at] != "7")
                and unicodedata.combining(plain[at - 1])):
            return plain[:at].strip(EDGES)
        # Nothing numeric came off, so look for the quote forms instead.
        if (at == len(plain)) and ((plain[-1] == "’") or unicodedata.combining(plain[-1])):
            at -= 1
        # A footnote marker set past a closing quote, as walk.’17 is. The ’ counts as a quote only
        # where the sentence's own punctuation stands in front of it, which keeps ˽c’ whole.
        elif (at > 1) and (plain[at - 1] == "’") and (plain[at - 2] in EDGES):
            at -= 1
        if (at == len(plain)) or (at == 0) or (plain[at - 1] not in EDGES):
            break
        plain = plain[:at].strip(EDGES)
    return plain


# A footnote number set in front of the word it marks, as Mary George's 70gagayat is. The two
# numbers stack: (28)140chechlhem carries the line number and the footnote number both, so the strip
# runs until nothing more comes off. 7 is the glottal stop in the van Eijk orthography, so 7amash
# and t7u open with a digit and are whole words. A run of one 7 stays; a run holding any other digit
# is the marker.
def leading_marker(plain):
    """One token with the line and footnote numbers off the front of it."""
    while True:
        at = 0
        while (at < len(plain)) and plain[at].isdigit():
            at += 1
        if (at == 0) or (at == len(plain)) or (plain[:at] == "7"):
            return plain
        plain = plain[at:].lstrip(EDGES)


# A footnote marker set against a word that ends in a plain letter, as Lyon's zuxʷt5, ʕant7 and
# ks-cúy-iʔ-səlx11 are. trailing_marker leaves those alone, and it has to: a run of digits at the end
# of a word is the word's own last letter in the van Eijk orthography, where skúza7 and Cw7aoz spell
# the glottal stop as 7.
#
# So this is never applied. It is offered as a second string to look for, the way a slashed cell and
# a hyphen join are, and direction two lets a token through only when the table holds the form
# without the marker. Both sides then have to agree before anything is skipped, and a paper that
# writes 7 as a letter is unaffected because its rows carry the 7.
def without_marker(plain):
    """One token with a trailing run of digits off the end of it, or the token as it came."""
    at = len(plain)
    while (at > 0) and plain[at - 1].isdigit():
        at -= 1
    if (at == len(plain)) or (at == 0) or (not plain[at - 1].isalpha()):
        return plain
    return plain[:at]


# The letters of the paper currently being checked, set once per paper by main.
#
# Module state, because bare() is reached from eight places across three functions and the paper is
# the same for all of them within one check. It sits beside EDGES, PAIRED and LIGATURES, which are
# the same kind of fact about how a paper is written; this is the part of that which changes per
# paper instead of holding for all of them.
MARKS = ""


def edges_for(marks):
    """The punctuation to strip, with this paper's own letters taken out of it.

    Off by default. Turning it on for every paper moved the tree from 438 disagreements to 457,
    and Hilbert_Hess stayed at exactly 200. Pass an explicit `marks` to use it for one call.
    """
    return "".join(one for one in EDGES if one not in (marks or ""))


def bare(token, marks=None):
    """One token with the punctuation around it off, and its orthography left alone.

    An opening quote always comes off: no orthography here starts a word with one. A closing quote
    comes off only where an opening one is on the same token, because ’ ends real words in Nuxalk
    and in Lyon's Okanagan.

    `marks` is the paper's own letters, and anything in it is not punctuation for that paper. It
    defaults to the paper under check, which main sets before reading either side of it.
    """
    edges = edges_for(MARKS if marks is None else marks)
    plain = token.replace(NULL_CLITIC, "")
    for ligature, letters in LIGATURES:
        plain = plain.replace(ligature, letters)
    plain = plain.strip(edges)
    for opens, closes in PAIRED:
        if (len(plain) > 1) and plain.startswith(opens) and plain.endswith(closes):
            plain = plain[1:-1].strip(edges)
    while plain and (plain[0] in "‘“"):
        plain = plain[1:].strip(edges)
    plain = leading_marker(trailing_marker(plain))
    # Last, after every strip has run. Folding earlier turns ’form’ into 'form', which PAIRED then
    # takes the quotes off both ends of, and one of those ends was the glottalization mark. The
    # strips have to see the characters the page actually printed; only the comparison needs the
    # two spellings settled.
    for typographic, plain_quote in QUOTES:
        plain = plain.replace(typographic, plain_quote)
    return plain

# What a form may be built out of besides its letters. A morpheme boundary, a clitic boundary, a
# reduplication tilde and the parentheses around a deleted segment are all part of how the paper
# writes a form, and splitting on them would compare pieces the paper never printed apart.
INSIDE = "-=~()"


def pieces(form):
    """One written form as the strings a source line could hold it as.

    Composed the same way the source is. A hand extraction is typed at a keyboard that composes á as
    one character while the paper sometimes writes it as two, and without this every accented form
    written by hand is reported as one the paper does not hold.
    """
    held = set()
    for token in unicodedata.normalize("NFC", form).split():
        plain = bare(token)
        if plain:
            held.add(plain)
    return held


def oracle_rows(path):
    """Every row of a hand extraction, as where, who, kind, form, gloss.

    Twenty-four of the twenty-five files declare that header. Mellesmoen_Kye_ICSNL61 declares
    `dialect` in the second column and fills it with dialect labels instead of the people who
    spoke. That is an open question and not a settled second shape, so this reader takes the
    column by position and compares it against nothing, and both files parse.
    """
    held = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if (len(fields) < 4) or (fields[0] == "where"):
                continue
            held.append((fields[0], fields[1], fields[2], fields[3],
                         fields[4] if len(fields) > 4 else ""))
    return held


def wrong_width(path):
    """Every row that is not four or five fields wide, as (line number, field count).

    Four is a row with no gloss and five is a full one. Every oracle on disk is one or the
    other, so any other width is damage and not a shape somebody chose.

    A short row is dropped by oracle_rows and says nothing. A wide one is worse, because it is
    kept and everything past the fifth field goes unread. One tab written where a space belongs
    turns `n > <null> / n_` into `n > <null>`, moves the conditioning environment into the gloss
    column where nothing reads it as one, and drops the name of the rule off the end. A
    conditioned rule becomes an unconditional one, attributed to a named language, and the row
    still looks well formed. Four rows of one staged copy carried exactly that for four months.
    Nothing caught it because one byte had been swapped for one byte: same file size, same line
    count, same row count.
    """
    held = []
    with open(path, encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if fields[0] == "where":
                continue
            if len(fields) not in (4, 5):
                held.append((number, len(fields)))
    return held


def source_forms(path, repair=None, pieces=2, line_joins=False):
    """Every string of a paper a written form could be looking for, with the line it sits on.

    pieces is how many tokens one broken word may arrive as, and it is 2 for a paper whose text is
    the page. Only the drafted ones need more, and giving it to every paper tripled the lookup on
    the nine that do not, which is a lot of strings for direction one to accidentally agree with.

    Three things beyond splitting on spaces. A cell can hold two alternants divided by a slash, as
    Table A2 does at dᶻəlč̓/ǰəlč̓. Each half of a slashed token is offered as well as the whole
    token, which keeps the constraint name *P/ə findable too. A form can be broken across a line break,
    as sčəbíd-ac is in both of the Figure 7 captions, and a line ending in a hyphen is also offered
    joined to the line after it. All of this widens what a lookup finds and none of it builds a
    corpus. An over-join here costs nothing but a question not asked.
    """
    held = {}
    # What the paper actually prints, without the joins and halves offered above. Direction two asks
    # about these. Asking about a join would make every accidental pairing a hole to answer for.
    printed = set()
    # Each printed token against what it makes when welded to the token beside it. A PDF that breaks
    # a word before a marked letter leaves các and l̓epa, and the hand extraction has cácl̓epa. Both
    # halves are then words the paper prints that no row holds, and neither is a row anybody should
    # write: the word is one word.
    welds = {}
    previous = ""

    # The same line joining coverage_check.py already applies, applied here too.
    #
    # This check joined a line to the one under it only where the first ended in a hyphen. A PDF
    # that breaks a word with no hyphen leaves two fragments and this check saw two words. A form
    # the reader wrote whole then read as a form the paper does not hold. 2012_Robertson's epigraph
    # splits across two lines with no hyphen and could not be repaired at all.
    #
    # line_breaks.joined is the repair coverage_check has used all along, and its own header says
    # both sides have to go through the same transformation or a join the reader makes and the check
    # does not reports every welded word as a hole. The two checks were reading different text.
    #
    # Applied only where the paper's own config asks for it, which is the gate coverage_check has:
    # `if "line joins" in repairs`. Running it as a measurement over all twenty papers first took
    # the disagreement count from 441 to 2287. line_breaks.py is written for one paper's defect and
    # welds words in the nineteen that do not have it, inventing forms nobody wrote. The repair is
    # right for 2012_Robertson and wrong everywhere else, and a shared transformation applied
    # unconditionally is a different error from the one it was fixing.
    with open(path, encoding="utf-8", errors="replace") as handle:
        raw = [one.rstrip("\n") for one in handle]
    lines = joined_lines(raw)[0] if line_joins else [one.rstrip() for one in raw]

    for number, line in enumerate(lines, 1):
            if line.startswith("====="):
                continue
            # NFC on both sides, always. Two strings are the same string only after it, and skipping
            # it reports ǰ typed at a keyboard as absent from a paper that prints ǰ on ten lines.
            # It runs after the repair. Composing a with a combining acute into á first takes that
            # acute out of the set of marks whose following space gets closed, and the repair then
            # misses every word the PDF split at an accent. The repair ends in NFC for the same
            # reason; without that, 164 of one paper's forms came back as destroyed by the repair.
            line = repair(line.rstrip()) if repair else line.rstrip()
            line = unicodedata.normalize("NFC", line)
            reach = [line]
            if previous.endswith("-"):
                # Both readings of the hyphen at a line end. sčəbíd- ac is one Salish form whose
                # hyphen is a morpheme boundary and stays; Lyon's English translations are typeset,
                # and hold- ing is one word whose hyphen the typesetter put there.
                tail = previous.split()[-1]
                reach.append("%s%s" % (tail, line.lstrip()))
                reach.append("%s%s" % (tail[:-1], line.lstrip()))
            previous = line
            for at, one in enumerate(reach):
                tokens = one.split()
                for where, token in enumerate(tokens):
                    # The half of a wrapped form left at a line end is not a form to ask about; the
                    # join built from it above is. p̓il- ‘flat’ ends in a hyphen too and is a real
                    # prefix, and only the last token on a line is dropped for that reason.
                    #
                    # It stays in the lookup all the same, because the page does print those
                    # characters at that place. Lyon's interlinear arrives one token per line, so
                    # every token in it is the last on its line, and dropping them outright lost
                    # an-, a-ks- and ʔakɬ-, which are forms the paper prints on their own.
                    wrapped = ((at == 0) and (where == (len(tokens) - 1)) and token.endswith("-"))
                    # The token itself, its slash-separated halves, and it joined to the tokens
                    # after it. The last of those is for the PDFs that break a word before a
                    # marked letter: cácl̓ep arrives as các l̓ep, and the hand extraction records
                    # the word. A join offered here only widens what a lookup finds.
                    plain = bare(token)
                    if plain:
                        held.setdefault(plain, number)
                        # Only the line as printed adds to printed. The hyphen-join built above is
                        # a lookup candidate, and counting its tokens made ł-AUX, the tail of one
                        # line welded to the head of the next, a word the paper holds.
                        if (at == 0) and not wrapped:
                            printed.add(plain)
                    reach = list(token.split("/"))
                    # The same token without a footnote marker welded to its last letter.
                    if plain:
                        reach.append(without_marker(plain))
                    # Lyon's five-line interlinear puts a form on one line and its parse on the
                    # next, and the extraction runs the two together wherever the parse opens with
                    # the root mark: cáwt@t,√cáwt-tt is the word and its analysis in one token. A √
                    # anywhere but the front is that join, and both sides are offered.
                    at_root = surface_parse_join(token)
                    if at_root > 0:
                        reach.append(token[:at_root])
                        reach.append(token[at_root:])
                    for span in range(2, pieces + 1):
                        if (where + span) > len(tokens):
                            break
                        run = tokens[where:where + span]
                        # The join is offered with and without a footnote marker on the end of it.
                        # n-t̓ə k̓[ʷ]-t̓í k̓[ʷ]-ləx2 is one word carrying a 2 and the row holds the
                        # word, while (s)K ékets’a7 ends in the letter van Eijk writes the glottal
                        # stop with and the row holds the 7. Offering only the stripped form lost
                        # the second one.
                        joined = bare("".join(run))
                        if not joined:
                            continue
                        reach.append("".join(run))
                        # A run can be a surface form and its own parse, broken in the middle as
                        # well: k̓ʷ l̓ncútn√k̓ʷ l̓-ncút+tn is k̓ʷl̓ncútn and √k̓ʷl̓-ncút+tn, and the
                        # table holds those two apart because the paper prints them on two lines.
                        halves = [joined, without_marker(joined)]
                        at_join = surface_parse_join(joined)
                        if at_join > 0:
                            halves = [bare(joined[:at_join]), bare(joined[at_join:])]
                            reach.extend(halves)
                        for piece in run:
                            broken = bare(piece)
                            if broken:
                                welds.setdefault(broken, set()).update(one for one in halves
                                                                       if one)
                    for part in reach:
                        plain = bare(part)
                        if plain:
                            held.setdefault(plain, number)
    return held, printed, welds


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    failed = 0
    waiting = []
    for name, stem, record, repair, marks, line_joins in EVERY:
        table = os.path.join(ORACLES, name)
        # A paper whose extraction is the font's encoding is checked against the drafted page text
        # instead, because the extraction is not what the paper says and comparing against it only
        # asks whether the table copied the damage correctly.
        source = os.path.join(PAPERS, (PAGE_TEXT if stem in NOT_FAITHFUL else "%s.txt") % stem)
        if not os.path.isfile(table):
            waiting.append(stem)
            continue
        if not os.path.isfile(source):
            out.write("  no paper on disk for %s\n" % stem)
            failed += 1
            continue

        # Set before either side is read, so the hand extraction and the paper are stripped by the
        # same rule. Stripping them differently is how a form that is in both reads as being in
        # neither.
        # Left empty. edges_for records what turning this on measured: 438 disagreements became
        # 457 and the paper it was aimed at did not move. The mechanism is available per call.
        global MARKS
        MARKS = ""

        rows = oracle_rows(table)

        # Width first, because it is structural and holds whether or not the content can be
        # graded. A paper in ORTHOGRAPHY_ABSENT returns before the counts below, and a damaged
        # row there is still a damaged row.
        wide = wrong_width(table)
        if wide:
            out.write("    %d row(s) of the wrong width\n" % len(wide))
            for number, count in wide:
                out.write("      line %-6d %d fields, expected 4 or 5\n" % (number, count))
            failed += len(wide)

        broken = PIECES if stem in NOT_FAITHFUL else 2
        held, printed, welds = source_forms(source, repair, broken, line_joins)
        raw = source_forms(source, None, broken, line_joins)[0]
        out.write("  %s%s\n" % (name, "   (against a drafted page text)"
                                if stem in NOT_FAITHFUL else ""))
        out.write("    %d rows read by hand, %d distinct tokens in the paper\n"
                  % (len(rows), len(held)))

        # Direction one. A form written down that the paper does not hold is a typing slip or an
        # invented row, and it would put a word nobody printed into the corpus.
        #
        # Asked against the unrepaired paper as well. A form the repair took out is a different
        # thing from a form nobody wrote. The person read it off the page correctly and the repair
        # then destroyed it. That is a fact about the repair and is reported as one.
        unfound = []
        cost = []
        written = set()
        for where, who, kind, form, gloss in rows:
            for piece in pieces(form):
                written.add(piece)
                if piece in held:
                    continue
                (cost if piece in raw else unfound).append((where, kind, form, piece))
        out.write("    %d forms the repair took out of the paper\n" % len(cost))
        for where, kind, form, piece in cost:
            out.write("      %-12s %-11s %-28s %s\n" % (where, kind, form, piece))
        out.write("    %d written forms the paper does not hold\n" % len(unfound))
        for where, kind, form, piece in unfound:
            out.write("      %-12s %-11s %-28s %s\n" % (where, kind, form, piece))

        # Direction two. A word in the paper that no row holds is a row the reader skipped. Only
        # tokens carrying a character of the language are asked about; the paper is otherwise
        # English prose and the hand extraction is not a transcription of that.
        missed = []
        for token, number in sorted(held.items(), key=lambda one: one[1]):
            if token not in printed:
                continue
            if not is_language_token(token, marks):
                continue
            # Half a word the PDF split. The hand extraction holds the whole word.
            if welds.get(token, set()) & written:
                continue
            # An English possessive on a name in the language. These papers are written in English
            # and put one on Kʷəɬtəzétkʷu’s. The word is the name, and the row holds the name.
            if token.endswith(("’s", "'s")) and (token[:-2] in written):
                continue
            # A capital opening a sentence. None of these orthographies tell two words apart by
            # case, so the Yéyeʔ that opens a translation is the yéyeʔ a row already holds.
            if token.lower() in written:
                continue
            # A footnote marker welded to the word it marks, as Lyon's zuxʷt5 is. The row holds the
            # word. A paper spelling the glottal stop as 7 keeps the 7 in its rows, so skúza7 is not
            # let through here by a row holding skúza.
            marked = without_marker(token)
            if (marked != token) and (marked in written):
                continue
            # A form run together with its own parse, as Lyon's extraction leaves cáwt@t,√cáwt-tt.
            # The table holds the word and the analysis apart, as the paper sets them.
            at_root = surface_parse_join(token)
            if (at_root > 0) and all((one in written) for one in
                                     (bare(token[:at_root]), bare(token[at_root:]))
                                     if is_language_token(one, marks)):
                continue
            # A slashed token is two forms printed in one cell, dᶻəlč̓/ǰəlč̓, and the hand
            # extraction gives each of them its own row. Asking for the whole string back would
            # make a row per printing accident.
            if all((one in written) for one in token.split("/")
                   if is_language_token(one, marks)):
                continue
            missed.append((number, token))
        out.write("    %d language tokens in the paper that no row holds\n" % len(missed))
        for number, token in missed:
            out.write("      line %-6d %s\n" % (number, token))

        # A paper whose text lost the orthography is not something the table can be graded against.
        # The counts above are still printed, because hiding them would hide the size of the gap,
        # but they are not disagreements: the reading is right and the file it is being compared
        # with is not the paper.
        if stem in ORTHOGRAPHY_ABSENT:
            out.write("    not counted. This paper's text holds none of its orthography and it has "
                      "no page text,\n    so the two sides above are not comparable. See "
                      "ORTHOGRAPHY_ABSENT in papers.py.\n")
            continue

        failed += len(unfound) + len(missed)

    out.write("\n  %d of %d papers have a hand extraction\n"
              % (len(EVERY) - len(waiting), len(EVERY)))
    if waiting:
        out.write("  still to be read by hand:\n")
        for stem in waiting:
            out.write("    %s\n" % stem)
    out.write("\n  %s\n" % ("every hand extraction agrees with its paper" if not failed
                            else "%d disagreements to work through" % failed))
    out.flush()
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
