#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-4-001
#
# Read a period off a cell without sweeping for it, and show what was considered.
#
#   Usage:  python examples/crystallography/4_measure/period_from_the_difference_set.py [entries]
#
# Nothing here is compared against a published edge. That is stage six, and keeping the two apart is
# the point of the split: this stage says what the instrument returns and how it got there, and the
# oracle says whether it was right.
#
# The sweep is gone. A swept measure walks lag one upward to a ceiling, and the ceiling is a claim
# about what the answer can be. Here every difference between two occupied coordinates is a
# candidate, and that set is complete. A period agreeing with anything at all is a difference
# between two things that agree, and lands in the set by construction. The count of candidates is
# printed for that reason, being the quantity a sweep would have had to guess a bound for.
#
# The family rule stays, and it is the single correction this measure needed. A set with period P agrees
# with itself at 2P and 3P, so the tallest lag alone reports a harmonic. Scoring a candidate as the
# mean over itself and its multiples fixes that, and capping the family at two members keeps a short
# wrong candidate from winning by holding more multiples and catching one good lag among them.
#
# Read along an axis, a coordinate carries the whole arrangement sitting at it. Two coordinates
# agree when their arrangements match, values included. Leaving the values out reads a rocksalt cell
# at half its edge, correctly: the two sublattices interleave and the positions alone repeat at a/2.

import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.shift_agreement import exact_agreement, recover_exact_period  # noqa: E402
from representation import exact  # noqa: E402
from representation.structure import crystal  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")


def angstroms(value, places=8):
    """An exact integer at the scale as decimal text, cut to `places` for the column it sits in."""
    if value is None:
        return "none"
    sign = "-" if value < 0 else ""
    digits = str(abs(value)).rjust(exact.SCALE_DIGITS + 1, "0")
    whole = digits[:-exact.SCALE_DIGITS]
    part = digits[-exact.SCALE_DIGITS:][:places].rstrip("0")
    return "%s%s.%s" % (sign, whole, part) if part else "%s%s" % (sign, whole)


def read_axis(points, axis):
    """One axis, as (period, agreement at it, planes, candidates considered, runner up).

    The runner up is the next best scoring candidate that is not a multiple of the winner. It says
    whether the answer was close or clear, which a bare count cannot.
    """
    seen = exact.along(points, axis)
    if len(seen) < 3:
        return None
    ordered = sorted(seen)
    candidates = set()
    for at, first in enumerate(ordered):
        for second in ordered[at + 1:]:
            candidates.add(second - first)

    period, score = recover_exact_period(seen)
    if period is None:
        return None

    runner = 0
    for candidate in candidates:
        if (candidate % period) == 0:
            continue
        runner = max(runner, exact_agreement(seen, candidate))
    return period, score, len(seen), len(candidates), runner


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(CACHE):
        out.write("\n  nothing cached under build/cod. Run the oracle to fill it.\n\n")
        out.flush()
        return 1

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 25

    out.write("\n  What the measure returns, with no published edge anywhere in it.\n\n")
    out.write("  %-12s %-5s %-7s %-11s %-16s %-7s %s\n"
              % ("entry", "axis", "planes", "candidates", "period", "agrees", "next best"))

    read = 0
    axes = 0
    clear = 0
    started = time.time()
    for name in sorted(os.listdir(CACHE)):
        if read >= limit:
            break
        if not name.endswith(".cif"):
            continue
        with io.open(os.path.join(CACHE, name), encoding="utf-8", errors="replace") as handle:
            points, _ = crystal.exact_points(handle.read())
        if points is None:
            continue
        read += 1
        for axis, label in enumerate(("a", "b", "c")):
            found = read_axis(points, axis)
            if found is None:
                continue
            period, score, planes, candidates, runner = found
            axes += 1
            if score > runner:
                clear += 1
            out.write("  %-12s %-5s %-7d %-11d %-16s %-7d %d\n"
                      % (name[:-4], label, planes, candidates, angstroms(period), score, runner))
        out.flush()

    out.write("\n  %d entries, %d axes, %.1fs\n" % (read, axes, time.time() - started))
    out.write("  %d of %d axes beat every candidate that is not a multiple of the answer\n"
              % (clear, axes))
    out.write("  no lag was swept and no ceiling was set, so the candidate column is the whole\n")
    out.write("  set of differences the arrangement contains\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
