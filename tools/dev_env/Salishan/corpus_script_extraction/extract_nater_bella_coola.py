#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Nuxalk of Dr. Margaret Siwallace from ICSNL 50, following that paper's own structure and its
# own symbols.
#
#   Usage:  python tools/dev_env/extract_nater_bella_coola.py
#
# Written for one paper. This is the simplest layout of the set: an introduction, a section defining the
# symbols, the text itself as numbered blocks, and references. Each block gives the Nuxalk with its
# morpheme markers, a gloss under it, and an English translation. A long sentence wraps, so one block can
# carry several transcription and gloss pairs before the translation arrives.
#
# Nater defines his own symbols in section 2 and they are used unchanged here. The character ˽, which he
# names Combining Inverted Bridge Below, follows proclitics and precedes enclitics. A hyphen follows a
# prefix and precedes a suffix. A colon precedes a reduplicated consonant. Those three carry the
# morphology and are part of the text, not punctuation to be stripped.
#
# The story is The Frog Children, told by the late Dr. Margaret Siwallace and recorded over forty years
# before the paper was published in 2015. Nater notes that the narrator first calls it a sʔalac'i, a
# family-owned account, and then uses smsmayamk, to tell as a parable, so it sits between the two genres
# the language names.

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

SOURCE = os.path.join(PAPERS, "22-Nater-Bella-Coola-tale-10.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "MargaretSiwallace_ABellaCoolaTale_Nater_Salish_nuxalk_2015_nomixed.txt")

# This paper's inventory, plus the clitic bridge and the glottalization mark it writes
MARKS = MARKED + "˽’ʷ̓"

PAGE = re.compile(r"^===== page \d+ =====$")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,4})\)\s*(.*)$")
QUOTED = re.compile(r"^['‘“]")
HEADING = re.compile(r"^(\d)\s+(\S.*)$")

# A form with its gloss in single quotes, which is how sections 1 and 2 cite one. The space between
# them is optional: the paper prints ci˽‘INDEF.FEM.PROX’ with none.
FORM_GLOSS = re.compile(r"(\S+?)\s*[‘']([^’']*)[’']")

# What the paper puts its own notation labels in.
BRACKETED = re.compile(r"\(([^)]*)\)")

# The abbreviations Nater lists in section 2, used unchanged
CATEGORIES = re.compile(
    r"\b(?:ACC|APP|ART|BEN|CAUS|CL|CONN|DEF|DEM|DIM|DIR|FEM|HYP|INCH|INDEF|INT|MED|NOM|OBJ|"
    r"PASS|PL|PREP|PRG|PROX|RECIP|REFL|REM|REP|SEP|SG|SUB|1SG|2SG|3SG|1PL|2PL|3PL|NON-FEM)\b")

