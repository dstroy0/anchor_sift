#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-4-003
#
# Doping counted in the whole cell instead of the asymmetric unit, reported by mineral family.
#
#   Usage:  python examples/crystallography/4_measure/doping_after_symmetry_expansion.py [entries]
#
# WHAT THE EXPANSION BUYS, STATED BEFORE THE NUMBER THAT LOOKS BIGGER
#
# A CIF lists the asymmetric unit and the operations that generate the rest of the cell.
# doping_from_shared_sites.py reads the asymmetric unit alone. This reads the cell.
#
# The count rises steeply and almost all of the rise is arithmetic. Over 2853 readable entries the
# shared positions go from 3424 to 20893, about six times as many, and nearly every added position
# is a symmetry copy of a site the asymmetric reading already found.
#
# Almost. Two entries hold a shared position that exists only after expansion, and they are worth
# more than the ratio is.
#
#   1001125   Ta5+ at (1/2, 1/2, 0.238) and W6+ at (1/2, 1/2, -0.238). An operation taking z to -z
#             carries one onto the other. Tantalum and tungsten substitute readily, so this is an
#             ordinary solid solution that the asymmetric unit simply does not show.
#
#   1509166   O at (0, 1/2, 0) at full occupancy and Ag at (1/2, 0, 1/2) at half, in I 4/m m m. The
#             I centring carries the first exactly onto the second, so the deposit has put an anion
#             and a cation in one orbit summing to one and a half atoms on a site that holds one.
#             That is not chemistry, it is a defect in a published deposit, and nothing short of
#             expansion surfaces it.
#
# So expansion IS a detection, on 2 entries in 2853. It is a poor detector by rate and the right
# tool for the thing it finds, and a reading that only wants to know whether a mineral dopes still
# should not pay for it.
#
# THIS SECTION SAID ZERO UNTIL THE CORPUS GREW
#
# At 1228 entries the count was 0 and this file asserted that expansion never detects. At 2801 it
# was 5, and three of those five were an artefact: deposits that mark an undetermined position with
# the sentinel -1 and the flag `dum`, which reduces into the cell at the origin and collides with
# whatever real atom sits there. Mo and O sharing a site is chemically impossible and that is how
# the artefact announced itself. crystal.site_table now drops `dum` rows, and the two survivors
# above are the real answer.
#
# Both halves of that are worth keeping. A claim of zero held for 1228 entries and was false, and a
# count of five looked like a finding and was mostly a parser reading a placeholder as an atom.
#
# A THIRD HAS NO DECIMAL, WHICH IS WHY THIS NEEDED A NEW SCALE
#
# See representation/structure/symmetry.py. A translation of 1/3 is not a decimal at any number of
# places, so carrying an R centred operation through the decimal scale would displace every copy it
# generates. Coordinates here are integers in units of 1/(24 * 10**SCALE_DIGITS), and an operation
# whose denominator does not divide 24 raises rather than rounding. Over this corpus nothing raised:
# 24 held every operation the deposits published.
#
# WHAT A FAMILY IS HERE
#
# The family comes from families.tsv beside the cache, written by maint/data/fetch/fetch_cod_doped.py,
# and it records the search term an entry was fetched under. That is provenance and not chemistry.
# An entry the archive returned for "olivine" that is not an olivine is still filed under olivine,
# because that is what happened. Entries fetched before families were recorded carry none, and are
# counted separately rather than being guessed at.

import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation import exact  # noqa: E402
from representation.structure import crystal  # noqa: E402
from representation.structure import symmetry  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")
FAMILIES_FILE = os.path.join(CACHE, "families.tsv")

# Entries whose expansion is larger than this are read for their asymmetric unit only and counted
# apart. A cell with 192 operations over 400 sites is 76800 placements, and the cost is in the
# expansion rather than in the reading. Declared here as an input, not applied quietly: the count of
# entries it holds back is printed.
MOST_PLACEMENTS = 200000


