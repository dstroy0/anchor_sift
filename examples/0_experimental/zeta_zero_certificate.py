#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-025
#
# A counted zero of the Riemann zeta function, turned into a certificate a second reader checks in one
# pass without repeating the search, the shape Proth's theorem gives a prime.
#
#   Usage:  python examples/0_experimental/zeta_zero_certificate.py [low] [high]
#
# This reads no corpus. It sits in 0_experimental and is an entry in the analytic number theory
# workbook, on its rail: it claims nothing about the Riemann hypothesis. It certifies the zeros it
# reaches inside the boxes it is asked for and stops there.
#
# THE TWO COSTS
#
# exact_zeta_zeros.py counts a zero by walking a path around a box and summing the eighth turns of
# zeta, splitting an edge wherever a chord or a step verdict is not yet positive. That walk is a
# search: it decides for itself how deep to read each point and how far to subdivide. The search is
# the expensive half. Checking its answer is the cheap half, and the two are separated here.
#
# A certificate is the settled path and, for each of its points, the places and the N at which the
# routes of exact_zeta_zeros.py agreed. It records where to read and how deep, never what was found.
# The checker re-reads each point once at that depth, re-derives the eighth of a turn from the exact
# value, and confirms three things: the two routes agree, the turns close to a whole number of
# circles, and every chord and step verdict is positive. No point is read twice and nothing is
# subdivided. The count falls out of the turns.
#
# WHY THE CHECK IS A PROOF
#
# This is the division Proth's theorem draws for a prime N = k 2^n + 1: a witness a is hard to find
# and proves nothing until a^((N-1)/2) == -1 settles it in one exponentiation. The eighth turns are
# the eighth roots of unity and the turn from point to point is subtraction in that group, the same
# group the twiddle table of a number theoretic transform lives in (theory/theory/
# twiddle_constants_article.tex, its sections on Proth's theorem and on the group law). The sum of the
# turns is the winding, and on a box symmetric about Re(s) = 1/2 a winding of one circle holds a zero
# on the line, because the symmetry s -> 1 - conj(s) brings an off-line zero's mirror into the same
# box (zeta_zero_symmetry.py, EXP-x-015).
#
# THE GROUP LAW IS NOT ENOUGH, AND WHAT FINISHES IT
#
# The winding alone is the twiddle table's trap in another dress. A root of half the required order
# satisfies every relation among the table entries and only the order test, two exponentiations,
# catches it. Here a path too coarse to resolve the turning can sum to a whole circle by luck while no
# chord is proved: the eighth turns add to eight with a half turn at a corner whose direction the two
# end points cannot see. The chord and step verdicts are the order test. A chord holds the angle
# across an edge under a sixth of a turn and a step holds the motion under the size, and together they
# lift the sum from the group Z/8 to the integers. Prove the steps, then trust the count. The reverse
# is a fast wrong answer.
#
# Positive control: the unit tiles from t = 14 to t = 26 meeting edge to edge, three certified to hold
# one zero each against Odlyzko's published table and the rest certified to hold none. Drawn null: the
# four corners alone, whose winding is already one circle and whose chords the checker refuses.

import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
import manifest  # noqa: E402,F401
from exact_zeta_zeros import (NOT, PUBLISHED, Steering, below, box_corners, common,  # noqa: E402
                              compare, decimal, halves, minus, refined, routes, units)


