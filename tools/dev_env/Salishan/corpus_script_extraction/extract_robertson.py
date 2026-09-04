#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the two Salish letters from Robertson's Chinuk pipa study, ICSNL 47.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_robertson.py
#
# Written for one paper. The paper is a history and structural analysis of the Chinuk pipa
# shorthand, and it prints six texts written in that script by Indigenous writers around 1900. Two
# of the six are Salish and four are Chinook Jargon.
#
#   Text 1  Nɬeʔkepmxcín, a letter by Charley Alexis Mayoos, published in Kamloops Wawa in 1893
#   Text 2  Secwepemctsín, the parting salutation of a letter by William Celestin
#   Texts 3 to 6  Chinook Jargon, which is a pidgin
#
# Only the first two are target-language material. Chinook Jargon is a language of its own and a
# pidgin besides, so nothing from Texts 3 to 6 or from the phonological analysis reaches the pure
# stream. Those lines are kept in the record and flagged, never dropped.
#
# TWO THINGS THIS PAPER DOES THAT NO OTHER ONE HERE DOES
#
# The transliteration line is written in plain ASCII. Mayoos wrote in shorthand and Robertson
# transliterates it letter for letter, so the line reads o l ha l kukpi, and carries not one
# character of the modern orthography. The character test every other reader here leans on calls
# that line English. It is Nɬeʔkepmxcín, and the only thing that says so is where it sits, so the
# pipa rows are marked T by position and never by their letters.
#
# The extraction breaks words across lines with no hyphen, 42 times. Some of the breaks fall inside
# a gloss: A above UG-, s above ick, gr above eet. joined() puts those back. It refuses the join
# where the line under the fragment is itself short, because the alphabet tables set the Chinuk pipa
# letter names wa, wi and waw one to a line and joining those would invent words.
#
# WHAT THE SOURCE STILL LOSES
#
# Labialization. Page 30 sets /kʷú[·kʷ]piʔ and the text gives /kwú[·kw]pi. The raised w is gone and
# a plain one stands where it was, so this reader writes what the file holds and the hand extraction
# carries what the page prints. docs/research/Salishan/refs.md has the measurement.

import io
import os
import re
import sys

from glyph_names import decoded
from line_breaks import joined
from salish_marking import DERIVED, SPOKEN, UNCLASSIFIED, rendered, switches, tagged_spans
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "2012_Robertson.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "CharleyAlexisMayoos-WilliamCelestin_BCIndigenousPeoplesChinukPipaScript_Robertson"
    "_Salish_nlekepmxcin-secwepemctsin_2012_mixed.txt")

# What this paper writes the two Salish languages with, on the morphemic line. Robertson names his
# Americanist symbols on page 30: č, š and a dot under an x. The dot is a combining mark, so a token
# carrying only it holds nothing the shared inventory would find.
MARKS = "ʔʕɬłƛəχčṣ̌ʷ"

PAGE = re.compile(r"^===== page \d+ =====$")

# Text N: Language (writer). The heading that opens each of the six texts.
TEXT_HEADING = re.compile(r"^Text (\d+):\s*(.*)$")

# A numbered line of a text. The number opens the transliteration row.
NUMBERED = re.compile(r"^(\d{1,3})\s+(\S.*)$")

# The two translation rows Robertson labels. Text 1 writes them out as CJ version and English
# version and Text 2 shortens both, so the colon is what the test hangs on.
CJ_ROW = re.compile(r"^CJ(?:\s+version)?:\s*(.*)$")
ENGLISH_ROW = re.compile(r"^English(?:\s+version)?:\s*(.*)$")

# A row that is nothing but a parenthesized phrase. Footnote 30 says one of these under a morphemic
# gloss is a plain-English gloss of the form above it, and one under a CJ row is a literal rendering
# of the Chinook Jargon.
PARENTHESIZED = re.compile(r"^\(.*\)$")

# A footnote marker inside a transliteration row. The page sets it as a superscript and the
# extraction puts it on the line, so stanza 5 arrives as skwa(l)inšut, 31 and stanza 9 as
# hawsšin 33 hawi. The Chinuk pipa transliteration of the two Salish letters is letters and
# punctuation throughout, so a run of digits standing on its own in one is always a marker. Text 3
# sets a date, Mi 4 1892, where the digits are the text, which is why this is asked of the Salish
# texts alone.
MARKER = re.compile(r"(?:(?<=\s)|^)\d{1,3}(?=\s|$)")

# The rows of a block, in the order the paper prints them. A long sentence wraps and the three come
# round again before the translations arrive, which is why this is a cycle and not a list.
BLOCK_ROWS = ("pipa", "morphemic", "gloss")

