#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Score the family again with the untranslated English taken out, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/clean_dravidian.py
#
# Four explanations were offered for why the family came out inverted. The scripts were aligned and it
# moved nothing. The unit was changed to whole clusters and it got worse. The stop rows were folded to the
# distinctions Tamil keeps and it got worse again. Then the files were looked at.
#
# They are unevenly full of English. Telugu is 30.0 percent Latin characters and only 47.8 percent Telugu.
# Hindi is 14.8 percent Latin. Tamil is 2.1 and Marathi 1.8. These are subtitles from educational video
# and the untranslated parts sit in them in whatever amount each translator left. So Telugu's nearest
# neighbour was Bengali because a third of Telugu's file is not Telugu.
#
# There was a tool for this already, written earlier to catch a Greek to English lexicon standing in a
# Greek corpus, and it was not run on any of these. Three explanations were built and tested before the
# first check that should have been made.
#
# Here each file is cut down to its own script and the same three questions are asked again. What remains
# is the family or it is not, and this time the answer is about the languages.

import io
import os
import sys
import unicodedata

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dravidian_structure import DRAVIDIAN, INDO_ARYAN, RANKS
from phoneme_lexer import judge
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

READ = 3000000
SAME_LENGTH = 300000

OWN = {
    "tamil": "TAMIL", "malayalam": "MALAYALAM", "kannada": "KANNADA", "telugu": "TELUGU",
    "hindi": "DEVANAGARI", "marathi": "DEVANAGARI", "bengali": "BENGALI",
}


def keep_own(text, script):
    """The text with everything outside its own writing taken out, spaces kept as separators."""
    out = []
    for symbol in text:
        if symbol.isspace():
            out.append(" ")
            continue
        try:
            name = unicodedata.name(symbol)
        except ValueError:
            continue
        if name.startswith(script):
            out.append(symbol)
    # Runs of space left where foreign words were removed collapse to one
    return " ".join("".join(out).split())


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    dirty = {}
    clean = {}
    sizes = {}
    for language, script in sorted(OWN.items()):
        path = os.path.join(CORPORA, "drav_%s.txt" % language)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(READ)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        kept = keep_own(text, script)
        if (len(text) < SAME_LENGTH) or (len(kept) < SAME_LENGTH):
            out.write("  %-12s holds %d characters, %d of its own, and is left out\n"
                      % (language, len(text), len(kept)))
            continue
        sizes[language] = (len(set(text[:SAME_LENGTH])), len(set(kept[:SAME_LENGTH])))
        first = web(text[:SAME_LENGTH], RANKS)
        second = web(kept[:SAME_LENGTH], RANKS)
        if (first is not None) and (second is not None):
            dirty[language] = first
            clean[language] = second

    if len(clean) < 5:
        out.write("  too few languages held\n")
        out.flush()
        return 0

    out.write("  distinct symbols in %d characters, before and after\n" % SAME_LENGTH)
    out.write("  %-12s %-14s %s\n" % ("language", "as fetched", "own script only"))
    for language in sorted(sizes):
        out.write("  %-12s %-14d %d\n" % ((language,) + sizes[language]))

    names = sorted(clean)
    out.write("\n  %-12s %s\n" % ("", "  ".join("%-11s" % name[:11] for name in names)))
    for one in names:
        row = ["%-11.4f" % float(numpy.linalg.norm(clean[one] - clean[two])) for two in names]
        out.write("  %-12s %s\n" % (one, "  ".join(row)))

    judge(out, dirty, "as fetched, English and all")
    judge(out, clean, "cut to its own script")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
