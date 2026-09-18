#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The renderer in Python, host arm, a byte-identical second route to the C host renderer.
#
#   Usage:  from render.host import raster, volume, RasterConfig, VolumeConfig, Probe
#
# A search produces one outcome per alignment: some probe rejected it, or every probe agreed and a
# full compare decided it. That sequence is already an image. This turns it into one, on the CPU in
# pure Python, and it shares no code with the C renderer. The two agreeing byte for byte is the check
# the "two routes or it does not ship" rule asks for, and the grader in test/engine/test_render_python.py
# runs it. This route is the reference and the slow one; render/__init__ prefers the C engine, which
# prefers the device, and falls back here when no shared library is present.
#
# Every value is an integer read off the same inputs the C arm reads. Nothing is a float and nothing
# is normalized against the image. A pixel means the same thing at two sizes. The constants and the
# arithmetic below are transcribed from src/engine/c/render/anchor_raster.c and are graded against it
# rather than trusted.

import collections

# Pixel sentinels, matching the #defines in anchor_raster.h.
EMPTY = 0
MATCH = 255
PROVEN = 200
UNDETERMINED = 60

# The death-level gray ramp, matching ANCHOR_RASTER_STEP and ANCHOR_RASTER_CEILING.
STEP = 40
CEILING = 250

# Layout, channel and reduce, matching the enums in anchor_raster.h by value.
LAYOUT_ROWS = 0
LAYOUT_SERPENTINE = 1
LAYOUT_COLUMNS = 2
LAYOUT_DIAGONAL = 3

CHANNEL_DEATH_LEVEL = 0
CHANNEL_SURVIVED = 1
CHANNEL_RARITY = 2
CHANNEL_BYTE = 3
CHANNEL_PROVEN = 4

REDUCE_MIN = 0
REDUCE_MAX = 1

# Volume layout, matching AnchorVolumeLayout by value.
VOLUME_SLABS = 0
VOLUME_BOUSTRO = 1
VOLUME_MORTON = 2
VOLUME_HELIX = 3

RasterConfig = collections.namedtuple(
    "RasterConfig", ["width", "height", "layout", "channel", "reduce", "gain"])
VolumeConfig = collections.namedtuple(
    "VolumeConfig", ["width", "height", "depth", "layout", "channel", "reduce", "gain"])
Probe = collections.namedtuple("Probe", ["origin", "step", "length"])


def _census(corpus):
    """Symbol counts and the total, the histogram the rarity channel reads.

    Returns (occurrences, total) where occurrences is a list of 256 counts. This is the same count
    the C arm builds from the corpus, and a caller supplied census is not read, matching the C.
    """
    occurrences = [0] * 256
    for symbol in corpus:
        occurrences[symbol] += 1
    return occurrences, len(corpus)


def _death_level(corpus, needle, needle_len, probes, at):
    """The probe index that rejected the alignment, and whether the full compare matched.

    Returns (level, matched). `level` is `len(probes)` where no probe refuted it, and `matched` is
    true only where the full compare confirmed an occurrence.
    """
    for slot, probe in enumerate(probes):
        for step in range(probe.length):
            offset = probe.origin + (step * probe.step)
            if corpus[at + offset] != needle[offset]:
                return slot, False
    # Survived every probe. The full compare decides an occurrence.
    for step in range(needle_len):
        if corpus[at + step] != needle[step]:
            return len(probes), False
    return len(probes), True


def _value(level, matched):
    """The gray value for a death level, matching raster_value."""
    if matched:
        return MATCH
    scaled = 1 + (level * STEP)
    return CEILING if scaled > CEILING else scaled


