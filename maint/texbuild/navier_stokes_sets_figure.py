#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Draw Fefferman's Navier-Stokes sets, and the horizon the engine measured on them, as one PDF figure
# that comes out of the engine: the left panel is the shape of the four alternatives read off his set
# definitions, the right panel is the mode count of the Taylor coefficients the torus example computes,
# taken from that example at run time and never typed in.
#
#   Usage:  python maint/texbuild/navier_stokes_sets_figure.py [--out FILE]
#
# The PDF is written by hand: a page, one content stream of line, rectangle, curve and text operators,
# and two base-14 fonts that every reader carries. Nothing is embedded and no drawing library is
# imported. The tree's arithmetic rule holds here as well as in the example: integers, and the
# coordinates a page needs. The output lands under build/theory/figures/, never beside a source, and the
# millennium book's chapter on their sets includes it behind a guard that typesets a sentence when the
# file is absent.
#
# WHAT THE LEFT PANEL SHOWS, AND WHAT IT DOES NOT CLAIM
#
# The base is the plane of pairs (datum, force) with the datum along the front edge and the force
# running back. Over every point stands a stalk, the solution set for that pair. The alternatives (A)
# and (B) speak only of the front edge, force zero: no stalk there is empty. The alternatives (C) and
# (D) speak of the whole plane: some stalk somewhere is empty. The front edge lies inside the plane,
# an empty stalk on the edge would refute (A) or (B) and establish (C) or (D), and an empty stalk off the
# edge establishes (C) or (D) and says nothing about the edge. That containment is the whole of what the
# panel draws. It draws every stalk except one as a question, because that is what they are. The one
# drawn solid is the Arnold-Beltrami-Childress datum on the torus, whose stalk is not empty by a
# classical closed form the example verifies exactly. One instance, and it is labeled as one.
#
# The dots along the front edge are the countable island of exactly nameable data, the ring the example
# computes in; the edge is uncountable and the dots are not to scale, since no drawing of a countable
# set inside an uncountable one is.
#
# WHAT THE RIGHT PANEL SHOWS
#
# For a generic datum on the torus the example computes the Taylor coefficients u_0 .. u_4 of the
# solution at t = 0, exactly. Each bar is the number of Fourier modes a coefficient occupies; the darker
# bar inside it is how many of those sit outside the box |k|_inf <= 1, and the darkest how many sit
# outside |k|_inf <= 2. The numbers come from running the example when this script runs. They are the
# measured horizon: any fixed box misses some order, and the count it misses is drawn, not bounded.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "examples", "0_experimental"))

import exact_navier_stokes_on_torus as torus  # noqa: E402

DEFAULT_OUT = os.path.join(ROOT, "build", "theory", "figures", "navier_stokes_sets.pdf")
GENERATOR = "maint/texbuild/navier_stokes_sets_figure.py"
SOURCE = "examples/0_experimental/exact_navier_stokes_on_torus.py"

PAGE_WIDTH = 430
PAGE_HEIGHT = 250
KAPPA = 0.5523  # the cubic that approximates a quarter circle


def pdf_string(text):
    """A text string as a PDF literal: ASCII only, the three escapes the syntax needs."""
    escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    return "(" + escaped.encode("ascii", "replace").decode("ascii") + ")"


def coordinate(value):
    """A coordinate written short. Integers stay integers; the rest keep two places."""
    if float(value) == int(value):
        return str(int(value))
    return "%.2f" % value


