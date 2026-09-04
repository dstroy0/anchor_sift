#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the Bella Coola etymological database Hank Nater published in 2013.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_nater_etymology.py
#
# 1407 numbered lines over 52 pages, which is more of one language than the rest of this set holds
# together. Nater is asking how Salish Bella Coola is, and his answer is a table: every morpheme he
# knows, sorted by where it came from. 209 proto-Salish, 94 Coastal, 63 Interior, 214 non-Salish, 34
# areal, and 661 he cannot place at all.
#
# TWO TABLES, NOT ONE
#
# Sections 2.2 and 2.3 print four columns: line, gloss, the Bella Coola form, and a cognate in some
# other language. Section 4 prints two: the Na90 practical orthography with its gloss, then the
# phonemic form. The two need separate readers because their columns divide on different evidence.
# A reader that took the last form on every line would take the Bella Coola word through section 4
# and somebody else's language through everything before it.
#
# WHAT IS NOT BELLA COOLA
#
# The cognate column is the point of the paper and it is where the other languages are. Section 2.3.4
# carries 121 entries of Haisla, Heiltsuk, Oowekyala and Kwak̓wala, which are North Wakashan, and
# section 2.3.4's second table adds Proto-Athabascan, Eyak, Carrier, Tahltan, Nootka, Quileute,
# Chinook and Yurok. Squamish, Sechelt, Shuswap, Lillooet and Halkomelem are Salish and still not
# this language. The who column says which, and only the Bella Coola column reaches the pure stream.
#
# The cognate column is found by its opening token, which is one of the abbreviations the paper
# defines for itself in section 1.1, a spelled-out language name, or a reconstruction opening with an
# asterisk. All three are the paper's own notation. No rule here was invented for the purpose.
#
# THE PRACTICAL ORTHOGRAPHY IS THE SAME WORDS IN DIFFERENT LETTERS
#
# Section 4 prints each entry twice. AKW'A and ʔak‟ʷa are one word, and section 2.1 gives the
# mapping: ʷ is written w, c is ts, ƛ‟ is tl‟, ɬ is lh, x is c, χ is x, and ʔ is 7. Both are Bella
# Coola, so both are recorded, but only the phonemic column joins the pure stream. Two orthographies
# in one stream would put the byte pairs of a transliteration into the measurement of a language.

import io
import os
import re
import sys

from inserted_space import closed_spaces
from salish_marking import DERIVED, SPOKEN, UNCLASSIFIED, rendered, switches, tagged_spans
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "2013_Nater.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "unstated_HowSalishIsBellaCoola_Nater_Salish_nuxalk_2013_mixed.txt")

# Kept in step with NATER_ETYM in hand_extraction/papers.py. ǝ is U+01DD and ə is U+0259, which NFC
# does not unify, and this paper prints both. The apostrophe is deliberately absent for the same
# reason it is absent from the other Nater paper: it is his ejective mark and also the closing quote
# of all 1275 glosses, so holding it makes every English gloss a word of the language.
MARKS = "ʔʕɬłƛəχ7̓̔̕ʷ˽" + "ǝ√" + "áíúà" + "ᴗɢʁʒščɣλˑ"

PAGE = re.compile(r"^===== page \d+ =====$")

TARGET_LANGUAGE = "Nuxalk"

# Where the four-column tables stop and the two-column appendix starts.
APPENDIX = "4 Bella Coola vocabulary with unknown origin"

# The column head the paper reprints at the top of every table page. The four-column form names the
# language of its own fourth column, which is what says whose a reconstruction in that column is.
# Without reading it, every *ƛ‟ǝp and *mus in the paper arrives with nobody's name on it.
HEADING = re.compile(r"^Line\s+(?:Gloss|Na90)\b")
COLUMN_HEAD = re.compile(r"^Line\s+Gloss\s+BC\s+(\S+)\s+Cognates$")

# A numbered row opens with its line number. Numbering is erased where an allomorph or a derivation
# is listed, so a row without one is still a row, and the number is not a reliable row test on its
# own. What it is reliable for is order: the numbers never go backwards, so a number below the
# highest seen is a page number or a citation and not the head of a row.
NUMBERED = re.compile(r"^(\d{1,4})\s+(\S.*)$")

# The last numbered entry, which is where the appendix stops. A four-digit number past this one is a
# year or a page range in the references, and the references sit under the last row of the table.
LAST_ENTRY = 1407

