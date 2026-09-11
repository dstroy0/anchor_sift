#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Turn a square dotmap into SVG outlines, by tracing the boundary between set and unset cells.
#
#   python maint/texbuild/dotmap_svg.py glyph.txt                 a 64x64 grid of . and #
#   python maint/texbuild/dotmap_svg.py glyph.hex --side 64       4096 bits as hex
#   python maint/texbuild/dotmap_svg.py glyph.txt --smooth 2      corners cut twice
#   python maint/texbuild/dotmap_svg.py glyph.txt --out g.svg     written rather than printed
#
# WHY TRACE AND NOT DRAW A SQUARE PER CELL
#
# A rectangle per set cell gives the same picture and is unusable. Adjacent rectangles share an edge
# and a renderer seams along it, so the glyph shows hairline cracks at some zoom levels and not at
# others. It also makes the file enormous and gives nothing to smooth, since there is no outline to
# cut a corner from.
#
# Tracing produces the actual boundary: every edge with a set cell on one side and an unset cell on
# the other, chained into closed loops. Two set cells touching contribute no edge between them, so
# the outline is one continuous path around the shape and there is nothing to seam.
#
# HOLES COME FREE, AND THE FILL RULE IS WHY
#
# The counter inside an o is its own closed loop, traced in the opposite direction from the outer
# one. With fill-rule evenodd a renderer fills between the loops and leaves the counter empty
# without being told which loop is which. Nothing here has to know what a hole is.
#
# WHY THE FACETS ARE THE POINT
#
# The outline is exact at cell boundaries, so a 64 grid gives hard facets where a font gives smooth
# curves. That reads as a cut or brushed letter rather than a typeset one. --smooth cuts corners by
# Chaikin's rule, which shortens every segment toward its neighbours and softens the facets without
# inventing a curve the dotmap did not have. Two passes is usually enough; four looks like a font
# again and loses the reason to do this.
#
# WHAT IT IS FOR
#
# A composed glyph of this orthography is a letter plus a combining mark, and where that mark sits is
# decided by a shaping engine at render time. That placement is exactly what a PDF text extraction
# destroys, and papers.py:29-31 records a page printing the mark over its letter while the extracted
# text puts it in front. An outline traced from a rendered composition has the placement baked in and
# cannot lose it again.

import io
import os
import sys

# What counts as a set cell when reading a text grid. Everything else is unset, so a grid may be
# drawn with dots, spaces, zeroes or anything else for the background.
SET_MARKS = "#*1Xx@"

# The SVG viewBox is the grid itself, so one cell is one unit and a consumer scales the whole thing
# by setting width and height. Coordinates stay small integers before any smoothing.
CELL = 1


def from_text(text):
    """A grid of rows, each a list of booleans, read from a drawing of the glyph."""
    rows = [line.rstrip("\n") for line in text.split("\n") if line.strip()]
    if not rows:
        raise SystemExit("dotmap_svg: the file holds no rows")
    width = max(len(one) for one in rows)
    return [[(at < len(row)) and (row[at] in SET_MARKS) for at in range(width)] for row in rows]


def from_hex(text, side):
    """A grid of `side` by `side`, read from hex digits, most significant bit first.

    4096 bits is 1024 hex digits and a side of 64. The count is checked rather than assumed: a
    dotmap one digit short would otherwise silently lose its last four cells.
    """
    digits = "".join(one for one in text.split() if one)
    digits = digits[2:] if digits[:2].lower() == "0x" else digits
    wanted = (side * side) // 4
    if len(digits) != wanted:
        raise SystemExit("dotmap_svg: %d hex digits for a side of %d, wanted %d"
                         % (len(digits), side, wanted))
    bits = bin(int(digits, 16))[2:].zfill(side * side)
    return [[bits[(row * side) + column] == "1" for column in range(side)] for row in range(side)]


def boundary_edges(grid):
    """Every unit edge with a set cell on one side and nothing on the other.

    Each edge is returned as (start, end) with the set cell kept on the left of the direction of
    travel. That makes an outer loop run one way and a hole run the other, which is what lets the
    fill rule separate them later without anything here knowing which is which.
    """
    height = len(grid)
    width = max(len(row) for row in grid)

    def filled(row, column):
        if (row < 0) or (row >= height) or (column < 0) or (column >= width):
            return False
        return (column < len(grid[row])) and grid[row][column]

    edges = {}
    for row in range(height):
        for column in range(width):
            if not filled(row, column):
                continue
            left, top = column * CELL, row * CELL
            right, bottom = left + CELL, top + CELL
            # Each neighbour that is empty contributes the edge between them, wound so the set cell
            # stays on the left.
            if not filled(row - 1, column):
                edges[(left, top)] = (right, top)
            if not filled(row, column + 1):
                edges[(right, top)] = (right, bottom)
            if not filled(row + 1, column):
                edges[(right, bottom)] = (left, bottom)
            if not filled(row, column - 1):
                edges[(left, bottom)] = (left, top)
    return edges


