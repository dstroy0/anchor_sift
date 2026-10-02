#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grades measure.shift_agreement.frame_shift against shift_agreement_host, count for count.
#
#   python utils/test/harness.py run engine_c
#
# shift_agreement_host (src/c/engine/analysis/shift_agreement/shift_agreement.c) reads two occupancy
# volumes of up to eight axes and returns, for every lag vector, how many voxels occupied in the
# first have the voxel that lag away occupied in the second, through a number theoretic transform
# over 998244353. frame_shift counts the same pairs one by one in Python. The two share no code.
# Each case runs both on the same volumes and prints, for each side, the lag chosen, the count at
# it, and the CRC-32 of the full count array laid out the way the C returns it (each axis's lag
# modulo its transform length, the last axis fastest, one little endian 32 bit count an entry),
# and then how many entries differ. The errors are graded too: the C returns -1 where
# frame_shift returns None.
#
# It needs shift_agreement_host (src/c/CMakeLists.txt): shift_agreement.c built alone as a
# shared library with SHIFT_AGREEMENT_BUILD_DLL=1, which exports the entry. The harness env engine_c
# runs it from utils/maint/engine/build_engine.sh, which builds the library and names it in
# ANCHOR_SHIFT_LIB. Without that, shift_agreement_host.dll or libshift_agreement_host.so is
# searched for under build/. A missing library fails the run and is never skipped.

import ctypes
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))))))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
import manifest  # noqa: E402,F401

from measure.shift_agreement import FRAME_AXES, frame_shift  # noqa: E402


class _Request(ctypes.Structure):
    _fields_ = [
        ("axes", ctypes.c_uint),
        ("extents", ctypes.c_uint * FRAME_AXES),
        ("weights", ctypes.c_uint * FRAME_AXES),
        ("before", ctypes.POINTER(ctypes.c_ulonglong)),
        ("after", ctypes.POINTER(ctypes.c_ulonglong)),
        ("lag", ctypes.c_int * FRAME_AXES),
        ("agreement", ctypes.c_uint),
        ("padded", ctypes.c_uint * FRAME_AXES),
        ("counts", ctypes.POINTER(ctypes.c_uint)),
    ]


def find_library():
    given = os.environ.get("ANCHOR_SHIFT_LIB")
    if given and os.path.isfile(given):
        return given
    for base, _dirs, files in os.walk(os.path.join(ROOT, "build")):
        for name in ("shift_agreement_host.dll", "libshift_agreement_host.so"):
            if name in files:
                return os.path.join(base, name)
    return None


def draws(seed):
    """A xorshift64 stream, the same generator on every run."""
    state = seed
    while True:
        state ^= (state << 13) & 0xFFFFFFFFFFFFFFFF
        state ^= state >> 7
        state ^= (state << 17) & 0xFFFFFFFFFFFFFFFF
        yield state


def mask(voxels, seed, per_thousand):
    stream = draws(seed)
    return [1 if (next(stream) % 1000) < per_thousand else 0 for _ in range(voxels)]


def moved(extents, occupancy, shift):
    """The occupancy carried by a shift vector, voxels leaving the box dropped."""
    out = [0] * len(occupancy)
    for at, occupied in enumerate(occupancy):
        if not occupied:
            continue
        rest = at
        place = []
        for extent in reversed(extents):
            place.append(rest % extent)
            rest //= extent
        place = [one + step for one, step in zip(reversed(place), shift)]
        if all(0 <= one < extent for one, extent in zip(place, extents)):
            index = 0
            for one, extent in zip(place, extents):
                index = (index * extent) + one
            out[index] = 1
    return out


