#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CHM-1-001
#
# Build a molecule as atoms carrying an element and bonds carrying an order, and read what that
# representation fixes and what it leaves open.
#
#   Usage:  python examples/chemistry/1_represent/build_molecules.py
#
# A molecule in the engine's terms is a set of points carrying values: each atom is a point carrying
# its element, and each bond is the vector between two of them. This stage builds the connectivity,
# the atoms and the bonds and their orders. It does not place the atoms in space, because a bond's
# magnitude is its length and a length is an oracle fact, valence-fixed and tabulated, that belongs in
# oracle/chemistry with a citation and is not entered yet. So what is built here is the molecular
# graph, and the geometry it carries is stated as design in theory/chemistry, not asserted here.
#
# The element identity, the proton count and the electron set, is authored once by the atomic-structure
# subject in representation.atom.element and consumed, not transcribed. This example holds only
# chemistry's own layer, a valence per element. It runs before that ledger lands on main; wiring the
# import is the routed follow-up. Valence is defined here as the number of covalent bonds a neutral,
# closed-shell atom forms, which for the main group is min(v, 8 - v) over its valence electrons.
#
# The validity gate on the catalog is the octet: every atom of every molecule below must close, or a
# bond was entered wrong. That is the positive control on a hand-built table. Ethanol and dimethyl ether
# are both C2H6O and both close every atom. The formula is a necessary label and not the structure,
#  the sift's survivors still need confirming.

import collections
import io
import sys

# The number of covalent bonds each element forms in a neutral, closed-shell molecule. Chemistry's
# own layer, not the element ledger: it names no proton count and no electron configuration. Helium
# forms none. A charged or open-shell species is outside this model and is left out of the catalog
# .
VALENCE = {"H": 1, "C": 4, "N": 3, "O": 2, "F": 1, "Cl": 1}

Molecule = collections.namedtuple("Molecule", ("name", "atoms", "bonds"))

# The catalog. Each molecule is its atoms in a fixed order and its bonds as (one, other, order),
# order counting shared pairs: 1 single, 2 double, 3 triple. Built by hand from the standard Lewis
# structures and checked by the octet below.
CATALOG = [
    Molecule("water", ["O", "H", "H"], [(0, 1, 1), (0, 2, 1)]),
    Molecule(
        "methane",
        ["C", "H", "H", "H", "H"],
        [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1)],
    ),
    Molecule("ammonia", ["N", "H", "H", "H"], [(0, 1, 1), (0, 2, 1), (0, 3, 1)]),
    Molecule("carbon dioxide", ["C", "O", "O"], [(0, 1, 2), (0, 2, 2)]),
    Molecule("molecular oxygen", ["O", "O"], [(0, 1, 2)]),
    Molecule("molecular nitrogen", ["N", "N"], [(0, 1, 3)]),
    Molecule(
        "ethane",
        ["C", "C", "H", "H", "H", "H", "H", "H"],
        [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1), (1, 5, 1), (1, 6, 1), (1, 7, 1)],
    ),
    Molecule(
        "ethene",
        ["C", "C", "H", "H", "H", "H"],
        [(0, 1, 2), (0, 2, 1), (0, 3, 1), (1, 4, 1), (1, 5, 1)],
    ),
    Molecule("ethyne", ["C", "C", "H", "H"], [(0, 1, 3), (0, 2, 1), (1, 3, 1)]),
    Molecule(
        "hydrogen peroxide", ["O", "O", "H", "H"], [(0, 1, 1), (0, 2, 1), (1, 3, 1)]
    ),
    Molecule("formaldehyde", ["C", "O", "H", "H"], [(0, 1, 2), (0, 2, 1), (0, 3, 1)]),
    Molecule("hydrogen cyanide", ["H", "C", "N"], [(0, 1, 1), (1, 2, 3)]),
    Molecule(
        "methanol",
        ["C", "H", "H", "H", "O", "H"],
        [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1), (4, 5, 1)],
    ),
    Molecule(
        "chloromethane",
        ["C", "H", "H", "H", "Cl"],
        [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1)],
    ),
    Molecule(
        "ethanol",
        ["C", "C", "H", "H", "H", "H", "H", "O", "H"],
        [
            (0, 1, 1),
            (0, 2, 1),
            (0, 3, 1),
            (0, 4, 1),
            (1, 5, 1),
            (1, 6, 1),
            (1, 7, 1),
            (7, 8, 1),
        ],
    ),
    Molecule(
        "dimethyl ether",
        ["C", "C", "O", "H", "H", "H", "H", "H", "H"],
        [
            (0, 2, 1),
            (1, 2, 1),
            (0, 3, 1),
            (0, 4, 1),
            (0, 5, 1),
            (1, 6, 1),
            (1, 7, 1),
            (1, 8, 1),
        ],
    ),
    Molecule(
        "benzene",
        ["C", "C", "C", "C", "C", "C", "H", "H", "H", "H", "H", "H"],
        [
            (0, 1, 2),
            (1, 2, 1),
            (2, 3, 2),
            (3, 4, 1),
            (4, 5, 2),
            (5, 0, 1),
            (0, 6, 1),
            (1, 7, 1),
            (2, 8, 1),
            (3, 9, 1),
            (4, 10, 1),
            (5, 11, 1),
        ],
    ),
]


