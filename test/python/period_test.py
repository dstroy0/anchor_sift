#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grades measure.period against period_read and period_draw, line for line.
#
#   python test/harness.py run python_period
#
# period_read (src/engine/analysis/period/) reads a volume of 16 bit lanes on the device and returns, for each
# axis, the agreement at every lag, the null band its line shuffles draw, and the period chosen against that band.
# measure/period.py computes the same measurement on the host in exact integers. The two share no code. This writes
# every case to one requests file, runs test/python/period_probe.cu on it (the engine's entry points, printing each
# measurement in full with every ratio as its exact numerator and denominator), writes the Python measurement in the
# probe's lines, and counts the lines that differ. It prints for each case, for each side, the period and candidate of
# each axis, the margins, and the CRC-32 of the full measurement. The errors are graded too: the engine returns -1
# where the Python returns None, and the engine's error line is shown and not compared.
#
# The harness env python_period runs it through test/python/period_test.sh, which builds period_probe (period_probe.cu
# with period_measure.cu, period_select.cu, device_pool.cu, sim_job.cu, the scriptura sources and the exact_integer
# sources), a job on the device's tessera daemon, and names it in ANCHOR_PERIOD_PROBE. Without that, period_probe.exe
# or period_probe is searched for under build/. A missing probe fails the run and is never skipped.

import os
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.period import ARRAY_RANK, draw, read  # noqa: E402

MAGIC = 0x31445250


def find_probe():
    given = os.environ.get("ANCHOR_PERIOD_PROBE")
    if given and os.path.isfile(given):
        return given
    for base, _dirs, files in os.walk(os.path.join(ROOT, "build")):
        for name in ("period_probe.exe", "period_probe"):
            if name in files:
                return os.path.join(base, name)
    return None


def stream(seed):
    """A xorshift64 stream, the same generator on every run."""
    state = seed
    while True:
        state ^= (state << 13) & 0xFFFFFFFFFFFFFFFF
        state ^= state >> 7
        state ^= (state << 17) & 0xFFFFFFFFFFFFFFFF
        yield state


def signum(seed):
    source = stream(seed)
    return b"".join(struct.pack("<Q", next(source)) for _ in range(4))


def noisy(lanes, seed, per_thousand, values=65536):
    """The lanes with about per_thousand of each thousand replaced by a drawn value."""
    source = stream(seed)
    out = []
    for lane in lanes:
        if (next(source) % 1000) < per_thousand:
            out.append(next(source) % values)
        else:
            out.append(lane)
    return out


def drawn(count, seed, values):
    source = stream(seed)
    return [next(source) % values for _ in range(count)]


def places(extent):
    """Every index tuple of an extent, row major with the last axis fastest."""
    if not extent:
        yield ()
        return
    for head in range(extent[0]):
        for rest in places(extent[1:]):
            yield (head,) + rest


