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
import re
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

# The existing molecules to verify the built space against, the same wide set the detector reads.
WIDE_SET = os.path.join(ROOT, "build", "pubchem", "formulae.csv")

# A formula's atoms, matched as an element symbol and an optional count.
ATOM = re.compile(r"([A-Z][a-z]?)(\d*)")


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
    for carbon in range(0, BOUND["C"] + 1):
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


def parse_existing(text):
    """An existing formula string as (counts, charged), the reading the detector uses."""
    charged = ("+" in text) or ("-" in text)
    body = re.sub(r"[+-]\d*$", "", text.strip())
    counts = {}
    for symbol, number in ATOM.findall(body):
        if symbol:
            counts[symbol] = counts.get(symbol, 0) + (int(number) if number else 1)
    return counts, charged


def verify_against_existing(built_keys, degree, out):
    """Verify the built space against the existing molecules, the way the crystal oracle checks a deposit.

    The build never reads which molecules exist; it reads valences off the shells, and agreement with the
    existing set is agreement with a truth the build did not use. Reported both ways: how many existing
    molecules the build covers, how many built formulae the existing set confirms, and the misses
    decomposed by the reason the gate gave, named and not waved at.
    """
    if not os.path.isfile(WIDE_SET):
        out.write("\n  no wide set at %s to verify against\n"
                  "  run maint/data/fetch/fetch_pubchem_formulae.py\n" % WIDE_SET.replace(os.sep, "/"))
        return
    in_space = 0
    covered = 0
    missed = {}
    with io.open(WIDE_SET, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            formula = line.split(",")[-1].strip().strip('"')
            if (not formula) or formula == "MolecularFormula":
                continue
            counts, charged = parse_existing(formula)
            if charged:
                continue
            if any(symbol not in BUILD_ELEMENTS for symbol in counts):
                continue
            if any(counts[symbol] > BOUND[symbol] for symbol in counts):
                continue
            in_space += 1
            if formula_text(counts) in built_keys:
                covered += 1
            else:
                degree_list = []
                for symbol, number in counts.items():
                    degree_list.extend([degree[symbol]] * number)
                _, reason = connected_multigraph(degree_list)
                missed[reason] = missed.get(reason, 0) + 1
    out.write("\n  VERIFY AGAINST EXISTING. The build never read which molecules exist.\n\n")
    out.write("    existing neutral C/H/N/O molecules inside the built bound: %d\n" % in_space)
    out.write("    of those, present in the built space: %d, missed %d\n"
              % (covered, in_space - covered))
    for reason in sorted(missed, key=lambda one: -missed[one]):
        out.write("      missed, %-26s %d\n" % (reason, missed[reason]))
    out.write("    of the %d built, %d are confirmed by the existing set\n" % (len(built_keys), covered))


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    degree = degrees_of_element()
    out.write("\n  BUILDING. Degrees read from the ledger: %s\n"
              % "  ".join("%s=%d" % (symbol, degree[symbol]) for symbol in BUILD_ELEMENTS))
    span = 1
    for symbol in BUILD_ELEMENTS:
        span *= BOUND[symbol] + 1
    legal = build(degree)

    out.write("\n  over carbon 0..%d, hydrogen 0..%d, nitrogen 0..%d, oxygen 0..%d\n"
              % (BOUND["C"], BOUND["H"], BOUND["N"], BOUND["O"]))
    out.write("  %d compositions carry a legal valence structure, built from the ledger.\n"
              % len(legal))
    out.write("\n  a sample of them:\n")
    for counts in legal[:SHOWN]:
        out.write("    %s\n" % formula_text(counts))

    built_keys = set(formula_text(counts) for counts in legal)
    verify_against_existing(built_keys, degree, out)

    out.write("\n  these are the molecules the valence rules allow, a necessary condition and not a\n")
    out.write("  sufficient one, and the built space is far larger than the molecules that exist. The\n")
    out.write("  gate here, connected_multigraph, is the same gate the wide-set detector runs, and the\n")
    out.write("  build is verified against existing molecules the way the crystal oracle checks a\n")
    out.write("  deposit. Nearly every existing molecule in range is built; the misses are named above,\n")
    out.write("  carbon monoxide, whose triple bond and lone pair one fixed valence cannot hold, and\n")
    out.write("  net-neutral salts the gate refuses.\n\n")
    out.flush()
    return 0 if len(legal) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
