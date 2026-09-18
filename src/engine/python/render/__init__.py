#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The renderer in Python, preferring the device.
#
#   Usage:  from render import render_raster, render_volume, RasterConfig, VolumeConfig, Probe
#
# render_raster and render_volume are the entries a caller uses. They render on the fastest arm
# available and produce the same bytes whichever runs. The choice is a performance one. The order
# is: the C dispatch through a loaded shared library, which itself prefers the CUDA device and falls
# back to the C host; then the pure Python host arm in render.host when no library is reachable. A
# machine that built the library with the device arm renders on the device from Python for free.
#
# The library is found the way render.native describes: an explicit path, the ANCHOR_RENDER_LIB
# environment variable, or a platform search. Nothing here walks the checkout. Where none is found
# the pure Python arm runs, which is correct and slow, and the grader in
# test/engine/test_render_python.py checks the two arms agree byte for byte.

from render import host, native
from render.host import (
    RasterConfig, VolumeConfig, Probe,
    LAYOUT_ROWS, LAYOUT_SERPENTINE, LAYOUT_COLUMNS, LAYOUT_DIAGONAL,
    CHANNEL_DEATH_LEVEL, CHANNEL_SURVIVED, CHANNEL_RARITY, CHANNEL_BYTE, CHANNEL_PROVEN,
    REDUCE_MIN, REDUCE_MAX,
    VOLUME_SLABS, VOLUME_BOUSTRO, VOLUME_MORTON, VOLUME_HELIX,
)

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
    """Renders a sheet on the fastest arm available. Returns width*height bytes, or None if refused.

    Passes through the C dispatch where a library is reachable, which prefers the device, and falls
    back to the pure Python host arm otherwise.
    """
    chosen = _library(lib)
    if chosen is not None:
        return native.raster_render(chosen, config, corpus, needle, probes)
    return host.raster(config, corpus, needle, probes)


def render_volume(config, corpus, needle, probes, lib=None):
    """Renders a volume on the fastest arm available. Returns the voxels, or None if refused.

    Passes through the C dispatch where a library is reachable, which prefers the device, and falls
    back to the pure Python host arm otherwise.
    """
    chosen = _library(lib)
    if chosen is not None:
        return native.volume_render(chosen, config, corpus, needle, probes)
    return host.volume(config, corpus, needle, probes)


def device_available(lib=None):
    """Whether a render happens on the device: a library is loaded and its device arm reports present.

    Returns False where the pure Python arm would run, since that arm is host only.
    """
    chosen = _library(lib)
    if chosen is None:
        return False
    return native.raster_device_available(chosen) != 0
