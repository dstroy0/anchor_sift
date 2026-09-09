#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Check the C limb arithmetic against python integers, which know nothing about limbs.
#
#   python maint/engine/check_exact_limbs.py                  build/engine_c/bench_exact is run
#   python maint/engine/check_exact_limbs.py <rows.txt>       rows already captured are read
#
# WHY THE CHECK IS NOT INSIDE THE C
#
# A library cannot be its own oracle. A second routine in bench_exact.c saying what an addition
# should come to would carry whatever the author believed about the answer, and it would agree with
# the first routine forever, including on the days both are wrong.
#
# A python integer is arbitrary precision and is implemented by somebody else. It has no fixed
# width, no limb, no carry the author of exact_limbs.c wrote, and no shared line of code. Where the
# two disagree the disagreement is real.
#
# WHAT IS BEING COMPARED
#
# The C prints a sign and its limbs in hex, least significant first. This reassembles that into an
# integer and compares against the same operation done directly. It also checks the refusals: a
# value too wide for the fixed width has to come back refused, since a fixed width is the only bound
# this representation carries and a silent wrap is the worst failure available to it.

import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

DRIVER = os.path.join(ROOT, "build", "engine_c", "bench_exact.exe")
if not os.path.isfile(DRIVER):
    DRIVER = os.path.join(ROOT, "build", "engine_c", "bench_exact")

# Positions in the planted run the C builds, and the value standing at each. Stated here as the plan
# and built independently, the same way bench_lattice plants an occurrence instead of looking for
# one. Nothing is read back from the C to construct it.
RUN_PLACES = 64
RUN_STEP = 4


def value_of(sign, limbs):
    """One printed row reassembled into an integer, without any of the C's arithmetic."""
    held = 0
    for at, limb in enumerate(limbs):
        held += limb << (32 * at)
    return sign * held


def exact_of(text, places):
    """Decimal text as an integer at `places`, done with python integers alone.

    Returns None where the text is not plain decimal or carries more places than `places` holds,
    which are the two cases the C is required to refuse.
    """
    body = text.strip()
    opened = body.find("(")
    if opened >= 0:
        closed = body.find(")")
        body = (body[:opened] + body[closed + 1:]) if closed >= 0 else body[:opened]
    body = body.strip()

    sign = 1
    if body[:1] in ("+", "-"):
        sign = -1 if body[0] == "-" else 1
        body = body[1:]
    whole, point, part = body.partition(".")
    digits = whole + part
    if (not digits) or (not digits.isdigit()):
        return None
    if len(part) > places:
        return None
    return sign * int(digits) * (10 ** (places - len(part)))


def planted_run(places):
    """The run the C builds, constructed here from the plan and not from its output."""
    positions = []
    values = []
    for at in range(RUN_PLACES):
        text = "%d.%02d" % (at // RUN_STEP, (at % RUN_STEP) * 25)
        positions.append(exact_of(text, places))
        values.append(at % RUN_STEP)
    return positions, values


def agreement(positions, values, lag):
    """How many places carry the same value as the place exactly one lag away."""
    seen = dict(zip(positions, values))
    return sum(1 for one, value in seen.items() if seen.get(one + lag) == value)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    if len(sys.argv) > 1:
        with io.open(sys.argv[1], encoding="utf-8") as handle:
            rows = handle.read().splitlines()
    else:
        if not os.path.isfile(DRIVER):
            out.write("\n  no bench_exact at %s\n" % DRIVER)
            out.write("  cmake -S src/engine/c -B build/engine_c -G Ninja"
                      " -DCMAKE_BUILD_TYPE=Release && cmake --build build/engine_c\n\n")
            out.flush()
            return 1
        rows = subprocess.run([DRIVER], capture_output=True, text=True,
                              check=True).stdout.splitlines()

    if (not rows) or (not rows[0].startswith("limbs ")):
        out.write("\n  the driver printed nothing recognizable\n\n")
        out.flush()
        return 1
    parts = rows[0].split()
    limbs = int(parts[1])
    places = int(parts[3])
    width = 32 * limbs

    subjects = {}
    checked = 0
    wrong = []

    for row in rows[1:]:
        field = row.split()
        if not field:
            continue
        kind = field[0]

        if kind == "read":
            index = int(field[1])
            text = field[2]
            wanted = exact_of(text, places)
            if field[3] == "refused":
                # A refusal has to be one the python side agrees is impossible, or the C is
                # refusing values it should have read.
                if wanted is not None:
                    wrong.append("%s: refused %s, which reads fine at %d places" % (row, text, places))
                subjects[index] = None
            else:
                got = value_of(int(field[3]), [int(one, 16) for one in field[4:]])
                if wanted is None:
                    wrong.append("%s: read %s, which python refuses" % (row, text))
                elif got != wanted:
                    wrong.append("%s: read %s as %d, python says %d" % (row, text, got, wanted))
                subjects[index] = wanted
            checked += 1
            continue

        if kind in ("add", "sub", "mul"):
            low = subjects.get(int(field[1]))
            high = subjects.get(int(field[2]))
            if (low is None) or (high is None):
                continue
            wanted = (low + high) if kind == "add" else \
                     (low - high) if kind == "sub" else (low * high)
            fits = abs(wanted) < (1 << width)
            if field[3] == "refused":
                if fits:
                    wrong.append("%s: refused, but %d fits %d bits" % (row, wanted, width))
            else:
                got = value_of(int(field[3]), [int(one, 16) for one in field[4:]])
                if not fits:
                    wrong.append("%s: produced a value where %d needs more than %d bits"
                                 % (row, wanted, width))
                elif got != wanted:
                    wrong.append("%s: got %d, python says %d" % (row, got, wanted))
            checked += 1
            continue

        if kind == "cmp":
            low = subjects.get(int(field[1]))
            high = subjects.get(int(field[2]))
            if (low is None) or (high is None):
                continue
            order = (low > high) - (low < high)
            same = 1 if low == high else 0
            if (int(field[3]) != order) or (int(field[4]) != same):
                wrong.append("%s: got %s %s, python says %d %d"
                             % (row, field[3], field[4], order, same))
            checked += 1
            continue

        if kind == "agree":
            lag = exact_of(field[1], places)
            positions, values = planted_run(places)
            wanted = agreement(positions, values, lag)
            if int(field[2]) != wanted:
                wrong.append("%s: got %s, python says %d" % (row, field[2], wanted))
            checked += 1
            continue

    out.write("\n  %d rows checked at %d limbs, %d decimal places, %d bits wide\n"
              % (checked, limbs, places, width))
    if wrong:
        out.write("\n  DISAGREEMENTS (%d)\n" % len(wrong))
        for one in wrong[:40]:
            out.write("    %s\n" % one)
        if len(wrong) > 40:
            out.write("    and %d more\n" % (len(wrong) - 40))
        out.write("\n  the C and python integers do not agree. One of them has a defect.\n\n")
        out.flush()
        return 1

    out.write("  every row agrees with python integer arithmetic\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
