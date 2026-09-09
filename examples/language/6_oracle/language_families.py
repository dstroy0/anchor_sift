#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: LNG-6-003
#
# Score the reading against a family tree this work did not produce and cannot influence.
#
#   Usage:  python examples/language/6_oracle/language_families.py
#
# Holding each text out and assigning it to the nearest language puts about half of them home over
# 31 languages, and the common mistakes are between languages that are actually related. If that is
# real, the distances are not noise and grouping the languages by them should return the families
# philology already established from shared roots.
#
# What that agreement is worth, stated before the numbers. A family tree is a reconstruction argued
# from cognates and sound correspondences, so this is agreement with a scholarly consensus and not a
# check against a fact, and where the two disagree nothing here can say which is wrong. Published
# cell edges are the other kind. Those are an oracle. This is a strong prior.
#
# The alphabet is removed as a second arm, since a milder version of that test once moved fourteen
# of twenty languages to a different nearest neighbor and was read as the family signal being
# spelling. Stripping the alphabet entirely gives the same family rate, so the alphabet is worth
# nothing to the families and the earlier reading was an overclaim.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.clustering import agglomerate, as_brackets, cophenetic_correlation, separation  # noqa: E402
from measure.web import web  # noqa: E402
from oracle.language.families import every_family, score_against  # noqa: E402
from representation.text.corpus import load_language_texts  # noqa: E402
from representation.text.marks import latin_share, to_bare  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")
RANKS = 64
BARE_RANKS = 26


def averaged(rows):
    """One reading per language, averaged over its texts."""
    held = {}
    for language, _, values in rows:
        held.setdefault(language, []).append(values)
    return {name: numpy.mean(numpy.stack(values), axis=0)
            for name, values in held.items() if len(values) >= 2}


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(CORPORA):
        out.write("  no corpora at %s\n" % CORPORA)
        out.flush()
        return 1

    loaded = load_language_texts(CORPORA)
    if len(loaded) < 8:
        out.write("  only %d texts are long enough\n" % len(loaded))
        out.flush()
        return 1

    families = every_family()
    out.write("  %d texts over %d languages\n\n"
              % (len(loaded), len({row[0] for row in loaded})))
    out.write("  %-34s %-9s %-14s %s\n" % ("reading", "letters", "found", "share"))

    readings = {}
    for label, ranks, prepare in (("every character it actually uses", RANKS, None),
                                  ("the same twenty six bare letters", BARE_RANKS, to_bare)):
        rows = []
        for language, name, text in loaded:
            if prepare is not None:
                if latin_share(text) < 0.8:
                    continue
                text = prepare(text)
            values = web(text, ranks)
            if values is not None:
                rows.append((language, name, values))
        middles = averaged(rows)
        if len(middles) < 6:
            out.write("  %-34s %-9d %s\n" % (label, ranks, "too few languages held"))
            continue
        right, scored, misses = score_against(middles, families)
        readings[label] = (middles, misses)
        out.write("  %-34s %-9d %-14s %.1f percent\n"
                  % (label, ranks, "%d of %d" % (right, scored),
                     100.0 * right / scored if scored else 0.0))

    for label, (middles, misses) in readings.items():
        if not misses:
            continue
        out.write("\n  where %s goes wrong\n" % label)
        for name, nearest, family in misses[:8]:
            out.write("    %-14s went to %-14s which is %s\n" % (name, nearest, family))

    label = "every character it actually uses"
    if label in readings:
        middles = readings[label][0]
        names = sorted(middles)
        apart = {}
        for one in names:
            for two in names:
                apart[(one, two)] = separation(middles[one], middles[two])
        joins = agglomerate(names, apart)
        out.write("\n  the first groupings made, closest pair first\n")
        for height, left, right_group in joins[:10]:
            out.write("    %.5f  %s\n" % (height, " ".join(sorted(left + right_group))))
        out.write("\n  cophenetic correlation %.4f over %d languages\n"
                  % (cophenetic_correlation(joins, names, apart), len(names)))
        out.write("  a low value means the tree is imposing structure the distances do not carry\n")
        out.write("\n  %s\n" % as_brackets(joins, names)[:200])

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
