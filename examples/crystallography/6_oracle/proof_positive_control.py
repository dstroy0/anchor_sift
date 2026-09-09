#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-6-001
#
# Ask the shift detector for a published cell edge, on as many crystals as the archive will give.
#
#   Usage:  python examples/crystallography/6_oracle/proof_positive_control.py [how many names]
#
# Proof of the posit that a negative control cannot show an instrument works, from the posits
# section of theory/workbook. Every control in this work until the protein
# structures was a memoryless process, and one of those can only show that an instrument does not
# invent structure. It cannot show that the instrument finds structure that is there, and the
# protein case demonstrated the difference by being reported as unstructured twice.
#
# A crystal is the cleanest positive control available, because the periodicity is not inferred from
# the measurement. The Crystallography Open Database publishes the cell edge for every entry, so the
# answer is a number someone else measured and wrote down before this instrument existed.
#
# This sweeps instead of sampling. The first run of it took three minerals and returned three exact
# answers, which is a result nobody should rest on: three is where a coincidence still lives. Every
# name below is fetched, every entry with right angles is read, and all three axes of every one are
# asked. A single structure contributes up to three independent answers, and a wrong one cannot
# hide in a small denominator.
#
# Everything fetched is cached under build/cod. The archive is a public service run by people. A
# second run costs it nothing, and the pause between requests is not negotiable.
#
# The reading is exact and the comparison is equality. An earlier version of this put the sites on a
# grid of 0.25 angstroms first, and every number it reported carried that grid: 453 axes recovered
# inside one voxel at a mean absolute error of 0.0124 angstroms and a worst of 0.0554. None of that
# error was in the deposit or in the detector. It was the grid, and the grid was chosen here.
#
# The points are now carried as exact integers at 1e-1024 of an angstrom. A recovered period either
# is the published edge or is not. There is no tolerance to set and no error to average, and the
# grid's cap on cell size went with it, leaving more axes readable than before.
#
# What a failure would look like, stated before the numbers: any axis where the recovered period is
# not equal to the published edge. A near miss counts as a miss, since nothing here rounds.

import io
import json
import os
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.shift_agreement import recover_exact_period  # noqa: E402
from representation import exact  # noqa: E402
from representation.structure.crystal import exact_points  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")

AGENT = {"User-Agent": "anchor-sift-research/1.0 "
                       "(https://github.com/dstroy0/anchor_sift; dquigg123@gmail.com)"}
SEARCH = "https://www.crystallography.net/cod/result?format=json&text=%s&count=%d"
CIF = "https://www.crystallography.net/cod/%s.cif"

# Seconds between requests that actually reach the archive. A cached read waits for nothing.
PAUSE = 2.0

# Attempts per request before the entry is given up on.
TRIES = 3

# Entries taken per name, and how many of those are read all the way through.
PER_NAME = 8
KEPT_PER_NAME = 3

# Minerals and simple compounds likely to be published with right angles. Names, not formulas,
# because the archive's text search is what accepts them.
WANTED = (
    "halite", "fluorite", "pyrite", "periclase", "galena", "sylvite", "magnetite",
    "spinel", "rutile", "anatase", "cassiterite", "zincite", "corundum", "hematite",
    "quartz", "cristobalite", "calcite", "aragonite", "dolomite", "siderite",
    "sphalerite", "wurtzite", "chromite", "franklinite", "gahnite", "bunsenite",
    "manganosite", "wustite", "lime", "cerianite", "thorianite", "uraninite",
    "villiaumite", "carobbiite", "chlorargyrite", "bromargyrite", "iodargyrite",
    "cooperite", "cattierite", "vaesite", "hauerite", "alabandite", "oldhamite",
    "niningerite", "carlsbergite", "osbornite", "khamrabaevite", "tantalcarbide",
    "brucite", "portlandite", "bromellite", "tenorite", "cuprite", "massicot",
    "litharge", "senarmontite", "valentinite", "arsenolite", "claudetite",
    "molybdenite", "tungstenite", "berndtite", "herzenbergite", "teallite",
)


