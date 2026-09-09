#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ART-4-004
#
# Separate what was made from how it was recorded by measuring across scales, for Section 4.11 of
# theory/anchor_sift.
#
#   Usage:  python examples/art/4_measure/scale_ladder.py
#
# Among seven paintings the bit volume's dependence on its numbering is predicted better by the grain of
# the photograph than by anything in the painting: the grain alone ranks it at rho 0.929, against 0.821
# for the abruptness left after the grain is subtracted and 0.786 for the abruptness as it arrives. Taken
# at one sampling that reads as a fact about the paintings, and it is a fact about the cameras.
#
# It reads that way because one sampling is all that was measured. A painted surface has gradients all the
# way down and a photograph of it has a finite number of samples, so every number here is taken at the
# resolution the file happens to carry, and the finest scale in that file is exactly where the grain
# lives.
#
# Scale separates them. Averaging neighboring samples in blocks cuts anything uncorrelated by the
# square root of the block size, while a region of a painting that is genuinely one tone stays one tone at
# every scale it survives to. So the same measurements are taken up a ladder of block sizes, and a
# quantity carried by the grain falls away while a quantity carried by the painting holds. Where each one
# lands as the blocks grow is the reading the sampling was hiding.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.stays import noise_level  # noqa: E402
from representation.bit_volume import spectrum_excess  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

SEED = 0x51F7
DRAWS = 8
# Read here instead of through the shared loader, which caps at a length that leaves nothing to average
# once the blocks get large and reported every coarse rung as short
CAP = 600000
STEPS = (1, 2, 4, 8, 16)

MEASURE = (
    "art_seurat.sym",
    "art_starry.sym",
    "art_whistler.sym",
    "art_turner.sym",
    "art_mondrian.sym",
    "art_hokusai.sym",
    "art_vermeer.sym",
    "env_voc_human_speech.sym",
)


def coarsen(floats, block):
    """Average neighboring samples in blocks, which cuts the uncorrelated part and keeps the rest."""
    if block == 1:
        return floats
    usable = (len(floats) // block) * block
    return floats[:usable].reshape(-1, block).mean(axis=1)


def dependence(values, rng):
    """How far the bit volume reading sits from its own renumberings, in standard deviations."""
    given = spectrum_excess(values)
    if given is None:
        return None
    drawn = []
    for _ in range(DRAWS):
        drawn.append(spectrum_excess(rng.permutation(256).astype(numpy.uint8)[values]))
    drawn = numpy.asarray([value for value in drawn if value is not None])
    if len(drawn) < 3:
        return None
    spread = float(drawn.std())
    if spread <= 0.0:
        return None
    return abs(given - float(drawn.mean())) / spread


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  dependence on the numbering, up a ladder of block sizes\n")
    out.write("  %-24s %s\n" % ("corpus", "  ".join("%9s" % ("block %d" % step) for step in STEPS)))

    collected = []
    for name in MEASURE:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-24s not present\n" % name[:-4])
            continue
        with open(path, "rb") as handle:
            floats = numpy.frombuffer(handle.read(CAP), dtype=numpy.uint8).astype(numpy.float64)
        if len(floats) < 320000:
            continue

        readings = []
        grains = []
        rng = numpy.random.default_rng(SEED)
        for step in STEPS:
            coarse = coarsen(floats, step)
            if len(coarse) < 20000:
                readings.append(None)
                grains.append(None)
                continue
            # Returned to whole levels, since the volume reads symbols and an average is not one
            seated = numpy.clip(numpy.rint(coarse), 0, 255).astype(numpy.uint8)
            readings.append(dependence(seated, rng))
            grains.append(noise_level(coarse))
        collected.append((name[:-4], readings, grains))
        out.write("  %-24s %s\n"
                  % (name[:-4],
                     "  ".join("%9s" % ("%.1f" % value if value is not None else "short")
                               for value in readings)))

    out.write("\n  high frequency level at each block size, against what uncorrelated noise would do\n")
    out.write("  %-24s %s\n" % ("corpus", "  ".join("%9s" % ("block %d" % step) for step in STEPS)))
    for label, _, grains in collected:
        out.write("  %-24s %s\n"
                  % (label, "  ".join("%9s" % ("%.2f" % value if value is not None else "short")
                                      for value in grains)))
        if grains[0] is not None:
            out.write("  %-24s %s   if it were noise\n"
                      % ("",
                         "  ".join("%9s" % ("%.2f" % (grains[0] / numpy.sqrt(step)))
                                   for step in STEPS)))

    # Ranked at the coarsest block against the finest, since a ranking that survives the grain being
    # averaged away is a ranking of the paintings and not of the cameras
    art = [row for row in collected if row[0].startswith("art_")
           and row[1][0] is not None and row[1][-1] is not None]
    if len(art) >= 5:
        first = numpy.argsort(numpy.argsort(numpy.asarray([row[1][0] for row in art])))
        last = numpy.argsort(numpy.argsort(numpy.asarray([row[1][-1] for row in art])))
        out.write("\n  order at block 1 against order at block %d over %d paintings: rho %.3f\n"
                  % (STEPS[-1], len(art), float(numpy.corrcoef(first, last)[0, 1])))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