class Canvas:
    """One page's content stream, collected as operators."""

    def __init__(self):
        self.ops = []

    def gray(self, level):
        self.ops.append("%s G %s g" % (coordinate(level), coordinate(level)))

    def width(self, points):
        self.ops.append("%s w" % coordinate(points))

    def dash(self, on, off):
        self.ops.append("[%s %s] 0 d" % (coordinate(on), coordinate(off)))

    def solid(self):
        self.ops.append("[] 0 d")

    def line(self, x_from, y_from, x_to, y_to):
        self.ops.append(
            "%s %s m %s %s l S"
            % (
                coordinate(x_from),
                coordinate(y_from),
                coordinate(x_to),
                coordinate(y_to),
            )
        )

    def polygon(self, points, fill=None, stroke=True):
        moves = ["%s %s m" % (coordinate(points[0][0]), coordinate(points[0][1]))]
        for x_at, y_at in points[1:]:
            moves.append("%s %s l" % (coordinate(x_at), coordinate(y_at)))
        moves.append("h")
        if fill is not None:
            self.ops.append("%s g" % coordinate(fill))
        self.ops.append(
            " ".join(moves)
            + (
                " B"
                if (fill is not None and stroke)
                else (" f" if fill is not None else " S")
            )
        )
        if fill is not None:
            self.ops.append("0 g")

    def rect(self, x_at, y_at, wide, high, fill=None, stroke=True):
        if fill is not None:
            self.ops.append("%s g" % coordinate(fill))
        self.ops.append(
            "%s %s %s %s re %s"
            % (
                coordinate(x_at),
                coordinate(y_at),
                coordinate(wide),
                coordinate(high),
                (
                    "B"
                    if (fill is not None and stroke)
                    else ("f" if fill is not None else "S")
                ),
            )
        )
        if fill is not None:
            self.ops.append("0 g")

    def circle(self, center_x, center_y, radius, fill=None):
        reach = KAPPA * radius
        arcs = [
            (
                center_x + radius,
                center_y + reach,
                center_x + reach,
                center_y + radius,
                center_x,
                center_y + radius,
            ),
            (
                center_x - reach,
                center_y + radius,
                center_x - radius,
                center_y + reach,
                center_x - radius,
                center_y,
            ),
            (
                center_x - radius,
                center_y - reach,
                center_x - reach,
                center_y - radius,
                center_x,
                center_y - radius,
            ),
            (
                center_x + reach,
                center_y - radius,
                center_x + radius,
                center_y - reach,
                center_x + radius,
                center_y,
            ),
        ]
        moves = ["%s %s m" % (coordinate(center_x + radius), coordinate(center_y))]
        for arc in arcs:
            moves.append(" ".join(coordinate(one) for one in arc) + " c")
        if fill is not None:
            self.ops.append("%s g" % coordinate(fill))
        self.ops.append(" ".join(moves) + (" B" if fill is not None else " S"))
        if fill is not None:
            self.ops.append("0 g")

    def text(self, x_at, y_at, string, size=7, font="F1", rotate=False):
        matrix = (
            "0 1 -1 0 %s %s Tm" % (coordinate(x_at), coordinate(y_at))
            if rotate
            else "1 0 0 1 %s %s Tm" % (coordinate(x_at), coordinate(y_at))
        )
        self.ops.append(
            "BT /%s %s Tf %s %s Tj ET"
            % (font, coordinate(size), matrix, pdf_string(string))
        )

    def stream(self):
        return "\n".join(self.ops) + "\n"