def cached(name, url, out):
    """Fetch a URL once and keep it. Returns the text, or None where the archive refused."""
    path = os.path.join(CACHE, name)
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read(), False
    # The archive closes a connection now and then under a sweep this size. A dropped request is
    # not a missing structure, and treating it as one would quietly shrink the denominator.
    text = None
    for attempt in range(TRIES):
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=180) as response:
                text = response.read().decode("utf-8", "replace")
            break
        except Exception as trouble:
            if attempt == (TRIES - 1):
                out.write("      gave up on %s: %s\n" % (name, str(trouble)[:60]))
                return None, True
            time.sleep(PAUSE * (attempt + 2))
    if text is None:
        return None, True
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    return text, True


def angstroms(value):
    """An exact integer at the scale, as the decimal text it stands for.

    Rendered by moving the point in the digit string. Dividing by the scale to print it would put a
    float back into the one path that has none.
    """
    sign = "-" if value < 0 else ""
    digits = str(abs(value)).rjust(exact.SCALE_DIGITS + 1, "0")
    whole = digits[:-exact.SCALE_DIGITS]
    part = digits[-exact.SCALE_DIGITS:].rstrip("0")
    return "%s%s.%s" % (sign, whole, part) if part else "%s%s" % (sign, whole)


def measure_entry(text):
    """Every axis of one structure, as (axis name, published edge, recovered period, agreement).

    The two edges are exact integers at representation.exact.SCALE and are compared with equality.
    Nothing is swept: the whole difference set of the axis is the candidate set, so no ceiling here
    decides what can be found.

    Returns an empty list where the cell cannot be read exactly or nothing agreed on any axis.
    """
    points, published = exact_points(text)
    if points is None:
        return []

    found = []
    for axis, name in enumerate(("a", "b", "c")):
        period, score = recover_exact_period(exact.along(points, axis))
        if period is None:
            continue
        found.append((name, published[axis], period, score))
    return found


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CACHE, exist_ok=True)

    how_many = int(sys.argv[1]) if len(sys.argv) > 1 else len(WANTED)
    names = WANTED[:how_many]

    out.write("  Predicted before measuring: the recovered period equals the published edge, on\n")
    out.write("  every axis of every structure, with nothing told to the detector.\n\n")
    out.write("  %-16s %-11s %-5s %-14s %-14s %-6s %s\n"
              % ("mineral", "cod id", "axis", "published", "recovered", "same", "agreement"))

    rows = []
    seen = set()
    for name in names:
        found, reached = cached("search_%s.json" % name, SEARCH % (urllib.parse.quote(name),
                                                                   PER_NAME), out)
        if reached:
            time.sleep(PAUSE)
        if found is None:
            continue
        try:
            entries = json.loads(found)
        except ValueError:
            continue

        kept = 0
        for entry in entries:
            if kept >= KEPT_PER_NAME:
                break
            identifier = str(entry.get("file", ""))
            if (not identifier) or (identifier in seen):
                continue
            seen.add(identifier)

            text, reached = cached("%s.cif" % identifier, CIF % identifier, out)
            if reached:
                time.sleep(PAUSE)
            if text is None:
                continue
            measured = measure_entry(text)
            if not measured:
                continue
            kept += 1
            for axis, published, recovered, score in measured:
                same = recovered == published
                rows.append((name, identifier, axis, published, recovered, same, score))
                out.write("  %-16s %-11s %-5s %-14s %-14s %-6s %d\n"
                          % (name[:16], identifier, axis, angstroms(published),
                             angstroms(recovered), "yes" if same else "NO", score))
            out.flush()

    if not rows:
        out.write("\n  nothing measured. The archive may be unreachable and the cache is empty.\n")
        out.flush()
        return 1

    same = sum(1 for row in rows if row[5])
    structures = len({row[1] for row in rows})

    out.write("\n  %d axes measured over %d structures from %d names\n"
              % (len(rows), structures, len(names)))
    out.write("  %d of %d equal the published edge exactly, which is %.1f percent\n"
              % (same, len(rows), 100.0 * same / len(rows)))
    out.write("  every coordinate carried as an integer at 1e-%d angstroms, nothing rounded\n"
              % exact.SCALE_DIGITS)

    # A miss counts for more than a hit here, so every one is named instead of counted.
    missed = [row for row in rows if not row[5]]
    if missed:
        out.write("\n  not equal to the published edge\n")
        for name, identifier, axis, published, recovered, _, score in missed[:20]:
            out.write("    %-16s %-11s %-5s published %-16s read %s\n"
                      % (name[:16], identifier, axis, angstroms(published), angstroms(recovered)))
    else:
        out.write("\n  no axis differed from its published edge\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
