#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Upper Nicola Okanagan of twelve narratives from ICSNL 48, repairing the font substitution
# first.
#
#   Usage:  python tools/dev_env/extract_lindley_lyon.py
#
# Written for one paper. Twelve stories, and unlike the others in this set its subsections carry
# names: Okanagan, Interlinear gloss, Free translation, Commentary. Three of the twelve are three
# tellings of one story and three more are three tellings of another, each with its own commentary.
# The section numbers do not line up with the story count, and reading them positionally misfiles the
# versions against each other. The subsections are matched on their titles instead.
#
# This paper carries the same font substitution as the other Lyon volume, and the same table was
# tested against it independently: before the mapping, 2 tokens of 4332 were attested in Lyon's later
# papers on this language; after it, 965. That table is applied here and recorded in the output. A
# reader can then see the text passed through a transformation, and check the mapping.
#
# The appendix holds a note on transcription and glossing practice and two pronominal paradigm tables.
# Those are the language and they are not narrative, so they are kept and marked derived.

import io
import os
import re
import sys

from page_text import (language_line, repaired, repaired_english, repaired_line,
                       repaired_prose)
from salish_marking import (CAPS_RUN, DERIVED, MARKED, SPOKEN, TEXT_SPACE, UNCLASSIFIED,
                            is_mixed, rendered, switches, tagged_spans, unligatured)
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted
from space_repair import joined_words, vocabulary_of, welded

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

# The drafted page text, not the extraction. This paper's PDF hands back the font's own alphabet,
# and a corpus built on that is not the language: measured against the hand extraction read off the
# rendered pages, a third of what this reader used to write was a string the page does not print.
SOURCE = os.path.join(PAPERS, "2013_Lindley_Lyon.page.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "LottieLindley_TwelveMoreUpperNicolaOkanaganNarratives_LindleyLyon"
    "_Salish_nsyilxcen_2013_nomixed.txt")

MARKS = MARKED + "ʷ̓’ʼ"

PAGE = re.compile(r"^===== page \d+ =====$")
HEADING = re.compile(r"^(\d{1,2}(?:\.\d+)*)\s+(\S.*)$")
DOTTED = re.compile(r"\.\s*\.\s*\.")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,4})\)\s*(.*)$")
# The free translation closes a block and this paper writes it inside single quotes. The double
# quote is deliberately absent: these are stories full of people talking, and a transcription of
# quoted speech opens with one. Matching it ended the block at the first line somebody spoke in and
# sent every entry after that into the leftovers, which cost the other Lyon paper eight hundred.
QUOTED = re.compile(r"^['‘]")

# A segmentation line joins its morphemes with a hyphen or an equals sign, and neither character is
# touched by the font repair below. Testing for one is what keeps a wrapped transcription line from
# entering the record as segmentation because nothing else matched it.
SEGMENTED = re.compile(r"[-=]")

# A page number survives inside a block and would put the two-line cycle out of step by one for
# every word after it. Nothing in this orthography is written with digits alone.
PAGE_NUMBER = re.compile(r"^\d{1,4}$")

CATEGORIES = re.compile(
    r"\b(?:ABS|APPL|AUT|C1C2|C1|C2|CAUS|CHAR|CISL|CONJ|CUST|DEON|DEV|DIM|DIR|DRV|DUB|EMPH|"
    r"EPIS|EVID|INCEPT|INCH|INDEP|INTERJ|INT|LC|LOC|MID|OCC|RED|STAT|UPOSS|FUT|IMP|"
    r"DET|DEM|ERG|OBJ|POSS|PL|SG|SBJ|NOM|OBL|IPFV|NEG|TR|1SG|2SG|3SG|1PL|2PL|3PL)\b")

# What each named subsection holds. Matched on the title because the numbering does not line up
# with the story count once the multiple versions and their commentaries are counted.
def kind_of(title):
    """What a subsection holds, from its own heading."""
    lowered = title.lower()
    if lowered.startswith("okanagan"):
        return "running speech"
    if "interlinear" in lowered:
        return "interlinear"
    if "free translation" in lowered:
        return "free translation"
    if "commentary" in lowered:
        return "commentary"
    if "paradigm" in lowered or "transcription" in lowered or "abbreviation" in lowered:
        return "appendix"
    return None


