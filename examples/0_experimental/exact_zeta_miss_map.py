#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-030
#
# Where Turing's machine misses a zero, seen from the sampler. Each cell runs twice on the device, on a coarse lattice
# and on a fine one, by the multiple evaluation, every point listed: its sign, S, Z and w = exp(i theta) F, F the main
# sum. A coarse step that holds more of the fine run's zeros than the coarse signs show hides a pair, and each such
# pair is a miss.
#
#   Usage:  python examples/0_experimental/exact_zeta_miss_map.py <binary> [first] [last] [coarse] [fine] [folder]
#           python examples/0_experimental/exact_zeta_miss_map.py <binary> e <base> <cells> <heights> <rate> [folder]
#
# With e, the same fields at heights an e-fold apart in t: cells from `base`, √e times it, e times it and on, each
# height's coarse lattice every k-th point of its fine one, k chosen to hold `rate` points a zero at every height, and
# each field read in its height's own units, the radius over its median and the turn over its median turn a step.
# Where the fields at every height fall on one another, the shift of a height by e carries them unchanged.
#
# It sits in 0_experimental and is an entry in the analytic number theory workbook, on its rail. It proves nothing;
# it reads where the misses fall.
#
# THE BALL
#
# Z = 2 Re w + R. w turns with theta, and its size |w| = |F| does not depend on theta at all:
# |F|^2 = sum over m, n of (m n)^(-1/2) cos(t ln(m / n)), the beats of the rotations n^(-it). The sampler stands at its
# last certified coarse point before the miss, the center of a ball of radius |w| there, heading along w's step from
# the point before. A miss is the fine point between its two zeros where |Z| is largest, the bottom of the dip, placed
# relative to the center: its direction from the heading, 0 to 360 degrees, and its distance in radii of the ball and
# in plain units. The ball spins, and a straight heading falls off its curve to one side: dead reckoning runs a
# steady arc through the last two coarse points, turning at the rate the heading turned over the last step, and the
# miss is placed again from that track, the spin taken out.
# The curve of the fine points through each miss is drawn over and under the plane through the center, its height
# the change in Z from the center's, in radii, up away from zero. The misses and the radii go to tab-separated files
# beside the map.
#
# The radius and the turn over a step at every coarse point are the baselines the misses' are read against.

import math
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exact_zeta_turing as tm  # noqa: E402

UNIT = float(1 << tm.SCALE_BITS)


def points_of(cell):
    """The listed points of a cell, in lane order: sign, S, Z, Re w and Im w, the last three as reals."""
    out = []
    with open(cell.path) as handle:
        for line in handle:
            if line.startswith("point"):
                sign, big_s, z, re, im = (int(v, 16) for v in line.split()[1:6])
                out.append((sign, big_s, z / UNIT, complex(re / UNIT, im / UNIT)))
    return out


def zeros_of(points):
    """Each sign change between consecutive certified points: the two lanes it lies between."""
    held = [j for j, point in enumerate(points) if point[0] != 0]
    return [(a, b) for a, b in zip(held, held[1:]) if points[a][0] != points[b][0]], held


def misses_of(coarse, fine, lift):
    """Each pair the coarse lattice hides: the coarse step it hides in, and the two fine zeros."""
    fine_zeros, _ = zeros_of(fine)
    _, held = zeros_of(coarse)
    at = 0
    out = []
    for a, b in zip(held, held[1:]):
        low, high = a * lift, b * lift
        inside = []
        while at < len(fine_zeros) and fine_zeros[at][1] <= high:
            if fine_zeros[at][0] >= low:
                inside.append(fine_zeros[at])
            at += 1
        seen = int(coarse[a][0] != coarse[b][0])
        extra = len(inside) - seen
        if extra < 2:
            continue
        gaps = sorted(range(len(inside) - 1), key=lambda k: inside[k + 1][0] - inside[k][0])
        taken = set()
        for k in gaps:
            if len(taken) // 2 >= extra // 2:
                break
            if k in taken or k + 1 in taken:
                continue
            taken |= {k, k + 1}
            out.append((a, b, inside[k], inside[k + 1]))
    return out


