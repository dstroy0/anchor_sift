#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-5-001
#
# The rarest signature as an anchor, and the one candidate period a necessary condition leaves standing.
#
#   Usage:  python examples/particle_physics/5_sift/rarest_anchor_narrows_the_period.py
#
# A sift is a necessary condition over an index set. A period is a difference between two things that
# agree, the reading the measure stage rests on, so if the sequence has period d then every signature
# that appears sits at two places d apart: d is a difference within that signature's positions. The
# necessary condition for a period is therefore that d belong to the difference set of every signature,
# and the candidates are the lags common to every one of those difference sets. It is all equality, a
# lag either is a difference or it is not, and no tolerance is chosen anywhere.
#
# The anchors are applied by census magnitude, the total less a count, the rarest first, the order the
# sift kernel probes a field in. The rarest signatures are the f-block ones, each at exactly two places,
# the lanthanide and the actinide of one column, thirty two apart. A signature at two places has a
# difference set of one lag, so the rarest anchor cuts the candidates to a single lag in one step, where
# a common anchor would leave many. The magnitude ordering buys that, and it is the steering the
# whole subject holds to: magnitude and equality, and never a bound.
#
# The one surviving candidate is 32, the lanthanide-actinide repeat and the longest row. It is not an
# exact period: the sufficiency check below reads the sequence at that lag and finds hydrogen against
# gallium at the first place, so the table has no period, the result the measure stage read from the
# other side. The necessary condition still did its work, and the rare anchor did most of it.

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

# How many anchors of the cascade to detail.
SHOWN = 8


def signature_sequence():
    """The group signature of every element in atomic number order, as text symbols for equality."""
    sequence = []
    for atomic_number in range(1, element.ELEMENT_COUNT + 1):
        azimuthal, population = element.group_signature(element.electrons(atomic_number))
        sequence.append("(%s,%d)" % (element.SUBSHELL[azimuthal], population))
    return sequence


def anchors_by_magnitude(sequence):
    """The distinct signatures, rarest first, each with its census magnitude, total less its count."""
    total = len(sequence)
    counts = {}
    for symbol in sequence:
        counts[symbol] = counts.get(symbol, 0) + 1
    return sorted(((symbol, total - count) for symbol, count in counts.items()),
                  key=lambda pair: (-pair[1], pair[0]))


def difference_set(sequence, anchor):
    """The lags at which the anchor recurs, the differences between the places it sits.

    A period of the whole sequence has to be one of these for this anchor, because a period carries the
    anchor from a place to the same anchor a period on, which is a difference within its places.
    """
    places = [at for at, symbol in enumerate(sequence) if symbol == anchor]
    return {later - earlier for index, earlier in enumerate(places) for later in places[index + 1:]}


def is_period(sequence, lag):
    """Whether the whole sequence reads the same lag apart, the sufficiency the necessary condition lacks."""
    return all(sequence[at] == sequence[at + lag] for at in range(len(sequence) - lag))


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    sequence = signature_sequence()
    if not sequence:
        out.write("\n  no signatures to sift.\n\n")
        out.flush()
        return 2

    anchors = anchors_by_magnitude(sequence)
    candidates = set(range(1, len(sequence)))

    out.write("\n  THE CASCADE. Candidate periods left standing as each anchor's difference set is met.\n\n")
    out.write("    %-10s %-10s %-9s %s\n" % ("anchor", "magnitude", "survive", "example lags"))
    out.write("    %-10s %-10s %-9d %s\n"
              % ("start", "", len(candidates), "1 .. %d" % (len(sequence) - 1)))
    for anchor, magnitude in anchors[:SHOWN]:
        candidates &= difference_set(sequence, anchor)
        listed = " ".join(str(lag) for lag in sorted(candidates)[:8]) if candidates else "none"
        out.write("    %-10s %-10d %-9d %s\n" % (anchor, magnitude, len(candidates), listed))

    for anchor, _ in anchors[SHOWN:]:
        candidates &= difference_set(sequence, anchor)

    survivors = sorted(candidates)
    out.write("\n  survivors of the necessary condition over every anchor: %s\n"
              % (" ".join(str(lag) for lag in survivors) if survivors else "none"))
    for lag in survivors:
        holds = is_period(sequence, lag)
        out.write("    lag %d as an actual period: %s\n" % (lag, holds))
    out.write("\n  the rarest anchor cut the candidates to one lag in a single step, an f-block signature\n")
    out.write("  at two places 32 apart. That lag is where every signature recurs, but the sequence does\n")
    out.write("  not read the same 32 apart, so the table has no exact period, reached with the rare\n")
    out.write("  anchor doing the work and no tolerance anywhere.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
