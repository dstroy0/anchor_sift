#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the nɬeʔkepmxcín of Bev Phillips from ICSNL 60, following that paper's own structure and its own
# glossing categories.
#
#   Usage:  python tools/dev_env/extract_hall_phillips.py
#
# Written for one paper. This one is laid out differently from the Garcia narratives: it has no inline
# sentence numbering and no per-story subsections. Section 2 is the story in nɬeʔkepmxcín with a timestamp
# above each sentence, section 3 is a running English translation, and section 4 is a four-line interlinear
# gloss under the same timestamps.
#
# The paper describes its own gloss format: the top line is the surface transcription, the second segments
# each word into morphemes in underlying form, the third glosses each morpheme, and the fourth translates.
# So the first line of a block is what she said and the lines under it are analysis of it.
#
# Sentences in section 2 wrap across lines of the PDF between timestamps, so the lines between one
# timestamp and the next are one sentence and are joined. Treating each line as its own sentence made the
# later line overwrite the earlier one and dropped the front of every long sentence.
#
# Bev Phillips wrote this story herself, deliberately in the style of the old sptékʷɬ, and says so in her
# own introduction. The audio was published with the paper. The authors note in a footnote that the
# recording and the transcription differ slightly, because a draft was used for the recording and they
# chose to edit the text and leave the recording unaltered, so the two are not the same object.

import io
import os
import re
import sys

from salish_marking import (CAPS_RUN, DERIVED, SPOKEN, UNCLASSIFIED, is_mixed, rendered,
                            switches, tagged_spans)
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "HallPhillipsICSNL60.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "BevPhillips_WhenOldOneCreatedTheEarth_HallPhillips"
    "_Salish_nlekepmxcin_2025_nomixed.txt")

PAGE = re.compile(r"^===== page \d+ =====$")
CLOCK = re.compile(r"^\s*\[\s*(\d{1,2}):(\d{2})\s*\]\s*$")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,3})\)\s*(.*)$")
QUOTED = re.compile(r"^['‘“]")

# The paper's second gloss line segments each word into morphemes and joins them with a hyphen or an
# equals sign, which is the positive evidence that a line is one. Without this test the branch below
# called a line segmentation because nothing else had matched it, and page numbers, footnote prose
# and the tails of wrapped sentences all went into the record under that name.
SEGMENTED = re.compile(r"[-=]")

# The category labels the paper defines in its footnote 3 and uses on its gloss line
CATEGORIES = re.compile(
    r"\b(?:ADD|AUG|AUT|CAUS|COS|COMP|CONN|CTR|COP|DEM|DET|D/C|DVL|DIM|EMPH|ERG|EXCL|IMM|IMP|"
    r"IPFV|INCH|INDEP|INDR|INFER|IRED|INS|LC|LOC|MID|NEG|NMLZ|OBJ|OBL|PASS|PL|PRP|PROSP|POSS|"
    r"QLT|RFM|RECP|REFL|RLT|REM|SG|STAT|SBJ|SBJV|TR|WH|1SG|2SG|3SG|1PL|2PL|3PL|1|2|3)\b")

# The marks the extraction inserted after a consonant's own diacritic. Deleting the space after one
# of these repairs the word. Stress accents are deliberately absent: a word can end in a stressed
# vowel, and closing that space would weld two words together everywhere.
JOINING = "̴̡̢̧̨̰̱̮̓̕"


def repair(line):
    """Take out the space the extraction inserted between a consonant's mark and the rest of it."""
    out = []
    for symbol in line:
        if (symbol == " ") and out and (out[-1] in JOINING):
            continue
        out.append(symbol)
    return "".join(out)


def tidy(text):
    """One line with its runs of blanks closed up and the inserted spaces taken out."""
    return " ".join(repair(text).split())


def sections(lines):
    """The paper's three numbered parts, as the lines under each."""
    held = {"2": [], "3": [], "4": []}
    current = None
    for line in lines:
        trimmed = line.strip()
        if PAGE.match(trimmed):
            continue
        # Matched without the accented vowel, since the extraction may hold it decomposed
        if re.match(r"^2\s+n\S*kepmxc", trimmed):
            current = "2"
            continue
        if re.match(r"^3\s+English", trimmed):
            current = "3"
            continue
        if re.match(r"^4\s+Interlinear", trimmed):
            current = "4"
            continue
        if current is not None:
            held[current].append(line.rstrip("\n"))
    return held


