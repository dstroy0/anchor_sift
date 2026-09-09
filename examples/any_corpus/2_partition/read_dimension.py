#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-2-002
#
# Recover how many dimensions a set has from a single line drawn through it, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python examples/any_corpus/2_partition/read_dimension.py
#
# Reading a set of n dimensions along a curve returns its exponent divided by n, which is only useful to
# someone already holding one of the two numbers. The question here is whether the line carries the
# dimension count on its own, with no width supplied, no exponent supplied, and no access to the set.
#
# The first attempt looked for a repeat spaced n doublings apart, sampled eight times per doubling, and
# found nothing at any dimension: every field returned the same period, which was the lowest the search
# allowed and therefore the leftover trend and not a repeat. The reason it found nothing is that it was
# looking for the wrong shape and sampling away the right one.
#
# What the index actually carries is one magnitude per dimension. Interleaving gives bit zero to the first
# axis, bit one to the second, bit n back to the first. A step of exactly two to the k crosses a bit
# belonging to axis k modulo n, and the roughness at that step is that axis's own. There are n such
# magnitudes and they only exist at the exact powers of two, which sampling between them destroys.
#
# So the roughness is read at the powers of two alone, the straight part is subtracted, and what is left
# is sorted into groups by the step's position modulo each candidate count. The count that sorts them
# into the most consistent groups is the answer. Nothing about the field is supplied, and two exponents
# are run at each dimension, which shows up a count that follows the field instead of the set.

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

from partition.curves import hilbert_order, interleave  # noqa: E402
from partition.dimension_count import CANDIDATES, best_count, roughness  # noqa: E402
from reference.fields import stretched  # noqa: E402

SEED = 0x51F7
SIDES = {2: 512, 3: 64, 4: 24}
TARGETS = (2.0, 3.0)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Predicted before measuring: the count that groups the magnitudes is the dimension.\n\n")
    out.write("  %-6s %-8s %-9s %-8s %-8s %-9s %s\n"
              % ("dims", "asked", "curve", "found", "score", "runner up", "verdict"))

    rng = numpy.random.default_rng(SEED)
    hits = 0
    total = 0
    for dims in sorted(SIDES):
        walk = hilbert_order(SIDES[dims], dims)
        for target in TARGETS:
            field = stretched(dims, SIDES[dims], target, rng)
            if field is None:
                continue
            for label, series in (("hilbert", field.reshape(-1)[walk]),
                                  ("interleaved", interleave(field))):
                found, score, scored = best_count(roughness(series), rng)
                total += 1
                if found is None:
                    out.write("  %-6d %-8.2f %-9s %s\n" % (dims, target, label, "nothing to score"))
                    continue
                hits += 1 if found == dims else 0
                runner = ("%d at %.2f" % (scored[1][1], scored[1][0])) if len(scored) > 1 else "none"
                out.write("  %-6d %-8.2f %-9s %-8d %-8.2f %-9s %s\n"
                          % (dims, target, label, found, score, runner,
                             "correct" if found == dims else "wrong"))

    out.write("\n  %d of %d readings recovered the dimension count from the line alone\n" % (hits, total))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
