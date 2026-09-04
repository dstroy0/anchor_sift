#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the nłeʔkepmxcín of wlwlmelst (Maurice Michell) from ICSNL 59, following that paper's own
# structure and its own glossing categories.
#
#   Usage:  python tools/dev_env/extract_lafontaine_janzen.py
#
# Written for one paper, and it is laid out unlike either of the other two. Each of the four stories is a
# running paragraph with no sentence numbering at all, followed by numbered interlinear blocks. The blocks
# are three lines deep and wrap, so one example carries several transcription, segmentation and gloss
# lines before its translation arrives.
#
# This paper writes ł where the others write ɬ. Carrying only one of those makes every token here
# invisible to the marking and to any check built on it, which is why salish_marking holds both.
#
# Two parts of this paper are the language and are not transcript. Section 2 cites forms directly while
# discussing dialect, and the appendix is a full morpheme inventory with a gloss and a meaning for each
# entry. Both are kept and marked for what they are, because a token of this language that appears in the
# paper and not in the extraction is a hole, and the coverage check counts every one of them.
#
# wlwlmelst transcribed and translated these stories himself, so the translations are his and are marked
# spoken. The segmentation normalizes morphemes to underlying forms and the gloss is written in category
# labels, so neither records anything uttered.
#
# These are words of wisdom passed to wlwlmelst by his mother nxwelinek and his grandmother ʔústko, and he
# shares them freely for people connecting with the language. That is recorded in the output.

import io
import os
import re
import sys

from inserted_space import closed_spaces
from salish_marking import (DERIVED, MARKED, SPOKEN, UNCLASSIFIED, rendered, switches,
                            tagged_spans)
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "ICSNL59_LaFontaine_Janzen_final.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "wlwlmelst-MauriceMichell_FourStoriesByWlwlmelst_LaFontaineJanzen"
    "_Salish_nlekepmxcin_2024_mixed.txt")

PAGE = re.compile(r"^===== page \d+ =====$")
HEADING = re.compile(r"^(\d+(?:\.\d+)?)\s+(\S.*)$")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,3})\)\s*(.*)$")
APPENDIX = re.compile(r"^Appendix", re.IGNORECASE)
QUOTED = re.compile(r"^['‘“]")

# A segmentation line writes each morpheme on its own and joins them with a hyphen or an equals
# sign. The blocks of this paper are three lines deep and wrap. A block holds several transcription
# lines as well as several segmentation lines, and without this test every transcription after the
# first went into the record under the name of the line below it.
SEGMENTED = re.compile(r"[-=]")

# The category labels this paper defines in its appendix and uses on its gloss line
CATEGORIES = re.compile(
    r"\b(?:ACCM|ACHV|AFF|AGENT|AT|AUG|AUT|AUX|CAUSE|CHR|CTST|DIM|DIR|DRV|DSCR|EMPH|EP|"
    r"EST\.CTX|FMV|FUT|IDF|IM|IMP|INC|INS|INT|LCL|LIG|MDL|NEG|NOM|OBL|PART\.CTX|PER|PTZG|"
    r"QLT|RFL|RFM|RPRT|RSL|SPZG|ST|TR|UNR|1SG|2SG|3SG|1PL|2PL|3PL|1\.SBJ|2\.SBJ|3\.SBJ|"
    r"1\.POSS|3\.POSS|3\.INTR|1PL\.OBJ|1PL\.SBJ|1PL\.POSS|1PL\.INTR|2\.CJV|EMPH\.INT)\b")

STORIES = {
    "3.1": "sptekwlcms l nskixzeʔ, A Story My Mother Told Me",
    "3.2": "kz̓e ʔústko, Grandmother Ustko",
    "3.3": "cúnsm ł nskíxzeʔ, Mom told me",
    "3.4": "nqʷincutn kt, Our language",
}

