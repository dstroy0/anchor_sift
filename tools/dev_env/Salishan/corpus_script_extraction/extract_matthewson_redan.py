#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the St'át'imcets of K̓weswapáw̓ / Linda Redan from ICSNL 61, following that paper's own structure
# and its own glossing categories.
#
#   Usage:  python tools/dev_env/extract_matthewson_redan.py
#
# Written for one paper, and this one is a different language from the three before it and a different
# orthography again. St'át'imcets writes the glottal stop as the digit 7, so Cw7aoz, skúza7 and ts7ásas
# carry none of the marked characters the other papers use. A test built on those marks alone finds almost
# nothing here, which is why the marking set is passed in per paper.
#
# Four things about this paper decide how it is read.
#
# The square brackets in section 2 hold Lisa Matthewson's notes on Linda's laughter and gestures, and they
# are written in St'át'imcets. So they are the target language and they are not Linda speaking. They are
# marked derived. The same notes in section 3 are in English.
#
# Linda moves into English inside her own narrative and the paper glosses that as part of the utterance,
# and her closing lines are entirely English. Those lines are hers and are kept whole.
#
# Section 5 discusses indefinite pronouns and repeats lines from the story, and one of its examples is not
# Linda's at all: example 35 is from Sam Mitchell, published in Van Eijk and Williams 1981. That is marked
# with its own speaker so the attribution does not blur.
#
# Lisa transcribed, translated and glossed the story and checked the transcription and translation with
# Linda. The story was told over Zoom on October 31, 2025 and runs three minutes and twenty-eight seconds.

import io
import os
import re
import sys

from inserted_space import closed_spaces
from salish_marking import (DERIVED, MARKED, PRACTICAL, SPOKEN, UNCLASSIFIED, rendered,
                            switches, tagged_spans)
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "Matthewson_Redan_ICSNL61.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "Kweswapaw-LindaRedan_Cw7aozKati7Lati7KuNaxwit_MatthewsonRedan"
    "_Salish_statimcets_2026_mixed.txt")

# This paper's orthography, plus the combining marks it writes glottalization with
MARKS = MARKED + PRACTICAL + "̓̔̕"

PAGE = re.compile(r"^===== page \d+ =====$")

# Matched on the actual titles. This paper numbers its sections with bare digits, and its footnotes
# open with a bare marker followed by prose. A general number-then-text pattern reads footnote 1
# as the start of section 1 and refiles the whole glossed story under it. Section 4 came back with
# two of its thirty-four blocks that way. Naming the four headings is exact and cannot drift.
HEADINGS = (
    ("2", re.compile(r"^2\s+The story in St")),
    ("3", re.compile(r"^3\s+The story in English")),
    ("4", re.compile(r"^4\s+The story glossed")),
    ("5", re.compile(r"^5\s+Indefinite pronouns")),
)
NUMBERED_BLOCK = re.compile(r"^\((\d{1,3})\)\s*(.*)$")
BRACKETED = re.compile(r"\[([^\]]*)\]")
QUOTED = re.compile(r"^['‘“]")

# Where one of her sentences ends. The closing quote comes after the stop, because the story is full
# of people talking: Nilh swe7áwentsas, “K̓weswapáw̓!” is one sentence and splitting at the ! would
# leave the quotation mark opening the next one.
SENTENCE = re.compile(r"(?<=[.!?])(?=\s)|(?<=[.!?][\"”’'])(?=\s)")

# A segmentation line writes each morpheme on its own and joins them with a hyphen or an equals
# sign. Testing for that is what keeps a wrapped transcription line, a page number or a line of
# footnote prose from entering the record under the name segmentation because nothing else matched.
SEGMENTED = re.compile(r"[-=]")

# The category labels the paper defines in its footnote 1 and uses on its gloss line
CATEGORIES = re.compile(
    r"\b(?:ABS|ACT|ADHORT|AUT|CAUS|CIRC|COMP|COP|D/C|DET|DIM|DIR|ERG|EXCL|EXIS|IND|INS|"
    r"INVIS|IPFV|MID|NEG|NMLZ|OBJ|PL|PLU|POSS|REM|RLT|SBJ|SBJV|SG|STAT|VIS|"
    r"1SG|2SG|3SG|1PL|2PL|3PL|PL\.DET|ABS\.DET)\b")

