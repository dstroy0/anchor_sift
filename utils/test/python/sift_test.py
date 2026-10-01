#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grades sift.anchors' kernel form against the kernel in src/engine/nbody/anchor_sift/, count for count and read for
# read.
#
#   python utils/test/harness.py run engine_c
#
# The kernel places four anchors in a needle, orders them by rarity in the corpus, dispatches between a short
# circuiting and a free order engine by one exact comparison, and counts exact occurrences. sift/anchors.py holds its
# Python route. The two share no code. Each case runs both on one corpus and needle and compares, item by item: the
# census, the dispatch rule and the engine chosen, the anchor count for a plan, every engine's count with the probe
# reads and exact compares a counted build records (the reads pin the offsets the kernel placed and the order it
# probed them in), the steered and unsteered counts with their reads, the rarity order of given offsets, counts with
# caller probes, and whether probes fit. It prints for each case the count, the in order and steered reads on each
# side, the items compared and how many differ.
#
# It needs anchor_sift_host (src/engine/CMakeLists.txt): the kernel's host sources and the exact_integer sources built
# as a shared library with ANCHOR_SIFT_COUNT_READS=1, on Windows with utils/test/python/anchor_sift_probe.def. The harness
# env engine_c runs it from utils/maint/engine/build_engine.sh, which builds the library and names it in ANCHOR_SIFT_LIB.
# Without that, anchor_sift_host.dll or libanchor_sift_host.so is searched for under build/. A missing library fails
# the run and is never skipped.

import ctypes
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from sift.anchors import (  # noqa: E402
    SIFT_ANCHORS, Probe, choose_offsets, field_census, sift_anchors_for, sift_choose, sift_count, sift_run,
    steer_count, steer_count_with_probes, steer_magnitude, steer_prefers_free, steer_probe_fits, steer_probe_order)


class _Census(ctypes.Structure):
    _fields_ = [("occurrences", ctypes.c_uint64 * 256), ("total", ctypes.c_uint64), ("distinct", ctypes.c_uint32)]


class _Plan(ctypes.Structure):
    _fields_ = [("census", ctypes.POINTER(_Census)), ("needle_len", ctypes.c_size_t), ("period", ctypes.c_size_t)]


class _Probe(ctypes.Structure):
    _fields_ = [("origin", ctypes.c_size_t), ("step", ctypes.c_size_t), ("length", ctypes.c_size_t)]


def find_library():
    given = os.environ.get("ANCHOR_SIFT_LIB")
    if given and os.path.isfile(given):
        return given
    for base, _dirs, files in os.walk(os.path.join(ROOT, "build")):
        for name in ("anchor_sift_host.dll", "libanchor_sift_host.so"):
            if name in files:
                return os.path.join(base, name)
    return None


def load(path):
    lib = ctypes.CDLL(path)
    counting = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]
    for name in ("anchor_sift_naive", "anchor_sift_inorder", "anchor_sift_free"):
        getattr(lib, name).argtypes = counting
        getattr(lib, name).restype = ctypes.c_size_t
    lib.anchor_sift_run.argtypes = [ctypes.POINTER(_Plan)] + counting
    lib.anchor_sift_run.restype = ctypes.c_size_t
    lib.anchor_sift_choose.argtypes = [ctypes.POINTER(_Plan)]
    lib.anchor_sift_choose.restype = ctypes.c_void_p
    lib.anchor_sift_engine_name.argtypes = [ctypes.c_void_p]
    lib.anchor_sift_engine_name.restype = ctypes.c_char_p
    lib.anchor_sift_anchors_for.argtypes = [ctypes.POINTER(_Plan)]
    lib.anchor_sift_anchors_for.restype = ctypes.c_size_t
    lib.anchor_field_census.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(_Census)]
    lib.anchor_steer_magnitude.argtypes = [ctypes.POINTER(_Census), ctypes.c_uint8]
    lib.anchor_steer_magnitude.restype = ctypes.c_uint64
    lib.anchor_steer_probe_order.argtypes = [ctypes.POINTER(ctypes.c_size_t), ctypes.c_size_t,
                                             ctypes.POINTER(_Census), ctypes.c_char_p, ctypes.c_size_t]
    lib.anchor_steer_prefers_free.argtypes = [ctypes.POINTER(_Census)]
    lib.anchor_steer_prefers_free.restype = ctypes.c_int
    lib.anchor_steer_count.argtypes = counting + [ctypes.c_int]
    lib.anchor_steer_count.restype = ctypes.c_size_t
    lib.anchor_steer_count_with_probes.argtypes = counting + [ctypes.POINTER(_Probe), ctypes.c_size_t]
    lib.anchor_steer_count_with_probes.restype = ctypes.c_size_t
    lib.anchor_steer_probe_fits.argtypes = [ctypes.POINTER(_Probe), ctypes.c_size_t]
    lib.anchor_steer_probe_fits.restype = ctypes.c_int
    return lib