def bearing(z):
    return math.degrees(math.atan2(z.imag, z.real)) % 360.0


def place(nu, coarse, fine, a, b, first, second, lift):
    """A miss seen from the center at coarse point a: the dip's direction from the heading and its distance in radii
    and in units; the same from the steady arc dead reckoning predicts, which takes out the curve of the ball's spin;
    the radius, the spin, the speed, and the curve of fine points from a to b in the center's frame, its height the
    change in Z toward zero."""
    center = coarse[a][3]
    behind = coarse[a - 1][3] if a > 0 else center
    before = coarse[a - 2][3] if a > 1 else behind
    heading = center - behind
    turn = heading / abs(heading) if abs(heading) > 0 else 1
    last = behind - before
    rate = math.atan2((heading / last).imag, (heading / last).real) if abs(last) > 0 and abs(heading) > 0 else 0.0
    radius = abs(center)
    toward = -1 if coarse[a][0] > 0 else 1
    between = range(first[1], second[0] + 1)
    dip = max(between, key=lambda j: abs(fine[j][2]))
    u = (dip - a * lift) / lift
    # a steady arc through the last two fixes: the heading is the chord a - 1 to a, the tangent at a is turned half
    # the rate past it, and the arc runs at the chord's length times (rate / 2) / sin(rate / 2) a step
    if abs(rate) > 1e-12:
        arc = (rate / 2) / math.sin(rate / 2)
        track = (heading * complex(math.cos(rate / 2), math.sin(rate / 2)) * arc *
                 (complex(math.cos(rate * u), math.sin(rate * u)) - 1) / complex(0, rate))
    else:
        track = heading * u
    d = (fine[dip][3] - center) / turn
    residual = (fine[dip][3] - center - track) / turn
    # the turn across the step: what the coarse chords show, and the tip's own, summed along the fine curve
    ahead = coarse[b][3] - center
    seen = math.atan2((ahead / heading).imag, (ahead / heading).real) if abs(heading) > 0 and abs(ahead) > 0 else 0.0
    turned, prior = 0.0, None
    for j in range(a * lift, b * lift):
        tangent = fine[j + 1][3] - fine[j][3]
        if prior is not None and abs(prior) > 0 and abs(tangent) > 0:
            turned += math.atan2((tangent / prior).imag, (tangent / prior).real)
        prior = tangent
    curve = []
    for j in range(a * lift, b * lift + 1):
        q = (fine[j][3] - center) / turn / radius
        curve.append((q.real, q.imag, -toward * (fine[j][2] - coarse[a][2]) / (2 * radius)))
    return {"nu": nu, "dip_s": fine[dip][1], "u": u, "angle": bearing(d), "radii": abs(d) / radius, "units": abs(d),
            "residual_angle": bearing(residual), "residual_radii": abs(residual) / radius,
            "residual_steps": abs(residual) / abs(heading) if abs(heading) > 0 else 0.0, "radius": radius,
            "spin": rate, "seen_turn": seen, "true_turn": turned, "speed": abs(heading),
            "dip_radius": abs(fine[dip][3]), "curve": curve}


MISS_KEYS = ("nu", "dip_s", "u", "angle", "radii", "units", "residual_angle", "residual_radii", "residual_steps",
             "radius", "spin", "seen_turn", "true_turn", "speed", "dip_radius")


def write_misses(misses, table):
    """One row a miss, the fields of MISS_KEYS, to the path `table`."""
    with open(table, "w") as handle:
        handle.write("\t".join(MISS_KEYS) + "\n")
        for m in misses:
            handle.write("\t".join(str(m[k]) for k in MISS_KEYS) + "\n")
    return table


