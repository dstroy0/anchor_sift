"""The directions a boundary reading cannot see, drawn beside the field they produce.

    python tools/view/build_blind_view.py
    python tools/view/build_blind_view.py --degree 8 --count 256
    python tools/view/build_blind_view.py --check

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

    # EQUAL AREA, CHECKED INSTEAD OF ASSERTED, AND THE FIRST VERSION OF THIS CHECK TESTED THE WRONG
    # QUANTITY AND FAILED A CORRECT PROJECTION. It measured HEIGHT along the meridian at longitude
    # zero and demanded that two bands of equal solid angle come out in ratio 1.0. That is the test
    # for a CYLINDRICAL equal-area projection, where width is constant. Mollweide is an ellipse: it
    # preserves area by trading height against width, a polar band is horizontally compressed and
    # must stretch vertically. It duly read 1.4754 and was reported as a failure for two sessions.
    #
    # The property the page actually relies on is that a patch's size on the page IS its solid
    # angle, everywhere on the disc rather than along one line. So the sphere is cut into cells of
    # EQUAL SOLID ANGLE, by sampling uniformly in cos(colatitude) and in longitude, and every cell's
    # projected area must come out the same. Area, not height, and the whole disc, not a meridian.
    #
    # THE TOLERANCE IS REPLACED BY A CONVERGENCE TEST. Summing quadrilaterals is a discretisation,
    # a fixed bound on the spread would be a number picked by hand. Instead the spread is
    # measured at two resolutions and must SHRINK when the grid is refined: a real projection error
    # does not go away with resolution, and a discretisation error does.
    # AND THE DENOMINATOR IS EACH ROW'S TRUE AREA, NOT THE MEAN OF THE ROWS. Dividing by the mean
    # is what made this measurement unreadable on the first attempt: the mean is itself dragged by
    # the polar rows and by the straight-edge under-count, so it drifts with resolution and the
    # quotient has no limit to converge to. Every row holds solid angle 4 pi / steps and the whole
    # disc is pi, so each row's true projected area is exactly pi / steps, which is fixed.
    def row_areas(steps):
        out = []
        for row in range(steps):
            # Uniform in cos(colatitude), so every row holds the same solid angle by construction.
            hi = math.acos(1.0 - 2.0 * row / steps)
            lo = math.acos(1.0 - 2.0 * (row + 1) / steps)
            run = 0.0
            for column in range(steps):
                left = -math.pi + 2.0 * math.pi * column / steps
                right = -math.pi + 2.0 * math.pi * (column + 1) / steps
                corners = [mollweide(hi, left), mollweide(hi, right),
                           mollweide(lo, right), mollweide(lo, left)]
                cell = 0.0
                for at in range(4):
                    x0, y0 = corners[at]
                    x1, y1 = corners[(at + 1) % 4]
                    cell += x0 * y1 - x1 * y0
                run += abs(cell) / 2.0
            out.append(run / (math.pi / steps))
        return out

    coarse = row_areas(12)
    fine = row_areas(24)

    # THE INTERIOR IS THE EQUAL-AREA CLAIM and it must converge to 1 at every latitude away from
    # the coordinate singularity. Refining the grid has to move it closer, or the unevenness is the
    # projection rather than the discretisation.
    coarse_worst = max(abs(one - 1.0) for one in coarse[1:-1])
    fine_worst = max(abs(one - 1.0) for one in fine[1:-1])
    lines.append("  interior rows against their true area pi/steps: worst error %.2e at 12, "
                 "%.2e at 24" % (coarse_worst, fine_worst))
    if not fine_worst < coarse_worst:
        lines.append("    FAIL refining the grid did not reduce the interior error, so the map is")
        lines.append("         not equal area and the page's patch sizes do not mean solid angle")
        failed += 1

    # THE POLAR ROW IS A PREDICTED CONSTANT AND NOT AN EXCUSE. At the pole the cell degenerates: its
    # top edge collapses to a point and its sides are ellipse arcs that are locally parabolic, a
    # straight-chord triangle inscribes a parabolic segment and Archimedes gives the ratio as
    # exactly 3/4. Measured 0.7272, 0.7363, 0.7416, 0.7448 and 0.7468 at 12 through 192 steps,
    # rising monotonically, and Richardson on the last pair with its observed error ratio of 0.62
    # per halving extrapolates to 0.7500. So the deficit is quantified rather than tolerated, and
    # the test is that it APPROACHES three quarters from below.
    polar_coarse, polar_fine = coarse[0], fine[0]
    lines.append("  the degenerate polar row against Archimedes' 3/4: %.4f at 12, %.4f at 24"
                 % (polar_coarse, polar_fine))
    if not polar_coarse < polar_fine < 0.75:
        lines.append("    FAIL the polar cell does not rise toward three quarters, so the chord")
        lines.append("         triangle story is wrong and the deficit is unexplained")
        failed += 1

    # AND THE TOTAL MUST APPROACH THE WHOLE ELLIPSE, which catches a map that is evenly wrong. A
    # per-row convergence test alone would pass a projection that shrank every cell by one factor.
    coarse_total = sum(coarse) * math.pi / 12.0
    fine_total = sum(fine) * math.pi / 24.0
    lines.append("  total projected area %.4f at 12, %.4f at 24, the unit ellipse is %.4f"
                 % (coarse_total, fine_total, math.pi))
    if abs(fine_total - math.pi) > abs(coarse_total - math.pi):
        lines.append("    FAIL the summed area moves AWAY from the unit ellipse as the grid is")
        lines.append("         refined, so the cells are not tiling the disc")
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
