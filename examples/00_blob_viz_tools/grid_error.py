"""How wrong is the picture the mesh draws, measured against the field the coefficients hold.

    python tools/view/grid_error.py
    python tools/view/grid_error.py --check

THE QUESTION THIS ANSWERS

The room viewer holds a boundary field as 121 numbers: a real spherical harmonic expansion to
degree 10. To draw it, the viewer evaluates that expansion at 2,701 vertices of a 36 by 72 grid,
writes the values into a vertex buffer, and lets the rasterizer fill the space between vertices by
linear interpolation across two triangles per cell.

The 121 numbers are exact. Every pixel between the vertices is a straight line drawn through a
curve, so the picture on screen is an approximation of a field held exactly. The approximation is
worst in the middle of a cell and vanishes at every vertex, and that pattern is what prints a
5 degree quilt on a smooth surface.

This tool measures the size of that approximation, so the choice between the grid and a per-pixel
evaluation is made against a number.

WHAT IT REPORTS

Three things, because the error depends on the state and a single state's number does not generalise.

  per degree      error for a field confined to one degree, so any state's error follows from its
                  own power spectrum without rerunning this
  named fields    a flat spectrum, and the 63 deposit field the viewer actually carries at two
                  reading depths
  the gradient    the angle between the exact tangential gradient and the interpolant's, since the
                  surface is shaded and shading reads the gradient, not the value

The gradient measure matters more than the value measure. Linear interpolation has a constant
gradient inside a triangle, so the interpolated gradient is a staircase over a field whose gradient
turns smoothly, and the eye is far better at seeing a discontinuity in shading than an error in
brightness.

WHAT IT DOES NOT CLAIM

Nothing here is a frame time. The cost accounting at the end is arithmetic on sizes and counts, and
a measurement of throughput belongs in the page where the shader would run.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

import boundary_read
import sphere_field

# The reconstruction grid the room viewer builds, named the same way it is named there.
ROWS = 36                  # SURFACE_LAT, rings pole to pole
COLUMNS = 72               # SURFACE_LON, samples around each ring
TOP = 10                   # the degree ceiling the clock reads to

# Samples across one cell, in each direction. The cell corners are excluded by the half step offset,
# because the error is zero at a corner by construction and averaging that in would understate it.
INSIDE = 6

# Step for the central difference that supplies the exact gradient. Small enough that the truncation
# term is far below the error being measured, large enough to stay clear of cancellation in double
# precision: a degree 10 field has third derivatives of order a thousand, so the truncation term is
# about 1e-8, and the subtraction loses about 1e-11.
NUDGE = 1.0e-5

# Draws per degree for the per degree curve. The error for a field confined to one degree depends
# slightly on how the power is spread across orders within that degree, so several random draws are
# averaged and the spread is reported.
DRAWS = 12

GOLDEN_DEPOSITS = 63       # the deposit count the viewer carries


def synthesize_at(total, top, colatitudes, longitudes):
    """The field on an arbitrary latitude by longitude grid, separably.

    Separable because the sum splits: a Legendre part depending only on the colatitude and a
    trigonometric part depending only on the longitude. Summing the basis at every point of a fine
    grid costs the point count times 121; splitting it costs the row count times 121 plus the point
    count times 21, and returns the same numbers.

    sphere_field.synthesize does this on its own fixed grid of cell centres. This one takes the
    angles, because the samples wanted here sit at chosen offsets inside a cell.
    """
    root_two = math.sqrt(2.0)
    out = numpy.zeros((len(colatitudes), len(longitudes)))
    orders = numpy.arange(1, top + 1)
    cosines = numpy.cos(numpy.outer(numpy.asarray(longitudes), orders))
    sines = numpy.sin(numpy.outer(numpy.asarray(longitudes), orders))

    for row_index, colatitude in enumerate(colatitudes):
        x = math.cos(colatitude)
        by_cosine = numpy.zeros(top + 1)
        by_sine = numpy.zeros(top + 1)
        for order in range(top + 1):
            column = sphere_field.legendre_column(top, order, x)
            cosine_sum = 0.0
            sine_sum = 0.0
            for degree in range(order, top + 1):
                here = column[degree]
                cosine_sum += total[degree][degree + order] * here
                sine_sum += total[degree][degree - order] * here
            by_cosine[order] = cosine_sum * (1.0 if order == 0 else root_two)
            by_sine[order] = 0.0 if order == 0 else sine_sum * root_two
        out[row_index] = (by_cosine[0]
                          + cosines.dot(by_cosine[1:])
                          + sines.dot(by_sine[1:]))
    return out


def fine_angles(rows, columns, inside, shift_down=0.0, shift_around=0.0):
    """The interior sample angles of every cell, as one grid, with an optional angular shift.

    The shift exists for the central difference: the same sample points, moved by a nudge, give the
    exact derivative there without leaving the separable form.
    """
    colatitudes = [math.pi * (r + (i + 0.5) / inside) / rows + shift_down
                   for r in range(rows) for i in range(inside)]
    longitudes = [2.0 * math.pi * (c + (j + 0.5) / inside) / columns + shift_around
                  for c in range(columns) for j in range(inside)]
    return colatitudes, longitudes


def vertex_values(total, top, rows, columns):
    """The value at every vertex of the reconstruction grid, as the viewer's vertex buffer holds it."""
    colatitudes = [math.pi * r / rows for r in range(rows + 1)]
    longitudes = [2.0 * math.pi * c / columns for c in range(columns + 1)]
    return synthesize_at(total, top, colatitudes, longitudes)


