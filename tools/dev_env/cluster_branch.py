#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find out whether the case branch can be gated by a group or has to be gated by a table, for Section
# 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/case_or_splitting.py   (writes build/case_branch.csv)
#           python tools/dev_env/cluster_branch.py
#
# A branch worth taking in some languages and not others has to be gated on something, and there are two
# shapes the gate can take. A table carries one row per language and costs a lookup. A group test carries
# one row per group and costs less, and it only works if the languages actually fall into groups.
#
# So the question is whether they do. The languages are clustered on what the branch costs and what it
# buys, which are the two numbers the gate decides from, and on how much ambiguity was left for it to
# work on. Joining the two closest, then the two closest groups, until one remains gives a tree, and the
# cophenetic correlation says whether that tree represents the distances or was invented from them. A
# tree with a low cophenetic correlation means there are no groups to test and the gate has to be a table.
#
# The three numbers are put on the same footing first. Vocabulary growth runs to ten percent, what the
# branch buys runs to nine hundredths, and clustering them as they stand would let the larger number
# decide everything. Each is centered on its own average and divided by its own scatter.
#
# The family each language belongs to is checked separately and directly, because a family gate is the
# one that was proposed. If families were the groups, the spread inside a family would be small against
# the spread across all of them. That comparison needs no clustering and does not depend on the linkage.
#
# What this cannot see: nineteen languages is a small number to cluster, one join changes everything
# above it, and the heights are printed so a join that barely won is visible. Two of the corpora hold
# only twenty thousand tokens against sixty thousand for the rest, and their numbers carry that.

import io
import os
import statistics
import sys

from cluster_profiles import report

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(ROOT, "build", "case_branch.csv")


def read_manifest(path):
    """Every language with its family and the numbers the gate would decide from."""
    held = {}
    with open(path, encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").split(",")
        for line in handle:
            parts = line.rstrip("\n").split(",")
            if len(parts) != len(header):
                continue
            row = dict(zip(header, parts))
            held[row["language"]] = (row["family"],
                                     float(row["keys_up"]),
                                     float(row["folded"]),
                                     float(row["survival"]))
    return held


def standardized(held, names):
    """Each number centered on its own average and divided by its own scatter."""
    columns = []
    for index in (1, 2, 3):
        values = [held[name][index] for name in names]
        middle = statistics.fmean(values)
        scatter = statistics.pstdev(values)
        columns.append((middle, scatter if scatter else 1.0))
    made = {}
    for name in names:
        made[name] = [(held[name][index] - columns[place][0]) / columns[place][1]
                      for place, index in enumerate((1, 2, 3))]
    return made


def main():
    if not os.path.isfile(MANIFEST):
        print("run case_or_splitting.py first, it writes %s" % MANIFEST)
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    held = read_manifest(MANIFEST)
    names = sorted(held)

    out.write("  %-12s %-16s %-11s %-11s %s\n"
              % ("language", "family", "keys up", "left over", "what it buys"))
    for name in names:
        family, grew, folded, survival = held[name]
        out.write("  %-12s %-16s %-11.1f %-11.4f %.4f\n" % (name, family, grew, folded, survival))

    out.write("\n  is the family the group\n")
    families = {}
    for name in names:
        families.setdefault(held[name][0], []).append(name)
    everything = [held[name][3] for name in names]
    whole = max(everything) - min(everything)
    out.write("  %-16s %-7s %-11s %-11s %s\n"
              % ("family", "members", "lowest", "highest", "share of the whole spread"))
    for family in sorted(families, key=lambda key: -len(families[key])):
        members = families[family]
        if len(members) < 2:
            continue
        buys = [held[name][3] for name in members]
        inside = max(buys) - min(buys)
        out.write("  %-16s %-7d %-11.4f %-11.4f %.2f\n"
                  % (family, len(members), min(buys), max(buys), inside / whole))
    out.write("\n  a family that grouped the languages would take a small share of the\n")
    out.write("  whole spread. A share near one means the family holds both ends of it\n")

    made = standardized(held, names)
    report(out, "on what the branch costs, what was left over, and what it buys", made, names)

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
