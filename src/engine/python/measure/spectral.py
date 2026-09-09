#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How the power falls with frequency. No other quantity here carries no scale of its own.
#
#   Usage:  from measure.spectral import exponent, exponent_plane, exponent_volume, fit_bands
#
# Every other statistic in this work has had a scale inside it and has been corrected once the scale
# showed. A window width was chosen and the choice was measured. A ceiling was put on a sum that has
# no bound. A band was fixed in levels and read a picture spread over 160 of them as flat. A distance
# in standard deviations moved one painting from 20.6 to 122.8 on nothing but how much of the file
# was read.
#
# Data carrying structure at every scale has no characteristic scale for any of those to sit at.
# What does not belong to a scale is how a quantity changes with scale, and that is this exponent.
# White noise gives zero, a random walk gives two, and a natural scene sits near two.

import numpy

# Frequencies below this are dropped. The lowest few carry the overall level and the read length,
# and a line fitted through them is fitted through how much of the file was opened.
LOW = 4

# Bands spaced evenly in the logs, so the many high frequencies do not outvote the few low ones and
# the fit describes the whole range instead of its top end.
BANDS = 48


def fit_bands(frequency, power):
    """Slope through the logs, averaged into bands spaced evenly in the logs.

    Returns the exponent as a positive number, since the power falls, and how much of the spread the
    line accounts for. Returns (None, None) where too few bands hold anything to fit.
    """
    edges = numpy.unique(numpy.round(
        numpy.logspace(numpy.log10(LOW), numpy.log10(frequency.max()), BANDS)).astype(numpy.int64))

    centers = []
    heights = []
    for index in range(len(edges) - 1):
        low, high = edges[index], edges[index + 1]
        if high <= low:
            continue
        inside = (frequency >= low) & (frequency < high)
        if not inside.any():
            continue
        centers.append(numpy.sqrt(float(low) * float(high)))
        heights.append(float(power[inside].mean()))

    if len(centers) < 8:
        return None, None

    logs = numpy.log10(numpy.asarray(centers))
    values = numpy.log10(numpy.asarray(heights))
    slope, intercept = numpy.polyfit(logs, values, 1)
    predicted = (slope * logs) + intercept
    spread = float(((values - values.mean()) ** 2).sum())
    quality = 1.0 - (float(((values - predicted) ** 2).sum()) / spread) if spread > 0 else 0.0
    return -float(slope), quality


def exponent(values):
    """The exponent along a single dimension, for a sequence of symbols."""
    floats = values.astype(numpy.float64)
    floats = floats - floats.mean()
    if floats.std() <= 0.0:
        return None, None

    power = numpy.abs(numpy.fft.rfft(floats)) ** 2
    power = power[1:]
    frequency = numpy.arange(1, len(power) + 1, dtype=numpy.float64)
    return fit_bands(frequency, power)


def exponent_plane(values, width):
    """The exponent over a picture read as a plane, against radial frequency.

    A picture read as one long line carries its width as a periodicity, and a slope through that is
    not the slope of the picture. The paintings first came back near half of what a natural scene
    gives for that reason, and the width has to be supplied here.
    """
    rows = len(values) // width
    if rows < 64:
        return None, None

    grid = values[:rows * width].reshape(rows, width).astype(numpy.float64)
    grid = grid - grid.mean()
    if grid.std() <= 0.0:
        return None, None

    power = numpy.abs(numpy.fft.fftshift(numpy.fft.fft2(grid))) ** 2
    down = numpy.arange(rows) - (rows // 2)
    across = numpy.arange(width) - (width // 2)
    radius = numpy.sqrt((down[:, None] ** 2) + (across[None, :] ** 2))
    keep = radius >= LOW
    return fit_bands(radius[keep], power[keep])


def exponent_volume(field):
    """The exponent over a whole set against radial frequency, at any number of dimensions.

    This is the number the reading along a curve is checked against. A curve filling a set of n
    dimensions covers its volume with a length, and a reading taken along one therefore comes back
    divided by n. Without the exponent of the set there is nothing to divide and nothing to compare.

    The set is given as an array, any rank, with equal sides. Returns (None, None) where it does not
    vary, or where too few bands hold anything to fit.
    """
    floats = field.astype(numpy.float64)
    floats = floats - floats.mean()
    if floats.std() <= 0.0:
        return None, None

    power = numpy.abs(numpy.fft.fftshift(numpy.fft.fftn(floats))) ** 2
    side = field.shape[0]
    axes = numpy.meshgrid(*[numpy.arange(side) - (side // 2)] * field.ndim, indexing="ij")
    radius = numpy.sqrt(sum(axis.astype(numpy.float64) ** 2 for axis in axes))
    keep = radius >= LOW
    return fit_bands(radius[keep], power[keep])
