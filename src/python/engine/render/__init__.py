#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The renderer in Python, preferring the device.
#
#   Usage:  from render import render_raster, render_volume, RasterConfig, VolumeConfig, Probe
#
# render_raster and render_volume are the entries a caller uses. They render on the fastest arm
# available and produce the same bytes whichever runs. The choice is a performance one. The order
# is: the CUDA device arm where a loaded shared library reports one present, falling back to the C
# host where the device errors; then the pure Python host arm in render.host when no library is
# reachable. A machine that built the library with the device arm renders on the device from Python
# for free. Each entry returns a Render carrying the bytes and the arm that produced them. A caller
# then names the arm that actually ran, not the arm that was available.
#
# The library is found the way render.native describes: an explicit path, the ANCHOR_RENDER_LIB
# environment variable, or a platform search. Nothing here walks the checkout. Where none is found
# the pure Python arm runs, which is correct and slow, and the grader in
# utils/test/src/python/engine/render/render_test.py checks the two arms agree byte for byte.

import collections

from render import host, native
from render.host import (
    RasterConfig, VolumeConfig, Probe,
    LAYOUT_ROWS, LAYOUT_SERPENTINE, LAYOUT_COLUMNS, LAYOUT_DIAGONAL,
    CHANNEL_DEATH_LEVEL, CHANNEL_SURVIVED, CHANNEL_RARITY, CHANNEL_BYTE, CHANNEL_PROVEN,
    REDUCE_MIN, REDUCE_MAX,
    VOLUME_SLABS, VOLUME_BOUSTRO, VOLUME_MORTON, VOLUME_HELIX,
)

# The arm a render ran on, carried back beside the bytes. A caller names the arm that actually ran,
# not the arm that was available. These are the only two values arm takes: the device, or the host,
# which covers both the C host arm and the pure Python one.
ARM_DEVICE = "device"
ARM_HOST = "host"

# A render's result: the bytes, and the arm that produced them. bytes is None where the render errored.
Render = collections.namedtuple("Render", ["bytes", "arm"])

# The loaded library, found once. A sentinel distinguishes "not looked yet" from "looked, found
# none". A failed search is not repeated on every call.
_LIB = None
_LOOKED = False


def _library(lib):
    """Returns the library to use: the one passed, or the cached auto-loaded one."""
    global _LIB, _LOOKED
    if lib is not None:
        return lib
    if not _LOOKED:
        _LIB = native.load()
        _LOOKED = True
    return _LIB


def render_raster(config, corpus, needle, probes, lib=None):
    """Renders a sheet on the fastest arm available. Returns a Render of the bytes and the arm.

    Chooses the device where a library is loaded and its device arm is present, and falls back to the
    C host where the device errors, the same order anchor_raster_render takes in C. Where no library
    is reachable the pure Python host arm runs. The arm returned names the arm that produced the
    bytes, read from which arm ran and not from which was available.
    """
    chosen = _library(lib)
    if chosen is None:
        return Render(host.raster(config, corpus, needle, probes), ARM_HOST)
    if native.raster_device_available(chosen) != 0:
        pixels = native.raster_device(chosen, config, corpus, needle, probes)
        if pixels is not None:
            return Render(pixels, ARM_DEVICE)
    return Render(native.raster_host(chosen, config, corpus, needle, probes), ARM_HOST)


def render_volume(config, corpus, needle, probes, lib=None):
    """Renders a volume on the fastest arm available. Returns a Render of the bytes and the arm.

    Chooses the device where a library is loaded and its device arm is present, and falls back to the
    C host where the device errors, the same order anchor_volume_render takes in C. Where no library
    is reachable the pure Python host arm runs. The arm returned names the arm that produced the
    bytes, read from which arm ran and not from which was available.
    """
    chosen = _library(lib)
    if chosen is None:
        return Render(host.volume(config, corpus, needle, probes), ARM_HOST)
    if native.volume_device_available(chosen) != 0:
        voxels = native.volume_device(chosen, config, corpus, needle, probes)
        if voxels is not None:
            return Render(voxels, ARM_DEVICE)
    return Render(native.volume_host(chosen, config, corpus, needle, probes), ARM_HOST)


def device_available(lib=None):
    """Whether a render happens on the device: a library is loaded and its device arm reports present.

    Returns False where the pure Python arm would run, since that arm is host only.
    """
    chosen = _library(lib)
    if chosen is None:
        return False
    return native.raster_device_available(chosen) != 0
