#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Okanagan of three speakers from ICSNL 50, repairing the font substitution first.
#
#   Usage:  python tools/dev_env/extract_lyon_priests.py
#
# Written for one paper, and this is the only one so far whose characters had to be repaired before it
# could be read at all. Its font wrote plain letters in place of the orthography, so the text arrives as
# iP naPì ʼqwQaylqs where it should read iʔ naʔɬ ʼqwʕaylqs.
#
# The mapping was tested, not assumed. font_substitution.py applies a candidate table to the damaged
# tokens and counts how many become forms attested in Lyon's recent papers on the same language, whose
# extraction kept its characters. Before the mapping, 1 token of 3599 was attested. After it, 811. The
# same table tested on the other damaged Lyon paper moved 2 of 4332 to 965. A wrong mapping cannot do
# that, because a wrong substitution produces strings the language does not contain.
#
# What the table does not cover is recorded with it. The caron entries are written by this font as a
# separate character before their letter, so x̌ arrives as ˇx, and the order of replacement matters.
#
# Three speakers, and the permissions are named in the paper. Conversation with the priest was told by
# George Lezard of the Penticton Indian Reserve in 1966 when he was eighty-five, recorded by Randy
# Bouchard and transcribed by Larry Pierre in 1970; Lyon updated that transcription with the permission of
# Arnie Baptiste, Larry Pierre's son. Smokey and the priest is Nellie's, reprinted with the permission of
# her great-granddaughter Lynne Jorgesen of the Upper Nicola Indian Band. The third story's teller is
# named in its own introduction, which this reports so the attribution comes from the paper.

import io
import os
import re
import sys

from page_text import (carries_orthography, language_line, repaired, repaired_english,
                       repaired_line, repaired_prose)
from salish_marking import (CAPS_RUN, DERIVED, MARKED, SPOKEN, UNCLASSIFIED, is_mixed,
                            rendered, switches, tagged_spans, unligatured)
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted
from space_repair import joined_words, vocabulary_of, welded

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

# The drafted page text, not the extraction. This paper's PDF hands back the font's own alphabet,
# and a corpus built on that is not the language. draft_page_text.py writes it back into the
# orthography and this reader applies no substitution of its own.
SOURCE = os.path.join(PAPERS, "19-Lyon_ICSNL50_final-78.page.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language without accents>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "GeorgeLezard-NellieGuitterez-AndrewMcGinnis_ThreeOkanaganStoriesAboutPriests_Lyon"
    "_Salish_nsyilxcen_2015_nomixed.txt")

MARKS = MARKED + "ʷ̓’ʼ"

PAGE = re.compile(r"^===== page \d+ =====$")
HEADING = re.compile(r"^(\d(?:\.\d)?)\s+(\S.*)$")
DOTTED = re.compile(r"\.\s*\.\s*\.")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,4})\)\s*(.*)$")
# The free translation closes a block and this paper writes it inside single quotes. The double
# quote is deliberately absent: these are stories full of people talking, and a transcription of
# quoted speech opens with one. Matching it ended the block at the first line somebody spoke in and
# sent every entry after that into the leftovers, which is where hundreds of them were.
QUOTED = re.compile(r"^['‘]")

# A segmentation line joins its morphemes with a hyphen or an equals sign, and neither character is
# touched by the font repair below. Testing for one is what keeps a wrapped transcription line or a
# page number from entering the record as segmentation because nothing else matched it.
SEGMENTED = re.compile(r"[-=]")

# The extraction ran the first two columns of a word together wherever the segmentation opens at
# the root, giving ’qwQaylqs√ ’qwQay=lqs on one line. A segmentation of its own can also hold √,
# as in-ks-√ ’ma ’y-ìt-ím does, and what tells the two apart is what stands before the root: a
# merged line has a bare word there, a segmentation has morpheme separators. This paper separates
# with + as well as with a hyphen or an equals sign, as s+√na ’qw and c+n+√ʔuɬxw-s do, so + belongs
# in the class with them. Leaving it out reads the front of a segmentation as a word of the story.
MERGED = re.compile(r"^([^-=•+√]+?)\s*(√.*)$")