def cases():
    """(name, mode, extent, draws or draw number, content, null top or None, lanes) for every graded case."""
    motif = [101, 3202, 77, 5150, 919, 64000, 12]
    line = noisy([motif[at % 7] for at in range(96)], 0x9E3779B97F4A7C15, 100)
    yield "line 96 p7", "read", (96,), 32, signum(1), None, line

    high = noisy([65531 + (at % 5) for at in range(64)], 0xD1B54A32D192ED03, 80)
    yield "line 64 high p5", "read", (64,), 16, signum(2), None, high

    column = drawn(40, 0x2545F4914F6CDD1D, 4096)
    rows = [7, 1900, 33, 40000, 512, 9]
    plane = noisy([((column[c] * 7) + rows[r % 6]) & 0xFFFF for r, c in places((48, 40))],
                  0x94D049BB133111EB, 60)
    yield "plane 48x40 p6,-", "read", (48, 40), 16, signum(3), None, plane

    first = [5, 600, 70]
    second = [1, 2, 3, 4, 5]
    third = [11, 900, 13, 1400]
    box = noisy([(first[i % 3] + (second[j % 5] * 17) + (third[k % 4] * 257)) & 0xFFFF
                 for i, j, k in places((14, 22, 18))], 0xBF58476D1CE4E5B9, 50)
    yield "box 14x22x18 p3,5,4", "read", (14, 22, 18), 6, signum(4), None, box

    yield "plane 30x30 four", "read", (30, 30), 12, signum(5), None, drawn(900, 0x369DEA0F31A53F85, 4)
    yield "plane 20x20 even", "read", (20, 20), 4, signum(6), None, [9] * 400
    yield "plane 48x40 given", "read", (48, 40), 0, signum(3), [(5, 960), (0, 960)], plane
    yield "rank 4 10x3x12x4", "read", (10, 3, 12, 4), 4, signum(7), None, drawn(1440, 0x7F4A7C159E3779B9, 3)
    yield "rank 8 2^7x10", "read", (2,) * 7 + (10,), 2, signum(8), None, drawn(1280, 0xA24BAED4963EE407, 2)
    yield "line 1", "read", (1,), 3, signum(9), None, [7]
    yield "line 5", "read", (5,), 3, signum(10), None, [1, 2, 1, 2, 1]

    yield "draw 0 plane", "draw", (48, 40), 0, signum(3), None, plane
    yield "draw 7 plane", "draw", (48, 40), 7, signum(3), None, plane
    yield "draw 5 box", "draw", (14, 22, 18), 5, signum(4), None, box
    yield "draw 0 line 1", "draw", (1,), 0, signum(9), None, [7]

    yield "error rank 0", "read", (), 1, signum(11), None, []
    yield "error rank 9", "read", (1,) * 9, 1, signum(11), None, [0]
    yield "error extent 0", "read", (4, 0), 1, signum(11), None, []
    yield "error 2^32 voxels", "read", (65536, 65536), 1, signum(11), None, []
    yield "error draws 0", "read", (8,), 0, signum(11), None, [0] * 8
    yield "error draws 2^29", "read", (8,), 536870912, signum(11), None, [0] * 8
    yield "error top, draws", "read", (8,), 3, signum(11), [(1, 4)], [0] * 8
    yield "draw error extent 0", "draw", (4, 0), 0, signum(11), None, []


def record(mode, extent, draws, content, null_top, lanes):
    fields = struct.pack("<IIII", MAGIC, 0 if mode == "read" else 1, len(extent), 0 if null_top is None else 1)
    extents = list(extent[:ARRAY_RANK]) + [0] * (ARRAY_RANK - min(len(extent), ARRAY_RANK))
    fields += struct.pack("<%dQ" % ARRAY_RANK, *extents)
    fields += struct.pack("<Q", draws) + content
    tops = list(null_top or []) + [(0, 0)] * (ARRAY_RANK - len(null_top or []))
    for numerator, denominator in tops:
        fields += struct.pack("<QQ", numerator, denominator)
    fields += struct.pack("<Q", len(lanes)) + struct.pack("<%dH" % len(lanes), *lanes)
    return fields


def ratio(pair):
    return "%d/%d" % pair


def python_block(number, mode, extent, draws, content, null_top, lanes):
    """The Python measurement in the probe's lines."""
    if mode == "draw":
        heights = draw(lanes, extent, draws, content)
        if heights is None:
            return ["case %d mode draw status -1" % number]
        return ["case %d mode draw status 0" % number,
                "heights %d %s" % (len(heights), " ".join(ratio(one) for one in heights))]
    measurement = read(lanes, extent, draws, content, null_top)
    if measurement is None:
        return ["case %d mode read status -1" % number]
    lines = ["case %d mode read status 0" % number,
             "measurement rank %d voxels %d collisions %d draws %d" % (
                 measurement.rank, measurement.voxels, measurement.collisions, measurement.draws)]
    for at, axis in enumerate(measurement.axis):
        lines.append(
            "axis %d extent %d period %d candidate %d lags %d pairs %d at %d beside %d doubled %d beside_double %d "
            "margin %s band_count %d bottom %s top %s" % (
                at, axis.extent, axis.period, axis.candidate, axis.lags, axis.pairs_per_lag,
                axis.agreement_at_candidate, axis.agreement_beside_candidate, axis.agreement_at_double,
                axis.agreement_beside_double, ratio(axis.margin), axis.band_count, ratio(axis.band_bottom),
                ratio(axis.band_top)))
    lines.append(" ".join(["agreement %d" % len(measurement.agreement)]
                          + ["%d" % one for one in measurement.agreement]))
    lines.append(" ".join(["band %d" % len(measurement.band)] + [ratio(one) for one in measurement.band]))
    return lines


