#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CEL-1-001
#
# How far a real cell moves between two frames, read off the answer key.
#
#   Usage:  python examples/cell_tracking/1_represent/how_far_a_cell_moves.py [extracted dataset dir]
#
# THE QUESTION THIS SETTLES, AND IT DECIDES WHETHER THE REST OF THIS SUBTREE MATTERS. Every
# measurement in examples/cell_tracking so far is about recovering a displacement to a fraction of a
# pixel. That work is worth doing if cells move a pixel or two between frames and is worth nothing if
# they move twenty, because at twenty pixels the whole lag carries the answer and the fraction is
# noise on top of it. Nothing measured so far establishes which of those this data is, and the
# figure was never looked up. It is available directly: the ground truth carries every cell's
# position in every frame.
#
# theory/workbook records the same defect from the other side, that a bound is chosen because
# something has to be chosen and the number then describes the choice. A feature width of 6 px and a
# displacement of 3.4 px were both invented by this author to stand in for a cell, and this file is
# what should have set them.
#
# WHAT IS READ. Fluo-N2DH-SIM+, sequence 01, the tracking ground truth. Each frame is a label image
# where every pixel carries the identity of the cell it belongs to, and man_track.txt carries one
# row per track as `label begin end parent`, with a non-zero parent naming a division. A cell's
# position in a frame is the centroid of its own label, which is exact arithmetic over the pixels
# the annotation assigned and involves no detector and no threshold of this work's.
#
# WHAT IS NOT MEASURED HERE. Anything this work does. No sift, no agreement, no null. This reads the
# answer key alone, to size the problem before any instrument is pointed at it.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)

DEFAULT = os.path.join("D:", os.sep, "tmp_ctc", "Fluo-N2DH-SIM+")


def frames(where):
    """Every ground truth label image in order, as arrays."""
    from PIL import Image
    track = os.path.join(where, "01_GT", "TRA")
    files = sorted(name for name in os.listdir(track) if name.endswith(".tif"))
    for name in files:
        yield numpy.array(Image.open(os.path.join(track, name)))


def centroids(labels):
    """Every label's centroid in one frame, as {label: (row, column)}.

    Exact over the pixels the annotation assigned. No threshold and no detector of this work's
    enters, which is what makes this an answer key rather than a second reading.
    """
    out = {}
    present = numpy.unique(labels)
    for label in present:
        if label == 0:
            continue
        rows, columns = numpy.nonzero(labels == label)
        out[int(label)] = (float(rows.mean()), float(columns.mean()))
    return out


def lineage(where):
    """man_track.txt as {label: (begin, end, parent)}."""
    out = {}
    path = os.path.join(where, "01_GT", "TRA", "man_track.txt")
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            parts = line.split()
            if len(parts) == 4:
                label, begin, end, parent = (int(value) for value in parts)
                out[label] = (begin, end, parent)
    return out


def main():
    where = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(where):
        out.write("  not found: %s\n" % where)
        out.write("  Fetch and extract first:\n")
        out.write("    python maint/data/fetch/fetch_ctc.py --fetch Fluo-N2DH-SIM+\n")
        out.flush()
        return 1

    tracks = lineage(where)
    divisions = sum(1 for _, _, parent in tracks.values() if parent != 0)

    steps = []
    sizes = []
    previous = None
    count = 0
    for labels in frames(where):
        count += 1
        here = centroids(labels)
        for label in here:
            rows, columns = numpy.nonzero(labels == label)
            # Equivalent diameter of the label's area, which is the closest thing to the width
            # the synthetic fields called a blob width.
            sizes.append(2.0 * numpy.sqrt(len(rows) / numpy.pi))
        if previous is not None:
            for label, (row, column) in here.items():
                if label in previous:
                    was_row, was_column = previous[label]
                    steps.append(numpy.hypot(row - was_row, column - was_column))
        previous = here

    steps = numpy.array(steps)
    sizes = numpy.array(sizes)

    out.write("  Fluo-N2DH-SIM+ sequence 01, tracking ground truth.\n")
    out.write("  %d frames, %d tracks, %d of them born from a division.\n\n"
              % (count, len(tracks), divisions))

    out.write("  Displacement between consecutive frames, per cell, in pixels:\n")
    for name, value in (("p50", 50), ("p75", 75), ("p90", 90), ("p99", 99)):
        out.write("    %-6s %.3f\n" % (name, float(numpy.percentile(steps, value))))
    out.write("    %-6s %.3f\n" % ("max", float(steps.max())))
    out.write("    %-6s %.3f\n" % ("mean", float(steps.mean())))

    out.write("\n  Cell diameter, equivalent from area, in pixels:\n")
    out.write("    %-6s %.3f\n" % ("p50", float(numpy.percentile(sizes, 50))))
    out.write("    %-6s %.3f\n" % ("mean", float(sizes.mean())))

    median = float(numpy.median(steps))
    out.write("\n  A median step of %.3f px against a sub-pixel error of 0.0483 px measured on\n"
              % median)
    out.write("  synthetic fields at 256 levels. The fraction is worth %.0f%% of a typical step.\n"
              % (100.0 * 0.0483 / median if median > 0 else 0.0))
    if median > 8.0:
        out.write("\n  That is a large step. The whole lag carries the answer at this scale and\n")
        out.write("  the sub-pixel work in 2_partition and 4_measure is a refinement on a\n")
        out.write("  quantity that was never the difficulty. Linking across steps this size is.\n")
    elif median < 2.0:
        out.write("\n  That is a small step. Cells move less than two pixels a frame. The\n")
        out.write("  fraction is most of the displacement and the sub-pixel work is load bearing.\n")
    else:
        out.write("\n  That is a middling step, where the whole lag and the fraction both carry\n")
        out.write("  part of the answer and neither alone is the reading.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
