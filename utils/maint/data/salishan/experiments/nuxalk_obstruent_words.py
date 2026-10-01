#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Nuxalk words made only of obstruents: how many in the lexicon, how often in speech, and how much
# of either is spacing.
#
#   Usage:  python maint/data/salishan/experiments/nuxalk_obstruent_words.py [ORACLES]
#
# Three sources frame this, all read in full from the corpus copies except the blog comment:
#   Mellesmoen (2021, "Syllables and Reduplication in Bella Coola (Nuxalk)", ICSNL 56) counts
#     OBSTRUENT-ONLY words, free words with no vowel and no sonorant, at 51 of 1506 FirstVoices
#     entries, "under 4%", and finds a single one made only of stops, tp 'spotted'. She sets aside
#     roots cited bound or starred, and words written without a vowel whose sonorant carries one.
#   Nater (2024, "Voiceless Words in Bella Coola: Fact vs. Fiction", ICSNL 59) lists 127 voiceless
#     words and roots from his 1990 dictionary, 30 of them stops and affricates only, and holds that
#     the language is non-syllabic.
#   Robertson (Language Log comment, 2 March 2020, on Victor Mair's "Words without vowels") holds
#     that the apparent preponderance of vowelless words "derives in big part from the community
#     writing system's choice of visually isolating several clitics".
#
# The two disputants' own papers are left out of every count here, since each lists words to make
# its case. What remains is Nuxalk in Americanist transcription: Nater's comparative list (2013,
# "How Salish is Bella Coola?"), his two oral texts (the Bella Coola tale in the ICSNL 50 volume and
# "An Oral Tradition from Sackʷ", ICSNL 59), his enclisis and loanword papers, Mellesmoen's 2025
# paper, and Elmendorf 1967. All but the last two are Nater's transcriptions, which do not write a
# predictable schwa; Mellesmoen's definition already sets those words aside by their sonorants.
#
# Classes follow Mellesmoen's: a vowel is a, e, i, o, u or ə in any accent; a sonorant is m, n, l, y,
# w, syllabic or not; everything else lettered is an obstruent, ʔ included. Stops are p, t, k, q with
# their ejectives and rounding; c and ƛ are affricates, which Mellesmoen keeps apart from stops and
# Nater counts with them.
#
# Robertson's claim is tested on the texts themselves. Nater writes a clitic group as one token,
# joined with ˽ (ti˽ƛ’χʷcaytχʷ). Each text is counted twice: as written, and with every joiner opened
# into a space the way an orthography that isolates clitics would print it.

import collections
import re
import sys
import unicodedata

import corpus_rows

DISPUTANTS = {"ICSNL56_Mellesmoen_final", "ICSNL59_Nater_2_final"}
TEXTS = {"22-Nater-Bella-Coola-tale-10", "ICSNL59_Nater_1_final"}
VOWELS = set("aeiouəɛɪʊ")
SONORANTS = set("mnlyw")
STOPS = set("ptkq")
AFFRICATES = set("cƛ")


# The two texts join a clitic to its host with different marks: ˽ (U+02FD) in the ICSNL 50 tale and
# ˬ (U+02EC) in the ICSNL 59 text, which also writes the glottal stop as ՚ (U+055A).
JOINERS = ("˽", "ˬ")


def letters(token):
    base = "".join(char for char in unicodedata.normalize("NFD", token.casefold()) if not unicodedata.combining(char))
    base = base.replace("՚", "ʔ")
    return [char for char in base if char.isalpha() or char in "ʔʕ"]


def kind(token):
    """VOWEL, SONORANT (no vowel, has a sonorant), STOPS, STOPS+AFFRICATES or OBSTRUENT, or None."""
    found = letters(token)
    if not found:
        return None
    if any(char in VOWELS for char in found):
        return "VOWEL"
    if any(char in SONORANTS for char in found):
        return "SONORANT"
    if all(char in STOPS or char == "ʔ" for char in found):
        return "STOPS"
    if all(char in STOPS or char in AFFRICATES or char == "ʔ" for char in found):
        return "STOPS+AFFRICATES"
    return "OBSTRUENT"


OBSTRUENT_ONLY = ("STOPS", "STOPS+AFFRICATES", "OBSTRUENT")


def free_word(form):
    """A cited form that is a free word: not starred, not a root, not an affix or clitic, one token."""
    form = form.strip()
    if not form or " " in form or re.search(r"[*√/<>~ˬ˽…]", form) or re.match(r"^[-=]|[-=]$", form):
        return None
    return re.sub(r"[-=]", "", form)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    everything = corpus_rows.rows(sys.argv[1] if len(sys.argv) > 1 else None)
    nuxalk = [row for row in everything if row.language == "Nuxalk" and row.stem not in DISPUTANTS]

    print("Running text, tokens by class (Nater's two oral texts):")
    for stem in sorted(TEXTS) + ["both"]:
        for spacing in ("as written, clitics joined", "clitics opened into their own tokens"):
            counts = collections.Counter()
            for row in nuxalk:
                if row.stem not in TEXTS or (stem != "both" and row.stem != stem):
                    continue
                if row.kind not in ("transcription", "running speech", "segmentation"):
                    continue
                text = row.form
                if not spacing.startswith("as written"):
                    for joiner in JOINERS:
                        text = text.replace(joiner, " ")
                for token in text.split():
                    found = kind(re.sub(r"[-=:.]", "", token))
                    if found:
                        counts[found] += 1
            total = sum(counts.values())
            obstruent = sum(counts[one] for one in OBSTRUENT_ONLY)
            print("   %-28s %-38s %5d tokens, obstruent-only %4d (%.3f), stops only %d, sonorant, no vowel %d"
                  % (stem[:28], spacing, total, obstruent, obstruent / total, counts["STOPS"], counts["SONORANT"]))

    print("\nFree words by source, distinct forms (obstruent-only share by Mellesmoen's definition):")
    types = collections.defaultdict(dict)
    for row in nuxalk:
        if row.kind != "cited form":
            continue
        word = free_word(row.form)
        if word and kind(word):
            types[row.stem][word] = kind(word)
    pooled = {}
    for stem, words in sorted(types.items(), key=lambda item: -len(item[1])):
        counts = collections.Counter(words.values())
        obstruent = sum(counts[one] for one in OBSTRUENT_ONLY)
        print("   %-34s %5d words, obstruent-only %4d (%.3f), stops only %d, stops+affricates %d"
              % (stem, len(words), obstruent, obstruent / len(words), counts["STOPS"], counts["STOPS+AFFRICATES"]))
        for word, found in words.items():
            pooled.setdefault(word, found)
    counts = collections.Counter(pooled.values())
    obstruent = sum(counts[one] for one in OBSTRUENT_ONLY)
    print("   %-34s %5d words, obstruent-only %4d (%.3f), stops only %d, stops+affricates %d"
          % ("pooled, distinct", len(pooled), obstruent, obstruent / len(pooled), counts["STOPS"],
             counts["STOPS+AFFRICATES"]))
    print("   free words of stops only, outside both disputants' papers: %s"
          % " ".join(sorted(word for word, found in pooled.items() if found == "STOPS")))


if __name__ == "__main__":
    main()
