#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Settle what the two instruments in this work each measure, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/complementarity.py
#
# The two disagree on the same corpora. Alphabetic text departs strongly on the gap measure and reads near
# zero in the bit volume, while a picture reads strongly in the volume. Renumbering the symbols cleared
# the numbering as the cause everywhere except on the picture, where the reading collapsed.
#
# That points at an answer which can be argued before it is measured. The gap measure reads only where
# each symbol occurs, so renaming the symbols cannot move it at all, and it is invariant to renumbering by
# construction. The bit volume reads the correlation of bit positions, which is a statement about the
# numbers themselves, so renumbering can move it and on the picture it does. Two instruments where one is
# invariant to a change the other is not cannot be measuring the same quantity.
#
# What each is then blind to follows. Structure carried as numeric proximity, where neighbouring positions
# hold near values, is what a greyscale level and a sound amplitude have and is what the volume reads.
# Structure carried as which symbol follows which survives any renumbering, is what text has, and is what
# the gap measure reads. Neither contains the other and the earlier attempt to have one replace the other
# was the wrong shape.
#
# Both instruments are run here on the same corpora, each under its own numbering and under a random
# renumbering that leaves every frequency and every position untouched. The prediction is exact: the gap
# measure returns identical numbers under renumbering, and the volume moves on the domains whose values
# are ordered and holds on the ones whose structure is symbolic.

import io
import os
import statistics
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from point_volume import gray_bits, load, spectrum_gap

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
MIN_OCCURRENCES = 32
WIDTH = 32
DRAWS = 8

WANTED = (
    ("art_hokusai.sym", "picture, values ordered"),
    ("env_voc_human_speech.sym", "sound, values ordered"),
    ("english_1813_austen.sym", "text, values symbolic"),
    ("greek_iliad.sym", "text, values symbolic"),
    ("csource_formal.sym", "source, values symbolic"),
    ("monkey_a08_d18_uniform.sym", "memoryless control"),
)


def gap_measure(values):
    """The rare half of the symbols, scored by gap spread against the permuted null."""
    def spread(series):
        seen = {}
        for index, value in enumerate(series):
            seen.setdefault(int(value), []).append(index)
        out = {}
        for value, spots in seen.items():
            if len(spots) < MIN_OCCURRENCES:
                continue
            gaps = numpy.diff(numpy.asarray(spots, dtype=numpy.float64))
            mean = gaps.mean()
            if mean > 0.0:
                out[value] = gaps.std() / mean
        return out

    live = spread(values)
    shuffled = values.copy()
    numpy.random.default_rng(SEED).shuffle(shuffled)
    dead = spread(shuffled)

    counts = {}
    for value in values:
        counts[int(value)] = counts.get(int(value), 0) + 1
    rows = []
    for value, live_spread in live.items():
        if (value in dead) and (live_spread > 0.0):
            rows.append((counts[value], dead[value] / live_spread))
    if len(rows) < 8:
        return None
    rows.sort()
    return statistics.fmean(row[1] for row in rows[:len(rows) // 2])


def volume_measure(values):
    """The excess of the bit correlation spectrum over the permuted null, at one window width."""
    live = spectrum_gap(gray_bits(values), WIDTH, numpy.random.default_rng(SEED))
    shuffled = values.copy()
    numpy.random.default_rng(SEED).shuffle(shuffled)
    dead = spectrum_gap(gray_bits(shuffled), WIDTH, numpy.random.default_rng(SEED))
    if (live is None) or (dead is None):
        return None
    return live - dead


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-24s %-24s %-19s %-22s %s\n"
              % ("corpus", "kind", "gap: given, drawn", "volume: given, drawn, sd", "volume verdict"))

    rng = numpy.random.default_rng(SEED)
    for name, kind in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-24s not present\n" % name[:-4])
            continue
        values = load(path, name)
        if len(values) < 20000:
            continue

        gap_given = gap_measure(values)
        volume_given = volume_measure(values)
        if (gap_given is None) or (volume_given is None):
            continue

        # Several renumberings, because one draw of a permutation is a sample of one and the spread
        # between draws is the same size as the differences being read off them
        gap_drawn = []
        volume_drawn = []
        for _ in range(DRAWS):
            renumbered = rng.permutation(256).astype(numpy.uint8)[values]
            gap_drawn.append(gap_measure(renumbered))
            volume_drawn.append(volume_measure(renumbered))
        gap_drawn = numpy.asarray([value for value in gap_drawn if value is not None])
        volume_drawn = numpy.asarray([value for value in volume_drawn if value is not None])
        if (len(gap_drawn) < 3) or (len(volume_drawn) < 3):
            continue

        spread = float(volume_drawn.std())
        distance = (abs(volume_given - float(volume_drawn.mean())) / spread
                    if spread > 0.0 else float("inf"))
        out.write("  %-24s %-24s %-19s %-22s %s\n"
                  % (name[:-4], kind,
                     "%.4f, %.4f" % (gap_given, float(gap_drawn.mean())),
                     "%.4f, %.4f, %.4f" % (volume_given, float(volume_drawn.mean()), spread),
                     "reads the numbering, %.1f sd" % distance if distance >= 3.0 else "blind to it"))

    out.write("\n  The gap measure reads only where each symbol falls, so renumbering cannot move it.\n")
    out.write("  Any movement in its two columns is a defect in this script, not a finding.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