def stream(seed):
    """A xorshift64 stream, the same generator on every run."""
    state = seed
    while True:
        state ^= (state << 13) & 0xFFFFFFFFFFFFFFFF
        state ^= state >> 7
        state ^= (state << 17) & 0xFFFFFFFFFFFFFFFF
        yield state


def uniform(count, seed, values=256):
    source = stream(seed)
    return bytes(next(source) % values for _ in range(count))


def skewed(count, seed):
    """Bytes of a few values at falling weights, a field whose effective alphabet sits well below its values used."""
    weights = [(ord("e"), 40), (ord("t"), 20), (ord("a"), 12), (ord(" "), 10), (ord("n"), 6), (ord("q"), 3),
               (ord("z"), 1)]
    table = [value for value, weight in weights for _ in range(weight)]
    source = stream(seed)
    return bytes(table[next(source) % len(table)] for _ in range(count))


def cases():
    """(name, corpus, needle, period) for every graded case, the period the plan carries."""
    flat = uniform(4096, 0x9E3779B97F4A7C15)
    yield "flat 4096 n12", flat, flat[1000:1012], 0
    text = skewed(4096, 0xD1B54A32D192ED03)
    yield "skewed 4096 n16", text, text[2048:2064], 0
    yield "skewed 4096 n3", text, text[77:80], 0
    comb = bytes((at * 37) % 251 for at in range(16)) * 256
    yield "period 16 n20", comb, comb[5:25], 16
    yield "period 16 n20 unplanned", comb, comb[5:25], 0
    two = uniform(2048, 0x2545F4914F6CDD1D, 2)
    yield "binary 2048 n24", two, two[300:324], 0
    yield "binary 2048 n5", two, two[9:14], 0
    yield "binary 2048 n8", two, two[64:72], 0
    yield "flat 4096 n1", flat, flat[17:18], 0
    yield "flat 4096 n33", flat, flat[3000:3033], 0
    yield "absent symbol", text, b"eetq\x00ae", 0
    yield "needle past corpus", flat[:10], flat[:11], 0
    yield "empty needle", flat[:100], b"", 0
    yield "empty corpus", b"", b"ab", 0


def c_census(lib, corpus):
    census = _Census()
    lib.anchor_field_census(corpus, len(corpus), ctypes.byref(census))
    return census


def census_row(census):
    """(total, distinct, CRC of the occurrences as little endian 64 bit words) of either side's census."""
    occurrences = list(census.occurrences)
    return census.total, census.distinct, "%08x" % zlib.crc32(struct.pack("<256Q", *occurrences))


def c_counted(lib, name, corpus, needle):
    lib.anchor_sift_counters_reset()
    found = getattr(lib, name)(corpus, len(corpus), needle, len(needle))
    return (found, ctypes.c_uint64.in_dll(lib, "anchor_sift_probes").value,
            ctypes.c_uint64.in_dll(lib, "anchor_sift_verifications").value)


def c_run(lib, plan, corpus, needle):
    lib.anchor_sift_counters_reset()
    found = lib.anchor_sift_run(plan, corpus, len(corpus), needle, len(needle))
    return (found, ctypes.c_uint64.in_dll(lib, "anchor_sift_probes").value,
            ctypes.c_uint64.in_dll(lib, "anchor_sift_verifications").value)


def c_steered(lib, corpus, needle, steered):
    lib.anchor_steer_probes_reset()
    found = lib.anchor_steer_count(corpus, len(corpus), needle, len(needle), steered)
    return found, ctypes.c_uint64.in_dll(lib, "anchor_steer_probes").value


def c_with_probes(lib, corpus, needle, probes):
    probe_array = (_Probe * max(1, len(probes)))(*[_Probe(*probe) for probe in probes])
    lib.anchor_steer_probes_reset()
    found = lib.anchor_steer_count_with_probes(corpus, len(corpus), needle, len(needle), probe_array, len(probes))
    return found, ctypes.c_uint64.in_dll(lib, "anchor_steer_probes").value


def c_order(lib, offsets, census, needle):
    offset_array = (ctypes.c_size_t * max(1, len(offsets)))(*offsets)
    lib.anchor_steer_probe_order(offset_array, len(offsets), ctypes.byref(census), needle, len(needle))
    return list(offset_array)[:len(offsets)]


