#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find what singles out the one corpus whose bit volume reading depends on its numbering, for Section 4.2
# of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/value_proximity.py
#
# Of every corpus measured, only the picture moves when its symbols are renumbered, at 20.6 standard
# deviations against 1.5 for recorded sound. The account offered for that was that domains with ordered
# values would move and symbolic ones would hold, and recorded sound refuted it by being ordered and
# holding. So the property that separates the picture from the rest is not known and is guessed at here no
# further.
#
# Nearness in value between neighbouring positions is the first candidate and it can be read straight off
# the data. Adjacent bytes of a picture row are adjacent pixels and should sit close in value, and the
# same argument is usually made for a sound waveform. Shuffling the corpus destroys that nearness while
# leaving every value and every frequency in place, so the mean step between neighbours divided by the
# same quantity shuffled says how much closer than chance neighbours are.
#
# Two other quantities are reported beside it, because either would also single out a corpus without any
# nearness being involved: the effective size of the alphabet, which is what the bit correlation has to
# work with, and how much of the corpus the commonest symbol takes.

import io
import math
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from point_volume import load

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7

# The last column is how far each corpus sat from its own renumberings in complementarity.py, carried
# here so the candidate can be read against the thing it is meant to explain
WANTED = (
    ("art_hokusai.sym", 20.6),
    ("art_starry.sym", None),
    ("art_vermeer.sym", None),
    ("env_voc_human_speech.sym", 1.5),
    ("voc_whale_humpback.sym", None),
    ("english_1813_austen.sym", 0.9),
    ("greek_iliad.sym", 0.7),
    ("csource_formal.sym", 2.2),
    ("monkey_a08_d18_uniform.sym", 1.5),
)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-12s %-14s %-12s %s\n"
              % ("corpus", "step ratio", "eff alphabet", "top share", "sd from renumbering"))

    for name, distance in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-26s not present\n" % name[:-4])
            continue
        values = load(path, name).astype(numpy.float64)
        if len(values) < 20000:
            continue

        live_step = float(numpy.abs(numpy.diff(values)).mean())
        shuffled = values.copy()
        numpy.random.default_rng(SEED).shuffle(shuffled)
        dead_step = float(numpy.abs(numpy.diff(shuffled)).mean())
        ratio = (live_step / dead_step) if dead_step > 0.0 else float("nan")

        counts = numpy.bincount(values.astype(numpy.int64), minlength=256).astype(numpy.float64)
        shares = counts / counts.sum()
        alive = shares[shares > 0.0]
        collision = float((alive * alive).sum())
        out.write("  %-26s %-12.4f %-14.1f %-12.4f %s\n"
                  % (name[:-4], ratio, 1.0 / collision, float(alive.max()),
                     ("%.1f" % distance) if distance is not None else "not measured"))

    out.write("\n  A ratio near 1 means neighbours are no closer in value than any two symbols drawn\n")
    out.write("  at random, and a ratio well under 1 means the corpus moves in small steps.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
