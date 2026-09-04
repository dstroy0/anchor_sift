#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the St'át'imcets of Qwa7yán'ak (Carl Alexander) from ICSNL 61, following that paper's own
# structure and its own glossing conventions.
#
#   Usage:  python tools/dev_env/extract_alexander_davis.py
#
# Written for one paper. Section 1.3 states the format: section 2 is the story in St'át'imcets only,
# section 3 is an English translation, section 4 is the fully analyzed text with a timestamp about every
# two minutes, and two appendices hold an orthography chart and the glossing abbreviations. Henry Davis
# divided the story into three parts and the part headings are his.
#
# Two of the conventions decide what may enter a corpus of spoken language, and the paper is explicit
# about both.
#
# Square brackets hold material Davis inserted: grammatically necessary and elided in fast or casual
# speech, or supplied where there was a speech error. That is his and it is derived.
#
# Round brackets hold extraneous material, which he lists as false starts and repetitions. That is
# Qwa7yán'ak speaking. A false start is speech. It stays.
#
# Curly brackets mark material missing by regular phonological rule and appear in section 4 only.
#
# The orthography is van Eijk's, converting one to one into NAPA, and writes the glottal stop as 7. A
# marking set built on the marked consonants alone finds almost nothing here.
#
# Recorded by Henry Davis at Qwa7yán'ak's home at Nxwísten (Bridge River) on 7 July 2025. The recording
# runs just over half an hour and is published with the paper. Davis transcribed, translated and analyzed
# it and wrote the introduction.

import io
import os
import re
import sys

from salish_marking import (DERIVED, MARKED, PRACTICAL, SPOKEN, UNCLASSIFIED, is_mixed,
                            rendered, switches, tagged_spans)
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "AlexanderDavis_ICSNL61.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "Qwa7yanak-CarlAlexander_ITsicwasSQwa7yanakAku7GraveyardValley_AlexanderDavis"
    "_Salish_statimcets_2026_mixed.txt")

MARKS = MARKED + PRACTICAL + "̓̔̕"

PAGE = re.compile(r"^===== page \d+ =====$")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,4})\)\s*(.*)$")
CLOCK = re.compile(r"\[?\s*(\d{1,2}):(\d{2})\s*\]?")
# The free translation opens a line and this paper writes it with either quote. Narrowing this to
# the single quote, which is what the two Lyon papers needed, cost five translations here. The
# convention is settled per paper and testing it on one says nothing about the next.
QUOTED = re.compile(r"^['‘“]")
INSERTED = re.compile(r"\[([^\]]*)\]")

# A segmentation line writes each morpheme on its own and joins them with a hyphen or an equals
# sign. Testing for that is what keeps a wrapped transcription line, a timestamp, a page number or a
# line of footnote prose from entering the record under the name segmentation because nothing
# else matched it.
SEGMENTED = re.compile(r"[-=]")

# The category labels this paper uses. Its appendix II lists them and section 1.3 adds the ones it
# changed, so both the inherited set and the new labels are here.
CATEGORIES = re.compile(
    r"\b(?:ABSN|ACT|ADHORT|AUT|CAUS|CIRC|COMP|COP|COS|DEM|DET|DIM|DIR|DIST|D/C|ERG|EXCL|"
    r"EXIS|IND|INS|INVIS|IPFV|MID|NEG|NMLZ|OBJ|PL|PLU|POSS|REM|RLT|SBJ|SBJV|SG|STAT|VIS|"
    r"1SG|2SG|3SG|1PL|2PL|3PL|PL\.DET|ABS\.DET|Ø)\b")

