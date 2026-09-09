#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-2-001
#
# What a set of n dimensions costs when it is carried through one, against a known answer.
#
#   Usage:  python examples/any_corpus/2_partition/carrying_dimensions_through_one.py
#
# Every reading behind this until now was of a painting, where the plane is the only authority on
# what the answer should be and there is nothing independent to catch a wrong one. Shaping white
# noise in the frequency domain gives a field built to a chosen exponent, so the answer exists before
# the measurement and a wrong reading cannot be argued into agreement afterward.
#
# Two curves are compared because they fail differently. Interleaving jumps whenever it crosses a
# block boundary, and a jump puts a step into the reading that no part of the field put there. A
# Hilbert curve never jumps, since consecutive positions along it are always neighbors. The
# difference between them is what the jumps cost and the remainder is what folding costs.
#
# The two do not have one winner. Hilbert is the better reading of the
# exponent and the worse reading of the dimension count, because a jump is a block completing and
# which block completes is which axis just turned over.

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

from measure.spectral import exponent, exponent_volume  # noqa: E402
from partition.curves import hilbert_order, interleave  # noqa: E402
from reference.fields import build  # noqa: E402

SEED = 0x51F7
SIDES = {2: 512, 3: 64, 4: 24}
TARGETS = (2.0, 3.0)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-6s %-8s %-11s %-13s %-11s %-11s %s\n"
              % ("dims", "asked", "over the set", "interleaved", "hilbert", "predicted",
                 "left after hilbert"))

    rng = numpy.random.default_rng(SEED)
    jumps = []
    folds = []
    for dims in sorted(SIDES):
        walk = hilbert_order(SIDES[dims], dims) if dims <= 3 else None
        for target in TARGETS:
            field = build(dims, SIDES[dims], target, rng)
            if field is None:
                continue
            over, _ = exponent_volume(field)
            morton, _ = exponent(interleave(field))
            hilbert = None
            if walk is not None:
                hilbert, _ = exponent(field.reshape(-1)[walk])
            if (over is None) or (morton is None):
                continue

            predicted = over / dims
            if hilbert is None:
                out.write("  %-6d %-8.2f %-11.3f %-13.3f %-11s %-11.3f %s\n"
                          % (dims, target, over, morton, "not run", predicted, ""))
                continue
            jumps.append(predicted - morton)
            folds.append(predicted - hilbert)
            out.write("  %-6d %-8.2f %-11.3f %-13.3f %-11.3f %-11.3f %.3f\n"
                      % (dims, target, over, morton, hilbert, predicted, predicted - hilbert))

    if jumps and folds:
        mean_jumps = float(numpy.mean(jumps))
        mean_folds = float(numpy.mean(folds))
        out.write("\n  shortfall while interleaving         %.3f\n" % mean_jumps)
        out.write("  shortfall on a curve that never jumps %.3f\n" % mean_folds)
        if mean_jumps:
            out.write("  share the jumps were responsible for  %.3f\n"
                      % (1.0 - (mean_folds / mean_jumps)))
        out.write("\n  the shortfall left on the better curve is the cost of the folding itself,\n")
        out.write("  and it belongs to reducing dimensions and not to any choice made here\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