# The abbreviations section 1.1 defines, plus the languages the body spells out. A token from this
# set opens the cognate column, and everything from there to the end of the line is somebody else's
# language. Kw is the paper's Kwakiutl, which is Kwak̓wala.
TAGS = frozenset((
    "BC", "CS", "Ha", "He", "IS", "Kw", "Li", "No", "NS", "NW", "Oo", "PA", "PS", "Se", "Sh", "Sq",
    "Oo/Kw", "Oo/Ha", "He/Oo", "PA-Eyak", "Halkomelem", "Tahltan", "Carrier", "Yurok", "Quileute",
    "Chinook", "Eyak", "Nootka", "Tsimshian", "Gitksan", "Athabascan", "early",
))

# What the paper marks a comparison with. Everything after it is a form the entry points at, not the
# entry's own headword, and a reader taking the last form on the line would take that one instead.
COMPARE = ("cf.", "(cf.")

# A wrapped cognate rather than a row of its own: the citation or the rest of a gloss that did not
# fit on the line above. An entry with erased numbering opens with an English gloss word instead.
WRAPPED = ("(", "„", "*", "√", "-", "+")

# Which languages a two-letter tag names, for the who column of the cognate side.
NAMED = {
    "Ha": "Haisla", "He": "Heiltsuk", "Kw": "Kwak̓wala", "Li": "Lillooet", "No": "Nootka",
    "Oo": "Oowekyala", "Se": "Sechelt", "Sh": "Secwepemctsin", "Sq": "Squamish",
    "Oo/Kw": "Oowekyala", "Oo/Ha": "Oowekyala", "He/Oo": "Heiltsuk", "PA-Eyak": "Proto-Athabascan",
    "PA": "Proto-Athabascan", "PS": "PS", "CS": "CS", "IS": "IS", "NS": "NS", "NW": "NW",
    "BC": TARGET_LANGUAGE, "early": "Athabascan",
}

# What a column head names, where the name it prints is a whole language. Areal and Non-NW head
# columns that hold two or three languages in one cell. A reconstruction under either of those is
# left for a person, because assigning it would mean picking whichever language the cell names first.
HEADED = {"CS": "CS", "IS": "IS", "PS": "PS", "NW": "NW"}

# What a practical orthography lemma is made of once its notation is taken off: capital letters. The
# root sign, the parentheses of an optional segment, the 7 that writes a glottal stop and the two
# apostrophes that write an ejective are all notation and none of them is a letter.
NOTATION = "√()7'‟,"


def cut_at_comparison(tokens):
    """The row up to the paper's own cf., which introduces a form the entry only points at."""
    for at, token in enumerate(tokens):
        if token in COMPARE:
            return tokens[:at]
    return tokens


def cognate_opens_at(tokens):
    """Where the cognate column starts, or the length of the row where there is no cognate."""
    for at, token in enumerate(tokens):
        if token in TAGS:
            return at
        if token.startswith("*"):
            return at
    return len(tokens)


def trailing_form(tokens):
    """The last column of a row: its final token, and any before it the paper joined with a comma.

    ʔaluuχ, √ʔaluuq and qikʷu, χikʷu are one entry with two forms in it. Taking the final token
    alone would drop the first of every such pair.
    """
    if not tokens:
        return []
    at = len(tokens) - 1
    while (at > 0) and tokens[at - 1].endswith(","):
        at -= 1
    return [one.strip(",") for one in tokens[at:] if one.strip(",")]


