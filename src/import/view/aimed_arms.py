"""Arms aimed at the kernel instead of scattered across it. The demon's arms.

    python tools/view/aimed_arms.py --check
    python tools/view/aimed_arms.py                 aimed against random, arms to closure
    python tools/view/aimed_arms.py --shape          what size and smoothness are worth

WHAT THIS IS FOR

Douglas, 2026-09-12: "that's what the other engine arms are for, you can size them, shape them,
pos and move anywhere." And: "those are the demons arms."

arm_rank.py established the wall from the wrong side: 1024 cap arms at two megabytes still give
rank 256, the source count. More arms buy nothing past that. What it did not ask is how FEW arms
reach it, and that question only becomes answerable once the kernel is known in advance.

null_first.py supplies exactly that. A degree-8 harmonic reading has rank 81 over 256 sources, so
it is blind in 175 dimensions, and an SVD hands over an explicit basis for them before any arm is
placed. An arm's centre, radius and weighting are all free. So the arms can be pointed AT the
blindness rather than sprinkled and hoped over.

THE PREDICTION, STATED BEFORE THE RUN SO THE RESULT CAN REFUTE IT

Aimed arms should close the kernel with fewer arms than random ones, because two random caps often
add the same direction twice while two aimed caps are pointed at directions that are orthogonal by
construction.

It should NOT be one arm per kernel dimension. A cap arm is an indicator over a region, so the rows
it can produce live in the span of indicator functions, and a kernel direction is generally not one
of those. aimed placement should help and should still fall short of the 175 that a perfect
basis-matched instrument would need. If it reached exactly 175 that would mean the caps happened to
span the kernel, which would be a surprise and worth checking rather than celebrating.

HOW AN ARM IS AIMED

Each kernel basis vector carries a weight per source. The arm is centred on the source direction
where that weight is largest in absolute value. That is the crudest possible aiming and it is
chosen for exactly that reason: if the crude version works, the effect is about knowing the kernel
and not about a clever placement rule.
"""

import argparse
import math
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import arm_rank
import beam_rows

SOURCES = beam_rows.COUNT          # 256
DEGREE = 8                         # 81 coefficients, a 175 dimensional kernel
TARGET = SOURCES                   # closure means rank equal to the source count


def harmonic_map():
    return numpy.asarray(beam_rows.harmonic_rows(DEGREE, SOURCES), dtype=float)


def kernel_basis(matrix):
    """An orthonormal basis for the null space, tolerance derived from the matrix not chosen."""
    _left, values, right = numpy.linalg.svd(matrix)
    tolerance = values[0] * max(matrix.shape) * numpy.finfo(float).eps
    rank = int((values > tolerance).sum())
    return right[rank:]


def rank_of(matrix):
    values = numpy.linalg.svd(matrix, compute_uv=False)
    tolerance = values[0] * max(matrix.shape) * numpy.finfo(float).eps
    return int((values > tolerance).sum())


def aimed_centres(points, basis, count):
    """One centre per kernel direction: the source where that direction weighs most."""
    unit = arm_rank.as_unit(points)
    out = []
    for at in range(min(count, basis.shape[0])):
        where = int(numpy.argmax(numpy.abs(basis[at])))
        out.append(unit[where])
    return numpy.array(out)


def random_centres(count, seed=0):
    generator = numpy.random.default_rng(seed)
    raw = generator.standard_normal((count, 3))
    return raw / numpy.linalg.norm(raw, axis=1, keepdims=True)


def arms_to_closure(points, harmonics, centres, radians, smooth=False):
    """How many arms from this list it takes to reach full rank, adding them in order.

    NO ARM CAP. An earlier version stopped at 1200 arms, which was a number I picked, and a picked
    number is exactly what this tree refuses. The loop now runs until closure or until the supplied
    centres run out, and the caller decides how many to supply. If it does not close, that is
    reported as not closing rather than as a bound.
    """
    builder = arm_rank.dwell_arms if smooth else arm_rank.cap_arms
    target = len(points)
    stack = harmonics
    for at in range(1, len(centres) + 1):
        arms = builder(points, centres[:at], radians)
        stack = numpy.vstack([harmonics, arms])
        if rank_of(stack) >= target:
            return at, rank_of(stack)
    return None, rank_of(stack)


