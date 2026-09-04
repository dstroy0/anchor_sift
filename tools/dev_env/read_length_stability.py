#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Replace a statistic that grows with the amount of data read, for Section 4.11 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/read_length_stability.py
#
# Every dependence figure in this work so far is a distance in standard deviations of the renumbered
# readings, and reading five times as much of one file moved a painting from 20.6 to 122.8. Nothing about
# the painting changed. The spread of the renumbered readings is the denominator of that distance and it
# narrows as more data is read, while the reading above it does not, so the distance climbs with the
# length on its own and roughly with its square root.
#
# That makes it a statistic for deciding whether an effect is there and a bad one for saying how large it
# is, and it has been used for the second purpose throughout. A ratio of the reading to the mean of its
# own renumberings has no such denominator and should hold as the length grows.
#
# Both are computed here at four read lengths on the same files. The distance is expected to climb and the
# ratio to hold. If the ratio also climbs then something in the measurement grows with length and neither
# number describes the corpus.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from abruptness import volume_at

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
DRAWS = 8
LENGTHS = (75000, 150000, 300000, 600000)

MEASURE = (
    "art_seurat.sym",
    "art_starry.sym",
    "art_hokusai.sym",
    "art_turner.sym",
    "art_vermeer.sym",
)


def both_ways(values, rng):
    """The distance in standard deviations and the ratio to the renumbered mean, from one reading."""
    given = volume_at(values)
    if given is None:
        return None, None
    drawn = []
    for _ in range(DRAWS):
        drawn.append(volume_at(rng.permutation(256).astype(numpy.uint8)[values]))
    drawn = numpy.asarray([value for value in drawn if value is not None])
    if len(drawn) < 3:
        return None, None
    middle = float(drawn.mean())
    spread = float(drawn.std())
    distance = (abs(given - middle) / spread) if spread > 0.0 else None
    ratio = (given / middle) if middle != 0.0 else None
    return distance, ratio


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    header = "  ".join("%9d" % length for length in LENGTHS)
    out.write("  distance in standard deviations, which is expected to climb with the length\n")
    out.write("  %-18s %s\n" % ("corpus", header))

    gathered = []
    for name in MEASURE:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-18s not present\n" % name[:-4])
            continue
        with open(path, "rb") as handle:
            whole = numpy.frombuffer(handle.read(), dtype=numpy.uint8)
        if len(whole) < LENGTHS[-1]:
            out.write("  %-18s holds %d bytes, short of %d\n"
                      % (name[:-4], len(whole), LENGTHS[-1]))
            continue

        distances = []
        ratios = []
        rng = numpy.random.default_rng(SEED)
        for length in LENGTHS:
            distance, ratio = both_ways(whole[:length].copy(), rng)
            distances.append(distance)
            ratios.append(ratio)
        gathered.append((name[:-4], distances, ratios))
        out.write("  %-18s %s\n"
                  % (name[:-4], "  ".join("%9s" % ("%.1f" % value if value is not None else "none")
                                          for value in distances)))

    out.write("\n  ratio to the renumbered mean, which has no denominator that narrows\n")
    out.write("  %-18s %s\n" % ("corpus", header))
    for label, _, ratios in gathered:
        out.write("  %-18s %s\n"
                  % (label, "  ".join("%9s" % ("%.2f" % value if value is not None else "none")
                                      for value in ratios)))

    # Spread across the four lengths divided by the middle of them, so the two are compared on one scale
    out.write("\n  %-18s %-22s %s\n" % ("corpus", "distance, spread share", "ratio, spread share"))
    for label, distances, ratios in gathered:
        clean_distance = numpy.asarray([value for value in distances if value is not None])
        clean_ratio = numpy.asarray([value for value in ratios if value is not None])
        if (len(clean_distance) < 3) or (len(clean_ratio) < 3):
            continue
        out.write("  %-18s %-22.3f %.3f\n"
                  % (label,
                     float(clean_distance.std() / abs(clean_distance.mean())),
                     float(clean_ratio.std() / abs(clean_ratio.mean()))))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
