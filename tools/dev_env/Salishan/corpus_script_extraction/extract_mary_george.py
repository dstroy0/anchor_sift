#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Mainland Comox of Mary George and the other speakers in ICSNL 56, following that paper's own
# structure.
#
#   Usage:  python tools/dev_env/extract_mary_george.py
#
# Written for one paper. This one holds fourteen separate narratives, each its own numbered section with a
# title and a date, and it is not all one speaker. Mary George told most of them between 1969 and 1980.
# The Mink story is Noel George Harry's, the basket ogre is Tommy Paul's, and the last is John Hamilton
# Davis's own. Attributing all of it to Mary George would be wrong about three of them, so the speaker is
# a column and is set per section.
#
# Every utterance appears twice: once in the community orthography and once as a phonetic transcription in
# square brackets, followed by an English translation. So square brackets mean something different in this
# paper than in Alexander and Davis, where they hold material the linguist inserted. Here they hold the
# same utterance written a second way, and both are records of what was said.
#
# The pure stream takes the community orthography and not the phonetic line, because the two are one
# utterance and writing both would put every sentence into the stream twice. The phonetic line is kept in
# the marked file with its own kind. A reader who wants Davis's ear instead has it there.
#
# Notes sections carry his commentary on particular lines and are derived.
#
# Mary George approached Davis and his wife at a film showing in the community hall at Sliammon in 1969
# and offered to teach him the language. That is how this material exists.

import io
import os
import re
import sys

from salish_marking import (DERIVED, MARKED, SPOKEN, UNCLASSIFIED, rendered, switches,
                            tagged_spans)
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "ICSNL56_DavisJ_2_final-1.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
#
# Three of the fourteen narratives are not Mary George's, and the speaker column in the record is
# what says which. The name in the filename is who most of it is by.
TARGET = os.path.join(
    CORPORA,
    "MaryGeorge_MaryGeorgePersonalNarratives_JohnHamiltonDavis"
    "_Salish_ayajuthem_2021_mixed.txt")

MARKS = MARKED + "̓̔̕"

PAGE = re.compile(r"^===== page \d+ =====$")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,4})\)\s*\d*\s*(.*)$")
PHONETIC = re.compile(r"^\[(.*)\]?\s*$")
QUOTED = re.compile(r"^['‘“]")
NOTES = re.compile(r"^Notes for\b", re.IGNORECASE)

# A heading is short and does not close with a period. A note line opens with a bare marker and runs
# on into commentary, which is what separates the two.
HEADING = re.compile(r"^(\d{1,2})\s+(\S.*)$")

# Who told which section. The paper's abstract names the three speakers who are not Mary George.
SPEAKER = {
    "11": "Noel George Harry",
    "13": "Tommy Paul",
    "14": "John Hamilton Davis",
}
DEFAULT_SPEAKER = "Mary George"