def timestamped_sentences(lines):
    """Section 2, as each timestamp and the sentence printed under it, wrapped lines joined."""
    held = []
    when = None
    building = []

    def close():
        if (when is not None) and building:
            held.append((when, tidy(" ".join(building))))
        building.clear()

    for line in lines:
        ticked = CLOCK.match(line)
        if ticked:
            close()
            when = "%s:%s" % (ticked.group(1), ticked.group(2))
            continue
        trimmed = line.strip()
        if trimmed and (when is not None):
            building.append(trimmed)
    close()
    return held


def gloss_blocks(lines):
    """Section 4, as each numbered block with its timestamp and the lines printed under it."""
    held = []
    when = None
    number = None
    block = []

    def close():
        if number is not None:
            held.append((when, number, list(block)))

    for line in lines:
        ticked = CLOCK.match(line)
        if ticked:
            when = "%s:%s" % (ticked.group(1), ticked.group(2))
            continue
        trimmed = line.strip()
        if (not trimmed) or PAGE.match(trimmed):
            continue
        found = NUMBERED_BLOCK.match(trimmed)
        if found:
            close()
            number = int(found.group(1))
            rest = tidy(found.group(2))
            block = [rest] if rest else []
            continue
        if number is None:
            continue
        block.append(tidy(trimmed))
    close()
    return held


