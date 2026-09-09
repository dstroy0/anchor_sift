#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-1-001
#
# A deposited cell becoming points carrying values, with every digit it was written with.
#
#   Usage:  python examples/crystallography/1_represent/a_cell_as_exact_points.py [entry.cif ...]
#
# This subject had no stage one for a while, and the reason given was that parsing a CIF and tiling a
# right angled cell is domain knowledge and not a demonstration. That was right about where the
# reader belongs and wrong about there being nothing to show, because the reader was deciding the
# result. It put every site on a grid of 0.25 angstroms on the way in, and the recovered cell edge
# then carried that grid instead of the deposit.
#
# What is shown here is one entry read both ways. The exact reading carries the deposited text as
# integers, a numerator and a count of decimal places, leaving a coordinate that is the number
# published. The voxel reading divides by 0.25 and truncates, and the difference between the two is
# printed per site, in angstroms.
#
# A crystal is the domain where that difference can be seen at all, because the answer is published.
# Everywhere else in this tree the same rounding happens against nothing to check it with.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation import exact  # noqa: E402
from representation.structure import crystal  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")

# Sites listed one by one before the run is summarized.
SHOWN = 12


def angstroms(value, places=8):
    """An exact integer at the scale, as decimal text cut to `places` for the column it sits in.

    The cut is for reading only. Nothing downstream sees it, and the full value is what is compared.
    """
    sign = "-" if value < 0 else ""
    digits = str(abs(value)).rjust(exact.SCALE_DIGITS + 1, "0")
    whole = digits[:-exact.SCALE_DIGITS]
    part = digits[-exact.SCALE_DIGITS:][:places].rstrip("0")
    return "%s%s.%s" % (sign, whole, part) if part else "%s%s" % (sign, whole)


def one_entry(path, out):
    """Read one deposit both ways and print what each keeps."""
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    points, published = crystal.exact_points(text, tiles=1)
    if points is None:
        out.write("  %s: no right angled cell to read\n" % os.path.basename(path))
        return False

    cell, sites = crystal.parse_cif(text)
    elements = sorted({value for _, value in points})

    out.write("\n  %s\n" % os.path.basename(path))
    out.write("    %d site(s) in one cell, %d element(s): %s\n"
              % (len(points), len(elements), " ".join(elements)))
    out.write("    published edges  %s  %s  %s angstroms\n"
              % tuple(angstroms(one) for one in published))
    out.write("    widest coordinate is %d bits, and the whole cell is %d integers\n"
              % (max(abs(one) for place, _ in points for one in place).bit_length(),
                 3 * len(points)))

    out.write("\n    %-4s %-16s %-16s %-12s\n" % ("", "exact", "on a 0.25 grid", "difference"))
    worst = 0
    for at, (place, element) in enumerate(points):
        # The grid reading, reproduced from the same deposited value the exact one used.
        along = (sites[at][0] * cell["a"]) / crystal.VOXEL
        gridded = int(along) * crystal.VOXEL
        held = exact.scaled("%.10f" % gridded)
        gap = abs(place[0] - held)
        worst = max(worst, gap)
        if at < SHOWN:
            out.write("    %-4s %-16s %-16s %-12s\n"
                      % (element, angstroms(place[0]), angstroms(held), angstroms(gap)))
    if len(points) > SHOWN:
        out.write("    and %d more\n" % (len(points) - SHOWN))
    out.write("\n    worst the grid moved a site along a: %s angstroms\n" % angstroms(worst))
    return True


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    wanted = [one for one in sys.argv[1:] if not one.startswith("-")]
    if not wanted:
        if not os.path.isdir(CACHE):
            out.write("\n  nothing cached under build/cod. Run the oracle to fill it.\n\n")
            out.flush()
            return 1
        wanted = [os.path.join(CACHE, one)
                  for one in sorted(os.listdir(CACHE))[:3] if one.endswith(".cif")]

    out.write("\n  One cell read twice. The exact reading keeps the deposited digits. The grid\n")
    out.write("  reading keeps 0.25 angstroms, which nobody who measured the crystal chose.\n")

    read = 0
    for path in wanted:
        if one_entry(path, out):
            read += 1
    out.write("\n  %d entry(s) read\n\n" % read)
    out.flush()
    return 0 if read else 1


if __name__ == "__main__":
    raise SystemExit(main())
