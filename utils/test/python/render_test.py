#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grades the Python renderer against the C one, byte for byte.
#
#   python utils/test/harness.py run engine_c
#
# The Python host arm in render.host and the C host arm in src/engine/render/anchor_raster_host.c share no
# code. Both walk the same alignments and write the same channel into the same cell. A byte that
# differs is a defect in one of them. This renders every layout and channel, as a sheet and as a
# volume, through both arms and compares the bytes. It also renders through render.render_raster and
# render.render_volume, the dispatch that prefers the device, and checks that output against the C
# host: where a device is present that grades the device arm too, and where none is it grades the
# fall back to the C host. The dispatch also names the arm it ran on, and a row checks that name
# against this machine's path: the device where one is present, the host where none is. Each row
# prints the CRC-32 of each side's bytes, the count of bytes that differ, and the reported arm, and
# the verdict reads those.
#
# It needs the anchor_render shared library (src/engine/CMakeLists.txt). The harness env engine_c
# runs it from utils/maint/engine/build_engine.sh, which builds the library and names it in
# ANCHOR_RENDER_LIB. Without that, it is searched for under build/.
# A missing library is a failure here and not a skip, because the grade cannot run without it, and a
# check that cannot run must not read as a pass.
#
# It has been seen to fail. Setting render.host.STEP to 41 breaks the death-level gray ramp, and the
# eight death-level rows report FAILS at exit 1 while the other channels, which do not read the ramp,
# stay ok. A suite nobody has watched fail is indistinguishable from an empty loop. That is
# recorded here and not assumed.

import os
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

import render
from render import host, native


def build_corpus(length):
    """A deterministic corpus whose symbols vary in rarity. The rarity channel has something to show."""
    corpus = bytearray(length)
    state = 2463534242
    for at in range(length):
        state ^= (state << 13) & 0xFFFFFFFF
        state ^= state >> 17
        state ^= (state << 5) & 0xFFFFFFFF
        roll = state % 1000
        if roll < 400:
            corpus[at] = 0x41
        elif roll < 700:
            corpus[at] = 0x42
        elif roll < 900:
            corpus[at] = 0x43
        else:
            corpus[at] = 0x50 + (state % 40)
    return bytes(corpus)


def find_library():
    """The render shared library the build produced, searched under build/, or None."""
    from_env = os.environ.get("ANCHOR_RENDER_LIB")
    if from_env and os.path.isfile(from_env):
        return from_env
    names = ("anchor_render.dll", "libanchor_render.dll", "libanchor_render.so",
             "libanchor_render.dylib")
    for base, _dirs, files in os.walk(os.path.join(ROOT, "build")):
        for name in names:
            if name in files:
                return os.path.join(base, name)
    return None


def crc(data):
    """The CRC-32 of a render's bytes as eight hex digits, or a dash for a failed render."""
    return "-" if data is None else "%08x" % (zlib.crc32(data) & 0xFFFFFFFF)


def differing(a, b):
    """How many bytes differ between two renders; a failed or short render counts every byte."""
    if a is None or b is None or len(a) != len(b):
        return max(len(a or b""), len(b or b""))
    return sum(1 for x, y in zip(a, b) if x != y)


def row(kind, layout, channel, py, c, rendered, expected_arm):
    """Prints one graded row with both sides' numbers, and returns 1 when it fails.

    The dispatch has to agree with the C host byte for byte and name the arm that ran. A row fails
    where the bytes differ or where the reported arm is not the one this machine's path takes.
    """
    wrong = differing(py, c) + differing(rendered.bytes, c)
    arm_ok = rendered.arm == expected_arm
    ok = py is not None and wrong == 0 and arm_ok
    print("  %6s %13s %11s %6d %6d %9s %9s %9s %5d %7s %6s" % (
        kind, layout, channel, 0 if py is None else len(py), 0 if c is None else len(c),
        crc(py), crc(c), crc(rendered.bytes), wrong, rendered.arm, "ok" if ok else "FAILS"))
    return 0 if ok else 1


def main():
    lib_path = find_library()
    if lib_path is None:
        print("  render shared library not found: set ANCHOR_RENDER_LIB, or build it under build/.")
        return 1
    lib = native.load(lib_path)
    if lib is None:
        print("  render shared library at %s could not be loaded" % lib_path)
        return 1

    corpus = build_corpus(4096)
    needle = corpus[1000:1016]
    probes = [host.Probe(0, 1, 1), host.Probe(5, 1, 1), host.Probe(11, 1, 1)]

    on_device = render.device_available(lib)
    expected_arm = render.ARM_DEVICE if on_device else render.ARM_HOST
    print("\n  PYTHON RENDERER AGAINST C, byte for byte. library: %s\n  device: %s, arm expected: %s\n"
          % (lib_path, "present" if on_device else "absent, host only", expected_arm))
    print("  %6s %13s %11s %6s %6s %9s %9s %9s %5s %7s %6s" % (
        "kind", "layout", "channel", "py", "c", "py crc", "c crc", "disp crc", "diff", "arm",
        "verdict"))

    failed = 0

    channels = [host.CHANNEL_DEATH_LEVEL, host.CHANNEL_SURVIVED, host.CHANNEL_RARITY,
                host.CHANNEL_BYTE, host.CHANNEL_PROVEN]
    channel_names = {host.CHANNEL_DEATH_LEVEL: "death-level", host.CHANNEL_SURVIVED: "survived",
                     host.CHANNEL_RARITY: "rarity", host.CHANNEL_BYTE: "byte",
                     host.CHANNEL_PROVEN: "proven"}
    raster_layouts = [host.LAYOUT_ROWS, host.LAYOUT_SERPENTINE, host.LAYOUT_COLUMNS,
                      host.LAYOUT_DIAGONAL]
    raster_names = {host.LAYOUT_ROWS: "rows", host.LAYOUT_SERPENTINE: "serpentine",
                    host.LAYOUT_COLUMNS: "columns", host.LAYOUT_DIAGONAL: "diagonal"}
    volume_layouts = [host.VOLUME_SLABS, host.VOLUME_BOUSTRO, host.VOLUME_MORTON, host.VOLUME_HELIX]
    volume_names = {host.VOLUME_SLABS: "slabs", host.VOLUME_BOUSTRO: "boustrophedon",
                    host.VOLUME_MORTON: "morton", host.VOLUME_HELIX: "helix"}

    for layout in raster_layouts:
        for channel in channels:
            config = host.RasterConfig(32, 32, layout, channel, host.REDUCE_MIN, 1)
            py = host.raster(config, corpus, needle, probes)
            c = native.raster_host(lib, config, corpus, needle, probes)
            rendered = render.render_raster(config, corpus, needle, probes, lib=lib)
            failed += row("sheet", raster_names[layout], channel_names[channel], py, c, rendered,
                          expected_arm)

    for layout in volume_layouts:
        for channel in channels:
            config = host.VolumeConfig(8, 8, 8, layout, channel, host.REDUCE_MAX, 1)
            py = host.volume(config, corpus, needle, probes)
            c = native.volume_host(lib, config, corpus, needle, probes)
            rendered = render.render_volume(config, corpus, needle, probes, lib=lib)
            failed += row("volume", volume_names[layout], channel_names[channel], py, c, rendered,
                          expected_arm)

    print("\n  %d checks, %d failed\n" % (len(raster_layouts + volume_layouts) * len(channels), failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