def engine_blocks(text):
    """The probe's lines per case, the end marker dropped."""
    blocks = []
    block = None
    for line in text.splitlines():
        if line.startswith("case "):
            block = [line]
        elif line == "end" and block is not None:
            blocks.append(block)
            block = None
        elif block is not None:
            block.append(line)
    return blocks


def summary(block):
    """(status, periods, margins, bands, crc) of one side's block."""
    status = block[0].split()[-1]
    periods = []
    margins = []
    bands = []
    for line in block:
        words = line.split()
        if words[0] == "axis":
            periods.append("%s/%s" % (words[words.index("period") + 1], words[words.index("candidate") + 1]))
            margins.append(words[words.index("margin") + 1])
            bands.append("%s:%s" % (words[words.index("band_count") + 1], words[words.index("top") + 1]))
        elif words[0] == "heights":
            margins.extend(words[2:])
    graded = "\n".join(line for line in block if not line.startswith("error "))
    return (status, ",".join(periods) or "-", ",".join(margins) or "-", ",".join(bands) or "-",
            "%08x" % (zlib.crc32(graded.encode()) & 0xFFFFFFFF))


def main():
    probe = find_probe()
    if probe is None:
        print("  period_probe not found: set ANCHOR_PERIOD_PROBE, or build it under build/.")
        return 1
    graded = list(cases())
    folder = tempfile.mkdtemp(prefix="period_test_")
    path = os.path.join(folder, "requests.bin")
    with open(path, "wb") as out:
        for _name, mode, extent, draws, content, null_top, lanes in graded:
            out.write(record(mode, extent, draws, content, null_top, lanes))
    try:
        ran = subprocess.run([probe, path], capture_output=True, text=True, timeout=600)
    finally:
        os.remove(path)
        os.rmdir(folder)
    blocks = engine_blocks(ran.stdout)

    print("\n  measure.period AGAINST period_read and period_draw, line for line. probe: %s\n" % probe)
    print("  %-21s %-4s %-6s %-16s %-28s %-30s %-8s %s" % (
        "case", "side", "status", "period/candidate", "margin", "band count:top", "crc", "verdict"))
    failed = 0
    for number, (name, mode, extent, draws, content, null_top, lanes) in enumerate(graded):
        mine = python_block(number, mode, extent, draws, content, null_top, lanes)
        theirs = blocks[number] if number < len(blocks) else ["case %d missing status -" % number]
        c_graded = [line for line in theirs if not line.startswith("error ")]
        differ = sum(1 for one, other in zip(c_graded, mine) if one != other) + abs(len(c_graded) - len(mine))
        ok = differ == 0
        failed += 0 if ok else 1
        c_status, c_periods, c_margins, c_bands, c_crc = summary(theirs)
        py_status, py_periods, py_margins, py_bands, py_crc = summary(mine)
        print("  %-21s %-4s %-6s %-16s %-28s %-30s %-8s" % (
            name, "C", c_status, c_periods, c_margins, c_bands, c_crc))
        print("  %-21s %-4s %-6s %-16s %-28s %-30s %-8s %d differ %s" % (
            "", "py", py_status, py_periods, py_margins, py_bands, py_crc, differ, "ok" if ok else "FAILS"))
        for line in theirs:
            if line.startswith("error "):
                print("  %-21s      engine %s" % ("", line))

    print("\n  %d case(s), %d failed; probe exit %d, %d measurement(s) printed\n" % (
        len(graded), failed, ran.returncode, len(blocks)))
    return 0 if failed == 0 and ran.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
