#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grades representation.exact against the C reader it mirrors, text for text.
#
#   python utils/test/harness.py run engine_c
#
# exact.py reads decimal text into an exact integer at a count of places, and so do
# anchor_exact_from_decimal and anchor_exact_from_measured in
# src/engine/arithmetic/no_rounding/exact_integer_decimal.c.
# The two share no code. utils/bench/bench_exact.c reads each of its SUBJECTS through both C entries and
# prints what it got, the text in hex, then a sign, a limb count and the limbs, or an error and its
# AnchorExactStatus. This runs that program, decodes each text as UTF-8 the way a Python reader
# holding a file would, reads it through exact.scaled and exact.measured at the same places, and
# compares.
#
# WHAT AGREEMENT MEANS HERE
#
# A value agrees when the C's sign and magnitude equal the Python integer's. An error agrees by
# kind: NOT_DECIMAL (2) is a ValueError that is not WillNotFit, and WILL_NOT_FIT (1) is either
# WillNotFit, where the text carries more places than the scale, or a Python value whose magnitude
# needs more bits than the C's fixed width. The last is the single difference the two are allowed: a
# Python integer has no width, and the C returns an error for what its width cannot hold. That case is counted
# and printed on its own row as "width", and not folded into a plain agreement.
#
# The places are the ones bench_exact.c reads at, min(24, (ANCHOR_EXACT_BITS - 5) x 30102 / 100000),
# with the width read out of exact_integer_widths.h. A build that sets a different width must be graded with
# that width passed in ANCHOR_EXACT_BITS.
#
# The harness env engine_c runs it from utils/maint/engine/build_engine.sh, which builds bench_exact and
# names it in ANCHOR_BENCH_EXACT. Without that, it is searched for under build/. A missing program
# is a failure here and not a skip.

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation import exact  # noqa: E402

HEADER = os.path.join(ROOT, "src", "engine", "arithmetic", "no_rounding", "exact_integer_widths.h")
NOT_DECIMAL = 2
WILL_NOT_FIT = 1


def width_bits():
    """ANCHOR_EXACT_BITS from the environment, or 32 times the header's default limb count."""
    given = os.environ.get("ANCHOR_EXACT_BITS")
    if given:
        return int(given)
    with open(HEADER, encoding="utf-8") as handle:
        found = re.search(r"#define\s+ANCHOR_EXACT_LIMBS\s+(\d+)u", handle.read())
    return int(found.group(1)) * 32


def find_program():
    """bench_exact as the build left it, or None."""
    given = os.environ.get("ANCHOR_BENCH_EXACT")
    if given and os.path.isfile(given):
        return given
    for base, _dirs, files in os.walk(os.path.join(ROOT, "build")):
        for name in ("bench_exact.exe", "bench_exact"):
            if name in files:
                return os.path.join(base, name)
    return None


def c_value(fields):
    """A C value printed as sign, limb count and limbs, as (sign, integer) and the fields it used."""
    sign = int(fields[0])
    used = int(fields[1])
    magnitude = 0
    for at, limb in enumerate(fields[2:2 + used]):
        magnitude |= int(limb, 16) << (32 * at)
    return (sign, sign * magnitude if sign < 0 else magnitude), 2 + used


def py_sign(value):
    return (value > 0) - (value < 0)


def python_side(reader, text, places):
    """What exact.py returns for one text: ("value", ...) or ("error", status)."""
    try:
        return ("value", reader(text, places))
    except exact.WillNotFit:
        return ("error", WILL_NOT_FIT)
    except ValueError:
        return ("error", NOT_DECIMAL)


def too_wide(values, bits):
    return any(v is not None and abs(v).bit_length() > bits for v in values)


def show(value):
    if value is None:
        return "-"
    text = str(value)
    return text if len(text) <= 30 else text[:13] + ".." + text[-13:]


def grade(kind, fields, text, places, bits):
    """One read or meas row graded. Returns (verdict, c shown, python shown)."""
    if kind == "read":
        py = python_side(exact.scaled, text, places)
    else:
        py = python_side(exact.measured, text, places)

    if fields[0] == "errored":
        status = int(fields[1])
        c_shown = "error %d" % status
        if py[0] == "error":
            return ("ok" if py[1] == status else "FAILS"), c_shown, "error %d" % py[1]
        values = py[1] if kind == "meas" else (py[1],)
        py_shown = " ".join(show(v) for v in values)
        if status == WILL_NOT_FIT and too_wide(values, bits):
            return "width", c_shown, py_shown
        return "FAILS", c_shown, py_shown

    if kind == "read":
        (sign, value), _used = c_value(fields)
        c_shown = show(value)
        if py[0] == "error":
            return "FAILS", c_shown, "error %d" % py[1]
        ok = value == py[1] and sign == py_sign(py[1])
        return ("ok" if ok else "FAILS"), c_shown, show(py[1])

    carried = int(fields[0])
    (sign, value), used = c_value(fields[1:])
    (u_sign, uncertainty), _ = c_value(fields[1 + used:])
    c_shown = "%s %s %d" % (show(value), show(uncertainty), carried)
    if py[0] == "error":
        return "FAILS", c_shown, "error %d" % py[1]
    py_value, py_uncertainty = py[1]
    py_shown = "%s %s %d" % (show(py_value), show(py_uncertainty or 0), py_uncertainty is not None)
    ok = (value == py_value and sign == py_sign(py_value)
          and carried == (1 if py_uncertainty is not None else 0)
          and uncertainty == (py_uncertainty or 0) and u_sign == py_sign(py_uncertainty or 0))
    return ("ok" if ok else "FAILS"), c_shown, py_shown


def main():
    program = find_program()
    if program is None:
        print("  bench_exact not found: set ANCHOR_BENCH_EXACT, or build it under build/.")
        return 1
    bits = width_bits()
    places = min(24, ((bits - 5) * 30102) // 100000)
    run = subprocess.run([program], capture_output=True, check=False)
    if run.returncode != 0:
        print("  %s exited %d" % (program, run.returncode))
        return 1

    print("\n  EXACT.PY AGAINST exact_integer_decimal.c, text for text. program: %s" % program)
    print("  width %d bits, %d places\n" % (bits, places))
    print("  %4s %4s %-30s %-34s %-34s %s" % ("kind", "row", "text", "C", "Python", "verdict"))

    counts = {"ok": 0, "width": 0, "FAILS": 0}
    for line in run.stdout.decode("ascii").splitlines():
        fields = line.split()
        if not fields or fields[0] not in ("read", "meas"):
            continue
        kind, index, hexed = fields[0], fields[1], fields[2]
        text = bytes.fromhex(hexed).decode("utf-8", errors="surrogateescape")
        verdict, c_shown, py_shown = grade(kind, fields[3:], text, places, bits)
        counts[verdict] += 1
        print("  %4s %4s %-30s %-34s %-34s %s" % (kind, index, ascii(text)[:30], c_shown, py_shown, verdict))

    total = sum(counts.values())
    print("\n  %d checks, %d failed: %d agree, %d in error by the C's width alone\n"
          % (total, counts["FAILS"], counts["ok"], counts["width"]))
    return 0 if counts["FAILS"] == 0 and total > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
