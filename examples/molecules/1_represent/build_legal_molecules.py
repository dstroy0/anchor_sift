#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: MOL-1-002
#
# Building the molecules the valence rules allow, over a composition space, ten thousand and more.
#
#   Usage:  python examples/molecules/1_represent/build_legal_molecules.py
#
# The assembly stage reads the bond count off an atom's shell. This walks the other way: it enumerates
# the compositions of carbon, hydrogen, nitrogen and oxygen within a bound, turns each into the degree
# list its atoms carry, and keeps the ones a molecule graph can hold. Each atom's degree is its capacity
# from assembly_from_atomic_properties, read from element.electrons, and the build takes its valences
# from the ledger and puts none in by hand. The keep decision is connected_multigraph in measure, the
# same gate the wide-set detector runs, and what is built legal and what is detected legal are one test.
#
# The gate is a necessary condition, not sufficient: a built formula is one that could be a molecule,
# not one that is. The space the rules allow is far larger than the molecules that exist, and the point
# of building it is that count and that containment: the real molecules the detector passed all sit
# inside this legal space, because they clear the same gate. Integer arithmetic only, no bound.

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

from measure.graph_realizable import connected_multigraph  # noqa: E402
from representation.atom import element  # noqa: E402

# assembly_from_atomic_properties sits in this directory; its valence reading is the ledger source, and
# building on it keeps one derivation of the bond count, not two.
import assembly_from_atomic_properties as assembly  # noqa: E402

# The elements the space is built over, and the count each ranges up to. Carbon, hydrogen, nitrogen and
# oxygen make the bulk of organic chemistry, and the bounds are wide enough to pass ten thousand legal.
BUILD_ELEMENTS = ("C", "H", "N", "O")
BOUND = {"C": 20, "H": 44, "N": 6, "O": 8}

# How many built formulae to print as a sample.
SHOWN = 12


def degrees_of_element():
    """The bonding degree of each build element, its capacity read from the ledger, not put in."""
    degree = {}
    for symbol in BUILD_ELEMENTS:
        valence, closure = assembly.outermost_valence(element.atomic_number(symbol))
        degree[symbol] = assembly.capacity(valence, closure)
    return degree


def formula_text(counts):
    """A count map as a formula string, element then count, the count dropped when it is one."""
    parts = []
    for symbol in BUILD_ELEMENTS:
        number = counts.get(symbol, 0)
        if number:
            parts.append("%s%s" % (symbol, number if number > 1 else ""))
    return "".join(parts)


def build(degree):
    """Every composition in the bound whose atoms a molecule graph can hold, as a list of count maps."""
    legal = []
    for carbon in range(1, BOUND["C"] + 1):
        for hydrogen in range(0, BOUND["H"] + 1):
            for nitrogen in range(0, BOUND["N"] + 1):
                for oxygen in range(0, BOUND["O"] + 1):
                    counts = {}
                    for symbol, number in (("C", carbon), ("H", hydrogen),
                                           ("N", nitrogen), ("O", oxygen)):
                        if number:
                            counts[symbol] = number
                    degree_list = []
                    for symbol, number in counts.items():
                        degree_list.extend([degree[symbol]] * number)
                    verdict, _ = connected_multigraph(degree_list)
                    if verdict:
                        legal.append(counts)
    return legal


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    degree = degrees_of_element()
    out.write("\n  BUILDING. Degrees read from the ledger: %s\n"
              % "  ".join("%s=%d" % (symbol, degree[symbol]) for symbol in BUILD_ELEMENTS))
    span = 1
    for symbol in BUILD_ELEMENTS:
        span *= BOUND[symbol] + 1
    legal = build(degree)

    out.write("\n  over carbon 1..%d, hydrogen 0..%d, nitrogen 0..%d, oxygen 0..%d\n"
              % (BOUND["C"], BOUND["H"], BOUND["N"], BOUND["O"]))
    out.write("  %d compositions carry a legal valence structure, built from the ledger.\n"
              % len(legal))
    out.write("\n  a sample of them:\n")
    for counts in legal[:SHOWN]:
        out.write("    %s\n" % formula_text(counts))

    out.write("\n  these are the molecules the valence rules allow, a necessary condition and not a\n")
    out.write("  sufficient one, so the built space is far larger than the molecules that exist. The\n")
    out.write("  gate here, connected_multigraph, is the same one the wide-set detector runs, and the\n")
    out.write("  real molecules it passed all sit inside this legal space, cleared by the same test.\n\n")
    out.flush()
    return 0 if len(legal) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