LAYER = {
    "running speech": SPOKEN,
    "transcription": SPOKEN,
    "translation": SPOKEN,
    "segmentation": DERIVED,
    "gloss": DERIVED,
    "cited form": DERIVED,
    "morpheme entry": DERIVED,
    # Kept and marked, held out of the ingestion stream until someone has classified it.
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds any of the marked characters this language is written with."""
    return any(mark in text for mark in MARKED)


def sectioned(lines):
    """The paper's numbered sections and its appendix, as the lines under each."""
    held = {}
    current = None
    for line in lines:
        trimmed = line.strip()
        if PAGE.match(trimmed):
            continue
        if APPENDIX.match(trimmed):
            current = "appendix"
            held.setdefault(current, [])
            continue
        found = HEADING.match(trimmed)
        if found and not NUMBERED_BLOCK.match(trimmed):
            current = found.group(1)
            held.setdefault(current, [])
            continue
        if current is not None:
            held.setdefault(current, []).append(line.rstrip("\n"))
    return held


def running_and_blocks(lines):
    """A story section: the paragraph before the first numbered block, then the blocks."""
    running = []
    blocks = []
    number = None
    building = []
    started = False

    def close():
        if (number is not None) and building:
            blocks.append((number, list(building)))
        building.clear()

    for line in lines:
        trimmed = line.strip()
        if not trimmed:
            continue
        found = NUMBERED_BLOCK.match(trimmed)
        if found:
            close()
            started = True
            number = int(found.group(1))
            rest = " ".join(found.group(2).split())
            if rest:
                building.append(rest)
            continue
        if started:
            building.append(" ".join(trimmed.split()))
        else:
            running.append(" ".join(trimmed.split()))
    close()
    return " ".join(running), blocks


def three_line_parts(block):
    """One numbered block, as the three lines this paper gives for each part of a sentence.

    A sentence too long for the page is printed in parts, and each part gets the same three lines:
    the sentence as spoken, its segmentation, then its gloss. Block 12 is three of them. Reading
    the lines one at a time recorded only the first part as the sentence and left the rest of what
    wlwlmelst wrote flagged, so two thirds of that sentence sat outside the record.

    Position in the cycle says which line is which. Content cannot: a transcription and its
    segmentation carry the same words and differ only by the boundaries written into one of them.

    The free translation closes the block and wraps onto a second line when it is long, so lines
    after it are joined to it, and none is left over.

    Hall and Phillips prints its interlinear the same way. The two are read by their own files
    because everything around the blocks differs, and this shape is what they happen to share.
    """
    parts = []
    translation = None
    leftover = []
    holding = [None, None, None]
    slot = 0

    def close():
        if any(one is not None for one in holding):
            parts.append(tuple(holding))
        holding[0] = holding[1] = holding[2] = None

    for line in block:
        if QUOTED.match(line):
            close()
            slot = 0
            translation = line
            continue
        if translation is not None:
            translation = "%s %s" % (translation, line)
            continue
        holding[slot] = line
        slot += 1
        if slot == 3:
            close()
            slot = 0
    close()
    slipped = any(CATEGORIES.search(one[0] or "") or CATEGORIES.search(one[1] or "")
                  for one in parts)
    return parts, translation, leftover, slipped


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    # This PDF leaves a space after 358 of its glottalization marks and carons, so ƛ̓uʔ arrives as
    # two tokens and c̓y̓es as three. Closed on the way in. The stress accents are left alone: neʔé
    # ends one word and e begins the next, and closing there gives neʔée.
    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [closed_spaces(one) for one in handle.read().splitlines()]

    held = sectioned(lines)
    rows = []

    for number in sorted(STORIES):
        under = held.get(number)
        if not under:
            continue
        story = STORIES[number]
        running, blocks = running_and_blocks(under)
        if running:
            rows.append(("T", 0, story, number, "running speech", running))
        for count, block in blocks:
            parts, translation, leftover, slipped = three_line_parts(block)
            if slipped:
                # The count slipped, so every line after that point is in the wrong column and
                # none of them can be named. The block is flagged whole.
                for one in block:
                    rows.append(("T" if carries_language(one) else "N",
                                 count, story, number, UNCLASSIFIED, one))
                continue
            # Each column joined across the parts, which is what puts a wrapped sentence together.
            said = " ".join(one[0] for one in parts if one[0])
            if said:
                rows.append(("T", count, story, number, "transcription", said))
            segmented = " ".join(one[1] for one in parts if one[1])
            if segmented:
                rows.append(("T", count, story, number, "segmentation", segmented))
            glossed = " ".join(one[2] for one in parts if one[2])
            if glossed:
                rows.append(("N", count, story, number, "gloss", glossed))
            if translation:
                rows.append(("N", count, story, number, "translation", translation))
            for one in leftover:
                rows.append(("T" if carries_language(one) else "N",
                             count, story, number, UNCLASSIFIED, one))

    # Section 2 cites forms while discussing dialect. They are this language and belong in the file.
    for one in held.get("2", []):
        trimmed = " ".join(one.split())
        if trimmed and carries_language(trimmed) and not CATEGORIES.search(trimmed):
            rows.append(("T", 0, "story traits", "2", "cited form", trimmed))

    # The appendix is a morpheme inventory: one morpheme, its gloss, and its meaning per row.
    for one in held.get("appendix", []):
        trimmed = " ".join(one.split())
        if not trimmed:
            continue
        if carries_language(trimmed) or re.match(r"^-?[A-Za-zʔə]{1,8}-?\s+[A-Z]", trimmed):
            rows.append(("T", 0, "glossing terms", "appendix", "morpheme entry", trimmed))

    # Every line of the paper no section reached, added to the record as unclassified, so the
    # marked file holds every token of the language the paper printed. They stay out of the pure
    # stream and are listed in the flag file for someone to work through.
    missed = unreached(lines, covered_tokens(one[5] for one in rows))
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "not reached", "page %d" % page, UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Four Stories by wlwlmelst.\n")
        handle.write("# Written, transcribed and translated by wlwlmelst (Maurice Michell), a\n")
        handle.write("# speaker of the Southern yutémkt dialect of nłeʔkepmxcín. With Jade\n")
        handle.write("# LaFontaine and Jonathan Janzen. Papers for the International Conference\n")
        handle.write("# on Salish and Neighbouring Languages 59, UBCWPL, 2024.\n")
        handle.write("# These stories were passed to wlwlmelst by his mother nxwelinek and his\n")
        handle.write("# grandmother ʔústko, and he shares them freely for those connecting with\n")
        handle.write("# the language.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is the target language, N is anything else.\n")
        handle.write("# spoken is what was said or written by him, including his own translations.\n")
        handle.write("# derived is worked out from it: segmentation normalizes to underlying forms\n")
        handle.write("# and the gloss is category labels, so neither records anything uttered.\n")
        handle.write("# Gloss categories are the paper's own, from its appendix, unchanged.\n")
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

    # A file of its own for what the tool could not sort: a block line none of the tests typed,
    # and a line no section reached, which here is the front matter and sections 1 and 4.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (number, count), UNKNOWN_KIND, "", text)
               for mark, count, story, number, kind, text in rows
               if (kind == UNCLASSIFIED) and (story != "not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "Four Stories by wlwlmelst", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written\n" % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    out.write("\n  %-38s %-10s %-16s %s\n" % ("story", "section", "kind", "lines"))
    counted = {}
    for mark, count, story, number, kind, text in rows:
        counted[(story, number, kind)] = counted.get((story, number, kind), 0) + 1
    for key in sorted(counted):
        out.write("  %-38s %-10s %-16s %d\n" % (key[0][:38], key[1], key[2], counted[key]))

    marks = {}
    for mark, count, story, number, kind, text in rows:
        marks[mark] = marks.get(mark, 0) + 1
    mixed = sum(1 for row in rows
                if (row[0] == "T") and (LAYER[row[4]] == SPOKEN)
                and any(one == "N" for one, run in tagged_spans(row[5])))
    out.write("\n  T lines %d, N lines %d, spoken lines he mixed %d\n"
              % (marks.get("T", 0), marks.get("N", 0), mixed))
    missing = [one for one in sorted(STORIES) if not held.get(one)]
    out.write("  stories the paper has that came back empty: %s\n"
              % (", ".join(missing) if missing else "none"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
