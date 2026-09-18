#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CEL-2-001
#
# Whether a sub-pixel displacement survives the pixel grid, on fields whose answer is known.
#
#   Usage:  python examples/cell_tracking/2_partition/what_a_pixel_costs.py
#
# THE PREDICTION THIS TESTS, AND WHERE IT COMES FROM. examples/crystallography/2_partition measures
# that a period which is not a whole number of voxels is not destroyed by the grid: successive tiles
# land alternately on the two lags straddling it, and the share of agreement at the upper one carries
# the fraction between them. Read that way a published cell edge came back to 0.0006 angstroms
# against a voxel of 0.25. A cell's displacement between two frames is not a whole number of pixels
# either, and theory_bucket/cell_tracking predicts the same relation carries the same remainder.
#
# WHY THAT PREDICTION IS NOT ENTAILED, WHICH IS THE REASON TO MEASURE IT. The crystal mechanism needs
# a repeating tile: the fraction accumulates because tile after tile lands at a shifting phase, and
# the proportion is read over many of them. Two frames supply one displacement and no tile series at
# all. What carries the fraction here, if anything does, is the relative agreement of the two
# straddling lags on a single pair, which is a different mechanism wearing the same arithmetic. It
# may hold, it may hold with a bias, or it may not hold. This file is built so that each of those
# three gives a different picture, and so none of them can be reported as either of the others.
#
# THE ANSWER EXISTS BEFORE THE MEASUREMENT. Every field here is displaced by an amount this file
# chose, using a Fourier shift, which moves a band-limited field by a real number exactly. So the truth is not an annotation and not a reading: it is an
# input. theory/workbook records that a positive control with a known answer is what the permutation
# null measure has never had, and what the spectral exponent got by building fields to a chosen
# exponent and reading them back. This is that arrangement for displacement.
#
# WHAT IS NOT TESTED HERE. Real cells. This field is blobs on a flat background with no division, no
# occlusion, no intensity drift and no noise beyond what is added on purpose. A pass here is a
# necessary condition for the method to work on microscopy and is nowhere near a sufficient one.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(
    os.path.join(ROOT, "src", "engine")
):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

SEED = 0x51F7

# Field size in pixels. Square. One axis carries the displacement and the other is a control that
# should read zero.
SIDE = 256

# How many blobs, and how wide each one is. A cell nucleus in the 2D challenge sets runs tens of
# pixels across against fields of several hundred, and these are chosen to sit in that ratio.
BLOBS = 40
BLOB_WIDTH = 6.0

# Levels the field is quantized to before agreement is measured. Agreement is a share of positions
# carrying the same value. A continuous field has to be given values it can carry. 32 is the
# figure theory/workbook settles on for envelopes, where a finer slice leaves too few occurrences per
# level to clear the floor.
LEVELS = 32

# True displacements swept along one axis, in pixels. Whole numbers are included on purpose: the
# fraction at 3.0 and 4.0 has to come back near zero or the reading is inventing one.
TRUTHS = (3.0, 3.1, 3.25, 3.4, 3.5, 3.6, 3.75, 3.9, 4.0)


def field(rng):
    """A flat background carrying `BLOBS` Gaussian blobs, as a float array."""
    rows, columns = numpy.mgrid[0:SIDE, 0:SIDE]
    canvas = numpy.zeros((SIDE, SIDE), dtype=numpy.float64)
    for _ in range(BLOBS):
        # Kept off the border by two widths so a shift never wraps a blob through the edge.
        centre_row = rng.uniform(3.0 * BLOB_WIDTH, SIDE - 3.0 * BLOB_WIDTH)
        centre_column = rng.uniform(3.0 * BLOB_WIDTH, SIDE - 3.0 * BLOB_WIDTH)
        brightness = rng.uniform(0.5, 1.0)
        canvas += brightness * numpy.exp(
            -(((rows - centre_row) ** 2) + ((columns - centre_column) ** 2))
            / (2.0 * BLOB_WIDTH * BLOB_WIDTH)
        )
    return canvas


def shifted(canvas, distance, axis):
    """`canvas` moved by a real `distance` along `axis`, by phase ramp and not by interpolation.

    A band-limited field shifted in the frequency domain moves by exactly the distance asked for.
    Interpolating between samples would put the reader's own error into the ground truth, which is
    the defect examples/crystallography/2_partition records: the grid reading landed inside one
    voxel every time and on the published edge zero times, and the figure was the grid.
    """
    frequencies = numpy.fft.fftfreq(canvas.shape[axis])
    shape = [1, 1]
    shape[axis] = canvas.shape[axis]
    ramp = numpy.exp(-2.0j * numpy.pi * frequencies.reshape(shape) * distance)
    return numpy.real(
        numpy.fft.ifft(numpy.fft.fft(canvas, axis=axis) * ramp, axis=axis)
    )


def to_levels(canvas, levels=LEVELS):
    """The field as integer levels, scaled to its own range so the band is not a fixed one.

    theory/workbook records a band fixed in absolute levels reading a picture spread over 160 of
    them as having no structure, and a corpus of eight symbols as one run covering everything. The
    cure recorded there is to scale the band to each corpus, which is what this does.
    """
    low = float(canvas.min())
    high = float(canvas.max())
    if high <= low:
        return numpy.zeros(canvas.shape, dtype=numpy.int32)
    scaled = (canvas - low) / (high - low)
    return numpy.clip((scaled * levels).astype(numpy.int32), 0, levels - 1)


