#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-4-001
#
# The table read for its period, which is not one number, and the shell closures read off the gaps.
#
#   Usage:  python examples/particle_physics/4_measure/shell_closures_from_the_difference_set.py
#
# The group signatures in atomic number order are a sequence, and the match rate at a lag is how often
# a signature equals the one that many elements ahead. A single period would stand up at one lag and
# its multiples. The periodic table does not: its rows run 2, 8, 8, 18, 18, 32, 32. No one lag
# carries the recurrence, and a reader that reported one period would be wrong for most of the table.
# periodicity.py's header records the same trap from the other side, a period scored against its own
# harmonics; here the harmonics are genuinely different lengths.
#
# What is one number is the gap between closures. A shell closes where a p subshell fills, signature
# (p,6), with helium closing the first row on (s,2). Those closures sit at the noble gases, and the
# differences between them are the row lengths, read off the accumulation with no row told to it. That
# is the crystallography difference-set reading moved to one dimension: a period is a difference
# between two things that agree. The complete candidate set is the differences themselves.
#
# The match rate is read against coincidence_floor, the rate a shuffle of the same signatures reaches
# at any lag. A lag above the floor repeats for a reason the counts do not force; a lag at the floor
# is the census talking to itself. Stage three shuffles and shows the peaks fall to the floor.

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
from representation.atom import element  # noqa: E402

# How many of the tallest lags to list.
SHOWN = 10


def signature_sequence():
    """The group signature of every element in atomic number order, as text symbols for equality."""
    sequence = []
    for atomic_number in range(1, element.ELEMENT_COUNT + 1):
        azimuthal, population = element.group_signature(element.electrons(atomic_number))
        sequence.append("(%s,%d)" % (element.SUBSHELL[azimuthal], population))
    return sequence


def closures():
    """The atomic numbers where a shell closes: a full p subshell, with helium closing the first row.

    Read off the signatures, not a table of noble gases. A closed p subshell reads (p,6); helium fills
    1s and reads (s,2) at Z 2, the one row with no p. Returns the closure positions in order.
    """
    found = []
    for atomic_number in range(1, element.ELEMENT_COUNT + 1):
        azimuthal, population = element.group_signature(element.electrons(atomic_number))
        subshell = element.SUBSHELL[azimuthal]
        if (subshell == "p" and population == 6) or atomic_number == 2:
            found.append(atomic_number)
    return found


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    sequence = signature_sequence()
    if not sequence:
        out.write("\n  no signatures to read.\n\n")
        out.flush()
        return 2

    floor = coincidence_floor(sequence)
    rates = match_rate_at_lag(sequence)

    out.write("\n  THE MATCH RATE. How often a signature equals the one `lag` elements ahead.\n\n")
    out.write("    a shuffle of these signatures reaches %.3f at any lag; a lag above that repeats\n"
              % floor)
    out.write("    for a reason the counts do not force.\n\n")
    out.write("    %6s %10s %10s\n" % ("lag", "rate", "over floor"))
    tallest = sorted(rates.items(), key=lambda pair: (-pair[1], pair[0]))[:SHOWN]
    for lag, rate in tallest:
        ratio = rate / floor if floor > 0 else 0.0
        out.write("    %6d %10.3f %9.2fx\n" % (lag, rate, ratio))

    out.write("\n  THE CLOSURES. Where a shell fills, and the gaps between, read off the signatures.\n\n")
    closed = closures()
    out.write("    closures at Z: %s\n" % " ".join(str(one) for one in closed))
    gaps = [later - earlier for earlier, later in zip(closed, closed[1:])]
    out.write("    row lengths (the gaps): %s\n" % " ".join(str(one) for one in gaps))
    out.write("    the whole set of closure positions is the periodic table's row structure, and no\n")
    out.write("    single lag above carries it because the rows are not one length.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
