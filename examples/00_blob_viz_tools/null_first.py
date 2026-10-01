"""The null permutation derived before the reading, not discovered after it. The demon's position.

    python examples/00_blob_viz_tools/null_first.py --check
    python examples/00_blob_viz_tools/null_first.py                 every instrument's kernel, up front
    python examples/00_blob_viz_tools/null_first.py --exclude       what each instrument's null can and cannot rule out

WHAT THIS IS FOR

"If we have the null permutation from the start, that's the demon."

On the demon's position: "just because laplaces demon knows everything, doesnt mean he can act on
the information, he can just tell us about it, we are the ones asking questions and adjudicating."

A null earned the expensive way runs the instrument, fades an injected signal until it disappears,
and reports the level at which it vanished. That gives a detection limit
and it is honest, but it is a measurement of the instrument's blindness discovered by experiment.

THE KERNEL DOES NOT HAVE TO BE DISCOVERED. It is a property of the reading map, alone.
Rank-nullity gives its dimension before any object is chosen, an SVD gives an explicit basis for
it, and every vector in that basis IS a null permutation: a change to the object that the reading
cannot see, exactly, by construction and not below a threshold.

That is the demon's position and it is available for free. Knowing it changes what a null means:

    WITHOUT the kernel   "we looked and found nothing" and the reader supplies the caveat
    WITH the kernel      "we looked and found nothing, and here are the K dimensions in which
                          finding nothing was guaranteed before we started"

THREE BLIND SPOTS THIS PREDICTS

    the harmonic reading at degree 8 over 256 sources is blind in 175 dimensions. Derivable
        from 256 - 81 in one line.
    the twist leaves entanglement exactly unchanged. Derivable from local Clifford invariance.
    the conditioning bound is blind to field placement. Derivable from the bound reading only
        min and max.

None of those needs an experiment to know.

WHAT THIS DOES NOT DO

A derived kernel says what CANNOT be seen. It says nothing about what can: a direction outside the
kernel may still be invisible in practice because the instrument is ill-conditioned there, and that
part is genuinely empirical. So this narrows the empirical work instead of replacing it, and the
injection-fade limit is still the right tool for everything outside the kernel.
"""

import argparse
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import beam_rows

SOURCES = beam_rows.COUNT          # 256, one per state bit


def reading_maps():
    """Every reading map in this family, as (name, matrix, how its rank is known in advance).

    The predicted rank is not read off the matrix. It is stated from the construction. The
    measurement below can agree with it or refute it.
    """
    points = beam_rows.source_points(SOURCES)
    out = []
    for degree in (2, 4, 8, 15, 16):
        rows = numpy.asarray(beam_rows.harmonic_rows(degree, SOURCES), dtype=float)
        out.append(("harmonic degree %d" % degree, rows,
                    min((degree + 1) ** 2, SOURCES),
                    "(L+1)^2 coefficients, capped at the source count"))
    beams = beam_rows.beam_set(SOURCES, points)
    out.append(("beams, %d line integrals" % SOURCES, beams, SOURCES,
                "one per source, and they close the harmonic kernel"))
    stacked = numpy.vstack([numpy.asarray(beam_rows.harmonic_rows(8, SOURCES), dtype=float), beams])
    out.append(("harmonic 8 + beams", stacked, SOURCES,
                "the beams supply what degree 8 cannot"))
    return out


def kernel_of(matrix, tolerance=None):
    """An orthonormal basis for the null space, from the SVD.

    The tolerance is the standard one for numerical rank and it is derived from the matrix and
    not chosen: the largest singular value times the larger dimension times the float64 epsilon.
    That is the level at which a singular value is indistinguishable from zero for THIS matrix, and
    it is not a judgment call. A fixed absolute tolerance here would be the same defect that
    produces false positives in beam_read.py.
    """
    left, values, right = numpy.linalg.svd(matrix)
    if tolerance is None:
        tolerance = values[0] * max(matrix.shape) * numpy.finfo(float).eps
    rank = int((values > tolerance).sum())
    return right[rank:], rank, tolerance


def _report():
    print("")
    print("  Every reading map's kernel, derived from the map before any object is chosen.")
    print("  The predicted rank comes from the construction; the measured rank comes from the SVD.")
    print("")
    print("  %-30s %6s %10s %10s %9s %12s"
          % ("instrument", "rows", "rank pred", "rank meas", "kernel", "verdict"))

    for name, matrix, predicted, _why in reading_maps():
        basis, rank, _tolerance = kernel_of(matrix)
        nullity = SOURCES - rank
        agree = "ok" if rank == predicted else "DISAGREES"
        print("  %-30s %6d %10d %10d %9d %12s"
              % (name, matrix.shape[0], predicted, rank, nullity, agree))

    print("")
    print("  THE KERNEL COLUMN IS THE NULL PERMUTATION COUNT, KNOWN IN ADVANCE. Every one of those")
    print("  dimensions is a change to the 256 sources that the instrument returns identically.")
    print("  Not below a threshold: identically, to the arithmetic floor of the format.")
    print("")
    print("  Degree 8 is blind in 175 of 256 dimensions and degree 15 in none. That is the")
    print("  content of what conserved.py measured the long way round.")
    return 0


