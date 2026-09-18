#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The C renderer reached from Python through ctypes, which is how Python renders on the device.
#
#   Usage:  from render.native import load, raster_render, volume_render, raster_host
#
# Python cannot own a device path here: numpy, cupy and the rest are banned tree wide. A pure
# Python renderer runs on the CPU alone. The device preference lives in C, where anchor_raster_render
# and anchor_volume_render already ask the device first and fall back to the host. This binding lets
# Python call those. A machine that built the shared library with the CUDA arm renders on the
# device without the Python caller choosing an arm. Where no library is loaded, render/__init__ falls
# back to the pure Python host arm in render.host, and the two are graded byte for byte.
#
# The library is not found by walking the tree. The engine knows nothing about the checkout it sits
# in. Load() takes an explicit path, or reads ANCHOR_RENDER_LIB, or asks the platform loader for a
# library named anchor_render. A caller that knows where the build put it passes the path.
#
# The structures below mirror AnchorRasterConfig, AnchorVolumeConfig and AnchorRasterProbe in
# src/engine/c/render/anchor_raster.h field for field. ctypes lays them out under the same ABI the C
# library was built with, and the grader compares the bytes this binding returns against the pure
# Python arm. A layout that did not match would fail rather than pass quietly.

import ctypes
import os

from render import host


class _RasterConfig(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_size_t),
        ("height", ctypes.c_size_t),
        ("layout", ctypes.c_int),
        ("channel", ctypes.c_int),
        ("reduce", ctypes.c_int),
        ("gain", ctypes.c_uint8),
    ]


class _VolumeConfig(ctypes.Structure):
    _fields_ = [
        ("width", ctypes.c_size_t),
        ("height", ctypes.c_size_t),
        ("depth", ctypes.c_size_t),
        ("layout", ctypes.c_int),
        ("channel", ctypes.c_int),
        ("reduce", ctypes.c_int),
        ("gain", ctypes.c_uint8),
    ]


class _Probe(ctypes.Structure):
    _fields_ = [
        ("origin", ctypes.c_size_t),
        ("step", ctypes.c_size_t),
        ("length", ctypes.c_size_t),
    ]


def _bind(lib):
    """Sets argtypes and restypes on the entries this binding calls, once per loaded library."""
    u8 = ctypes.POINTER(ctypes.c_uint8)
    probe = ctypes.POINTER(_Probe)
    size = ctypes.c_size_t

    for name in ("anchor_raster_host", "anchor_raster_render"):
        fn = getattr(lib, name)
        fn.restype = ctypes.c_int
        fn.argtypes = [u8, ctypes.POINTER(_RasterConfig), u8, size, u8, size, probe, size]

    for name in ("anchor_volume_render_host", "anchor_volume_render"):
        fn = getattr(lib, name)
        fn.restype = ctypes.c_int
        fn.argtypes = [u8, ctypes.POINTER(_VolumeConfig), u8, size, u8, size, probe, size,
                       ctypes.c_void_p]

    for name in ("anchor_raster_device_available", "anchor_volume_device_available"):
        fn = getattr(lib, name)
        fn.restype = ctypes.c_int
        fn.argtypes = []
    return lib


def load(path=None):
    """Loads the render shared library, or returns None where none is reachable.

    Tries `path`, then the ANCHOR_RENDER_LIB environment variable, then a platform search for a
    library named anchor_render. Returns None rather than raising. A caller can fall back to the
    pure Python arm.
    """
    candidates = []
    if path is not None:
        candidates.append(path)
    from_env = os.environ.get("ANCHOR_RENDER_LIB")
    if from_env:
        candidates.append(from_env)
    candidates.append("anchor_render")

    for candidate in candidates:
        try:
            return _bind(ctypes.CDLL(candidate))
        except OSError:
            continue
    return None


def _probe_array(probes):
    """Packs a sequence of host.Probe into a ctypes array, and its length."""
    count = len(probes)
    array = (_Probe * count)() if count > 0 else None
    for index, probe in enumerate(probes):
        array[index].origin = probe.origin
        array[index].step = probe.step
        array[index].length = probe.length
    return array, count


def _buffer(corpus):
    """A uint8 ctypes buffer over a bytes-like object, and its length."""
    data = bytes(corpus)
    return (ctypes.c_uint8 * len(data)).from_buffer_copy(data), len(data)


def _call_raster(lib, entry, config, corpus, needle, probes):
    plan = _RasterConfig(config.width, config.height, config.layout, config.channel, config.reduce,
                         config.gain)
    pixels = (ctypes.c_uint8 * (config.width * config.height))()
    corpus_buf, corpus_len = _buffer(corpus)
    needle_buf, needle_len = _buffer(needle)
    probe_array, probe_count = _probe_array(probes)
    ok = getattr(lib, entry)(pixels, ctypes.byref(plan), corpus_buf, corpus_len, needle_buf,
                             needle_len, probe_array, probe_count)
    if ok == 0:
        return None
    return bytes(pixels)


def _call_volume(lib, entry, config, corpus, needle, probes):
    plan = _VolumeConfig(config.width, config.height, config.depth, config.layout, config.channel,
                        config.reduce, config.gain)
    voxels = (ctypes.c_uint8 * (config.width * config.height * config.depth))()
    corpus_buf, corpus_len = _buffer(corpus)
    needle_buf, needle_len = _buffer(needle)
    probe_array, probe_count = _probe_array(probes)
    ok = getattr(lib, entry)(voxels, ctypes.byref(plan), corpus_buf, corpus_len, needle_buf,
                             needle_len, probe_array, probe_count, None)
    if ok == 0:
        return None
    return bytes(voxels)


def raster_host(lib, config, corpus, needle, probes):
    """The C host arm, for grading against render.host. Returns bytes or None."""
    return _call_raster(lib, "anchor_raster_host", config, corpus, needle, probes)


def raster_render(lib, config, corpus, needle, probes):
    """The C dispatch, preferring the device. Returns bytes or None."""
    return _call_raster(lib, "anchor_raster_render", config, corpus, needle, probes)


def volume_host(lib, config, corpus, needle, probes):
    """The C host volume arm, for grading against render.host. Returns bytes or None."""
    return _call_volume(lib, "anchor_volume_render_host", config, corpus, needle, probes)


def volume_render(lib, config, corpus, needle, probes):
    """The C volume dispatch, preferring the device. Returns bytes or None."""
    return _call_volume(lib, "anchor_volume_render", config, corpus, needle, probes)


def raster_device_available(lib):
    """1 where the loaded library has a device raster arm and a device is present, 0 otherwise."""
    return int(lib.anchor_raster_device_available())


def volume_device_available(lib):
    """1 where the loaded library has a device volume arm and a device is present, 0 otherwise."""
    return int(lib.anchor_volume_device_available())
