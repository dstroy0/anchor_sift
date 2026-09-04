#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure the one quantity that does not belong to a scale, for Section 4.11 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/spectral_exponent.py
#
# Every statistic used on these corpora so far has had a scale inside it and has been corrected once the
# scale showed. A window width was chosen and the choice was measured. A ceiling was put on a sum that has
# no bound. A band was fixed in levels and read a picture spread over 160 of them as flat. High frequency
# content was called sensor noise and then refused to fall as one over the square root of the block, which
# is what anything uncorrelated must do and what a painted surface never does.
#
# That last one is the whole difficulty in one measurement. A painted canvas and a natural scene carry
# structure at every scale, so there is no finest scale where only noise lives and no coarsest scale where
# structure stops. Any quantity read at one resolution is partly a reading of that resolution, which is why
# the same file gave 20.6 and 122.8 depending only on how much of it was read.
#
# For data with no scale of its own the invariant is how the quantity changes with scale. The power at a
# frequency falls as that frequency to some power, and that exponent is the same whatever length is read
# and whatever resolution it is read at. White noise gives zero, a random walk gives two, and a natural
# scene sits near two because that is what scale free structure looks like. The exponent is measured here
# at four read lengths so its own stability is shown and not assumed, which is the check the earlier
# statistics never got.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

LENGTHS = (75000, 150000, 300000, 600000)
# Center crops for pictures, as shares of each side, so the proportions hold while the area changes
SHARES = (0.4, 0.6, 0.8, 1.0)
LOW = 4
BANDS = 48

# Reported by the decoder when these files were fetched, so the plane is known here and not guessed at.
# A picture read as one long line carries its width as a periodicity and the slope through that is not the
# slope of the picture, which is why the paintings first came back near half of what a natural scene gives.
WIDTHS = {
    "art_seurat": 960,
    "art_starry": 960,
    "art_whistler": 960,
    "art_turner": 960,
    "art_mondrian": 595,
    "art_hokusai": 960,
    "art_vermeer": 960,
}

MEASURE = (
    "art_seurat.sym",
    "art_starry.sym",
    "art_whistler.sym",
    "art_turner.sym",
    "art_mondrian.sym",
    "art_hokusai.sym",
    "art_vermeer.sym",
    "voc_whale_humpback.sym",
    "env_voc_human_speech.sym",
    "english_1813_austen.sym",
    "csource_formal.sym",
    "monkey_a08_d18_uniform.sym",
)


def fit_bands(frequency, power):
    """Fit a straight line through the logs, in bands spaced evenly in the logs."""
    edges = numpy.unique(numpy.round(
        numpy.logspace(numpy.log10(LOW), numpy.log10(frequency.max()), BANDS)).astype(numpy.int64))
    centers = []
    heights = []
    for index in range(len(edges) - 1):
        low, high = edges[index], edges[index + 1]
        if high <= low:
            continue
        inside = (frequency >= low) & (frequency < high)
        if not inside.any():
            continue
        centers.append(numpy.sqrt(float(low) * float(high)))
        heights.append(float(power[inside].mean()))
    if len(centers) < 8:
        return None, None

    logs = numpy.log10(numpy.asarray(centers))
    values_log = numpy.log10(numpy.asarray(heights))
    slope, intercept = numpy.polyfit(logs, values_log, 1)
    predicted = (slope * logs) + intercept
    spread = float(((values_log - values_log.mean()) ** 2).sum())
    quality = 1.0 - (float(((values_log - predicted) ** 2).sum()) / spread) if spread > 0 else 0.0
    return -float(slope), quality


def exponent_plane(values, width):
    """Exponent of the power against radial frequency, over the picture as a plane."""
    rows = len(values) // width
    if rows < 64:
        return None, None
    grid = values[:rows * width].reshape(rows, width).astype(numpy.float64)
    grid = grid - grid.mean()
    if grid.std() <= 0.0:
        return None, None
    power = numpy.abs(numpy.fft.fftshift(numpy.fft.fft2(grid))) ** 2
    down = numpy.arange(rows) - (rows // 2)
    across = numpy.arange(width) - (width // 2)
    radius = numpy.sqrt((down[:, None] ** 2) + (across[None, :] ** 2))
    keep = radius >= LOW
    return fit_bands(radius[keep], power[keep])


def exponent(values):
    """Slope of the power against frequency in logs, which is the exponent the power law follows.

    Averaged into bands spaced evenly in the logs, so the many high frequencies do not outvote the few low
    ones and the fit describes the whole range instead of its top end.
    """
    floats = values.astype(numpy.float64)
    floats = floats - floats.mean()
    if floats.std() <= 0.0:
        return None, None
    power = numpy.abs(numpy.fft.rfft(floats)) ** 2
    power = power[1:]
    frequency = numpy.arange(1, len(power) + 1, dtype=numpy.float64)
    return fit_bands(frequency, power)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  exponent over four extents, pictures by center crop and the rest by read length\n")
    out.write("  %-24s %s   %-8s %s\n"
              % ("corpus", "  ".join("%9s" % ("part %d" % (index + 1)) for index in range(4)),
                 "fit r2", "spread"))

    for name in MEASURE:
        path = os.path.join(CORPORA, name)
        if not os.path.isfile(path):
            out.write("  %-24s not present\n" % name[:-4])
            continue
        with open(path, "rb") as handle:
            whole = numpy.frombuffer(handle.read(), dtype=numpy.uint8)

        label = name[:-4]
        width = WIDTHS.get(label)
        found = []
        quality = None
        if width is not None:
            # Center crops keeping the picture's proportions, because a short read of a row major file is
            # a thin strip and a radial average over a strip is not a radial average over a picture. That
            # alone made the exponent climb from 1.21 to 2.06 on one painting with nothing else changed.
            rows = len(whole) // width
            grid = whole[:rows * width].reshape(rows, width)
            for share in SHARES:
                high = max(64, int(rows * share))
                across = max(64, int(width * share))
                top = (rows - high) // 2
                left = (width - across) // 2
                piece = grid[top:top + high, left:left + across]
                slope, fit = exponent_plane(piece.reshape(-1), across)
                found.append(slope)
                if fit is not None:
                    quality = fit
        else:
            for length in LENGTHS:
                if len(whole) < length:
                    found.append(None)
                    continue
                slope, fit = exponent(whole[:length])
                found.append(slope)
                if fit is not None:
                    quality = fit
        clean = numpy.asarray([value for value in found if value is not None])
        if len(clean) < 2:
            continue
        out.write("  %-24s %s   %-8s %.4f\n"
                  % (name[:-4],
                     "  ".join("%9s" % ("%.3f" % value if value is not None else "short")
                               for value in found),
                     "%.3f" % quality if quality is not None else "none",
                     float(clean.std())))

    out.write("\n  Zero is white noise, two is a random walk, and a natural scene sits near two.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
