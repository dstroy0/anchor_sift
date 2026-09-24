#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CHM-4-002
#
# A single-period reader recovers a constant recurrence and goes blind on a growing one. The
# periodic recurrence along Z therefore needs its shell boundaries supplied from outside.
#
#   Usage:  python examples/chemistry/4_measure/a_single_period_cannot_see_a_growing_one.py
#
# The engine reads a recurrence in two composed steps that already exist. measure.periodicity finds
# the period by scoring a candidate against its own family of multiples, and a sequence that repeats
# every three is read as three and not as six, a trap caught earlier on protein backbones. Then
# reference.periodic builds the maximum entropy background at that one period, binding each position to
# the positions congruent to it modulo the period. Both steps fix a single period: phase is the index
# modulo P, and there is exactly one P.
#
# A periodic property along Z is not one period. The shell lengths are 2, 8, 8, 18, 18, 32, a sequence
# that grows. No single P puts index-modulo-P on the shell closures, and a reader that must find one
# period cannot land on a moving boundary. This example shows that limit on a synthetic sawtooth, a
# property that ramps inside each segment and resets at every segment start. It reuses the engine's own
# sequence_period and the engine's own shuffle, and it writes no element data: the segment lengths here
# are arbitrary and are deliberately not the shell counts, because the real sequence and the real
# boundaries are the atomic-structure ledger's to supply, in representation/atom, and chemistry consumes
# them.
#
# The partition that makes a growing recurrence legible is fixed in one of three ways the engine's
# partition module names. It is not stipulated, a boundary set picked by judgment, the bounding
# this work forbids. It cannot be estimated from the sequence, because a sweep for one period cannot
# recover a growing one, and that attempt is the trap below. It is supervised, ground truth from outside
# the sample, which the partition module places in oracle. So the shell boundaries are the same kind of
# fact as the bond-length oracle, reached from a second direction: the departure is measured, and the
# partition that makes it readable comes from outside.
#
# Two routes are read and shown able to disagree. Route one is the engine's single-period reader, which
# estimates a period and reports how far its best candidate beat the lags outside that candidate's
# family. Route two is a supervised-partition reader, handed the boundaries and asked whether each
# segment repeats the first, the reading that needs the ledger. On a constant recurrence both
# routes depart from the shuffle. On a growing recurrence route one stays inside the shuffle band while
# route two departs. Neither route is the other twice. The null is drawn, never assumed: the same
# values shuffled by reference.shuffles, and the only quantity reported is the distance to that shuffle.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.periodicity import sequence_period  # noqa: E402
from reference.shuffles import SEED, permuted  # noqa: E402

DRAWS = 200


def sawtooth(segment_lengths):
    """A property that ramps 1..L inside each segment. It resets to 1 exactly at every segment start.

    The segment lengths are the recurrence. A constant list is a constant period; a growing list is the
    shape of a periodic table, where each shell is longer than the last.
    """
    series = []
    for length in segment_lengths:
        series.extend(range(1, length + 1))
    return series


def boundaries_of(segment_lengths):
    """The index each segment starts at, the supervised partition a reader is handed."""
    starts = []
    cursor = 0
    for length in segment_lengths:
        starts.append(cursor)
        cursor += length
    return starts


def single_period_margin(series):
    """Route one: the engine's single-period reader, reporting how far its best period beat the rest.

    A positive margin is a period whose own multiples agree more than the lags outside the family. A
    margin at or below zero is the reader saying no single period is here, whatever period it was forced
    to name.
    """
    _, margin = sequence_period(series)
    return margin if margin is not None else 0.0


def partition_agreement(series, boundaries):
    """Route two: given the boundaries, the fraction of positions where a segment repeats the first.

    Each later segment is compared to the first over the length they share. A recurrence that repeats
    under this partition scores one; a shuffle of the same values scores near chance. The boundaries are
    supervised, supplied from outside, not found in the series.
    """
    edges = list(boundaries) + [len(series)]
    segments = [
        series[edges[index] : edges[index + 1]] for index in range(len(boundaries))
    ]
    reference = segments[0]
    matched = 0
    compared = 0
    for segment in segments[1:]:
        width = min(len(segment), len(reference))
        for offset in range(width):
            compared += 1
            matched += 1 if segment[offset] == reference[offset] else 0
    return matched / compared if compared else 0.0


