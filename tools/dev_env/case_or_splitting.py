#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Separate the grammar a capital letter carries from the arithmetic of splitting a vocabulary, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/case_or_splitting.py
#
# Keeping letter case lowered the readings per word in all eight languages, and the earlier run read that
# as eight languages using capitals grammatically. It is not evidence of that. Giving a word two keys
# instead of one divides its readings between them whatever decides the division, and the count falls for
# arithmetic reasons that have nothing to do with what the language marks.
#
# The null here removes the arithmetic. Every word that letter case actually splits keeps the same two
# keys and the same number of occurrences in each, and the occurrences are dealt out at random instead of
# by how they were written. The vocabulary ends up the same size with the same key frequencies, and the
# only thing destroyed is the correspondence between the capital and the reading. A drop that survives
# against this null is the language marking something. A drop that matches it was the split alone.
#
# The treatment also fixes what the earlier run got wrong at the first word. Two different things wear a
# capital letter in these languages: German marks a noun mid-sentence, and every language capitalizes the
# first word of a sentence whether it is a noun or not. Folding both throws away the grammar. Keeping both
# starves the first place, because a form seen only at the start of a sentence gets a key of its own and
# has been met in too few contexts to carry many readings. So the first word is folded and every word
# after it keeps what it was written with, which keeps the cue the language encodes and drops the
# convention it does not.
#
# Counts are taken from the second word on, since the first word's key is folded by construction and
# would otherwise be compared against itself.
#
# What this cannot see: a treebank records the reading a word had where it appeared, not every reading it
# could have. Each language is compared only against its own null here, which that limit does not reach.

import io
import math
import os
import random
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

DRAWS = 5
SEED = 0x4A21

# Readings per word climb with corpus size, and these corpora run from 20 thousand tokens to 1.2
# million. Every language is cut to the same count so the numbers can be set beside each other.
CAP = 60000

WHAT_IT_IS = {
    "german": "Germanic, every noun",
    "english": "Germanic, names only",
    "dutch": "Germanic, names only",
    "danish": "Germanic, names only",
    "swedish": "Germanic, names only",
    "icelandic": "Germanic, names, four cases",
    "polish": "Slavic, names only",
    "russian": "Slavic, names only",
    "croatian": "Slavic, names only",
    "slovak": "Slavic, names only",
    "ukrainian": "Slavic, names only",
    "finnish": "Uralic, names only",
    "estonian": "Uralic, names only",
    "hungarian": "Uralic, names only",
    "turkish": "Turkic, names only",
    "latvian": "Baltic, names only",
    "romanian": "Romance, names only",
    "spanish": "Romance, names only",
    "vietnamese": "Austroasiatic, names only",
}


def load(path):
    """Every sentence as its words in order, each folded, as written, and with its reading."""
    sentences = []
    building = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            trimmed = line.rstrip("\n")
            if not trimmed.strip():
                if building:
                    sentences.append(building)
                    building = []
                continue
            if not trimmed[0].isdigit():
                continue
            parts = trimmed.split("\t")
            if len(parts) < 6 or ("-" in parts[0]) or ("." in parts[0]):
                continue
            written = parts[1]
            reading = "%s|%s|%s" % (parts[2].lower(), parts[3], parts[5])
            building.append((written.lower(), written, reading))
    if building:
        sentences.append(building)
    return sentences


def keyed_folded(sentences):
    """One key per word with letter case thrown away everywhere."""
    return [[(folded, reading) for folded, written, reading in sentence]
            for sentence in sentences]


def keyed_written(sentences):
    """The first word of a sentence folded, every word after it kept as written."""
    keyed = []
    for sentence in sentences:
        row = []
        for place, entry in enumerate(sentence):
            folded, written, reading = entry
            row.append((folded if place == 0 else written, reading))
        keyed.append(row)
    return keyed


def keyed_null(sentences, rng):
    """The same keys in the same numbers, dealt out at random within each folded word."""
    pool = {}
    for sentence in sentences:
        for place, entry in enumerate(sentence):
            folded, written, reading = entry
            pool.setdefault(folded, []).append(folded if place == 0 else written)
    for folded in pool:
        rng.shuffle(pool[folded])

    reached = {folded: 0 for folded in pool}
    keyed = []
    for sentence in sentences:
        row = []
        for entry in sentence:
            folded = entry[0]
            index = reached[folded]
            reached[folded] = index + 1
            row.append((pool[folded][index], entry[2]))
        keyed.append(row)
    return keyed


