#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Check that every token of the language in a paper reached the file extracted from it.
#
#   Usage:  python tools/dev_env/coverage_check.py
#
# A per-paper extractor is written against one paper's layout and can miss a section without saying so.
# Story 3 of the Garcia narratives was numbered differently from stories 1 and 2 and came back empty.
# Section 4 of the Matthewson paper fell from thirty-four blocks to two because a footnote marker matched
# a heading. The Alexander story sits in subsections and reading the bare numbers returned two appendices
# and none of the narrative. Every one of those was silent.
#
# The check that catches them is a diff. Every token in the source carrying a character of the language
# should appear somewhere in the extraction, and the number that do not should be zero.
#
# Both sides have to be put through the same transformation first, which the first version of this file
# did not do. Some extractors repair the source before writing it: the space the PDF inserted after each
# combining mark is closed, and two papers had a font that wrote plain letters in place of the
# orthography. Comparing a repaired extraction against an unrepaired source reports every correctly
# repaired word as missing, which is what produced 173 false holes in one paper. So the repairs are
# applied to the source lines here before either side is tokenized, and it does not matter that a repair
# is lossy as long as both sides receive it.
#
# What this reports that is not an error: a token is counted as covered if it appears anywhere in the
# extraction. A form living only in a footnote is found wherever the extractor kept it. What it reports
# that is an error: a form cited in prose that no section captures, an appendix nobody read, and a
# sentence a splitter dropped.

import io
import os
import re
import sys
import unicodedata

from font_repair import repaired_line
from glyph_names import decoded
from inserted_space import closed_spaces
from line_breaks import joined
from mellesmoen_kye_repair import repaired as mellesmoen_repaired
# Aliased because this file already calls the directory of paper texts PAPERS, and importing the
# config under the same name shadowed it with a string that iterated as characters.
from paper_config import PAPERS as EVERY_PAPER
from salish_marking import MARKED, PRACTICAL, unligatured
from salish_unsorted import is_language_token
from space_repair import joined_words

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

PAGE = re.compile(r"^===== page (\d+) =====$")

# The span marker a record writes ahead of each run, as T.spoken.transcription: or N.derived.gloss:
MARKER = re.compile(r"\b[TN](?:\.[^:\s{}]*)*:")

# A brace is punctuation on both sides of the comparison. The record delimits a span with them and
# one paper cites a reduplication template written in them, so neither side may keep them.
EDGES = ".,!?;:“”‘’\"'()[]…«»{}"

# A token carrying any of these is the language. The union of every orthography in the set, since a
# checker that knows one paper's alphabet reports the others as empty.
MARKS = MARKED + PRACTICAL + "̓̔̕ʷ˽"

"""The font substitution two of these papers needed lives in font_repair.py, and the guarded form
of it is what belongs here. The readers apply every substitution inside a language column and the
guarded one everywhere else, and the check has no columns to work from, so it takes the guarded
form for the whole source. That leaves an all-caps gloss label and an address alone, which is what
stops INCEPT and jmlyon@sfu.ca being counted as words of the language and then reported as holes.

The cost is that a word like Paks keeps its capital here and so is not counted as a language token
at all. The check under-counts by about ten tokens a paper and never invents a hole, which is the
direction to be wrong in for a measurement."""

# The marks whose following space the extraction inserted, closed by the Hall and Phillips reader
JOINING = "̴̡̢̧̨̰̱̮̓̕"

# The Lyon extraction ran a word's first two columns together wherever the segmentation opens at
# the root, giving ’qwQaylqs√ ’qwQay=lqs where the paper prints a word above its own analysis. Both
# readers split that, so the source is split the same way here. Without it the source carries one
# token the extraction has no reason to hold and 46 words of one paper were reported as holes while
# sitting in the file under their own two names. The test is the reader's: a root marker with a
# bare word before it is two columns, one with morpheme separators before it is a segmentation.
COLUMN = re.compile(r"^([^-=•+√]+)(√.*)$")

# paper, extraction, which repairs the extractor applied to the source, and what that paper writes
# its language with.
#
# Every one of these was written out here a second time until this read the config. The alphabets
# were literals duplicating hand_extraction/papers.py, and a paper added to one and not the other was
# a paper this check read with the wrong alphabet and then reported as fully covered. paper_config.py
# is the one place a paper is described and the notes behind each entry are there.
#
# Two of the repair lists still differ from the ones the oracle check applies, and neither difference
# was deliberate. paper_config.Paper says which and why.
PAIRS = tuple((one.stem, one.record, one.coverage, one.marks) for one in EVERY_PAPER)

def close_spaces(line):
    """Take out the space the extraction inserted between a consonant's mark and the rest of it."""
    out = []
    for symbol in line:
        if (symbol == " ") and out and (out[-1] in JOINING):
            continue
        out.append(symbol)
    return "".join(out)


def font_repaired(line):
    """Apply the substitution a paper's own reader would have applied to this line."""
    return repaired_line(line)


def split_columns(line):
    """Put back the space between two columns the extraction ran together."""
    out = []
    for token in line.split():
        found = COLUMN.match(token)
        if found:
            out.append(found.group(1))
            out.append(found.group(2))
        else:
            out.append(token)
    return " ".join(out)