def build_pdf(canvas, title, producer):
    """A one-page PDF as bytes: catalog, pages, page, content, two fonts, info, xref, trailer."""
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R "
        "/Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> >>"
        % (PAGE_WIDTH, PAGE_HEIGHT),
        None,  # the content stream, filled below
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique >>",
        "<< /Title %s /Producer %s >>" % (pdf_string(title), pdf_string(producer)),
    ]
    content = canvas.stream().encode("ascii")
    objects[3] = b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream"

    out = io.BytesIO()
    out.write(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(out.tell())
        out.write(b"%d 0 obj\n" % number)
        out.write(body if isinstance(body, bytes) else body.encode("ascii"))
        out.write(b"\nendobj\n")
    xref_at = out.tell()
    out.write(b"xref\n0 %d\n" % (len(objects) + 1))
    out.write(b"0000000000 65535 f \n")
    for offset in offsets:
        out.write(b"%010d 00000 n \n" % offset)
    out.write(
        b"trailer\n<< /Size %d /Root 1 0 R /Info 7 0 R >>\nstartxref\n%d\n%%%%EOF\n"
        % (len(objects) + 1, xref_at)
    )
    return out.getvalue()


def measure_horizon(order):
    """The horizon numbers from the example itself: modes held, outside two boxes, and the reach."""
    datum = torus.generic_field()
    velocities, _ = torus.taylor_velocity(datum, torus.VISCOSITY, order)
    return [
        (
            len(torus.modes_of(velocities[step])),
            torus.modes_outside(velocities[step], 1),
            torus.modes_outside(velocities[step], 2),
            torus.mode_reach(velocities[step]),
        )
        for step in range(order + 1)
    ]


def draw_sets(canvas):
    """The left panel: the plane the breakdown alternatives speak of, and the edge the others do."""
    left, right = 12, 205
    canvas.text(
        left,
        PAGE_HEIGHT - 14,
        "their sets: the plane (C), (D) speak of holds the edge (A), (B) speak of",
        7,
    )

    # the base plane, drawn oblique so a stalk can rise from it
    front_y, back_y, skew = 70, 150, 22
    front_left, front_right = 30, 185
    plane = [
        (front_left, front_y),
        (front_right, front_y),
        (front_right + skew, back_y),
        (front_left + skew, back_y),
    ]
    canvas.width(0.6)
    canvas.polygon(plane, fill=0.96)
    canvas.width(1.4)
    canvas.line(front_left, front_y, front_right, front_y)  # the front edge: force zero
    canvas.width(0.6)

    # the countable island: dots along the front edge, not to scale
    for at in range(front_left + 6, front_right - 4, 9):
        canvas.circle(at, front_y, 0.9, fill=0)
    canvas.text(
        front_left + 2,
        front_y - 9,
        "front edge: force f = 0, datum in D_8; dots: R_div, the countable island (not to scale)",
        5,
    )
    canvas.text(front_right + skew + 3, back_y - 4, "F_89", 6, "F2")
    canvas.text(front_right + skew + 3, back_y - 40, "force", 6, "F2")
    canvas.text(front_right + skew + 3, back_y - 48, "runs back", 6, "F2")

    # stalks: the solution set over a point. One solid, the rest questions.
    abc_x = 60
    canvas.width(1.2)
    canvas.line(abc_x, front_y, abc_x, front_y + 48)
    canvas.circle(abc_x, front_y + 48, 1.6, fill=0)
    canvas.text(
        abc_x - 24, front_y + 54, "ABC datum: S_1011(u0, 0) not empty, one instance", 5
    )
    canvas.width(0.6)
    canvas.dash(1.5, 1.5)
    for stalk_x in (110, 150):
        canvas.line(stalk_x, front_y, stalk_x, front_y + 34)
        canvas.text(stalk_x - 2, front_y + 37, "?", 7)
    canvas.text(96, front_y + 46, "(A), (B): no stalk on this edge empty?", 5)
    # an interior point of the plane, off the edge: the force is nonzero there
    interior_x, interior_y = 148, 118
    canvas.line(interior_x, interior_y, interior_x, interior_y + 30)
    canvas.text(interior_x - 2, interior_y + 33, "?", 7)
    canvas.solid()
    canvas.circle(interior_x, interior_y, 1.4)
    canvas.text(
        interior_x - 62,
        interior_y + 42,
        "(C), (D): some stalk anywhere in the plane empty?",
        5,
    )
    canvas.text(
        left,
        38,
        "a stalk over (u0, f) is the solution set S(u0, f). The edge lies in the plane:",
        5.5,
    )
    canvas.text(
        left,
        30,
        "an empty stalk on the edge refutes (A) or (B) and gives (C) or (D);",
        5.5,
    )
    canvas.text(
        left,
        22,
        "an empty stalk off the edge gives (C) or (D) and says nothing about the edge.",
        5.5,
    )
    canvas.text(
        left,
        14,
        "(C) is not the negation of (A). Nothing here says which stalks are empty.",
        5.5,
    )
    canvas.width(0.4)
    canvas.line(right + 8, 12, right + 8, PAGE_HEIGHT - 10)


def draw_horizon(canvas, rows):
    """The right panel: the mode count per Taylor order, from the run, with the two boxes inside it."""
    left = 228
    canvas.text(
        left,
        PAGE_HEIGHT - 14,
        "the horizon: modes held by u_m for a generic datum, from the run",
        7,
    )
    base_y = 60
    tallest = max(row[0] for row in rows) or 1
    scale = 140 / tallest
    bar_wide = 22
    gap = 14
    canvas.width(0.5)
    canvas.line(left, base_y, left + len(rows) * (bar_wide + gap), base_y)
    for step, (held, outside_one, outside_two, reach) in enumerate(rows):
        x_at = left + 6 + step * (bar_wide + gap)
        canvas.rect(x_at, base_y, bar_wide, held * scale, fill=0.85)
        if outside_one:
            canvas.rect(x_at + 3, base_y, bar_wide - 6, outside_one * scale, fill=0.6)
        if outside_two:
            canvas.rect(x_at + 6, base_y, bar_wide - 12, outside_two * scale, fill=0.3)
        canvas.text(x_at + 2, base_y + held * scale + 3, str(held), 6)
        canvas.text(x_at + 6, base_y - 9, "u_%d" % step, 6)
        canvas.text(x_at + 4, base_y - 18, "%d" % reach, 6, "F2")
    canvas.text(
        left, base_y - 30, "largest |k|_1 per order (climbs by one):", 5.5, "F2"
    )
    legend_y = PAGE_HEIGHT - 30
    for offset, (level, label) in enumerate(
        (
            (0.85, "modes held"),
            (0.6, "outside |k|_inf <= 1"),
            (0.3, "outside |k|_inf <= 2"),
        )
    ):
        canvas.rect(left, legend_y - offset * 10, 8, 6, fill=level)
        canvas.text(left + 11, legend_y - offset * 10 + 1, label, 5.5)
    canvas.text(
        left,
        22,
        "any fixed box misses some order; the count it misses is measured,",
        5.5,
    )
    canvas.text(
        left,
        14,
        "not bounded. Coefficients exact, orders 0..%d, viscosity %s at %d place(s)."
        % (len(rows) - 1, torus.VISCOSITY[0], torus.VISCOSITY[1]),
        5.5,
    )


def flag(argv, name, fallback):
    if name not in argv:
        return fallback
    at = argv.index(name)
    if at + 1 >= len(argv):
        raise SystemExit("navier_stokes_sets_figure: %s wants a value" % name)
    return argv[at + 1]


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    target = flag(sys.argv[1:], "--out", DEFAULT_OUT)
    order = 4
    rows = measure_horizon(order)

    canvas = Canvas()
    draw_sets(canvas)
    draw_horizon(canvas, rows)
    canvas.text(
        12,
        4,
        "generated by %s from %s; it claims nothing about (A), (B), (C) or (D)"
        % (GENERATOR, SOURCE),
        4.5,
        "F2",
    )
    document = build_pdf(
        canvas,
        "Their sets, and the measured horizon",
        "anchor_sift %s, drawing %s" % (GENERATOR, SOURCE),
    )

    os.makedirs(os.path.dirname(target), exist_ok=True)
    with io.open(target, "wb") as handle:
        handle.write(document)

    out.write("  horizon from the run, orders 0..%d:\n" % order)
    out.write(
        "    order:                %s\n"
        % "  ".join("%4d" % step for step in range(order + 1))
    )
    out.write(
        "    modes held:           %s\n" % "  ".join("%4d" % row[0] for row in rows)
    )
    out.write(
        "    outside |k|_inf <= 1: %s\n" % "  ".join("%4d" % row[1] for row in rows)
    )
    out.write(
        "    outside |k|_inf <= 2: %s\n" % "  ".join("%4d" % row[2] for row in rows)
    )
    out.write(
        "    largest |k|_1:        %s\n" % "  ".join("%4d" % row[3] for row in rows)
    )
    out.write("  %s  %d bytes\n" % (target, len(document)))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
