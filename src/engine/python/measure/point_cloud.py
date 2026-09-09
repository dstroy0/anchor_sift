#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# One reduction for a cloud of points carrying values, whatever domain the cloud came from.
#
#   Usage:  from measure.point_cloud import reduce_sequence, reduce_cloud
#
# Two instruments were in use here and three separate claims merged them. Both return a ratio near
# one for nothing and a departure for something, and a row in a table does not record which of them
# produced it. The cause was that each domain got its own reader: a sequence for text, a raster for a
# picture, a voxel grid for a structure.
#
# None of that is necessary. Every corpus here is already a cloud of points carrying values. Text is
# positions along a line holding symbols, sound is the same holding amplitudes, a picture is
# positions on a plane, a structure is positions in space. Writing them all that way leaves one
# instrument.
#
# The reduction is a sum over vectors. Each point takes the displacement to the nearest point holding
# the same value, and those displacements are summed in two ways, because one of them cancels and the
# other does not. Their lengths give a spread. Their directions cancel when summed straight, since if
# one point reaches its neighbor then that neighbor usually reaches back and the two vectors are
# opposite, so the directions are summed as outer products instead, which are unchanged when a vector
# flips sign. That sum is the orientation tensor and its eigenvalues report whether the displacements
# share a direction.
#
# On a line there is only one direction and the tensor is constant, leaving the orientation channel
# undefined below two dimensions. It is reported as absent instead of as zero. The length channel is
# defined everywhere. The null is the same one used throughout: the values are permuted over the
# points and every coordinate stays.
#
# The rare half is what gets reported, for the reason the dispersion measure states: under a Zipf
# distribution the head carries the token count and the tail carries the information.

import numpy

# Occurrences a value needs before its neighbor distances carry a statistic.
MIN_OCCURRENCES = 32

# Values that must clear the occurrence floor before a corpus is scored at all.
MIN_VALUES = 8

# Points compared per value. The comparison count is quadratic in the points, and a large group is
# therefore sampled down. A thinner set puts neighbors further apart. The null is sampled the same
# way, and the bias divides out of the ratio.
SAMPLE = 600

# The seed the recorded figures were taken at.
SEED = 0x51F7


def groups_by_value(values, width):
    """Split point indices by the value each point carries, each group left in ascending order."""
    counts = numpy.bincount(values, minlength=width)
    order = numpy.argsort(values, kind="stable")
    edges = numpy.concatenate(([0], numpy.cumsum(counts)))
    return [order[edges[value]:edges[value + 1]] for value in range(width)], counts


def spread_1d(spots, least=MIN_OCCURRENCES):
    """Coefficient of variation of the distance from each point to its nearest neighbor on a line."""
    if len(spots) < least:
        return None
    steps = numpy.diff(spots.astype(numpy.float64))
    # Interior points take the closer of their two neighbors; the two ends have only one
    nearest = numpy.empty(len(spots), dtype=numpy.float64)
    nearest[0] = steps[0]
    nearest[-1] = steps[-1]
    if len(spots) > 2:
        nearest[1:-1] = numpy.minimum(steps[:-1], steps[1:])
    mean = nearest.mean()
    return (nearest.std() / mean) if mean > 0.0 else None


def nearest_nd(points, rng, sample=SAMPLE, least=MIN_OCCURRENCES):
    """Nearest neighbor displacements within one value's points, in any number of dimensions.

    Returns the displacement vectors and their lengths, or None where too few points survive.
    """
    if len(points) < least:
        return None
    if len(points) > sample:
        points = points[rng.choice(len(points), sample, replace=False)]
    offsets = points[:, None, :] - points[None, :, :]
    lengths = numpy.sqrt((offsets * offsets).sum(axis=2))
    numpy.fill_diagonal(lengths, numpy.inf)
    picked = lengths.argmin(axis=1)
    best = lengths[numpy.arange(len(points)), picked]
    alive = numpy.isfinite(best) & (best > 0.0)
    if alive.sum() < least:
        return None
    return offsets[numpy.arange(len(points)), picked][alive], best[alive]


def reduce_sequence(values, width, seed=SEED, least=MIN_OCCURRENCES, need=MIN_VALUES):
    """The rare half of the values on a line, against a permutation of the values over the points.

    Returns (rare half mean, values scored), or None where too few values cleared the floor.
    """
    live_groups, counts = groups_by_value(values, width)

    shuffled = values.copy()
    numpy.random.default_rng(seed).shuffle(shuffled)
    dead_groups, _ = groups_by_value(shuffled, width)

    sizes = []
    ratios = []
    for value in range(width):
        if counts[value] < least:
            continue
        live = spread_1d(live_groups[value], least)
        dead = spread_1d(dead_groups[value], least)
        if (live is None) or (dead is None) or (live <= 0.0):
            continue
        sizes.append(counts[value])
        ratios.append(dead / live)
    if len(ratios) < need:
        return None

    order = numpy.argsort(numpy.asarray(sizes))
    rare = numpy.asarray(ratios)[order][:len(ratios) // 2]
    return float(rare.mean()), len(ratios)


def reduce_cloud(coords, values, width, dims, seed=SEED, least=MIN_OCCURRENCES, need=MIN_VALUES):
    """Both channels over a cloud in two or more dimensions, against the same permutation null.

    Returns (rare half of the length channel, values scored, orientation channel), where the
    orientation channel is None if no value gave a scorable tensor. Returns None where too few
    values cleared the occurrence floor.
    """
    live_groups, counts = groups_by_value(values, width)
    shuffled = values.copy()
    numpy.random.default_rng(seed).shuffle(shuffled)
    dead_groups, _ = groups_by_value(shuffled, width)

    rng = numpy.random.default_rng(seed)
    sizes = []
    length_ratios = []
    tensor_ratios = []
    for value in range(width):
        if counts[value] < least:
            continue
        live = nearest_nd(coords[live_groups[value]], rng, least=least)
        dead = nearest_nd(coords[dead_groups[value]], rng, least=least)
        if (live is None) or (dead is None):
            continue

        live_spread = live[1].std() / live[1].mean() if live[1].mean() > 0.0 else 0.0
        dead_spread = dead[1].std() / dead[1].mean() if dead[1].mean() > 0.0 else 0.0
        if live_spread <= 0.0:
            continue
        sizes.append(counts[value])
        length_ratios.append(dead_spread / live_spread)

        # Directions summed as outer products, which survive a sign flip where a plain sum cancels
        live_units = live[0] / live[1][:, None]
        dead_units = dead[0] / dead[1][:, None]
        live_top = numpy.linalg.eigvalsh(live_units.T @ live_units / len(live_units))[-1]
        dead_top = numpy.linalg.eigvalsh(dead_units.T @ dead_units / len(dead_units))[-1]
        floor = 1.0 / dims
        live_bias = (live_top - floor) / (1.0 - floor)
        dead_bias = (dead_top - floor) / (1.0 - floor)
        if dead_bias > 0.0:
            tensor_ratios.append(live_bias / dead_bias)

    if len(length_ratios) < need:
        return None
    order = numpy.argsort(numpy.asarray(sizes))
    rare = numpy.asarray(length_ratios)[order][:len(length_ratios) // 2]
    bias = float(numpy.mean(tensor_ratios)) if tensor_ratios else None
    return float(rare.mean()), len(length_ratios), bias
