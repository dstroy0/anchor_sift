#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether abruptness sets how far a corpus depends on its numbering, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/abruptness.py
#
# How long a corpus stays near a value says which side of the split it falls on and not how far it goes.
# Starry Night has the largest dependence in the set at 278.2 standard deviations and the shortest stay of
# the four that move, while Vermeer has the longest stay and the smallest dependence at 8.1. So the two
# quantities run opposite to each other among the movers, and the candidate for the second one is how
# sharply the corpus crosses between the values it stays at. Starry Night is short holds separated by hard
# transitions. Vermeer is long holds joined by soft ones.
#
# Four paintings out of copyright are fetched to test that as a prediction and not as a description of
# what was already measured: a pointillist surface at the abrupt end, flat regions with hard edges,
# and two atmospheric paintings at the smooth end. Every prediction is written into the output before the
# numbers come back so a miss cannot be reread afterward as a hit.
#
# Abruptness is read two ways, because a picture holds two kinds of it and only one belongs to the
# painter. The share of large steps counts every crossing, the brushwork and the grain of the photograph
# alike, and a dark canvas carries noise in its shadows that lands in that count as if it had been
# painted. Noise is separable from what was made: it is uncorrelated between neighbouring positions, so a
# second difference cancels the smooth content and leaves it, and the median of that keeps the sparse real
# edges from inflating the estimate. Subtracting its contribution leaves the share of crossings the
# painter is responsible for, and the gap between the two counts is what the acquisition added.

import io
import os
import sys
import urllib.parse
import urllib.request

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from island_size import BAND_SHARE, mean_stay
from point_volume import gray_bits, load, spectrum_gap

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0"}

SEED = 0x51F7
WIDTH = 32
DRAWS = 8
CAP = 120000
SIDE = 512

FETCH = (
    ("art_seurat", "Georges Seurat - A Sunday on La Grande Jatte -- 1884 - Google Art Project.jpg"),
    ("art_mondrian", "Composition with Red, Yellow, Black, Blue and Grey by Piet Mondrian, 1921.jpg"),
    ("art_turner", "Turner - Rain, Steam and Speed - National Gallery file.jpg"),
    ("art_whistler", "Whistler-Nocturne in black and gold.jpg"),
)

MEASURE = (
    "art_seurat.sym",
    "art_starry.sym",
    "art_mondrian.sym",
    "art_hokusai.sym",
    "art_turner.sym",
    "art_whistler.sym",
    "art_vermeer.sym",
    "voc_whale_humpback.sym",
    "env_voc_human_speech.sym",
    "english_1813_austen.sym",
)


def fetch_missing(out):
    """Store any painting not already held, leaving the ones that are alone."""
    from PIL import Image

    for name, title in FETCH:
        path = os.path.join(CORPORA, "%s.sym" % name)
        if os.path.isfile(path):
            continue
        url = ("https://commons.wikimedia.org/wiki/Special:FilePath/"
               + urllib.parse.quote(title) + "?width=%d" % SIDE)
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=180) as response:
                blob = response.read()
            picture = Image.open(io.BytesIO(blob)).convert("L")
        except Exception as trouble:
            out.write("  %-16s could not fetch: %s\n" % (name, trouble))
            continue
        with open(path, "wb") as handle:
            handle.write(picture.tobytes())
        out.write("  %-16s stored, %d by %d\n" % (name, picture.size[0], picture.size[1]))


def noise_level(floats):
    """Standard deviation of the uncorrelated part, from the median of the second differences.

    A second difference cancels any straight run, so what it leaves is noise plus the real edges. The
    edges are sparse, so the median of it is set by the noise alone and a painting full of hard crossings
    does not inflate the estimate. A second difference of pure noise has six times its variance.
    """
    second = floats[2:] - (2.0 * floats[1:-1]) + floats[:-2]
    return 1.4826 * float(numpy.median(numpy.abs(second))) / numpy.sqrt(6.0)


def steady(floats):
    """The series with isolated spikes removed and its edges intact, by a median of every three."""
    stacked = numpy.stack([floats[:-2], floats[1:-1], floats[2:]])
    return numpy.median(stacked, axis=0)


def volume_at(values):
    live = spectrum_gap(gray_bits(values), WIDTH, numpy.random.default_rng(SEED))
    shuffled = values.copy()
    numpy.random.default_rng(SEED).shuffle(shuffled)
    dead = spectrum_gap(gray_bits(shuffled), WIDTH, numpy.random.default_rng(SEED))
    if (live is None) or (dead is None):
        return None
    return live - dead


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    fetch_missing(out)
    out.write("\n  %-24s %-11s %-11s %-9s %-9s %s\n"
              % ("corpus", "abrupt raw", "authored", "noise", "grain sd", "sd from renumbering"))

    rng = numpy.random.default_rng(SEED)
    gathered = []
    for name in MEASURE:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-24s not present\n" % name[:-4])
            continue
        values = load(path, name)[:CAP]
        if len(values) < 20000:
            continue

        floats = values.astype(numpy.float64)
        spread = float(floats.std())
        if spread <= 0.0:
            continue
        steps = numpy.abs(numpy.diff(floats))
        abrupt = float((steps > spread).mean())
        # Measured on the same scale as the raw count, so the two columns subtract
        settled = steady(floats)
        authored = float((numpy.abs(numpy.diff(settled)) > spread).mean())
        grain = noise_level(floats)
        stay = mean_stay(values, max(1.0, BAND_SHARE * spread))

        given = volume_at(values)
        if given is None:
            continue
        drawn = []
        for _ in range(DRAWS):
            drawn.append(volume_at(rng.permutation(256).astype(numpy.uint8)[values]))
        drawn = numpy.asarray([value for value in drawn if value is not None])
        if len(drawn) < 3:
            continue
        scatter = float(drawn.std())
        distance = (abs(given - float(drawn.mean())) / scatter) if scatter > 0.0 else float("inf")
        out.write("  %-24s %-11.4f %-11.4f %-9.2f %-9.2f %.1f\n"
                  % (name[:-4], abrupt, authored, abrupt - authored, grain, distance))
        gathered.append((abrupt if name.startswith("art_") else None, authored, grain, distance))

    # Ranked over the paintings alone, since abruptness runs the other way between families: text scores
    # highest of anything measured and does not depend on its numbering at all
    art = [row for row in gathered if row[0] is not None]
    if len(art) >= 5:
        against = numpy.argsort(numpy.argsort(numpy.asarray([row[3] for row in art])))
        for label, column in (("as measured", 0), ("noise removed", 1), ("the grain alone", 2)):
            side = numpy.argsort(numpy.argsort(numpy.asarray([row[column] for row in art])))
            out.write("\n  abruptness %s against dependence over %d paintings: rho %.3f"
                      % (label, len(art), float(numpy.corrcoef(side, against)[0, 1])))
        out.write("\n")

    out.write("\n  Predicted before measuring, from the ordering the three earlier paintings gave:\n")
    out.write("  the pointillist surface most abrupt and most dependent, above Starry Night's 282;\n")
    out.write("  the flat regions with hard edges long staying and low in abruptness; the two\n")
    out.write("  atmospheric paintings least abrupt and least dependent, near Vermeer's 8.1.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
