#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether the bit volume measures a corpus or the numbering given to its symbols, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/seating_invariance.py
#
# Three times now a free parameter has been introduced and then measured in place of the corpus: a
# dimension assigned per domain, a ceiling chosen for a sweep with no bound, and now the number each
# symbol is given. The bit volume Gray codes those numbers so that two values one apart differ in one
# bit, which is only meaningful where being one apart already meant something. A greyscale level, a sound
# amplitude and an ASCII code all carry that order. A number handed out in order of first appearance does
# not, and neither does one handed out by a re-carving.
#
# The corpora that read strongest are exactly the ones whose bytes carry a real order, and the ones that
# read near zero are the ones numbered here. That is what this checks. Each corpus is measured under its
# own numbering and then under random renumberings of the same symbols, which leave every frequency and
# every position untouched and change only which number each symbol was given.
#
# If the reading holds across renumbering, the numbering was not what was being measured, and the earlier
# result stands for the corpora numbered here. If the reading collapses, the volume is reading an
# ordering that was invented, and no cross corpus row from it means anything.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from point_volume import CAP, WIDTHS, gray_bits, load, spectrum_gap

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
DRAWS = 8

WANTED = (
    "art_hokusai.sym",
    "art_starry.sym",
    "art_vermeer.sym",
    "csource_formal.sym",
    "env_voc_human_speech.sym",
    "voc_whale_humpback.sym",
    "english_1813_austen.sym",
    "greek_iliad.sym",
    "monkey_a08_d18_uniform.sym",
)


def excess_at(values, width):
    """The excess over the permuted null at one window width, for one numbering of the symbols."""
    live = spectrum_gap(gray_bits(values), width, numpy.random.default_rng(SEED))
    shuffled = values.copy()
    numpy.random.default_rng(SEED).shuffle(shuffled)
    dead = spectrum_gap(gray_bits(shuffled), width, numpy.random.default_rng(SEED))
    if (live is None) or (dead is None):
        return None
    return live - dead


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-26s %-12s %-22s %s\n"
              % ("corpus", "as numbered", "renumbered mean, sd", "verdict"))

    rng = numpy.random.default_rng(SEED)
    for name in WANTED:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-26s not present\n" % name[:-4])
            continue
        values = load(path, name)
        if len(values) < 20000:
            continue

        given = excess_at(values, 32)
        if given is None:
            continue

        drawn = []
        for _ in range(DRAWS):
            seating = rng.permutation(256).astype(numpy.uint8)
            drawn.append(excess_at(seating[values], 32))
        drawn = numpy.asarray([value for value in drawn if value is not None])
        if len(drawn) < 3:
            continue

        # A reading inside the spread of its own renumberings is a reading of the corpus. A reading far
        # outside that spread came from the numbering, which was chosen here and is not a fact about it.
        spread = float(drawn.std())
        distance = abs(given - float(drawn.mean())) / spread if spread > 0 else float("inf")
        out.write("  %-26s %-12.4f %-22s %s\n"
                  % (name[:-4], given, "%.4f, %.4f" % (drawn.mean(), spread),
                     "holds" if distance < 3.0 else "numbering, %.1f sd out" % distance))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
