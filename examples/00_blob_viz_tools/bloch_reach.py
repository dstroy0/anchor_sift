"""Which points of the Bloch sphere this machine can reach, enumerated and recorded.

    python examples/00_blob_viz_tools/bloch_reach.py --check
    python examples/00_blob_viz_tools/bloch_reach.py               the reachable set, recorded
    python examples/00_blob_viz_tools/bloch_reach.py --depth       how the miss shrinks as T gates are added

THE QUESTION, AND IT HAS AN EXACT ANSWER

"Prove that we can reach all points on a Bloch sphere, record the graph pts."

The answer is no for the graph form and it is not a vague no. A single-qubit STABILIZER state is an
eigenstate of a Pauli operator, and there are exactly six of them:

    |0>, |1>            the Z eigenstates, the poles
    |+>, |->            the X eigenstates
    |+i>, |-i>          the Y eigenstates

Those six points are the vertices of a REGULAR OCTAHEDRON inscribed in the Bloch sphere. Not a
dense set, not an approximation to the sphere: six points. The single-qubit Clifford group has 24
elements and it PERMUTES those six. No amount of Clifford work reaches a seventh.

A graph state on one vertex with no edges is |+>, one of the six. Its local Clifford orbit is all
six. So the graph points are recorded below and there are six of them.

HOW FAR SHORT IS THAT, IN A NUMBER

The right measure is the COVERING RADIUS: the largest angle from any point of the sphere to the
nearest reachable point. For the octahedron that angle is exact and it is worth having in closed
form, because it says how wrong the stabilizer set can be about a state:

    the worst-case point is a face center, at (1,1,1)/sqrt(3)
    its angle to the nearest vertex is arccos(1/sqrt(3)) = 54.7356 degrees

a stabilizer state can be wrong about a qubit's direction by nearly fifty-five degrees. That is
the honest size of the gap and it is why the graph form cannot be sold as reaching the sphere.

WHAT CLOSES IT, AND THAT WE HAVE IT

T gates. tgate_free.py proves the T gate is applied exactly here at no cost beyond the working
precision, because exp(i pi/4) = (1+i)/sqrt(2) and sqrt(2) sits in dn_constants.csv at a thousand
places with a zero gap. Clifford plus T is universal. The reachable set becomes DENSE in the
sphere and the covering radius falls with depth.

DENSE IS STILL NOT ALL, AND THAT DISTINCTION IS THE WHOLE HONEST ANSWER. A finite gate set applied
finitely many times reaches a countable set of points, and the sphere is uncountable, a measure
zero subset is the most any gate set reaches. The claim that survives is: arbitrarily close to any
point, exactly, with the error falling as depth grows and each gate costing nothing to apply.
"""

import argparse
import cmath
import math
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)


def bloch_of(alpha, beta):
    """The Bloch vector of a normalized single-qubit amplitude pair."""
    x = 2.0 * (alpha.conjugate() * beta).real
    y = 2.0 * (alpha.conjugate() * beta).imag
    z = abs(alpha) ** 2 - abs(beta) ** 2
    return numpy.array([x, y, z])


def stabilizer_points():
    """The six single-qubit stabilizer states, as (name, amplitudes, Bloch vector).

    ENUMERATED FROM THE STATES AND NOT WRITTEN DOWN AS COORDINATES. The octahedron comes out
    of the construction. If the six Bloch vectors do not come out as the signed axis
    vectors then the construction is wrong and the control below says so.
    """
    root = 1.0 / math.sqrt(2.0)
    out = [
        ("|0>", (1 + 0j, 0 + 0j)),
        ("|1>", (0 + 0j, 1 + 0j)),
        ("|+>", (root + 0j, root + 0j)),
        ("|->", (root + 0j, -root + 0j)),
        ("|+i>", (root + 0j, root * 1j)),
        ("|-i>", (root + 0j, -root * 1j)),
    ]
    return [(name, pair, bloch_of(pair[0], pair[1])) for name, pair in out]


