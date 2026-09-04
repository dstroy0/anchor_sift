#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Check that a language corpus is in the language it claims, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/corpus_purity.py
#
# One of the four Greek texts is a Greek to English lexicon of the New Testament, so most of its
# characters are English and it has been standing in every Greek measurement in this work. Greek is also
# the language with the result nobody could explain, sitting nearest Hebrew across a change of script, and
# a quarter of its corpus not being Greek is a better explanation than any offered so far.
#
# That was found by reading the first line of a file, which is not a method. The same fault could sit in
# any of the others, and several of them cannot be printed to a console at all here, which is its own
# argument for checking them by measurement instead of by eye.
#
# So each text is scored by what share of its letters belong to the script its language is written in.
# A text well below its language's other texts is carrying something that is not that language: a
# translation, a glossary, a parallel text, or an editor's apparatus. Nothing is deleted here. The point
# is to know which numbers rest on what.

import io
import os
import statistics
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 200000

# Which block of letters each language is written in, by the name Unicode gives its characters
SCRIPTS = {
    "greek": "GREEK", "russian": "CYRILLIC", "serbian": "CYRILLIC", "hebrew": "HEBREW",
    "japanese": ("CJK", "HIRAGANA", "KATAKANA"), "chinese": "CJK",
    "urdu": "ARABIC", "persian": "ARABIC", "arabic": "ARABIC",
    "hindi": "DEVANAGARI", "bengali": "BENGALI", "tamil": "TAMIL", "korean": "HANGUL",
    "thai": "THAI",
}
DEFAULT = "LATIN"


def belongs(character, wanted):
    try:
        name = unicodedata.name(character)
    except ValueError:
        return False
    if isinstance(wanted, tuple):
        return any(name.startswith(one) for one in wanted)
    return name.startswith(wanted)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.endswith(".txt") and (name.startswith("lang_") or name.startswith("wiki_"))):
            continue
        stem = name[5:-4]
        language = stem.rsplit("_", 1)[0] if name.startswith("lang_") else stem.rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)

        wanted = SCRIPTS.get(language, DEFAULT)
        letters = [character for character in text if character.isalpha()]
        if len(letters) < 2000:
            continue
        share = sum(1 for character in letters if belongs(character, wanted)) / float(len(letters))
        latin = sum(1 for character in letters if belongs(character, "LATIN")) / float(len(letters))
        rows.append((language, name[:-4], share, latin, len(letters)))

    out.write("  %-14s %-26s %-11s %-11s %s\n"
              % ("language", "text", "own script", "latin", "verdict"))
    flagged = 0
    for language in sorted({row[0] for row in rows}):
        group = [row for row in rows if row[0] == language]
        middle = statistics.median(row[2] for row in group)
        for _, label, share, latin, letters in sorted(group):
            # Judged against the other texts of the same language, since every language has its own
            # ordinary level of foreign matter from names, citations and an editor's notes
            odd = (share < (middle - 0.15)) or (share < 0.5)
            flagged += 1 if odd else 0
            out.write("  %-14s %-26s %-11.3f %-11.3f %s\n"
                      % (language, label, share, latin,
                         "not mostly its own script" if odd else ""))

    out.write("\n  %d of %d texts are out of line with the rest of their language\n"
              % (flagged, len(rows)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
