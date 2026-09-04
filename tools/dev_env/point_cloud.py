#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# One representation and one reduction for every corpus in this work, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/point_cloud.py
#
# Two instruments are in use in this work and three separate claims merged them, because both return a
# ratio near one for nothing and a departure for something, so a row in a table does not carry which
# produced it. The cause is that each domain got its own reader: a sequence for text, a raster for a
# picture, a voxel grid for a structure.
#
# None of that is necessary. Every corpus here is already a cloud of points carrying values. Text is
# positions along a line holding symbols, sound is the same holding amplitudes, a picture is positions on
# a plane, a structure is positions in space. Writing them all that way leaves one instrument.
#
# The reduction is a sum over vectors. Each point takes the displacement to the nearest point holding the
# same value, and those displacements are summed in two ways, because one of them cancels and the other
# does not. Their lengths give a spread. Their directions cancel when summed straight, since if one point
# reaches its neighbour then that neighbour usually reaches back and the two vectors are opposite, so the
# directions are summed as outer products instead, which are unchanged when a vector flips sign. That sum
# is the orientation tensor and its eigenvalues report whether the displacements share a direction.
#
# On a line there is only one direction and the tensor is the constant one, so the orientation channel is
# undefined below two dimensions and is reported as absent instead of as zero. The length channel is
# defined everywhere. The null is the one used throughout: the values are permuted over the points and
# every coordinate stays.

import io
import math
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(ROOT, "build", "point_cloud.csv")

CAP = 200000
MIN_OCCURRENCES = 32
MIN_VALUES = 8
SEED = 0x51F7


def groups_by_value(values, width):
    """Split point indices by the value each point carries, each group left in ascending order."""
    counts = numpy.bincount(values, minlength=width)
    order = numpy.argsort(values, kind="stable")
    edges = numpy.concatenate(([0], numpy.cumsum(counts)))
    return [order[edges[value]:edges[value + 1]] for value in range(width)], counts


def spread_1d(spots):
    """Coefficient of variation of the distance from each point to its nearest neighbour on the line."""
    if len(spots) < MIN_OCCURRENCES:
        return None
    steps = numpy.diff(spots.astype(numpy.float64))
    # Interior points take the closer of their two neighbours; the two ends have only one
    nearest = numpy.empty(len(spots), dtype=numpy.float64)
    nearest[0] = steps[0]
    nearest[-1] = steps[-1]
    if len(spots) > 2:
        nearest[1:-1] = numpy.minimum(steps[:-1], steps[1:])
    mean = nearest.mean()
    return (nearest.std() / mean) if mean > 0.0 else None


