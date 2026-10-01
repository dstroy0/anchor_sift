#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How a glottalized resonant fares under reduplication, language by language, measured on the oracle
# forms and set against the survey that asked.
#
#   Usage:  python maint/data/salishan/experiments/reduplication_glottalization.py [ORACLES] [with-survey]
#
# Mellesmoen and Urbanczyk (2021, "Some Remarks on the Distribution and Representation of Glottalized
# Resonants in Salish", ICSNL 56, pp. 244-270, read in full from the corpus copy) classify each Salish
# language in their Table 4 by what reduplication does to a glottalized resonant: both copies
# glottalized (their Glottalized + Glottalized), or one copy plain (their Plain + Glottalized), with
# Upriver Halkomelem having no glottalized resonants and five languages left Unclear: Pentlatch,
# Sechelt, Upper Chehalis, Cowlitz and Bella Coola. They write that "the blanks in the charts can serve
# as a guide for further research".
#
# What is counted. Every form row of a Salish language is read as segments, a glottalized resonant
# being m, n, l, w, y or r carrying a comma above or followed by an apostrophe. A form is taken as
# doubled when its consonant skeleton, with glottalization set aside, holds some pair of consonants
# twice in a row (qən̓qən̓, həlhíləm), the shape of CVC reduplication. Where a resonant of that pair is
# glottalized in either copy, the pair is scored IDENTICAL (glottalized in both copies) or SPLIT
# (glottalized in one). Each doubled consonant pair is counted once per language, however many words
# carry it, and a footnote number stuck to a word's end is taken off first. The skeleton test also
# catches a root that repeats a consonant pair without being reduplicated. The known languages are
# scored first, and the test is trusted for the Unclear ones only if it sorts those.
#
# The survey's own two papers are left out of the count unless the run is given "with-survey". The
# agreement with Table 4 is then not the survey agreeing with itself.

import collections
import re
import sys
import unicodedata

import corpus_rows

RESONANTS = set("mnlwyr")
GLOTTAL_MARKS = {"̓", "̕", "'", "’", "ʼ"}
STRESS_AND_LENGTH = {"́", "̀", "ː", "·", ":"}
VOWELS = set("aeiouəɛɩʌɔæɪʊ")
SURVEY = {"ICSNL56_Mellesmoen_Urbanczyk_final", "ICSNL59_Mellesmoen_Urbanczyk_final"}

# Table 4, by the names corpus_rows folds to. Halkomelem and Northern Straits fold dialects the table
# splits (Musqueam both, Island Halkomelem plain; Samish and Saanich identical, Songish plain). Both
# folded languages are expected to show both.
TABLE_4 = {
    "St’át’imcets": "IDENTICAL", "Nɬeʔkepmxcín": "IDENTICAL", "Coeur d’Alene": "IDENTICAL",
    "Nsyilxcən": "IDENTICAL", "Montana Salish": "IDENTICAL", "Columbian": "IDENTICAL", "Nooksack": "IDENTICAL",
    "Klallam": "IDENTICAL", "Lushootseed": "IDENTICAL",
    "Secwepemctsín": "SPLIT", "ʔayʔaǰuθəm": "SPLIT", "Squamish": "SPLIT", "Twana": "SPLIT",
    "Halkomelem": "BOTH", "Northern Straits": "BOTH",
    "Pentlatch": "UNCLEAR", "Sechelt": "UNCLEAR", "Upper Chehalis": "UNCLEAR", "Cowlitz": "UNCLEAR",
    "Nuxalk": "UNCLEAR",
}


def segments(form):
    """(letter, glottalized) for each consonant and vowel, stress and length removed."""
    out = []
    for char in unicodedata.normalize("NFD", form.casefold()):
        if char in STRESS_AND_LENGTH:
            continue
        if char in GLOTTAL_MARKS:
            if out and out[-1][0] in RESONANTS:
                out[-1] = (out[-1][0], True)
            continue
        if unicodedata.combining(char) or char == "ʷ":
            if out:
                out[-1] = (out[-1][0] + char, out[-1][1])
            continue
        if char.isalpha() or char in "ʔʕ7":
            out.append((char, False))
    return out


def doubled(form):
    """The doubled consonant pair and each glottalized-resonant comparison it offers, or (None, [])."""
    consonants = [one for one in segments(form) if one[0][0] not in VOWELS]
    for start in range(len(consonants) - 3):
        first, second = consonants[start:start + 2], consonants[start + 2:start + 4]
        if [one[0] for one in first] != [one[0] for one in second]:
            continue
        found = []
        for left, right in zip(first, second):
            if left[0] in RESONANTS and (left[1] or right[1]):
                found.append("IDENTICAL" if left[1] and right[1] else "SPLIT")
        if found:
            return "".join(one[0] for one in first), found
    return None, []


def word_key(word):
    """A word with boundaries removed and a footnote number stuck to its end taken off."""
    word = re.sub(r"[^\ẁ-ͯ'’ʼʔʕ~\-=]", "", word)
    word = re.sub(r"(?<=[^\d])(\d{2,}|[0-68-9])$", "", word)
    return re.sub(r"[-=~]", "", word)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    given = next((one for one in sys.argv[1:] if one not in ("with-survey",)), None)
    keep_survey = "with-survey" in sys.argv[1:]
    counts = collections.defaultdict(collections.Counter)
    seen = collections.defaultdict(set)
    papers = collections.defaultdict(set)
    for row in corpus_rows.rows(given):
        if row.kind not in corpus_rows.FORM_KINDS or row.branch not in ("CS", "NIS", "SIS", "NUX", "TS", "TI"):
            continue
        if row.stem in SURVEY and not keep_survey:
            continue
        for word in row.form.split():
            key = word_key(word)
            pair, verdicts = doubled(key) if key else (None, [])
            # One doubled root is counted once per language however many words carry it.
            if not verdicts or (pair, tuple(verdicts)) in seen[row.language]:
                continue
            seen[row.language].add((pair, tuple(verdicts)))
            papers[row.language].add(row.stem)
            for verdict in verdicts:
                counts[row.language][verdict] += 1
    print("%-18s %-9s %9s %6s %7s %6s  %s" % ("language", "Table 4", "IDENTICAL", "SPLIT", "share", "papers", "reading"))
    for language in sorted(counts, key=lambda one: (TABLE_4.get(one, "~"), one)):
        identical, split = counts[language]["IDENTICAL"], counts[language]["SPLIT"]
        total = identical + split
        share = identical / total
        reading = "IDENTICAL" if share >= 0.75 else "SPLIT" if share <= 0.25 else "BOTH"
        expected = TABLE_4.get(language, "-")
        verdict = "" if expected in ("-", "UNCLEAR") else ("agrees" if reading == expected else "DISAGREES")
        print("%-18s %-9s %9d %6d %7.2f %6d  %-9s %s" % (language, expected, identical, split, share,
                                                        len(papers[language]), reading, verdict))


if __name__ == "__main__":
    main()