def corners_of(vertices):
    """The four corner values of every cell, in the order the viewer's index buffer names them.

    Cell (r, c) has a at (r, c), b at (r, c + 1), d at (r + 1, c) and e at (r + 1, c + 1), and the
    two triangles are (a, d, b) and (b, d, e). The first covers the half of the cell where u + v is
    below one and the second covers the rest.
    """
    return (vertices[:-1, :-1], vertices[:-1, 1:], vertices[1:, :-1], vertices[1:, 1:])


def triangle_value(corners, across, down):
    """The rasterizer's value inside a cell at fractional position (across, down).

    Two planes meeting on the diagonal, as a pair of triangles must.
    """
    a, b, d, e = corners
    if across + down <= 1.0:
        return a + down * (d - a) + across * (b - a)
    return e + (1.0 - across) * (d - e) + (1.0 - down) * (b - e)


def triangle_slopes(corners, across, down):
    """The interpolant's slopes in the cell's own coordinates, constant within a triangle."""
    a, b, d, e = corners
    if across + down <= 1.0:
        return b - a, d - a
    return e - d, e - b


def flat_spectrum(top, seed):
    """A coefficient set with equal power in every degree, drawn at random within each degree.

    The realistic worst case for this measurement. Depth and conduction both suppress high degrees,
    so any field carried outward through a kernel has less high degree power than this and less
    interpolation error with it.
    """
    generator = numpy.random.default_rng(seed)
    total = []
    for degree in range(top + 1):
        row = generator.normal(size=2 * degree + 1)
        scale = math.sqrt(float(numpy.dot(row, row)))
        total.append(list(row / scale) if scale > 0 else list(row))
    return total


def single_degree(top, degree, seed):
    """Unit power in one degree and nothing anywhere else."""
    generator = numpy.random.default_rng(seed)
    total = [[0.0] * (2 * one + 1) for one in range(top + 1)]
    row = generator.normal(size=2 * degree + 1)
    scale = math.sqrt(float(numpy.dot(row, row))) or 1.0
    total[degree] = list(row / scale)
    return total


def deposit_field(top, radius_fraction, tau, count=GOLDEN_DEPOSITS):
    """The field of golden placed deposits at one depth, the way the viewer builds its own."""
    angles = boundary_read.as_angles(boundary_read.golden_place(count))
    sources = [(1.0, radius_fraction, down, around) for down, around in angles]
    return sphere_field.coefficients(sources, top, tau)


