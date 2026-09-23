"""The directions a boundary reading cannot see, drawn beside the field they produce.

    python examples/00_blob_viz_tools/build_blind_view.py
    python examples/00_blob_viz_tools/build_blind_view.py --degree 8 --count 256
    python examples/00_blob_viz_tools/build_blind_view.py --check

WHAT THIS DRAWS

A reading to degree L is a linear map from a weight per interior source to (L+1)^2 boundary
coefficients. Take its singular value decomposition. The right singular vectors are directions in
*source* space, ordered by how strongly the boundary answers them, and the ones past the rank
answer with exactly nothing.

So the page puts two equal-area maps of the same sphere side by side. On the left, the source
weights of one singular direction. On the right, the boundary field those weights produce. Step
through the directions and the left map stays vivid while the right map goes flat.

Delta Null theory in one picture: a change to the object, and a boundary with nothing to
say about it. Not a faint reading. Nothing.

WHY A PROJECTION INSTEAD OF A BALL

A sphere drawn as a ball hides half of itself and makes a reader turn it to be sure they have seen
everything. A blind direction has to be shown entire, or the picture invites the suspicion that the
missing signal was simply round the back. Mollweide is equal-area, and a patch's size on the page is
its solid angle, and no part of the sphere is hidden or magnified.

WHAT IS EXACT AND WHAT IS NOT

The matrix, its decomposition, and the residual norms are computed at full depth with no smoothing, the
most favourable case there is: both kernels are diagonal in degree and below one, so either can
only shrink a singular value. The field maps are drawn on a finite grid and are a picture; the
numbers printed beside them are the measurement.
"""

import argparse
import io
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

import boundary_read
import reading_rank
import sphere_field

try:
    import out_path
except ImportError:
    out_path = None

FIELD_LON = 64          # field grid columns, in longitude
FIELD_LAT = 32          # field grid rows, in colatitude
SHOWN = 12              # singular directions carried into the page


def mollweide(colatitude, longitude):
    """Equal-area projection of one direction to (x, y), each in [-1, 1].

    Newton on 2t + sin 2t = pi sin(lat). Six iterations is past double precision for every argument
    here, and the poles are handled by their closed form because the iteration stalls there.
    """
    lat = math.pi / 2.0 - colatitude
    lon = longitude
    while lon > math.pi:
        lon -= 2.0 * math.pi
    while lon < -math.pi:
        lon += 2.0 * math.pi

    if abs(abs(lat) - math.pi / 2.0) < 1e-12:
        return 0.0, 1.0 if lat > 0 else -1.0

    target = math.pi * math.sin(lat)
    theta = lat
    for _ in range(6):
        top = 2.0 * theta + math.sin(2.0 * theta) - target
        bottom = 2.0 + 2.0 * math.cos(2.0 * theta)
        if abs(bottom) < 1e-15:
            break
        theta -= top / bottom
    return lon / math.pi * math.cos(theta), math.sin(theta)


def field_grid(coefficients, top, rows=FIELD_LAT, columns=FIELD_LON):
    """The boundary field of one coefficient vector, on a colatitude by longitude grid."""
    total = [[0.0] * (2 * degree + 1) for degree in range(top + 1)]
    at = 0
    for degree in range(top + 1):
        for order in range(2 * degree + 1):
            total[degree][order] = float(coefficients[at])
            at += 1
    return sphere_field.synthesize(total, top, rows, columns)


def grid_corners(rows=FIELD_LAT, columns=FIELD_LON):
    """Projected corners of every grid cell, so the page draws quads and never guesses a shape."""
    out = []
    for r in range(rows):
        for c in range(columns):
            cell = []
            for down, across in ((r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c)):
                colatitude = math.pi * down / rows
                longitude = 2.0 * math.pi * across / columns - math.pi
                x, y = mollweide(colatitude, longitude)
                cell.append(round(x, 5))
                cell.append(round(y, 5))
            out.append(cell)
    return out


def pick(values, rank, shown=SHOWN):
    """Which singular directions to carry: the loud end, the quiet end, and the first blind ones.

    A page showing only null directions invites the reply that the whole map is flat because the
    drawing is broken. So the strongest directions ride along as the control: same code, same
    scales, and a field that is plainly not flat.
    """
    live = list(range(min(rank, len(values))))
    null = list(range(rank, len(values)))
    take = []
    for one in (live[:3] + live[-3:] if len(live) > 6 else live):
        if one not in take:
            take.append(one)
    for one in null[:shown - len(take)]:
        take.append(one)
    return take[:shown]


