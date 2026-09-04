#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Check the web of an alphabet against the accepted family tree, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/language_tree.py
#
# Holding each text out and assigning it to the nearest language put 52.8 percent home over 31 languages,
# and every common mistake was between languages that are actually related: the two Scandinavian
# standards for each other, Polish and Czech, Serbian and Slovenian, Chinese and Japanese, and Esperanto
# for the first language of the man who built it. If that is real then the distances between these squares
# are not noise, and grouping the languages by them should return the families that philology already
# established from shared roots.
#
# That is a check against an answer this work did not produce and cannot influence, which is what almost
# every other measurement here has lacked. Classifying languages from character statistics is old ground,
# and grouping them from linguistic data is a field of its own, so nothing below is offered as new. What
# it is good for is telling whether this particular square measures a language or measures an artifact,
# and a wrong instrument cannot reproduce a tree it was never shown.
#
# The families are written down before the distances are computed so the grouping is scored and not
# admired afterward.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_alphabet import CAP, LEAST, SKIP, web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

RANKS = 64

# Written down from philology before anything here is measured
FAMILY = {
    "danish": "germanic", "norwegian": "germanic", "swedish": "germanic",
    "icelandic": "germanic", "dutch": "germanic", "german": "germanic",
    "afrikaans": "germanic",
    "french": "romance", "italian": "romance", "spanish": "romance",
    "portuguese": "romance", "catalan": "romance", "romanian": "romance",
    "polish": "slavic", "czech": "slavic", "russian": "slavic",
    "serbian": "slavic", "slovenian": "slavic",
    "finnish": "uralic", "hungarian": "uralic",
    "welsh": "celtic", "irish": "celtic",
    "greek": "hellenic", "hebrew": "semitic", "persian": "iranian",
    "japanese": "japonic", "chinese": "sinitic", "tagalog": "austronesian",
    "vietnamese": "austroasiatic", "urdu": "indic", "hindi": "indic",
    "esperanto": "constructed",
}


def joined(distances, names, groups):
    """Average linkage, joining the two nearest groups until one is left."""
    steps = []
    live = {name: [name] for name in names}
    while len(live) > 1:
        best = None
        pair = None
        for left in live:
            for right in live:
                if left >= right:
                    continue
                total = 0.0
                for one in live[left]:
                    for two in live[right]:
                        total += distances[names.index(one)][names.index(two)]
                spread = total / (len(live[left]) * len(live[right]))
                if (best is None) or (spread < best):
                    best = spread
                    pair = (left, right)
        left, right = pair
        steps.append((best, live[left] + live[right]))
        live[left] = live[left] + live[right]
        del live[right]
    return steps


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    holding = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("lang_") and name.endswith(".txt")):
            continue
        if name[:-4] in SKIP:
            continue
        language = name[5:].rsplit("_", 1)[0]
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue
        values = web(text, RANKS)
        if values is not None:
            holding.setdefault(language, []).append(values)

    names = sorted(language for language in holding if len(holding[language]) >= 2)
    if len(names) < 8:
        out.write("  too few languages with two texts each\n")
        out.flush()
        return 0

    middles = {name: numpy.mean(numpy.stack(holding[name]), axis=0) for name in names}
    distances = [[float(numpy.linalg.norm(middles[left] - middles[right])) for right in names]
                 for left in names]

    out.write("  nearest other language, for each of %d\n\n" % len(names))
    out.write("  %-14s %-14s %-10s %s\n" % ("language", "nearest", "family", "same family"))
    agreed = 0
    scored = 0
    for index, name in enumerate(names):
        order = sorted(range(len(names)), key=lambda other: distances[index][other])
        nearest = names[order[1]]
        here = FAMILY.get(name)
        there = FAMILY.get(nearest)
        if (here is not None) and (there is not None):
            scored += 1
            same = here == there
            agreed += 1 if same else 0
            # A family holding only one language here cannot have a neighbour in it, so it is marked
            alone = sum(1 for other in names if FAMILY.get(other) == here) < 2
            out.write("  %-14s %-14s %-10s %s\n"
                      % (name, nearest, here,
                         "yes" if same else ("only one here" if alone else "no")))

    out.write("\n  %d of %d languages have their nearest neighbour inside their own family\n"
              % (agreed, scored))
    together = sum(1 for name in names
                   if sum(1 for other in names if FAMILY.get(other) == FAMILY.get(name)) >= 2)
    out.write("  %d of those had a family member present to be found\n" % together)

    out.write("\n  the first groupings made, closest pair first\n")
    for spread, members in joined(distances, names, None)[:12]:
        out.write("    %.5f  %s\n" % (spread, " ".join(sorted(members))))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