# A page number survives inside a block and would put the four-line cycle out of step by one for
# every word after it. Nothing in this orthography is written with digits alone.
PAGE_NUMBER = re.compile(r"^\d{1,4}$")

CATEGORIES = re.compile(
    r"\b(?:ABS|APPL|AUT|C1C2|C1|C2|CAUS|CHAR|CISL|CONJ|CUST|DEON|DEV|DIM|DIR|DRV|DUB|EMPH|"
    r"EPIS|EVID|INCEPT|INCH|INDEP|INTERJ|INT|LC|LOC|MID|OCC|RED|STAT|UPOSS|"
    r"DET|DEM|ERG|OBJ|POSS|PL|SG|SBJ|NOM|OBL|IPFV|NEG|TR|1SG|2SG|3SG|1PL|2PL|3PL)\b")

# Taken from each story's own introduction, which names its teller and the recording
SPEAKER = {
    "1": "George Lezard, Penticton Indian Reserve, told 1966",
    "2": "Nellie Guitterez, Upper Nicola Indian Band, told 1978 or 1979",
    "3": "Kiláwnaʔ (Andrew McGinnis), Penticton Indian Reserve, told 9 October 2014",
}

LAYER = {
    "running speech": SPOKEN,
    "transcription": SPOKEN,
    "translation": SPOKEN,
    "segmentation": DERIVED,
    "gloss": DERIVED,
    "word gloss": DERIVED,
    # Kept and marked, held out of the ingestion stream until someone has classified it.
    UNCLASSIFIED: DERIVED,
}


def carries_language(text):
    """Whether a line holds any character this paper writes the language with."""
    return any(mark in text for mark in MARKS)


def kind_by_notation(text):
    """What a line is, from the notation this paper defines, where its position is unavailable.

    Used only inside a block whose cycle slipped. Position is the better evidence and it is gone,
    so what is left is what Lyon states about his own writing: a run of two or more capitals is a
    gloss label, and √ marks a root, which a segmentation carries and a spoken word does not.

    Nothing else is decided here. A line with neither is a word as spoken or the segmentation of a
    word with no affixes to mark, and in this language those are frequently the same string: block
    1 opens with p and then p again. Naming one of them would be inventing the answer.
    """
    if CAPS_RUN.search(text):
        return "gloss"
    if "√" in text:
        return "segmentation"
    return UNCLASSIFIED


def split_merged(text):
    """Put back the space between two columns the extraction ran together.

    Applied where a block could not be read by position and its lines are kept as they arrived. The
    line still holds ʔacəcqáʔ√ʔac•c•qáʔ-wi as one token there, and a reader looking for the word
    ʔacəcqáʔ in the record does not find it inside that. The rule is the one four_line_words uses.
    """
    out = []
    for token in text.split():
        found = MERGED.match(token)
        if found:
            out.append(found.group(1))
            out.append(found.group(2))
        else:
            out.append(token)
    return " ".join(out)


