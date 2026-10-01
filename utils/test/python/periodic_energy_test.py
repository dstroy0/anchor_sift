#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grades measure.periodic_energy's engine form against src/sims/cu/engine/analysis/art/periodic_energy.h, line for line.
#
#   python utils/test/harness.py run python_periodic_energy
#
# periodic_energy.h reads the period a coherent addend keeps from the dispersion ratio of its phase classes, draws its
# null from shuffles, and removes each phase's mean; the fixed_pattern and classify_reject_recover sims call it.
# measure/periodic_energy.py holds its Python route. The two share no code. This writes every case to one requests
# file, runs utils/test/src/cu/engine/analysis/periodic_energy_probe.cu on it (the header's functions, printing every exact integer in
# full), writes the Python results in the probe's lines, and counts the lines that differ. It prints for each case, for
# each side, the recovered period and its ratio to three places, the band's reach and top, whether the live
# measurement stands above it, the reduction, and the CRC-32 of the full block. The "results" lines, where a device
# call failed, are shown and not compared.
#
# The harness env python_periodic_energy runs it through utils/test/python/periodic_energy_test.sh, which builds
# periodic_energy_probe (periodic_energy_probe.cu with sim_job.cu, the scriptura sources and the exact_integer
# sources), a job on the device's tessera daemon, and names it in ANCHOR_PERIODIC_ENERGY_PROBE. Without that,
# periodic_energy_probe.exe or periodic_energy_probe is searched for under build/. A missing probe fails the run and
# is never skipped.

import os
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.periodic_energy import (  # noqa: E402
    energy_above, energy_band_top, energy_print, energy_ratio, energy_recover, energy_reduction, energy_shuffle,
    energy_welford, ratio_text)

MAGIC = 0x314E4550


def find_probe():
    given = os.environ.get("ANCHOR_PERIODIC_ENERGY_PROBE")
    if given and os.path.isfile(given):
        return given
    for base, _dirs, files in os.walk(os.path.join(ROOT, "build")):
        for name in ("periodic_energy_probe.exe", "periodic_energy_probe"):
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


def spread(count, seed, low, high):
    """count integers drawn from low to high inclusive."""
    source = stream(seed)
    return [low + (next(source) % (high - low + 1)) for _ in range(count)]


def cases():
    """(name, values, target or None, reach, draws, key, period, places) for every graded case."""
    scene = spread(3072, 0x9E3779B97F4A7C15, 0, 199)
    hum = spread(64, 0xD1B54A32D192ED03, -40, 40)
    noise = spread(3072, 0x2545F4914F6CDD1D, -20, 20)
    stack = [scene[at] + hum[at % 64] + noise[at] for at in range(3072)]
    yield "frame 64 hum", stack, scene, 64, 8, 0xF17A, 64, 3

    addend = spread(7, 0x94D049BB133111EB, -30, 30)
    rest = spread(200, 0xBF58476D1CE4E5B9, -25, 25)
    yield "line 200 p7", [rest[at] + addend[at % 7] for at in range(200)], rest, 30, 6, 0x5EED, 7, 6

    loose = spread(150, 0x369DEA0F31A53F85, -50, 50)
    yield "random 150", loose, [0] * 150, 20, 5, 0xC0FFEE, 10, 3

    motif = [4, -9, 17, 0, 3, 3, -1, 12]
    yield "exact repeat 96 p8", [motif[at % 8] for at in range(96)], None, 20, 4, 0xA11, 8, 3
    yield "constant 50", [5] * 50, [5] * 50, 10, 3, 0xB22, 5, 3
    yield "length 4", [3, -1, 4, 1], [0, 0, 0, 0], 3, 3, 0xC33, 2, 3
    yield "length 3", [1, 2, 3], None, 5, 2, 0xD44, 2, 3
    yield "reach 1", spread(20, 0x7F4A7C159E3779B9, -9, 9), None, 1, 2, 0xE55, 3, 3
    yield "reach 0", spread(20, 0x7F4A7C159E3779B9, -9, 9), None, 0, 2, 0xE55, 3, 3

    wide = spread(500, 0xA24BAED4963EE407, -30000, 30000)
    yield "wide 500", wide, spread(500, 0x9FB21C651E98DF25, -30000, 30000), 40, 4, 0xF66, 25, 3

    tenth = spread(10, 0x3C6EF372FE94F82B, -15, 15)
    base = spread(101, 0xA54FF53A5F1D36F1, -8, 8)
    yield "length 101 p10", [base[at] + tenth[at % 10] for at in range(101)], base, 30, 4, 0x1077, 10, 0
    yield "reach past length", spread(12, 0x510E527FADE682D1, -6, 6), None, 100, 3, 0x2188, 5, 3


def record(values, target, reach, draws, key, period, places):
    fields = struct.pack("<II", MAGIC, 0 if target is None else 1)
    fields += struct.pack("<6Q", len(values), reach, draws, key, period, places)
    fields += struct.pack("<%dq" % len(values), *values)
    if target is not None:
        fields += struct.pack("<%dq" % len(target), *target)
    return fields


def hexed(number):
    return "0" if number == 0 else ("-" if number < 0 else "") + format(abs(number), "x")


def pair(numerator, denominator):
    return "%s/%s" % (hexed(numerator), hexed(denominator))


