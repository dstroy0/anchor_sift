#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Make the regeneration coefficient a property of the corpus and not of its numbering, for Section 4.11 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/canonical_seating.py
#
# How far the values spread orders the share of symbols a reconstruction returns exactly, at rho -1.000
# over fifteen corpora. That makes the spread the coefficient, and it also makes it useless as one,
# because the spread belongs to the numbering. The Iliad returns the least of anything measured at 0.056,
# and the reason is that polytonic Greek needs 141 code points laid across a wide range. The same poem
# under a tighter numbering would return more without a word of it changing.
#
# A quantity that moves when the alphabet is renumbered is not a coefficient of the corpus. The repair is
# to stop reading it at whatever numbering a file arrived in and take the value it converges to, which is
# the smallest spread any numbering can give. That is one number for the corpus, and it is reached and not
# approached, since minimizing a weighted spread over whole positions has a known answer: the most
# frequent symbol takes the middle and the rest go outward in order of frequency, because the spread
# weights each position by how often it is used.
#
# Reported here for every corpus: the spread and the share returned as the file has it, the same two under
# the tightest numbering, and what the numbering was worth. If the two orderings disagree, the earlier
# result was reading numberings and not corpora.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generative_coefficient import BITS, EXTRA, recovered

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 262144


def tightest(series):
    """The corpus renumbered so its values spread as little as any numbering allows.

    The spread weights each position by how often it is used, so the commonest symbol belongs at the
    middle and the rest go outward in order of frequency. Nothing about the sequence changes, only which
    number each symbol carries.
    """
    counts = numpy.bincount(series, minlength=256)
    present = numpy.flatnonzero(counts)
    ordered = present[numpy.argsort(-counts[present])]

    # Positions taken from the middle outward, which is where the weight wants them
    middle = len(ordered) // 2
    places = [middle]
    for step in range(1, len(ordered)):
        if (middle + step) < len(ordered):
            places.append(middle + step)
        if (middle - step) >= 0:
            places.append(middle - step)
    places = places[:len(ordered)]

    seating = numpy.zeros(256, dtype=numpy.uint8)
    for symbol, place in zip(ordered, places):
        seating[symbol] = place
    return seating[series]


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-8s %-9s %-9s %-9s %-9s %s\n"
              % ("corpus", "symbols", "spread", "returned", "tightest", "returned", "gained"))

    names = sorted(name for name in os.listdir(CORPORA)
                   if name.startswith("monkey_") and name.endswith(".sym"))
    gathered = []
    for name in list(names) + list(EXTRA):
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            series = numpy.frombuffer(handle.read(CAP), dtype=numpy.uint8)
        if len(series) < 65536:
            continue

        seated = tightest(series)
        was_spread = float(series.astype(numpy.float64).std())
        now_spread = float(seated.astype(numpy.float64).std())
        was_share, _ = recovered(series, BITS)
        now_share, _ = recovered(seated, BITS)
        distinct = int((numpy.bincount(series, minlength=256) > 0).sum())
        gathered.append((name[:-4], distinct, was_spread, was_share, now_spread, now_share))
        out.write("  %-26s %-8d %-9.2f %-9.3f %-9.2f %-9.3f %.3f\n"
                  % (name[:-4], distinct, was_spread, was_share, now_spread, now_share,
                     now_share - was_share))

    if len(gathered) >= 6:
        def ranked(left, right):
            return float(numpy.corrcoef(numpy.argsort(numpy.argsort(numpy.asarray(left))),
                                        numpy.argsort(numpy.argsort(numpy.asarray(right))))[0, 1])

        was = [row[3] for row in gathered]
        now = [row[5] for row in gathered]
        out.write("\n  the two orderings against each other: rho %.3f\n" % ranked(was, now))
        out.write("  tightest spread against what it returns: rho %.3f\n"
                  % ranked([row[4] for row in gathered], now))
        out.write("  symbols against what the tightest numbering returns: rho %.3f\n"
                  % ranked([float(row[1]) for row in gathered], now))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