def four_line_words(block):
    """One numbered block of the interlinear, as the four lines the paper gives for each word.

    The PDF handed this paper's interlinear over a column at a time. A word arrives as four
    consecutive lines: the word as spoken, its segmentation, its gloss, and an English word for it.
    Position in that cycle is what fixes which line is which. Content cannot, because a short word
    written in plain letters comes out the same on the first two lines and carries nothing to test.
    Block 1 opens with p, then p again, and only the order separates the two.

    Two things break the cycle and both are handled. Where the extraction ran the first two columns
    together the line fills both positions at once. A page number sitting inside a block is passed
    over, because counting it puts every word after it out of step.

    A third breaks it and cannot be handled: a word given no English gloss takes three lines instead
    of four, and block 44 opens with one. Nothing in the lines themselves marks it, and every word
    after it lands a slot early. That is caught, not repaired. An uppercase category label belongs
    to a gloss and cannot stand in a spoken word or its segmentation. Finding one in either of those
    slots is proof the count has slipped, and the caller is told.

    Returns the words, the free translation that closes the block, any line left over, and whether
    the cycle slipped.
    """
    words = []
    translation = None
    leftover = []
    slot = 0
    holding = [None, None, None, None]

    def close():
        if any(one is not None for one in holding):
            words.append(tuple(holding))
        holding[0] = holding[1] = holding[2] = holding[3] = None

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
        # The fourth line is an English word for the word above it, and the paper does not always
        # give one: block 44 opens with ixí P / ixíP / DEM and nothing else. Where it is missing,
        # the next word's own first line stands in that place, and reading it as a gloss puts every
        # word after it a slot early. A word gloss is English and carries none of the damaged
        # orthography, which is what separates you.all and priest from yaQyá;;Qt and t@twít.
        # Closing early on a single-letter line was tried, on the reasoning that l, p and t are
        # proclitics and never an English gloss. It cost 331 lines and eight blocks. A single letter
        # does stand in that slot often enough to matter, and the rule is not there.
        if (slot == 3) and any(carries_orthography(one) for one in line.split()):
            close()
            slot = 0
        if slot == 0:
            found = MERGED.match(line)
            if found:
                holding[0] = found.group(1)
                holding[1] = found.group(2)
                slot = 2
                continue
        holding[slot] = line
        slot += 1
        if slot == 4:
            close()
            slot = 0
    close()
    # Tested on a run of capitals, not on the label list. The list matches on word boundaries and
    # there is none inside 3POSS. A block whose gloss line read father-3POSS passed the check and
    # put that into the ingestion stream as something somebody said.
    slipped = any(CAPS_RUN.search(one[0] or "") or CAPS_RUN.search(one[1] or "")
                  for one in words)
    return words, translation, leftover, slipped