def _sources():
    """Does the ceiling move with the source count? It is the object's size, not a limit.

    Douglas, 2026-09-12: "you don't need to cap at 175, stop bounding us."

    He is right and the framing was mine. 256 is not a wall that arms run into. It is how many
    sources I put in the object, and rank cannot exceed the number of things there are to see. The
    kernel of a degree-L reading is sources - (L+1)^2, so both the ceiling and the hole move when
    the object does. arm_rank.py's result that 1024 arms still give rank 256 is a statement about a
    256 source object and says nothing about arms.

    This sweeps the source count and reports the ceiling, the kernel and the arms to closure at
    each. If the ceiling tracks the source count, there is no bound here to argue with.
    """
    print("")
    print("  The ceiling against the source count. Degree %d throughout, so the reading carries" % DEGREE)
    print("  (L+1)^2 = %d coefficients whatever the object's size." % ((DEGREE + 1) ** 2))
    print("")
    print("  %8s %10s %10s %10s %14s"
          % ("sources", "rank", "ceiling", "kernel", "arms to close"))

    for count in (64, 128, 256, 512, 1024):
        points = beam_rows.source_points(count)
        harmonics = numpy.asarray(beam_rows.harmonic_rows(DEGREE, count), dtype=float)
        rank = rank_of(harmonics)
        basis = kernel_basis(harmonics)
        kernel = basis.shape[0]

        centres = aimed_centres(points, basis, kernel) if kernel else numpy.zeros((0, 3))
        if kernel:
            extra = random_centres(max(0, kernel // 2 + 8), seed=1)
            centres = numpy.vstack([centres, extra])
            used, reached = arms_to_closure(points, harmonics, centres, 0.9)
        else:
            used, reached = 0, rank

        print("  %8d %10d %10d %10d %14s"
              % (count, rank, count, kernel, used if used is not None else "not closed"))

    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE.")
    print("")
    print("  The ceiling is the source count at every row, so it is the object's size and not a")
    print("  property of the instrument. Raise the source count and the ceiling rises with it. The")
    print("  arms needed track the kernel, which is sources - %d, and that is arithmetic rather"
          % ((DEGREE + 1) ** 2))
    print("  than a limit somebody has to accept.")
    return 0


def _report():
    points = beam_rows.source_points(SOURCES)
    harmonics = harmonic_map()
    basis = kernel_basis(harmonics)

    print("")
    print("  Degree %d harmonic reading over %d sources: rank %d, kernel %d."
          % (DEGREE, SOURCES, rank_of(harmonics), basis.shape[0]))
    print("  The kernel basis is derived from the map before any arm exists. The arms are then")
    print("  pointed at it, or scattered, and counted to closure.")
    print("")
    print("  %-26s %10s %12s %14s" % ("arm placement", "radius", "arms used", "rank reached"))

    outcomes = {}
    for radians in (0.4, 0.6, 0.9, 1.2):
        aimed = aimed_centres(points, basis, basis.shape[0])
        used, reached = arms_to_closure(points, harmonics, aimed, radians)
        outcomes[("aimed", radians)] = used
        print("  %-26s %10.2f %12s %14d"
              % ("aimed at the kernel", radians,
                 used if used else "not closed", reached))

    print("")
    for radians in (0.4, 0.6, 0.9, 1.2):
        best = None
        for seed in range(3):
            centres = random_centres(1200, seed=seed)
            used, reached = arms_to_closure(points, harmonics, centres, radians)
            if used is not None and (best is None or used < best):
                best = used
            last = reached
        outcomes[("random", radians)] = best
        print("  %-26s %10.2f %12s %14s"
              % ("random, best of 3 seeds", radians,
                 best if best else "not closed", last))

    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE.")
    print("")
    for radians in (0.4, 0.6, 0.9, 1.2):
        aimed = outcomes[("aimed", radians)]
        scattered = outcomes[("random", radians)]
        if aimed and scattered:
            print("    radius %.2f: aimed %d arms, random %d arms, a factor of %.2f"
                  % (radians, aimed, scattered, scattered / float(aimed)))
        else:
            print("    radius %.2f: aimed %s, random %s"
                  % (radians, aimed or "not closed", scattered or "not closed"))
    print("")
    print("  The kernel is %d dimensional, so %d arms is the floor a perfectly basis-matched"
          % (basis.shape[0], basis.shape[0]))
    print("  instrument would hit. A cap is an indicator over a region and a kernel direction is")
    print("  not one, so falling short of that floor is expected rather than a defect.")
    return 0


def _shape():
    """Size and smoothness, which are the other two free parameters of an arm."""
    points = beam_rows.source_points(SOURCES)
    harmonics = harmonic_map()
    basis = kernel_basis(harmonics)
    aimed = aimed_centres(points, basis, basis.shape[0])

    print("")
    print("  Aimed arms, varying the two parameters that are not position.")
    print("")
    print("  %10s %14s %14s" % ("radius", "hard cap", "smooth dwell"))
    for radians in (0.2, 0.3, 0.4, 0.6, 0.9, 1.2, 1.5):
        hard, _ = arms_to_closure(points, harmonics, aimed, radians, smooth=False)
        soft, _ = arms_to_closure(points, harmonics, aimed, radians, smooth=True)
        print("  %10.2f %14s %14s"
              % (radians, hard if hard else "not closed", soft if soft else "not closed"))

    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE. A hard edge and a smooth weight are both legal")
    print("  arms, and the table says which is worth choosing at each size rather than an argument")
    print("  about which ought to be.")
    return 0


def _check():
    failed = 0
    print("")

    points = beam_rows.source_points(SOURCES)
    harmonics = harmonic_map()
    basis = kernel_basis(harmonics)

    # THE STARTING POINT MUST BE WHAT null_first PREDICTS, or this tool is aiming at the wrong hole.
    print("  harmonic rank %d, kernel %d (predicted 81 and 175)"
          % (rank_of(harmonics), basis.shape[0]))
    if rank_of(harmonics) != 81 or basis.shape[0] != 175:
        print("    FAIL the starting map is not degree 8 over 256 sources")
        failed += 1

    # A DUPLICATE ARM MUST ADD EXACTLY ZERO RANK. Free, exact, and it catches a rank routine whose
    # tolerance is loose enough to count numerical noise as a new direction, which would make every
    # arm look productive and the whole comparison meaningless.
    centres = aimed_centres(points, basis, 12)
    single = arm_rank.cap_arms(points, centres[:6], 0.6)
    doubled = numpy.vstack([single, single])
    if rank_of(doubled) != rank_of(single):
        print("    FAIL duplicating an arm set changed its rank, %d against %d"
              % (rank_of(doubled), rank_of(single)))
        failed += 1
    print("  duplicating an arm set adds exactly zero rank: %s"
          % (rank_of(doubled) == rank_of(single)))

    # AN ARM MUST BE A REAL REGION. A cap that covers nothing, or everything, is not an arm and
    # would silently contribute a zero row or a constant row.
    empty = 0
    for radians in (0.2, 0.6, 1.2):
        arms = arm_rank.cap_arms(points, centres[:20], radians)
        counts = arms.sum(axis=1)
        if counts.min() < 1.0 or counts.max() >= SOURCES:
            empty += 1
    print("  every cap covers at least one source and not all of them: %s" % (empty == 0))
    failed += empty

    # AND CLOSURE MUST ACTUALLY BE REACHABLE, or a "not closed" row below would be uninformative
    # about aiming and only report that caps cannot span anything.
    used, reached = arms_to_closure(points, harmonics, random_centres(1200, seed=0), 0.6)
    print("  random caps do reach full rank eventually: %s (%s arms, rank %d)"
          % (used is not None, used if used else "none", reached))
    if used is None:
        print("    FAIL caps cannot close the kernel at all, aiming cannot be compared")
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="arms aimed at a kernel known in advance")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--shape", action="store_true")
    parser.add_argument("--sources", action="store_true",
                        help="does the ceiling move with the source count")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.shape:
        return _shape()
    if args.sources:
        return _sources()
    return _report()


if __name__ == "__main__":
    sys.exit(main())
