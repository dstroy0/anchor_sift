#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-3-001
#
# The periodic recurrence measured against two backgrounds, one keeping the counts and one keeping no
# exclusion, so what Pauli builds is read as the departure from what it does not.
#
#   Usage:  python examples/particle_physics/3_reference/what_exclusion_builds.py
#
# A reference is the background a signal is read against, built by deleting a property from the data.
# Two are drawn here.
#
# The first keeps the census and deletes the order. reference.shuffles.permuted draws a uniform
# arrangement of the same signatures, so every count is exactly preserved and only the accumulation
# order is gone. It is the least committal background consistent with the histogram, and it cannot be
# wrong about the counts because it is the counts. If the recurrence is in the order it falls to the
# floor here; if it is in the census it survives.
#
# The second keeps no exclusion. Fermions accumulate into successive states because Pauli forbids two
# in one; delete that and every electron drops to 1s, and an element is then only a count of electrons
# in one state, with nothing to recur. Its signatures are all distinct, one per element, and its match rate
# is the floor of a set with no repeats. This is the background Doug named: we accumulate here because
# exactness gives infinite discrimination, and Pauli turns that accumulation into shells. Remove the
# exclusion and the table is a ladder.
#
# The positive control is the real accumulation, Madelung order under Hund's rule, and it is the only
# arm carrying the recurrence at 8, 18 and 32 that the two backgrounds lack.

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

from measure.sequence_match import match_rate_at_lag, coincidence_floor  # noqa: E402
from reference.shuffles import permuted  # noqa: E402
from representation.atom import element  # noqa: E402

# The row lengths, the lags the real accumulation repeats at. Read against each background below.
LAGS = (8, 18, 32)


def real_sequence():
    """The group signature of every element in atomic number order, the real accumulation."""
    sequence = []
    for atomic_number in range(1, element.ELEMENT_COUNT + 1):
        azimuthal, population = element.group_signature(element.electrons(atomic_number))
        sequence.append("(%s,%d)" % (element.SUBSHELL[azimuthal], population))
    return sequence


def without_exclusion():
    """The signatures if every electron dropped to 1s: an element is (s, its electron count), all distinct."""
    return ["(s,%d)" % atomic_number for atomic_number in range(1, element.ELEMENT_COUNT + 1)]


def peak(rates):
    """The tallest lag and its rate, for the arm's own high water mark."""
    lag, rate = max(rates.items(), key=lambda pair: (pair[1], -pair[0]))
    return lag, rate


def arm_row(name, sequence, out):
    """One background or the control: its floor, its rate at each row length, and its tallest lag."""
    floor = coincidence_floor(sequence)
    rates = match_rate_at_lag(sequence)
    tall_lag, tall_rate = peak(rates)
    columns = "  ".join("%.3f" % rates.get(lag, 0.0) for lag in LAGS)
    out.write("    %-16s %6.3f   %s   %6.3f @ %d\n"
              % (name, floor, columns, tall_rate, tall_lag))


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    real = real_sequence()
    if not real:
        out.write("\n  no signatures to read.\n\n")
        out.flush()
        return 2

    symbols = sorted(set(real))
    index = {symbol: place for place, symbol in enumerate(symbols)}
    shuffled = permuted(bytearray(index[symbol] for symbol in real))
    ladder = without_exclusion()

    out.write("\n  THE RECURRENCE AGAINST ITS BACKGROUNDS. Match rate at the row lengths 8, 18, 32.\n\n")
    out.write("    %-16s %6s   %5s  %5s  %5s   %s\n"
              % ("arm", "floor", "8", "18", "32", "tallest lag"))
    arm_row("real (Pauli)", real, out)
    arm_row("counts kept", shuffled, out)
    arm_row("no exclusion", ladder, out)

    out.write("\n  The real accumulation stands above its floor at 8, 18 and 32. Keeping the counts and\n")
    out.write("  deleting the order drops those to the floor, so the recurrence is in the order Pauli\n")
    out.write("  fills the shells in and not in the counts. Deleting the exclusion leaves a ladder of\n")
    out.write("  distinct counts with a floor of zero and nothing to recur: no shells, no table.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