def value_error(total, top, rows=ROWS, columns=COLUMNS, inside=INSIDE):
    """Largest and root mean square error of the drawn picture, as a fraction of the field's range.

    Normalised on the peak to peak range of the field itself, because that range is what a reader
    sees on screen: an error of a tenth of the range is a tenth of the whole picture's contrast.
    """
    vertices = vertex_values(total, top, rows, columns)
    corners = corners_of(vertices)
    colatitudes, longitudes = fine_angles(rows, columns, inside)
    exact = synthesize_at(total, top, colatitudes, longitudes)
    span = float(exact.max() - exact.min())
    if span <= 0.0:
        return {"span": 0.0, "largest": 0.0, "typical": 0.0}

    worst = 0.0
    squares = 0.0
    counted = 0
    for down_step in range(inside):
        down = (down_step + 0.5) / inside
        for across_step in range(inside):
            across = (across_step + 0.5) / inside
            drawn = triangle_value(corners, across, down)
            truth = exact[down_step::inside, across_step::inside]
            gap = numpy.abs(drawn - truth)
            worst = max(worst, float(gap.max()))
            squares += float(numpy.sum(gap * gap))
            counted += gap.size
    return {"span": span,
            "largest": worst / span,
            "typical": math.sqrt(squares / counted) / span}


def gradient_error(total, top, rows=ROWS, columns=COLUMNS, inside=INSIDE, skip_rings=1):
    """Angle between the exact tangential gradient and the interpolant's, in degrees.

    The shading error. A lit surface takes its normal from the gradient of the field that displaces
    it, the interpolant's gradient is constant inside a triangle, and the exact gradient turns
    continuously, so the drawn normal is a staircase approximating a curve. Reported as an angle,
    because an angle between normals is what a shading model consumes and is free of any scale.

    The polar rings are skipped. The longitude term carries a division by the sine of the
    colatitude, and at a pole every column of the grid is the same point, so the quantity being
    measured there is a property of the grid's parameterisation and not of the drawn picture.
    """
    vertices = vertex_values(total, top, rows, columns)
    corners = corners_of(vertices)
    colatitudes, longitudes = fine_angles(rows, columns, inside)

    down_plus = synthesize_at(total, top, [one + NUDGE for one in colatitudes], longitudes)
    down_minus = synthesize_at(total, top, [one - NUDGE for one in colatitudes], longitudes)
    around_plus = synthesize_at(total, top, colatitudes, [one + NUDGE for one in longitudes])
    around_minus = synthesize_at(total, top, colatitudes, [one - NUDGE for one in longitudes])

    by_down = (down_plus - down_minus) / (2.0 * NUDGE)
    by_around = (around_plus - around_minus) / (2.0 * NUDGE)
    sine = numpy.sin(numpy.asarray(colatitudes)).reshape(-1, 1)

    step_down = math.pi / rows
    step_around = 2.0 * math.pi / columns

    angles = []
    for down_step in range(inside):
        down = (down_step + 0.5) / inside
        for across_step in range(inside):
            across = (across_step + 0.5) / inside
            slope_across, slope_down = triangle_slopes(corners, across, down)
            drawn_down = slope_down / step_down
            drawn_around = slope_across / step_around

            truth_down = by_down[down_step::inside, across_step::inside]
            truth_around = by_around[down_step::inside, across_step::inside]
            here = sine[down_step::inside]

            keep = slice(skip_rings, rows - skip_rings)
            first = numpy.stack([drawn_down[keep], drawn_around[keep] / here[keep]])
            second = numpy.stack([truth_down[keep], truth_around[keep] / here[keep]])

            dot = numpy.sum(first * second, axis=0)
            size_one = numpy.sqrt(numpy.sum(first * first, axis=0))
            size_two = numpy.sqrt(numpy.sum(second * second, axis=0))
            live = (size_one > 0) & (size_two > 0)
            cosine = numpy.clip(dot[live] / (size_one[live] * size_two[live]), -1.0, 1.0)
            angles.append(numpy.degrees(numpy.arccos(cosine)))

    every = numpy.concatenate(angles)
    return {"median": float(numpy.median(every)),
            "upper": float(numpy.percentile(every, 95)),
            "largest": float(every.max())}