LAYER = {
    "running speech": SPOKEN,
    "transcription": SPOKEN,
    "translation": SPOKEN,
    "segmentation": DERIVED,
    "gloss": DERIVED,
    "stage direction": DERIVED,
    "cited example": DERIVED,
    # Kept and marked, held out of the ingestion stream until someone has classified it.
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds any character this paper writes the language with."""
    return any(mark in text for mark in MARKS)


def sectioned(lines):
    """The paper's numbered sections, as the lines under each."""
    held = {}
    current = None
    for line in lines:
        trimmed = line.strip()
        if PAGE.match(trimmed):
            continue
        opened = None
        for number, pattern in HEADINGS:
            if pattern.match(trimmed):
                opened = number
                break
        if opened is not None:
            current = opened
            held.setdefault(current, [])
            continue
        if current is not None:
            held.setdefault(current, []).append(line.rstrip("\n"))
    return held


def split_brackets(text):
    """A line as its spoken parts and the bracketed notes between them, in order."""
    pieces = []
    at = 0
    for found in BRACKETED.finditer(text):
        before = text[at:found.start()].strip()
        if before:
            pieces.append(("said", " ".join(before.split())))
        inside = found.group(1).strip()
        if inside:
            pieces.append(("note", " ".join(inside.split())))
        at = found.end()
    tail = text[at:].strip()
    if tail:
        pieces.append(("said", " ".join(tail.split())))
    return pieces


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    # This PDF leaves a space after every glottalization mark, 169 of them, and K̓weswapáw̓ arrives
    # as two tokens. Closed on the way in, so that everything reading these lines sees one word.
    # The hand extraction is what caught it: reading the paper by eye gives K̓weswapáw̓, and the
    # record held K̓ and weswapáw̓ while coverage_check reported this paper at 100 percent.
    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [closed_spaces(one) for one in handle.read().splitlines()]

    held = sectioned(lines)
    rows = []
    count = 0

    # Section 2, the story as she told it, with Lisa's notes on laughter and gesture between.
    #
    # Joined into one string before it is read. The line breaks here are the PDF's page width and
    # nothing else: her first sentence runs across two of them and her fifth starts halfway through
    # a third. Read line by line, the record held fragments, and the hand extraction of this paper,
    # which is one row per sentence, matched none of them.
    whole = " ".join(" ".join(one.split()) for one in held.get("2", []) if one.strip())
    for kind, piece in split_brackets(whole):
        if kind == "note":
            count += 1
            rows.append(("T", count, "2", "stage direction", "Lisa Matthewson", piece))
            continue
        for said in SENTENCE.split(piece):
            said = said.strip()
            if said:
                count += 1
                rows.append(("T", count, "2", "running speech",
                             "K̓weswapáw̓ Linda Redan", said))

    # Section 3, the English translation, checked with Linda
    for one in held.get("3", []):
        trimmed = " ".join(one.split())
        if not trimmed:
            continue
        count += 1
        rows.append(("N", count, "3", "translation", "Lisa Matthewson, checked with Linda", trimmed))

    # Section 4, the glossed story
    number = None
    for one in held.get("4", []):
        trimmed = " ".join(one.split())
        if not trimmed:
            continue
        found = NUMBERED_BLOCK.match(trimmed)
        if found:
            number = int(found.group(1))
            rest = found.group(2).strip()
            if rest:
                rows.append(("T", number, "4", "transcription",
                             "K̓weswapáw̓ Linda Redan", rest))
            continue
        if number is None:
            continue
        if QUOTED.match(trimmed):
            rows.append(("N", number, "4", "translation",
                         "Lisa Matthewson, checked with Linda", trimmed))
        elif CATEGORIES.search(trimmed):
            rows.append(("N", number, "4", "gloss", "Lisa Matthewson", trimmed))
        elif carries_language(trimmed) and SEGMENTED.search(trimmed):
            rows.append(("T", number, "4", "segmentation", "Lisa Matthewson", trimmed))
        else:
            # Nothing fired, so the line is flagged and its speaker is left unset. Filling that
            # column would put a name on a line nobody has read.
            rows.append(("T" if carries_language(trimmed) else "N",
                         number, "4", UNCLASSIFIED, "", trimmed))

    # Section 5 repeats lines from the story and cites one that is not hers
    number = None
    for one in held.get("5", []):
        trimmed = " ".join(one.split())
        if not trimmed:
            continue
        found = NUMBERED_BLOCK.match(trimmed)
        if found:
            number = int(found.group(1))
            rest = found.group(2).strip()
            if rest and carries_language(rest):
                who = ("Sam Mitchell, in Van Eijk and Williams 1981" if number == 35
                       else "K̓weswapáw̓ Linda Redan")
                rows.append(("T", number, "5", "cited example", who, rest))
            continue
        if (number is not None) and carries_language(trimmed) \
                and not CATEGORIES.search(trimmed) and not QUOTED.match(trimmed):
            who = ("Sam Mitchell, in Van Eijk and Williams 1981" if number == 35
                   else "K̓weswapáw̓ Linda Redan")
            rows.append(("T", number, "5", "cited example", who, trimmed))

    # Every line of the paper no section reached, added to the record as unclassified, so the
    # marked file holds every token of the language the paper printed. The speaker column is left
    # unset, which also keeps these out of the pure stream, and they are listed in the flag file.
    # The union of every orthography, not this paper's own set. The coverage check counts a token
    # against the union. A finder using a narrower set leaves holes the check still reports.
    missed = unreached(lines, covered_tokens(one[5] for one in rows))
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "not reached page %d" % page, UNCLASSIFIED, "", text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Cw7aoz káti7 láti7 ku naxwít, There was definitely no snake there.\n")
        handle.write("# A story in St'át'imcets by K̓weswapáw̓ / Linda Redan, Qayqáyten, born at\n")
        handle.write("# K̓maqs (Six Mile) and raised at Cácl̓ep (Fountain). With Lisa Matthewson,\n")
        handle.write("# University of British Columbia. Proceedings of ICSNL 61, UBCWPL.\n")
        handle.write("# Told over Zoom on 31 October 2025, three minutes twenty-eight seconds.\n")
        handle.write("# Lisa transcribed, translated and glossed it; the transcription and the\n")
        handle.write("# translation were checked with Linda. Audio and video are held by her.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is St'át'imcets, N is anything else.\n")
        handle.write("# The glottal stop is written 7 in this orthography.\n")
        handle.write("# Bracketed notes on laughter and gesture are Lisa's and are marked derived,\n")
        handle.write("# in section 2 written in St'át'imcets and in section 3 in English.\n")
        handle.write("# Example 35 is Sam Mitchell's, not Linda's, and carries his name.\n")
        handle.write("# Gloss categories are the paper's own, from its footnote 1, unchanged.\n")
        handle.write("line\tsection\tkind\tspeaker\tswitches\tcontent\n")
        for mark, number, section, kind, who, text in rows:
            layer = LAYER[kind]
            if mark == "T":
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text)
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%s\t%d\t%s\n"
                         % (number, section, kind, who, crossings, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, number, section, kind, who, text in rows:
            if (mark != "T") or (LAYER[kind] != SPOKEN):
                continue
            if not who.startswith("K̓weswapáw̓"):
                continue
            for span, run in tagged_spans(text, MARKS):
                if (span != "T") or (not run.strip()):
                    continue
                key = " ".join(run.split())
                if key in already:
                    repeated += 1
                    continue
                already.add(key)
                handle.write("%s\n" % run)
                kept += 1

    # A file of its own for what the tool could not sort: a section 4 line none of the tests typed,
    # and a line no section reached, which here is the front matter, section 1 and the references.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (section, number), UNKNOWN_KIND, "", text)
               for mark, number, section, kind, who, text in rows
               if (kind == UNCLASSIFIED) and not section.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "Cw7aoz káti7 láti7 ku naxwít", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written\n" % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    out.write("\n  %-8s %-16s %-38s %s\n" % ("section", "kind", "speaker", "lines"))
    counted = {}
    for mark, number, section, kind, who, text in rows:
        counted[(section, kind, who)] = counted.get((section, kind, who), 0) + 1
    for key in sorted(counted):
        out.write("  %-8s %-16s %-38s %d\n" % (key[0], key[1], key[2][:38], counted[key]))

    marks = {}
    for mark, number, section, kind, who, text in rows:
        marks[mark] = marks.get(mark, 0) + 1
    mixed = sum(1 for row in rows
                if (row[0] == "T") and (LAYER[row[3]] == SPOKEN)
                and any(one == "N" for one, run in tagged_spans(row[5], MARKS)))
    out.write("\n  T lines %d, N lines %d, spoken lines she mixed %d\n"
              % (marks.get("T", 0), marks.get("N", 0), mixed))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
