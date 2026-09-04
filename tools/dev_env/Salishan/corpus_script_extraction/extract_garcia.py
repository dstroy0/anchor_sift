#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the nɬeʔkepmxcín of Kʷəɬtəzétkʷu (Bernice Garcia) from ICSNL 59, following that paper's own
# structure and its own glossing categories.
#
#   Usage:  python tools/dev_env/extract_garcia.py
#
# Written for one paper. Reading the whole of it first is what this file is an argument for: stories 1 and
# 2 number their parts X.1 preamble, X.2 nɬeʔkepmxcín, X.3 English, X.4 gloss, and story 3 has no preamble
# subsection, so it runs 6.1, 6.2, 6.3 instead. A rule that assumed X.4 returned nothing for story 3 and
# reported no error, which is how a third of a paper leaves without anyone noticing.
#
# Kʷəɬtəzétkʷu moves between her languages inside her own telling, in the introduction and again inside
# stories 2 and 3, and the paper glosses those English words as part of the sentence. A line she mixed is
# kept whole and its spans are marked in place, because splitting it means deciding for each word which
# language it belongs to, and us, te and kn are words in both.
#
# The gloss categories are the paper's own, taken from its footnote 1 and used unchanged. Renaming them
# would make this file disagree with the source it came from.
#
# Two files come out. One holds everything found, marked, so nothing is lost and a reader can check it
# against the paper. The other holds only what she said in the target language, with no gloss, no
# segmentation, no translation and no marks, which is what gets ingested.
#
# Bernice Garcia asked that it be acknowledged that she is a Kamloops Indian Residential School speaker
# who is re-learning her language. That is recorded in the output because she asked for it.

import io
import os
import re
import sys

from inserted_space import closed_spaces
from salish_marking import (DERIVED, SPOKEN, UNCLASSIFIED, rendered, switches,
                            tagged_spans)
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

# Walk up to the tree that holds build/. Counting directories has been wrong twice now, once when
# these moved into Salishan and again when they moved into categories.
ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "ICSNL59_Garcia_Hannon_Stacey_final.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "Kweltezetkwu-BerniceGarcia_ThreeGlossedNlekepmxcinNarratives_GarciaHannonStacey"
    "_Salish_nlekepmxcin_2024_mixed.txt")

PAGE = re.compile(r"^===== page \d+ =====$")
HEADING = re.compile(r"^(\d+\.\d+)\s+(\S.*)$")

# A sentence number can follow a closing quote with no space, as in tékɬ!”18. where 17 ends and 18
# begins. Requiring whitespace before the number lost that sentence and reported only a total one
# short, which is why the numbering gaps are checked at the end of this run.
NUMBERED_INLINE = re.compile(r"(?:(?<=^)|(?<=\s)|(?<=[”\"'’.!?]))(\d{1,3})\.\s")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,3})\)\s*(.*)$")
COMMENT = re.compile(r"^Comment:\s*(.*)$")

# The free translation opens a line and this paper writes it with either quote. Narrowing this to
# the single quote, which is what the two Lyon papers needed, cost seven translations here: this
# paper does open a translation with a double quote. The convention is per paper and not a family.
QUOTED = re.compile(r"^['‘“\"]")

# A segmentation line writes each morpheme on its own and joins them with a hyphen or an equals
# sign, which is the positive evidence that a line is one. Without this test the branch below filed
# a line as segmentation because nothing else had matched it, and a line nothing matched is exactly
# the line nobody has looked at.
SEGMENTED = re.compile(r"[-=]")