def _sample(channel, gain, corpus, needle, needle_len, probes, at, occurrences, total):
    """The value one alignment contributes under a channel, matching anchor_raster_sample."""
    gain = 1 if gain == 0 else gain

    if channel == CHANNEL_BYTE:
        return corpus[at]
    if channel == CHANNEL_RARITY:
        if total == 0:
            return 1
        missing = total - occurrences[corpus[at]]
        return 1 + ((missing * 254) // total)
    if channel == CHANNEL_PROVEN:
        level, _matched = _death_level(corpus, needle, needle_len, probes, at)
        return PROVEN if level < len(probes) else UNDETERMINED
    if channel == CHANNEL_SURVIVED:
        level, _matched = _death_level(corpus, needle, needle_len, probes, at)
        return MATCH if level >= len(probes) else 1
    # CHANNEL_DEATH_LEVEL and any other value.
    level, matched = _death_level(corpus, needle, needle_len, probes, at)
    return _value(level * gain, matched)


def _raster_cell(config, at, alignments):
    """The pixel an alignment lands on under a layout, matching anchor_raster_cell."""
    cells = config.width * config.height
    linear = (at * cells) // alignments
    row = linear // config.width
    column = linear % config.width

    if config.layout == LAYOUT_SERPENTINE:
        flipped = column if (row % 2) == 0 else (config.width - 1 - column)
        return (row * config.width) + flipped
    if config.layout == LAYOUT_COLUMNS:
        turned_row = linear % config.height
        turned_column = linear // config.height
        if turned_column >= config.width:
            return linear
        return (turned_row * config.width) + turned_column
    if config.layout == LAYOUT_DIAGONAL:
        shifted = (column + row) % config.width
        return (row * config.width) + shifted
    return linear


def _is_power_of_two(value):
    return (value != 0) and ((value & (value - 1)) == 0)


def _volume_cell(config, alignment, cells):
    """The voxel an alignment lands on under a volume layout, matching anchor_volume_cell_for.

    Returns `cells` where the layout refuses the configuration, which is Morton on extents that are
    not all powers of two and any unknown layout. A caller reads that as "not placed".
    """
    width = config.width
    height = config.height
    depth = config.depth
    at = alignment % cells
    sheet = width * height

    if config.layout == VOLUME_SLABS:
        return at
    if config.layout == VOLUME_BOUSTRO:
        slab = at // sheet
        within = at % sheet
        row = within // width
        column = within % width
        if (row % 2) == 1:
            column = (width - 1) - column
        if (slab % 2) == 1:
            row = (height - 1) - row
        return (slab * sheet) + (row * width) + column
    if config.layout == VOLUME_MORTON:
        if (not _is_power_of_two(width)) or (not _is_power_of_two(height)) \
           or (not _is_power_of_two(depth)):
            return cells
        x = 0
        y = 0
        z = 0
        # 21 bits, matching (sizeof(size_t) * 8) / 3 on a 64 bit build.
        for bit in range(21):
            x |= ((at >> ((3 * bit) + 0)) & 1) << bit
            y |= ((at >> ((3 * bit) + 1)) & 1) << bit
            z |= ((at >> ((3 * bit) + 2)) & 1) << bit
        x %= width
        y %= height
        z %= depth
        return (z * sheet) + (y * width) + x
    if config.layout == VOLUME_HELIX:
        slab = at // sheet
        within = at % sheet
        row = within // width
        column = (within + slab) % width
        return (slab * sheet) + (row * width) + column
    return cells


def _reduce_into(cells_out, cell, value, reduce):
    """Places a value into a cell under the reduction, filling empty on first arrival.

    An empty cell holds EMPTY, which would win every minimum and lose every maximum. It is filled
    on first arrival rather than compared against, matching the C arm.
    """
    if cells_out[cell] == EMPTY:
        cells_out[cell] = value
        return
    if reduce == REDUCE_MAX:
        if value > cells_out[cell]:
            cells_out[cell] = value
    elif value < cells_out[cell]:
        cells_out[cell] = value


def raster(config, corpus, needle, probes):
    """Renders a sheet, returning width*height bytes, or None where the configuration is refused.

    `corpus` and `needle` are bytes or a sequence of ints in [0, 255]. `probes` is a sequence of
    Probe. The bytes returned are identical to anchor_raster_host on the same arguments.
    """
    needle_len = len(needle)
    if (config.width == 0) or (config.height == 0) or (needle_len == 0) \
       or (needle_len > len(corpus)):
        return None

    cells = config.width * config.height
    pixels = bytearray(cells)  # bytearray is zero filled, which is EMPTY.

    occurrences, total = _census(corpus)
    alignments = (len(corpus) - needle_len) + 1
    for at in range(alignments):
        value = _sample(config.channel, config.gain, corpus, needle, needle_len, probes, at,
                        occurrences, total)
        cell = _raster_cell(config, at, alignments)
        _reduce_into(pixels, cell, value, config.reduce)
    return bytes(pixels)


def volume(config, corpus, needle, probes):
    """Renders a volume, returning width*height*depth bytes, or None where the configuration is refused.

    The bytes returned are identical to anchor_volume_render_host on the same arguments. A layout that
    refuses the configuration returns None, matching the host arm returning 0 without a volume.
    """
    needle_len = len(needle)
    if (config.width == 0) or (config.height == 0) or (config.depth == 0) or (needle_len == 0) \
       or (needle_len > len(corpus)):
        return None

    cells = config.width * config.height * config.depth
    voxels = bytearray(cells)

    occurrences, total = _census(corpus)
    alignments = (len(corpus) - needle_len) + 1
    for at in range(alignments):
        cell = _volume_cell(config, at, cells)
        if cell >= cells:
            # The layout refused this configuration, as the host arm does for the whole render.
            return None
        value = _sample(config.channel, config.gain, corpus, needle, needle_len, probes, at,
                        occurrences, total)
        _reduce_into(voxels, cell, value, config.reduce)
    return bytes(voxels)
