#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How much of Nuxalk's reputation for words without vowels comes from how the words are written.
#
#   Usage:  python maint/data/salishan/experiments/vowelless_words.py [ORACLES]
#
# David D. Robertson, commenting on Victor Mair's Language Log post "Words without vowels"
# (2 March 2020, read at languagelog.ldc.upenn.edu/nll/?p=46316), wrote that "any apparent
# preponderance of vowelless 'words' in Nuxalk derives in big part from the community writing
# system's choice of visually isolating several clitics from the words they inflect", and that
# Nuxalk has carried the pan-Salish reduction of unstressed vowels further, to zero where the
# phonotactics allow. The first part is a claim about spacing, the second about the lexicon, and the
# oracle forms can separate them.
#
# Measured per language, over tokens of multiword rows (transcription, running speech,
# segmentation) and over single-word rows (cited forms, roots):
#   running  - share of running-text tokens with no vowel letter,
#   short    - of those vowelless tokens, the share with two consonants or fewer, the size of a clitic,
#   joined   - the running share after every vowelless token of two consonants or fewer is written
#              onto the token before it, as the orthographies that attach enclitics would write it,
#   glossed  - in segmentation rows whose gloss aligns word for word, the vowelless share among tokens
#              the author glosses with a grammatical label only (capitals, numbers, stops), and among
#              tokens carrying an English word,
#   lexical  - share of single-word cited forms and roots with no vowel letter.
# Robertson's reading predicts that Nuxalk's running share falls far when the short tokens are joined,
# and that its vowelless tokens are mostly grammatical ones. His second clause predicts that Nuxalk's
# lexical share stays above the other languages' after that.

import collections
import re
import sys
import unicodedata

import corpus_rows

VOWELS = set("aeiouəɛɩʌɔæɪʊɑøyœ")
SALISH = ("CS", "NIS", "SIS", "NUX", "TS", "TI")


def letters(token):
    """The base letters of a token, marks and punctuation removed, 7 read as a consonant."""
    base = "".join(char for char in unicodedata.normalize("NFD", token.casefold())
                   if not unicodedata.combining(char))
    return [char for char in base if char.isalpha() or char in "ʔʕ7"]


def vowelless(token):
    found = letters(token)
    # A y between consonants is a consonant in every orthography here; Nuxalk and the Americanist
    # transcriptions have no front rounded vowel it could stand for.
    return bool(found) and not any(char in VOWELS - {"y"} for char in found)


def short(token):
    return len(letters(token)) <= 2


def tokens(form):
    return [one for one in re.split(r"[\s]+", form) if letters(one)]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    everything = corpus_rows.rows(sys.argv[1] if len(sys.argv) > 1 else None)
    running = collections.defaultdict(lambda: [0, 0, 0])
    joined = collections.defaultdict(lambda: [0, 0])
    lexical = collections.defaultdict(lambda: [0, 0])
    for row in everything:
        if row.branch not in SALISH:
            continue
        if row.kind in ("transcription", "running speech", "segmentation"):
            found = tokens(row.form)
            if len(found) < 2:
                continue
            for token in found:
                running[row.language][0] += 1
                if vowelless(token):
                    running[row.language][1] += 1
                    running[row.language][2] += short(token)
            merged = []
            for token in found:
                if merged and vowelless(token) and short(token):
                    merged[-1] += token
                else:
                    merged.append(token)
            joined[row.language][0] += len(merged)
            joined[row.language][1] += sum(1 for one in merged if vowelless(one))
        elif row.kind in ("cited form", "root") and len(tokens(row.form)) == 1:
            lexical[row.language][0] += 1
            lexical[row.language][1] += vowelless(row.form)
    glossed = collections.defaultdict(lambda: [0, 0, 0, 0])
    for segmentation, gloss in corpus_rows.glossed_pairs(everything):
        if segmentation.branch not in SALISH:
            continue
        words, labels = segmentation.form.split(), gloss.form.split()
        if len(words) != len(labels):
            continue
        for word, label in zip(words, labels):
            if not letters(word):
                continue
            grammatical = not re.search(r"[a-z]{2,}", label)
            slot = 0 if grammatical else 2
            glossed[segmentation.language][slot] += 1
            glossed[segmentation.language][slot + 1] += vowelless(word)
    print("%-18s %7s %8s %6s %7s %13s %13s %7s %8s" % ("language", "tokens", "running", "short", "joined",
                                                        "gram. tokens", "word tokens", "lexical", "(forms)"))
    for language in sorted(running, key=lambda one: -running[one][0]):
        total, empty, small = running[language]
        if total < 150:
            continue
        grammar = glossed[language]
        print("%-18s %7d %8.3f %6.2f %7.3f %6d %5.3f %6d %5.3f %7.3f %8d" % (
            language, total, empty / total, small / empty if empty else 0.0,
            joined[language][1] / joined[language][0],
            grammar[0], grammar[1] / grammar[0] if grammar[0] else 0.0,
            grammar[2], grammar[3] / grammar[2] if grammar[2] else 0.0,
            lexical[language][1] / lexical[language][0] if lexical[language][0] else 0.0, lexical[language][0]))
    print("\nNuxalk rows by paper (running tokens, vowelless share):")
    by_paper = collections.defaultdict(lambda: [0, 0])
    for row in everything:
        if row.language == "Nuxalk" and row.kind in ("transcription", "running speech", "segmentation"):
            for token in tokens(row.form):
                by_paper[row.stem][0] += 1
                by_paper[row.stem][1] += vowelless(token)
    for stem, (total, empty) in sorted(by_paper.items()):
        print("   %-34s %5d %6.3f" % (stem, total, empty / total))


if __name__ == "__main__":
    main()