# The category labels the paper defines in its footnote 1 and uses on its gloss line
CATEGORIES = re.compile(
    r"\b(?:AUT|CHR|CNSQ|CTR|DESID|DIM|DVL|EMPH|EXT|IMM|INCH|INDEP|INFER|INT|INTS|LC|MOD|"
    r"PROSP|RLT|RPRT|SENSE|STAT|TAG|NMLZ|DET|DEM|OBL|IPFV|NEG|PL|SG|DU|POSS|ERG|OBJ|SBJ|"
    r"SBJV|TR|IMP|RECP|RFL|BEN|INDR|INS|LOC|COMPL|EXCL|CAUS|PRP|LENGTH|HYP|COMP|D/C|"
    r"1SG|2SG|3SG|1PL|2PL|3PL)\b")

# Section number, which story it belongs to, and what it holds. This paper numbers story 3
# differently from stories 1 and 2, so the mapping is written out instead of computed.
SECTIONS = (
    ("3.1", "introduction", "target"),
    ("3.2", "introduction", "english"),
    ("4.1", "story 1", "english"),
    ("4.2", "story 1", "target"),
    ("4.3", "story 1", "english"),
    ("4.4", "story 1", "gloss"),
    ("5.1", "story 2", "english"),
    ("5.2", "story 2", "target"),
    ("5.3", "story 2", "english"),
    ("5.4", "story 2", "gloss"),
    ("6.1", "story 3", "target"),
    ("6.2", "story 3", "english"),
    ("6.3", "story 3", "gloss"),
)

# Everything she said is spoken, including the translations, which the paper states she made
# herself. The segmentation normalizes each morpheme to an underlying form and the gloss is written
# in category labels, so neither is a record of anything uttered.
# Her self-introduction sits in the acknowledgments footnote on the first page, ahead of every
# numbered section. A reader that starts at the first heading never reaches it. It is the one
# place in the paper where she gives her traditional name and says where her home is, in her own
# language, and the coverage check found it missing along with fifteen other tokens from that page.
INTRODUCES = re.compile(r"introduces herself thus:\s*(.+)$", re.IGNORECASE)

LAYER = {
    "self-introduction": SPOKEN,
    "transcription": SPOKEN,
    "running speech": SPOKEN,
    "translation": SPOKEN,
    "free translation": SPOKEN,
    "speaker comment": SPOKEN,
    "segmentation": DERIVED,
    "gloss": DERIVED,
    # Kept and marked, held out of the ingestion stream until someone has classified it.
    UNCLASSIFIED: DERIVED,
}


def sectioned(lines):
    """Every X.N section of the paper, as its number and the lines under it.

    A dot is required in the number. Footnotes at the foot of these pages open with their marker and
    then prose, which matches a bare number heading, and reading those as sections refiled everything
    after each one and emptied story 3 entirely.
    """
    held = {}
    current = None
    for line in lines:
        trimmed = line.strip()
        if PAGE.match(trimmed):
            continue
        found = HEADING.match(trimmed)
        if found:
            current = found.group(1)
            held.setdefault(current, [])
            continue
        if current is not None:
            held.setdefault(current, []).append(line.rstrip("\n"))
    return held


def inline_sentences(lines):
    """A paragraph of sentences numbered inline, split back into numbered sentences."""
    joined = " ".join(" ".join(line.split()) for line in lines if line.strip())
    pieces = NUMBERED_INLINE.split(joined)
    held = []
    walk = 1
    while (walk + 1) <= (len(pieces) - 1):
        text = " ".join(pieces[walk + 1].split())
        if text:
            held.append((int(pieces[walk]), text))
        walk += 2
    return held


