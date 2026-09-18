#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-1-003
#
# Rebuild every deposit in the corpus from a magnitude table and the Ramachandran cell each residue
# sits in, and read how far the rebuild lands from the deposit.
#
#   Usage:  python examples/proteins/1_represent/rebuild_from_the_table.py [limit]
#
# The claim of the representation is that a backbone is its bond-length magnitudes and its torsions,
# and nothing about where the molecule sits or how it is turned. The walk is the test of that claim.
# A backbone is read as a run of points; internal_coords reads off each point's bond length, turn
# angle and dihedral; rebuild walks them back. Handed a run's own terms, the walk returns the run to
# the digit it was written to, which is the positive control printed first: the transform loses
# nothing.
#
# The reading is what survives compressing the direction. Bond lengths, bond angles and the peptide
# torsion are kept; the two torsions the fold lives in, phi and psi, are quantized to the Richardson
# two-degree grid, the reference's own quantum and the same grid ramachandran_rules scores against.
# So the stored backbone is a magnitude table plus, per residue, which grid cell it fell in. The gap
# between that rebuild and the deposit is read as a whole and then split by constituent. It says
# which backbone atom carries the disagreement, and mapped by resolution where the deposit's own
# published resolution is cached. It says where the disagreement lives.
#
# The walk is unbounded: every unbroken run of every chain, at any length, is rebuilt. The only floor
# is arithmetic, that a dihedral needs four points. The walk carries no length cutoff.

import glob
import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "proteins"))

import numpy  # noqa: E402
from representation.structure.protein import walk, internal_coords, rebuild  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")
CACHE = os.path.join(ROOT, "build", "rama")

# Two degrees is the Richardson grid, the reference's quantum, and the whole of what the walk is told
# about direction. It is not a number chosen here.
GRID_DEGREES = 2.0
CONSTITUENT = ("N", "CA", "C")


def bin_grid(radians):
    degrees = numpy.degrees(radians)
    index = int((degrees + 180) // GRID_DEGREES) % int(360 / GRID_DEGREES)
    return numpy.radians(-180 + GRID_DEGREES * index + GRID_DEGREES / 2)


def kabsch(mobile, target):
    m = mobile - mobile.mean(axis=0)
    t = target - target.mean(axis=0)
    u, _, vt = numpy.linalg.svd(m.T @ t)
    hand = numpy.sign(numpy.linalg.det(u @ vt))
    return (m @ (u @ numpy.diag([1.0, 1.0, hand]) @ vt)) + target.mean(axis=0)


def steered(run):
    """Rebuild a run keeping magnitudes and the peptide torsion, quantizing phi and psi to the grid.

    In walk order the dihedral that places atom i is psi at i%3==0, omega at i%3==1 and phi at
    i%3==2. The peptide torsion omega keeps its measured value and the two fold torsions are told
    to the walk as a grid cell.
    """
    bond, angle, dih = internal_coords(run)

    def steer(index, value):
        return value if (index % 3 == 1) else bin_grid(value)

    return rebuild(run[:3], bond, angle, dih, steer=steer)


def resolution_of(code):
    """The deposit's published resolution from the cached entry document, or None if not cached."""
    path = os.path.join(CACHE, "entry_%s.json" % code)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            body = json.load(handle)
    except (ValueError, OSError):
        return None
    value = body.get("rcsb_entry_info", {}).get("resolution_combined")
    if isinstance(value, list):
        value = value[0] if value else None
    return value


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    limit = int(sys.argv[1]) if len(sys.argv) > 1 else None

    paths = sorted(glob.glob(os.path.join(CORPORA, "pdb_*.txt")))
    if not paths:
        out.write("no corpus. Run examples/proteins/build_corpus.py first.\n")
        out.flush()
        return 1
    if limit:
        paths = paths[:limit]

    out.write("  The magnitude table is the bond lengths and angles; the direction is phi and psi,\n")
    out.write("  each quantized to the Richardson %g-degree grid. omega keeps its measured value.\n\n"
              % GRID_DEGREES)

    worst_exact = 0.0
    gaps = []
    by_constituent = {name: [] for name in CONSTITUENT}
    bands = {}
    proteins = runs = 0
    for path in paths:
        code = os.path.basename(path)[4:8]
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        proteins += 1
        resolution = resolution_of(code)
        band = "unknown" if resolution is None else "%.1f" % (round(float(resolution) * 2) / 2)
        for run in walk(text, least=1):
            if len(run) < 4:
                continue
            runs += 1
            bond, angle, dih = internal_coords(run)
            exact = kabsch(rebuild(run[:3], bond, angle, dih), run)
            worst_exact = max(worst_exact, float(numpy.sqrt(((exact - run) ** 2).sum(1)).max()))
            back = kabsch(steered(run), run)
            gap = numpy.sqrt(((back - run) ** 2).sum(axis=1))
            rmsd = float(numpy.sqrt((gap ** 2).mean()))
            gaps.append(rmsd)
            for offset, name in enumerate(CONSTITUENT):
                by_constituent[name].extend(gap[offset::3].tolist())
            tally = bands.setdefault(band, [])
            tally.append(rmsd)

    if not gaps:
        out.write("  no reconstructable run in the corpus.\n")
        out.flush()
        return 1

    gaps = numpy.array(gaps)
    out.write("  positive control: the walk handed a run's own terms rebuilds it to within\n")
    out.write("  %.2e A over %d proteins, %d runs. The transform loses nothing.\n\n"
              % (worst_exact, proteins, runs))

    q = numpy.percentile(gaps, [25, 50, 75])
    out.write("  magnitude table + %g-degree cell, RMSD per run against the deposit:\n" % GRID_DEGREES)
    out.write("    median %.3f A   Q1 %.3f   Q3 %.3f   under 1 A %.1f%%   under 2 A %.1f%%\n\n"
              % (q[1], q[0], q[2], 100.0 * (gaps < 1.0).mean(), 100.0 * (gaps < 2.0).mean()))

    out.write("  disagreement by constituent (mean gap per backbone atom, A):\n")
    for name in CONSTITUENT:
        column = numpy.array(by_constituent[name])
        out.write("    %-3s %.3f\n" % (name, column.mean()))

    out.write("\n  disagreement by resolution band (median RMSD, count):\n")
    for band in sorted(bands, key=lambda one: (one == "unknown", one)):
        rows = numpy.array(bands[band])
        label = band + (" A" if band != "unknown" else "")
        out.write("    %-9s median %.3f A   %d runs\n" % (label, numpy.median(rows), len(rows)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
