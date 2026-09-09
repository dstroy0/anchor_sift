#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fields built to a known answer, letting a reading be wrong instead of merely different.
#
#   Usage:  from reference.fields import build, stretched
#
# Every reading of the spectral exponent until these existed was of a painting, where the plane is
# the only authority on what the answer should be and there is nothing independent to catch a wrong
# one. Shaping white noise in the frequency domain gives a field whose exponent was put in by hand,
# so the answer exists before the measurement and a wrong reading cannot be argued into agreement
# afterward.
#
# That is a positive control for the spectral reading, which had none. Asked for 2.00 the reading
# returns 2.044, 2.005 and 1.958 in two, three and four dimensions, and asked for 3.00 it returns
# 2.968, 2.974 and 2.970. It says nothing about the gap measure, which still has none.
#
# The fields are quantized to eight bits before they are read, because every corpus in this work is
# read at that width and a control measured at full precision would be measuring something the real
# corpora never get.
#
# `stretched` exists because of a failure. The first fields were isotropic, so every axis had
# identical statistics and there was one magnitude repeated n times instead of n magnitudes. No line
# can count what was never made different, and two attempts at recovering a dimension count were
# asked to do exactly that before anyone noticed.

import numpy

from representation.levels import to_levels


def build(dims, side, slope, rng):
    """A field whose power falls at a chosen rate, quantized to whole levels the way a corpus is.

    Every axis has the same statistics, which is right for measuring an exponent and wrong for
    counting dimensions.
    """
    noise = rng.standard_normal((side,) * dims)
    spectrum = numpy.fft.fftn(noise)
    axes = numpy.meshgrid(*[numpy.fft.fftfreq(side) * side] * dims, indexing="ij")
    radius = numpy.sqrt(sum(axis ** 2 for axis in axes))
    radius[(0,) * dims] = 1.0
    shaped = spectrum * (radius ** (-slope / 2.0))
    shaped[(0,) * dims] = 0.0
    return to_levels(numpy.real(numpy.fft.ifftn(shaped)))


def stretched(dims, side, slope, rng, factors=None):
    """The same, with a different correlation length along each axis.

    Each axis then carries a roughness of its own, so there are n magnitudes to count instead of one
    repeated n times. Without this a dimension count cannot be recovered from a line at all, and the
    two attempts that failed before anyone noticed were both asked to count what was never made
    different.
    """
    noise = rng.standard_normal((side,) * dims)
    spectrum = numpy.fft.fftn(noise)
    axes = numpy.meshgrid(*[numpy.fft.fftfreq(side) * side] * dims, indexing="ij")

    if factors is None:
        factors = [1.0 + (2.0 * place) for place in range(dims)]
    radius = numpy.sqrt(sum((axis / factor) ** 2 for axis, factor in zip(axes, factors)))
    radius[(0,) * dims] = 1.0
    shaped = spectrum * (radius ** (-slope / 2.0))
    shaped[(0,) * dims] = 0.0
    return to_levels(numpy.real(numpy.fft.ifftn(shaped)))
