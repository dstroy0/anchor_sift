#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-x-002
# Catalog: PRO-VIEW
#
# Render the object under exam: a deposited backbone and the one a vector walk rebuilds from a
# magnitude table and the Ramachandran cell each residue sits in, laid on the same axes so the
# disagreement is read where it enters.
#
#   Usage:  python examples/proteins/build_protein_view.py 1UBQ
#           python examples/proteins/build_protein_view.py 1UBQ --out build/1ubq_view.html
#
# The engine reads the deposit and walks the rebuild; this writes the numbers into a template as one
# JSON literal and emits a single self-contained page, the same way the blob viewers do. It uses the
# engine. It is an example of the pattern and not a standard-library toolkit viewer.
#
# What the page shows, per unbroken chain run, no run left out and no length window:
#   - the deposited backbone, drawn as muted reference ink,
#   - the rebuilt backbone, superposed onto the deposit and colored by how far each atom lands from
#     where the deposit put it,
#   - the disagreement broken down by constituent: which backbone atom (N, CA, C) carries it.
#
# The rebuild stores only the bond-length magnitudes, the real bond angles, the peptide torsion, and
# each phi and psi quantized to the Richardson two-degree grid. That grid is the reference's quantum,
# named in ramachandran_rules, and it is the whole of what the walk is told about direction.

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
from representation.structure.protein import fetch, walk, internal_coords, rebuild  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "protein_view_template.html")
CORPORA = os.path.join(ROOT, "build", "corpora")

# The three backbone atoms in walk order. An atom's place in the cycle names which bond it is.
CONSTITUENT = ("N", "CA", "C")


def bin_two_degrees(radians):
    """Quantize an angle to the nearest Richardson two-degree grid center, in radians.

    Two degrees is the reference's grid, not a number chosen here. It is the one quantum the walk is
    given for direction, and it is the same grid ramachandran_rules scores a residue against.
    """
    degrees = numpy.degrees(radians)
    index = int((degrees + 180) // 2) % 180
    return numpy.radians(-179 + 2 * index)


def kabsch(mobile, target):
    """Superpose `mobile` onto `target` by the optimal rigid motion, and return the moved points.

    Kabsch 1976 (Acta Cryst A32:922), the SVD form with the determinant-sign correction that keeps
    the motion a rotation and refuses the reflection a raw SVD would take when the two are of
    opposite hand.
    """
    m_center = mobile.mean(axis=0)
    t_center = target.mean(axis=0)
    left = mobile - m_center
    right = target - t_center
    u, _, vt = numpy.linalg.svd(left.T @ right)
    hand = numpy.sign(numpy.linalg.det(u @ vt))
    rotation = u @ numpy.diag([1.0, 1.0, hand]) @ vt
    return (left @ rotation) + t_center


def compressed_rebuild(run):
    """The backbone the walk rebuilds from the magnitude table and the two-degree Ramachandran cell.

    Bond lengths, bond angles and the peptide torsion are kept from the deposit; phi and psi, the two
    torsions the fold lives in, are quantized to the reference grid. In walk order the dihedral that
    places atom i is psi at i%3==0, omega at i%3==1 and phi at i%3==2. Only the omega positions
    keep their measured direction and every other torsion is told to the walk as a grid cell.
    """
    bond, angle, dih = internal_coords(run)
    steered = dih.copy()
    for i in range(3, len(run)):
        if i % 3 != 1:
            steered[i] = bin_two_degrees(dih[i])
    return rebuild(run[:3], bond, angle, steered)


def main():
    argv = sys.argv[1:]
    if not argv or argv[0].startswith("-"):
        sys.stderr.write("give a PDB code, e.g. python build_protein_view.py 1UBQ\n")
        return 2
    code = argv[0].upper()
    out = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(HERE, "protein_view.html")

    os.makedirs(CORPORA, exist_ok=True)
    text = fetch(code, CORPORA)

    runs_payload = []
    all_gap = []
    by_constituent = {name: [] for name in CONSTITUENT}
    for run in walk(text, least=1):                 # every unbroken run, any length, none dropped
        if len(run) < 4:                            # a dihedral needs four points; arithmetic floor
            continue
        rebuilt = kabsch(compressed_rebuild(run), run)
        gap = numpy.sqrt(((rebuilt - run) ** 2).sum(axis=1))
        all_gap.append(gap)
        for offset, name in enumerate(CONSTITUENT):
            by_constituent[name].append(gap[offset::3])
        runs_payload.append({
            "atoms": len(run),
            "deposit": [[round(float(v), 3) for v in point] for point in run],
            "rebuilt": [[round(float(v), 3) for v in point] for point in rebuilt],
            "gap": [round(float(v), 3) for v in gap],
        })

    if not runs_payload:
        sys.stderr.write("no reconstructable backbone run in %s\n" % code)
        return 1

    gaps = numpy.concatenate(all_gap)
    constituent_mean = {name: float(numpy.concatenate(by_constituent[name]).mean())
                        for name in CONSTITUENT}
    payload = {
        "code": code,
        "title": "%s - deposit against the vector walk" % code,
        "runs": runs_payload,
        "summary": {
            "runs": len(runs_payload),
            "atoms": int(gaps.size),
            "rmsd": round(float(numpy.sqrt((gaps ** 2).mean())), 3),
            "median": round(float(numpy.median(gaps)), 3),
            "worst": round(float(gaps.max()), 3),
            "constituent": {name: round(constituent_mean[name], 3) for name in CONSTITUENT},
        },
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "</script>" not in page:
        raise SystemExit("template is truncated: the script tag is never closed")
    page = page.replace("/*PROTEIN_DATA*/null", json.dumps(payload, separators=(",", ":")))

    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    s = payload["summary"]
    print("wrote %s (%.1f KB)" % (out, os.path.getsize(out) / 1024.0))
    print("  %s: %d run(s), %d atoms, RMSD %.3f A, median gap %.3f A, worst %.3f A"
          % (code, s["runs"], s["atoms"], s["rmsd"], s["median"], s["worst"]))
    print("  by constituent (mean gap A): N %.3f  CA %.3f  C %.3f"
          % (s["constituent"]["N"], s["constituent"]["CA"], s["constituent"]["C"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