def octant(re, im):
    """The eighth of a turn zeta sits in, from the signs of its real part, its imaginary part, and
    which of the two is larger. Re-derived here from the exact value, trusting no recorded number."""
    sign_re, sign_im = compare(re, 0), compare(im, 0)
    sign_size = compare(abs(re), abs(im))
    quadrant = (1 - sign_im) + (1 - sign_re * sign_im) // 2
    return 2 * quadrant + ((1 - sign_size) // 2 + quadrant) % 2


def certify(box):
    """Run the search of exact_zeta_zeros.py once over `box`, then read back the settled path and the
    depth each of its points was decided at. Returns the count and the certificate, a list of
    (point, places, N) in path order with its midpoints restored."""
    steering = Steering()
    count = steering.count([box])[0]
    path = refined(steering.last_paths[0])
    certificate = [(point, steering.values[point][2], steering.values[point][3]) for point in path]
    return count, certificate, steering.asked


def check(certificate):
    """One pass over the certificate, no search. Re-read each point once at its recorded depth,
    re-derive its octant, and tally the three verdicts. Returns the count and a record holding whether
    the two routes agree everywhere, the sum of the turns, and how many chords and steps are positive."""
    reads = []
    agree_all = 1
    for point, places, n_sum in certificate:
        re_one, im_one, d_re, d_im, re_two, im_two, _, _ = routes(point[0], point[1], places, n_sum)
        agree_all *= NOT(re_one - re_two) * NOT(im_one - im_two)
        reads.append((point, places, re_one, im_one, d_re, d_im))
    total = chords_ok = steps_ok = 0
    edges = len(reads)
    for index in range(edges):
        point, places, re, im, d_re, d_im = reads[index]
        far, far_places, re_c, im_c, d_re_c, d_im_c = reads[(index + 1) % edges]
        total += (octant(re_c, im_c) - octant(re, im) + 4) % 8 - 4
        size = min(re * re + im * im, re_c * re_c + im_c * im_c)
        chords_ok += int(compare(size, (re_c - re) ** 2 + (im_c - im) ** 2) > 0 and far_places == places)
        run_re, run_im, run_places = common(minus(far[0], point[0]), minus(far[1], point[1]))
        span = run_re * run_re + run_im * run_im
        unit = 10 ** (2 * run_places)
        step_near = compare((re * re + im * im) * unit, (d_re * d_re + d_im * d_im) * span)
        step_far = compare((re_c * re_c + im_c * im_c) * unit, (d_re_c * d_re_c + d_im_c * d_im_c) * span)
        steps_ok += int(step_near > 0 and step_far > 0)
    record = {"agree": bool(agree_all), "turns": total, "edges": edges,
              "chords": chords_ok, "steps": steps_ok}
    verified = bool(agree_all) and total % 8 == 0 and chords_ok == edges and steps_ok == edges
    return total // 8 if total % 8 == 0 else None, verified, record


def fixed_depth(box, refinements, places, n_sum):
    """A path around `box` refined a fixed number of times, every point tagged with the same depth. No
    search: the path the four corners grow into by halving each edge `refinements` times."""
    path = box_corners(box)
    for _ in range(refinements):
        path = refined(path)
    return [(point, places, n_sum) for point in path]


def bracket(published):
    """A unit-tall box symmetric about Re(s) = 1/2 that holds the published ordinate."""
    value = units(published)
    return ((0, 0), (1, 0), (value[0] // 10 ** value[1], 0), (value[0] // 10 ** value[1] + 1, 0))


def report_line(out, low, high):
    """Section one: tile the strip from t = low to t = high with unit boxes edge to edge, certify every
    tile, and hold the count against the published ordinates in the same span."""
    out.write("  the line: every unit tile from t = %d to t = %d searched once and checked in one pass\n" % (low, high))
    out.write("  %-20s %-6s %-7s %-9s %-8s %s\n" % ("tile", "count", "turns", "searched", "checked", "verdict"))
    all_pass = True
    total = 0
    pending = [((0, 0), (1, 0), (floor, 0), (floor + 1, 0)) for floor in range(low, high)]
    while pending:
        box = pending.pop(0)
        count, certificate, searched = certify(box)
        if count > 1:
            pending = halves(box) + pending
            continue
        checked, verified, record = check(certificate)
        single = verified and checked == count
        all_pass = all_pass and single
        total += count
        verdict = ("one zero on the line", "no zero")[NOT(count)] if single else "FAIL"
        out.write("  [%s, %s]   %-6d %-7d %-9d %-8d %s\n"
                  % (decimal(box[2], 3), decimal(box[3], 3), count, record["turns"], searched,
                     len(certificate), verdict))
    published = sum(below((low, 0), units(p)) * below(units(p), (high, 0)) for p in PUBLISHED)
    covered = below((high, 0), units(PUBLISHED[-1]))
    matches = (not covered) or total == published
    out.write("\n  %d zeros certified in [%d, %d]; the published table holds %s there.\n"
              % (total, low, high, ("%d" % published) if covered else "too few ordinates to say"))
    out.write("  each tile is symmetric about Re(s) = 1/2, where a winding of one circle holds a zero on the\n")
    out.write("  line (zeta_zero_symmetry.py) and a winding of none holds no zero. the tiles meet edge to\n")
    out.write("  edge and every one is checked; no part of the span is read by trust.\n\n")
    return all_pass and matches


def report_rejection(out):
    """Section two: the checker refuses an understated depth, and the certificate carries nothing to fiddle."""
    out.write("  rejection: a certificate that understates its depth cannot pass\n")
    box = bracket(PUBLISHED[2])
    _, certificate, _ = certify(box)
    checked, verified, record = check(certificate)
    shallow = [(point, 1, 1) for point, _, _ in certificate]
    checked_shallow, verified_shallow, record_shallow = check(shallow)
    out.write("  box around %s at its searched depth: routes agree %s, verified %s (count %s)\n"
              % (decimal(units(PUBLISHED[2]), 3), record["agree"], verified, checked))
    out.write("  the same points forced to 1 place and N = 1: routes agree %s, verified %s\n"
              % (record_shallow["agree"], verified_shallow))
    out.write("\n  a check that cannot fail is not a check. this one fails on a depth that cannot sign the\n")
    out.write("  value, caught by the two routes drawing apart. the certificate records only where to read\n")
    out.write("  and how deep, never the value found. a fiddled reading has nothing to fiddle: the checker\n")
    out.write("  re-derives every octant from zeta itself.\n\n")
    return (not verified_shallow) and verified


def report_floor(out):
    """Section three: the winding closes on a path too coarse to prove, and the chords catch it."""
    out.write("  floor: the winding alone closes to one circle before any chord is proved\n")
    out.write("  %-24s %-7s %-10s %-10s %s\n" % ("path around [14, 15]", "turns", "chords+", "steps+", "verdict"))
    box = ((0, 0), (1, 0), units("14"), units("15"))
    for name, refinements in (("4 corners", 0), ("8 points", 1), ("16 points", 2)):
        _, _, record = check(fixed_depth(box, refinements, 6, 4))
        out.write("  %-24s %-7d %-10s %-10s %s\n"
                  % (name, record["turns"], "%d/%d" % (record["chords"], record["edges"]),
                     "%d/%d" % (record["steps"], record["edges"]), "winding only, unproved"))
    _, certificate, _ = certify(box)
    checked, verified, record = check(certificate)
    out.write("  %-24s %-7d %-10s %-10s %s\n"
              % ("searched and settled", record["turns"], "%d/%d" % (record["chords"], record["edges"]),
                 "%d/%d" % (record["steps"], record["edges"]),
                 "certificate" if verified else "FAIL"))
    out.write("\n  the four corners already wind one circle, the group law satisfied, and no chord holds: a\n")
    out.write("  half turn at a corner hides its direction from the two ends. only the chord and step\n")
    out.write("  verdicts, the order test of the twiddle table, separate a proved count from a lucky one.\n")
    _, four_corner_verified, _ = check(fixed_depth(box, 0, 6, 4))
    return (not four_corner_verified) and verified and checked == 1


def main():
    out = sys.stdout
    low = int((sys.argv[1:] + ["14"])[0])
    high = int((sys.argv[2:] + ["26"])[0])
    out.write("  the zero certificate: a counted zero checked in one pass, the shape Proth gives a prime\n")
    out.write("  it claims nothing about the Riemann hypothesis; it certifies the zeros it reaches\n\n")

    line = report_line(out, low, high)
    rejection = report_rejection(out)
    floor = report_floor(out)
    out.flush()
    return 0 if (line and rejection and floor) else 1


if __name__ == "__main__":
    raise SystemExit(main())
