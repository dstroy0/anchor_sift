#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-4-001
#
# Read every residue's conformation against the published rules, with no answer key.
#
#   Usage:  python examples/proteins/4_measure/outlier_rate_from_the_rules.py
#
# Nothing here is compared against a deposit's own published outlier rate. That is stage six, and
# keeping them apart is the point of the split: this stage says what the instrument returns and what
# it read to get there, and the oracle says whether it was right.
#
# The instrument is the Ramachandran rules. A residue's two backbone torsions place it on the
# phi-psi plane, and the Richardson laboratory's Top8000 contours say what fraction of a large clean
# reference sits at that place. Above the favored cutoff the conformation is common, above the
# allowed cutoff it is rare but seen, and below it the conformation is one the reference practically
# never took. The cutoffs are MolProbity's own and are printed below. Nothing about what counts
# as an outlier is decided in this file.
#
# The torsions come back from the engine as exact integer terms, and the one irrational step, the
# atan2 that makes a degree, is taken in decimal to a precision far under the two-degree grid the
# answer is read against. So the only quantum in the reading is the grid, and the grid is the
# reference's, not this work's.
#
# Predicted before measuring: a deposited structure sits almost entirely in the favored regions,
# because these are refined models of real folded proteins and the rules were drawn from exactly
# such models. The reading is the favored fraction and the outlier fraction, per structure, said
# plainly with no deposit-published number in sight.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "proteins"))

from representation.structure.protein import WANTED, fetch, phi_psi  # noqa: E402
import ramachandran_rules as rules  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")
CACHE = os.path.join(ROOT, "build", "rama")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)

    out.write("  The rules are the Richardson Top8000 contours. A residue is scored against the\n")
    out.write("  contour for its class, at the MolProbity cutoffs:\n\n")
    for name, (_, favored, allowed) in rules.CONTOURS.items():
        out.write("      %-9s favored >= %-8s allowed >= %s\n" % (name, favored, allowed))
    out.write("\n  Predicted: a deposited model sits almost entirely in the favored regions.\n\n")
    out.write("  %-8s %-8s %-9s %-9s %-9s %s\n"
              % ("code", "scored", "favored", "allowed", "outlier", "favored %"))

    contours = rules.load_contours(CACHE)
    for code, _ in WANTED:
        try:
            text = fetch(code, CORPORA)
        except Exception as trouble:
            out.write("  %-8s could not fetch: %s\n" % (code, trouble))
            continue
        read = rules.score(contours, phi_psi(text))
        if not read:
            out.write("  %-8s no scorable residues\n" % code)
            continue
        favored = sum(1 for residue in read if residue["favored"])
        outlier = sum(1 for residue in read if residue["outlier"])
        allowed = len(read) - favored - outlier
        out.write("  %-8s %-8d %-9d %-9d %-9d %6.2f\n"
                  % (code, len(read), favored, allowed, outlier, 100.0 * favored / len(read)))

    out.write("\n  The favored fraction is the reading. Whether it is the right one is stage six.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
