#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-3-001
#
# The favored fraction a structure reaches with its phi-psi pairing deleted, built from itself.
#
#   Usage:  python examples/proteins/3_reference/what_a_shuffle_reaches.py
#
# A reference is the most a structure reaches once the thing being looked for is removed from it,
# and made out of the structure alone so it borrows nothing. What stage four reads is the favored
# fraction, so the question here is how much of that fraction survives when what carries it is taken
# away, and the answer names what carries it.
#
# Two deletions, each keeping something and destroying something.
#
# Shuffling psi against phi keeps both marginal angle distributions exactly and destroys only which
# psi stood with which phi. If the favored fraction were a property of the two angles separately it
# would survive this untouched. It does not, because the favored regions are diagonal ridges on the
# plane and not a rectangle: a helix is one narrow place and a sheet another, and a phi from the
# helix put beside a psi from the sheet lands between them where the reference is thin. The pairing
# is the secondary structure, and this deletion is the one that shows it.
#
# Drawing angles uniformly keeps nothing. It is the flat background, the fraction of the whole plane
# the favored regions cover, and it says how much a reading would get from a structure that had no
# preference at all. The favored regions are a small part of the plane, so this floor is low.
#
# Predicted before measuring: the live favored fraction is near total, the paired-shuffle fraction
# is well below it, and the uniform fraction is lower still. The gap from live to shuffle is the
# part of the reading that rests on the pairing, and it is not small.

import io
import os
import random
import sys
from decimal import Decimal

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

# Held, so a rerun reports the same background. The draw belongs to the universe and not to the run.
SEED = 0x51F7


def favored_fraction(contours, angles):
    """The share of residues whose (phi, psi) sits at or above the general favored cutoff.

    One contour is used for every residue here, the general one, because a shuffle has already
    broken the residue identity that would pick a class. The question is about the plane, not the
    per-class bookkeeping, and holding the contour fixed keeps the three columns comparing like with
    like.
    """
    grid, favored, _ = contours["general"]
    inside = sum(1 for phi, psi in angles if rules.value_at(grid, phi, psi) >= favored)
    return 100.0 * inside / len(angles) if angles else 0.0


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    rng = random.Random(SEED)

    out.write("  Favored fraction against the general contour, read three ways.\n")
    out.write("  live: the pairing as deposited.  shuffled: psi permuted against phi.\n")
    out.write("  uniform: phi and psi drawn flat on the plane.\n\n")
    out.write("  %-8s %-8s %-11s %-11s %-11s %s\n"
              % ("code", "residues", "live fav %", "shuffled %", "uniform %", "live minus shuffle"))

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

        phis = [residue["phi"] for residue in read]
        psis = [residue["psi"] for residue in read]

        live = favored_fraction(contours, list(zip(phis, psis)))

        moved = psis[:]
        rng.shuffle(moved)
        shuffled = favored_fraction(contours, list(zip(phis, moved)))

        flat = [(Decimal(rng.uniform(-180, 180)), Decimal(rng.uniform(-180, 180)))
                for _ in read]
        uniform = favored_fraction(contours, flat)

        out.write("  %-8s %-8d %-11.2f %-11.2f %-11.2f %+.2f\n"
                  % (code, len(read), live, shuffled, uniform, live - shuffled))

    out.write("\n  The live to shuffle gap is the favored fraction that rests on the pairing, which\n")
    out.write("  is the secondary structure. The uniform column is how much the bare plane gives.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