LAYER = {
    "transcription": SPOKEN,
    "translation": SPOKEN,
    "gloss": DERIVED,
    "symbol note": DERIVED,
    # Kept and marked, held out of the ingestion stream until someone has classified it.
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds any character this paper writes the language with."""
    return any(mark in text for mark in MARKS)


def looks_heading(trimmed):
    """A numbered section heading, told apart from a numbered example and from prose."""
    if NUMBERED_BLOCK.match(trimmed):
        return None
    found = HEADING.match(trimmed)
    if not found:
        return None
    if len(trimmed) > 78 or trimmed.endswith("."):
        return None
    return found.group(1)


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
    number = None

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue
        if trimmed.startswith("References"):
            section = "references"
            continue

        opened = looks_heading(trimmed)
        if opened:
            section = opened
            number = None
            continue

        # Section 1 names the two genres this story sits between, and section 2 lists every
        # preposition, article, deictic and enclitic adverb the text uses, each with its gloss in
        # quotes. Both are the language. Kept as whole lines, the record held forty-odd forms inside
        # six blobs of prose, and the hand extraction of this paper, which has one row per form,
        # matched none of them.
        if section in ("1", "2") and carries_language(trimmed):
            for form, meaning in FORM_GLOSS.findall(trimmed):
                for one in form.strip("(),").split("/"):
                    if one and carries_language(one):
                        rows.append(("T", 0, section, "symbol note", one))
            # The paper names its own notation in brackets: (PREP˽), (˽ART and (˽)DEM), ( ˽CL).
            for found in BRACKETED.findall(trimmed):
                for one in found.split():
                    plain = one.strip(",")
                    if plain and ("˽" in plain):
                        rows.append(("T", 0, section, "symbol note", plain))
            rows.append(("T", 0, section, "symbol note", trimmed))
            continue

        if section != "3":
            continue

        found = NUMBERED_BLOCK.match(trimmed)
        if found:
            number = int(found.group(1))
            rest = found.group(2).strip()
            if rest:
                rows.append(("T", number, "3", "transcription", rest))
            continue

        if number is None:
            continue

        if QUOTED.match(trimmed):
            rows.append(("N", number, "3", "translation", trimmed))
        elif CATEGORIES.search(trimmed):
            rows.append(("N", number, "3", "gloss", trimmed))
        elif carries_language(trimmed):
            rows.append(("T", number, "3", "transcription", trimmed))
        else:
            # Nothing fired. This branch used to be absent. A line inside the text that was neither
            # quoted, nor glossed, nor holding one of Nater's symbols left without a word.
            rows.append(("N", number, "3", UNCLASSIFIED, trimmed))

    # Every line of the paper no section reached, added to the record as unclassified, so the
    # marked file holds every token of the language the paper printed. For this one that is the
    # introduction and the references. They stay out of the pure stream.
    # The union of every orthography, not this paper's own set. The coverage check counts a token
    # against the union. A finder using a narrower set leaves holes the check still reports.
    missed = unreached(lines, covered_tokens(one[4] for one in rows))
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "not reached page %d" % page, UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# A Bella Coola tale: The Frog Children.\n")
        handle.write("# Told in Nuxalk by the late Dr. Margaret Siwallace and recorded over forty\n")
        handle.write("# years before publication. Transcribed and interpreted by Hank Nater.\n")
        handle.write("# Papers for the International Conference on Salish and Neighbouring\n")
        handle.write("# Languages 50, UBCWPL 40, 2015.\n")
        handle.write("# The narrator first names it a sʔalac'i, a family-owned account, then uses\n")
        handle.write("# smsmayamk, to tell as a parable, so it sits between the two genres.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is Nuxalk, N is anything else.\n")
        handle.write("# Nater's symbols are kept: ˽ follows a proclitic and precedes an enclitic,\n")
        handle.write("# a hyphen follows a prefix and precedes a suffix, and a colon precedes a\n")
        handle.write("# reduplicated consonant. They carry morphology and are not punctuation.\n")
        handle.write("# Gloss categories are the paper's own, from its section 2, unchanged.\n")
        handle.write("line\tsection\tkind\tswitches\tcontent\n")
        for mark, count, sect, kind, text in rows:
            layer = LAYER[kind]
            if mark == "T":
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text)
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n" % (count, sect, kind, crossings, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, count, sect, kind, text in rows:
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

    # A file of its own for what the tool could not sort: a line inside the text that none of the
    # tests typed, and a line no section reached, which here is the introduction and the references.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (sect, count), UNKNOWN_KIND, "", text)
               for mark, count, sect, kind, text in rows
               if (kind == UNCLASSIFIED) and not sect.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "The Frog Children", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written\n" % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    kinds = {}
    for mark, count, sect, kind, text in rows:
        kinds[kind] = kinds.get(kind, 0) + 1
    out.write("\n  by kind: %s\n" % ", ".join("%s %d" % (one, kinds[one]) for one in sorted(kinds)))
    numbers = sorted({row[1] for row in rows if row[1]})
    if numbers:
        gaps = [one for one in range(1, max(numbers) + 1) if one not in numbers]
        out.write("  blocks 1..%d, missing %s\n"
                  % (max(numbers), ", ".join(str(one) for one in gaps) if gaps else "none"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
