#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: SND-1-001
#
# The same recordings read at two scales, where one of the two answers a different question.
#
#   Usage:  python examples/sound/1_represent/vocalization_scale.py corpus.sym [more.sym ...]
#
# This is the plainest case in the work of a representation choice deciding an answer, and it was
# wrong by four orders of magnitude.
#
# The vocalizations were measured at 8 kHz with one byte a sample. A whale song unit runs one to
# three seconds and a wolf howl is seconds long. A statistic over the gaps between rare
# amplitudes at that rate reads inside a single call and never sees how calls are arranged.
#
# At sample scale the animals and the people interleaved: whale 0.25, dawn chorus 0.30, human speech
# 0.42 and 0.43, wolf 0.46, with two of three animals departing further from the null than a person
# reading an encyclopedia. Taking the amplitude envelope at one symbol every 10 ms gives whale 0.44,
# dawn chorus 0.45 and wolf 0.49 against 0.56 and 0.72 for two human recordings, which separates
# without overlap where the sample scale had them interleaved.
#
# Both readings are printed because the point is the difference between them, and neither is the
# true unit scale. At one symbol every 50 ms a one minute clip gives 1053 symbols for the whale, and
# measuring the arrangement of units needs recordings of tens of minutes.
#
# A mechanism unrelated to communication also fits and is not excluded here. A bird call is discrete
# and separated by silence while a person reading aloud emits a continuous signal, so clustered rare
# amplitudes follow from the shape of the emission and not from what it carries. Separating those
# needs the measure applied to segmented calls, which is not built.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.dispersion import rare_half  # noqa: E402
from representation.sound.envelope import envelope, symbols_per_second  # noqa: E402

SAMPLE_RATE = 8000
BLOCKS = (80, 400)


def main():
    if len(sys.argv) < 2:
        print("usage: vocalization_scale.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-11s %s\n"
              % ("recording", "at samples", "  ".join("at %d ms" % int(1000.0 / symbols_per_second(
                  SAMPLE_RATE, block)) for block in BLOCKS)))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            seats = handle.read()
        if len(seats) < 100000:
            out.write("  %-26s %d samples, too few\n" % (os.path.basename(path)[:-4], len(seats)))
            continue

        row = []
        for block in BLOCKS:
            marks = envelope(seats, block)
            value = rare_half(bytes(marks)) if len(marks) >= 2000 else None
            row.append("%.4f" % value if value is not None else "few symbols")

        at_samples = rare_half(seats)
        out.write("  %-26s %-11s %s\n"
                  % (os.path.basename(path)[:-4],
                     "%.4f" % at_samples if at_samples is not None else "none",
                     "  ".join("%-11s" % one for one in row)))

    out.write("\n  the envelope leaves few distinct levels, so the rare half out there is a\n")
    out.write("  handful of symbols and those figures are thin. The agreement of separate\n")
    out.write("  populations is the strongest thing about the result and the symbol count\n")
    out.write("  is the weakest\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