def looks_heading(trimmed):
    """A numbered heading, told apart from the contents listing and from a numbered example."""
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
        # sees the same text. This paper holds 76 of them and one reached the corpus as ﬁve.
        lines = [unligatured(one.rstrip("\n")) for one in handle]

    rows = []
    blocks = []
    running_at = []
    intros = {}
    section = None
    story = None
    number = None
    seen_heading = set()

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue

        opened = looks_heading(trimmed)
        if opened:
            number_of, title = opened
            # The contents list repeats every heading before the body. A top-level heading opens
            # its section on its second appearance. Subsection entries in that list are padded with
            # dot leaders and are already refused above, so they never register as seen, and
            # skipping their first appearance discarded every one of them.
            if "." not in number_of:
                if number_of not in seen_heading:
                    seen_heading.add(number_of)
                    continue
            section = number_of
            story = number_of.split(".")[0]
            number = None
            continue

        if section is None:
            continue

        who = SPEAKER.get(story, "")

        if "." not in section:
            # Prose introducing a story, which is where the paper names its teller
            intros.setdefault(section, []).append(trimmed)
            continue

        if section.endswith(".1"):
            # A footnote or an acknowledgment printed inside a story section is English throughout,
            # and the repair hides that by putting a glottal stop where its capital P stood. So the
            # test runs on the line as it arrived. A line of these stories always holds a word with
            # an accented vowel or a glottalization mark in it and English prose does not.
            if not language_line(trimmed):
                rows.append(("N", 0, section, UNCLASSIFIED, who, repaired_english(trimmed)))
                continue
            # The running text of a story is the language from end to end, so every substitution
            # applies to it and no token in it needs guarding. Where the extraction broke a word in
            # two is not known yet: the interlinear says that and has not been read. So the row is
            # written now to keep the paper's order, its place is remembered, and the words are put
            # back together below once the list exists.
            fixed = repaired(trimmed)
            if carries_language(fixed):
                running_at.append(len(rows))
                rows.append(("T", 0, section, "running speech", who, fixed))
            continue

        # A block is gathered whole and unrepaired, and read afterward. Its lines cannot be typed
        # one at a time, because which column a line belongs to is fixed by its position in the
        # block, and which repair a line may take depends on which column it turns out to be.
        found = NUMBERED_BLOCK.match(trimmed)
        if found:
            number = int(found.group(1))
            rest = found.group(2).strip()
            blocks.append((section, number, who, [rest] if rest else []))
            continue
        if number is None:
            continue
        blocks[-1][3].append(trimmed)

    # Each block read back as words. The sentence is the first column joined in order, and it is
    # the only part of a block that was spoken: the other three columns are Lyon's analysis of it.
    # Every block read first, so the list of true word forms exists before any of them is written.
    # An entry is one word, so the spaces inside it are the extraction's, and welding them shut
    # gives what the word really looks like. Only blocks that read cleanly contribute: an entry
    # taken from a block whose cycle slipped is not a word, and one bad entry in the list joins
    # two real words together everywhere it matches.
    slipped_blocks = 0
    vocabulary = set()
    parsed = []
    for section, number, who, block in blocks:
        read = four_line_words(block)
        parsed.append((section, number, who, block, read))
        if not read[3]:
            vocabulary |= vocabulary_of(
                repaired(welded(one[slot])) for one in read[0] for slot in (0, 1) if one[slot])

    for section, number, who, block, read in parsed:
        words, translation, leftover, slipped = read
        if slipped:
            # The count slipped somewhere in this block, so every column after that point is one
            # line out and nothing in it can be named. The whole block is flagged. Emitting the
            # sentence anyway would put gloss text such as know+INCH -manage.to-DIR-3ERG into the
            # ingestion stream as though someone had said it.
            slipped_blocks += 1
            for one in block:
                # Which column each line belongs to is exactly what is not known here, so the
                # repair is chosen from what the line itself turns out to be.
                fixed = repaired_line(split_merged(one))
                kind = kind_by_notation(fixed)
                rows.append(("N" if kind == "gloss" else "T", number, section, kind, who, fixed))
            continue
        said = " ".join(repaired(welded(one[0])) for one in words if one[0])
        if said:
            rows.append(("T", number, section, "transcription", who, said))
        for one in words:
            if one[1]:
                rows.append(("T", number, section, "segmentation", who, repaired(welded(one[1]))))
            if one[2]:
                rows.append(("N", number, section, "gloss", who, repaired_english(one[2])))
            if one[3]:
                rows.append(("N", number, section, "word gloss", who, repaired_english(one[3])))
        if translation:
            rows.append(("N", number, section, "translation", who, repaired_english(translation)))
        for one in leftover:
            # What sits after the free translation is a footnote, a page artifact, or Lyon's prose
            # discussing a form. The English test the other branches use is deliberately not
            # applied here: he cites words of the language inside English sentences, and dropping
            # those lines cost this paper six points of coverage with nothing gained.
            fixed = joined_words(repaired_line(split_merged(one)), vocabulary)
            if carries_language(fixed):
                rows.append(("T", number, section, UNCLASSIFIED, who, fixed))

    # The running text, with the words the extraction broke put back together. Its rows were
    # written above to keep the paper's order, and the list that says where the breaks are only
    # exists now that the interlinear has been read.
    for at in running_at:
        row = rows[at]
        rows[at] = row[:5] + (joined_words(row[5], vocabulary),)

    # The list is written out beside the record. The coverage check has to put the source through
    # the same joining before comparing, and building its own copy of the list from the paper gave
    # a different one that joined words wrongly, so it reads this instead.
    words_at = TARGET[:-4] + ".words.txt"
    with open(words_at, "w", encoding="utf-8", newline="") as handle:
        handle.write("# The word forms this paper's interlinear gives, one to a line, with the\n")
        handle.write("# spaces the extraction put inside them taken out. Every entry comes from a\n")
        handle.write("# block whose four-line cycle read cleanly.\n")
        for one in sorted(vocabulary):
            handle.write("%s\n" % one)

    def prepared(text):
        """One line put through everything this reader does before recording it.

        Used on the source when working out which lines never reached the record. A line outside
        every section still passes all three steps on its way in, and comparing it against a source
        that has had only some of them applied reports a hole that is not there.
        """
        return joined_words(repaired_line(split_merged(text)), vocabulary)

    # Every line of the paper no section reached, added to the record as unclassified, so the
    # marked file holds every token of the language the paper printed. That is the front matter,
    # the prose introducing each story, and Lyon's discussion. They stay out of the pure stream.
    # The union of every orthography, not this paper's own set. The coverage check counts a token
    # against the union. A finder using a narrower set leaves holes the check still reports.
    missed = unreached(lines, covered_tokens(one[5] for one in rows), repair=prepared)
    for page, where, reason, missing, text in missed:
        rows.append(("T", 0, "not reached page %d" % page, UNCLASSIFIED, "", text))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Three Okanagan stories about priests. John Lyon, Simon Fraser University.\n")
        handle.write("# Okanagan, also called Nsyílxcən, Colville-Okanagan and Nqílxwcən, a\n")
        handle.write("# southern Interior Salish language. Three different fluent speakers.\n")
        handle.write("# Papers for the International Conference on Salish and Neighbouring\n")
        handle.write("# Languages 50, UBCWPL 40, 2015.\n")
        handle.write("# Conversation with the priest: George Lezard, Penticton Indian Reserve,\n")
        handle.write("# told 1966 at eighty-five, recorded by Randy Bouchard, transcribed by Larry\n")
        handle.write("# Pierre 1970, updated by permission of Arnie Baptiste, his son.\n")
        handle.write("# Smokey and the priest: Nellie, reprinted by permission of her\n")
        handle.write("# great-granddaughter Lynne Jorgesen, Upper Nicola Indian Band.\n")
        handle.write("#\n")
        handle.write("# READ FROM THE PAGE. This paper's PDF hands back the font's own alphabet\n")
        handle.write("# and not what the page prints, so this reader takes build/papers/\n")
        handle.write("# 19-Lyon_ICSNL50_final-78.page.txt, which draft_page_text.py writes in the\n")
        handle.write("# orthography, and applies no substitution of its own.\n")
        handle.write("#\n")
        handle.write("# That text is a draft. Two things in it are settled only by the rendered\n")
        handle.write("# page and are still open here: which w is a labialized consonant, and which\n")
        handle.write("# inserted space is a word boundary. The hand extraction beside this paper\n")
        handle.write("# was read off the pages and is what says so.\n")
        handle.write("#\n")
        handle.write("# Mark is language.layer.kind. T is Okanagan, N is anything else.\n")
        handle.write("# Gloss categories are the paper's own, from its first footnote, unchanged.\n")
        handle.write("line\tsection\tkind\tspeaker\tswitches\tcontent\n")
        for mark, count, sect, kind, who, text in rows:
            layer = LAYER[kind]
            if mark == "T":
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text)
            else:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            handle.write("line#${%d}\t%s\t%s\t%s\t%d\t%s\n"
                         % (count, sect, kind, who, crossings, content))

    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    repeated = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for mark, count, sect, kind, who, text in rows:
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

    # A file of its own for what the tool could not sort: a line inside a story that none of the
    # tests typed, and a line no section reached, which here is the front matter and the prose
    # introducing each story. The source is put through the same font repair before comparing, so
    # a correctly repaired word is not reported. What that repair does to English is reported: it
    # turns Pierre into ʔierre and Quilchena into ʕuilchena, and those arrive here as unreached.
    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, "%s block %d" % (sect, count), UNKNOWN_KIND, "", text)
               for mark, count, sect, kind, who, text in rows
               if (kind == UNCLASSIFIED) and not sect.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "Three Okanagan stories about priests", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d target-language spans written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d spans skipped as already written\n" % repeated)
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))
    out.write("  %d of %d interlinear blocks read cleanly, %d had a word given no English\n"
              "  gloss and were flagged whole\n"
              % (len(blocks) - slipped_blocks, len(blocks), slipped_blocks))

    counted = {}
    for mark, count, sect, kind, who, text in rows:
        counted[(sect, kind)] = counted.get((sect, kind), 0) + 1
    out.write("\n  %-8s %-18s %s\n" % ("section", "kind", "lines"))
    for key in sorted(counted):
        out.write("  %-8s %-18s %d\n" % (key[0], key[1], counted[key]))

    out.write("\n  the opening prose of each story, which is where the teller is named\n")
    for section in sorted(intros):
        text = repaired_english(" ".join(intros[section]))
        out.write("    section %s: %s\n" % (section, text[:190]))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
