#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Read the dimension count off real structures instead of made ones, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/protein_dimension.py
#
# Eleven of twelve readings recovered the dimension count from a single line, and every one of those sets
# was built here, with a correlation length put along each axis by hand to make the axes tellable apart.
# That is the friendliest possible case and it proves the method works on sets shaped to suit it.
#
# A protein is the honest version. It occupies three dimensions, nobody here chose its shape, and its axes
# differ because a folded chain is longer one way than another and packs differently along each. If the
# count comes back as three from a line drawn through a structure that was measured in a laboratory, the
# claim holds outside the fields written to demonstrate it.
#
# The atoms are laid into a grid and smoothed, which is not a convenience. A structure is observed as a
# density and deposited atoms with no smoothing give a grid that is almost entirely empty, so the readings
# would describe the emptiness. Smoothing to a few voxels is what the measurement that produced these
# coordinates actually resolves.
#
# Nothing about the structure is given to the reader. It receives one line of bytes.

import io
import os
import sys
import urllib.request

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from read_dimension import best_count, roughness
from spectral_exponent import exponent
from squash_dimensions import interleave, volume_exponent

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0"}

SEED = 0x51F7
SIDE = 64
# Swept, because the first run smoothed by 1.6 voxels and put every structure at an exponent of 5.8 to
# 7.5, where the reading along the line is the curve's own floor and carries nothing about the structure
BLURS = (0.3, 0.5, 0.8, 1.2, 1.6)

WANTED = (
    ("1UBQ", "ubiquitin, small and compact"),
    ("4HHB", "hemoglobin, four chains"),
    ("1AON", "chaperonin, large barrel"),
    ("1BNA", "a DNA duplex, strongly elongated"),
    ("6VXX", "a spike glycoprotein"),
    ("1CRN", "crambin, very small"),
)


def fetch(code):
    path = os.path.join(CORPORA, "pdb_%s.txt" % code)
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    url = "https://files.rcsb.org/download/%s.pdb" % code
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=180) as response:
        text = response.read().decode("utf-8", errors="replace")
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    return text


def atoms(text):
    """Every atom position in the file, in the order the file lists them."""
    found = []
    for line in text.splitlines():
        if not line.startswith("ATOM"):
            continue
        try:
            found.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))
        except ValueError:
            continue
    return numpy.asarray(found, dtype=numpy.float64)


def density(points, side, blur):
    """Atoms laid into a grid and smoothed, which is the form a structure is observed in."""
    low = points.min(axis=0)
    high = points.max(axis=0)
    span = high - low
    if float(span.min()) <= 0.0:
        return None
    # Each axis scaled on its own, so the grid holds the shape and not the bounding cube
    placed = numpy.clip(((points - low) / span * (side - 1)).astype(numpy.int64), 0, side - 1)
    grid = numpy.zeros((side,) * 3, dtype=numpy.float64)
    numpy.add.at(grid, (placed[:, 0], placed[:, 1], placed[:, 2]), 1.0)

    axes = numpy.meshgrid(*[numpy.fft.fftfreq(side) * side] * 3, indexing="ij")
    radius = sum(axis ** 2 for axis in axes)
    kernel = numpy.exp(-2.0 * (numpy.pi ** 2) * (blur ** 2) * radius / (side ** 2))
    smooth = numpy.real(numpy.fft.ifftn(numpy.fft.fftn(grid) * kernel))

    spread = smooth.std()
    if spread <= 0.0:
        return None
    scaled = (smooth - smooth.mean()) / spread
    return numpy.clip(numpy.rint((scaled * 42.0) + 128.0), 0, 255).astype(numpy.uint8)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Predicted before measuring: three, at whatever smoothing puts the exponent in range.\n\n")
    out.write("  %-8s %-6s %-8s %-10s %-9s %-8s %s\n"
              % ("code", "blur", "atoms", "over set", "line", "found", "score"))

    rng = numpy.random.default_rng(SEED)
    hits = 0
    total = 0
    for code, note in WANTED:
        try:
            text = fetch(code)
        except Exception as trouble:
            out.write("  %-8s could not fetch: %s\n" % (code, trouble))
            continue
        points = atoms(text)
        if len(points) < 400:
            out.write("  %-8s only %d atoms\n" % (code, len(points)))
            continue

        for blur in BLURS:
            field = density(points, SIDE, blur)
            if field is None:
                continue
            series = interleave(field)
            found, score, _ = best_count(roughness(series), rng)
            over, _ = volume_exponent(field)
            along, _ = exponent(series)
            if found is None:
                continue
            # Counted only where the set sits in the range the synthetic fields established
            inside = (over is not None) and (over <= 3.5)
            if inside:
                total += 1
                hits += 1 if found == 3 else 0
            out.write("  %-8s %-6.1f %-8d %-10s %-9s %-8d %-8.2f %s\n"
                      % (code, blur, len(points),
                         "%.3f" % over if over is not None else "none",
                         "%.3f" % along if along is not None else "none",
                         found, score, "in range" if inside else ""))
        out.write("\n")

    out.write("  %d of %d readings inside the workable range returned three\n" % (hits, total))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
