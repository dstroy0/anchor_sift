#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CHM-5-001
#
# Valence is a necessary condition on a molecule, and a shuffle of the same atoms loses it.
#
#   Usage:  python examples/chemistry/5_sift/valence_is_a_necessary_condition.py
#
# This is the one chemistry demonstration that runs on the primitives already in the tree. The
# molecule reader and the bond-length oracle are design, stated in theory/chemistry; nothing here
# depends on them. What runs here is the sift proposition read on chemistry: an atom's octet is a
# condition on every atom of an arrangement, a real molecule satisfies all of them at once, and the
# error is one directional. A structure the octet refuses cannot be a closed-shell molecule; a
# structure it admits still has to be confirmed, because valence fixes the degree at each atom and
# does not fix which atoms are joined. Ethanol and dimethyl ether both close every atom.
#
# The reading at each atom is boolean. Sum the bond orders on the atom, the electrons it shares, and
# compare against the standard valence of its element: it closes or it does not, with no tolerance,
# because a bond order and a valence are both integers. The molecule is the conjunction.
#
# Two routes are read and they are shown able to disagree. The per-atom octet is the strong one. The
# handshake sum, that the valences add to twice the bond count, is a weaker necessary condition: it
# can pass on an arrangement the per-atom check refuses, which is the mis-wired peroxide below. A
# route that could never disagree with the other would be the same route twice.
#
# The null is drawn, not assumed. Keep the bond graph and the multiset of elements, and permute which
# element sits at which atom with reference.shuffles.permuted. That deletes one property, the match
# between an element and the degree its place carries, and keeps the counts exactly. Most such
# permutations put an element where its valence does not fit the degree. The octet refuses them.
# The real assignment is the one the elements were dealt, and it sits above the band the shuffles
# occupy. No distance here is a value; every one is a departure from that band.

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

# The standard valence of each element used here: the number of covalent bonds a neutral, closed-shell
# atom of it forms. A fact from general chemistry, not derived from anything measured in this script.
# Helium forms none, which is why the He2 negative control cannot close.
VALENCE = {"H": 1, "C": 4, "N": 3, "O": 2, "F": 1, "Cl": 1, "He": 0}

# Each molecule is atoms carrying an element and bonds carrying an order. A bond order counts the
# shared pairs: one for a single bond, two for a double, three for a triple.
MOLECULES = [
    ("water", ["O", "H", "H"], [(0, 1, 1), (0, 2, 1)]),
    ("methane", ["C", "H", "H", "H", "H"], [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1)]),
    ("ammonia", ["N", "H", "H", "H"], [(0, 1, 1), (0, 2, 1), (0, 3, 1)]),
    ("carbon dioxide", ["C", "O", "O"], [(0, 1, 2), (0, 2, 2)]),
    ("ethane", ["C", "C", "H", "H", "H", "H", "H", "H"],
     [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1), (1, 5, 1), (1, 6, 1), (1, 7, 1)]),
    ("ethene", ["C", "C", "H", "H", "H", "H"],
     [(0, 1, 2), (0, 2, 1), (0, 3, 1), (1, 4, 1), (1, 5, 1)]),
    ("ethyne", ["C", "C", "H", "H"], [(0, 1, 3), (0, 2, 1), (1, 3, 1)]),
    ("hydrogen peroxide", ["O", "O", "H", "H"], [(0, 1, 1), (0, 2, 1), (1, 3, 1)]),
]

# Arrangements the octet must refuse. Carbon cannot carry five bonds and helium cannot carry one.
IMPOSSIBLE = [
    ("carbon with five hydrogens", ["C", "H", "H", "H", "H", "H"],
     [(0, 1, 1), (0, 2, 1), (0, 3, 1), (0, 4, 1), (0, 5, 1)]),
    ("bonded helium", ["He", "He"], [(0, 1, 1)]),
]

# Same atoms as peroxide and the same number of shared pairs, wired so the handshake sum still passes
# while two oxygens miss their octet. This is the case the two routes disagree on.
MISWIRED = ("mis-wired peroxide", ["O", "O", "H", "H"], [(0, 1, 1), (0, 2, 1), (0, 3, 1)])