def families():
    """Entry number to the family it was fetched under, from the sidecar beside the cache."""
    found = {}
    if not os.path.isfile(FAMILIES_FILE):
        return found
    with io.open(FAMILIES_FILE, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and parts[0]:
                found.setdefault(parts[0], parts[1])
    return found


def sites(text):
    """The deposit's atom sites as exact points, and how many coordinates would not parse."""
    points = []
    skipped = 0
    for along_a, along_b, along_c, element, _occupancy in crystal.site_table(text):
        try:
            points.append(((exact.scaled(along_a), exact.scaled(along_b), exact.scaled(along_c)),
                           element))
        except ValueError:
            skipped += 1
    return points, skipped


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(CACHE):
        out.write("\n  nothing cached under build/cod. Run a fetcher to fill it.\n\n")
        out.flush()
        return 1

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    names = sorted(name for name in os.listdir(CACHE) if name.endswith(".cif"))
    if limit:
        names = names[:limit]
    known = families()

    out.write("\n  Doping in the whole cell, by mineral family. Operations applied exactly.\n\n")

    read = 0
    with_ops = 0
    refused = 0
    held_back = 0
    skipped_sites = 0
    before_total = 0
    after_total = 0
    newly_doped = 0
    per_family = {}
    started = time.time()

    for name in names:
        with io.open(os.path.join(CACHE, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        points, skipped = sites(text)
        skipped_sites += skipped
        if not points:
            continue
        read += 1
        family = known.get(name[:-4], "unrecorded")
        row = per_family.setdefault(family, {"entries": 0, "doped": 0, "before": 0, "after": 0,
                                             "ops": 0})
        row["entries"] += 1

        try:
            ops = symmetry.operations(text)
        except symmetry.WillNotDivide:
            # Refused rather than rounded. The entry is counted and left out of the totals.
            refused += 1
            continue
        if len(ops) > 1:
            with_ops += 1
        row["ops"] += len(ops)

        before = len(exact.contested(points))
        row["before"] += before
        before_total += before

        if (len(points) * len(ops)) > MOST_PLACEMENTS:
            held_back += 1
            continue

        after = len(exact.contested(symmetry.expand(points, ops)))
        row["after"] += after
        after_total += after
        if after:
            row["doped"] += 1
        if before == 0 and after > 0:
            newly_doped += 1

    out.write("  %-16s %-9s %-8s %-11s %-11s %s\n"
              % ("family", "entries", "doped", "asymmetric", "whole cell", "mean ops"))
    for family, row in sorted(per_family.items(), key=lambda pair: -pair[1]["after"]):
        if not row["entries"]:
            continue
        out.write("  %-16s %-9d %-8d %-11d %-11d %.0f\n"
                  % (family[:16], row["entries"], row["doped"], row["before"], row["after"],
                     row["ops"] / row["entries"]))

    out.write("\n  %d entries read, %.0fs\n" % (read, time.time() - started))
    out.write("  publishing operations                    %d\n" % with_ops)
    out.write("  refused, a denominator not dividing %d   %d\n" % (symmetry.UNITS, refused))
    out.write("  held back, over %d placements        %d\n" % (MOST_PLACEMENTS, held_back))
    if skipped_sites:
        out.write("  sites skipped, coordinate not plain decimal text   %d\n" % skipped_sites)

    out.write("\n  shared positions, asymmetric unit only   %d\n" % before_total)
    out.write("  shared positions, whole cell             %d\n" % after_total)
    if before_total:
        out.write("  ratio                                    %.2fx\n"
                  % (after_total / float(before_total)))

    out.write("\n  entries with no shared site before expansion that have one after   %d\n"
              % newly_doped)
    out.write("     This is the number that makes expansion a detection rather than a count.\n")
    out.write("     Nearly every position the expansion adds is a symmetry copy of a site the\n")
    out.write("     asymmetric reading already found, and the few that are not are the whole\n")
    out.write("     reason to run it. See the header for the two in this corpus: one ordinary\n")
    out.write("     Ta for W solid solution, and one deposit putting an anion and a cation in\n")
    out.write("     the same orbit at a sum of one and a half atoms on a site that holds one.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