LAYER = {
    "running speech": SPOKEN,
    "transcription": SPOKEN,
    "translation": SPOKEN,
    "segmentation": DERIVED,
    "gloss": DERIVED,
    "orthography chart": DERIVED,
    "glossing term": DERIVED,
    # Kept and marked, held out of the ingestion stream until someone has classified it.
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds any character this paper writes the language with."""
    return any(mark in text for mark in MARKS)


def is_heading(trimmed):
    """A numbered section heading, told apart from a footnote that opens with its marker.

    Footnotes here begin with a bare number and run on into prose for several lines. A heading is
    short and does not close with a period, which separates the two without naming either.
    """
    if not re.match(r"^\d(?:\.\d)?\s+\S", trimmed):
        return None
    if len(trimmed) > 78 or trimmed.endswith("."):
        return None
    return re.match(r"^(\d(?:\.\d)?)", trimmed).group(1)


def sectioned(lines):
    """The paper's sections and appendices, as the lines under each."""
    held = {}
    current = None
    for line in lines:
        trimmed = line.strip()
        if PAGE.match(trimmed) or not trimmed:
            continue
        if re.match(r"^Appendix\s+I\b(?!I)", trimmed):
            current = "appendix I"
            held.setdefault(current, [])
            continue
        if re.match(r"^Appendix\s+II\b", trimmed):
            current = "appendix II"
            held.setdefault(current, [])
            continue
        number = is_heading(trimmed)
        if number:
            current = number
            held.setdefault(current, [])
            continue
        if current is not None:
            held.setdefault(current, []).append(trimmed)
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()

    held = sectioned(lines)
    rows = []
    count = 0

    # Davis divided the story into three parts and those are numbered subsections, so the whole of
    # the story sits under 2.1, 2.2 and 2.3 and nothing under a bare 2. Reading only the bare
    # numbers returned the two appendices and none of the narrative.
    def under(top):
        """Every line in a section and in its subsections, in the order the paper prints them."""
        gathered = []
        for key in sorted(held, key=lambda one: [int(part) for part in one.split(".")]
                          if re.match(r"^\d+(\.\d+)?$", one) else [999]):
            if (key == top) or key.startswith(top + "."):
                gathered.extend(held[key])
        return gathered

    for one in under("2"):
        if not carries_language(one):
            continue
        count += 1
        rows.append(("T", count, "2", "running speech", one))

    for one in under("3"):
        count += 1
        rows.append(("N", count, "3", "translation", one))

    number = None
    for one in under("4"):
        found = NUMBERED_BLOCK.match(one)
        if found:
            number = int(found.group(1))
            rest = found.group(2).strip()
            if rest:
                rows.append(("T", number, "4", "transcription", rest))
            continue
        if number is None:
            continue
        if QUOTED.match(one):
            rows.append(("N", number, "4", "translation", one))
        elif CATEGORIES.search(one):
            rows.append(("N", number, "4", "gloss", one))
        # Not gated on carries_language. Van Eijk's orthography writes the glottal stop as 7 and
        # many St'át'imcets lines hold no marked character at all, so that test read
        # i=tsilikútn=a. and l=ta=s=t'ák=ih=a. as not being the language. What separates a
        # segmentation line from a line of Davis's footnote prose, which also carries hyphens, is
        # that the prose has English in it and the segmentation does not.
        elif SEGMENTED.search(one) and not is_mixed(one, MARKS):
            rows.append(("T", number, "4", "segmentation", one))
        else:
            rows.append(("T" if carries_language(one) else "N",
                         number, "4", UNCLASSIFIED, one))

    for one in held.get("appendix I", []):
        if carries_language(one):
            rows.append(("T", 0, "appendix I", "orthography chart", one))

    for one in held.get("appendix II", []):
        rows.append(("N", 0, "appendix II", "glossing term", one))

    # Every line of the paper no section reached, added to the record as unclassified, so the
    # marked file holds every token of the language the paper printed. They stay out of the pure
    # stream and are listed in the flag file for someone to work through.
    # The union of every orthography, not this paper's own set. The coverage check counts a token
    # against the union. A finder using a narrower set leaves holes the check still reports.
    missed = unreached(lines, covered_tokens(one[4] for one in rows))
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "not reached page %d" % page, UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# I Tsícwas sQwa7yán'ak Áku7 Graveyard Valley\n")
        handle.write("# (When Qwa7yán'ak went to Graveyard Valley). A St'át'imcets narrative.\n")
        handle.write("# Told by Qwa7yán'ak (Carl Alexander), Nxwísten (Bridge River), recorded by\n")
        handle.write("# Henry Davis at his home on 7 July 2025. Just over half an hour of audio,\n")
        handle.write("# published with the paper. Proceedings of ICSNL 61, UBCWPL.\n")
        handle.write("# Davis transcribed, translated and analyzed it and wrote the introduction.\n")
        handle.write("# It tells of the Bury the Hatchet ceremony held at Graveyard Valley in the\n")
        handle.write("# South Chilcotin Mountains on 19 July 2003 between the St'át'imc and the\n")
        handle.write("# Tŝilhqot'in, and of earlier meetings at the rodeo at T'ít'q'et.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is St'át'imcets, N is anything else.\n")
        handle.write("# The glottal stop is written 7 in this orthography.\n")
        handle.write("# Square brackets hold material Davis inserted and are derived. Round\n")
        handle.write("# brackets hold false starts and repetitions, which are Qwa7yán'ak speaking\n")
        handle.write("# and are kept. Curly brackets mark what a phonological rule removed.\n")
        handle.write("# Gloss categories are the paper's own, from its appendix II, unchanged.\n")
        handle.write("line\tsection\tkind\tswitches\tcontent\n")
        for mark, number, section, kind, text in rows:
            layer = LAYER[kind]
            if mark == "T":
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text)
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (number, section, kind, crossings, content))

    # The ingestion stream. Material Davis supplied inside square brackets is taken back out,
    # since he wrote it and Qwa7yán'ak did not say it.
    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, number, section, kind, text in rows:
            if (mark != "T") or (LAYER[kind] != SPOKEN):
                continue
            said = INSERTED.sub(" ", text)
            for span, run in tagged_spans(said, MARKS):
                if (span != "T") or (not run.strip()):
                    continue
                key = " ".join(run.split())
                if key in already:
                    repeated += 1
                    continue
                already.add(key)
                handle.write("%s\n" % key)
                kept += 1

    # A file of its own for what the tool could not sort: a section 4 line none of the tests typed,
    # and a line no section reached, which here is the front matter and section 1.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (section, number), UNKNOWN_KIND, "", text)
               for mark, number, section, kind, text in rows
               if (kind == UNCLASSIFIED) and not section.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "I Tsícwas sQwa7yán'ak Áku7 Graveyard Valley", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written\n" % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    out.write("\n  %-12s %-20s %s\n" % ("section", "kind", "lines"))
    counted = {}
    for mark, number, section, kind, text in rows:
        counted[(section, kind)] = counted.get((section, kind), 0) + 1
    for key in sorted(counted):
        out.write("  %-12s %-20s %d\n" % (key[0], key[1], counted[key]))

    marks = {}
    for mark, number, section, kind, text in rows:
        marks[mark] = marks.get(mark, 0) + 1
    out.write("\n  T lines %d, N lines %d\n" % (marks.get("T", 0), marks.get("N", 0)))
    out.write("  sections found: %s\n" % ", ".join(sorted(held)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
