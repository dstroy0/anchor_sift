#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Write out the language the sift finds in the papers that have no reader.
#
#   Usage:  python tools/dev_env/sift_extract.py
#
# Nine papers have a reader written against their layout, and what those readers produce is named
# for the speaker, the language and the year, because the paper states all three. The other 143
# state those things too, in prose nobody has read.
#
# So what comes out of here is a different kind of thing and is kept apart from the nine. It goes
# to build/corpora/sifted/, one file per paper, and it carries no speaker and no language name.
# Guessing either from a filename would put a name on somebody's words on no evidence, and the
# whole of the rest of this directory exists to avoid exactly that.
#
# What each line does carry is where it came from and how far outside English it fell. A person
# opening one paper can start at the strongest lines and work down. These are candidates. A line
# here has been found, not read.

import collections
import glob
import io
import os
import sys

# Every Salishan category on the import path, so this can use a sibling from another one.
for _category in os.scandir(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))):
    if _category.is_dir():
        sys.path.insert(0, _category.path)

from english_sift import (PAGE, PAPERS, english_reference, language_reference, sorted_into,
                          surprise)
from paper_language import attribution, named_in

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
SIFTED = os.path.join(ROOT, "build", "corpora", "sifted")

# The nine that already have a reader. Their output is named and verified and does not belong here.
READ = {"ICSNL59_Garcia_Hannon_Stacey_final", "HallPhillipsICSNL60",
        "ICSNL59_LaFontaine_Janzen_final", "Matthewson_Redan_ICSNL61",
        "AlexanderDavis_ICSNL61", "ICSNL56_DavisJ_2_final-1",
        "22-Nater-Bella-Coola-tale-10", "19-Lyon_ICSNL50_final-78", "2013_Lindley_Lyon"}


def found_in(path, english, language):
    """Every line of a paper sorted against the two anchors, with its page and both scores."""
    held = []
    page = 0
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            trimmed = " ".join(line.split())
            if PAGE.match(trimmed):
                page = int(trimmed.split()[2])
                continue
            if not trimmed:
                continue
            where = sorted_into(trimmed, english, language)
            if where == "english":
                continue
            held.append((page, where, surprise(trimmed, english[0], english[1]),
                         surprise(trimmed, language[0], language[1]), trimmed))
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(SIFTED, exist_ok=True)
    english = english_reference()
    language = language_reference()
    if not english[1] or not language[1]:
        out.write("  no anchors, run the nine extractors first\n")
        out.flush()
        return 1
    out.write("  english anchor: %d lines, %d byte pairs\n" % (english[2], english[1]))
    out.write("  language anchor: %d pure lines, %d byte pairs\n" % (language[2], language[1]))

    papers = 0
    kept = 0
    residue = 0
    named = 0
    index = []
    candidates = collections.defaultdict(list)
    for path in sorted(glob.glob(os.path.join(PAPERS, "*.txt"))):
        stem = os.path.basename(path)[:-4]
        if stem in READ:
            continue
        held = found_in(path, english, language)
        if not held:
            continue
        papers += 1
        kept += sum(1 for one in held if one[1] == "language")
        residue += sum(1 for one in held if one[1] == "residue")
        # The language the paper names in its own title and abstract. Read, not assigned: a paper
        # that names one language and no other is attributed to it, and one that names several is
        # left unattributed, which is right for a comparative paper.
        says = attribution(named_in(path))
        if says:
            named += 1
        target = os.path.join(SIFTED, "%s.sifted.tsv" % stem)
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write("# Lines of %s sorted against two anchors: English, and the corpus\n"
                         % stem)
            handle.write("# nine hand-read papers produced, which is known to be pure.\n")
            handle.write("# Written by tools/dev_env/sift_extract.py. No reader has been written\n")
            handle.write("# for this paper, so nothing here is verified against its layout.\n")
            handle.write("#\n")
            handle.write("# language: %s\n"
                         % (says if says else "not named by this paper's front matter"))
            handle.write("# Read out of the paper's own title and abstract by paper_language.py,\n")
            handle.write("# not taken from the filename. Where the front matter names more than\n")
            handle.write("# one language, none is recorded.\n")
            handle.write("#\n")
            handle.write("# The speaker is not named. Papers name their speakers in acknowledgment\n")
            handle.write("# footnotes that nothing here reads, and a speaker is not a thing to\n")
            handle.write("# guess at.\n")
            handle.write("#\n")
            handle.write("# where: language, nearer the pure corpus than English.\n")
            handle.write("#        residue, nearer neither. Glosses, formatting and font damage\n")
            handle.write("#        land here, and it is the small set worth a person's time.\n")
            handle.write("# Lines nearer English are not written out at all.\n")
            handle.write("# to_english and to_language are bits of surprise per byte pair.\n")
            handle.write("#\n")
            handle.write("# A line here has been found, not read.\n")
            handle.write("page\twhere\tto_english\tto_language\ttext\n")
            for page, where, to_en, to_lang, text in sorted(held,
                                                            key=lambda one: one[3] - one[2]):
                handle.write("%d\t%s\t%.2f\t%.2f\t%s\n" % (page, where, to_en, to_lang, text))
        index.append((says or "", sum(1 for one in held if one[1] == "language"),
                      len(held), stem))
        if says:
            for page, where, to_en, to_lang, text in held:
                if where == "language":
                    candidates[says].append((text, stem, page))

    # One index over the lot, so the set can be read by language without opening every file.
    with open(os.path.join(SIFTED, "index.tsv"), "w", encoding="utf-8", newline="") as handle:
        handle.write("# Every paper with no reader, the language its own front matter names,\n")
        handle.write("# and how many of its lines the sift put on each side.\n")
        handle.write("# An empty language means the paper's front matter named more than one.\n")
        handle.write("language\tlanguage_lines\tall_lines\tpaper\n")
        for says, lines, whole, stem in sorted(index):
            handle.write("%s\t%d\t%d\t%s\n" % (says, lines, whole, stem))

    out.write("\n  %d papers written to %s\n" % (papers, os.path.relpath(SIFTED, ROOT)))
    out.write("  %d lines nearer the language, %d residue for a person to look at\n"
              % (kept, residue))
    out.write("  %d of the %d carry the language their own front matter names\n" % (named, papers))

    # One file per language, which is the record these candidates belong in. Not the same tier as
    # the nine: nothing here was read against a layout, and the speaker of any given line is not
    # known. What is known is which paper and page it came from, and that is carried with it.
    for language in sorted(candidates):
        held = candidates[language]
        target = os.path.join(SIFTED, "%s.candidates.pure.txt" % language.replace(" ", ""))
        already = set()
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write("# Candidate %s, sifted from %d papers with no reader.\n"
                         % (language, len({one[1] for one in held})))
            handle.write("# The language is the one each paper names in its own front matter.\n")
            handle.write("# No speaker is named and no line was read against a layout, so this is\n")
            handle.write("# not the same tier as the nine hand-read corpora and is kept apart.\n")
            handle.write("# Each line carries the paper and page it came from.\n")
            for text, stem, page in held:
                key = " ".join(text.split())
                if key in already:
                    continue
                already.add(key)
                handle.write("%s\t%s\tp%d\n" % (key, stem, page))
        out.write("  %-18s %5d candidate lines\n" % (language, len(already)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
