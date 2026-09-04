#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure how long a corpus stays near one value, for Section 4.2 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/island_size.py
#
# Only some corpora move when their symbols are renumbered, and the property behind it has now been
# narrowed twice. Ordered values was wrong, since recorded speech is ordered and holds. Nearness between
# neighbours was wrong on its own, since speech sits at 0.54 and whale song at 0.48 and only one of them
# moves.
#
# What the moving corpora have is not small steps but long stays. A picture is flat regions with edges
# between them, so a row crosses a stretch of sky and holds near one value for a long run. Whale song is
# sustained calls that hold a tone. Human speech has small steps and never stays anywhere, because it
# re-articulates continuously, and text has neither.
#
# So the quantity is the length of a stay, not the size of a step. A run is counted here from a starting
# position until the value leaves a band around where it started, which is what a flat region gives and
# what an oscillation does not, however smooth the oscillation is. The same count on the shuffled corpus
# is the floor, since a band of that width catches some positions by chance alone.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from point_volume import load

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
# The band is a share of each corpus's own spread of values, not a fixed count of levels. A fixed band is
# wide for a corpus using few levels and narrow for one using many, which made a picture spread over an
# effective alphabet of 160 read as having no stays while a picture over 14 read as one long stay, and
# made a corpus of eight symbols read as a single run covering everything.
BAND_SHARE = 0.25
CAP = 120000

# How far each corpus sat from its own renumberings, carried here so the candidate can be read against
# the thing it has to explain. The monkey figure is a scale artifact and is marked: its spread is 0.0008,
# so an absolute difference of 0.0025 divides into a large number of standard deviations while meaning
# nothing.
WANTED = (
    ("art_starry.sym", "278.2"),
    ("art_hokusai.sym", "20.6"),
    ("voc_whale_humpback.sym", "16.0"),
    ("art_vermeer.sym", "8.1"),
    ("csource_formal.sym", "holds"),
    ("env_voc_human_speech.sym", "holds"),
    ("english_1813_austen.sym", "holds"),
    ("greek_iliad.sym", "holds"),
    ("monkey_a08_d18_uniform.sym", "3.3, scale artifact"),
)


def mean_stay(values, band):
    """Mean run length before the value leaves a band around where the run started."""
    total = 0
    runs = 0
    index = 0
    limit = len(values)
    while index < limit:
        start = values[index]
        walk = index + 1
        while (walk < limit) and (abs(int(values[walk]) - int(start)) <= band):
            walk += 1
        total += walk - index
        runs += 1
        index = walk
    return (total / float(runs)) if runs else 0.0


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-11s %-11s %-11s %s\n"
              % ("corpus", "stay", "shuffled", "excess", "sd from renumbering"))

    for name, distance in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-26s not present\n" % name[:-4])
            continue
        values = load(path, name)[:CAP]
        if len(values) < 20000:
            continue

        band = max(1.0, BAND_SHARE * float(values.astype(numpy.float64).std()))
        live = mean_stay(values, band)
        shuffled = values.copy()
        numpy.random.default_rng(SEED).shuffle(shuffled)
        dead = mean_stay(shuffled, band)
        out.write("  %-26s %-11.2f %-11.2f %-11.2f %s\n"
                  % (name[:-4], live, dead, (live / dead) if dead > 0 else float("nan"), distance))

    out.write("\n  A stay near the shuffled figure means the corpus never holds near a value, however\n")
    out.write("  small its steps between neighbours are.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