def probe_sets(needle_len):
    """Caller probe sets: arms, an eye, one that cannot fit, and none."""
    last = max(needle_len - 1, 0)
    yield "arms", [Probe(last, 0, 1), Probe(0, 0, 1)]
    yield "eye", [Probe(0, 2, (last // 2) + 1 if needle_len else 1), Probe(last // 3, 0, 1)]
    yield "past", [Probe(0, 1, needle_len + 1)]
    yield "none", []


def fit_probes(needle_len):
    return [Probe(0, 0, 1), Probe(0, 0, 2), Probe(0, 1, needle_len), Probe(0, 1, needle_len + 1),
            Probe(needle_len, 0, 1), Probe(1, 3, 4), Probe(0, (1 << 63), 3), Probe(0, 1, 0)]


def grade(lib, corpus, needle, period):
    """[(item, C value, Python value)] for one case."""
    items = []
    c_side = c_census(lib, corpus)
    py_side = field_census(corpus)
    items.append(("census", census_row(c_side), census_row(py_side)))
    items.append(("magnitudes", [lib.anchor_steer_magnitude(ctypes.byref(c_side), value) for value in needle[:8]],
                  [steer_magnitude(py_side, value) for value in needle[:8]]))
    items.append(("prefers free", lib.anchor_steer_prefers_free(ctypes.byref(c_side)), int(steer_prefers_free(py_side))))
    plan = _Plan(ctypes.pointer(c_side), len(needle), period)
    items.append(("choose", lib.anchor_sift_engine_name(lib.anchor_sift_choose(ctypes.byref(plan))).decode(),
                  sift_choose(py_side)))
    items.append(("choose, no plan", lib.anchor_sift_engine_name(lib.anchor_sift_choose(None)).decode(),
                  sift_choose(None)))
    items.append(("anchors for", lib.anchor_sift_anchors_for(ctypes.byref(plan)), sift_anchors_for(period)))
    items.append(("anchors for, no plan", lib.anchor_sift_anchors_for(None), sift_anchors_for(0)))
    for name, engine in (("anchor_sift_naive", "naive"), ("anchor_sift_inorder", "anchor_inorder"),
                         ("anchor_sift_free", "anchor_free")):
        items.append((engine, c_counted(lib, name, corpus, needle), tuple(sift_count(corpus, needle, engine))))
    items.append(("run", c_run(lib, ctypes.byref(plan), corpus, needle), tuple(sift_run(py_side, period, corpus,
                                                                                         needle))))
    items.append(("run, no plan", c_run(lib, None, corpus, needle), tuple(sift_run(None, 0, corpus, needle))))
    for steered in (0, 1):
        items.append(("steer %d" % steered, c_steered(lib, corpus, needle, steered),
                      steer_count(corpus, needle, steered)))
    placed = choose_offsets(SIFT_ANCHORS, len(needle))
    for label, offsets in (("order placed", placed), ("order reversed", placed[::-1]),
                           ("order past", [len(needle) + 3] + placed[:3])):
        items.append((label, c_order(lib, offsets, c_side, needle), steer_probe_order(offsets, py_side, needle)))
    for label, probes in probe_sets(len(needle)):
        items.append(("probes " + label, c_with_probes(lib, corpus, needle, probes),
                      steer_count_with_probes(corpus, needle, probes)))
    fitted = fit_probes(len(needle))
    items.append(("fits", [lib.anchor_steer_probe_fits(ctypes.byref(_Probe(*probe)), len(needle)) for probe in fitted],
                  [int(steer_probe_fits(probe, len(needle))) for probe in fitted]))
    return items


def flat(value):
    """A value as plain ints and strings, the same form from either side."""
    return tuple(value) if isinstance(value, (list, tuple)) else value


def main():
    path = find_library()
    if path is None:
        print("  anchor_sift_host library not found: set ANCHOR_SIFT_LIB, or build it under build/.")
        return 1
    lib = load(path)
    print("\n  sift.anchors AGAINST nbody/anchor_sift, count for count and read for read. library: %s\n" % path)
    print("  %-24s %-4s %-6s %-22s %-14s %-14s %-6s %s" % (
        "case", "side", "found", "in order probes/verif", "steered reads", "engine", "items", "verdict"))
    failed = 0
    graded = 0
    for name, corpus, needle, period in cases():
        graded += 1
        items = grade(lib, corpus, needle, period)
        differ = [label for label, c_value, py_value in items if flat(c_value) != flat(py_value)]
        ok = not differ
        failed += 0 if ok else 1
        found = dict((label, (c_value, py_value)) for label, c_value, py_value in items)
        for side, at in (("C", 0), ("py", 1)):
            inorder = found["anchor_inorder"][at]
            print("  %-24s %-4s %-6d %-22s %-14d %-14s %-6s %s" % (
                name if at == 0 else "", side, found["naive"][at][0], "%d/%d" % (inorder[1], inorder[2]),
                found["steer 1"][at][1], found["choose"][at], len(items) if at else "",
                "" if at == 0 else ("%d differ ok" % len(differ) if ok else "FAILS: " + ", ".join(differ))))
    print("\n  %d checks, %d failed\n" % (graded, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
