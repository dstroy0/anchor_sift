#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: MOL-1-001
#
# The bond count an atom carries, read off its outermost shell, and the assembly that count dictates.
#
#   Usage:  python examples/molecules/1_represent/assembly_from_atomic_properties.py
#
# An atom assembles by the one magnitude its outermost shell carries: the deficit to a closed shell. A
# shell closes at two electrons for the first, at eight for the main-group shells past it, the duet and
# the octet, and those closures are the shell closures the periodic-law measure stage read off the
# accumulation. An atom with v electrons in its outermost shell is v short one way and closed-minus-v
# short the other, and it forms the smaller of the two in bonds: min(v, closed - v). That integer is the
# capacity, the vector magnitude the atom brings to assembly, and it dictates the stoichiometry with no
# tolerance and no measured length.
#
# The rules are not put in here. The capacity is read from element.electrons, the same ledger the atom
# stage represents, and the closures are read from the same shells. What comes out is the simplest
# hydride of each element and the bond order of its homonuclear pair: oxygen at capacity two binds two
# hydrogens and doubles with itself, nitrogen at three binds three and triples, carbon at four binds
# four. Water, ammonia and methane are the capacity counting hydrogens, not a fact told to the reader.
#
# The main group is where one magnitude suffices. The d-block and f-block carry a partly filled inner
# shell and a variable valence. This reads the first eighteen elements and says where it stops.
# Bonding has more to it than a count, bond length and angle and energy among it, and those are the
# chemistry subject's oracle. This reads the count.

import io
import os
import sys

# Walk up to the repository instead of counting directories to it, and stop at the filesystem root.
# A directory that is its own parent would otherwise loop the walk forever. Counting is what broke
# every path in this tree the last time anything moved.
ROOT = os.path.dirname(os.path.abspath(__file__))
while ROOT != os.path.dirname(ROOT) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
if not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    raise SystemExit("could not find src/engine above %s" % os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.atom import element  # noqa: E402

# The last main-group element before the first d electron arrives. One magnitude reads every atom at
# or below it. Argon closes the third shell at Z 18; scandium opens 3d at 21.
LAST_MAIN_GROUP = 18

# The common name of a simplest hydride, for the ones everyone knows. The formula is the capacity
# counting hydrogens; the name is cited chemistry.
HYDRIDE_NAMES = {"C": "methane", "N": "ammonia", "O": "water"}


def outermost_valence(atomic_number):
    """The electrons in the atom's outermost shell, and that shell's closure, from the ledger.

    The outermost shell is the highest principal number the atom fills. Its valence electrons are the
    ones there in the s and p subshells, and it closes at two for the first shell and eight beyond it.
    Returns (valence, closure).
    """
    electrons = element.electrons(atomic_number)
    outermost = max(state[0] for state, _ in electrons)
    valence = sum(1 for state, _ in electrons if state[0] == outermost and state[1] in (0, 1))
    closure = 2 if outermost == 1 else 8
    return valence, closure


def capacity(valence, closure):
    """The bonds an atom forms: the smaller of the electrons it shares and the holes it fills."""
    return min(valence, closure - valence)


def hydride(symbol, bonds):
    """The simplest hydride formula for an element that binds `bonds` hydrogens."""
    if bonds == 0:
        return "none"
    if symbol == "H":
        return "H2"
    return "%sH%s" % (symbol, bonds if bonds > 1 else "")


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("\n  ASSEMBLY FROM THE OUTERMOST SHELL. The capacity is min(valence, closure - valence).\n\n")
    out.write("    %-3s %-8s %-8s %-9s %-10s %s\n"
              % ("", "valence", "closure", "capacity", "hydride", "known as"))
    for atomic_number in range(1, LAST_MAIN_GROUP + 1):
        symbol = element.symbol(atomic_number)
        valence, closure = outermost_valence(atomic_number)
        bonds = capacity(valence, closure)
        name = HYDRIDE_NAMES.get(symbol, "")
        out.write("    %-3s %-8d %-8d %-9d %-10s %s\n"
                  % (symbol, valence, closure, bonds, hydride(symbol, bonds), name))

    out.write("\n  the capacity is the vector magnitude the outermost shell carries, and it dictates how\n")
    out.write("  many hydrogens the simplest hydride holds. The same capacity gives the bond order of the\n")
    out.write("  elements that pair off as gases: H2 single, N2 triple, O2 double, F2 and Cl2 single. The\n")
    out.write("  duet and the octet are the shell closures the measure stage found, and the bond count is\n")
    out.write("  the deficit to them, an integer, read from the ledger with no tolerance.\n")
    out.write("  Beyond argon a d electron arrives and the valence stops being one magnitude; this stops\n")
    out.write("  at element %d and says so.\n\n" % LAST_MAIN_GROUP)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