def leading_lemma(tokens):
    """The practical orthography column of an appendix row, which is its leading run of capitals.

    The gloss can hold a capital of its own, as in horn played in KUSYUT dance, so the run is read
    from the head of the row and stops at the first token that is not one.
    """
    kept = []
    for token in tokens:
        bare = token.strip(NOTATION)
        if not bare or not bare.isupper() or not bare.isalpha():
            break
        kept.append(token.strip(","))
    return kept


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [closed_spaces(one.rstrip("\n")) for one in handle]

    rows = []
    seen = set()
    in_appendix = False
    highest = 0
    where = "front matter"
    headed = ""

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue
        if HEADING.match(trimmed):
            found = COLUMN_HEAD.match(trimmed)
            headed = HEADED.get(found.group(1), "") if found else ""
            continue
        if trimmed.startswith(APPENDIX):
            in_appendix = True
            where = "section 4"
            continue

        found = NUMBERED.match(trimmed)
        if found and (int(found.group(1)) > highest) and (int(found.group(1)) <= LAST_ENTRY):
            highest = int(found.group(1))
            seen.add(highest)
            where = "(%d)" % highest
            trimmed = found.group(2)
        elif trimmed.startswith(WRAPPED) or not highest:
            # A wrapped cognate, or anything before the first table row. Neither is an entry.
            rows.append((where, "", UNCLASSIFIED, trimmed, ""))
            continue

        tokens = cut_at_comparison(trimmed.split())
        if not tokens:
            continue

        if in_appendix:
            lemma = leading_lemma(tokens)
            phonemic = trailing_form(tokens[len(lemma):])
            for one in lemma:
                rows.append((where, TARGET_LANGUAGE, "practical orthography", one, ""))
            for one in phonemic:
                rows.append((where, TARGET_LANGUAGE, "cited form", one, ""))
            if not phonemic:
                rows.append((where, "", UNCLASSIFIED, trimmed, ""))
            continue

        opens = cognate_opens_at(tokens)
        for one in trailing_form(tokens[:opens]):
            rows.append((where, TARGET_LANGUAGE, "cited form", one, ""))
        if opens < len(tokens):
            tag = tokens[opens]
            who = NAMED.get(tag, "") if tag in TAGS else headed
            kind = "cited form" if who else UNCLASSIFIED
            rows.append((where, who, kind, " ".join(tokens[opens:]), ""))

    # Every line no branch above reached, so the record holds every token the paper printed.
    missed = unreached(lines, covered_tokens(one[3] for one in rows), marks=MARKS)
    for page, spot, reason, missing, text in missed:
        rows.append(("not reached page %d" % page, "", UNCLASSIFIED, text, ""))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# How Salish is Bella Coola? Hank Nater, 2013. The paper carries no volume\n")
        handle.write("# number on its pages; the archive index files it with the other 2013 papers.\n")
        handle.write("#\n")
        handle.write("# 1407 numbered entries: every Bella Coola morpheme the author knows, with\n")
        handle.write("# where it came from. 661 of them he cannot place, and those are section 4.\n")
        handle.write("#\n")
        handle.write("# The cognate column is not this language. Haisla, Heiltsuk, Oowekyala and\n")
        handle.write("# Kwak̓wala are North Wakashan; Proto-Athabascan, Eyak, Carrier, Tahltan,\n")
        handle.write("# Nootka, Quileute, Chinook and Yurok are further off again; Squamish,\n")
        handle.write("# Sechelt, Shuswap, Lillooet and Halkomelem are Salish and still not this\n")
        handle.write("# language. The who column says which.\n")
        handle.write("#\n")
        handle.write("# Section 4 prints each entry twice, once in the Na90 practical orthography\n")
        handle.write("# and once phonemically. Both are Bella Coola. Only the phonemic column is\n")
        handle.write("# written to the pure file, because two orthographies in one stream would\n")
        handle.write("# measure a transliteration alongside the language.\n")
        handle.write("line\twho\tkind\tswitches\tcontent\n")
        for at, (spot, who, kind, text, gloss) in enumerate(rows, 1):
            spoken = (kind == "cited form") and (who == TARGET_LANGUAGE)
            layer = SPOKEN if spoken else DERIVED
            if kind == UNCLASSIFIED:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            else:
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text, MARKS)
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (at, who or spot, kind, crossings, content))

    # The Bella Coola words alone. The practical orthography is held out by its kind and every other
    # language by the who column, which is the whole reason both columns are there.
    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for spot, who, kind, text, gloss in rows:
            if (kind != "cited form") or (who != TARGET_LANGUAGE):
                continue
            for span, run in tagged_spans(text, MARKS):
                if (span != "T") or not run.strip():
                    continue
                key = " ".join(run.split())
                if key in already:
                    continue
                already.add(key)
                handle.write("%s\n" % key)
                kept += 1

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, spot, UNKNOWN_KIND, "", text) for spot, who, kind, text, gloss in rows
               if (kind == UNCLASSIFIED) and not spot.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "How Salish is Bella Coola", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d Bella Coola words written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    languages = {}
    for spot, who, kind, text, gloss in rows:
        if kind == "cited form":
            languages[who] = languages.get(who, 0) + 1
    out.write("\n  by language: %s\n"
              % ", ".join("%s %d" % (one, languages[one]) for one in sorted(languages)))

    if seen:
        gaps = [one for one in range(1, max(seen) + 1) if one not in seen]
        out.write("  entries 1..%d, %d with numbering the paper erased\n" % (max(seen), len(gaps)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
