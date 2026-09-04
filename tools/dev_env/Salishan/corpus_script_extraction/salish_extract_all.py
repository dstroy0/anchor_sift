#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Pull every line of Salish text out of every extracted paper held here, keeping all of it.
#
#   Usage:  python tools/dev_env/salish_extract_all.py
#
# The rule is include by default. A line that might be the language goes in the file with a note saying
# what it might instead be, and a line is never dropped for failing a test. The reverse rule, drop unless
# it passes, was used once here and it discarded two thirds of a twenty-two minute story because two
# printings of it disagreed about accents. There is not much of this language written down and no test
# written from outside it is worth losing a sentence to.
#
# Every row carries where it came from: the paper, the page, and the line. So a row that turns out to be a
# gloss line or a segmentation line can be found and corrected against the source instead of being guessed
# at, and a row that turns out to be good is already attributed.
#
# What the rows are marked as:
#   text          carries the marked consonants, no gloss tags, no segmentation marks
#   segmented     carries morpheme or clitic boundaries, so it is an analysis of a form
#   glossed       carries grammatical category tags, so it is a gloss line
#   mixed         carries the marked consonants and enough English to be prose about the language
#
# Nothing here decides which papers are usable. salish_purity.py already reports which files lost their
# phonemes in extraction, and a file that failed there produces rows that look like text and are not.

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

# The marked consonants and vowels a Salish orthography is written with
MARKED = "ʔʕɬƛəχx̣ʷ̓ʼ"

# A grammatical category tag on a gloss line
TAGS = re.compile(r"\b(?:[1-3](?:SG|PL|DU)|SG|PL|DU|NOM|ACC|ERG|ABS|GEN|DAT|LOC|ART|DEM|DET|"
                  r"POSS|PASS|CAUS|APPL|TR|INTR|REFL|RECP|IMPF|PERF|PROG|ASP|TNS|PAST|FUT|"
                  r"IRR|SUBJ|IND|CONJ|NEG|WH|REP|EVID|HYP|INCH|RES|REL|AUG|DIM|TEL|FACT|"
                  r"DISC|COMP|CONCL|CONF|ADH|REIN|KAT|CLF|MID|CTR|LC|COS|AUT|NMLZ|PROSP|"
                  r"DVL|STAT|OBJ|OBL|SBJ|SBJV|EXCL|INS|QLT|RFM|INDEP|INFER|IRED|INDR)\b")

# A morpheme, clitic or reduplication boundary, which marks an analysis and not a written form
SEGMENTS = re.compile(r"[=~<>\[\]]|(?<=[^\s])-(?=[^\s])")

# Enough English to be prose about the language instead of the language
ENGLISH = re.compile(r"\b(?:the|and|that|this|with|from|which|for|are|was|were|have|has|been|"
                     r"would|there|their|these|those|then|than|when|where|what|about|into|"
                     r"paper|section|example|language|suffix|speaker|analysis)\b", re.IGNORECASE)

PAGE = re.compile(r"^===== page (\d+) =====$")


def classify(line):
    """What a line looks like, given it holds the marked characters."""
    english = len(set(one.lower() for one in ENGLISH.findall(line)))
    if TAGS.search(line):
        return "glossed"
    if SEGMENTS.search(line):
        return "segmented"
    if english >= 2:
        return "mixed"
    return "text"


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isdir(PAPERS):
        out.write("  no %s\n" % PAPERS)
        out.flush()
        return 1

    target = os.path.join(CORPORA, "salish_all_lines.tsv")
    counted = {}
    papers = 0
    rows = 0

    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("paper\tpage\tline\tkind\ttext\n")
        for name in sorted(os.listdir(PAPERS)):
            if not name.endswith(".txt"):
                continue
            if name.startswith("icsnl_index"):
                continue
            path = os.path.join(PAPERS, name)
            with open(path, encoding="utf-8", errors="replace") as source:
                lines = source.read().splitlines()

            page = 0
            held = 0
            for number, line in enumerate(lines, 1):
                marker = PAGE.match(line.strip())
                if marker:
                    page = int(marker.group(1))
                    continue
                trimmed = " ".join(line.split())
                if len(trimmed) < 2:
                    continue
                if not any(symbol in trimmed for symbol in MARKED):
                    continue
                kind = classify(trimmed)
                handle.write("%s\t%d\t%d\t%s\t%s\n"
                             % (name[:-4], page, number, kind, trimmed))
                counted[kind] = counted.get(kind, 0) + 1
                held += 1
                rows += 1
            if held:
                papers += 1

    out.write("  %d papers held Salish characters, %d lines written to\n" % (papers, rows))
    out.write("  %s\n" % target)
    out.write("\n  %-12s %s\n" % ("kind", "lines"))
    for kind in sorted(counted, key=lambda key: -counted[key]):
        out.write("  %-12s %d\n" % (kind, counted[kind]))
    out.write("\n  nothing was dropped. A line that holds the marked characters is in the file\n")
    out.write("  with the paper, page and line it came from, and the kind is a note on it\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