def three_line_parts(block):
    """One numbered block of section 4, as the three lines the paper gives for each part of it.

    A sentence too long for the page is printed in parts, and each part gets the same three lines:
    the sentence as spoken, its segmentation, then its gloss. The parts repeat until the free
    translation closes the block. Block 10 is two of them, and reading its lines one at a time
    recorded the first part as the sentence and left ʔé scwúws néʔe e spéym flagged, so half of what
    Bev Phillips said sat outside the record while the other half looked complete.

    Position in the cycle is what says which line is which. Content cannot: a segmentation and a
    transcription of the same words differ only by the morpheme boundaries written into one.

    A slipped count is caught, not repaired, on the test every reader here uses: a run of capitals
    is a gloss label and cannot stand in a spoken sentence or its segmentation.

    Returns the parts, the free translation, any line left over, and whether the cycle slipped.
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
            leftover.append(line)
            continue
        holding[slot] = line
        slot += 1
        if slot == 3:
            close()
            slot = 0
    close()
    slipped = any(CAPS_RUN.search(one[0] or "") or CAPS_RUN.search(one[1] or "")
                  for one in parts)
    return parts, translation, leftover, slipped


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()

    held = sections(lines)
    rows = []

    for index, (when, text) in enumerate(timestamped_sentences(held["2"]), 1):
        rows.append(("T", index, when, "2", "transcription", text))

    english = " ".join(" ".join(one.split()) for one in held["3"] if one.strip())
    if english:
        rows.append(("N", 0, "", "3", "free translation", english))

    slipped_blocks = 0
    for when, number, block in gloss_blocks(held["4"]):
        parts, translation, leftover, slipped = three_line_parts(block)
        if slipped:
            # The count slipped, so every line after that point is in the wrong column and none of
            # them can be named. The block is flagged whole.
            slipped_blocks += 1
            for one in block:
                rows.append(("T", number, when, "4", UNCLASSIFIED, one))
            continue
        # Each column joined across the parts, which is what puts a wrapped sentence back together.
        said = " ".join(one[0] for one in parts if one[0])
        if said:
            rows.append(("T", number, when, "4", "transcription", said))
        segmented = " ".join(one[1] for one in parts if one[1])
        if segmented:
            rows.append(("T", number, when, "4", "segmentation", segmented))
        glossed = " ".join(one[2] for one in parts if one[2])
        if glossed:
            rows.append(("N", number, when, "4", "gloss", glossed))
        if translation:
            rows.append(("N", number, when, "4", "translation", translation))
        for one in leftover:
            rows.append(("T", number, when, "4", UNCLASSIFIED, one))

    # Every line of the paper no section reached, added to the record as unclassified. The marked
    # file then holds every token of the language the paper printed, which for this one is
    # section 1 and the front matter. They stay out of the pure stream and are listed in the flag
    # file, so the record is complete without anything being called classified that is not.
    missed = unreached(lines, covered_tokens(one[5] for one in rows), repair=tidy)
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "page %d" % page, "not reached", UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# ɬ cutés us ɬ qəɬmín ɬ tmíxʷ (When Old One Created the Earth).\n")
        handle.write("# Written and told in nɬeʔkepmxcín by Bev Phillips, Lytton First Nation\n")
        handle.write("# (ƛ̓q̓əmcín). With Brent Hall, University of British Columbia.\n")
        handle.write("# Papers for the International Conference on Salish and Neighbouring\n")
        handle.write("# Languages 60, UBCWPL, 2025. Audio published alongside the paper.\n")
        handle.write("# The authors note the recording and the transcription differ slightly,\n")
        handle.write("# because a draft was used for the recording and the text was edited after.\n")
        handle.write("#\n")
        handle.write("# T = target language, nɬeʔkepmxcín.  N = non-target, English.\n")
        handle.write("# One line per line she spoke, so the switches stay grouped and sortable.\n")
        handle.write("# Gloss categories are the paper's own, from its footnote 3, unchanged.\n")
        handle.write("line\ttime\tsection\tswitches\tcontent\n")
        for tag, number, when, section, kind, text in rows:
            layer = DERIVED if kind in ("segmentation", "gloss", UNCLASSIFIED) else SPOKEN
            if tag == "T":
                content = rendered(text, layer, kind)
                crossings = switches(text)
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (number, when, section, crossings, content))

    # The ingestion stream: only what she said, only in the target language, nothing around it.
    # A mixed line contributes its target spans and not its English ones, and no gloss, no
    # segmentation, no translation and no metadata reach this file at all.
    # Sections 2 and 4 are two printings of the same story, so writing both puts every sentence
    # into the stream twice. A span already written is not written again and the count skipped is
    # reported, since a large skip means the two printings agree and a small one means they differ.
    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for tag, number, when, section, kind, text in rows:
            if (tag != "T") or (kind != "transcription"):
                continue
            for mark, run in tagged_spans(text):
                if (mark != "T") or (not run.strip()):
                    continue
                key = " ".join(run.split())
                if key in already:
                    repeated += 1
                    continue
                already.add(key)
                handle.write("%s\n" % run)
                kept += 1

    # A file of its own for what the tool could not sort. Two kinds go in it: a gloss-block line
    # none of the tests above typed, and a line no section reached, which for this paper is
    # section 1 and the front matter, since sections() is told to hold only 2, 3 and 4.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (section, number), UNKNOWN_KIND, "", text)
               for tag, number, when, section, kind, text in rows
               if (kind == UNCLASSIFIED) and (section != "not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "When Old One Created the Earth", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written, sections 2 and 4 print the same story\n"
              % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))
    out.write("\n  %-10s %-18s %s\n" % ("section", "kind", "lines"))
    counted = {}
    for tag, number, when, section, kind, text in rows:
        counted[(section, kind)] = counted.get((section, kind), 0) + 1
    for key in sorted(counted):
        out.write("  %-10s %-18s %d\n" % (key[0], key[1], counted[key]))

    marks = {}
    for tag, number, when, section, kind, text in rows:
        marks[tag] = marks.get(tag, 0) + 1
    # Counted over spoken lines only. A segmentation line is target-language material full of
    # plain-letter underlying forms, so the span test fires on it and calling that a switch would
    # report code-switching that was not done.
    mixed = sum(1 for row in rows
                if (row[0] == "T") and (row[4] == "transcription") and is_mixed(row[5]))
    out.write("\n  T lines %d, N lines %d, lines she mixed %d\n"
              % (marks.get("T", 0), marks.get("N", 0), mixed))

    two = len([one for one in rows if (one[3] == "2") and (one[4] == "transcription")])
    four = len([one for one in rows if (one[3] == "4") and (one[4] == "transcription")])
    out.write("  section 2 sentences %d, section 4 transcriptions %d\n" % (two, four))
    out.write("  the two sections are two printings of one story. A difference between\n")
    out.write("  these counts is a discrepancy in the paper or in this reading of it\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