def agreement(first, second, lag, axis):
    """Share of OCCUPIED positions where `first` and `second` agree `lag` apart along `axis`.

    This is examples/crystallography's lattice_agreement, and the word that matters is occupied.
    Scoring every position instead was measured here first and is kept in the docstring because it
    fails in a way that looks like a result: a field of blobs on a flat background is mostly
    background, background agrees with background at every lag, and the measure returns its maximum
    at lag zero for every true displacement with both neighbors equal to it. The cross-axis control
    returned the same figure, which is what named it. theory/workbook says the same thing about the
    protein row from the other side, that in empty space every axis is identical and a line crossing
    mostly vacuum has no magnitude to carry.

    The predicate is still an equality between positions and still reads no value, which is what
    Section 2.1 of the construction requires. What changed is which positions are asked.
    """
    if lag < 0:
        return 0.0
    if lag >= first.shape[axis]:
        return 0.0
    # first[j] against second[j + lag]. The other pairing searches the opposite direction and was
    # measured here first: it returns lag zero on every row because the true displacement is
    # positive and no negative lag is swept, which reads exactly like a measure with no resolution.
    if axis == 0:
        left = first[: first.shape[0] - lag, :] if lag else first
        right = second[lag:, :]
    else:
        left = first[:, : first.shape[1] - lag] if lag else first
        right = second[:, lag:]
    if left.size == 0:
        return 0.0
    # Occupied means carrying anything above the background level. Either arm being occupied
    # qualifies the position: a cell that moved away from a place is as much a fact about the
    # displacement as one that moved into it, and scoring only where both are lit would count
    # agreement over the overlap alone and reward a lag for missing.
    lit = (left > 0) | (right > 0)
    counted = int(lit.sum())
    if counted == 0:
        return 0.0
    return float(((left == right) & lit).sum()) / float(counted)


def recover(first, second, axis, reach=12):
    """The whole lag and the fraction beyond it, from the two lags straddling the true displacement.

    Returns (lag, fraction, agreement at the lag). The fraction is the share the taller neighbor
    holds of the two, which is the quantity examples/crystallography reads off a tiling.
    """
    scores = {lag: agreement(first, second, lag, axis) for lag in range(0, reach + 1)}
    lag = max(scores, key=lambda step: scores[step])
    score = scores[lag]
    above = scores.get(lag + 1, 0.0)
    below = scores.get(lag - 1, 0.0) if lag > 0 else 0.0
    neighbor = above if above >= below else below
    total = score + neighbor
    share = (neighbor / total) if total > 0.0 else 0.0
    return lag, (share if above >= below else -share), score


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    rng = numpy.random.default_rng(SEED)
    canvas = field(rng)
    first = to_levels(canvas)

    out.write(
        "  A field displaced by an amount this file chose, read back off the pixel grid.\n"
    )
    out.write(
        "  %d levels, %d blobs %.1f px wide, %dx%d field.\n\n"
        % (LEVELS, BLOBS, BLOB_WIDTH, SIDE, SIDE)
    )
    out.write(
        "  %-8s %-8s %-10s %-10s %-10s %s\n"
        % ("true", "lag", "fraction", "recovered", "error", "cross axis")
    )

    errors = []
    plain = []
    for truth in TRUTHS:
        second = to_levels(shifted(canvas, truth, axis=0))
        lag, fraction, _ = recover(first, second, axis=0)
        recovered = lag + fraction
        error = recovered - truth
        errors.append(abs(error))
        # The background this is read against: the whole lag on its own, with the fraction
        # discarded. A value says nothing here and a departure from a background says something,
        # and this is the background. If the two columns agree, the fraction carries nothing.
        plain.append(abs(lag - truth))
        # The other axis moved by nothing. Anything but zero there is the reading inventing a
        # displacement. Reported on every row  because a control quoted once is a
        # control that stopped being checked.
        cross_lag, cross_fraction, _ = recover(first, second, axis=1)
        out.write(
            "  %-8.2f %-8d %-10.4f %-10.4f %-10.4f %.4f\n"
            % (truth, lag, fraction, recovered, error, cross_lag + cross_fraction)
        )

    out.write(
        "\n  with the fraction:    mean %.4f px, worst %.4f px\n"
        % (sum(errors) / len(errors), max(errors))
    )
    out.write(
        "  whole lag alone:      mean %.4f px, worst %.4f px\n"
        % (sum(plain) / len(plain), max(plain))
    )
    out.write(
        "  the fraction is worth %.2fx on the mean, over %d rows.\n"
        % ((sum(plain) / len(plain)) / (sum(errors) / len(errors)), len(errors))
    )
    out.write(
        "\n  The residual is not scatter. It is largest at whole-number displacements and\n"
    )
    out.write(
        "  near zero at the half, because the share never reaches zero: a blob six pixels\n"
    )
    out.write(
        "  wide still agrees substantially at the neighbouring lag when the displacement is\n"
    )
    out.write(
        "  exact. The fraction is monotone in the true remainder and is not equal to it.\n"
    )
    out.write(
        "\n  The cross-axis column is the control and it does not read zero. An axis that\n"
    )
    out.write(
        "  moved by nothing returns about half a pixel, which is the same floor seen from\n"
    )
    out.write("  underneath. Any per-cell reading built on this inherits that floor.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