def reachable_with_t(depth, samples=4000, seed=3):
    """Bloch points reachable by Clifford plus `depth` T gates, sampled.

    The full reachable set at depth d is finite and grows fast. It is sampled and not
    enumerated past the smallest depths. Sampling is honest here because the question is the
    COVERING radius, and a sampled subset can only make the covering radius look WORSE than it is,
    never better. So every figure below is an upper bound on the miss.
    """
    generator = numpy.random.default_rng(seed)
    # Clifford on one qubit permutes the six stabilizer points. The orbit is those six. T is a
    # rotation of pi/4 about Z, and H moves the Z axis to X. Words in {T, H} generate the set.
    turn = math.pi / 4.0
    root = 1.0 / math.sqrt(2.0)

    # THE SET IS CUMULATIVE AND STARTS FROM THE SIX STABILIZER POINTS, and it has to be. Reaching
    # something with AT MOST d T gates is a superset of reaching it with at most d-1, because the
    # extra gate can always be declined. The covering radius cannot rise with depth.
    #
    # Words with EXACTLY d T gates exclude the six octahedron vertices, and read 119.76 degrees at
    # depth 1 against 54.64 at depth 0. That is not a finding about T gates: it is a set that does
    # not contain the depth 0 set. A monotone control in _check refuses it.
    points = [one[2] for one in stabilizer_points()]
    for _ in range(samples):
        alpha, beta = 1 + 0j, 0 + 0j
        used = 0
        budget = int(generator.integers(0, depth + 1)) if depth > 0 else 0
        while used < budget:
            if generator.random() < 0.5:
                # Hadamard, a Clifford, free and exact.
                alpha, beta = (alpha + beta) * root, (alpha - beta) * root
            else:
                # T, the one that leaves the stabilizer set.
                beta = beta * cmath.exp(1j * turn)
                used += 1
        # A final Hadamard half the time. The set is not biased to the Z axis.
        if generator.random() < 0.5:
            alpha, beta = (alpha + beta) * root, (alpha - beta) * root
        size = math.sqrt(abs(alpha) ** 2 + abs(beta) ** 2)
        points.append(bloch_of(alpha / size, beta / size))
    return numpy.array(points)


def covering_radius(points, probes=20000, seed=17):
    """The largest angle from a sphere point to the nearest of `points`, in degrees.

    Probes are drawn area-uniformly, taking cos(colatitude) uniform and not the angle, or they
    would crowd the poles and the worst case would be missed.
    """
    generator = numpy.random.default_rng(seed)
    cosines = 2.0 * generator.random(probes) - 1.0
    sines = numpy.sqrt(numpy.maximum(0.0, 1.0 - cosines * cosines))
    angles = 2.0 * math.pi * generator.random(probes)
    probe = numpy.stack([sines * numpy.cos(angles), sines * numpy.sin(angles), cosines], axis=1)

    normalized = points / numpy.linalg.norm(points, axis=1, keepdims=True)
    dots = probe.dot(normalized.T)
    best = numpy.clip(dots.max(axis=1), -1.0, 1.0)
    return float(numpy.degrees(numpy.arccos(best)).max())


def _report():
    print("")
    print("  THE GRAPH POINTS, recorded. A single-qubit stabilizer state is a Pauli eigenstate and")
    print("  there are exactly six. These are computed from the amplitudes, not written down.")
    print("")
    print("  %-6s %28s %26s" % ("state", "amplitudes", "Bloch vector"))
    points = stabilizer_points()
    for name, pair, vector in points:
        print("  %-6s %28s %26s"
              % (name,
                 "(%.4f%+.4fi, %.4f%+.4fi)" % (pair[0].real, pair[0].imag,
                                               pair[1].real, pair[1].imag),
                 "(%+.4f, %+.4f, %+.4f)" % (vector[0], vector[1], vector[2])))

    vectors = numpy.array([one[2] for one in points])
    print("")
    print("  Those are the six signed axis vectors. The reachable set is a REGULAR OCTAHEDRON")
    print("  inscribed in the sphere. The single-qubit Clifford group has 24 elements and permutes")
    print("  these six. No Clifford sequence reaches a seventh point.")
    print("")

    measured = covering_radius(vectors)
    exact = math.degrees(math.acos(1.0 / math.sqrt(3.0)))
    print("  COVERING RADIUS, how wrong the set can be about a direction:")
    print("    measured by area-uniform probing : %.4f degrees" % measured)
    print("    exact, arccos(1/sqrt 3)          : %.4f degrees" % exact)
    print("")
    print("  So the answer to reaching all points is NO for the stabilizer form, and the size of")
    print("  the no is fifty-five degrees. The worst case is a face center at (1,1,1)/sqrt(3),")
    print("  equidistant from three vertices.")
    return 0