def words(occupancy):
    """Occupancy packed into 64 bit words, bit (position mod 64) of word position / 64."""
    packed = [0] * ((len(occupancy) + 63) // 64 or 1)
    for at, occupied in enumerate(occupancy):
        if occupied:
            packed[at // 64] |= 1 << (at % 64)
    return (ctypes.c_ulonglong * len(packed))(*packed)


def padded_of(extent):
    power = 1
    while power < (2 * extent) - 1:
        power <<= 1
    return power


def c_side(lib, extents, weights, before, after):
    """The C's (lag, agreement, counts as bytes) or None where it returned an error."""
    request = _Request()
    request.axes = len(extents)
    for axis in range(min(len(extents), FRAME_AXES)):
        request.extents[axis] = extents[axis]
        request.weights[axis] = weights[axis]
    total = 1
    for extent in extents[:FRAME_AXES]:
        total *= padded_of(extent) if extent else 1
    before_words = words(before)
    after_words = words(after)
    request.before = ctypes.cast(before_words, ctypes.POINTER(ctypes.c_ulonglong))
    request.after = ctypes.cast(after_words, ctypes.POINTER(ctypes.c_ulonglong))
    counts = (ctypes.c_uint * total)() if 0 < total <= (1 << 24) else None
    request.counts = ctypes.cast(counts, ctypes.POINTER(ctypes.c_uint)) if counts else None
    status = lib.shift_agreement_host(ctypes.byref(request))
    if status != 0:
        return None
    lag = tuple(request.lag[axis] for axis in range(len(extents)))
    return lag, request.agreement, bytes(counts)


def python_side(extents, weights, before, after):
    """frame_shift's (lag, agreement, counts laid out as the C lays them) or None."""
    found = frame_shift(extents, before, after, weights)
    if found is None:
        return None
    lag, agreement, counts = found
    padded = [padded_of(extent) for extent in extents]
    total = 1
    for length in padded:
        total *= length
    layout = [0] * total
    for vector, count in counts.items():
        index = 0
        for one, length in zip(vector, padded):
            index = (index * length) + (one % length)
        layout[index] = count
    return lag, agreement, struct.pack("<%dI" % total, *layout)


def cases():
    """(name, extents, weights, before, after) for every graded case."""
    one = mask(37, 0x9E3779B97F4A7C15, 300)
    yield "line 37", (37,), (1,), one, moved((37,), one, (5,))
    wide = mask(64, 0xD1B54A32D192ED03, 500)
    yield "line 64 self", (64,), (1,), wide, wide
    plane = mask(9 * 13, 0x2545F4914F6CDD1D, 250)
    yield "plane 9x13", (9, 13), (1, 1), plane, moved((9, 13), plane, (-2, 3))
    square = mask(16 * 16, 0x94D049BB133111EB, 400)
    yield "plane 16x16 w", (16, 16), (4, 1), square, moved((16, 16), square, (1, -4))
    noise_a = mask(12 * 10, 0xBF58476D1CE4E5B9, 350)
    noise_b = mask(12 * 10, 0x369DEA0F31A53F85, 350)
    yield "plane 12x10 two", (12, 10), (1, 1), noise_a, noise_b
    box = mask(5 * 6 * 7, 0x7F4A7C159E3779B9, 300)
    yield "box 5x6x7", (5, 6, 7), (1, 1, 1), box, moved((5, 6, 7), box, (1, 0, -2))
    cube = mask(8 * 8 * 8, 0xA24BAED4963EE407, 200)
    yield "box 8x8x8 w", (8, 8, 8), (9, 4, 1), cube, moved((8, 8, 8), cube, (0, 2, 1))
    sparse = [0] * 64
    sparse[3] = 1
    sparse[40] = 1
    yield "self 8x8", (8, 8), (1, 1), sparse, sparse
    # One voxel before and two after, one lag to each: the counts tie at 1. Lags (1, 0) and (-1, 0)
    # tie on length as well, and the C's scan meets (1, 0) first. Lags (1, 0) and (0, 2) under
    # weights (9, 1) have lengths 9 and 4, and the shorter wins.
    center = [0] * 25
    center[12] = 1
    both_sides = [0] * 25
    both_sides[17] = 1
    both_sides[7] = 1
    yield "tie 5x5 order", (5, 5), (1, 1), center, both_sides
    two_ways = [0] * 25
    two_ways[17] = 1
    two_ways[14] = 1
    yield "tie 5x5 weight", (5, 5), (9, 1), center, two_ways
    yield "empty 4x4", (4, 4), (1, 1), [0] * 16, [0] * 16
    yield "error 0 axes", (), (), [0], [0]
    yield "error extent 0", (4, 0), (1, 1), [0], [0]
    yield "error 9 axes", (1,) * 9, (1,) * 9, [0], [0]
    yield "error 2^22+1", ((1 << 22) + 1,), (1,), [0] * 8, [0] * 8


def crc(data):
    return "%08x" % (zlib.crc32(data) & 0xFFFFFFFF)


def differing(left, right):
    if len(left) != len(right):
        return max(len(left), len(right)) // 4
    return sum(1 for at in range(0, len(left), 4) if left[at:at + 4] != right[at:at + 4])


def main():
    path = find_library()
    if path is None:
        print("  shift_agreement_host library not found: set ANCHOR_SHIFT_LIB, or build it under build/.")
        return 1
    lib = ctypes.CDLL(path)
    lib.shift_agreement_host.restype = ctypes.c_long
    lib.shift_agreement_host.argtypes = [ctypes.POINTER(_Request)]

    print("\n  frame_shift AGAINST shift_agreement_host, count for count. library: %s\n" % path)
    print("  %-17s %-12s %-12s %6s %6s %9s %9s %6s %s" % (
        "case", "C lag", "py lag", "C agr", "py agr", "C crc", "py crc", "diff", "verdict"))

    failed = 0
    graded = 0
    for name, extents, weights, before, after in cases():
        graded += 1
        c = c_side(lib, extents, weights, before, after)
        py = python_side(extents, weights, before, after)
        if c is None or py is None:
            ok = c is None and py is None
            print("  %-17s %-12s %-12s %6s %6s %9s %9s %6s %s" % (
                name, "error" if c is None else str(c[0]), "error" if py is None else str(py[0]),
                "-", "-", "-", "-", "-", "ok" if ok else "FAILS"))
        else:
            diff = differing(c[2], py[2])
            ok = c[0] == py[0] and c[1] == py[1] and diff == 0
            print("  %-17s %-12s %-12s %6d %6d %9s %9s %6d %s" % (
                name, str(c[0]).replace(" ", ""), str(py[0]).replace(" ", ""), c[1], py[1],
                crc(c[2]), crc(py[2]), diff, "ok" if ok else "FAILS"))
        failed += 0 if ok else 1

    print("\n  %d checks, %d failed\n" % (graded, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
