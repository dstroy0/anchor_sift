#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-6-001
#
# Ask the shift detector for a published cell edge, on as many crystals as the archive will give.
#
#   Usage:  python examples/crystals/6_oracle/proof_positive_control.py [how many names]
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
# What a failure would look like, stated before the numbers: a recovered edge that misses the
# published one by more than the voxel would mean the instrument is not reading the period, and a
# systematic bias in one direction would mean it is reading the tiling instead of the crystal.

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

from measure.shift_agreement import recover_lattice_period  # noqa: E402
from representation.structure.crystal import VOXEL, parse_cif, tiles_for, voxel_grid  # noqa: E402

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


def measure_entry(cell, sites):
    """Every axis of one structure, as (axis name, published edge, recovered edge).

    Returns an empty list where the cell cannot be tiled or nothing agreed on any axis.
    """
    tiles = tiles_for(cell)
    if tiles is None:
        return []
    grid, _ = voxel_grid(cell, sites, VOXEL, tiles)
    if grid is None:
        return []

    found = []
    for axis, name in enumerate(("a", "b", "c")):
        published = cell[name]
        exact = published / VOXEL
        # Swept past two whole periods, so the fundamental and its first harmonic are both in range
        # and the fundamental has to win on its own instead of by being the only candidate.
        reach = min(int(exact * 2.0) + 6, grid.shape[axis] - 1)
        if reach < 4:
            continue
        lag, fraction, score = recover_lattice_period(grid, axis, reach)
        if lag is None:
            continue
        recovered = (lag + (fraction if fraction is not None else 0.0)) * VOXEL
        found.append((name, published, recovered, lag, score))
    return found


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CACHE, exist_ok=True)

    how_many = int(sys.argv[1]) if len(sys.argv) > 1 else len(WANTED)
    names = WANTED[:how_many]

    out.write("  Predicted before measuring: the recovered edge lands inside one voxel of %.2f\n"
              % VOXEL)
    out.write("  angstroms, on every axis of every structure, with nothing told to the detector.\n\n")
    out.write("  %-16s %-11s %-5s %-11s %-11s %-9s %s\n"
              % ("mineral", "cod id", "axis", "published", "recovered", "error", "agreement"))

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
            try:
                cell, sites = parse_cif(text)
            except Exception:
                continue
            if (cell is None) or (len(sites) < 2):
                continue

            measured = measure_entry(cell, sites)
            if not measured:
                continue
            kept += 1
            for axis, published, recovered, lag, score in measured:
                error = recovered - published
                rows.append((name, identifier, axis, published, recovered, error, score))
                out.write("  %-16s %-11s %-5s %-11.4f %-11.4f %-9.4f %.3f\n"
                          % (name[:16], identifier, axis, published, recovered, error, score))
            out.flush()

    if not rows:
        out.write("\n  nothing measured. The archive may be unreachable and the cache is empty.\n")
        out.flush()
        return 1

    errors = [abs(row[5]) for row in rows]
    signed = [row[5] for row in rows]
    inside = sum(1 for value in errors if value <= VOXEL)
    structures = len({row[1] for row in rows})

    out.write("\n  %d axes measured over %d structures from %d names\n"
              % (len(rows), structures, len(names)))
    out.write("  %d of %d landed inside one voxel of %.2f angstroms, which is %.1f percent\n"
              % (inside, len(rows), VOXEL, 100.0 * inside / len(rows)))
    out.write("  mean absolute error %.4f angstroms, worst %.4f\n"
              % (sum(errors) / len(errors), max(errors)))
    out.write("  mean signed error %+.4f angstroms, which says whether it reads long or short\n"
              % (sum(signed) / len(signed)))

    # A miss is worth more than a hit here, so every one of them is named instead of counted.
    missed = sorted((row for row in rows if abs(row[5]) > VOXEL), key=lambda row: -abs(row[5]))
    if missed:
        out.write("\n  outside one voxel, worst first\n")
        for name, identifier, axis, published, recovered, error, score in missed[:20]:
            out.write("    %-16s %-11s %-5s published %-9.4f recovered %-9.4f off by %+.4f\n"
                      % (name[:16], identifier, axis, published, recovered, error))
    else:
        out.write("\n  nothing missed by more than one voxel\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