def cost_note(rows=ROWS, columns=COLUMNS, top=TOP, across_screen=900):
    """Sizes and counts for the two ways of drawing the same field. Arithmetic, and no timing.

    The grid pass reads a precomputed basis table, one row of 121 floats per vertex, and produces
    one sample per vertex. A per pixel pass builds the basis by recurrence from the direction and
    reads only the coefficients, so its whole working set is 121 floats however many samples it
    produces.
    """
    width = (top + 1) * (top + 1)
    vertices = (rows + 1) * (columns + 1)
    covered = math.pi * (across_screen / 2.0) ** 2
    return {"width": width,
            "vertices": vertices,
            "table_bytes": vertices * width * 4,
            "uniform_bytes": width * 4,
            "grid_terms": vertices * width,
            "pixel_terms": int(covered * width),
            "sample_ratio": covered / vertices,
            "cell_degrees": 360.0 / columns}


def _report():
    lines = []

    facts = cost_note()
    lines.append("  the two ways of drawing one field")
    lines.append("    coefficients            %d, degree %d" % (facts["width"], TOP))
    lines.append("    grid vertices           %d, cells %.1f degrees across"
                 % (facts["vertices"], facts["cell_degrees"]))
    lines.append("    basis table read        %.2f MB per pass, for %d samples"
                 % (facts["table_bytes"] / 1048576.0, facts["vertices"]))
    lines.append("    per pixel working set   %d bytes, for any number of samples"
                 % facts["uniform_bytes"])
    lines.append("    samples at 900 px wide  %d, %.0fx the grid's"
                 % (int(math.pi * 450 * 450), facts["sample_ratio"]))
    lines.append("")

    lines.append("  error of the drawn picture, per degree, unit power in that degree alone")
    lines.append("    degree   largest   typical   gradient median   gradient 95th")
    for degree in range(1, TOP + 1):
        largest = []
        typical = []
        median = []
        upper = []
        for draw in range(DRAWS):
            total = single_degree(TOP, degree, seed=1000 * degree + draw)
            got = value_error(total, TOP)
            turn = gradient_error(total, TOP)
            largest.append(got["largest"])
            typical.append(got["typical"])
            median.append(turn["median"])
            upper.append(turn["upper"])
        lines.append("    %6d   %7.4f   %7.4f   %15.2f   %13.2f"
                     % (degree, numpy.mean(largest), numpy.mean(typical),
                        numpy.mean(median), numpy.mean(upper)))
    lines.append("")
    lines.append("    the value error climbs as the square of the degree, because linear")
    lines.append("    interpolation of a wave of length L over a step h is wrong by about half of")
    lines.append("    (pi h / L) squared, and a degree l harmonic has length 360 / l degrees")
    lines.append("")

    lines.append("  error of the drawn picture, named fields")
    lines.append("    field                          largest   typical   gradient median")
    named = [("flat spectrum to degree 10", flat_spectrum(TOP, seed=7)),
             ("63 deposits at r/R = 0.80", deposit_field(TOP, 0.80, 0.0)),
             ("63 deposits at r/R = 0.60", deposit_field(TOP, 0.60, 0.0)),
             ("63 deposits at r/R = 0.40", deposit_field(TOP, 0.40, 0.0))]
    for name, total in named:
        got = value_error(total, TOP)
        turn = gradient_error(total, TOP)
        lines.append("    %-28s   %7.4f   %7.4f   %15.2f"
                     % (name, got["largest"], got["typical"], turn["median"]))
    lines.append("")
    lines.append("    a deeper reading has less high degree power, so the same grid draws it more")
    lines.append("    accurately. The grid is not wrong by a fixed amount; it is wrong in")
    lines.append("    proportion to the fine structure the state happens to carry.")
    lines.append("")

    lines.append("  the same field on finer grids, flat spectrum to degree 10")
    lines.append("    grid          vertices   largest   typical   gradient median")
    for rows, columns in ((36, 72), (72, 144), (144, 288), (288, 576)):
        total = flat_spectrum(TOP, seed=7)
        got = value_error(total, TOP, rows, columns, inside=4)
        turn = gradient_error(total, TOP, rows, columns, inside=4)
        lines.append("    %3d by %3d   %8d   %7.4f   %7.4f   %15.2f"
                     % (rows, columns, (rows + 1) * (columns + 1),
                        got["largest"], got["typical"], turn["median"]))
    lines.append("")
    lines.append("    four times the vertices for a quarter of the error, which is the second")
    lines.append("    order convergence of a linear interpolant. Reaching the accuracy a per pixel")
    lines.append("    evaluation has for free costs the grid a table it cannot hold.")

    sys.stdout.write("\n".join(lines) + "\n")
    return 0


