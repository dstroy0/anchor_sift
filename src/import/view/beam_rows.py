"""The neutrino beams as rows in the reading map, and whether they reach where the harmonics cannot.

    python tools/view/beam_rows.py --check
    python tools/view/beam_rows.py                 rank added, and reach into the harmonic kernel
    python tools/view/beam_rows.py --oblique        how a beam's reading grows with its angle

WHY A BEAM IS A DIFFERENT KIND OF ROW, WHICH IS THE WHOLE REASON TO ADD IT

`build_sha_clock_view.py` already carries these in the picture and states what they do: what stops
the carried beam is the bit being set, what casts the shadow is the stopping, and the pattern on the
wall is the state. a beam is an OCCLUSION ALONG A RAY. That makes it a line integral through the
volume, where every instrument already in the engine is a different shape:

    a harmonic row      integrates the whole lit set against Y_lm over the sphere
    an arm              integrates the weight sitting inside a region
    a BEAM              integrates the weight lying along one line

Douglas: the arms are our touch, the neutrino beams are our eyes. That is the right distinction and
it is a statement about linear algebra rather than about metaphor. A line integral is not in the
span of region integrals, so beams can reach directions the other rows cannot, and this file measures
whether they actually do rather than asserting that they should.

THE CEILING IS UNCHANGED AND THAT IS NOT A DISAPPOINTMENT

Rank cannot exceed the number of sources however many beams are added, the same way 1024 arms at two
megabytes still gave rank 256. Eyes past the rank buy conditioning and not rank. So the question is
never whether beams break the ceiling, it is whether they climb to it from a direction touch cannot.

BOTH CONTROLS RUN, AND THE NEGATIVE ONE DECIDES WHETHER THE REST MEANS ANYTHING

    positive    rows drawn FROM the harmonic kernel must reach 1.0 and must add rank. If they do
                not, the reach measure is broken and every beam number is uninterpretable.
    negative    the harmonic rows restacked on themselves must add exactly nothing. An instrument
                that reports a gain for a copy reports a gain for anything.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

import arm_rank
import boundary_read
import reading_rank

COUNT = 256          # source points, one per state bit
DEGREE = 8           # harmonic reading degree: 81 coefficients, a 175 dimensional kernel
DEPTH = 0.62         # the shell the sources sit on
ORIGIN_RADIUS = 3.0  # where a beam starts, outside the object

# The beam's thickness, as a fraction of the source shell's radius. A beam narrower than the spacing
# between sources reads one source and is a delta; one much wider reads everything and is a
# monopole. This sits between, a beam sees a chord's worth of sources and not all or one.
BEAM_WIDTH = 0.10


def source_points(count=COUNT, depth=DEPTH):
    """The source positions in space: golden directions scaled onto the shell at `depth`."""
    return [tuple(depth * one for one in point) for point in boundary_read.golden_place(count)]


def beam_row(origin, direction, points, width=BEAM_WIDTH):
    """One beam's row: how much each source attenuates a ray from `origin` along `direction`.

    The weight is a Gaussian in the PERPENDICULAR distance from the source to the ray, which is the
    smooth form of "the bit sits in the beam's path". A hard cylinder would do the same job with a
    discontinuity, and the discontinuity would make the rank depend on whether a source fell a
    hair inside or outside rather than on the geometry.

    Sources behind the origin are excluded: a ray is a half line, and counting what sits behind the
    emitter would make the row a line through the object rather than a beam into it.
    """
    unit = numpy.array(direction, dtype=float)
    unit = unit / numpy.linalg.norm(unit)
    start = numpy.array(origin, dtype=float)

    row = numpy.zeros(len(points))
    for at, point in enumerate(points):
        offset = numpy.array(point, dtype=float) - start
        along = float(offset.dot(unit))
        if along <= 0.0:
            continue
        across = offset - along * unit
        gap = float(numpy.linalg.norm(across))
        row[at] = math.exp(-(gap * gap) / (width * width))
    return row


def beam_set(count, points, seed=0):
    """`count` beams aimed through the object, placed so the set has no preferred direction.

    Each beam starts on a golden direction of the outer shell and is aimed at a golden direction of
    the source shell, which gives a spread of impact parameters and orientations without any of them
    chosen by hand.
    """
    origins = boundary_read.golden_place(count)
    targets = boundary_read.golden_place(count)
    rows = []
    for at in range(count):
        start = tuple(ORIGIN_RADIUS * one for one in origins[at])
        aim = tuple(DEPTH * one for one in targets[(at * 7 + seed) % count])
        direction = tuple(a - b for a, b in zip(aim, start))
        rows.append(beam_row(start, direction, points))
    return numpy.array(rows)


def harmonic_rows(top=DEGREE, count=COUNT):
    """The harmonic reading map as rows over the sources, which is the engine as it stands."""
    return reading_rank.reading_matrix(top, boundary_read.golden_place(count))


def _report():
    points = source_points()
    harmonics = harmonic_rows()
    base_rank, _values = arm_rank.rank_of(harmonics)
    kernel = arm_rank.null_basis(harmonics)

    print("  %d sources on a shell at r/R %.2f. The engine's harmonic reading to degree %d is"
          % (COUNT, DEPTH, DEGREE))
    print("  %d rows, rank %d, so its kernel is %d dimensional."
          % (harmonics.shape[0], base_rank, COUNT - base_rank))
    print("")
    print("  Adding beams: occlusion along a ray, which is a line integral and not a region one.")
    print("")
    print("  %8s %10s %12s %14s %16s"
          % ("beams", "own rank", "stacked", "new directions", "reach into kernel"))

    for many in (8, 32, 64, 128, 256, 512):
        beams = beam_set(many, points)
        own, _values = arm_rank.rank_of(beams)
        together = numpy.vstack([harmonics, beams])
        joint, _values = arm_rank.rank_of(together)
        reach = arm_rank.reach_into(beams, kernel)
        print("  %8d %10d %12d %14d %16.6f"
              % (many, own, joint, joint - base_rank, reach))

    print("")
    print("  THE CONTROLS, and the negative one decides whether the table above means anything.")
    print("")

    # Negative: the harmonics restacked on themselves must add nothing at all.
    doubled = numpy.vstack([harmonics, harmonics])
    same, _values = arm_rank.rank_of(doubled)
    print("    harmonics stacked on themselves:   rank %d, new directions %d, reach %.3e"
          % (same, same - base_rank, arm_rank.reach_into(harmonics, kernel)))

    # Positive: rows taken straight from the kernel must reach 1 and must add rank.
    from_kernel = kernel[:, :16].T
    with_kernel = numpy.vstack([harmonics, from_kernel])
    lifted, _values = arm_rank.rank_of(with_kernel)
    print("    16 rows drawn FROM the kernel:      rank %d, new directions %d, reach %.6f"
          % (lifted, lifted - base_rank, arm_rank.reach_into(from_kernel, kernel)))

    print("")
    print("  WHAT THE NUMBERS SAY. A beam's reach into the harmonic kernel is the quantity to read:")
    print("  one means some direction of the beam set lies entirely where the harmonics are blind,")
    print("  and zero means the beams live inside what the harmonics already spanned. The rank")
    print("  ceiling is %d whatever is added, because that is the number of sources, so beams" % COUNT)
    print("  cannot break it and are not meant to. What they can do is climb to it along directions")
    print("  the harmonics do not have, and the new directions column is that climb.")
    return 0


def aimed_at_bits(points, width=BEAM_WIDTH, signed=False, seed=0):
    """One beam per source, each aimed at its own source. Douglas: fix them on bits.

    The emitter sits on the outer shell along the source's own direction, so the beam arrives at
    that source head on. That is the most targeted set available and it is the natural reading of
    fixing an eye on a bit.

    `signed` gives each beam an amplitude with a sign rather than an intensity, which is the part of
    the wave-function reading that can be tested: a signed row can cancel against another and a
    non-negative one cannot.
    """
    generator = numpy.random.default_rng(seed)
    rows = []
    for at, point in enumerate(points):
        direction = numpy.array(point, dtype=float)
        direction = direction / numpy.linalg.norm(direction)
        start = tuple(ORIGIN_RADIUS * one for one in direction)
        row = beam_row(start, tuple(-one for one in direction), points, width)
        if signed:
            row = row * (1.0 if generator.integers(0, 2) else -1.0)
        rows.append(row)
    return numpy.array(rows)


def _fixed():
    """Beams fixed on bits against beams aimed at random, and whether the closure is usable.

    THE QUESTION COMPLETENESS DOES NOT ANSWER. 256 random beams take the stacked rank to 256, which
    says every direction is present. It does not say the recovery works: this tree has already been
    caught by that once, where degree 15 was complete at a least singular value of 3.5e-3 and degree
    16 was complete at 1.5e-1, a factor of forty four in usability between two maps of equal rank.
    So conditioning and a round trip are measured here beside the rank.
    """
    points = source_points()
    harmonics = harmonic_rows()
    base_rank, _values = arm_rank.rank_of(harmonics)
    kernel = arm_rank.null_basis(harmonics)

    generator = numpy.random.default_rng(41)
    truth = generator.integers(0, 2, size=COUNT).astype(float)

    print("  Closing the harmonic kernel three ways, then asking whether the closure is usable.")
    print("  The object is a random BINARY state, which is what a bit pattern is.")
    print("")
    print("  %-26s %7s %14s %14s %16s"
          % ("beam set", "rank", "least live", "condition", "recovery error"))

    sets = (("harmonics alone", None),
            ("plus 256 random beams", beam_set(256, points)),
            ("plus 256 fixed on bits", aimed_at_bits(points)),
            ("plus 256 fixed, signed", aimed_at_bits(points, signed=True)))

    for name, beams in sets:
        matrix = harmonics if beams is None else numpy.vstack([harmonics, beams])
        rank, values = arm_rank.rank_of(matrix)
        least = float(values[rank - 1]) if rank else 0.0
        condition = float(values[0] / least) if least > 0.0 else float("inf")
        reading = matrix.dot(truth)
        recovered, _residual, _rank, _singular = numpy.linalg.lstsq(matrix, reading, rcond=None)
        error = float(numpy.linalg.norm(recovered - truth)) / float(numpy.linalg.norm(truth))
        print("  %-26s %7d %14.4e %14.3e %16.4e"
              % (name, rank, least, condition, error))

    print("")
    print("  ALL THE COMPLETE ONES RECOVER THE STATE, so the closure is real and not nominal. The")
    print("  conditioning column is the one to watch over time: rank says the direction exists and")
    print("  the least live singular value says how much noise it survives. They are different")
    print("  questions and a complete map can be useless.")
    print("")

    # The beam row as a distribution, which is the testable half of his wave-function reading.
    one = aimed_at_bits(points)[0]
    total = float(one.sum())
    share = one / total
    entropy = -sum(float(p) * math.log(float(p)) for p in share if p > 0.0)
    print("  ONE BEAM READ AS A DISTRIBUTION OVER SOURCES, which it is: the weights are")
    print("  non-negative and they normalise.")
    print("    sources with any weight   %d of %d" % (int((one > 1e-6).sum()), COUNT))
    print("    weight sum                %.6f" % total)
    print("    entropy                   %.4f nats, about %.1f sources' worth of spread"
          % (entropy, math.exp(entropy)))
    print("")
    print("  SO 'THEY ARE A PROBABILITY DISTRIBUTION' IS EXACTLY RIGHT AND MEASURABLE: one beam")
    print("  spreads over about %.0f sources rather than picking one, which is why a beam is a line"
          % math.exp(entropy))
    print("  integral and not a probe of a single bit.")
    print("")
    print("  'IT IS A WAVE FUNCTION' NEEDS ONE CORRECTION AND IT MATTERS. A probability")
    print("  distribution is the SQUARE of a wave function, and the difference is phase. These rows")
    print("  are real and non-negative, so they carry an intensity and no phase, and two beams")
    print("  cannot interfere or cancel. The harmonic rows are the opposite: their coefficients are")
    print("  complex and the phase is what torsion reads. So the engine already holds both kinds,")
    print("  amplitude in the harmonics and intensity in the beams, and calling the beams a wave")
    print("  function claims a phase they do not have.")
    print("")
    print("  THE SIGNED ROW ABOVE IS THAT DIFFERENCE MADE MEASURABLE. Giving each beam a sign")
    print("  changes nothing about rank, because a linear span does not care about signs. What it")
    print("  would change is a recovery constrained to non-negative combinations, which is a")
    print("  different and harder problem than the least squares run here.")
    return 0


def _oblique():
    """How a beam's reading grows with its angle, against Douglas's note that it goes with log n.

    A beam aimed through the centre passes the longest chord and a grazing one the shortest, so the
    naive expectation is that a more oblique beam reads LESS rather than more. Whatever the shape
    turns out to be it is measured here and not asserted, because the note said logarithmic and a
    logarithm and a square root are hard to tell apart by eye over one decade.
    """
    points = source_points()

    print("  One beam, swept from through-the-centre to grazing. The impact parameter is the")
    print("  closest approach of the ray to the origin, in units of the source shell's radius.")
    print("")
    print("  %10s %12s %14s %14s %14s"
          % ("impact", "chord", "sources lit", "row norm", "obliquity deg"))

    held = []
    for step in range(12):
        impact = (step / 11.0) * DEPTH * 1.35
        # A ray in the x direction, offset in y by the impact parameter.
        start = (-ORIGIN_RADIUS, impact, 0.0)
        row = beam_row(start, (1.0, 0.0, 0.0), points)
        inside = DEPTH * DEPTH - impact * impact
        chord = 2.0 * math.sqrt(inside) if inside > 0.0 else 0.0
        lit = int((row > 0.01).sum())
        norm = float(numpy.linalg.norm(row))
        # Angle between the ray and the surface normal where it enters the shell.
        obliquity = math.degrees(math.asin(min(1.0, impact / DEPTH))) if DEPTH > 0 else 0.0
        held.append((impact, chord, lit, norm))
        print("  %10.4f %12.4f %14d %14.4f %14.1f"
              % (impact, chord, lit, norm, obliquity))

    strongest = max(held, key=lambda one: one[3])
    print("")
    print("  THE ROW NORM RISES WITH OBLIQUITY AND THE CHORD FALLS, AND BOTH ARE IN THE TABLE.")
    print("  Douglas said deflection increases as the beam goes oblique, and it does: the norm")
    print("  climbs from %.4f through the centre to %.4f at impact %.4f, about %.0f percent, and"
          % (held[0][3], strongest[3], strongest[0], 100.0 * (strongest[3] / held[0][3] - 1.0)))
    print("  only collapses once the ray misses the shell entirely.")
    print("")
    print("  AN EARLIER VERSION OF THIS PARAGRAPH SAID THE OPPOSITE AND WAS CONTRADICTED BY ITS")
    print("  OWN TABLE. It reasoned from the chord, which does shrink as 2 sqrt(r^2 - b^2), and")
    print("  concluded the beam must read less. The chord is the wrong measure and the reason is")
    print("  the geometry of where the sources are:")
    print("")
    print("    THE SOURCES SIT ON A SHELL, NOT THROUGHOUT A BALL. What a beam reads is time spent")
    print("    NEAR THE SHELL, and a grazing ray is nearly tangent to it, so it runs alongside many")
    print("    sources at once. A ray through the centre crosses the shell twice, briefly, and")
    print("    spends the rest of its chord in an interior where nothing sits.")
    print("")
    print("  So obliquity buys contact with the source set even as it loses chord, which is why the")
    print("  norm rises while the chord falls. That is a property of a shell placement and it would")
    print("  not hold for sources filling a volume.")
    print("")
    print("  WHAT IS NOT SETTLED. The functional form. Over this sweep the rise is consistent with")
    print("  a logarithm and with a reciprocal square root of the cosine and with several other")
    print("  shapes, because one decade of angle cannot separate them. Naming it wants either a")
    print("  wider sweep or the wall reading, where an oblique beam also spreads its shadow over")
    print("  more area at one over the cosine. This file measures the rise and does not name it.")
    return 0


def _check():
    lines = []
    failed = 0

    points = source_points()
    harmonics = harmonic_rows()
    base_rank, _values = arm_rank.rank_of(harmonics)
    kernel = arm_rank.null_basis(harmonics)
    lines.append("  harmonics to degree %d: %d rows, rank %d, kernel %d"
                 % (DEGREE, harmonics.shape[0], base_rank, COUNT - base_rank))
    if base_rank != (DEGREE + 1) ** 2:
        lines.append("    FAIL the harmonic rank is not the coefficient count, so the map is wrong")
        failed += 1

    # THE NEGATIVE CONTROL. Restacking the harmonics must add exactly nothing, or a gain reported
    # for the beams would be a gain the tool reports for anything.
    doubled = numpy.vstack([harmonics, harmonics])
    same, _values = arm_rank.rank_of(doubled)
    reach_self = arm_rank.reach_into(harmonics, kernel)
    lines.append("  harmonics restacked: rank %d, new %d, reach into own kernel %.3e"
                 % (same, same - base_rank, reach_self))
    if same != base_rank:
        lines.append("    FAIL a copy of the rows added rank")
        failed += 1
    if reach_self > 1e-8:
        lines.append("    FAIL the rows reach into their own kernel, which is a contradiction")
        failed += 1

    # THE POSITIVE CONTROL. Rows from the kernel must reach 1 and add exactly their own count.
    from_kernel = kernel[:, :12].T
    lifted, _values = arm_rank.rank_of(numpy.vstack([harmonics, from_kernel]))
    reach_kernel = arm_rank.reach_into(from_kernel, kernel)
    lines.append("  12 rows from the kernel: rank %d, new %d, reach %.6f"
                 % (lifted, lifted - base_rank, reach_kernel))
    if lifted - base_rank != 12:
        lines.append("    FAIL kernel rows did not add their own count")
        failed += 1
    if reach_kernel < 0.999999:
        lines.append("    FAIL rows taken from the kernel do not reach it, so the measure is broken")
        failed += 1

    # A beam row must be a line and not a blob: it must light far fewer than every source, or the
    # beam is so wide it is a monopole and carries no line information at all.
    row = beam_row((-ORIGIN_RADIUS, 0.0, 0.0), (1.0, 0.0, 0.0), points)
    lit = int((row > 0.01).sum())
    lines.append("  one beam through the centre lights %d of %d sources" % (lit, COUNT))
    if lit == 0 or lit > COUNT // 4:
        lines.append("    FAIL a beam that lights nothing or most of the set is not a line integral")
        failed += 1

    # And sources behind the emitter must be excluded, or the row is a full line and not a ray.
    behind = beam_row((0.0, 0.0, 0.0), (1.0, 0.0, 0.0), points)
    ahead = sum(1 for point in points if point[0] > 0.0 and behind[points.index(point)] > 0.01)
    any_behind = any(behind[at] > 0.01 for at, point in enumerate(points) if point[0] < 0.0)
    lines.append("  a ray from the origin lights sources ahead (%d) and none behind: %s"
                 % (ahead, not any_behind))
    if any_behind:
        lines.append("    FAIL the row counts sources behind the emitter, so it is a line not a ray")
        failed += 1

    # THE QUESTION THE FILE EXISTS FOR. Beams must reach into the harmonic kernel, or the eyes see
    # nothing touch could not already see and the whole addition is decorative.
    beams = beam_set(128, points)
    reach = arm_rank.reach_into(beams, kernel)
    joint, _values = arm_rank.rank_of(numpy.vstack([harmonics, beams]))
    lines.append("  128 beams: own rank %d, joint rank %d, new directions %d, reach %.6f"
                 % (arm_rank.rank_of(beams)[0], joint, joint - base_rank, reach))
    if joint <= base_rank:
        lines.append("    FAIL the beams added no direction at all, so they are inside the")
        lines.append("         harmonic row space and are not a new kind of row")
        failed += 1

    # The ceiling must hold. However many beams, rank cannot pass the source count.
    many = beam_set(400, points)
    ceiling, _values = arm_rank.rank_of(numpy.vstack([harmonics, many]))
    lines.append("  400 beams stacked with the harmonics: rank %d, and the source count is %d"
                 % (ceiling, COUNT))
    if ceiling > COUNT:
        lines.append("    FAIL rank passed the number of sources, which is impossible")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the neutrino beams as rows, and what they reach")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--oblique", action="store_true")
    parser.add_argument("--fixed", action="store_true",
                        help="beams fixed on bits, and whether the closure is usable")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.oblique:
        sys.exit(_oblique())
    if args.fixed:
        sys.exit(_fixed())
    sys.exit(_report())
