#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Read the web with the content held fixed across every language, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/parallel_web.py
#
# Every earlier reading compared different books, so a difference between two languages was also a
# difference between an epic and a novel. One text translated into 43 languages removes that: the content
# is the same everywhere, so topic cannot help tell two languages apart and what the web finds is the
# language.
#
# Two things pull against each other here and both are stated because neither can be removed. Holding the
# content fixed takes away a cue the earlier test had, since different books in different languages could
# be told apart partly by being different books, so this is the harder test. Against that, one text per
# language has to be cut into pieces to have several samples, and pieces of one translation resemble each
# other more than separate books do, which makes it easier. The two do not cancel and the number below is
# not directly comparable to the earlier one.
#
# What is comparable is the shape of the answer: whether the languages that get confused are still the
# related ones, and whether the families still come out, with the content that could have been carrying
# them taken away.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from binary_web import as_codes, web_of_codes
from language_tree import FAMILY
from web_alphabet import leave_one_out, web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

PIECES = 4
CAP = 800000
LEAST = 60000
RANKS = 64
WIDTH = 5

# Families for the languages this corpus adds, written from philology before anything is measured
MORE = {
    "tamil": "dravidian", "malayalam": "dravidian", "telugu": "dravidian",
    "hindi": "indic", "marathi": "indic", "nepali": "indic", "gujarati": "indic",
    "bengali": "indic", "punjabi": "indic",
    "burmese": "tibeto-burman", "thai": "tai", "korean": "koreanic",
    "indonesian": "austronesian", "malay": "austronesian", "cebuano": "austronesian",
    "malagasy": "austronesian",
    "armenian": "armenian", "albanian": "albanian", "georgian": "kartvelian",
    "amharic": "semitic", "arabic": "semitic",
    "turkish": "turkic", "kazakh": "turkic",
    "latvian": "baltic", "lithuanian": "baltic",
    "estonian": "uralic", "ukrainian": "slavic", "swahili": "bantu",
    "vietnamese": "austroasiatic", "haitian": "creole",
}


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    families = dict(FAMILY)
    families.update(MORE)

    loaded = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("para_") and name.endswith(".txt")):
            continue
        language = name[5:-4]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < (PIECES * LEAST):
            continue
        step = len(text) // PIECES
        for piece in range(PIECES):
            loaded.append((language, "%s_%d" % (language, piece),
                           text[piece * step:(piece + 1) * step]))

    languages = sorted({row[0] for row in loaded})
    if len(languages) < 8:
        out.write("  too few languages\n")
        out.flush()
        return 0

    out.write("  %d pieces over %d languages of one text, so guessing gets %.1f percent\n\n"
              % (len(loaded), len(languages), 100.0 / len(languages)))
    out.write("  %-30s %-14s %s\n" % ("reading", "correct", "share"))

    trials = []
    rows = [(language, label, web(text, RANKS)) for language, label, text in loaded]
    rows = [row for row in rows if row[2] is not None]
    correct, total, confused = leave_one_out(rows)
    out.write("  %-30s %-14s %.1f percent\n"
              % ("characters by rank, top %d" % RANKS, "%d of %d" % (correct, total),
                 100.0 * correct / total))
    trials.append(("characters", rows, confused))

    coded = []
    for language, label, text in loaded:
        codes, width_of = as_codes(text, WIDTH)
        values = web_of_codes(codes, width_of)
        if values is not None:
            coded.append((language, label, values))
    correct, total, confused = leave_one_out(coded)
    out.write("  %-30s %-14s %.1f percent\n"
              % ("one binary alphabet, %d codes" % (1 << WIDTH), "%d of %d" % (correct, total),
                 100.0 * correct / total))
    trials.append(("binary", coded, confused))

    # Restricted to the languages the book corpus also holds, because that corpus covers 22 languages
    # and this one covers 33 across many more families, so a change in the result cannot otherwise be
    # told apart from the change in which languages are being asked about
    shared = set()
    for name in os.listdir(CORPORA):
        if name.startswith("lang_") and name.endswith(".txt"):
            shared.add(name[5:].rsplit("_", 1)[0])

    for label, rows, confused in trials:
        for limited in (False, True):
            report_families(out, rows, families, shared if limited else None, label)
    out.flush()
    return 0


def report_families(out, rows, families, only, label):
    """How many languages sit nearest a relative, over all of them or over a named few."""
    holding = {}
    for language, _, values in rows:
        if (only is None) or (language in only):
            holding.setdefault(language, []).append(values)
    names = sorted(holding)
    if len(names) < 6:
        return
    if True:
        middles = {name: numpy.mean(numpy.stack(holding[name]), axis=0) for name in names}

        agreed = 0
        scored = 0
        misplaced = []
        for name in names:
            here = families.get(name)
            if here is None:
                continue
            if sum(1 for other in names if families.get(other) == here) < 2:
                continue
            scored += 1
            nearest = min((float(numpy.linalg.norm(middles[name] - middles[other])), other)
                          for other in names if other != name)[1]
            if families.get(nearest) == here:
                agreed += 1
            else:
                misplaced.append((name, nearest, families.get(nearest, "unknown")))
        out.write("\n  the %s, over %s: %d of %d languages with a relative sit nearest one\n"
                  % (label, "the languages the books also hold" if only else "every language here",
                     agreed, scored))
        for name, nearest, family in misplaced[:6]:
            out.write("    %-14s went to %-14s which is %s\n" % (name, nearest, family))


if __name__ == "__main__":
    raise SystemExit(main())
