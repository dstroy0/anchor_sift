#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Two instruments, and the change that moves one of them and not the other.
#
#   Usage:  python examples/any_corpus/4_measure/which_corpora_read_their_numbering.py corpus.sym [more ...]
#
# The two instruments in this work disagree on the same corpora. Alphabetic text departs strongly on
# the gap measure and reads near zero in the bit volume, while a picture reads strongly in the
# volume. Renumbering the symbols settles which is which, and the answer can be argued before it is
# measured.
#
# The gap measure reads only where each symbol falls, so renaming the symbols cannot move it at all.
# It is invariant to renumbering by construction, and any movement in its column is a defect in this
# script. The bit volume reads the correlation of bit positions, which is a statement about the
# numbers themselves, so renumbering can move it and on a picture it does. Two instruments where one
# is invariant to a change the other is not cannot be measuring one quantity, and the attempt to
# have the volume subsume the gap measure was the wrong shape from the start.
#
# What singles out the moving corpora took three tries. Ordered values was wrong, since recorded
# speech is as ordered as a greyscale level and holds. Nearness between neighbors was wrong on its
# own, since speech sits at 0.54 and whale song at 0.48 and only one of them moves. What the movers
# have is long stays: a picture is flat regions with edges between them, and speech has small steps
# and never stays anywhere because articulation never stops moving.
#
# Two defects in the measuring are worth carrying, because both produced confident wrong numbers. A
# band fixed in levels is wide for a corpus using few and narrow for one using many, which read a
# picture spread over 160 levels as having no stays while it had the strongest dependence in the
# set. And a distance in standard deviations is meaningless where the spread is near zero.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.dispersion import rare_half  # noqa: E402
from measure.stays import abruptness, band_for, mean_stay  # noqa: E402
from representation.bit_volume import gray_bits, spectrum_gap  # noqa: E402

CAP = 120000
WIDTH = 32
DRAWS = 8
SEED = 0x51F7


def volume(values):
    """The excess of the bit correlation spectrum over the permuted null, at one window width."""
    live = spectrum_gap(gray_bits(values), WIDTH, numpy.random.default_rng(SEED))
    shuffled = values.copy()
    numpy.random.default_rng(SEED).shuffle(shuffled)
    dead = spectrum_gap(gray_bits(shuffled), WIDTH, numpy.random.default_rng(SEED))
    if (live is None) or (dead is None):
        return None
    return live - dead


def main():
    if len(sys.argv) < 2:
        print("usage: which_corpora_read_their_numbering.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-14s %-14s %-9s %-9s %s\n"
              % ("corpus", "gap: given", "gap: renumbered", "stay", "abrupt", "volume verdict"))

    rng = numpy.random.default_rng(SEED)
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            values = numpy.frombuffer(handle.read(CAP), dtype=numpy.uint8).copy()
        if len(values) < 20000:
            continue

        given_gap = rare_half(bytes(values))
        given_volume = volume(values)
        if (given_gap is None) or (given_volume is None):
            continue

        drawn_gap = []
        drawn_volume = []
        for _ in range(DRAWS):
            renumbered = rng.permutation(256).astype(numpy.uint8)[values]
            one = rare_half(bytes(renumbered))
            two = volume(renumbered)
            if one is not None:
                drawn_gap.append(one)
            if two is not None:
                drawn_volume.append(two)
        if (len(drawn_gap) < 3) or (len(drawn_volume) < 3):
            continue

        scatter = float(numpy.std(drawn_volume))
        distance = (abs(given_volume - float(numpy.mean(drawn_volume))) / scatter
                    if scatter > 0.0 else float("inf"))
        stay = mean_stay(values, band_for(values))

        out.write("  %-26s %-14.4f %-14.4f %-9.2f %-9.4f %s\n"
                  % (os.path.basename(path)[:-4], given_gap, float(numpy.mean(drawn_gap)),
                     stay, abruptness(values),
                     "reads the numbering, %.1f sd" % distance if distance >= 3.0
                     else "blind to it"))

    out.write("\n  the two gap columns have to agree. Any difference between them is a defect\n")
    out.write("  in this script and never a finding, since renaming symbols cannot move a\n")
    out.write("  reading of where they fall\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