def build(top=8, count=256, into=None):
    places = boundary_read.golden_place(count)
    angles = boundary_read.as_angles(places)
    matrix = reading_rank.reading_matrix(top, places)

    left, values, right = numpy.linalg.svd(matrix, full_matrices=True)
    floor = values[0] * len(values) * numpy.finfo(float).eps
    rank = int((values > floor).sum())

    seats = []
    for colatitude, longitude in angles:
        x, y = mollweide(colatitude, longitude)
        seats.append([round(x, 5), round(y, 5)])

    taken = pick(values, rank)
    arrows = []
    for which in taken:
        direction = right[which]
        coefficients = matrix.dot(direction)
        answer = float(numpy.linalg.norm(coefficients))
        sigma = float(values[which]) if which < len(values) else 0.0
        grid = field_grid(coefficients, top)
        flat = [round(one, 6) for row in grid for one in row]
        arrows.append({
            "at": int(which),
            "sigma": sigma,
            "answer": answer,
            "live": bool(which < rank),
            "weights": [round(float(one), 5) for one in direction],
            "field": flat
        })

    data = {
        "degree": top,
        "count": count,
        "width": reading_rank.width(top),
        "rank": rank,
        "blind": count - rank,
        "floor": float(floor),
        "rows": FIELD_LAT,
        "columns": FIELD_LON,
        "seats": seats,
        "cells": grid_corners(),
        "arrows": arrows,
        "spectrum": [round(float(one), 6) for one in values]
    }

    with io.open(os.path.join(HERE, "blind_view_template.html"), encoding="utf-8") as handle:
        page = handle.read()
    page = page.replace("__DATA__", json.dumps(data, separators=(",", ":")))

    if into is None:
        if out_path is not None and hasattr(out_path, "beside"):
            into = out_path.beside("blind_view.html")
        else:
            into = os.path.join(os.path.dirname(os.path.dirname(HERE)),
                                "build", "view", "blind_view.html")
    os.makedirs(os.path.dirname(into), exist_ok=True)
    with io.open(into, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    print("%s (%.1f KB)" % (into, len(page) / 1024.0))
    print("  degree %d, %d coefficients, %d sources" % (top, data["width"], count))
    print("  rank %d, blind in %d directions, floor %.3e" % (rank, data["blind"], floor))
    print("  strongest singular value %.4f, weakest live %.4f"
          % (values[0], values[rank - 1] if rank else 0.0))
    quiet = [one for one in arrows if not one["live"]]
    if quiet:
        worst = max(one["answer"] for one in quiet)
        print("  %d blind direction(s) drawn, largest boundary answer %.3e" % (len(quiet), worst))
    return into


def _check():
    lines = []
    failed = 0

    # The projection has to be an involution on the equator and put the poles where they belong,
    # or every map on the page is a different sphere from the one being measured.
    x, y = mollweide(math.pi / 2.0, 0.0)
    lines.append("  the equator's centre projects to (%.3f, %.3f)" % (x, y))
    if abs(x) > 1e-9 or abs(y) > 1e-9:
        lines.append("    FAIL the centre of the map is not the centre of the sphere")
        failed += 1
    x, y = mollweide(0.0, 1.2)
    lines.append("  the north pole projects to (%.3f, %.3f)" % (x, y))
    if abs(x) > 1e-9 or abs(y - 1.0) > 1e-9:
        lines.append("    FAIL the pole is not at the top and on the axis")
        failed += 1

    # Equal area, checked instead of asserted. A Mollweide cell's area on the page has to track its
    # solid angle, so two bands of equal solid angle must project to equal page area.
    def band_area(low, high, steps=240):
        run = 0.0
        for k in range(steps):
            c0 = low + (high - low) * k / steps
            c1 = low + (high - low) * (k + 1) / steps
            x0, y0 = mollweide(c0, 0.0)
            x1, y1 = mollweide(c1, 0.0)
            run += abs(y1 - y0)
        return run

    # Equal solid angle bands: cos(colatitude) split evenly.
    first = band_area(math.acos(1.0), math.acos(0.5))
    second = band_area(math.acos(0.5), math.acos(0.0))
    ratio = first / second if second else float("inf")
    lines.append("  two bands of equal solid angle project to heights in ratio %.4f" % ratio)
    if abs(ratio - 1.0) > 0.02:
        lines.append("    FAIL the projection is not equal area along the meridian")
        failed += 1

    # The finding itself. A direction past the rank must produce a boundary answer at the floor, and
    # a direction inside it must not. Both halves, because only reporting the quiet one proves that
    # the matrix is zero.
    places = boundary_read.golden_place(64)
    matrix = reading_rank.reading_matrix(4, places)
    _, values, right = numpy.linalg.svd(matrix, full_matrices=True)
    floor = values[0] * len(values) * numpy.finfo(float).eps
    rank = int((values > floor).sum())
    loud = float(numpy.linalg.norm(matrix.dot(right[0])))
    quiet = float(numpy.linalg.norm(matrix.dot(right[-1])))
    lines.append("  degree 4 on 64 sources: rank %d of 64, blind in %d" % (rank, 64 - rank))
    lines.append("  strongest direction answers %.4f, a blind direction answers %.3e"
                 % (loud, quiet))
    if rank != reading_rank.width(4):
        lines.append("    FAIL the rank is not the coefficient count, so this is a different map")
        failed += 1
    if not quiet < 1e-12 < loud:
        lines.append("    FAIL a blind direction did not come back at the floor")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the directions a boundary cannot see")
    parser.add_argument("--degree", type=int, default=8)
    parser.add_argument("--count", type=int, default=256)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    build(args.degree, args.count)
