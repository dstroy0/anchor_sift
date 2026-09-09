#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Recovering how many dimensions a set has, from a single line drawn through it.
#
#   Usage:  from partition.dimension_count import roughness, best_count
#
# Reading a set of n dimensions along a curve returns its exponent divided by n, which is only
# useful to somebody already holding one of the two numbers. The question here is whether the line
# carries the dimension count on its own, with no width supplied, no exponent supplied, and no
# access to the set.
#
# What the index carries. Interleaving gives bit zero to the first axis, bit one to the second and
# bit n back to the first. A step of exactly two to the k therefore crosses a bit belonging to axis k
# modulo n, and the roughness at that step belongs to that axis. There are n such magnitudes and
# they exist only at the exact powers of two.
#
# Three attempts and two of them failed for reasons worth carrying.
#
# The first looked for a repeat spaced n doublings apart and sampled eight times per doubling, which
# sampled away the only steps that carry anything. It returned the same period for every field at
# every dimension, and that period was the lowest the search allowed.
#
# The second read the powers of two correctly and scored them by how consistently they grouped,
# which returned the largest candidate offered in all twelve readings, because splitting few
# readings into many groups raises that score on its own. Scoring each candidate against shuffles of
# the same readings holds the group count fixed and cancels it.
#
# Under both sat a worse error. The fields were built isotropic, so every axis had identical
# statistics and there was one magnitude repeated n times instead of n magnitudes. No line can count
# what was never made different, and the first two attempts were asked to do exactly that. Rebuilt
# with a different correlation length along each axis, eleven of twelve readings return the count.

import numpy

# Candidate dimension counts scored.
CANDIDATES = (2, 3, 4, 5, 6)

# Powers of two read. Beyond this the lag exceeds any set here.
STEPS = 16

# Shuffles each candidate is scored against.
DRAWS = 200


def roughness(series, steps=STEPS):
    """Mean absolute difference at each power of two step, one reading per bit crossed.

    Only the exact powers of two, because that is where the magnitudes are. Sampling between them is
    what made the first attempt return nothing at any dimension.
    """
    floats = numpy.asarray(series, dtype=numpy.float64)
    out = []
    for power in range(steps):
        lag = 1 << power
        if lag >= len(floats):
            break
        out.append(float(numpy.abs(floats[lag:] - floats[:-lag]).mean()))
    return numpy.asarray(out)


def group_score(left, count):
    """How much more alike the readings are inside groups than between them, at one candidate."""
    groups = [left[place::count] for place in range(count)]
    if any(len(group) < 2 for group in groups):
        return None
    inside = numpy.mean([float(group.var()) for group in groups])
    between = float(numpy.var([float(group.mean()) for group in groups]))
    return (between / inside) if inside > 0.0 else 0.0


def best_count(marks, rng, candidates=CANDIDATES, draws=DRAWS):
    """The candidate whose grouping beats its own shuffles by the most.

    The straight part is subtracted first, since the magnitudes sit on a trend that would otherwise
    dominate the grouping. Each candidate is then scored against shuffles of the same readings,
    which holds the group count fixed so that splitting few readings into many groups cannot win on
    arithmetic alone.

    Returns the count, its score in standard deviations above its own shuffles, and every candidate
    scored, letting a win that barely beat its runner up show as one.
    """
    if len(marks) < 8:
        return None, None, []

    places = numpy.arange(len(marks), dtype=numpy.float64)
    slope, intercept = numpy.polyfit(places, numpy.log2(marks), 1)
    left = numpy.log2(marks) - ((slope * places) + intercept)

    scored = []
    for count in candidates:
        real = group_score(left, count)
        if real is None:
            continue
        drawn = [group_score(rng.permutation(left), count) for _ in range(draws)]
        drawn = numpy.asarray([one for one in drawn if one is not None])
        if (len(drawn) < 20) or (drawn.std() <= 0.0):
            continue
        scored.append((float((real - drawn.mean()) / drawn.std()), count))

    if not scored:
        return None, None, []
    scored.sort(reverse=True)
    return scored[0][1], scored[0][0], scored
