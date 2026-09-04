#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Split a word's ambiguity into the part about what kind of word it is and the part about which form of
# it this is, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/category_or_inflection.py
#
# Everything measured here so far has counted readings per written word as one number, and it is two
# things stacked. A form can be unclear about what kind of word it is, where English run is a noun and a
# verb and German Essen is a meal and to eat. Or it can be settled about that and unclear about which
# form of it this is, where a Russian noun's written form serves several cases at once. Those are
# different problems and a channel that solves one does not touch the other.
#
# The split is multiplicative and exact. For any written word, the readings it carries divide into how
# many kinds of word it can be, and how many readings it has left once the kind is fixed. The two
# multiply back to the whole, so each is reported as the geometric mean of its factor and the product of
# the two columns is the geometric mean of the total.
#
# The reason to separate them is Straits Salish, which is argued to have no noun and verb contrast at the
# word level at all. A language like that does not sit at the ambiguous end of the category factor. It
# sits at one, the settled end, because a language with a single category has nothing to be ambiguous
# between and any annotation of it records one kind of word everywhere. The instrument would call it
# clean. The work of deciding whether a root is predicating or referring still has to happen, and it
# happens somewhere this measurement cannot reach, which is the reason to keep the two factors apart and
# to distrust a low category factor without asking what produced it.
#
# What makes Straits Salish hard is that its resolver is not written down.
# Meaning there follows the season and the state of the land, which is shared knowledge between speakers
# standing in one place at one time and is absent from any text taken away from that place. Every
# measurement in this file assumes the thing that settles a word is somewhere in the string. That
# assumption is what this scale is for, and it is a property of the languages tested and not of language.
#
# No Salishan corpus is measured here. The published academic description is the right source for that
# family and the community archives are not mine to take from.
#
# Words are keyed as written from the second word of a sentence on, with the first word folded to
# lowercase, since a capital there is a convention of writing and not a mark the language makes.
#
# What this cannot see: a treebank records the reading a word had where it appeared, not every reading it
# could have, which is why every corpus is cut to one size before the columns are set beside each other.

import io
import math
import os
import statistics
import sys

from case_or_splitting import CAP, WHAT_IT_IS, capped, load

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")


def keyed(sentences):
    """Every word as the key it is written with, and the reading split into kind and form."""
    rows = []
    for sentence in sentences:
        row = []
        for place, entry in enumerate(sentence):
            folded, written, reading = entry
            lemma, kind, feats = reading.split("|", 2)
            row.append((folded if place == 0 else written, lemma, kind, feats))
        rows.append(row)
    return rows


def split_ambiguity(rows):
    """How much of a word's ambiguity is which kind of word it is, and how much is which form."""
    readings = {}
    kinds = {}
    for row in rows:
        for key, lemma, kind, feats in row:
            readings.setdefault(key, set()).add((lemma, kind, feats))
            kinds.setdefault(key, set()).add(kind)

    category = []
    inflection = []
    whole = []
    mixed = 0
    counted = 0
    for row in rows:
        for entry in row[1:]:
            key = entry[0]
            total = len(readings[key])
            kind_count = len(kinds[key])
            category.append(math.log(kind_count))
            inflection.append(math.log(total / float(kind_count)))
            whole.append(math.log(total))
            counted += 1
            if kind_count > 1:
                mixed += 1

    return (math.exp(statistics.fmean(category)),
            math.exp(statistics.fmean(inflection)),
            math.exp(statistics.fmean(whole)),
            mixed / float(counted) if counted else float("nan"))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("ud_") and name.endswith(".conllu")):
            continue
        language = name[3:-7]
        sentences, used = capped(load(os.path.join(CORPORA, name)), CAP)
        if used < 5000:
            continue
        category, inflection, whole, mixed = split_ambiguity(keyed(sentences))
        rows.append((language, used, category, inflection, whole, mixed))

    rows.sort(key=lambda row: -row[2])

    out.write("  %-12s %-27s %-11s %-11s %-11s %s\n"
              % ("language", "what it is", "which kind", "which form", "together",
                 "words of two kinds"))
    for language, used, category, inflection, whole, mixed in rows:
        out.write("  %-12s %-27s %-11.4f %-11.4f %-11.4f %.4f\n"
                  % (language, WHAT_IT_IS.get(language, ""), category, inflection, whole, mixed))

    out.write("\n  which kind is how many kinds of word the written form can be\n")
    out.write("  which form is what is left once the kind is settled\n")
    out.write("  the two multiply to together, all three as geometric means\n")
    out.write("  words of two kinds is the share of words whose form spans more than one\n")

    out.write("\n  where each language puts its ambiguity\n")
    out.write("  %-12s %-11s %s\n" % ("language", "in the kind", "reading"))
    for language, used, category, inflection, whole, mixed in rows:
        weight = math.log(category) / math.log(whole) if whole > 1.0 else float("nan")
        if weight != weight:
            note = "carries almost no ambiguity either way"
        elif weight >= 0.5:
            note = "mostly what kind of word it is"
        else:
            note = "mostly which form of it this is"
        out.write("  %-12s %-11.3f %s\n" % (language, weight, note))

    out.write("\n  in the kind is the share of the whole taken by the category factor,\n")
    out.write("  measured on the logarithms since the two factors multiply\n")
    out.write("\n  a language with no noun and verb contrast reads as zero on this scale\n")
    out.write("  and as one on the category factor, because a single category cannot be\n")
    out.write("  ambiguous with anything. It would be called clean here while none of its\n")
    out.write("  interpretation had been done, so a low category factor is worth nothing\n")
    out.write("  until it is known whether the contrast was resolved or never existed\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
