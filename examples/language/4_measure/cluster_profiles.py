#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Group the languages by their positional ambiguity profile and check what the grouping recovers, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python examples/language/4_measure/cluster_profiles.py
#
# The positional measurement produced eight curves and they were read by eye. Reading eight curves by eye
# is where this work has gone wrong before: a curve that looks like its neighbor is an impression, and the
# impression survives until something counts it.
#
# Hierarchical agglomerative clustering counts it. The two closest languages join, then the two closest
# groups, until one group is left, and the distance at every join is kept. The order of the joins is the
# tree and the distances are its heights.
#
# Two matrices are built because there are two questions. Clustering the profiles as measured asks which
# languages carry ambiguity at the same level, and the answer to that is mostly already known from the
# per-word counts. Dividing each profile by its own average takes the level out and leaves the shape,
# which asks whether the first three places form a signature that is independent of how ambiguous the
# language is overall.
#
# Average linkage is used because it is standard for this and because it does not push toward equal-sized
# groups the way Ward's method does.
#
# The cophenetic correlation is reported beside each tree. A tree can be built from any distance matrix
# whatsoever and will look like a result, so the check compares the height at which each pair first landed
# in one group against the distance actually measured between them. A low value means the tree is
# imposing structure the distances do not carry, and the tree should then be read as an ordering and not
# as a grouping.
#
# Family and type are printed beside the trees, because a tree checked only against itself proves nothing.
#
# What this cannot see: eight languages is a small number to cluster and one merge changes the shape of
# everything above it. The heights are printed, which makes a merge that barely beat its alternative visible.

import io
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from measure.clustering import (agglomerate, as_brackets, cophenetic,  # noqa: E402
                                correlation, separation)
from oracle.language.typology import MORPHOLOGY, SUBFAMILY  # noqa: E402
from positional_ambiguity import CORPORA, PLACES, measure, read_sentences  # noqa: E402


def report(out, title, profiles, names):
    """One distance matrix, its tree, and the check on whether the tree represents it."""
    apart = {}
    for one in names:
        for two in names:
            apart[(one, two)] = separation(profiles[one], profiles[two])

    out.write("\n  %s\n" % title)
    out.write("  %-12s" % "")
    for name in names:
        out.write("%8s" % name[:7])
    out.write("\n")
    for one in names:
        out.write("  %-12s" % one)
        for two in names:
            out.write("%8.3f" % apart[(one, two)])
        out.write("\n")

    joins = agglomerate(names, apart)
    out.write("\n  %-9s %s\n" % ("height", "joined"))
    for height, left, right in joins:
        out.write("  %-9.4f (%s) with (%s)\n"
                  % (height, " ".join(left), " ".join(right)))

    out.write("\n  %s\n" % as_brackets(joins, names))

    heights = cophenetic(joins)
    measured = []
    implied = []
    for first in range(len(names)):
        for second in range(first + 1, len(names)):
            measured.append(apart[(names[first], names[second])])
            implied.append(heights[(names[first], names[second])])
    out.write("\n  cophenetic correlation %.4f, over %d pairs\n" % (
        correlation(measured, implied), len(measured)))
    return joins


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    level = {}
    shape = {}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("ud_") and name.endswith(".conllu")):
            continue
        language = name[3:-7]
        sentences = read_sentences(os.path.join(CORPORA, name))
        if sum(len(sentence) for sentence in sentences) < 5000:
            continue
        profile = measure(sentences)[2]
        level[language] = profile
        middle = statistics.fmean(profile)
        shape[language] = [value / middle for value in profile]

    names = sorted(level)
    out.write("  %-12s %-26s %-22s %s\n" % ("language", "family", "type", "profile"))
    for language in names:
        out.write("  %-12s %-26s %-22s %s\n"
                  % (language, SUBFAMILY.get(language, ""), MORPHOLOGY.get(language, ""),
                     " ".join("%.2f" % value for value in level[language])))

    report(out, "as measured, which groups by how ambiguous the language is", level, names)
    report(out, "each profile over its own average, which groups by shape alone", shape, names)

    out.write("\n  average linkage over %d places, %d languages\n" % (PLACES, len(names)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