def shuffle_band_margin(series, draws):
    """The single-period margin over `draws` shuffles of the series: the null route one is read against."""
    seats = bytes(series)
    high = 0.0
    for step in range(draws):
        drawn = list(permuted(seats, seed=SEED + step))
        high = max(high, single_period_margin(drawn))
    return high


def shuffle_band_agreement(series, boundaries, draws):
    """The partition agreement over `draws` shuffles: the null route two is read against."""
    seats = bytes(series)
    high = 0.0
    for step in range(draws):
        drawn = list(permuted(seats, seed=SEED + step))
        high = max(high, partition_agreement(drawn, boundaries))
    return high


def read_one(name, segment_lengths, out):
    """Read one sequence by both routes, each against its own drawn null, and report the two departures."""
    series = sawtooth(segment_lengths)
    boundaries = boundaries_of(segment_lengths)

    margin = single_period_margin(series)
    margin_null = shuffle_band_margin(series, DRAWS)
    route_one_departs = margin > margin_null

    agreement = partition_agreement(series, boundaries)
    agreement_null = shuffle_band_agreement(series, boundaries, DRAWS)
    route_two_departs = agreement > agreement_null

    out.write(
        "  %-10s %-8d %8.3f %10.3f %-8s %8.3f %10.3f %-8s\n"
        % (
            name,
            len(series),
            margin,
            margin_null,
            "departs" if route_one_departs else "flat",
            agreement,
            agreement_null,
            "departs" if route_two_departs else "flat",
        )
    )
    return route_one_departs, route_two_departs


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    out.write(
        "  A recurrence read two ways. Route one estimates a single period; route two is handed\n"
    )
    out.write(
        "  the boundaries. Each is read against its own shuffle of the same values.\n\n"
    )
    out.write(
        "  %-10s %-8s %8s %10s %-8s %8s %10s %-8s\n"
        % (
            "sequence",
            "length",
            "margin",
            "null high",
            "route1",
            "agree",
            "null high",
            "route2",
        )
    )

    # Positive control: a constant recurrence. The single-period reader is built for this case. Both
    # routes must depart from the shuffle. Segment length five, repeated enough to read at lag sixteen.
    constant_one, constant_two = read_one("constant", [5] * 16, out)

    # The trap: a growing recurrence. The lengths grow and are not the shell counts. The single-period
    # reader must go flat while the supervised partition departs.
    growing_one, growing_two = read_one("growing", [4, 6, 8, 10, 12, 14, 16], out)

    out.write(
        "\n  positive control: the constant recurrence departs on both routes, %s and %s.\n"
        % (
            "route one " + ("yes" if constant_one else "no"),
            "route two " + ("yes" if constant_two else "no"),
        )
    )
    out.write(
        "  the trap: on the growing recurrence route one is %s and route two is %s. The single\n"
        % (
            "flat" if not growing_one else "departing",
            "departs" if growing_two else "flat",
        )
    )
    out.write(
        "  period cannot see a boundary that moves; the supplied partition can.\n"
    )

    disagree = growing_one != growing_two
    out.write(
        "  two routes, shown able to disagree: on the growing recurrence they %s. Neither route\n"
        % ("disagree" if disagree else "agree")
    )
    out.write("  is the other twice.\n")

    # The whole reading holds when: the constant case departs on both, the growing case is flat on the
    # single period and departs on the partition, and the two routes therefore disagree on the growing
    # case. Anything else means a control did not hold.
    ok = (
        constant_one and constant_two and (not growing_one) and growing_two and disagree
    )
    out.write(
        "\n  %s\n"
        % (
            "every control held."
            if ok
            else "a control did not hold; read the rows above."
        )
    )
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