def _check():
    """The properties this tool must have before any number it prints is worth reading."""
    lines = []
    failed = 0

    # A field with power in degree zero alone is constant on the sphere, and a linear interpolant
    # reproduces a constant exactly. Any error reported there is an error in this tool.
    flat = [[1.0]] + [[0.0] * (2 * degree + 1) for degree in range(1, TOP + 1)]
    vertices = vertex_values(flat, TOP, 4, 8)
    spread = float(vertices.max() - vertices.min())
    lines.append("  degree zero is constant on the sphere: spread %.2e" % spread)
    if spread > 1e-12:
        lines.append("    FAIL a constant field came back varying, so the synthesis is wrong")
        failed += 1

    # The separable synthesis and a direct sum over the basis must agree. One is the fast path every
    # number here comes from and the other is the definition.
    total = flat_spectrum(TOP, seed=3)
    down, around = 0.7, 2.1
    mine = float(synthesize_at(total, TOP, [down], [around])[0][0])
    rows = sphere_field.harmonics_at(TOP, down, around)
    theirs = sum(total[degree][at] * rows[degree][at]
                 for degree in range(TOP + 1) for at in range(2 * degree + 1))
    lines.append("  separable synthesis against the direct sum: %.3e apart" % abs(mine - theirs))
    if abs(mine - theirs) > 1e-10:
        lines.append("    FAIL the fast path and the definition disagree")
        failed += 1

    # At a cell corner the interpolant is the vertex value, so the error there is zero by
    # construction. This is why the samples are taken at half step offsets, and checking it keeps
    # the reported error from being quietly diluted by exact points.
    corners = (numpy.array([[1.0]]), numpy.array([[2.0]]),
               numpy.array([[4.0]]), numpy.array([[8.0]]))
    at_corners = [float(triangle_value(corners, 0.0, 0.0)[0][0]),
                  float(triangle_value(corners, 1.0, 0.0)[0][0]),
                  float(triangle_value(corners, 0.0, 1.0)[0][0]),
                  float(triangle_value(corners, 1.0, 1.0)[0][0])]
    lines.append("  the interpolant at the four corners: %s" % at_corners)
    if at_corners != [1.0, 2.0, 4.0, 8.0]:
        lines.append("    FAIL the interpolant does not pass through its own vertices")
        failed += 1

    # The interpolant must be continuous across the diagonal where the two triangles meet, or the
    # gradient measure is reading a seam this tool invented.
    middle = (float(triangle_value(corners, 0.5, 0.5)[0][0]),
              float(triangle_value(corners, 0.5 + 1e-9, 0.5)[0][0]))
    lines.append("  across the diagonal: %.6f and %.6f" % middle)
    if abs(middle[0] - middle[1]) > 1e-6:
        lines.append("    FAIL the two triangles do not meet, so the seam is this tool's own")
        failed += 1

    # Second order convergence. Halving the step must quarter the error, and a tool that reported
    # the wrong power of the step would be measuring something other than linear interpolation.
    total = single_degree(TOP, TOP, seed=11)
    coarse = value_error(total, TOP, 36, 72, inside=4)["typical"]
    finer = value_error(total, TOP, 72, 144, inside=4)["typical"]
    ratio = coarse / finer if finer > 0 else float("inf")
    lines.append("  halving the step divides the error by %.2f, and second order says 4" % ratio)
    if not 3.0 < ratio < 5.0:
        lines.append("    FAIL the error does not fall as the square of the step")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--check" in argv:
        sys.exit(1 if _check() else 0)
    sys.exit(_report())
