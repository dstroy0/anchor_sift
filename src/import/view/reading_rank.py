"""How many independent numbers a boundary reading actually carries, and how many it cannot.

    python tools/view/reading_rank.py --check

A tool and not a library: it measures one thing and prints it.

THE DEFECT THIS EXISTS FOR

The octant alphabet separated sixty-four rounds from sixty-four rounds, every signature distinct,
and that was reported as coherence. It is nearly free. Eight real numbers will separate sixty-four
arbitrary states whether or not the eight numbers mean anything, so distinctness at that sample size
is not evidence and the report should never have implied it was.

What settles it is not a harder sample. It is a rank. The map from lit points to boundary
coefficients is linear -- that linearity is the whole reason a field of many sources sums instead of
needing a solve -- and it therefore has a rank, a null space, and a dimension count that no amount
of sampling and no amount of precision moves. A reading to degree L carries at most (L+1)^2 real
numbers about its source, and every direction of the source space beyond that is invisible by
arithmetic.

WHAT IS MEASURED

    orthonormality   the basis graded against exact quadrature, leaving any rank reported below a
                     property of the map instead of a basis that had already lost digits.
    rank             singular values of the reading matrix, at several reading degrees.
    nullity          the dimension of what the reading cannot see. This bounds every claim of the
                     form "the beams map the whole object".
    the octant map   the same measurement for the eight-letter alphabet, the coarsest reading in
                     the tree and the one whose limit is easiest to overstate.

WHAT IT DOES NOT MEASURE

Whether the numbers a reading does carry are the interesting ones. Rank is a ceiling on what can be
recovered and says nothing about what is worth recovering. A rank-81 reading blind to every bit of
consequence is arithmetically identical to one that is not.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy

import boundary_read
import sphere_field

# The placement every SHA reading in this tree uses, and the count it uses it at.
COUNT = 256

# The reading degrees graded. Eight is what the viewers read at, and fifteen earns its place as the
# first degree whose coefficient count reaches the source count.
DEGREES = (4, 8, 12, 15, 16)

# A singular value below this fraction of the largest counts as zero. Chosen far above the double
# precision floor and far below the smallest nonzero value any run here produces, so the rank does
# not depend on where in that gap the line is drawn.
RANK_FLOOR = 1e-10


def width(top):
    """Real coefficients in a reading to this degree: one per order per degree, so (top+1)^2."""
    return (top + 1) * (top + 1)


def flat_harmonics(top, colatitude, longitude):
    """The harmonic basis at one direction, flattened to one vector of length width(top)."""
    rows = sphere_field.harmonics_at(top, colatitude, longitude)
    out = []
    for row in rows:
        out.extend(row)
    return out


def reading_matrix(top, places):
    """The map from a weight per lit point to boundary coefficients, at full depth and no smoothing.

    Full depth and no smoothing is the most favourable case there is: the depth kernel (r/R)^l and
    the conduction kernel exp(-l(l+1)tau) are both diagonal in degree and both below one, so either
    of them can only shrink a singular value. A rank measured here is therefore an upper bound on
    the rank at any depth or any conduction time, and the nullity is a lower bound.
    """
    angles = boundary_read.as_angles(places)
    out = numpy.zeros((width(top), len(places)))
    for at, (colatitude, longitude) in enumerate(angles):
        out[:, at] = flat_harmonics(top, colatitude, longitude)
    return out


def octant_matrix(places):
    """The eight-letter alphabet as a linear map: row j counts the weight sitting in octant j."""
    out = numpy.zeros((8, len(places)))
    for at, point in enumerate(places):
        signs = tuple(1 if value >= 0.0 else -1 for value in point)
        out[boundary_read.OCTANTS.index(signs), at] = 1.0
    return out


def gram_residual(top):
    """How far the basis is from orthonormal under exact quadrature, as a worst-cell deviation.

    Gauss-Legendre in the cosine of the colatitude and the trapezoid in the longitude, both at
    orders that integrate a product of two degree-`top` harmonics exactly. A basis that has lost
    digits reports it here, before any rank below is believed.
    """
    lat = 2 * (top + 1)
    lon = 4 * top + 6
    nodes, weights = sphere_field.gauss_legendre(lat)
    gram = numpy.zeros((width(top), width(top)))
    share = 2.0 * math.pi / lon
    for node, weight in zip(nodes, weights):
        colatitude = math.acos(max(-1.0, min(1.0, node)))
        for step in range(lon):
            vector = numpy.array(flat_harmonics(top, colatitude, step * share))
            gram += (weight * share) * numpy.outer(vector, vector)
    return float(numpy.abs(gram - numpy.eye(width(top))).max())


def depth_rank(matrix, floor):
    """Recoverable directions and conditioning, with absent separated from badly conditioned.

    Two different failures share the word "unrecoverable" and they should not. A direction whose
    singular value sits below the measured floor of the instrument is ABSENT: the reading carries no
    trace of it and no arithmetic downstream can invent one. A direction above the floor with a small
    singular value is PRESENT AND BADLY CONDITIONED: it is there, and recovering it costs precision
    in proportion. The first is a wall and the second is a bill.

    Reported separately because a sweep that adds them together says a reading gets worse smoothly
    with depth, when what actually happens is that degrees switch off one at a time.
    """
    values = numpy.linalg.svd(matrix, compute_uv=False)
    live = values[values > floor]
    return {
        "present": int(live.size),
        "absent": int(values.size - live.size),
        "largest": float(values[0]) if values.size else 0.0,
        "least_live": float(live[-1]) if live.size else 0.0,
        "condition": float(values[0] / live[-1]) if live.size else float("inf"),
    }


def depth_kernel(top, radius_fraction, tau=0.0):
    """The per-coefficient gain of depth and conduction, laid out to match a flattened reading.

    Both kernels are diagonal in the degree, so this is a scaling of the rows of the reading matrix
    and never a change to its structure. Everything depth does to a reading is here.
    """
    out = numpy.zeros(width(top))
    climb = 1.0
    for degree in range(top + 1):
        soften = math.exp(-degree * (degree + 1.0) * tau)
        for order in range(2 * degree + 1):
            out[degree * degree + order] = climb * soften
        climb *= radius_fraction
    return out


def sweep_depth(places, degrees, fractions, floor, tau=0.0):
    """Rank and conditioning at each reading degree, for a source at each depth.

    THE QUESTION THIS ANSWERS
    -------------------------
    An optimizer that maximizes recovered directions per unit cost picks the smallest degree whose
    coefficient count reaches the source count. On a 256-point source that is degree fifteen, and
    degree fifteen is the worst-conditioned complete degree there is -- its least singular value is
    three decades under the degrees on either side, and one degree of headroom recovers a factor of forty-four.
    So the objective is not monotone, and an engine that optimizes the count lands on the one degree
    it should avoid and reports success.

    The open question was whether the degree a reading should actually use tracks the source's depth
    or pins at that same fifteen whatever the depth. This sweep answers it by measurement.
    """
    rows = []
    for fraction in fractions:
        for top in degrees:
            matrix = reading_matrix(top, places)
            gain = depth_kernel(top, fraction, tau)
            got = depth_rank(gain[:, None] * matrix, floor)
            got["fraction"] = fraction
            got["degree"] = top
            got["coefficients"] = width(top)
            rows.append(got)
    return rows


def rank_of(matrix):
    """Rank, nullity and the singular value spread, from the singular values themselves.

    Reported with the smallest nonzero value and not only the count, because a matrix of full rank
    whose least singular value is a millionth of its largest is full rank and not invertible in any
    useful sense, and the count alone hides that.
    """
    values = numpy.linalg.svd(matrix, compute_uv=False)
    big = float(values[0])
    kept = int((values > big * RANK_FLOOR).sum())
    least = float(values[kept - 1]) if kept else 0.0
    return kept, matrix.shape[1] - kept, big, least


def _check():
    lines = []
    failed = 0

    def say(text):
        lines.append(text)

    places = boundary_read.golden_place(COUNT)
    say("  %d lit points on the golden placement" % COUNT)
    say("")

    say("  the basis, graded against exact quadrature")
    for top in (4, 8, 15):
        off = gram_residual(top)
        say("    degree %-2d  worst cell off orthonormal by %.3e" % (top, off))
        if off > 1e-11:
            say("    FAIL the basis is not orthonormal, so no rank below can be trusted")
            failed += 1
    say("    precision is not the limit at any degree this reading needs")
    say("")

    say("  the reading map, degree by degree")
    say("    degree  coefficients  rank  blind  largest    least kept")
    for top in DEGREES:
        kept, blind, big, least = rank_of(reading_matrix(top, places))
        say("    %6d  %12d  %4d  %5d  %9.4f  %.3e" % (top, width(top), kept, blind, big, least))
        # Below the source count the map has as much rank as it has rows, leaving the shortfall in
        # coefficients as the entire cause of the blindness.
        if width(top) < COUNT and (kept != width(top) or blind != COUNT - width(top)):
            say("    FAIL degree %d did not reach the rank its coefficient count allows" % top)
            failed += 1
    say("")

    need = int(math.ceil(math.sqrt(COUNT))) - 1
    say("    (L+1)^2 first reaches %d at degree %d, so degree %d is the floor for a reading"
        % (COUNT, need, need))
    say("    that could separate all %d sources at all. Below it the blindness is forced." % COUNT)
    if width(need) < COUNT or width(need - 1) >= COUNT:
        say("    FAIL the floor degree was computed wrong")
        failed += 1
    say("")

    say("  the eight-letter alphabet, as the same kind of map")
    kept, blind, big, least = rank_of(octant_matrix(places))
    say("    rank %d of %d sources, blind in %d directions" % (kept, COUNT, blind))
    if kept != 8:
        say("    FAIL the eight octants did not give eight independent counts")
        failed += 1
    say("    at fixed weight the eight shares carry one constraint, so %d free numbers" % (kept - 1))
    say("    %d of %d directions of the source space do not move any letter" % (blind, COUNT))
    say("    64 distinct signatures out of 64 rounds is therefore not evidence: distinctness")
    say("    is cheap in 7 dimensions and says nothing about the %d that are invisible" % blind)
    say("")

    say("  what this bounds")
    say("    a reading to degree 8 recovers at most %d of %d numbers about its source, so no" %
        (width(8), COUNT))
    say("    sampling, precision or beam count completes it. Raising the degree does, and the")
    say("    cost is coefficients and not accuracy: the basis above is clean at degree 15.")

    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        sys.exit(1 if _check() else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
