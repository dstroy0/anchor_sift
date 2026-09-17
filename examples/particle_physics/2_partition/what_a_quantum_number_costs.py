#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-2-001
#
# The accumulated electrons read at each quantum number, and what each partition agglomerates.
#
#   Usage:  python examples/particle_physics/2_partition/what_a_quantum_number_costs.py [Z | symbol ...]
#
# A partition is the unit and the scale the points are read at, and a reading is undetermined until it
# is fixed. For an atom the partition is which of the four quantum numbers the reading keeps. Keep all
# four and every electron is its own state, the finest the atom is written at, and no two electrons
# agglomerate. Drop the spin and the two electrons of an orbital fall to one bucket. Drop the magnetic
# number and a subshell's electrons fall together. Drop the principal number and the whole atom is one
# bucket.
#
# The capacity at each level is what Pauli allows there: one electron per spin-orbital, two per orbital,
# 2(2l+1) per subshell, 2n^2 per shell. Those numbers are read off the accumulation here, not put in.
# The max bucket at a partition is the fullest that level's cell ever gets, and it lands on the Pauli
# capacity because the ideal filling packs each cell before opening the next.
#
# Only the full partition keeps every element's electrons distinct. Every coarser partition
# agglomerates, and the count of what it folds is what the coarse reading costs. Exact arithmetic is
# the full partition: infinite discrimination is the reading that never merges two states that differ,
# and it is why an accumulation of fermions stays an accumulation here instead of collapsing.

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

# The partition levels, finest first. Each keeps a prefix of the state (principal, azimuthal, magnetic,
# doubled_spin): four numbers is every electron, then spin drops, then the magnetic number, then the
# subshell, until nothing but the atom is left.
LEVELS = (
    (4, "spin-orbital", "every electron apart"),
    (3, "orbital", "spins folded together"),
    (2, "subshell", "one subshell"),
    (1, "shell", "one shell"),
    (0, "atom", "the whole atom"),
)

# Elements detailed one by one, chosen to span the blocks: hydrogen, carbon, iron, a lanthanide,
# uranium, oganesson.
DETAIL = ("H", "C", "Fe", "Nd", "U", "Og")


def partition_counts(electrons, keep):
    """The accumulated electrons read at a partition keeping `keep` of the four numbers.

    Returns (distinct, fullest), distinct the number of cells the electrons fall into and fullest the
    most electrons any one cell holds. At keep of four every electron is its own cell, so distinct is
    Z and fullest is one. At keep of zero the atom is one cell, so distinct is one and fullest is Z.
    """
    cells = {}
    for state, _ in electrons:
        key = state[:keep]
        cells[key] = cells.get(key, 0) + 1
    return len(cells), max(cells.values())


def one_element(atomic_number, out):
    """Detail one element: how many cells it falls into at each partition, and the fullest cell."""
    electrons = element.electrons(atomic_number)
    out.write("\n  %-3s Z=%d\n" % (element.symbol(atomic_number), atomic_number))
    for keep, name, _ in LEVELS:
        distinct, fullest = partition_counts(electrons, keep)
        out.write("    %-12s %3d cell(s), fullest holds %2d, folded %3d\n"
                  % (name, distinct, fullest, len(electrons) - distinct))


def summarize(out):
    """Sweep the partitions over the whole table: distinct states, the Pauli capacity, what folds."""
    out.write("\n  THE SWEEP. Every element read at each partition.\n\n")
    out.write("    %-12s %-22s %9s %9s %8s\n"
              % ("partition", "tells apart", "distinct", "capacity", "exact"))
    total_electrons = sum(number for number in range(1, element.ELEMENT_COUNT + 1))
    for keep, name, tells in LEVELS:
        distinct_total = 0
        capacity = 0
        kept_whole = 0
        for atomic_number in range(1, element.ELEMENT_COUNT + 1):
            electrons = element.electrons(atomic_number)
            distinct, fullest = partition_counts(electrons, keep)
            distinct_total += distinct
            capacity = max(capacity, fullest)
            if distinct == len(electrons):
                kept_whole += 1
        out.write("    %-12s %-22s %9d %9d %5d/%d\n"
                  % (name, tells, distinct_total, capacity, kept_whole, element.ELEMENT_COUNT))
    out.write("\n  distinct is the states kept summed over the table; the accumulation is %d electrons.\n"
              % total_electrons)
    out.write("  capacity is the fullest one cell ever gets, and it is the Pauli number at that level:\n")
    out.write("  one per spin-orbital, two per orbital, 14 at the f subshell, 32 at the n=4 shell.\n")
    out.write("  exact is how many of the %d elements keep every electron distinct, and only the full\n"
              % element.ELEMENT_COUNT)
    out.write("  partition does. Every coarser one folds an accumulation of fermions into fewer states.\n")


def wanted_numbers(argv):
    """The atomic numbers named on the command line, by Z or by symbol. Empty means the block span."""
    numbers = []
    for token in argv:
        if token.startswith("-"):
            continue
        if token.isdigit():
            candidate = int(token)
            if 1 <= candidate <= element.ELEMENT_COUNT:
                numbers.append(candidate)
            continue
        try:
            numbers.append(element.atomic_number(token))
        except ValueError:
            continue
    return numbers


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("\n  The partition of an atom is which quantum numbers the reading keeps. Keep all four\n")
    out.write("  and every electron stands apart. Drop them one at a time and the accumulation folds.\n")

    detail = wanted_numbers(argv)
    if not detail:
        detail = [element.atomic_number(symbol) for symbol in DETAIL]

    shown = 0
    for atomic_number in detail:
        one_element(atomic_number, out)
        shown += 1

    if shown == 0:
        out.write("\n  nothing to read. Name a Z from 1 to %d or a symbol.\n\n" % element.ELEMENT_COUNT)
        out.flush()
        return 2

    summarize(out)
    out.write("\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
