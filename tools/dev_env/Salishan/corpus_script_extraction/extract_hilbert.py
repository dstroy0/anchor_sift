#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Lushootseed of Vi taqʷšəblu Hilbert from ICSNL 1983, following that paper's own
# structure.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_hilbert.py
#
# Written for one paper. Poking Fun in Lushootseed is her essay, in English, about humour her
# students kept missing, with forty numbered examples in Lushootseed set into it. Each example is
# printed twice under the same number: the Lushootseed first, then her English for it. So the
# number is the pairing and the order decides which is which, and nothing else has to.
#
# THE ORTHOGRAPHY IS NOT REPAIRED AND THAT IS DELIBERATE.
#
# This is a 1983 typescript and its scan is badly damaged. ʔ arrives as ?, ə arrives as ~ and J and
# G, ʷ arrives as V and v, and her own name is set as VI [!.aq liS'"} blu] lIil bert. The Lyon
# papers had damage like this and it was repaired, but only because a candidate table could be
# tested: applying it moved attested tokens from 1 of 3599 to 811 against Lyon's later papers on the
# same language.
#
# The same test on this paper says nothing. Six modern Lushootseed papers yield 1068 distinct
# Lushootseed tokens between them, and of the 103 damaged tokens here, 0 are attested before a
# candidate mapping and 0 after. Her vocabulary is Raven and Bear and Marblemount and the names of
# houses; theirs is grammar. The reference does not share enough with her to decide anything, which
# is the case font_substitution.py names as the test having said nothing either way.
#
# So the text comes out as it arrived. A guessed table applied to Vi Hilbert's words would put forms
# into a corpus that nobody said, and nothing downstream would ever question them. Marked damaged
# and left alone, the words are still hers, and the repair stays available to whoever finds a
# reference that shares her vocabulary.
#
# WHERE HER ENGLISH ENDS, WHICH THIS FILE GETS RIGHT NINETEEN TIMES IN TWENTY-ONE
#
# The typescript sets each example in an indented column and the essay at full width, and the
# extraction dropped every leading space. The width survived and separates the two, which is what
# COLUMN below is for. What it does not separate is an example's English from a story summary
# printed under it, because those are set in the same indented column and the blank line between
# them is gone too.
#
# The proportion rule catches eight of the ten that run on: her English for an example is about as
# long as the example, never more than one line longer. Examples 15 and 18 run on by exactly one
# line and pass it. Both are recorded correctly in the hand extraction, which is the control this
# file is graded against, and neither reaches the pure stream, since only the Lushootseed does.
#
# She asks in the paper that the moral of a story never be explained. That is not this file's to
# keep or break. It is the reason her essay is kept whole beside the examples and not thrown away
# as apparatus. The essay is where she says what she is doing and why.

import io
import os
import re
import sys

from salish_marking import DERIVED, SPOKEN, UNCLASSIFIED, rendered, switches, tagged_spans
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "1983_Hilbert.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
#
# The speaker comes first because the speaker is who the corpus is of. The name that used to sit in
# that slot here was Vi Hilbert's, and she is the one who wrote this paper: the twenty-one examples
# in it were said by her aunt Susie Sampson Peter of the Upper Skagit and by Martha LaMont, recorded
# by Leon Metcalf between 1950 and 1958 and by Thom Hess in 1963, and transcribed and translated by
# Hilbert afterward. Nothing in the old name said so.
TARGET = os.path.join(
    CORPORA,
    "SusieSampsonPeter-MarthaLaMont_PokingFunInLushootseed_Hilbert"
    "_Salish_lushootseed_1983_mixed.txt")

PAGE = re.compile(r"^===== page \d+ =====$")

# A marker anywhere in a line, not only at its start, and tolerating the space this typewriter left
# inside the bracket on either side of the number. Example 5 ends and its English begins on one line:
# qa~qs. tai ?as~awit. (5 ) And he
# Anchored at the start, that put her English into the Lushootseed stream. Allowing the space only
# after the number missed ( 20), and the whole English translation of example 20 was then read as
# more of Susie Sampson Peter's sentence and written into the pure stream as something she said.
NUMBERED = re.compile(r"\(\s*(\d{1,3})\s*\)")

# A page number the typescript left on its own line, between an example and its translation.
PAGE_NUMBER = re.compile(r"^\d{1,4}$")

# The width of the indented column the examples are set in.
#
# The typescript indents every numbered example, its Lushootseed and its English alike, and sets the
# essay at full width. The extraction dropped the leading spaces, so both arrive flush left and
# nothing in a line says which block it belongs to. What survived is the width: of the 138 lines
# inside an example block, the longest is 46 characters, and 144 of the essay's 308 lines are longer
# than that.
#
# Without this the English of an example ran on into the essay under it. Example 2's translation is
# the one line ‘High class, high class was Raven.’ and it was recorded with the next eleven lines of
# Hilbert's commentary welded onto it, as something Susie Sampson Peter had said. Coverage was 100
# percent throughout, because every token was in the file; it was in the wrong row.
COLUMN = 46

