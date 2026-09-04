#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Run the family test with every language in the same twenty six letters, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/stripped_families.py
#
# Removing the few characters each language uses far more than the others moved fourteen of twenty
# languages to a different nearest neighbour, so most of what this reading calls naming a language is
# matching an alphabet. That test removed a handful of characters. This removes the alphabet.
#
# Every text is decomposed, every combining mark dropped, everything lowered, and everything outside the
# twenty six bare letters thrown away. Polish loses its slashed l, Hungarian its long double accents,
# Turkish its dotless i, Vietnamese all six tones. What remains is the same twenty six letters for every
# language, so no language holds a symbol another lacks and nothing can be named by its inventory.
#
# What survives is relatedness that does not depend on spelling. The earlier run says which pairings to
# expect: Romance held together with its characters gone, and Polish held with Slovenian, while most
# others moved. If the families still come out at anything like their earlier rate, the reading was seeing
# structure through the spelling. If they collapse to what those six pairs give, it was the spelling.
#
# This applies only to languages written in the Latin alphabet, so Greek, Russian, Hebrew, Arabic and the
# Indic and east Asian languages are not in it. Stripping them would mean transliterating them, which is a
# choice about sounds and would put back the judgement this test exists to remove.

import io
import os
import statistics
import sys
import unicodedata

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import load
from language_tree import FAMILY
from parallel_web import MORE
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SAME_LENGTH = 300000
RANKS = 26


def to_bare(text):
    """The text in the twenty six letters every Latin alphabet shares, and nothing else."""
    opened = unicodedata.normalize("NFD", text.lower())
    kept = []
    for symbol in opened:
        if unicodedata.category(symbol) == "Mn":
            continue
        if "a" <= symbol <= "z":
            kept.append(symbol)
        elif symbol.isspace():
            kept.append(" ")
    return " ".join("".join(kept).split())


def score(reading, families):
    names = sorted(reading)
    right = 0
    scored = 0
    misses = []
    for name in names:
        here = families.get(name)
        if (here is None) or (sum(1 for other in names if families.get(other) == here) < 2):
            continue
        scored += 1
        nearest = min((float(numpy.linalg.norm(reading[name] - reading[other])), other)
                      for other in names if other != name)[1]
        if families.get(nearest) == here:
            right += 1
        else:
            misses.append((name, nearest, families.get(nearest, "?")))
    return right, scored, misses


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    families = dict(FAMILY)
    families.update(MORE)

    plain = {}
    bare = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("para_") and name.endswith(".txt")):
            continue
        language = name[5:-4]
        text, _ = load(os.path.join(CORPORA, name), cap=SAME_LENGTH * 2, clean=True)
        if (text is None) or (len(text) < SAME_LENGTH):
            continue
        cut = text[:SAME_LENGTH]
        # Only where the language is written in this alphabet to begin with
        letters = sum(1 for symbol in cut if symbol.isalpha())
        latin = sum(1 for symbol in unicodedata.normalize("NFD", cut)
                    if "a" <= symbol.lower() <= "z")
        if (letters < 1000) or (latin / float(letters) < 0.8):
            continue
        stripped = to_bare(cut)
        if len(stripped) < SAME_LENGTH // 2:
            continue
        first = web(cut, 64)
        second = web(stripped, RANKS)
        if (first is not None) and (second is not None):
            plain[language] = first
            bare[language] = second

    if len(bare) < 8:
        out.write("  only %d languages written in this alphabet were held\n" % len(bare))
        out.flush()
        return 0

    out.write("  %d languages, all written in the Latin alphabet\n\n" % len(bare))
    out.write("  %-26s %-9s %-13s %s\n" % ("reading", "letters", "found", "share"))
    for label, reading, count in (("as written, every character", plain, 64),
                                  ("the same twenty six letters", bare, RANKS)):
        right, scored, misses = score(reading, families)
        if scored:
            out.write("  %-26s %-9d %-13s %.1f percent\n"
                      % (label, count, "%d of %d" % (right, scored), 100.0 * right / scored))

    right, scored, misses = score(bare, families)
    out.write("\n  which pairings survive losing the alphabet\n")
    names = sorted(bare)
    for name in names:
        here = families.get(name)
        if (here is None) or (sum(1 for other in names if families.get(other) == here) < 2):
            continue
        was = min((float(numpy.linalg.norm(plain[name] - plain[other])), other)
                  for other in names if other != name)[1]
        now = min((float(numpy.linalg.norm(bare[name] - bare[other])), other)
                  for other in names if other != name)[1]
        out.write("    %-14s %-14s %-14s %s\n"
                  % (name, was, now,
                     "held" if was == now else ("still its family" if families.get(now) == here
                                                else "")))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
