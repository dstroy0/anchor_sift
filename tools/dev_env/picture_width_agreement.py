#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Put the two instruments in this work on the same picture and see whether they agree, for Section 4.11 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/picture_width_agreement.py
#
# Three claims in this work reported one instrument's result as the other's, because both return a number
# near one for nothing and a departure for something. Nothing was ever measured to connect them. This
# measures it.
#
# A picture stored row by row carries its width as a period, so both instruments should be able to find
# it. The shift detector reads the share of positions equal to the position one lag away and takes the
# lag where that share peaks, which is how Section 4.11 recovered a record period. The point cloud
# reduction reads the displacement from each point to the nearest point holding the same value, and at
# the true width the picture reshapes into a plane where those displacements are short and directional,
# while at a wrong width the rows slide against each other and the arrangement is scrambled.
#
# The two share no code, no null and no statistic. If they peak at the same width on the same file, that
# is a measured link between them and the first this work has. If they peak at different widths, at most
# one of them recovers a picture's width and the other has been reporting something else.
#
# Both are swept over the widths that divide the file length exactly, since a partial final row is not a
# rectangle. The true width is not supplied to either.

import io
import os
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from point_cloud import reduce_cloud

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

LOW = 200
HIGH = 2000
STRIDE = 7


def shift_peak(data, widths):
    """The width where the share of positions equal to the position one width away is highest."""
    marks = []
    for width in widths:
        window = data[:len(data) - width:STRIDE]
        shifted = data[width::STRIDE][:len(window)]
        marks.append((float((window == shifted).mean()), width))
    marks.sort(reverse=True)
    return marks[0][1], marks[0][0], marks


def cloud_peak(data, widths):
    """The width where reshaping the file into a plane departs furthest from the permutation null."""
    marks = []
    for width in widths:
        grid = data.reshape(-1, width)
        step = max(1, width // 180)
        thinned = grid[::step, ::step]
        rows, columns = thinned.shape
        if (rows < 24) or (columns < 24):
            continue
        vertical, horizontal = numpy.mgrid[0:rows, 0:columns]
        coords = numpy.stack([horizontal.ravel(), vertical.ravel()], axis=1).astype(numpy.float64)
        # Quantized so a value recurs often enough to have neighbours of its own
        values = (thinned.ravel() >> 3).astype(numpy.int64)
        found = reduce_cloud(coords, values, 32, 2)
        if (found is None) or (found[2] is None):
            continue
        # Ranked on the orientation channel, which is the one that only exists once there is a plane
        marks.append((found[2], width, found[0], found[2]))
    if not marks:
        return None, None, []
    marks.sort(reverse=True)
    return marks[0][1], marks[0][0], marks


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-14s %-9s %-9s %-10s %s\n"
              % ("picture", "shift w", "cloud w", "agree", "cloud departure at its peak"))

    names = sorted(name for name in os.listdir(CORPORA)
                   if name.startswith("art_") and name.endswith(".sym"))
    for name in names:
        with open(os.path.join(CORPORA, name), "rb") as handle:
            data = numpy.frombuffer(handle.read(), dtype=numpy.uint8)
        widths = [width for width in range(LOW, HIGH + 1) if (len(data) % width) == 0]
        if len(widths) < 3:
            out.write("  %-14s only %d candidate widths, nothing to choose between\n"
                      % (name[:-4], len(widths)))
            continue

        shift_width, shift_score, shift_marks = shift_peak(data, widths)
        cloud_width, _, cloud_marks = cloud_peak(data, widths)
        if cloud_width is None:
            out.write("  %-14s %-9d %-9s cloud found no scorable width\n"
                      % (name[:-4], shift_width, "none"))
            continue
        top = cloud_marks[0]
        out.write("  %-14s %-9d %-9d %-10s length %.3f, orientation %s\n"
                  % (name[:-4], shift_width, cloud_width,
                     "yes" if shift_width == cloud_width else "no",
                     top[2], ("%.3f" % top[3]) if top[3] is not None else "none"))
        out.write("      shift ranking %s\n"
                  % " ".join("%d:%.4f" % (mark[1], mark[0]) for mark in shift_marks[:6]))
        out.write("      cloud ranking %s\n"
                  % " ".join("%d:%.3f" % (mark[1], mark[3]) for mark in cloud_marks[:6]))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