def gloss_blocks(lines):
    """Each numbered gloss block: the transcription, the analysis lines, and any comment.

    The paper states that the transcription line "faithfully presents words as they were uttered,
    with no such normalization", so that line is what she said and the lines under it are analysis.
    """
    held = []
    number = None
    transcription = None
    analysis = []
    comment = None

    def close():
        if number is not None:
            held.append((number, transcription, list(analysis), comment))

    for line in lines:
        trimmed = line.strip()
        if PAGE.match(trimmed) or (not trimmed):
            continue
        found = NUMBERED_BLOCK.match(trimmed)
        if found:
            close()
            number = int(found.group(1))
            transcription = " ".join(found.group(2).split())
            analysis = []
            comment = None
            continue
        if number is None:
            continue
        said = COMMENT.match(trimmed)
        if said:
            comment = " ".join(said.group(1).split())
            continue
        analysis.append(" ".join(trimmed.split()))
    close()
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    # This PDF leaves a space after 856 of its glottalization marks, the most of any paper here, so
    # c̓ʔáq̓ʷ ‘wet’ arrives as three tokens and k̓ʷén̓s ‘she looked at it’ as two. Closed on the way
    # in. The stress accents are left alone, for the reason inserted_space.py gives.
    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [closed_spaces(one) for one in handle.read().splitlines()]

    held = sectioned(lines)
    rows = []
    empty = []

    # The self-introduction, taken from the front matter before any numbered section. It runs from
    # the marker to the point where the English rendering of it opens in quotes, and it wraps
    # across the lines of the page, and it is gathered from all of them.
    gathering = False
    said = []
    for line in lines:
        trimmed = " ".join(line.split())
        opened = INTRODUCES.search(trimmed)
        if opened:
            gathering = True
            trimmed = opened.group(1)
        elif not gathering:
            continue
        at = min((trimmed.find(one) for one in ("‘", "“") if one in trimmed), default=-1)
        if at >= 0:
            tail = trimmed[:at].strip()
            if tail:
                said.append(tail)
            break
        said.append(trimmed)
    if said:
        rows.append(("T", 0, "introduction", "front matter", "self-introduction",
                     " ".join(said)))

    for number, story, holds in SECTIONS:
        under = held.get(number)
        if not under:
            empty.append(number)
            continue

        if holds in ("target", "english"):
            mark = "T" if holds == "target" else "N"
            found = inline_sentences(under)
            if found:
                kind = "transcription" if holds == "target" else "translation"
                for count, text in found:
                    rows.append((mark, count, story, number, kind, text))
            else:
                kind = "running speech" if holds == "target" else "free translation"
                whole = " ".join(" ".join(one.split()) for one in under if one.strip())
                if whole:
                    rows.append((mark, 0, story, number, kind, whole))
            continue

        for count, said, analysis, comment in gloss_blocks(under):
            if said:
                rows.append(("T", count, story, number, "transcription", said))
            for one in analysis:
                # The translation is tested first. A translation can hold a word that matches a
                # category label, and testing the categories first filed six of them as gloss.
                if QUOTED.match(one):
                    rows.append(("N", count, story, number, "translation", one))
                elif CATEGORIES.search(one):
                    rows.append(("N", count, story, number, "gloss", one))
                elif SEGMENTED.search(one):
                    rows.append(("T", count, story, number, "segmentation", one))
                else:
                    rows.append(("T", count, story, number, UNCLASSIFIED, one))
            if comment:
                rows.append(("N", count, story, number, "speaker comment", comment))

    # Every line of the paper no section reached, added to the record as unclassified. The marked
    # file then holds every token of the language the paper printed, which is the whole point of
    # extracting it. They are held out of the pure stream and listed in the flag file, so this
    # makes the record complete without pretending anything has been classified.
    missed = unreached(lines, covered_tokens(one[5] for one in rows))
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "not reached", "page %d" % page, UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Three Glossed Nɬeʔkepmxcín Narratives by Kʷəɬtəzétkʷu (Bernice Garcia).\n")
        handle.write("# Told by Kʷəɬtəzétkʷu (Bernice Garcia), c̓əɬétkʷu (Coldwater), with Ella\n")
        handle.write("# Hannon and Anna Stacey. Papers for the International Conference on Salish\n")
        handle.write("# and Neighbouring Languages 59, UBCWPL, 2024.\n")
        handle.write("# Transcribed by Anna Stacey and Ella Hannon. Translations by Kʷəɬtəzétkʷu.\n")
        handle.write("# Bernice Garcia asks that it be acknowledged that she is a Kamloops Indian\n")
        handle.write("# Residential School speaker who is re-learning her language.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is the target language, N is anything else.\n")
        handle.write("# spoken is what was said. derived is worked out from it: the segmentation\n")
        handle.write("# normalizes each morpheme to an underlying form and the gloss is written in\n")
        handle.write("# category labels, so neither records anything uttered.\n")
        handle.write("# Gloss categories are the paper's own, from its footnote 1, unchanged.\n")
        handle.write("line\tstory\tsection\tswitches\tcontent\n")
        for mark, count, story, number, kind, text in rows:
            layer = LAYER[kind]
            if mark == "T":
                content = rendered(text, layer, kind)
                crossings = switches(text)
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (count, story, number, crossings, content))

    # The ingestion stream: only what she said, only in the target language, nothing around it.
    #
    # Each sentence is printed twice in this paper, once in the story section and again as the
    # transcription line of its gloss block. Writing both would put every sentence into the stream
    # twice and weight whatever happens to be glossed. A span already written is not written again,
    # and the number skipped is reported.
    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, count, story, number, kind, text in rows:
            if (mark != "T") or (LAYER[kind] != SPOKEN):
                continue
            for span, run in tagged_spans(text):
                if (span != "T") or (not run.strip()):
                    continue
                key = " ".join(run.split())
                if key in already:
                    repeated += 1
                    continue
                already.add(key)
                handle.write("%s\n" % run)
                kept += 1

    # A file of its own for what the tool could not sort. Two kinds go in it: a gloss-block line
    # none of the tests above typed, and a line no section of SECTIONS ever reached, which is where
    # this paper's front matter and its prose discussion of particular words sit.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (number, count), UNKNOWN_KIND, "", text)
               for mark, count, story, number, kind, text in rows
               if (kind == UNCLASSIFIED) and (story != "not reached")]
    flagged.extend(missed)
    held = write_unsorted(stuck, "the Garcia narratives", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written, this paper prints each sentence twice\n"
              % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (held, os.path.basename(stuck)))

    out.write("\n  %-12s %-8s %-18s %s\n" % ("story", "section", "kind", "lines"))
    counted = {}
    for mark, count, story, number, kind, text in rows:
        counted[(story, number, kind)] = counted.get((story, number, kind), 0) + 1
    for key in sorted(counted):
        out.write("  %-12s %-8s %-18s %d\n" % (key[0], key[1], key[2], counted[key]))

    out.write("\n  breaks in the sentence numbering\n")
    seen = {}
    for mark, count, story, number, kind, text in rows:
        if kind in ("transcription", "translation"):
            seen.setdefault((story, number, kind), set()).add(count)
    quiet = True
    for key in sorted(seen):
        numbers = seen[key]
        gaps = [one for one in range(1, max(numbers) + 1) if one not in numbers]
        if gaps:
            quiet = False
            out.write("  %-12s %-6s %-14s missing %s of 1..%d\n"
                      % (key[0], key[1], key[2],
                         ", ".join(str(one) for one in gaps), max(numbers)))
    if quiet:
        out.write("  none\n")

    marks = {}
    for mark, count, story, number, kind, text in rows:
        marks[mark] = marks.get(mark, 0) + 1
    # Counted over spoken lines only. A segmentation line is target-language material full of
    # plain-letter underlying forms, so the span test fires on it and calling that a switch would
    # report code-switching she did not do.
    mixed = sum(1 for row in rows
                if (row[0] == "T") and (LAYER[row[4]] == SPOKEN)
                and any(one == "N" for one, run in tagged_spans(row[5])))
    out.write("\n  T lines %d, N lines %d, lines she mixed %d\n"
              % (marks.get("T", 0), marks.get("N", 0), mixed))
    out.write("  sections the paper has that came back empty: %s\n"
              % (", ".join(empty) if empty else "none"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