def summary(misses, radii):
    radii = sorted(radii)
    n = len(radii)
    tenth = radii[n // 10]
    median = radii[n // 2]
    taken = sorted(m["radius"] for m in misses)
    print("  %d misses over %d coarse points" % (len(misses), n))
    if not misses:
        return
    print("  the ball's radius: median %.4f over every coarse point, %.4f at the misses' centers, %.4f at their dips" %
          (median, taken[len(taken) // 2], sorted(m["dip_radius"] for m in misses)[len(misses) // 2]))
    print("  misses whose center lies in the smallest tenth of radii: %.1f%%, against 10%% were the radius no field" %
          (100.0 * sum(1 for r in taken if r <= tenth) / len(taken)))
    for key, name in (("angle", "from the heading"), ("residual_angle", "from the dead-reckoned track")):
        sectors = [0] * 8
        for m in misses:
            sectors[int(m[key] // 45) % 8] += 1
        print("  direction %s, by 45 degrees from 0: %s" % (name, sectors))
    print("  distance from the dead-reckoned track in radii: median %.3f" %
          sorted(m["residual_radii"] for m in misses)[len(misses) // 2])
    print("  distance in radii: median %.3f; in units: median %.4f" %
          (sorted(m["radii"] for m in misses)[len(misses) // 2], sorted(m["units"] for m in misses)[len(misses) // 2]))


PANEL = 420
MARGIN = 40


def shade(value, top):
    """A color from dark blue at 0 to yellow at `top`."""
    f = max(0.0, min(1.0, value / top)) if top > 0 else 0.0
    return "rgb(%d,%d,%d)" % (int(40 + 213 * f), int(20 + 211 * f), int(110 - 75 * f))


def ninety_fifth(values):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, (95 * len(ordered)) // 100)] if ordered else 1.0


def polar(out, x0, y0, misses, angle, distance, title, top_radius):
    """Heading at the top, bearings clockwise, distance out to the misses' 95th percentile, past it on the rim."""
    cx, cy, r = x0 + PANEL / 2, y0 + PANEL / 2 + 10, PANEL / 2 - MARGIN
    reach = ninety_fifth([m[distance] for m in misses]) or 1.0
    out.append('<text x="%d" y="%d" font-size="13">%s</text>' % (x0 + 10, y0 + 18, title))
    for k in (1, 2, 3, 4):
        out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="#ccc"/>' % (cx, cy, r * k / 4))
        out.append('<text x="%.1f" y="%.1f" font-size="10" fill="#666">%.3g</text>' %
                   (cx + 3, cy - r * k / 4 - 2, reach * k / 4))
    for degrees in range(0, 360, 45):
        a = math.radians(degrees)
        out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#ddd"/>' %
                   (cx, cy, cx + r * math.sin(a), cy - r * math.cos(a)))
        out.append('<text x="%.1f" y="%.1f" font-size="10" text-anchor="middle">%d</text>' %
                   (cx + (r + 14) * math.sin(a), cy - (r + 14) * math.cos(a) + 4, degrees))
    for m in misses:
        a = math.radians(m[angle])
        d = min(m[distance] / reach, 1.0) * r
        out.append('<circle cx="%.1f" cy="%.1f" r="2" fill="%s"/>' %
                   (cx + d * math.sin(a), cy - d * math.cos(a), shade(m["radius"], top_radius)))


def axes(out, x0, y0, title, xlabel, ylabel):
    left, bottom, right, top = x0 + MARGIN + 10, y0 + PANEL - MARGIN, x0 + PANEL - 10, y0 + MARGIN
    out.append('<text x="%d" y="%d" font-size="13">%s</text>' % (x0 + 10, y0 + 18, title))
    out.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#000"/>' % (left, bottom, right, bottom))
    out.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#000"/>' % (left, bottom, left, top))
    out.append('<text x="%d" y="%d" font-size="11" text-anchor="middle">%s</text>' %
               ((left + right) / 2, bottom + 28, xlabel))
    out.append('<text x="%d" y="%d" font-size="11" transform="rotate(-90 %d %d)" text-anchor="middle">%s</text>' %
               (x0 + 14, (top + bottom) / 2, x0 + 14, (top + bottom) / 2, ylabel))
    return left, bottom, right, top


def draw(misses, radii, folder):
    """The map as an SVG: three polar panels, the turn against the distance from the track, the radii, and the
    curves."""
    width, height = 3 * PANEL, 2 * PANEL
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" font-family="sans-serif">' % (width, height),
           '<rect width="100%" height="100%" fill="white"/>']
    top_radius = ninety_fifth([m["radius"] for m in misses])
    panels = (("angle", "radii", "from the center, heading at 0, in radii"),
              ("angle", "units", "the same, in units"),
              ("residual_angle", "residual_radii", "from the steady arc, the spin taken out, in radii"))
    for at, (angle, distance, title) in enumerate(panels):
        polar(out, at * PANEL, 0, misses, angle, distance, title, top_radius)
    # the turn over the last step against the distance from the steady arc
    left, bottom, right, top = axes(out, 0, PANEL, "the turn before against the distance from the arc",
                                    "turn over the last step, radians", "distance from the arc, radii")
    spin_low, spin_high = min(m["spin"] for m in misses), max(m["spin"] for m in misses)
    reach = ninety_fifth([m["residual_radii"] for m in misses]) or 1.0
    for m in misses:
        x = left + (right - left) * (m["spin"] - spin_low) / ((spin_high - spin_low) or 1.0)
        y = bottom - (bottom - top) * min(m["residual_radii"] / reach, 1.0)
        out.append('<circle cx="%.1f" cy="%.1f" r="2" fill="%s"/>' % (x, y, shade(m["radius"], top_radius)))
    # the radius: every coarse point's, the misses' centers' and their dips', each as a share of its own count
    left, bottom, right, top = axes(out, PANEL, PANEL, "the ball's radius", "|w|, out to the 99th percentile",
                                    "share in each of 40 bins")
    limit = sorted(radii)[(99 * len(radii)) // 100]
    series = ((radii, "#4a7fb5"), ([m["radius"] for m in misses], "#e08a2c"),
              ([m["dip_radius"] for m in misses], "#3a9a3a"))
    counted = []
    for values, color in series:
        bins = [0] * 40
        for v in values:
            if v < limit:
                bins[int(40 * v / limit)] += 1
        counted.append(([b / len(values) for b in bins], color))
    tallest = max(max(bins) for bins, _ in counted) or 1.0
    for bins, color in counted:
        path = []
        for k, share in enumerate(bins):
            x1 = left + (right - left) * k / 40
            x2 = left + (right - left) * (k + 1) / 40
            y = bottom - (bottom - top) * share / tallest
            path.append("%.1f,%.1f %.1f,%.1f" % (x1, y, x2, y))
        out.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="1.6"/>' % (" ".join(path), color))
    for k, (name, color) in enumerate((("every coarse point", "#4a7fb5"), ("misses' centers", "#e08a2c"),
                                       ("misses' dips", "#3a9a3a"))):
        out.append('<text x="%d" y="%d" font-size="11" fill="%s">%s</text>' % (right - 130, top + 14 + 14 * k, color, name))
    # each miss's fine curve, the plane through the center seen at a slant, height the change in Z away from zero
    x0, y0 = 2 * PANEL, PANEL
    out.append('<text x="%d" y="%d" font-size="13">each miss\'s curve over and under the center\'s plane</text>' %
               (x0 + 10, y0 + 18))
    shown = misses[:200]
    span = max([max(abs(a), abs(b), abs(c)) for m in shown for a, b, c in m["curve"]] or [1.0])
    span = min(span, ninety_fifth([max(abs(c) for _, _, c in m["curve"]) for m in shown]) * 3 or span)
    cx, cy, scale = x0 + PANEL / 2, y0 + PANEL / 2 + 20, (PANEL / 2 - MARGIN) / (span or 1.0)
    slant = (math.cos(math.radians(30)) * 0.5, math.sin(math.radians(30)) * 0.5)
    corners = [(-span, -span), (span, -span), (span, span), (-span, span)]
    plane = " ".join("%.1f,%.1f" % (cx + scale * (a + slant[0] * b), cy - scale * (slant[1] * b)) for a, b in corners)
    out.append('<polygon points="%s" fill="#eef" stroke="#99a"/>' % plane)
    for k, m in enumerate(shown):
        points = " ".join("%.1f,%.1f" % (cx + scale * (a + slant[0] * b), cy - scale * (c + slant[1] * b))
                          for a, b, c in m["curve"])
        out.append('<polyline points="%s" fill="none" stroke="hsl(%d,60%%,45%%)" stroke-width="0.7"/>' %
                   (points, (k * 47) % 360))
    out.append('<text x="%d" y="%d" font-size="11">along the heading to the right, across it into the page, up away '
               'from zero; radii</text>' % (x0 + 10, y0 + PANEL - 12))
    out.append("</svg>")
    path = os.path.join(folder, "miss_map.svg")
    with open(path, "w") as handle:
        handle.write("\n".join(out) + "\n")
    return path


def main():
    binary = sys.argv[1]
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    last = int(sys.argv[3]) if len(sys.argv) > 3 else 304
    coarse_p = int(sys.argv[4]) if len(sys.argv) > 4 else 15
    fine_p = int(sys.argv[5]) if len(sys.argv) > 5 else 18
    folder = sys.argv[6] if len(sys.argv) > 6 else tempfile.mkdtemp(prefix="miss_map_")
    sys.stdout.reconfigure(line_buffering=True)
    constants = tm.Constants()
    lift = 1 << (fine_p - coarse_p)
    misses, radii, spins, failed = [], [], [], 0
    for nu in range(first, last + 1):
        coarse_cell, _ = tm.run_cell(binary, constants, nu, coarse_p, "transform", listing=1)
        fine_cell, _ = tm.run_cell(binary, constants, nu, fine_p, "transform", listing=1)
        failed += coarse_cell.failed + fine_cell.failed
        coarse, fine = points_of(coarse_cell), points_of(fine_cell)
        radii.extend(abs(point[3]) for point in coarse)
        for j in range(2, len(coarse)):
            heading, last = coarse[j][3] - coarse[j - 1][3], coarse[j - 1][3] - coarse[j - 2][3]
            if abs(heading) > 0 and abs(last) > 0:
                spins.append(math.atan2((heading / last).imag, (heading / last).real))
        found = [place(nu, coarse, fine, a, b, x, y, lift) for a, b, x, y in misses_of(coarse, fine, lift)]
        misses.extend(found)
        print("  cell %d: 2^%d against 2^%d points, %d misses" % (nu, coarse_p, fine_p, len(found)))
    summary(misses, radii)
    if misses and spins:
        ordered = sorted(spins)
        top = ordered[(9 * len(ordered)) // 10]
        print("  the turn over a step: median %.3f radians at every coarse point, %.3f at the misses' centers; misses "
              "in the largest tenth of turns: %.1f%%" %
              (ordered[len(ordered) // 2], sorted(m["spin"] for m in misses)[len(misses) // 2],
               100.0 * sum(1 for m in misses if m["spin"] >= top) / len(misses)))
        sixth = math.pi / 3
        print("  turns past a sixth of a turn: %.1f%% of every coarse step's; at the misses, %.1f%% of the steps' as "
              "the coarse chords see them and %.1f%% of the tip's own" %
              (100.0 * sum(1 for s in spins if abs(s) > sixth) / len(spins),
               100.0 * sum(1 for m in misses if abs(m["seen_turn"]) > sixth) / len(misses),
               100.0 * sum(1 for m in misses if abs(m["true_turn"]) > sixth) / len(misses)))
        print("  the tip's own turn across a miss's step: deciles %s degrees" %
              ["%.0f" % math.degrees(v) for v in sorted(abs(m["true_turn"]) for m in misses)[len(misses) // 10::
                                                                                             max(1, len(misses) // 10)]])
        with open(os.path.join(folder, "spins.tsv"), "w") as handle:
            handle.write("\n".join("%.6f" % s for s in spins) + "\n")
    table = write_misses(misses, os.path.join(folder, "misses.tsv"))
    with open(os.path.join(folder, "radii.tsv"), "w") as handle:
        handle.write("\n".join("%.6f" % r for r in radii) + "\n")
    print("  the misses: %s" % table)
    print("  the map: %s; %d host checks failed" % (draw(misses, radii, folder), failed))
    return 0 if failed == 0 else 1


def median(values):
    ordered = sorted(values)
    return ordered[len(ordered) // 2] if ordered else 0.0


def fold_cells(binary, constants, nu, count, rate):
    """Cells nu to nu + count - 1, each on a fine lattice, its coarse lattice every k-th fine point with k chosen for
    `rate` points a zero: the misses, every coarse point's radius and turn, the rate held, and the zeros."""
    misses, radii, turns, rates, zeros, failed = [], [], [], [], 0, 0
    for at in range(nu, nu + count):
        z = tm.rises(at)
        fine_p = math.ceil(math.log2(8 * rate * z))
        k = max(2, round((1 << fine_p) / (rate * z)))
        cell, _ = tm.run_cell(binary, constants, at, fine_p, "transform", listing=1)
        failed += cell.failed
        fine = points_of(cell)
        os.remove(cell.path)
        coarse = fine[::k]
        zeros += len(zeros_of(fine)[0])
        rates.append((1 << fine_p) / (k * z))
        radii.extend(abs(point[3]) for point in coarse)
        for j in range(2, len(coarse)):
            heading, last = coarse[j][3] - coarse[j - 1][3], coarse[j - 1][3] - coarse[j - 2][3]
            if abs(heading) > 0 and abs(last) > 0:
                turns.append(abs(math.atan2((heading / last).imag, (heading / last).real)))
        misses.extend(place(at, coarse, fine, a, b, x, y, k) for a, b, x, y in misses_of(coarse, fine, k))
    # the inertia the carrier frame predicts, the mean over t of |F|^2 with its cross terms gone: the sum of 1/n over
    # n <= nu, averaged over the cells
    harmonic = sum(sum(1.0 / n for n in range(1, at + 1)) for at in range(nu, nu + count)) / count
    return {"misses": misses, "radii": radii, "turns": turns, "rate": sum(rates) / len(rates), "zeros": zeros,
            "failed": failed, "nu": nu, "t": 2 * math.pi * nu * nu, "harmonic": harmonic}


def fold_row(fold):
    """The fields of one height in its own units."""
    misses, radii, turns = fold["misses"], fold["radii"], fold["turns"]
    r_mid, t_mid = median(radii), median(turns)
    r_tenth = sorted(radii)[len(radii) // 10]
    t_tenth = sorted(turns)[(9 * len(turns)) // 10]
    pull = sum(complex(math.cos(math.radians(m["residual_angle"])), math.sin(math.radians(m["residual_angle"])))
               for m in misses) / max(1, len(misses))
    # the scatter about the steady arc, in the walker's own frame: it holds its shape from height to height while the
    # walk reads the field, whatever the heading does
    scatter = sorted(m["residual_steps"] for m in misses)
    # under us: within one step of the arc. A miss past it is read as a curl of the field at a scale the walk has not
    # reached, and its own radius and turn say where it stands. The far misses' distance over the core's ninetieth
    # percentile is the separation: it rises as the core tightens under the walk and the far misses stand apart as
    # single dots
    near = [m for m in misses if m["residual_steps"] <= 1.0]
    far = [m for m in misses if m["residual_steps"] > 1.0]
    # the pickle: each miss's distance from the arc split into along-track, parallel to the heading and behind when
    # below zero, and cross-track, across it. The width is the cross-track RMS. Locking a carrier narrows the width
    # first, and the along-track contracts after, the scatter closing under the walk
    along = [m["residual_steps"] * math.cos(math.radians(m["residual_angle"])) for m in misses]
    cross = [m["residual_steps"] * math.sin(math.radians(m["residual_angle"])) for m in misses]
    cross_rms = math.sqrt(sum(c * c for c in cross) / max(1, len(cross)))
    along_rms = math.sqrt(sum(a * a for a in along) / max(1, len(along)))
    return [
        ("t at the first cell", "%.4g" % fold["t"]),
        ("points a zero, coarse", "%.3f" % fold["rate"]),
        ("misses a thousand zeros", "%.3f" % (1000.0 * 2 * len(misses) / max(1, fold["zeros"]))),
        ("median radius, every point", "%.4f" % r_mid),
        ("inertia, the mean of |w|^2", "%.4f" % (sum(r * r for r in radii) / max(1, len(radii)))),
        ("its law, the sum of 1/n to nu", "%.4f" % fold["harmonic"]),
        ("misses' radius over the median", "%.3f" % (median(m["radius"] for m in misses) / r_mid)),
        ("misses in the smallest tenth of radii", "%.1f%%" % (100.0 * sum(1 for m in misses if m["radius"] <= r_tenth) /
                                                             max(1, len(misses)))),
        ("median turn a step, every point", "%.3f" % t_mid),
        ("misses' turn over the median", "%.3f" % (median(abs(m["spin"]) for m in misses) / t_mid)),
        ("misses in the largest tenth of turns", "%.1f%%" % (100.0 * sum(1 for m in misses if abs(m["spin"]) >= t_tenth) /
                                                            max(1, len(misses)))),
        ("bearing from the heading, median", "%.1f" % median(m["angle"] for m in misses)),
        ("distance from the arc, steps, median", "%.3f" % median(m["residual_steps"] for m in misses)),
        ("distance from the arc, steps, tenth", "%.3f" % scatter[len(scatter) // 10] if scatter else "-"),
        ("distance from the arc, steps, ninetieth", "%.3f" % scatter[(9 * len(scatter)) // 10] if scatter else "-"),
        ("pull from the arc: length, bearing", "%.3f at %.0f" % (abs(pull), math.degrees(math.atan2(pull.imag, pull.real)) % 360)),
        ("bearing's spread from the arc, 1 - pull", "%.3f" % (1.0 - abs(pull))),
        ("the pickle's width, cross-track RMS steps", "%.3f" % cross_rms),
        ("the pickle's aspect, cross over along", "%.3f" % (cross_rms / along_rms) if along_rms else "-"),
        ("under us, within a step of the arc", "%.3f%%" % (100.0 * len(near) / max(1, len(misses)))),
        ("past a step: radius, turn over the median", "%.3f, %.3f" % (median(m["radius"] for m in far) / r_mid,
                                                                     median(abs(m["spin"]) for m in far) / t_mid)
         if far else "-"),
        ("past a step: dip radius over the median", "%.3f" % (median(m["dip_radius"] for m in far) / r_mid) if far else "-"),
        ("past a step over the core's ninetieth", "%.2f" % (median(m["residual_steps"] for m in far) /
                                                           (sorted(m["residual_steps"] for m in near)[(9 * len(near)) // 10]
                                                            or 1.0)) if far and near else "-"),
        ("misses", "%d" % len(misses)),
    ]


def draw_folds(folds, folder):
    """The heights side by side: the pull from the arc in steps, the radius over its median, and the turn over its
    median, every point dashed and the misses solid, one color a height."""
    colors = ("#4a7fb5", "#e08a2c", "#3a9a3a", "#a03ab0", "#b03a3a")
    width, height = 3 * PANEL, PANEL
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" font-family="sans-serif">' % (width, height),
           '<rect width="100%" height="100%" fill="white"/>']
    cx, cy, r = PANEL / 2, PANEL / 2 + 10, PANEL / 2 - MARGIN
    reach = ninety_fifth([m["residual_steps"] for f in folds for m in f["misses"]]) or 1.0
    out.append('<text x="10" y="18" font-size="13">from the steady arc, heading at 0, in steps; out to the 95th '
               'percentile</text>')
    for k in (1, 2, 3, 4):
        out.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="none" stroke="#ccc"/>' % (cx, cy, r * k / 4))
        out.append('<text x="%.1f" y="%.1f" font-size="10" fill="#666">%.3g</text>' % (cx + 3, cy - r * k / 4 - 2, reach * k / 4))
    for degrees in range(0, 360, 45):
        a = math.radians(degrees)
        out.append('<text x="%.1f" y="%.1f" font-size="10" text-anchor="middle">%d</text>' %
                   (cx + (r + 14) * math.sin(a), cy - (r + 14) * math.cos(a) + 4, degrees))
    for f, color in zip(folds, colors):
        for m in f["misses"]:
            a = math.radians(m["residual_angle"])
            d = min(m["residual_steps"] / reach, 1.0) * r
            out.append('<circle cx="%.1f" cy="%.1f" r="1.6" fill="%s" fill-opacity="0.6"/>' %
                       (cx + d * math.sin(a), cy - d * math.cos(a), color))
    for at, (key, title) in enumerate((("radius", "the radius over its median"), ("turn", "the turn a step over its median"))):
        left, bottom, right, top = axes(out, (at + 1) * PANEL, 0, title, "in the height's own units, to 4", "share")
        curves = []
        for f, color in zip(folds, colors):
            every = f["radii"] if key == "radius" else f["turns"]
            mid = median(every) or 1.0
            ours = [m["radius"] for m in f["misses"]] if key == "radius" else [abs(m["spin"]) for m in f["misses"]]
            for values, dash in ((every, "4,3"), (ours, "")):
                bins = [0] * 40
                for v in values:
                    x = v / mid
                    if x < 4:
                        bins[int(10 * x)] += 1
                curves.append(([b / max(1, len(values)) for b in bins], color, dash))
        tallest = max(max(b) for b, _, _ in curves) or 1.0
        for bins, color, dash in curves:
            path = " ".join("%.1f,%.1f" % (left + (right - left) * (k + 0.5) / 40, bottom - (bottom - top) * share / tallest)
                            for k, share in enumerate(bins))
            out.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="1.4"%s/>' %
                       (path, color, ' stroke-dasharray="%s"' % dash if dash else ""))
    for k, (f, color) in enumerate(zip(folds, colors)):
        out.append('<text x="%d" y="%d" font-size="11" fill="%s">t from %.3g</text>' % (width - 120, 40 + 14 * k, color, f["t"]))
    out.append("</svg>")
    path = os.path.join(folder, "folds.svg")
    with open(path, "w") as handle:
        handle.write("\n".join(out) + "\n")
    return path


def main_folds(binary, base, count, folds, rate, folder):
    """Cells from `base`, then √e times it, e times it and on, `folds` heights an e-fold apart in t, `count` cells
    each, every height's coarse lattice at `rate` points a zero."""
    constants = tm.Constants()
    found = []
    for j in range(folds):
        nu = round(base * math.exp(j / 2))
        fold = fold_cells(binary, constants, nu, count, rate)
        found.append(fold)
        write_misses(fold["misses"], os.path.join(folder, "misses_%d.tsv" % nu))
        print("  cells %d to %d, t from %.4g: %d misses, %d host checks failed" %
              (nu, nu + count - 1, fold["t"], len(fold["misses"]), fold["failed"]))
    rows = [fold_row(f) for f in found]
    print("  %-40s %s" % ("", "".join("%18s" % ("e^%d" % j) for j in range(folds))))
    for at in range(len(rows[0])):
        print("  %-40s %s" % (rows[0][at][0], "".join("%18s" % row[at][1] for row in rows)))
    failed = sum(f["failed"] for f in found)
    print("  the heights: %s; %d host checks failed" % (draw_folds(found, folder), failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[2] == "e":
        sys.stdout.reconfigure(line_buffering=True)
        sys.exit(main_folds(sys.argv[1], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), float(sys.argv[6]),
                            sys.argv[7] if len(sys.argv) > 7 else tempfile.mkdtemp(prefix="miss_folds_")))
    sys.exit(main())