DRAWS = 400


def weighted_degree(atom_count, bonds):
    """Shared pairs on each atom, a bond counted once for each end it joins."""
    degree = [0] * atom_count
    for one, other, order in bonds:
        degree[one] += order
        degree[other] += order
    return degree


def octet_ok(atoms, bonds):
    """Every atom closes: its shared pairs equal its element's valence. The strong route."""
    degree = weighted_degree(len(atoms), bonds)
    return all(degree[node] == VALENCE[atoms[node]] for node in range(len(atoms)))


def handshake_ok(atoms, bonds):
    """The valences add to twice the bond orders. A weaker necessary condition than the octet."""
    return sum(VALENCE[element] for element in atoms) == 2 * sum(order for _, _, order in bonds)


def null_pass_rate(atoms, bonds, draws):
    """Fraction of element-label permutations, drawn by the engine's shuffle, that still close.

    The bond graph is held and the multiset of elements is held; what is deleted is which element
    sits at which atom. permuted preserves every count exactly. Each draw is a genuine
    rearrangement of the same atoms and never invents or loses one.
    """
    codes = {element: index for index, element in enumerate(sorted(set(atoms)))}
    back = {index: element for element, index in codes.items()}
    seats = bytes(codes[element] for element in atoms)
    passed = 0
    for step in range(draws):
        drawn = permuted(seats, seed=SEED + step)
        relabeled = [back[code] for code in drawn]
        if octet_ok(relabeled, bonds):
            passed += 1
    return passed / float(draws)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    out.write("  The octet is a necessary condition on every atom at once. A real molecule meets it,\n")
    out.write("  a shuffle of the same atoms across the same bonds usually does not.\n\n")
    out.write("  %-20s %-7s %-9s %-9s %s\n"
              % ("molecule", "atoms", "octet", "handshake", "null pass-rate over 400 shuffles"))

    real_hits = 0
    null_low, null_high = 1.0, 0.0
    for name, atoms, bonds in MOLECULES:
        strong = octet_ok(atoms, bonds)
        weak = handshake_ok(atoms, bonds)
        rate = null_pass_rate(atoms, bonds, DRAWS)
        real_hits += 1 if strong else 0
        null_low = min(null_low, rate)
        null_high = max(null_high, rate)
        out.write("  %-20s %-7d %-9s %-9s %.3f\n"
                  % (name, len(atoms), "closes" if strong else "open",
                     "holds" if weak else "breaks", rate))

    out.write("\n  positive control: %d of %d real molecules close every atom, and each sits above its\n"
              % (real_hits, len(MOLECULES)))
    out.write("  own null band of %.3f to %.3f. The real assignment is the departure from the shuffle.\n\n"
              % (null_low, null_high))

    out.write("  negative control: arrangements the octet must refuse, or the pass above proves only\n")
    out.write("  that the check is wired to say yes.\n")
    refused = 0
    for name, atoms, bonds in IMPOSSIBLE:
        strong = octet_ok(atoms, bonds)
        refused += 0 if strong else 1
        out.write("    %-28s octet %s\n" % (name, "closes" if strong else "refused"))
    out.write("  %d of %d refused.\n\n" % (refused, len(IMPOSSIBLE)))

    name, atoms, bonds = MISWIRED
    strong = octet_ok(atoms, bonds)
    weak = handshake_ok(atoms, bonds)
    out.write("  two routes, shown able to disagree:\n")
    out.write("    %-28s octet %s, handshake %s\n"
              % (name, "closes" if strong else "refused", "holds" if weak else "breaks"))
    disagree = strong != weak
    out.write("  the routes %s here. Neither is the other twice.\n"
              % ("disagree" if disagree else "agree"))

    ok = real_hits == len(MOLECULES) and refused == len(IMPOSSIBLE) and disagree
    out.write("\n  %s\n" % ("every control held." if ok else "a control did not hold; read the rows above."))
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