def measurement_line(name, measurement, places):
    if measurement is None:
        return "%s status 0 found 0" % name
    if not measurement.found:
        return "%s status 1 found 0" % name
    return "%s status 1 found 1 period %d ratio %s print %s places %s" % (
        name, measurement.period, pair(measurement.numerator, measurement.denominator), energy_print(measurement),
        ratio_text(measurement.numerator, measurement.denominator, places))


def python_block(number, values, target, reach, draws, key, period, places):
    """The Python results in the probe's lines."""
    length = len(values)
    lines = ["case %d length %d reach %d draws %d period %d" % (number, length, reach, draws, period)]
    live = energy_recover(values, reach)
    lines.append(measurement_line("recover", live, places))
    top = min(reach, length - 1) if length >= 1 else 0
    if live is not None:
        for scanned in range(2, top + 1):
            ratio = energy_ratio(values, scanned)
            lines.append("ratio %d %s" % (scanned, "none" if ratio is None else pair(*ratio)))
    if target is not None and live is not None and 2 <= period <= top:
        sums = [sum(values[phase::period]) for phase in range(period)]
        lines.append("reduction status 1 %s" % pair(*energy_reduction(values, target, period, sums)))
    if period != 0 and length != 0:
        lines.append(" ".join(["welford status 1"] + ["%d/%d" % one for one in energy_welford(values, period)]))
    if length != 0:
        lines.append(" ".join(["shuffle"] + ["%d" % one for one in energy_shuffle(values, key)]))
        band = energy_band_top(values, reach, draws, key)
        lines.append("reached %d" % (band[1] if band is not None else 0))
        lines.append(measurement_line("band", band[0] if band is not None else None, places))
        if live is not None and band is not None:
            lines.append("above %d" % (1 if energy_above(live, band[0]) else 0))
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


def field(block, head, name):
    for line in block:
        words = line.split()
        if words and words[0] == head and name in words:
            return words[words.index(name) + 1]
    return "-"


def summary(block):
    """(recovered, band, above, reduction, crc) of one side's block."""
    recovered = "%s@%s" % (field(block, "recover", "period"), field(block, "recover", "print"))
    reached = next((line.split()[1] for line in block if line.startswith("reached ")), "-")
    band = "%s:%s" % (reached, field(block, "band", "print"))
    above = next((line.split()[1] for line in block if line.startswith("above ")), "-")
    reduction = next((line.split()[3] for line in block if line.startswith("reduction ")), "-")
    graded = "\n".join(line for line in block if not line.startswith("results "))
    return recovered, band, above, reduction, "%08x" % (zlib.crc32(graded.encode()) & 0xFFFFFFFF)


def shown(reduction):
    """The reduction to four places, from its hexadecimal pair."""
    if reduction == "-":
        return "-"
    numerator, denominator = (int(one, 16) for one in reduction.split("/"))
    return ratio_text(numerator, denominator, 4)


def main():
    probe = find_probe()
    if probe is None:
        print("  periodic_energy_probe not found: set ANCHOR_PERIODIC_ENERGY_PROBE, or build it under build/.")
        return 1
    graded = list(cases())
    folder = tempfile.mkdtemp(prefix="periodic_energy_test_")
    path = os.path.join(folder, "requests.bin")
    with open(path, "wb") as out:
        for _name, values, target, reach, draws, key, period, places in graded:
            out.write(record(values, target, reach, draws, key, period, places))
    try:
        ran = subprocess.run([probe, path], capture_output=True, text=True, timeout=600)
    finally:
        os.remove(path)
        os.rmdir(folder)
    blocks = engine_blocks(ran.stdout)

    print("\n  measure.periodic_energy AGAINST src/sims/cu/engine/analysis/art/periodic_energy.h, line for line. probe: %s\n" % probe)
    print("  %-19s %-4s %-12s %-14s %-5s %-9s %-8s %s" % (
        "case", "side", "period@ratio", "band reach:top", "above", "reduction", "crc", "verdict"))
    failed = 0
    for number, (name, values, target, reach, draws, key, period, places) in enumerate(graded):
        mine = python_block(number, values, target, reach, draws, key, period, places)
        theirs = blocks[number] if number < len(blocks) else ["case %d missing" % number]
        c_graded = [line for line in theirs if not line.startswith("results ")]
        differ = sum(1 for one, other in zip(c_graded, mine) if one != other) + abs(len(c_graded) - len(mine))
        ok = differ == 0
        failed += 0 if ok else 1
        c_side = summary(theirs)
        py_side = summary(mine)
        print("  %-19s %-4s %-12s %-14s %-5s %-9s %-8s" % (
            name, "C", c_side[0], c_side[1], c_side[2], shown(c_side[3]), c_side[4]))
        print("  %-19s %-4s %-12s %-14s %-5s %-9s %-8s %d differ %s" % (
            "", "py", py_side[0], py_side[1], py_side[2], shown(py_side[3]), py_side[4], differ,
            "ok" if ok else "FAILS"))
        for line in theirs:
            if line.startswith("results "):
                print("  %-19s      engine %s" % ("", line))

    print("\n  %d checks, %d failed; probe exit %d, %d block(s) printed\n" % (
        len(graded), failed, ran.returncode, len(blocks)))
    return 0 if failed == 0 and ran.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