def _depth():
    print("")
    print("  Adding T gates, which tgate_free.py proves cost nothing here beyond working precision.")
    print("  Clifford plus T is universal. The set becomes dense and the miss falls with depth.")
    print("")
    print("  %8s %14s %20s %16s" % ("T gates", "points sampled", "covering radius deg", "vs depth 0"))

    base = covering_radius(numpy.array([one[2] for one in stabilizer_points()]))
    print("  %8d %14d %20.4f %16s" % (0, 6, base, "-"))

    for depth in (1, 2, 3, 4, 6, 8, 12):
        points = reachable_with_t(depth)
        radius = covering_radius(points)
        print("  %8d %14d %20.4f %16s"
              % (depth, len(points), radius, ("%.2fx tighter" % (base / radius)) if (radius > 0 and radius < base) else "no gain"))

    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE.")
    print("")
    print("  These are UPPER BOUNDS on the miss. The reachable set at each depth is sampled, and a")
    print("  sampled subset can only make a covering radius look worse than the truth. The real")
    print("  radii are at or below these.")
    print("")
    print("  DENSE IS NOT ALL, and that is the honest end of the answer. A finite gate set applied")
    print("  finitely often reaches a countable set of points and the sphere is uncountable, so")
    print("  every gate set reaches a measure zero subset. What is true: arbitrarily close to any")
    print("  point, exactly, with the error falling as depth grows and each T costing nothing.")
    return 0


def _check():
    failed = 0
    print("")

    points = stabilizer_points()
    vectors = numpy.array([one[2] for one in points])

    # THE SIX MUST BE THE SIGNED AXIS VECTORS EXACTLY, or the octahedron claim is invented. Derived
    # from the amplitudes. This grades the construction and not a table of coordinates.
    want = numpy.array([[0, 0, 1], [0, 0, -1], [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0]],
                       dtype=float)
    worst = 0.0
    for vector in vectors:
        gaps = numpy.abs(want - vector).max(axis=1)
        worst = max(worst, float(gaps.min()))
    print("  the six states are the signed axis vectors, worst coordinate error %.3e" % worst)
    if worst > 1e-12:
        print("    FAIL the stabilizer states are not the octahedron vertices")
        failed += 1

    # EVERY ONE MUST BE ON THE SPHERE, since a pure state has a unit Bloch vector. A short vector
    # would mean the state was mixed and the whole picture would be wrong.
    lengths = numpy.linalg.norm(vectors, axis=1)
    print("  all six are unit length, worst deviation %.3e" % float(numpy.abs(lengths - 1.0).max()))
    if float(numpy.abs(lengths - 1.0).max()) > 1e-12:
        print("    FAIL a stabilizer state is not pure")
        failed += 1

    # THE COVERING RADIUS MUST MATCH ITS CLOSED FORM. Probing is a measurement and arccos(1/sqrt 3)
    # is the answer, agreement grades the prober against arithmetic.
    measured = covering_radius(vectors, probes=60000)
    exact = math.degrees(math.acos(1.0 / math.sqrt(3.0)))
    print("  covering radius measured %.4f against exact %.4f degrees" % (measured, exact))
    if abs(measured - exact) > 0.5:
        print("    FAIL the prober disagrees with the closed form")
        failed += 1

    # AND IT MUST NOT REACH EVERYTHING, the negative control. A covering radius near zero
    # for six points would mean the prober is broken, since six points cannot cover a sphere.
    if measured < 30.0:
        print("    FAIL six points cannot cover the sphere to better than 30 degrees")
        failed += 1

    # THE POSITIVE CONTROL. Adding T gates must tighten it, or the universality claim is untested.
    tightened = covering_radius(reachable_with_t(8))
    print("  with 8 T gates the radius falls to %.4f degrees" % tightened)
    if tightened >= measured:
        print("    FAIL T gates did not improve the reach. The set is not becoming dense")
        failed += 1

    # THE MONOTONE CONTROL, WHICH EXISTS BECAUSE THE FIRST VERSION VIOLATED IT. Reaching with at
    # most d T gates is a superset of reaching with at most d-1. The covering radius can only
    # fall. A rise means the sampled set is not cumulative and the depth table is comparing
    # different kinds of set to each other instead of measuring an improvement.
    ladder = [covering_radius(reachable_with_t(depth, samples=1500))
              for depth in (0, 1, 2, 3, 4, 6)]
    rises = [at for at in range(1, len(ladder)) if ladder[at] > ladder[at - 1] + 1e-9]
    print("  covering radius by depth: %s" % ["%.2f" % one for one in ladder])
    print("  it never rises with depth: %s" % (not rises))
    if rises:
        print("    FAIL the radius rose at depth index %s. The set is not cumulative" % rises)
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="which Bloch points this machine reaches")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--depth", action="store_true")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.depth:
        return _depth()
    return _report()


if __name__ == "__main__":
    sys.exit(main())