def reduce_sequence(values, width):
    """The rare half of the values, scored against a permutation of the values over the same points."""
    live_groups, counts = groups_by_value(values, width)

    shuffled = values.copy()
    numpy.random.default_rng(SEED).shuffle(shuffled)
    dead_groups, _ = groups_by_value(shuffled, width)

    sizes = []
    ratios = []
    for value in range(width):
        if counts[value] < MIN_OCCURRENCES:
            continue
        live = spread_1d(live_groups[value])
        dead = spread_1d(dead_groups[value])
        if (live is None) or (dead is None) or (live <= 0.0):
            continue
        sizes.append(counts[value])
        ratios.append(dead / live)
    if len(ratios) < MIN_VALUES:
        return None

    order = numpy.argsort(numpy.asarray(sizes))
    rare = numpy.asarray(ratios)[order][:len(ratios) // 2]
    return float(rare.mean()), len(ratios)


def nearest_nd(points, rng, sample=600):
    """Nearest neighbour displacements within one value's points, in any number of dimensions.

    Sampled, because the comparison count is quadratic in the points. A thinner set puts neighbours
    further apart, and the null is sampled the same way, so the bias divides out of the ratio.
    """
    if len(points) < MIN_OCCURRENCES:
        return None
    if len(points) > sample:
        points = points[rng.choice(len(points), sample, replace=False)]
    offsets = points[:, None, :] - points[None, :, :]
    lengths = numpy.sqrt((offsets * offsets).sum(axis=2))
    numpy.fill_diagonal(lengths, numpy.inf)
    picked = lengths.argmin(axis=1)
    best = lengths[numpy.arange(len(points)), picked]
    alive = numpy.isfinite(best) & (best > 0.0)
    if alive.sum() < MIN_OCCURRENCES:
        return None
    return offsets[numpy.arange(len(points)), picked][alive], best[alive]


def reduce_cloud(coords, values, width, dims):
    """Both channels over a cloud in two or more dimensions, against the same permutation null."""
    live_groups, counts = groups_by_value(values, width)
    shuffled = values.copy()
    numpy.random.default_rng(SEED).shuffle(shuffled)
    dead_groups, _ = groups_by_value(shuffled, width)

    rng = numpy.random.default_rng(SEED)
    sizes = []
    length_ratios = []
    tensor_ratios = []
    for value in range(width):
        if counts[value] < MIN_OCCURRENCES:
            continue
        live = nearest_nd(coords[live_groups[value]], rng)
        dead = nearest_nd(coords[dead_groups[value]], rng)
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

    if len(length_ratios) < MIN_VALUES:
        return None
    order = numpy.argsort(numpy.asarray(sizes))
    rare = numpy.asarray(length_ratios)[order][:len(length_ratios) // 2]
    bias = float(numpy.mean(tensor_ratios)) if tensor_ratios else None
    return float(rare.mean()), len(length_ratios), bias


def load_sequence(path):
    with open(path, "rb") as handle:
        raw = handle.read(CAP)
    return numpy.frombuffer(raw, dtype=numpy.uint8).astype(numpy.int64)


def load_text(path):
    """A text file as points on a line holding characters, which is the only width Chinese survives."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read(CAP)
    # Line endings folded, as everywhere here, so a publisher's wrapping is not measured
    text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
    seating = {}
    for character in text:
        if character not in seating:
            seating[character] = len(seating)
    return numpy.asarray([seating[character] for character in text], dtype=numpy.int64), len(seating)


def load_picture(path):
    """A byte file holding a square picture, reconstructed at the side its length implies."""
    with open(path, "rb") as handle:
        raw = handle.read()
    side = int(math.isqrt(len(raw)))
    if (side * side) != len(raw) or side < 64:
        return None, None
    step = max(1, side // 200)
    grid = numpy.frombuffer(raw, dtype=numpy.uint8).reshape(side, side)[::step, ::step]
    rows, cols = grid.shape
    ys, xs = numpy.mgrid[0:rows, 0:cols]
    coords = numpy.stack([xs.ravel(), ys.ravel()], axis=1).astype(numpy.float64)
    # Quantized so a value recurs often enough to have neighbours of its own
    return coords, (grid.ravel() >> 3).astype(numpy.int64)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    names = sorted(name for name in os.listdir(CORPORA)
                   if name.endswith(".sym") or name.endswith(".txt"))

    rows = []
    for name in names:
        path = os.path.join(CORPORA, name)
        label = name[:-4]
        if os.path.getsize(path) < 20000:
            continue

        if label.startswith("art_") or label.startswith("img_"):
            coords, values = load_picture(path)
            if coords is None:
                continue
            found = reduce_cloud(coords, values, 32, 2)
            if found is None:
                continue
            rows.append((label, 2, len(values), found[1], found[0], found[2]))
            continue

        if name.endswith(".txt"):
            values, width = load_text(path)
        else:
            values, width = load_sequence(path), 256
        if len(values) < 20000:
            continue
        found = reduce_sequence(values, width)
        if found is None:
            continue
        rows.append((label, 1, len(values), found[1], found[0], None))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("corpus,dims,points,values,length,orientation\n")
        for label, dims, points, scored, length, bias in rows:
            handle.write("%s,%d,%d,%d,%.6f,%s\n"
                         % (label, dims, points, scored, length,
                            ("%.6f" % bias) if bias is not None else ""))

    families = {}
    for label, dims, _, _, length, bias in rows:
        families.setdefault(label.split("_")[0], []).append((length, bias, dims))

    out.write("  %-12s %-7s %-5s %-16s %s\n"
              % ("family", "corpora", "dims", "length mean, sd", "orientation"))
    for family in sorted(families):
        members = families[family]
        lengths = numpy.asarray([row[0] for row in members])
        biases = [row[1] for row in members if row[1] is not None]
        out.write("  %-12s %-7d %-5d %-16s %s\n"
                  % (family, len(members), members[0][2],
                     "%.3f, %.3f" % (lengths.mean(), lengths.std()),
                     ("%.3f" % numpy.mean(biases)) if biases else "not defined on a line"))

    # The rare half of a large alphabet is a rarer population than the rare half of a small one, so a
    # channel that tracks the alphabet size is comparing inventories and not corpora
    scored = numpy.asarray([row[3] for row in rows], dtype=numpy.float64)
    lengths = numpy.asarray([row[4] for row in rows], dtype=numpy.float64)
    ranked = numpy.corrcoef(numpy.argsort(numpy.argsort(scored)),
                            numpy.argsort(numpy.argsort(lengths)))[0, 1]
    out.write("\n  alphabet size against the length channel, over %d corpora: rho %.3f\n"
              % (len(rows), ranked))
    out.write("  values scored run %d to %d\n" % (int(scored.min()), int(scored.max())))

    out.write("\n  wrote %s with %d rows\n" % (TARGET, len(rows)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
