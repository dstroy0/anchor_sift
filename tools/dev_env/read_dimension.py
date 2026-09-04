#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Recover how many dimensions a set has from a single line drawn through it, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/read_dimension.py
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
# axis, bit one to the second, bit n back to the first, so a step of exactly two to the k crosses a bit
# belonging to axis k modulo n and the roughness at that step is that axis's own. There are n such
# magnitudes and they only exist at the exact powers of two, which sampling between them destroys.
#
# So the roughness is read at the powers of two alone, the straight part is subtracted, and what is left
# is sorted into groups by the step's position modulo each candidate count. The count that sorts them
# into the most consistent groups is the answer. Nothing about the field is supplied, and two exponents
# are run at each dimension so a count that follows the field instead of the set is visible as one.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from curve_floor import hilbert_order
from squash_dimensions import SIDES, TARGETS, build, interleave

SEED = 0x51F7
CANDIDATES = (2, 3, 4, 5, 6)
STEPS = 16


def roughness(series):
    """Mean absolute difference at each power of two step, which is one reading per bit crossed."""
    floats = series.astype(numpy.float64)
    out = []
    for power in range(STEPS):
        lag = 1 << power
        if lag >= len(floats):
            break
        out.append(float(numpy.abs(floats[lag:] - floats[:-lag]).mean()))
    return numpy.asarray(out)


def stretched(dims, side, slope, rng):
    """A field whose correlation length differs along each axis, so the axes are tellable apart.

    An isotropic field has one magnitude repeated, not one per dimension, since every axis is built to
    the same statistics. Nothing can recover a count from readings that are all the same by construction,
    which is what the first two attempts here were asked to do.
    """
    noise = rng.standard_normal((side,) * dims)
    spectrum = numpy.fft.fftn(noise)
    axes = numpy.meshgrid(*[numpy.fft.fftfreq(side) * side] * dims, indexing="ij")
    # Each axis stretched by a different factor, so its bits carry a roughness of their own
    factors = [1.0 + (2.0 * place) for place in range(dims)]
    radius = numpy.sqrt(sum((axis / factor) ** 2 for axis, factor in zip(axes, factors)))
    radius[(0,) * dims] = 1.0
    shaped = spectrum * (radius ** (-slope / 2.0))
    shaped[(0,) * dims] = 0.0
    field = numpy.real(numpy.fft.ifftn(shaped))
    spread = field.std()
    if spread <= 0.0:
        return None
    scaled = (field - field.mean()) / spread
    return numpy.clip(numpy.rint((scaled * 42.0) + 128.0), 0, 255).astype(numpy.uint8)


def group_score(left, count):
    """How much more alike the readings are inside groups than between them, at one candidate count."""
    groups = [left[place::count] for place in range(count)]
    if any(len(group) < 2 for group in groups):
        return None
    inside = numpy.mean([float(group.var()) for group in groups])
    between = float(numpy.var([float(group.mean()) for group in groups]))
    return (between / inside) if inside > 0.0 else 0.0


def best_count(marks, rng, draws=200):
    """The candidate whose grouping beats its own shuffles by the most.

    Splitting few readings into many groups raises the score on its own, which had every field returning
    the largest candidate offered. Shuffling the readings and scoring the same candidate the same way
    holds the group count fixed, so what is left is whether the order carries anything.
    """
    if len(marks) < 8:
        return None, None, []
    places = numpy.arange(len(marks), dtype=numpy.float64)
    slope, intercept = numpy.polyfit(places, numpy.log2(marks), 1)
    left = numpy.log2(marks) - ((slope * places) + intercept)

    scored = []
    for count in CANDIDATES:
        real = group_score(left, count)
        if real is None:
            continue
        drawn = []
        for _ in range(draws):
            drawn.append(group_score(rng.permutation(left), count))
        drawn = numpy.asarray([value for value in drawn if value is not None])
        if (len(drawn) < 20) or (drawn.std() <= 0.0):
            continue
        scored.append((float((real - drawn.mean()) / drawn.std()), count))
    if not scored:
        return None, None, []
    scored.sort(reverse=True)
    return scored[0][1], scored[0][0], scored


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
