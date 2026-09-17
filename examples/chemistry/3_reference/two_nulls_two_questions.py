#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CHM-3-001
#
# Two graded nulls for a molecule, each deleting a different property, so the reference fixes the
# question the octet is asked.
#
#   Usage:  python examples/chemistry/3_reference/two_nulls_two_questions.py
#
# A departure is only as good as the background it is read against, and the engine's rule is that the
# background is drawn from the object by deleting one property, never assumed. Two deletions are
# available on a molecule and they are not the same question.
#
# Null one deletes the match between an element and the site it sits on: keep the bond graph and the
# multiset of elements, permute which element sits where. The octet then closes only when each element
# lands on a site whose degree is its valence, so the real molecule departs from this null and most
# permutations fail. This is the reading the sift stage rests on.
#
# Null two deletes the connectivity: keep each atom's degree exactly equal to its valence, rewire
# which atoms are joined by drawing a random matching of the bond stubs. Every rewire closes the
# octet, because the octet counts degree and the degree is held fixed by construction. So the octet
# does not depart from this null at all, and the rewires it admits include self-bonded and
# disconnected graphs that are not molecules.
#
# The two answers are the finding. The octet carries information about which element sits where and
# carries none about which atoms are joined. It is a statement about degrees, necessary and not
# sufficient, which is why telling one isomer from another is a measure question and not a valence
# question. Both nulls are drawn with the engine's own shuffle; nothing about the disordered state is
# assumed.

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

from reference.shuffles import SEED, permuted  # noqa: E402

# Chemistry's own valence layer: the covalent bonds a neutral, closed-shell atom forms. Not the
# element ledger, which carries proton counts and electron sets and is consumed, not held here.
VALENCE = {"H": 1, "C": 4, "N": 3, "O": 2, "F": 1, "Cl": 1}

Molecule = collections.namedtuple("Molecule", ("name", "atoms", "bonds"))

# A few molecules from the catalog, small enough that a site index fits in one byte so the engine's
# byte shuffle can draw the matching.
MOLECULES = [
    Molecule("water", ["O", "H", "H"], [(0, 1, 1), (0, 2, 1)]),
    Molecule("methane", ["C", "H", "H", "H", "H"],
             [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1)]),
    Molecule("ammonia", ["N", "H", "H", "H"], [(0, 1, 1), (0, 2, 1), (0, 3, 1)]),
    Molecule("ethanol", ["C", "C", "H", "H", "H", "H", "H", "O", "H"],
             [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1), (1, 5, 1), (1, 6, 1),
              (1, 7, 1), (7, 8, 1)]),
    Molecule("benzene", ["C", "C", "C", "C", "C", "C", "H", "H", "H", "H", "H", "H"],
             [(0, 1, 2), (1, 2, 1), (2, 3, 2), (3, 4, 1), (4, 5, 2), (5, 0, 1),
              (0, 6, 1), (1, 7, 1), (2, 8, 1), (3, 9, 1), (4, 10, 1), (5, 11, 1)]),
]

DRAWS = 400


def weighted_degree(atom_count, bonds):
    """Shared pairs on each atom, a bond counted once for each end it joins."""
    degree = [0] * atom_count
    for one, other, order in bonds:
        degree[one] += order
        degree[other] += order
    return degree


def octet_holds(atoms, bonds):
    """Every atom's shared pairs equal its element's valence."""
    degree = weighted_degree(len(atoms), bonds)
    return all(degree[node] == VALENCE[atoms[node]] for node in range(len(atoms)))


def null_one_rate(molecule, draws):
    """Element-label permutation: keep the bond graph, permute which element sits at which site."""
    codes = {element: index for index, element in enumerate(sorted(set(molecule.atoms)))}
    back = {index: element for element, index in codes.items()}
    seats = bytes(codes[element] for element in molecule.atoms)
    passed = 0
    for step in range(draws):
        drawn = permuted(seats, seed=SEED + step)
        relabeled = [back[code] for code in drawn]
        if octet_holds(relabeled, molecule.bonds):
            passed += 1
    return passed / float(draws)


def null_two(molecule, draws):
    """Degree-preserving rewire: hold each atom's degree at its valence, redraw the matching.

    Each atom contributes as many bond stubs as its valence. A permutation of the stubs, paired two
    at a time, is a random matching with the same degree sequence. The octet is checked on the rewired
    graph, and a self-bond, a stub of an atom paired with another of its own, is counted because it is
    a graph the octet admits and a molecule cannot be.
    """
    stubs = []
    for node, element in enumerate(molecule.atoms):
        stubs.extend([node] * VALENCE[element])
    seats = bytes(stubs)
    passed = 0
    with_self_bond = 0
    for step in range(draws):
        drawn = permuted(seats, seed=SEED + step)
        bonds = [(drawn[position], drawn[position + 1], 1)
                 for position in range(0, len(drawn), 2)]
        if octet_holds(molecule.atoms, bonds):
            passed += 1
        if any(one == other for one, other, _ in bonds):
            with_self_bond += 1
    return passed / float(draws), with_self_bond / float(draws)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Two nulls, two questions. Null one deletes the element-to-site match; null two deletes\n")
    out.write("  the connectivity and holds every degree at its valence.\n\n")
    out.write("  %-12s %-22s %-22s %s\n"
              % ("molecule", "null 1 octet pass-rate", "null 2 octet pass-rate", "null 2 self-bonded"))

    departs_one = 0
    holds_two = 0
    for molecule in MOLECULES:
        real = octet_holds(molecule.atoms, molecule.bonds)
        rate_one = null_one_rate(molecule, DRAWS)
        rate_two, self_bond = null_two(molecule, DRAWS)
        departs_one += 1 if (real and rate_one < 1.0) else 0
        holds_two += 1 if rate_two == 1.0 else 0
        out.write("  %-12s %-22.3f %-22.3f %.3f\n"
                  % (molecule.name, rate_one, rate_two, self_bond))

    out.write("\n  null one: the real molecule closes and departs from the shuffle in %d of %d, so which\n"
              % (departs_one, len(MOLECULES)))
    out.write("  element sits where carries information.\n")
    out.write("  null two: the octet closes on every degree-preserving rewire in %d of %d, so it carries\n"
              % (holds_two, len(MOLECULES)))
    out.write("  none about which atoms are joined. The self-bonded column counts rewires that are not\n")
    out.write("  molecules and pass the octet anyway.\n")

    ok = departs_one == len(MOLECULES) and holds_two == len(MOLECULES)
    out.write("\n  %s\n" % ("both nulls read as predicted." if ok
                            else "a null did not read as predicted; see the rows above."))
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
