#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CHM-4-001
#
# A histogram measure reads a molecule's composition and cannot read its structure.
#
#   Usage:  python examples/chemistry/4_measure/a_histogram_cannot_see_structure.py
#
# The measure part of the engine reads how far an object sits from its reference, and it carries a
# warning about one class of measure: collision entropy is computed from the symbol counts alone, so
# it is permutation invariant. A corpus and its own shuffle carry identical values, exactly and not
# approximately, and no entropy of that order separates a structured arrangement from a rearrangement
# of the same symbols.
#
# Chemistry is where that boundary is easiest to see. A molecule read as its multiset of atoms is a
# histogram. Its collision entropy is exactly equal to the collision entropy of any rearrangement
# of the same atoms, and two isomers, being the same formula, carry the identical value. The measure
# reads the formula and stops there.
#
# That is the negative result the rest of the pipeline exists for. Arrangement is what tells a
# molecule from a random packing of its atoms, and the sift stage reads arrangement through the octet.
# Telling one isomer from another is a finer reading still, and no histogram and no octet reaches it,
# because both isomers close every atom; it is a geometry question, answered by the bond lengths that
# are an oracle. So this stage is the measure that a molecule's composition is not its structure, run
# on the engine's own collision entropy and reported as a departure of exactly zero.

import collections
import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.entropy import collision_entropy  # noqa: E402
from reference.shuffles import SEED, permuted  # noqa: E402

Molecule = collections.namedtuple("Molecule", ("name", "atoms"))

# Read as multisets of atoms, which is all a histogram measure sees. Ethanol and dimethyl ether are
# the same multiset and are here to be told apart, and are not.
MOLECULES = [
    Molecule("water", ["O", "H", "H"]),
    Molecule("methane", ["C", "H", "H", "H", "H"]),
    Molecule("benzene", ["C"] * 6 + ["H"] * 6),
    Molecule("ethanol", ["C", "C", "H", "H", "H", "H", "H", "O", "H"]),
    Molecule("dimethyl ether", ["C", "C", "O", "H", "H", "H", "H", "H", "H"]),
]

DRAWS = 8


def as_bytes(atoms):
    """Atoms encoded one element to one byte. The engine's shuffle and entropy both read them."""
    codes = {element: index for index, element in enumerate(sorted(set(atoms)))}
    return bytes(codes[element] for element in atoms)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Collision entropy reads the atom counts alone. It is permutation invariant: a\n")
    out.write("  molecule and any rearrangement of its atoms carry the same value, exactly.\n\n")
    out.write("  %-16s %-8s %-14s %s\n" % ("molecule", "H2 bits", "eff. alphabet", "real minus shuffle, worst of 8"))

    worst_gap = 0.0
    for molecule in MOLECULES:
        seats = as_bytes(molecule.atoms)
        bits, alphabet, _, _ = collision_entropy(seats)
        gap = 0.0
        for step in range(DRAWS):
            shuffled = permuted(seats, seed=SEED + step)
            shifted, _, _, _ = collision_entropy(shuffled)
            gap = max(gap, abs(shifted - bits))
        worst_gap = max(worst_gap, gap)
        out.write("  %-16s %-8.3f %-14.3f %.3e\n" % (molecule.name, bits, alphabet, gap))

    out.write("\n  the departure from a shuffle is zero to machine precision on every molecule, worst %.1e.\n"
              % worst_gap)

    ethanol = collision_entropy(as_bytes(["C", "C", "H", "H", "H", "H", "H", "O", "H"]))[0]
    ether = collision_entropy(as_bytes(["C", "C", "O", "H", "H", "H", "H", "H", "H"]))[0]
    out.write("  the two isomers read identically: ethanol %.4f, dimethyl ether %.4f, difference %.1e.\n"
              % (ethanol, ether, abs(ethanol - ether)))
    out.write("  So the histogram reads the formula and no more. Arrangement is the sift's to read, and\n")
    out.write("  which isomer a formula becomes is a geometry question the bond-length oracle answers.\n")

    ok = worst_gap == 0.0 and ethanol == ether
    out.write("\n  %s\n" % ("the measure is blind to arrangement, as predicted." if ok
                            else "a departure was not zero; the invariance did not hold."))
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