def _exclude():
    """What a null from each instrument can and cannot rule out."""
    print("")
    print("  A null result's reach, stated from the kernel and not from the run.")
    print("")
    print("  %-30s %9s %9s %28s" % ("instrument", "kernel", "seen", "a null from it excludes"))

    for name, matrix, _predicted, _why in reading_maps():
        basis, rank, _tolerance = kernel_of(matrix)
        nullity = SOURCES - rank
        share = 100.0 * rank / SOURCES
        if nullity == 0:
            claim = "the whole source space"
        else:
            claim = "%.1f%% of directions only" % share
        print("  %-30s %9d %9d %28s" % (name, nullity, rank, claim))

    print("")
    print("  a NULL IS NOT ONE KIND OF STATEMENT. A null from the stacked map excludes signal in")
    print("  every direction the object has. A null from degree 2 excludes it in nine directions of")
    print("  256 and is silent about the other 247, no matter how carefully it was run or how many")
    print("  shuffles drew its bar.")
    print("")
    print("  THIS IS THE CORRECTION TO HOW THE EARLIER NULLS WERE REPORTED. nonce_read.py used six")
    print("  rotation-invariant scalars and reported a detection limit, which is true and complete")
    print("  about what it measured. What it could not say, without this table, is that the six")
    print("  scalars were a projection onto a handful of directions out of 256. The limit was")
    print("  honest and the reach was unstated.")
    return 0


def _check():
    failed = 0
    print("")

    # THE CENTRAL CLAIM, AND IT IS EXACT AND NOT THRESHOLDED. A kernel vector added to the
    # object must leave the reading unchanged to the arithmetic floor while the object itself
    # changes by a large amount. Both halves are required: unchanged reading alone would be
    # satisfied by adding zero.
    points = beam_rows.source_points(SOURCES)
    harmonics = numpy.asarray(beam_rows.harmonic_rows(8, SOURCES), dtype=float)
    basis, rank, tolerance = kernel_of(harmonics)

    generator = numpy.random.default_rng(20260912)
    occupancy = (generator.random(SOURCES) < 0.5).astype(float)
    baseline = harmonics.dot(occupancy)

    worst_reading = 0.0
    smallest_move = None
    for at in range(min(12, basis.shape[0])):
        permutation = basis[at]
        moved = occupancy + permutation
        drift = float(numpy.abs(harmonics.dot(moved) - baseline).max())
        move = float(numpy.abs(permutation).max())
        worst_reading = max(worst_reading, drift)
        smallest_move = move if smallest_move is None else min(smallest_move, move)

    scale = float(numpy.abs(baseline).max())
    print("  12 derived null permutations on a random object:")
    print("    largest reading change   %.4e   (reading scale %.4e)" % (worst_reading, scale))
    print("    smallest object change   %.4e" % smallest_move)
    if worst_reading > 1e-10 * max(scale, 1.0):
        print("    FAIL a kernel vector moved the reading. It is not in the kernel")
        failed += 1
    if smallest_move is None or smallest_move < 1e-6:
        print("    FAIL the object barely changed. The null is vacuous")
        failed += 1

    # RANK-NULLITY MUST HOLD, the arithmetic the whole a-priori claim rests on.
    for name, matrix, predicted, _why in reading_maps():
        basis, rank, _tolerance = kernel_of(matrix)
        if rank + basis.shape[0] != SOURCES:
            print("    FAIL %s: rank %d plus nullity %d is not %d"
                  % (name, rank, basis.shape[0], SOURCES))
            failed += 1
    print("  rank plus nullity equals the source count for every map: %s" % (failed == 0))

    # THE PREDICTION MUST MATCH. If the construction says (L+1)^2 and the SVD says otherwise, one of
    # the two is wrong and the a-priori position is worthless.
    mismatches = []
    for name, matrix, predicted, _why in reading_maps():
        _basis, rank, _tolerance = kernel_of(matrix)
        if rank != predicted:
            mismatches.append((name, predicted, rank))
    print("  every predicted rank matches the measured rank: %s" % (not mismatches))
    for name, predicted, rank in mismatches:
        print("    FAIL %s predicted %d, measured %d" % (name, predicted, rank))
        failed += 1

    # THE NEGATIVE CONTROL. A map with NO kernel must produce no null permutations, or this tool
    # would manufacture them for any instrument and the whole table would be decoration.
    beams = beam_rows.beam_set(SOURCES, points)
    stacked = numpy.vstack([harmonics, beams])
    basis, rank, _tolerance = kernel_of(stacked)
    print("  the stacked map has rank %d and %d null permutations" % (rank, basis.shape[0]))
    if basis.shape[0] != 0:
        print("    FAIL a full-rank map was given a kernel")
        failed += 1

    # AND A VECTOR OUTSIDE THE KERNEL MUST MOVE THE READING, or "in the kernel" means nothing.
    outside = generator.standard_normal(SOURCES)
    projection = basis.T.dot(basis.dot(outside)) if basis.shape[0] else numpy.zeros(SOURCES)
    outside = outside - projection
    drift = float(numpy.abs(harmonics.dot(occupancy + outside) - baseline).max())
    print("  a vector outside the kernel moves the reading by %.4e" % drift)
    if drift < 1e-6:
        print("    FAIL a non-kernel change left the reading alone")
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="the null permutation derived before the reading")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--exclude", action="store_true")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.exclude:
        return _exclude()
    return _report()


if __name__ == "__main__":
    sys.exit(main())