LAYER = {
    "running speech": SPOKEN,
    "transcription": SPOKEN,
    "translation": SPOKEN,
    "free translation": SPOKEN,
    "segmentation": DERIVED,
    "gloss": DERIVED,
    "commentary": DERIVED,
    "appendix": DERIVED,
    # Kept and marked, held out of the ingestion stream until someone has classified it.
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds any character this paper writes the language with."""
    return any(mark in text for mark in MARKS)


def two_line_words(block):
    """One numbered block of the interlinear, as the two lines this paper gives for each word.

    The PDF handed the interlinear over a column at a time. A word arrives as its form and then its
    gloss on the next line, and the pair repeats until the free translation closes the block.
    Position is what fixes which line is which. Content cannot: iʔ and DET are both plain ASCII, and
    the form of a word with no affixes carries nothing a gloss does not.

    The form line here is the segmented form. It writes sm-sámaʔ and c-’tʕap-nwíxw where the running
    text of the same story writes the surface. A sentence rebuilt from this column is the paper's
    analysis of what was said and not a record of it.

    A slipped count is caught, not repaired, on the same test the other Lyon paper uses: an uppercase
    category label belongs to a gloss and cannot stand in a form.

    Returns the words, the free translation, any line left over, and whether the cycle slipped.
    """
    words = []
    translation = None
    leftover = []
    holding = [None, None]
    slot = 0

    def close():
        if any(one is not None for one in holding):
            words.append(tuple(holding))
        holding[0] = holding[1] = None

    for line in block:
        if PAGE_NUMBER.match(line):
            continue
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
        if slot == 2:
            close()
            slot = 0
    close()
    # Tested on a run of capitals, not on the label list. The list matches on word boundaries and
    # there is none inside 3POSS, and a form line reading father-3POSS passed it.
    slipped = any(CAPS_RUN.search(one[0] or "") for one in words)
    return words, translation, leftover, slipped


def looks_heading(trimmed):
    """A numbered heading, told apart from a contents entry and from a numbered example."""
    if NUMBERED_BLOCK.match(trimmed) or DOTTED.search(trimmed):
        return None
    found = HEADING.match(trimmed)
    if not found:
        return None
    if len(trimmed) > 78 or trimmed.endswith("."):
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
        # Ligatures come out here, before the loop below, so that everything reading these lines
        # sees the same text. Taking them out later left the unreached check comparing preﬁxsən-
        # against prefixsən- and reporting a hole that was not one.
        lines = [unligatured(one.rstrip("\n")) for one in handle]

    rows = []
    blocks = []
    running_at = []
    stories = {}
    section = None
    story = None
    holds = None
    number = None
    opening = []

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue
        if trimmed.startswith("References"):
            section = None
            holds = None
            continue

        opened = looks_heading(trimmed)
        if opened:
            section, title = opened
            story = section.split(".")[0]
            number = None
            if "." not in section:
                stories[story] = repaired_prose(title)
                holds = None
            else:
                holds = kind_of(title)
            continue

        if section is None:
            if not stories:
                opening.append(trimmed)
            continue

        if holds is None:
            continue

        name = stories.get(story, "")

        if holds == "running speech":
            # A footnote or an acknowledgment printed inside a story section is English throughout,
            # and the repair hides that by putting a glottal stop where its capital P stood. The
            # American Philosophical Society's Phillips Fund reached the ingestion stream that way.
            # So the test runs on the line as it arrived, where the English is still English.
            if not language_line(trimmed):
                rows.append(("N", 0, section, name, UNCLASSIFIED, repaired_english(trimmed)))
                continue
            # The Okanagan subsection is the language from end to end, so every substitution
            # applies to it and no token in it needs guarding. Where the extraction broke a word in
            # two is not known yet: the interlinear says that and has not been read. So the row is
            # written now to keep the paper's order, its place is remembered, and the words are put
            # back together below once the list exists.
            fixed = repaired(trimmed)
            if carries_language(fixed):
                running_at.append(len(rows))
                rows.append(("T", 0, section, name, "running speech", fixed))
            continue

        if holds in ("free translation", "commentary", "appendix"):
            # A free translation and a commentary are Lyon's own English. The appendix is his
            # pronominal paradigms, which are the language, so it keeps the repair that a capital
            # at the front of a word does not survive.
            fixed = (repaired_line(trimmed) if holds == "appendix"
                     else repaired_english(trimmed))
            mark = "T" if (holds == "appendix" and carries_language(fixed)) else "N"
            rows.append((mark, 0, section, name, holds, fixed))
            continue

        # A block is gathered whole and unrepaired, and read afterward. Its lines cannot be typed
        # one at a time, because which column a line belongs to is fixed by its position in the
        # block, and which repair a line may take depends on which column it turns out to be.
        found = NUMBERED_BLOCK.match(trimmed)
        if found:
            number = int(found.group(1))
            rest = found.group(2).strip()
            blocks.append((section, name, number, [rest] if rest else []))
            continue
        if number is None:
            continue
        blocks[-1][3].append(trimmed)

    # Each block read back as words. The sentence is the form column joined in order, and it is
    # marked segmentation because that column carries the morpheme boundaries. The surface of the
    # same story is in the Okanagan subsection above and is what reaches the ingestion stream.
    # Every block read first, so the list of true word forms exists before any of them is written.
    # An entry is one word, so the spaces inside it are the extraction's, and welding them shut
    # gives what the word really looks like. Only blocks that read cleanly contribute: one bad
    # entry in the list joins two real words together everywhere it matches.
    slipped_blocks = 0
    vocabulary = set()
    parsed = []
    for section, name, number, block in blocks:
        read = two_line_words(block)
        parsed.append((section, name, number, block, read))
        if not read[3]:
            vocabulary |= vocabulary_of(repaired(welded(one[0])) for one in read[0] if one[0])

    for section, name, number, block, read in parsed:
        words, translation, leftover, slipped = read
        if slipped:
            # The count slipped, so every column after that point is one line out and nothing in
            # the block can be named. Flagged whole. Nothing is written under a guessed name.
            slipped_blocks += 1
            for one in block:
                # Which column each line belongs to is exactly what is not known here, so the
                # repair is chosen from what the line itself turns out to be.
                fixed = repaired_line(one)
                rows.append(("T" if carries_language(fixed) else "N",
                             number, section, name, UNCLASSIFIED, fixed))
            continue
        built = " ".join(repaired(welded(one[0])) for one in words if one[0])
        if built:
            rows.append(("T", number, section, name, "segmentation", built))
        for one in words:
            if one[1]:
                rows.append(("N", number, section, name, "gloss", repaired_english(one[1])))
        if translation:
            rows.append(("N", number, section, name, "translation",
                         repaired_english(translation)))
        for one in leftover:
            # What sits after the free translation is the wrapped tail of it, a footnote, or Lyon's
            # prose discussing a form. The English test the other branches use is deliberately not
            # applied here: he cites words of the language inside English sentences, and dropping
            # those lines costs coverage with nothing gained.
            fixed = repaired_line(one)
            if carries_language(fixed):
                rows.append(("T", number, section, name, UNCLASSIFIED, fixed))

    # The running text, with the words the extraction broke put back together. Its rows were
    # written above to keep the paper's order, and the list that says where the breaks are only
    # exists now that the interlinear has been read.
    for at in running_at:
        row = rows[at]
        rows[at] = row[:5] + (joined_words(row[5], vocabulary),)

    # The list is written out beside the record, because the coverage check has to put the source
    # through the same joining and a second list built from the paper would not be the same one.
    words_at = TARGET[:-4] + ".words.txt"
    with open(words_at, "w", encoding="utf-8", newline="") as handle:
        handle.write("# The word forms this paper's interlinear gives, one to a line, with the\n")
        handle.write("# spaces the extraction put inside them taken out. Every entry comes from a\n")
        handle.write("# block whose two-line cycle read cleanly.\n")
        for one in sorted(vocabulary):
            handle.write("%s\n" % one)

    def prepared(text):
        """One line put through everything this reader does before recording it."""
        return joined_words(repaired_line(text), vocabulary)

    # Every line of the paper no subsection reached, added to the record as unclassified, so the
    # marked file holds every token of the language the paper printed. They stay out of the pure
    # stream and are listed in the flag file for someone to work through.
    # The union of every orthography, not this paper's own set. The coverage check counts a token
    # against the union. A finder using a narrower set leaves holes the check still reports.
    missed = unreached(lines, covered_tokens(one[5] for one in rows), repair=prepared)
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "not reached", "page %d" % page, UNCLASSIFIED, text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# 12 more Upper Nicola Okanagan narratives.\n")
        handle.write("# Nsyilxcən, Upper Nicola. Lottie Lindley and John Lyon.\n")
        handle.write("# Papers for the International Conference on Salish and Neighbouring\n")
        handle.write("# Languages, UBCWPL, 2013.\n")
        handle.write("# Three of the twelve are three tellings of one story and three more are\n")
        handle.write("# three tellings of another, each with its own commentary.\n")
        handle.write("#\n")
        handle.write("# READ FROM THE PAGE. This paper's PDF hands back the font's own alphabet\n")
        handle.write("# and not what the page prints, so this reader takes build/papers/\n")
        handle.write("# 2013_Lindley_Lyon.page.txt, which draft_page_text.py writes in the\n")
        handle.write("# orthography, and applies no substitution of its own.\n")
        handle.write("#\n")
        handle.write("# That text is a draft. Two things in it are settled only by the rendered\n")
        handle.write("# page and are still open here: which w is a labialized consonant, and which\n")
        handle.write("# inserted space is a word boundary. The hand extraction beside this paper\n")
        handle.write("# was read off the pages and is what says so.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is Nsyilxcən, N is anything else.\n")
        handle.write("# Subsections are matched on their titles, not their numbers, because the\n")
        handle.write("# numbering does not line up with the story count once the versions and\n")
        handle.write("# their commentaries are counted.\n")
        handle.write("line\tsection\tstory\tkind\tswitches\tcontent\n")
        for mark, count, sect, name, kind, text in rows:
            layer = LAYER[kind]
            if mark == "T":
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text)
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%s\t%d\t%s\n"
                         % (count, sect, name[:40], kind, crossings, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, count, sect, name, kind, text in rows:
            if (mark != "T") or (LAYER[kind] != SPOKEN):
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

    # A file of its own for what the tool could not sort: an interlinear line none of the tests
    # typed, and a line no subsection reached. The source is put through the same font repair
    # before comparing. A correctly repaired word is not reported as a hole.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (sect, count), UNKNOWN_KIND, "", text)
               for mark, count, sect, name, kind, text in rows
               if (kind == UNCLASSIFIED) and (sect != "not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "12 more Upper Nicola Okanagan narratives", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written\n" % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))
    out.write("  %d of %d interlinear blocks read cleanly, %d slipped and were flagged whole\n"
              % (len(blocks) - slipped_blocks, len(blocks), slipped_blocks))

    # Two counts per story, because they come from the two printings of it. The running speech is
    # the surface and is what reaches the ingestion stream. The rebuilt blocks are the interlinear.
    out.write("\n  %-40s %-16s %s\n" % ("story", "running speech", "rebuilt blocks"))
    spoken = {}
    built = {}
    for mark, count, sect, name, kind, text in rows:
        if kind == "running speech":
            spoken[name] = spoken.get(name, 0) + 1
        elif kind == "segmentation":
            built[name] = built.get(name, 0) + 1
    for name in sorted(set(spoken) | set(built)):
        out.write("  %-40s %-16d %d\n"
                  % (name[:40], spoken.get(name, 0), built.get(name, 0)))

    kinds = {}
    for mark, count, sect, name, kind, text in rows:
        kinds[kind] = kinds.get(kind, 0) + 1
    out.write("\n  by kind: %s\n" % ", ".join("%s %d" % (one, kinds[one]) for one in sorted(kinds)))
    out.write("  %d stories found\n" % len(stories))
    if opening:
        out.write("\n  the paper's opening, which names its speaker\n    %s\n"
                  % " ".join(opening)[:220])

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
