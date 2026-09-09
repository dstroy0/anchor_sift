#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# An image read as a sequence, told nothing, returning its own width.
#
#   Usage:  python examples/art/4_measure/a_picture_returns_its_width.py corpus.sym [more.sym ...]
#
# A picture is not an extension of this construction, it is the case the construction was written
# for: a domain whose alphabet is a range of values and whose arrangement has two dimensions. Read
# row by row the second dimension survives as a periodicity, since a pixel and the pixel below it
# lie one width apart in the sequence.
#
# The controls are what make the result readable. Uniform noise returns unrelated lags at an
# agreement of 0.0050, which is 1/256 and therefore chance, and has nothing to find. A generated
# ramp returns 511 where the width is 512, and 511 is the correct answer, because the ramp is
# (row + column) mod 256 and stepping down one row and back one column leaves the value alone. The
# detector found the structure of the object instead of the width it was built with.
#
# Those three separate by how strongly they agree, and that ordering is the useful part. Noise at
# 0.0050 has nothing to find. A machine made ramp at 0.9980 is perfectly regular, trivial to detect
# and empty to use. Paintings sit at 0.02 to 0.30, in the band where a periodicity is both findable
# and carries a position.
#
# A shuffle of the same bytes is printed beside every row, because a raw agreement count carries no
# information on its own.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.shift_agreement import against_a_shuffle, recover_period, strongest_lags  # noqa: E402


def main():
    if len(sys.argv) < 2:
        print("usage: a_picture_returns_its_width.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-22s %-9s %-9s %-11s %-9s %s\n"
              % ("corpus", "top lag", "agree", "shuffled", "sub lag", "the top six lags"))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            data = handle.read()
        if len(data) < 20000:
            continue

        marks = strongest_lags(data, keep=6)
        if not marks:
            continue
        live, dead = against_a_shuffle(data)
        lag, fraction, _ = recover_period(data)

        out.write("  %-22s %-9d %-9.4f %-11.4f %-9s %s\n"
                  % (os.path.basename(path)[:-4], marks[0][1], marks[0][0],
                     dead[0] if dead else float("nan"),
                     "%.3f" % (lag + fraction) if lag is not None else "none",
                     " ".join(str(one[1]) for one in marks)))

    out.write("\n  the shuffled column holds the histogram and destroys the positions, so what\n")
    out.write("  survives the subtraction is the only part that means anything\n")
    out.write("  a real period arrives with its neighbours beside it and its harmonics behind\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