def vocabulary_beside(target):
    """The word list a reader wrote out beside its record, if it wrote one.

    A reader that puts words back together publishes the list it used. Building a second list here
    from the same paper gave a different one, which joined words the reader left apart and then
    reported every one of them as a hole. The list is read here, never rebuilt.
    """
    path = target[:-4] + ".words.txt"
    if not os.path.isfile(path):
        return set()
    held = set()
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            word = line.strip()
            if word:
                held.add(word)
    return held


def prepared(line, repairs, vocabulary=None):
    """One source line put through the same transformation its extractor applied."""
    # Applied to every paper. A ligature is one codepoint for two letters and the readers take
    # them out on the way in. A source keeping them reports every repaired word as a hole.
    line = unligatured(line)
    if "font" in repairs:
        line = font_repaired(line)
    if "spaces" in repairs:
        line = close_spaces(line)
    if "columns" in repairs:
        line = split_columns(line)
    if "inserted spaces" in repairs:
        line = closed_spaces(line)
    if "mellesmoen" in repairs:
        line = mellesmoen_repaired(line)
    if "glyph names" in repairs:
        line = decoded(line)
    if vocabulary:
        line = joined_words(line, vocabulary)
    return line


def marked_tokens(text, marks=MARKS):
    """Every token holding a character of the language, stripped of surrounding punctuation.

    What counts as one is decided by salish_unsorted, which is where the readers get it too. Two
    copies of that rule drift, and a check counting something the reader never looks for reports
    holes that no amount of extraction can close.
    """
    held = {}
    for token in text.split():
        plain = token.strip(EDGES)
        if is_language_token(plain, marks):
            held[plain] = held.get(plain, 0) + 1
    return held


def source_tokens(path, repairs, vocabulary=None, marks=MARKS):
    """The language tokens of a paper, with the page each was first seen on.

    Read whole where the reader put words back together across a line break, because that repair
    cannot be applied a line at a time. Robertson's extraction breaks /ncéweʔ as /n above céweʔ,
    the reader welds it, and a check reading one line at a time reported the half it could see as a
    hole the extraction had no way to hold.
    """
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = [one.rstrip("\n") for one in handle]
    if "line joins" in repairs:
        lines = joined(lines)[0]

    held = {}
    where = {}
    page = 0
    for line in lines:
        found = PAGE.match(line.strip())
        if found:
            page = int(found.group(1))
            continue
        for token, times in marked_tokens(prepared(line, repairs, vocabulary), marks).items():
            held[token] = held.get(token, 0) + times
            where.setdefault(token, page)
    return held, where


def extracted_tokens(path, marks=MARKS):
    """The language tokens present anywhere in the content column of an extracted file.

    Read from the whole content column instead of from the braces inside it. The record writes a
    span as kind:{text}, and one of these papers cites a reduplication template that is itself
    written in braces, {C1aC2-ɬəχ.t.ana(n).θot}, which ends a span early and lost the token. The
    span markers hold no character of any of these languages, so taking the column entire costs
    nothing, and the column is the last field of every paper's format.
    """
    held = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            content = line.rstrip("\n").split("\t")[-1]
            # The marker runs into the first word of its span, giving T.spoken.transcription:{iʔ
            # as one token, so it comes out before the column is split into words.
            content = MARKER.sub(" ", content).replace("{", " ").replace("}", " ")
            for token, times in marked_tokens(content, marks).items():
                held[token] = held.get(token, 0) + times
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-36s %-9s %-9s %-9s %s\n"
              % ("paper", "in paper", "extracted", "missing", "covered"))

    worst = []
    for entry in PAIRS:
        stem, name, repairs = entry[:3]
        marks = entry[3] if len(entry) > 3 else MARKS
        source = os.path.join(PAPERS, ("%s.page.txt" if "page" in repairs else "%s.txt") % stem)
        target = os.path.join(CORPORA, name)
        if not os.path.isfile(source) or not os.path.isfile(target):
            out.write("  %-36s missing a file\n" % stem[:36])
            continue

        held, where = source_tokens(source, repairs, vocabulary_beside(target), marks)
        got = extracted_tokens(target, marks)
        missing = {token: count for token, count in held.items() if token not in got}
        covered = (100.0 * (len(held) - len(missing)) / len(held)) if held else 0.0
        out.write("  %-36s %-9d %-9d %-9d %.1f%%\n"
                  % (stem[:36], len(held), len(got), len(missing), covered))
        worst.append((len(missing), stem, missing, where))

    out.write("\n  where the missing tokens sit, for the papers that have any\n")
    for count, stem, missing, where in sorted(worst, reverse=True):
        if not count:
            continue
        by_page = {}
        for token in missing:
            by_page.setdefault(where.get(token, 0), []).append(token)
        out.write("\n  %s, %d missing on %d page(s)\n" % (stem, count, len(by_page)))
        for page in sorted(by_page)[:6]:
            shown = by_page[page][:5]
            out.write("    page %-4d %-3d  %s\n"
                      % (page, len(by_page[page]), "  ".join(shown)))
        if len(by_page) > 6:
            out.write("    and %d more page(s)\n" % (len(by_page) - 6))

    clean = [one for one in worst if not one[0]]
    out.write("\n  %d of %d papers have every token of the language accounted for\n"
              % (len(clean), len(worst)))
    out.write("  both sides are put through the same repair first, and a correctly repaired\n")
    out.write("  word is not reported as a hole\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