def loops_from(edges):
    """The edges chained into closed rings, each a list of points.

    An edge dictionary maps a start point to an end point, so following it from any unused start
    walks a ring and returns to where it began. Every edge belongs to exactly one ring because a
    boundary point has one outgoing edge.
    """
    remaining = dict(edges)
    rings = []
    while remaining:
        start = next(iter(remaining))
        ring = [start]
        point = start
        while True:
            step = remaining.pop(point, None)
            if (step is None) or (step == start):
                break
            ring.append(step)
            point = step
        if len(ring) > 2:
            rings.append(ring)
    return rings


def straightened(ring):
    """One ring with every run of collinear points reduced to its two ends.

    A traced ring carries a point per cell along a straight run, so a flat side of forty cells
    arrives as forty points describing one line. Dropping the middles changes no geometry at all and
    is what keeps the path readable and the file small.
    """
    if len(ring) < 3:
        return ring
    kept = []
    count = len(ring)
    for at in range(count):
        before = ring[(at - 1) % count]
        here = ring[at]
        after = ring[(at + 1) % count]
        turning = ((here[0] - before[0]) * (after[1] - here[1])) != \
                  ((here[1] - before[1]) * (after[0] - here[0]))
        if turning:
            kept.append(here)
    return kept or ring


def chaikin(ring, passes):
    """The ring with its corners cut, `passes` times, by Chaikin's rule.

    Each pass replaces every corner with two points a quarter and three quarters along its edges, so
    the ring keeps its shape and loses its sharpest angles. It invents no curve the dotmap did not
    imply, which is the reason to prefer it here over fitting splines.
    """
    for _ in range(max(0, passes)):
        count = len(ring)
        if count < 3:
            return ring
        cut = []
        for at in range(count):
            here = ring[at]
            after = ring[(at + 1) % count]
            cut.append((here[0] + 0.25 * (after[0] - here[0]),
                        here[1] + 0.25 * (after[1] - here[1])))
            cut.append((here[0] + 0.75 * (after[0] - here[0]),
                        here[1] + 0.75 * (after[1] - here[1])))
        ring = cut
    return ring


def number(value):
    """A coordinate written as short as it can be without changing it."""
    if float(value) == int(value):
        return str(int(value))
    return ("%.3f" % value).rstrip("0").rstrip(".")


def path_of(rings):
    """Every ring as one SVG path data string, each closed."""
    pieces = []
    for ring in rings:
        head = ring[0]
        moves = ["M%s %s" % (number(head[0]), number(head[1]))]
        for point in ring[1:]:
            moves.append("L%s %s" % (number(point[0]), number(point[1])))
        moves.append("Z")
        pieces.append(" ".join(moves))
    return " ".join(pieces)


def svg_of(grid, passes, label):
    """The whole document, sized to the grid so a consumer scales it by width and height."""
    height = len(grid)
    width = max(len(row) for row in grid)
    rings = [chaikin(straightened(one), passes) for one in loops_from(boundary_edges(grid))]

    held = []
    held.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" '
                'width="%d" height="%d" role="img">' % (width * CELL, height * CELL,
                                                        width * CELL, height * CELL))
    if label:
        # Named so a reader using a screen reader gets the character rather than silence. An outline
        # carries no text and this is the only place the codepoint survives.
        held.append("  <title>%s</title>" % label)
    held.append('  <path fill-rule="evenodd" d="%s"/>' % path_of(rings))
    held.append("</svg>")
    return "\n".join(held) + "\n", len(rings)


def flag(argv, name, fallback):
    """One named argument's value, or the fallback where it was not given."""
    if name not in argv:
        return fallback
    at = argv.index(name)
    if (at + 1) >= len(argv):
        raise SystemExit("dotmap_svg: %s wants a value" % name)
    return argv[at + 1]


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    argv = sys.argv[1:]
    if not argv:
        out.write(__doc__ or "")
        out.write("  usage: python maint/texbuild/dotmap_svg.py <dotmap> [--side N] "
                  "[--smooth N] [--label C] [--out FILE]\n")
        out.flush()
        return 2

    side = int(flag(argv, "--side", 64))
    passes = int(flag(argv, "--smooth", 0))
    label = flag(argv, "--label", "")
    target = flag(argv, "--out", "")
    taken = {"--side", "--smooth", "--label", "--out",
             str(side), str(passes), label, target}
    sources = [one for one in argv if (one not in taken) and not one.startswith("-")]
    if not sources:
        raise SystemExit("dotmap_svg: name a dotmap file")

    source = sources[0]
    with io.open(source, encoding="utf-8") as handle:
        text = handle.read()

    grid = from_hex(text, side) if source.lower().endswith(".hex") else from_text(text)
    document, rings = svg_of(grid, passes, label)

    if target:
        with io.open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(document)
        out.write("  %s  %d ring(s), %d bytes\n" % (target, rings, len(document)))
    else:
        out.write(document)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