def capped(sentences, limit):
    """The leading whole sentences whose words come to at most a given count."""
    kept = []
    total = 0
    for sentence in sentences:
        if total + len(sentence) > limit:
            break
        kept.append(sentence)
        total += len(sentence)
    return kept, total


def readings_per_word(keyed, from_place):
    """Readings per word, with the lexicon taken from every word and the average from a place on."""
    seen = {}
    for sentence in keyed:
        for key, reading in sentence:
            seen.setdefault(key, set()).add(reading)
    marks = [len(seen[key]) for sentence in keyed for key, _ in sentence[from_place:]]
    return (statistics.fmean(marks) if marks else float("nan")), len(seen)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    rng = random.Random(SEED)

    rows = []
    short = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("ud_") and name.endswith(".conllu")):
            continue
        language = name[3:-7]
        sentences, used = capped(load(os.path.join(CORPORA, name)), CAP)
        if used < 5000:
            continue
        if used < CAP:
            short.append((language, used))

        folded, folded_keys = readings_per_word(keyed_folded(sentences), 1)
        written, written_keys = readings_per_word(keyed_written(sentences), 1)

        nulls = []
        for _ in range(DRAWS):
            value, _ = readings_per_word(keyed_null(sentences, rng), 1)
            nulls.append(value)
        null = statistics.fmean(nulls)
        scatter = statistics.pstdev(nulls) if len(nulls) > 1 else 0.0

        rows.append((language, folded_keys, written_keys, folded, written, null, scatter))

    rows.sort(key=lambda row: row[4] - row[5])

    out.write("  %-12s %-9s %-9s %-9s %-9s %-9s %s\n"
              % ("language", "keys up", "folded", "written", "null", "spread", "what survives"))
    for language, folded_keys, written_keys, folded, written, null, scatter in rows:
        grew = 100.0 * (written_keys - folded_keys) / float(folded_keys)
        beats = null - written
        out.write("  %-12s %-9.1f %-9.4f %-9.4f %-9.4f %-9.4f %+.4f\n"
                  % (language, grew, folded, written, null, scatter, beats))

    out.write("\n  keys up is how much bigger the vocabulary gets when case is kept\n")
    out.write("  folded, written and null are readings per word from the second word on\n")
    out.write("  spread is the scatter across %d draws of the null\n" % DRAWS)
    out.write("  what survives is the null minus the written count, negative where\n")
    out.write("  keeping the capitals bought nothing a random split would not\n")

    out.write("\n  every corpus cut to %d tokens, on whole sentences\n" % CAP)
    for language, used in sorted(short):
        out.write("  %s holds only %d and is under-sampled against the rest\n" % (language, used))

    out.write("\n  the null moves by almost nothing across draws, so a count of its scatter\n")
    out.write("  measures how steady the null is and is not the size of the effect. What\n")
    out.write("  the branch is worth is the survival, against the keys it costs to take it\n")
    out.write("\n  %-12s %-26s %s\n" % ("language", "what it capitalizes", "what the branch is worth"))
    for language, folded_keys, written_keys, folded, written, null, scatter in rows:
        beats = null - written
        grew = 100.0 * (written_keys - folded_keys) / float(folded_keys)
        worth = (beats / grew) if grew else float("nan")
        if beats <= 0.0:
            verdict = "nothing a random split would not have bought"
        else:
            verdict = "%.4f for %.1f%% more keys, %.4f per percent" % (beats, grew, worth)
        out.write("  %-12s %-26s %s\n" % (language, WHAT_IT_IS.get(language, ""), verdict))

    manifest = os.path.join(ROOT, "build", "case_branch.csv")
    with open(manifest, "w", encoding="utf-8", newline="") as handle:
        handle.write("language,family,keys_up,folded,written,null,survival\n")
        for language, folded_keys, written_keys, folded, written, null, scatter in rows:
            grew = 100.0 * (written_keys - folded_keys) / float(folded_keys)
            handle.write("%s,%s,%.4f,%.4f,%.4f,%.4f,%.4f\n"
                         % (language, WHAT_IT_IS.get(language, "").split(",")[0],
                            grew, folded, written, null, null - written))
    out.write("\n  written to %s\n" % manifest)

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