LAYER = {
    "transcription": SPOKEN,
    "phonetic": SPOKEN,
    "translation": SPOKEN,
    "note": DERIVED,
    # Kept, marked, and held out of the ingestion stream until someone has looked at it. A line
    # nobody has classified is not a line to feed to anything, and it is not a line to throw away.
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds any character this paper writes the language with."""
    return any(mark in text for mark in MARKS)


def looks_heading(trimmed):
    """A numbered section heading, told apart from a note line that opens with its marker."""
    found = HEADING.match(trimmed)
    if not found:
        return None
    if len(trimmed) > 78 or trimmed.endswith("."):
        return None
    if re.match(r"^\d+\s*line\s*\(", trimmed):
        return None
    return found.group(1), found.group(2).strip()


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [one.rstrip("\n") for one in handle]

    rows = []
    section = None
    title = None
    in_notes = False
    number = None
    seen_orthography = False

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue

        if NOTES.match(trimmed):
            in_notes = True
            continue

        opened = looks_heading(trimmed)
        if opened:
            section, title = opened
            in_notes = False
            number = None
            continue

        if section is None:
            continue

        who = SPEAKER.get(section, DEFAULT_SPEAKER)

        # A numbered block ends the notes, and this has to be tested before the notes branch.
        # This paper interleaves its notes with more examples inside one section, and with the
        # notes tested first every later block was captured as commentary and the reset below
        # was never reached. That cost 259 of the paper's 398 blocks.
        found = NUMBERED_BLOCK.match(trimmed)

        if in_notes and not found:
            rows.append(("N", number or 0, section, title, "note", who, trimmed))
            continue

        if found:
            in_notes = False
            number = int(found.group(1))
            rest = found.group(2).strip()
            if rest:
                rows.append(("T", number, section, title, "transcription", who, rest))
                seen_orthography = True
            continue

        if number is None:
            continue

        if trimmed.startswith("[") and carries_language(trimmed):
            rows.append(("T", number, section, title, "phonetic", who, trimmed))
            continue
        if QUOTED.match(trimmed):
            rows.append(("N", number, section, title, "translation", who, trimmed))
            continue
        if carries_language(trimmed) and not seen_orthography:
            rows.append(("T", number, section, title, "transcription", who, trimmed))
            seen_orthography = True
            continue
        # Anything else carrying the language is kept and marked unsorted. None of it is dropped.
        # A phonetic line that wrapped does not open with its bracket, and the notes cite forms
        # inline as form = gloss, so both fall past the tests above. Eighty-six tokens of this
        # paper went missing that way, which is the largest hole the coverage check found.
        if carries_language(trimmed):
            rows.append(("T", number, section, title, UNCLASSIFIED, who, trimmed))

    # Every line of the paper no section reached, added to the record as unclassified, so the
    # marked file holds every token of the language the paper printed. The speaker is left unset
    # because nobody has said whose line it is. They stay out of the pure stream.
    # The union of every orthography, not this paper's own set. The coverage check counts a token
    # against the union. A finder using a narrower set leaves holes the check still reports.
    missed = unreached(lines, covered_tokens(one[6] for one in rows))
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "not reached", "page %d" % page, UNCLASSIFIED, "", text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Mary George Personal Narratives.\n")
        handle.write("# Mainland Comox, told by Mary George at Sliammon between 1969 and 1980,\n")
        handle.write("# recorded by John Hamilton Davis. The Mink story is Noel George Harry's,\n")
        handle.write("# the basket ogre is Tommy Paul's, and the last narrative is Davis's own.\n")
        handle.write("# Papers for the International Conference on Salish and Neighboring\n")
        handle.write("# Languages 56, UBCWPL, 2021.\n")
        handle.write("# Mary George approached Davis at a film showing in the community hall at\n")
        handle.write("# Sliammon in 1969 and offered to teach him her language.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is Mainland Comox, N is anything else.\n")
        handle.write("# Each utterance appears twice: the community orthography, then a phonetic\n")
        handle.write("# transcription in square brackets. Both are records of what was said.\n")
        handle.write("# The speaker column is set per section and is not the same throughout.\n")
        handle.write("line\tsection\ttitle\tkind\tspeaker\tswitches\tcontent\n")
        for mark, count, sect, name, kind, who, text in rows:
            layer = LAYER[kind]
            if mark == "T":
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text)
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%s\t%s\t%d\t%s\n"
                         % (count, sect, (name or "")[:46], kind, who, crossings, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, count, sect, name, kind, who, text in rows:
            if (mark != "T") or (kind != "transcription"):
                continue
            for span, run in tagged_spans(text, MARKS):
                if (span != "T") or (not run.strip()):
                    continue
                key = " ".join(run.split())
                if key in already:
                    repeated += 1
                    continue
                already.add(key)
                handle.write("%s\n" % key)
                kept += 1

    # A file of its own for what the tool could not sort, in the columns every paper's file uses.
    # A wrapped phonetic line does not open with its bracket and the notes cite forms inline as
    # form = gloss, so both fall past the tests above and are flagged. The second kind is a line no
    # section reached, which here is the front matter and the paper's own introduction.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (sect, count), UNKNOWN_KIND, "", text)
               for mark, count, sect, name, kind, who, text in rows
               if (kind == UNCLASSIFIED) and (sect != "not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "the Mary George narratives", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written\n" % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    out.write("\n  %-4s %-46s %-16s %s\n" % ("sec", "title", "speaker", "lines"))
    counted = {}
    for mark, count, sect, name, kind, who, text in rows:
        counted[(sect, name, who)] = counted.get((sect, name, who), 0) + 1
    # Sorted numerically where the section is a number. The lines no section reached carry a name
    # instead of a number and sort after them.
    for key in sorted(counted, key=lambda one: (0, int(one[0])) if one[0].isdigit() else (1, 0)):
        out.write("  %-4s %-46s %-16s %d\n" % (key[0], (key[1] or "")[:46], key[2], counted[key]))

    marks = {}
    kinds = {}
    for mark, count, sect, name, kind, who, text in rows:
        marks[mark] = marks.get(mark, 0) + 1
        kinds[kind] = kinds.get(kind, 0) + 1
    out.write("\n  by kind: %s\n" % ", ".join("%s %d" % (one, kinds[one]) for one in sorted(kinds)))
    out.write("  T lines %d, N lines %d\n" % (marks.get("T", 0), marks.get("N", 0)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