# What the damaged typescript writes the language with. Not the modern orthography: ? is the
# glottal stop here, ~ and J and G are the schwa, V and v are labialization. A test built on ʔ and
# ə finds nothing in this file at all.
MARKS = "?~JG@V%]!"

LAYER = {
    "transcription": SPOKEN,
    "citation": SPOKEN,
    # Hilbert's English for what her aunt and Martha LaMont said, made from the recordings years
    # afterward, so it is hers and is not a record of anything either of them uttered.
    "translation": DERIVED,
    "essay": DERIVED,
    # The page of Thomas E. Hukari's Halkomelem and Configuration the PDF carries after this paper.
    "foreign": DERIVED,
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds a character this typescript writes the language with."""
    return any(mark in text for mark in MARKS)


def examples(lines, ends_at):
    """The forty numbered examples, each as its Lushootseed and her English for it.

    A number appears twice. The first time it opens the Lushootseed, the second time it opens her
    translation, and each runs on until the next number or a page number interrupts it. Content
    cannot tell the two apart here, because the damage leaves both looking like neither.
    """
    held = {}
    order = []
    taken = set()
    number = None
    which = None
    # Set when a marker opened a Lushootseed slot and carried no text with it. The typescript puts
    # such a marker in the left margin, part way down the previous example's English, and the OCR
    # flattened that into its own line. Example 3's English runs on for two lines after the bare
    # (4) that interrupts it, and those two lines are hers in English, not the start of example 4.
    waiting = False
    previous = None

    def open_number(one):
        if one not in held:
            held[one] = {"said": [], "english": []}
            order.append(one)
            return "said"
        return "english"

    for at, line in enumerate(lines):
        # Where this paper ends and the next one in the volume begins. Its opening lines are short
        # enough to pass for the indented column, so example 21's English took its title.
        if at >= ends_at:
            break
        trimmed = " ".join(line.split())
        if not trimmed or PAGE.match(trimmed) or PAGE_NUMBER.match(trimmed):
            continue

        marks = list(NUMBERED.finditer(trimmed))
        # A line too wide for the indented column is the essay resuming, and it closes whatever
        # example was open. Tested before the marker search, because the essay names an example
        # number in prose often enough to matter.
        if len(line.rstrip()) > COLUMN:
            number = None
            which = None
            waiting = False
            continue
        if not marks:
            if (number is None) or (which is None):
                continue
            taken.add(at)
            # A line with none of the typescript's marks, while a Lushootseed slot is still
            # waiting for its first line, is the previous example's English running past the
            # marker in the margin.
            if waiting and not carries_language(trimmed) and (previous is not None):
                held[previous]["english"].append(trimmed)
                continue
            if waiting:
                waiting = False
            held[number][which].append(trimmed)
            continue

        # Text before the first marker belongs to whatever was open.
        taken.add(at)
        lead = trimmed[:marks[0].start()].strip()
        if lead and (number is not None) and (which is not None):
            held[number][which].append(lead)
        for index, mark in enumerate(marks):
            if (number is not None) and (which == "english"):
                previous = number
            number = int(mark.group(1))
            which = open_number(number)
            stop = marks[index + 1].start() if (index + 1) < len(marks) else len(trimmed)
            rest = trimmed[mark.end():stop].strip()
            if rest:
                held[number][which].append(rest)
                waiting = False
            else:
                waiting = (which == "said")
    return [(one, held[one]) for one in order], taken


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [one.rstrip("\n") for one in handle]

    # The PDF carries the first page of the next paper in the volume, Thomas E. Hukari's Halkomelem
    # and Configuration, after this one ends. Its prose is English and holds no Lushootseed, but the
    # damaged mark set reads Victoria and nonconfigurationality? as forms of the language, so it
    # would put both into this record as things somebody said.
    #
    # Kept and named, not cut. Cutting it lost those tokens from the record and the coverage check
    # then reported this paper as incomplete. It is not incomplete. The words are in the PDF and
    # they belong to somebody else's paper.
    next_paper = len(lines)
    for at, line in enumerate(lines):
        if line.strip().startswith("Halkome"):
            next_paper = at
            break

    rows = []
    held_lines = []
    cited = set()
    found, taken = examples(lines, next_paper)
    for number, parts in found:
        said = " ".join(parts["said"])
        english = " ".join(parts["english"])
        held_lines.append((0, number, 0, len(parts["said"]), len(parts["english"])))
        if said:
            rows.append(("T", number, "transcription", said))
        if english:
            rows.append(("N", number, "translation", english))

    # Her essay. It is English and it is hers, and it is what the examples are set into, so it is
    # kept and marked derived, not dropped as apparatus. Told from the examples by which lines they
    # took, not by comparing text. A line matched against a bag of words matches nothing, and every
    # continuation line went into the essay a second time.
    for at, line in enumerate(lines):
        trimmed = " ".join(line.split())
        if not trimmed or PAGE.match(trimmed) or PAGE_NUMBER.match(trimmed) or (at in taken):
            continue
        if at >= next_paper:
            rows.append(("N", 0, "foreign", trimmed))
            continue
        rows.append(("N", 0, "essay", trimmed))
        # She names four words in her essay and glosses each in quotes, and gives three names: the
        # supernatural dawi?, the same name written ~awi? ten lines later, and the place ~acaladi.
        # Those are the only Lushootseed outside the numbered examples, and a reader that keeps the
        # essay whole without pulling them leaves seven forms in prose and out of the record.
        for token in trimmed.split():
            # Only sentence punctuation comes off. The damaged orthography writes with ], [, ' and "
            # as letters: ]u?il ‘happy’ opens with one, and stripping it gives u?il, a word this
            # paper does not contain.
            plain = token.strip(".,;:")
            if plain and carries_language(plain) and (plain not in cited):
                cited.add(plain)
                rows.append(("T", 0, "citation", plain))

    missed = unreached(lines, covered_tokens(one[3] for one in rows))
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Poking Fun in Lushootseed.\n")
        handle.write("# Vi taqʷšəblu Hilbert, University of Washington. Papers for the\n")
        handle.write("# International Conference on Salish and Neighbouring Languages, 1983.\n")
        handle.write("# Her essay on humour her students kept missing, with forty numbered\n")
        handle.write("# Lushootseed examples and her own English for each.\n")
        handle.write("#\n")
        handle.write("# ORTHOGRAPHY NOT REPAIRED. This is a 1983 typescript and its scan is\n")
        handle.write("# damaged: ? stands for the glottal stop, ~ and J and G for the schwa,\n")
        handle.write("# V and v for labialization. A repair table was tried and could not be\n")
        handle.write("# tested: of 103 damaged tokens, 0 are attested in six modern Lushootseed\n")
        handle.write("# papers before a mapping and 0 after, because her story vocabulary and\n")
        handle.write("# their grammar vocabulary do not meet. An untested table applied to her\n")
        handle.write("# words would put forms in that nobody said, so none was applied.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is Lushootseed, N is anything else.\n")
        handle.write("# An example is printed twice under one number, the Lushootseed first and\n")
        handle.write("# her English second, so the number pairs them and the order names them.\n")
        handle.write("line\tkind\tswitches\tcontent\n")
        for mark, number, kind, text in rows:
            # Not span-marked. The damage leaves this paper's Lushootseed in plain ASCII, so the
            # span test reads huy, six, tud and Zilid as English and cuts them out of her own
            # sentence. She does not switch languages inside an example: her English is the second
            # block under the same number, so an example line is one language from end to end.
            content = "%s.%s.%s:{%s}" % (mark, LAYER[kind], kind, text)
            handle.write("line#${%d}\t%s\t0\t%s\n" % (number, kind, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, number, kind, text in rows:
            if (mark != "T") or (kind != "transcription"):
                continue
            key = " ".join(text.split())
            if not key or (key in already):
                continue
            already.add(key)
            handle.write("%s\n" % key)
            kept += 1

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "example %d" % number, UNKNOWN_KIND, "", text)
               for mark, number, kind, text in rows if kind == UNCLASSIFIED]
    flagged.extend(missed)

    # The English of an example and the story summary under it are set in the same indented column,
    # so the width rule that separates both from the essay does not separate them from each other.
    # Nothing else in the extracted lines does either: the blank line the typescript puts between
    # two paragraphs is gone, and both are English prose in the same measure.
    #
    # What the paper does give is proportion. Her English for an example runs to about as many lines
    # as the example does, never more than one longer, except for example 13 where the translation
    # carries two bracketed asides. A translation much longer than that has run on into the summary,
    # and the ones that have are named here. None is trimmed at a guessed point.
    for number, said, english in ((one[1], one[3], one[4]) for one in held_lines):
        if english > (said + 1):
            flagged.append((0, "(%d)" % number, UNKNOWN_KIND, "",
                            "the English is %d lines against %d of Lushootseed, so it has run on "
                            "into the story summary under it; where it ends is not recoverable "
                            "from the extracted text and the hand extraction has the boundary"
                            % (english, said)))
    stuck_count = write_unsorted(stuck, "Poking Fun in Lushootseed", flagged)

    counted = {}
    for mark, number, kind, text in rows:
        counted[kind] = counted.get(kind, 0) + 1
    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))
    out.write("\n  by kind: %s\n"
              % ", ".join("%s %d" % (one, counted[one]) for one in sorted(counted)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
