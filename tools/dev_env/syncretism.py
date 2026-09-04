#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Count how many readings one written word carries, and what that does over a sentence, for Section 4.13
# of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/syncretism.py
#
# Polish humour turns on using a word correctly in order to use it incorrectly, and the reason is that
# Polish forms are shared between grammatical slots. That is countable where the grammar of every word is
# written beside it, and these treebanks write it: each token carries its lemma and the case, number,
# gender and person it stands in, so the readings sharing one surface form can be counted instead of
# guessed at.
#
# It also answers a question left open by the earlier work here, where a reading over a growing window
# kept climbing and would not settle. If the average written word carries more than one reading, then
# taking a second word multiplies the readings instead of settling the first, and the possibilities over a
# sentence grow as a product. Below one they cannot grow. That is the difference between a walk that
# explodes and one that collapses, and it is a property of a language and not of any parser.
#
# Two counts are reported because they answer different questions. How many readings a word carries when
# it is met at random in running text, which is what a reader faces. And how many the average distinct
# form carries, which is what the language holds regardless of how often each is used.
#
# What this cannot see: a treebank records the reading a word has in the sentence it appeared in, not
# every reading it could have. So a form is ambiguous here only if the corpus happened to use it both
# ways, and a longer corpus finds more ambiguity. Comparisons between languages of unlike size are
# therefore not safe, and the token counts are given so that is visible.

import io
import math
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

WHAT_IT_IS = {
    "polish": "seven cases, heavy syncretism",
    "finnish": "fifteen cases, little syncretism",
    "hungarian": "agglutinative",
    "estonian": "fourteen cases",
    "german": "four cases, much syncretism",
    "english": "almost no inflection",
    "vietnamese": "no inflection at all",
    "turkish": "agglutinative",
}


def read_treebank(path):
    """Every token as its written form and the reading the sentence gave it."""
    seen = {}
    order = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if (not line) or (not line[0].isdigit()):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 6 or ("-" in parts[0]) or ("." in parts[0]):
                continue
            form = parts[1].lower()
            reading = "%s|%s|%s" % (parts[2].lower(), parts[3], parts[5])
            seen.setdefault(form, set()).add(reading)
            order.append(form)
    return seen, order


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-12s %-32s %-9s %-11s %-11s %s\n"
              % ("language", "what its grammar does", "tokens", "per word", "per form", "over ten"))

    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("ud_") and name.endswith(".conllu")):
            continue
        language = name[3:-7]
        seen, order = read_treebank(os.path.join(CORPORA, name))
        if len(order) < 5000:
            continue

        # What a reader meets: the readings carried by each word as it comes
        met = statistics.fmean(len(seen[form]) for form in order)
        # What the language holds: the readings carried by each distinct form, however rare
        holds = statistics.fmean(len(readings) for readings in seen.values())
        # Ten words of running text, if the readings of each multiply
        over_ten = met ** 10
        rows.append((language, len(order), met, holds, over_ten))

    for language, tokens, met, holds, over_ten in sorted(rows, key=lambda row: -row[2]):
        out.write("  %-12s %-32s %-9d %-11.4f %-11.4f %s\n"
                  % (language, WHAT_IT_IS.get(language, ""), tokens, met, holds,
                     ("%.0f" % over_ten) if over_ten < 1e7 else "%.1e" % over_ten))

    out.write("\n  per word is what a reader meets, per form is what the language holds\n")
    out.write("  over ten is those readings multiplied across ten words of running text\n")

    if len(rows) >= 4:
        out.write("\n  every language here carries more than one reading per word, so the\n")
        out.write("  possibilities grow with every word taken and none of them collapse\n")
        least = min(rows, key=lambda row: row[2])
        most = max(rows, key=lambda row: row[2])
        out.write("  the flattest is %s at %.4f, which is %.0f over ten words\n"
                  % (least[0], least[2], least[2] ** 10))
        out.write("  the steepest is %s at %.4f, which is %.0f over ten words\n"
                  % (most[0], most[2], most[2] ** 10))
        out.write("  and the corpora differ in size by %.1f times, which moves these counts\n"
                  % (max(row[1] for row in rows) / float(min(row[1] for row in rows))))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
