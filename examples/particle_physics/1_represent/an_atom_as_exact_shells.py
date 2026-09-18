#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-1-001
#
# Each element becoming its electrons as points carrying values, with no quantum imposed on the state.
#
#   Usage:  python examples/particle_physics/1_represent/an_atom_as_exact_shells.py [Z | symbol ...]
#
# The ledger is read from representation.atom.element, the one transcribed element table. This file is
# the reading over it: it prints what each reading keeps and what it throws away.
#
# The crystallography reader put every site on a 0.25 angstrom grid on the way in, and the recovered
# cell edge then carried the grid instead of the deposit. An atom has the same failure available. An
# electron sits at a quantum state, four numbers: principal, azimuthal, magnetic, spin. A reader that
# keeps only the subshell, the first two, drops the magnetic and spin numbers that tell two electrons
# of one subshell apart.
#
# This reads each element both ways. The exact reading places Z electrons at Z distinct states. The
# subshell reading keeps only the subshell, and a filled 2p then arrives as one address holding six
# electrons where the exact reading holds six.
#
# The difference is a count, and only a count. Both readings agree on the value every electron carries,
# its subshell, and a check that compares values sees nothing: exact.contested returns empty on the
# collapsed reading because the six electrons of a 2p all say "2p" and none disagrees. The loss is in
# the cardinality alone, and exact.placed, a dict, is where the six become one without a word. The
# count is the only place it shows. This reading counts the states and does not lean on the labels
# to disagree. Two electrons at one state is a Pauli violation, and it shows only in the count.
#
# The filling read here is the ideal, Madelung order and Hund's rule, as element.electrons builds it.
# Real atoms deviate, and those measured configurations are the oracle stage, not this one. The
# differentiating electron's group signature recurs down the table, and that recurrence is the periodic
# law the measure stage reads. It is not read here. This stage writes each element down.

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

from representation import exact  # noqa: E402
from representation.atom import element  # noqa: E402

# How many elements are detailed one by one before the run summarizes the rest.
SHOWN = 10


def signature_text(signature):
    """A group signature as text. It prints and sorts the same way twice."""
    azimuthal, population = signature
    return "(%s,%d)" % (element.SUBSHELL[azimuthal], population)


def read_both_ways(electrons):
    """One element's electrons read exactly and read at the subshell, as the two counts and the contest.

    Returns (exact_states, subshell_states, contested_count). exact_states is the distinct quantum
    states, which equals the electron count when Pauli holds. subshell_states is the distinct subshells,
    which is fewer whenever any subshell holds more than one electron. contested_count is what a
    value-comparing check finds on the collapsed reading. It is zero, and the collapse shows only in
    the count.
    """
    exact_states = len(exact.placed(electrons))
    at_subshell = [((state[0], state[1]), subshell) for state, subshell in electrons]
    subshell_states = len(exact.placed(at_subshell))
    contested_count = len(exact.contested(at_subshell))
    return exact_states, subshell_states, contested_count


def one_element(atomic_number, out):
    """Detail one element: what the exact reading keeps, what the subshell reading collapses."""
    electrons = element.electrons(atomic_number)
    exact_states, subshell_states, contested_count = read_both_ways(electrons)
    signature = element.group_signature(electrons)
    _, differentiating = electrons[-1]

    out.write("\n  %-3s Z=%d  %d electron(s)\n"
              % (element.symbol(atomic_number), atomic_number, len(electrons)))
    out.write("    exact states kept %d,  subshell states %d,  collapsed %d\n"
              % (exact_states, subshell_states, len(electrons) - subshell_states))
    out.write("    contested by value on the collapsed reading: %d\n" % contested_count)
    out.write("    differentiating electron %s, group signature %s\n"
              % (differentiating, signature_text(signature)))
    return exact_states == len(electrons)


def summarize(out):
    """Read all of the elements, report Pauli, the collapse, and the group-signature census."""
    census = {}
    pauli_held = 0
    collapsed_total = 0
    contested_total = 0
    for atomic_number in range(1, element.ELEMENT_COUNT + 1):
        electrons = element.electrons(atomic_number)
        exact_states, subshell_states, contested_count = read_both_ways(electrons)
        if exact_states == len(electrons):
            pauli_held += 1
        collapsed_total += len(electrons) - subshell_states
        contested_total += contested_count
        signature = signature_text(element.group_signature(electrons))
        census[signature] = census.get(signature, 0) + 1

    total = element.ELEMENT_COUNT
    out.write("\n  %d element(s) represented, Z 1 to %d\n" % (total, total))
    out.write("  Pauli held, Z distinct states, for %d of %d under the exact reading\n"
              % (pauli_held, total))
    out.write("  the subshell reading collapsed %d electron states across the table,\n"
              % collapsed_total)
    out.write("  and a value-comparing check flagged %d of them\n" % contested_total)

    # Rarity is what the sift stage probes on: magnitude = total - count, larger meaning rarer. The
    # rarest signature goes first. Sorted by magnitude then by text. Two runs print one order.
    out.write("\n  group signatures, rarest first (magnitude = %d - count):\n" % total)
    ranked = sorted(census.items(), key=lambda pair: (-(total - pair[1]), pair[0]))
    for signature, count in ranked:
        out.write("    %-8s count %-3d  magnitude %d\n" % (signature, count, total - count))
    return pauli_held == total


def wanted_numbers(argv):
    """The atomic numbers named on the command line, by Z or by symbol. Empty means detail the first."""
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
    out.write("\n  Each element read twice. The exact reading keeps every electron at its own quantum\n")
    out.write("  state. The subshell reading keeps 2p, which drops the numbers that separate its six\n")
    out.write("  electrons, and the loss is a count the labels never report.\n")

    detail = wanted_numbers(argv)
    if not detail:
        detail = list(range(1, SHOWN + 1))

    shown = 0
    for atomic_number in detail:
        if one_element(atomic_number, out):
            shown += 1

    if shown == 0:
        out.write("\n  nothing represented. Name a Z from 1 to %d or a symbol.\n\n" % element.ELEMENT_COUNT)
        out.flush()
        return 2

    held = summarize(out)
    out.write("\n")
    out.flush()
    return 0 if held else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
