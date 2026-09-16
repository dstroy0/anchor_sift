#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Count what the exact reading path admits out of the crystal cache, and what it refuses, before
# anything reports a number over it.
#
#   Usage:  python maint/analysis/survey/crystal_gate_census.py [--cache DIR] [--families FILE]
#
# WHY THIS EXISTS
#
# representation.structure.crystal.exact_points returns (None, None) where a cell is absent, is not
# right angled, holds no sites, or is not plain decimal text. Four refusals, one return value, and
# the readings that consume it treat the whole class as `continue`. That is the shape a silent
# denominator takes: examples/crystallography/5_sift/lattice_breaks_the_product_rule.py skips a
# refused entry and its closing line still reports a median over whatever survived, with nothing on
# the page saying how much did not.
#
# The cache this runs against makes that worse rather than better. maint/data/fetch/fetch_cod_doped.py
# fetched solid solution formers on purpose and says so in its header: most of them are monoclinic
# or triclinic, and the right angle restriction is deliberately not applied at fetch time. So the
# corpus was built to contain exactly the cells the reading gate turns away.
#
# A run that skips most of its input and prints a confident median is a check whose failure looks
# like its answer, and zero findings over a root that vanished counts as a defect. This tool exists
# so the denominator can be quoted beside the result.
#
# WHAT IT DOES NOT DO
#
# Nothing here is changed on disk, nothing is fetched, and no entry is deleted. This counts.
# Whether the right angle gate should be lifted is a separate question, and this tool supplies the
# measurement that question needs.
#
# THE REFUSALS ARE SEPARATED BECAUSE THEY ARE NOT ONE FAULT
#
# A cell that is absent is a deposit that did not publish one. A cell that is not right angled is a
# deposit that published a perfectly good monoclinic cell the reader chose not to take. The first is
# missing data and the second is a policy of this repository. Reporting them in one bucket would
# hide which of the two the corpus is actually losing entries to, and on this cache it is the
# second by a wide margin.

import argparse
import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke every
# path in this tree the last time anything moved. The dirname guard is what keeps a missing sentinel
# from climbing off the top of the drive and resolving every root to the filesystem root, which is
# the failure recorded against the prose checker.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.structure import crystal  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")
FAMILIES = os.path.join(ROOT, "build", "cod", "families.tsv")

# The refusal names, in the order exact_points applies them. A row is counted under the first test
# it fails, because that is the one that actually turned it away.
NO_CELL = "no cell published"
NOT_RIGHT = "cell not right angled"
NO_SITES = "no atom sites"
NOT_DECIMAL = "coordinate not plain decimal"
ADMITTED = "admitted"


def verdict(text):
    """Which gate an entry meets first, as one of the names above.

    This repeats the order in crystal.exact_points instead of calling it, because exact_points
    collapses four refusals into one return value and tiling every admitted cell to find that out
    would cost the whole corpus a full exact reading. The tests here are the cheap prefix of that
    function and they are in its order.
    """
    raw = crystal.cell_text(text)
    if raw is None:
        return NO_CELL
    if not crystal.right_angled(raw):
        return NOT_RIGHT
    if not crystal.site_text(text):
        return NO_SITES
    try:
        edges = [crystal.exact.units(raw[key]) for key in ("a", "b", "c")]
    except ValueError:
        return NOT_DECIMAL
    if any(edge[0] <= 0 for edge in edges):
        return NOT_DECIMAL
    return ADMITTED


def families_of(path):
    """entry id to family, out of the fetch's manifest. Empty where the file is absent."""
    table = {}
    if not os.path.isfile(path):
        return table
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                table[parts[0]] = parts[1]
    return table


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--cache", default=CACHE, help="directory of .cif files to census")
    parser.add_argument("--families", default=FAMILIES, help="families.tsv written by the fetch")
    args = parser.parse_args()

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    # Named, not assumed. A census whose root is wrong reports a smaller tree than the one it names,
    # and the number still looks like an answer.
    out.write("\n  cache    %s\n" % args.cache)
    out.write("  families %s\n\n" % args.families)

    if not os.path.isdir(args.cache):
        out.write("  REFUSED: no directory at that cache path. This is not a census of zero.\n\n")
        out.flush()
        return 1

    names = sorted(name for name in os.listdir(args.cache) if name.endswith(".cif"))
    if not names:
        out.write("  REFUSED: no .cif under that cache. This is not a census of zero.\n\n")
        out.flush()
        return 1

    family = families_of(args.families)
    counts = {}
    by_family = {}
    for name in names:
        with io.open(os.path.join(args.cache, name), encoding="utf-8", errors="replace") as handle:
            answer = verdict(handle.read())
        counts[answer] = counts.get(answer, 0) + 1
        group = family.get(name[:-4], "unrecorded")
        seen = by_family.setdefault(group, {"total": 0, ADMITTED: 0})
        seen["total"] += 1
        if answer == ADMITTED:
            seen[ADMITTED] += 1

    total = len(names)
    admitted = counts.get(ADMITTED, 0)

    out.write("  %d entries under the cache\n\n" % total)
    out.write("  %-32s %-8s %s\n" % ("verdict", "entries", "share"))
    for answer in (ADMITTED, NOT_RIGHT, NO_CELL, NO_SITES, NOT_DECIMAL):
        got = counts.get(answer, 0)
        out.write("  %-32s %-8d %.1f%%\n" % (answer, got, 100.0 * got / total))

    out.write("\n  %d of %d entries reach the exact reading, which is %.1f percent.\n"
              % (admitted, total, 100.0 * admitted / total))
    out.write("  Every reading that calls exact_points is quoting a number over that denominator\n")
    out.write("  and not over %d.\n\n" % total)

    if len(by_family) > 1:
        out.write("  %-16s %-8s %-10s %s\n" % ("family", "entries", "admitted", "share"))
        for group in sorted(by_family, key=lambda key: -by_family[key]["total"]):
            seen = by_family[group]
            out.write("  %-16s %-8d %-10d %.1f%%\n"
                      % (group, seen["total"], seen[ADMITTED],
                         100.0 * seen[ADMITTED] / seen["total"]))
        out.write("\n")

    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