def weighted_degree(atom_count, bonds):
    """Shared pairs on each atom, a bond counted once for each end it joins."""
    degree = [0] * atom_count
    for one, other, order in bonds:
        degree[one] += order
        degree[other] += order
    return degree


def octet_closes(molecule):
    """Every atom closes: its shared pairs equal its element's valence."""
    degree = weighted_degree(len(molecule.atoms), molecule.bonds)
    return all(
        degree[node] == VALENCE[molecule.atoms[node]]
        for node in range(len(molecule.atoms))
    )


def formula(molecule):
    """The molecular formula in Hill order: carbon first, hydrogen second, then the rest by name."""
    counts = collections.Counter(molecule.atoms)
    order = []
    if "C" in counts:
        order.append("C")
        if "H" in counts:
            order.append("H")
        order.extend(sorted(element for element in counts if element not in ("C", "H")))
    else:
        order.extend(sorted(counts))
    spelled = ""
    for element in order:
        spelled += element + ("" if counts[element] == 1 else str(counts[element]))
    return spelled


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    out.write(
        "  A molecule is atoms carrying an element and bonds carrying an order. The octet is the\n"
    )
    out.write("  gate: every atom closes, or a bond was built wrong.\n")
    out.write(
        "  Formulas are in Hill order, the database convention. A carbon-free compound is fully\n"
    )
    out.write("  alphabetical and ammonia reads H3N.\n\n")
    out.write(
        "  %-20s %-9s %-7s %-7s %s\n"
        % ("molecule", "formula", "atoms", "bonds", "octet")
    )

    closed = 0
    by_formula = collections.defaultdict(list)
    for molecule in CATALOG:
        held = octet_closes(molecule)
        closed += 1 if held else 0
        by_formula[formula(molecule)].append(molecule.name)
        out.write(
            "  %-20s %-9s %-7d %-7d %s\n"
            % (
                molecule.name,
                formula(molecule),
                len(molecule.atoms),
                len(molecule.bonds),
                "closes" if held else "OPEN, check the bonds",
            )
        )

    out.write(
        "\n  positive control: %d of %d built molecules close every atom.\n"
        % (closed, len(CATALOG))
    )

    isomers = {
        spelled: names for spelled, names in by_formula.items() if len(names) > 1
    }
    out.write(
        "  a formula does not fix a molecule. %d formula(s) hold more than one structure:\n"
        % len(isomers)
    )
    for spelled, names in sorted(isomers.items()):
        out.write("    %-9s %s\n" % (spelled, ", ".join(sorted(names))))
    out.write(
        "  each of those closes every atom. The octet admits them all and the choice among\n"
    )
    out.write("  them is left to a measure, not to valence.\n")

    ok = closed == len(CATALOG)
    out.write(
        "\n  %s\n"
        % (
            "every built molecule closed."
            if ok
            else "a molecule did not close; a bond above is wrong."
        )
    )
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
