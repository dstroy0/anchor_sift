#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Re-carve a vocalization at the scale its units occupy, for Section 4.10 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/envelope_scale.py corpus.sym [more.sym ...]
#
# The vocalizations were measured at 8 kHz with one byte a sample, and that is the wrong carving for the
# structure they are supposed to carry. A whale song unit runs one to three seconds and its phrases and
# themes run longer, and a wolf howl is seconds. A statistic over the gaps between rare amplitudes at
# 8 kHz therefore reads inside a single unit and never sees the arrangement of units.
#
# Section 4.10 records the symbol width as a choice this work never justified, and this is that choice
# being wrong by four orders of magnitude. Taking the amplitude envelope over blocks of 400 samples gives
# one symbol every 50 ms, so a unit spans tens of symbols and a phrase spans hundreds. For speech the same
# window is about one phoneme, which is why the comparison is fairer at this scale than at the last one.

import io
import math
import os
import sys

BLOCK = 80
MIDPOINT = 128


def envelope(seats, block):
    """Root mean square deviation from the midpoint, per block, quantized back to a byte."""
    out = bytearray()
    for start in range(0, len(seats) - block + 1, block):
        total = 0
        for index in range(start, start + block):
            offset = seats[index] - MIDPOINT
            total += offset * offset
        out.append(int(math.sqrt(total / float(block))))
    if not out:
        return out

    # Spread over the range actually used, so a quiet recording is not compressed into a few levels and
    # compared against a loud one that is not
    low = min(out)
    high = max(out)
    if high <= low:
        return out
    return bytearray(1 + int(254 * (value - low) / float(high - low)) for value in out)


def main():
    if len(sys.argv) < 2:
        print("usage: envelope_scale.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            seats = handle.read()
        marks = envelope(seats, BLOCK)
        if len(marks) < 2000:
            out.write("  %-24s %d envelope symbols, too few\n"
                      % (os.path.basename(path)[:-4], len(marks)))
            continue
        target = os.path.join(os.path.dirname(path), "env_%s" % os.path.basename(path))
        with open(target, "wb") as handle:
            handle.write(marks)
        out.write("  %-24s %d samples to %d envelope symbols at %d Hz, %d levels\n"
                  % (os.path.basename(path)[:-4], len(seats), len(marks), 8000 // BLOCK,
                     len(set(marks))))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