# Which text numbers are Salish. Texts 3 to 6 are Chinook Jargon and are recorded, not ingested.
SALISH_TEXTS = (1, 2)

LAYER = {
    "pipa": SPOKEN,
    "morphemic": DERIVED,
    "gloss": DERIVED,
    "cj translation": SPOKEN,
    "translation": SPOKEN,
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds a character this paper writes the Salish with."""
    return any(mark in text for mark in MARKS)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        raw = [decoded(one.rstrip("\n")) for one in handle]

    lines, welds = joined(raw)

    rows = []
    text = None
    number = None
    # Whether the lines arriving belong to a stanza. A footnote closes the block without touching
    # the stanza count, because the stanza after it still continues the run.
    open_block = False
    # Where in the pipa, morphemic, gloss cycle the block is. Reset by every numbered line.
    step = 0
    # Whether the row above was a Chinook Jargon translation, which is what tells a literal
    # rendering of it from a plain-English gloss of a morphemic line.
    after_cj = False
    # The rows of the block being read. A stanza too wide for the page is printed as two groups of
    # three rows and it is one sentence, so each row is collected and written once at the end.
    pending = {}
    # The parenthesized plain-English glosses of the block, which the paper sets on their own line
    # under the morphemic gloss and footnote 30 explains.
    plain = []

    def flush():
        """The block just read, written out one row per kind, in the order the paper prints them."""
        for kind in ("pipa", "morphemic", "gloss"):
            pieces = pending.get(kind)
            if pieces:
                mark = "T" if (text in SALISH_TEXTS) else "N"
                rows.append((mark, number or 0, "Text %d" % text, kind, " ".join(pieces)))
        for body in plain:
            rows.append(("N", number or 0, "Text %d" % text, "gloss", body))
        for kind in ("cj translation", "translation"):
            pieces = pending.get(kind)
            if pieces:
                rows.append(("N", number or 0, "Text %d" % text, kind, " ".join(pieces)))
        pending.clear()
        del plain[:]

    for trimmed in lines:
        if PAGE.match(trimmed) or not trimmed:
            continue

        heading = TEXT_HEADING.match(trimmed)
        if heading:
            if text is not None:
                flush()
            text = int(heading.group(1))
            number = None
            open_block = False
            step = 0
            after_cj = False
            rows.append(("N", 0, "Text %d" % text, UNCLASSIFIED, trimmed))
            continue

        if text is None:
            continue

        found = CJ_ROW.match(trimmed)
        if found:
            pending.setdefault("cj translation", []).append(found.group(1))
            after_cj = True
            continue

        found = ENGLISH_ROW.match(trimmed)
        if found:
            pending.setdefault("translation", []).append(found.group(1))
            after_cj = False
            continue

        if PARENTHESIZED.match(trimmed):
            # Under a CJ row this is that row rendered literally, and under a morphemic gloss it is
            # the plain-English gloss footnote 30 describes.
            if after_cj:
                pending.setdefault("cj translation", []).append(trimmed)
            else:
                plain.append(trimmed)
            continue
        after_cj = False

        found = NUMBERED.match(trimmed)
        # A stanza number continues the run. Robertson's footnotes are numbered too and they sit
        # inside the texts they annotate, so 30 Where a line with parenthesized information opens
        # exactly like a stanza does. Asking for the next number in the run is what tells them
        # apart: after stanza 2 the reader wants 3, and footnote 30 is not it.
        if found and (int(found.group(1)) == ((number or 0) + 1)):
            flush()
            number = int(found.group(1))
            open_block = True
            step = 1
            opening = found.group(2)
            if text in SALISH_TEXTS:
                opening = " ".join(MARKER.sub("", opening).split())
            pending.setdefault("pipa", []).append(opening)
            continue

        if found:
            # A number that does not continue the run opens a footnote, and a footnote sits between
            # two stanzas. Closing the block here is what keeps footnote 30's abbreviation list out
            # of stanza 2: without it the cycle went on reading prose as pipa, morphemic and gloss
            # until stanza 3 arrived. The stanza count is not touched, because stanza 3 still has
            # to follow stanza 2 across the footnote that sits between them.
            flush()
            open_block = False
            step = 0
            rows.append(("N", 0, "Text %d" % text, UNCLASSIFIED, trimmed))
            continue

        if not open_block:
            rows.append(("N", 0, "Text %d" % text, UNCLASSIFIED, trimmed))
            continue

        # A footnote marker the page set as a superscript and the extraction left standing on a
        # line of its own. Counting it as the next row of the cycle put stanza 6's gloss where its
        # transliteration belongs and every row after it one place out.
        if trimmed.isdigit():
            continue

        # A Text 2 translation carries no label and opens with a quote instead. Reading it as the
        # next row of the cycle would file a line of English as the language.
        held = pending.get("translation")
        if held and not held[-1].rstrip().endswith(("’", "'")):
            held.append(trimmed)
            continue
        if trimmed.startswith(("‘", "'", "“")):
            pending.setdefault("translation", []).append(trimmed)
            continue

        kind = BLOCK_ROWS[step % len(BLOCK_ROWS)]
        step += 1
        pending.setdefault(kind, []).append(trimmed)
    if text is not None:
        flush()

    # Every line no text reached, added to the record as unclassified so the marked file holds every
    # token of the language the paper printed. For this one that is the whole analysis, its cited
    # forms, and the bibliography. They stay out of the pure stream.
    missed = unreached(lines, covered_tokens(one[4] for one in rows))
    for page, where, reason, missing, body in missed:
        rows.append(("N", 0, "not reached page %d" % page, UNCLASSIFIED, body))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# BC Indigenous people's Chinuk pipa script: History, analysis, and texts.\n")
        handle.write("# David D. Robertson, University of Victoria. ICSNL 47, UBCWPL 32, 2012.\n")
        handle.write("# Text 1 is Nɬeʔkepmxcin, written by Charley Alexis Mayoos and published in\n")
        handle.write("# Kamloops Wawa #82, 11 June 1893. Text 2 is Secwepemctsin, written by\n")
        handle.write("# William Celestin of the Salmon Arm area.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is Salish, N is anything else. Texts 3 to 6\n")
        handle.write("# are Chinook Jargon, which is a pidgin and a language of its own, and they\n")
        handle.write("# are recorded here and held out of the pure stream.\n")
        handle.write("# The pipa row is Mayoos' own shorthand transliterated letter for letter. It\n")
        handle.write("# is plain ASCII and carries no mark of the modern orthography, so it is\n")
        handle.write("# marked by where it sits and not by its letters.\n")
        handle.write("# The morphemic row is Robertson's analysis and holds forms nobody wrote, so\n")
        handle.write("# it is in the record and out of the pure stream.\n")
        handle.write("line\tsection\tkind\tswitches\tcontent\n")
        for mark, count, section, kind, body in rows:
            layer = LAYER[kind]
            if (mark == "T") and (kind == "morphemic"):
                content = rendered(body, layer, kind, MARKS)
                crossings = switches(body, MARKS)
            elif mark == "T":
                # The pipa row, whole. tagged_spans reads it by its characters and it has none.
                content = "T.%s.%s:{%s}" % (layer, kind, body)
                crossings = 0
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, body)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n" % (count, section, kind, crossings, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, count, section, kind, body in rows:
            if (mark != "T") or (kind != "pipa"):
                continue
            key = " ".join(body.split())
            if key in already:
                repeated += 1
                continue
            already.add(key)
            handle.write("%s\n" % key)
            kept += 1

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (section, count), UNKNOWN_KIND, "", body)
               for mark, count, section, kind, body in rows
               if (kind == UNCLASSIFIED) and not section.startswith("not reached")]
    flagged.extend(missed)
    # Every join is reported, because a join this reader took is a decision a person has to be able
    # to check. The alphabet tables are the place it would be wrong.
    flagged.extend((0, "line %d" % at, "word joined across a line break", fragment_half, "%s%s"
                    % (fragment_half, rest)) for at, fragment_half, rest in welds)
    stuck_count = write_unsorted(stuck, "BC Indigenous people's Chinuk pipa script", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language lines written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d lines skipped as already written\n" % repeated)
    out.write("  %d words put back together across a line break\n" % len(welds))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    kinds = {}
    for mark, count, section, kind, body in rows:
        kinds[kind] = kinds.get(kind, 0) + 1
    out.write("\n  by kind: %s\n" % ", ".join("%s %d" % (one, kinds[one]) for one in sorted(kinds)))
    for which in (1, 2, 3, 4, 5, 6):
        numbers = sorted({row[1] for row in rows if row[2] == ("Text %d" % which) and row[1]})
        if numbers:
            gaps = [one for one in range(1, max(numbers) + 1) if one not in numbers]
            out.write("  Text %d blocks 1..%d, missing %s\n"
                      % (which, max(numbers), ", ".join(str(one) for one in gaps) if gaps
                         else "none"))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
