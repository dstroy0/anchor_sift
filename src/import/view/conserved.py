"""Whether a boundary reading conserves the information in its object, tested by recovering it.

    python tools/view/conserved.py --check
    python tools/view/conserved.py                 the round trip, and where the kernel comes from
    python tools/view/conserved.py --radiate       is any finite source combination nonradiating

THE CLAIM UNDER TEST, AND I HAD IT WRONG

I wrote that a boundary reading conserves one quantity, the monopole, rather than conserving
information, and that the kernel is where the rest goes. Douglas said the kernel is background the
reading is not reading rather than information the reading destroys, and asked for proof.

"Conserves information" has an exact operational meaning and it is testable: take an object, read
it, and try to recover the object from the reading alone. If the recovery lands at the arithmetic
floor then the reading carried everything and nothing was lost. That is a measurement, not a
definition, so this file runs it.

WHAT IT COMES BACK AS

A degree-L reading carries (L+1)^2 real numbers, and N sources carry N. At degree 15 the count
first reaches 256 and at 16 it exceeds it. So the question has a different answer on either side of
that line, and the reason the dispute was possible at all is that both answers are correct about
different readings:

    TRUNCATED BELOW THE COUNT     the map has a kernel, the recovery fails, and the part it fails
                                  on is exactly the kernel component. Information is not carried.
    AT OR ABOVE THE COUNT         the kernel is empty, the recovery lands at the arithmetic floor,
                                  and every one of the N numbers comes back. Information IS carried.

So the kernel of a truncated reading is a property of the truncation and not of the boundary, which
is what Douglas was saying. My statement described one reading and was quoted as though it described
the map.

THE SHARPER QUESTION, AND IT IS THE ONE THAT SETTLES IT

Is there a combination of these sources that radiates nothing at all, at every degree, so that no
reading at any degree or any precision could ever find it? For a finite set of point sources at
distinct positions the answer is no, and `--radiate` shows it: the kernel dimension falls to zero
as the degree rises and stays there. Distinct point sources are linearly independent as
distributions, so no nonzero combination of them is nonradiating.

The genuinely nonradiating sources exist in the CONTINUUM, where a volume distribution has
infinitely many degrees of freedom and particular ones cancel in the exterior. They are not
reachable as a finite combination of point sources, which means the nonradiating obstruction is
real and does not apply to any model in this tree.

WHAT THIS DOES NOT SHOW

It does not show that a reading of a physical field conserves anything. This is the linear algebra
of a specific map, measured. And conditioning is left out on purpose: a recovery can be exact in
arithmetic and still be useless against noise, which is a separate axis reported by reading_rank
and not confused with this one.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

import boundary_read
import reading_rank

COUNT = 256
DEPTH = 0.62

# Degrees swept. Fifteen is where (L+1)^2 first reaches the source count and sixteen is the first
# degree past it, so the interesting behaviour is all between fourteen and sixteen.
DEGREES = (4, 8, 12, 14, 15, 16, 18, 20)


def gain_spread(top, depth):
    """The depth gain (r/R)^l, one entry per coefficient."""
    out = numpy.zeros((top + 1) * (top + 1))
    climb = 1.0
    for degree in range(top + 1):
        out[degree * degree:(degree + 1) * (degree + 1)] = climb
        climb *= depth
    return out


def reading_map(top, count=COUNT, depth=DEPTH):
    """The map from one weight per source to boundary coefficients, at this depth."""
    points = boundary_read.golden_place(count)
    raw = reading_rank.reading_matrix(top, points)
    return raw * gain_spread(top, depth)[:, None]


def live_rank(matrix):
    """Rank and singular values, with the cut taken from the format rather than chosen."""
    singular = numpy.linalg.svd(matrix, compute_uv=False)
    floor = singular[0] * max(matrix.shape) * numpy.finfo(float).eps
    return int((singular > floor).sum()), singular


def round_trip(matrix, weights):
    """Recover the weights from the reading alone, and report the relative error.

    The recovery is a least-squares solve of the same map, which is the most favourable recovery
    available: it is handed the exact map, exact arithmetic apart from rounding, and a noiseless
    reading. Anything it cannot recover under those conditions is not recoverable at all.
    """
    reading = matrix.dot(weights)
    recovered, _residual, _rank, _singular = numpy.linalg.lstsq(matrix, reading, rcond=None)
    gap = float(numpy.linalg.norm(recovered - weights))
    return gap / float(numpy.linalg.norm(weights)), recovered


def kernel_basis(matrix):
    """An orthonormal basis of the map's null space, from the trailing right singular vectors."""
    _left, singular, right = numpy.linalg.svd(matrix)
    floor = singular[0] * max(matrix.shape) * numpy.finfo(float).eps
    keep = int((singular > floor).sum())
    return right[keep:].T


def _report():
    generator = numpy.random.default_rng(11)
    weights = generator.normal(size=COUNT)
    size = float(numpy.linalg.norm(weights))

    print("  %d sources at r/R %.2f. Recovering the sources from the reading alone, by least"
          % (COUNT, DEPTH))
    print("  squares on the exact map with a noiseless reading, which is the most favourable")
    print("  recovery there is.")
    print("")
    print("  %7s %11s %7s %8s %16s %16s"
          % ("degree", "coeffs", "rank", "kernel", "recovery error", "verdict"))

    for top in DEGREES:
        matrix = reading_map(top)
        rank, _singular = live_rank(matrix)
        error, _recovered = round_trip(matrix, weights)
        kernel = COUNT - rank
        verdict = "carried" if error < 1e-8 else "NOT carried"
        print("  %7d %11d %7d %8d %16.4e %16s"
              % (top, (top + 1) ** 2, rank, kernel, error, verdict))

    print("")
    print("  THE LINE IS AT DEGREE 15, WHERE (L+1)^2 FIRST REACHES %d. Below it the kernel is" % COUNT)
    print("  nonempty and the recovery fails. At and above it the kernel is empty and every one")
    print("  of the %d numbers comes back at the arithmetic floor." % COUNT)
    print("")

    # Now the decomposition that settles WHERE the lost part goes, at a truncated degree.
    top = 8
    matrix = reading_map(top)
    null = kernel_basis(matrix)
    print("  WHERE THE MISSING PART SITS, at degree %d with a kernel of %d dimensions."
          % (top, null.shape[1]))
    print("")

    # Split the object into the part the map can see and the part it cannot.
    in_kernel = null.dot(null.T.dot(weights))
    seen = weights - in_kernel
    error_all, recovered = round_trip(matrix, weights)
    print("    the object splits into %.4f of its length outside the kernel and %.4f inside"
          % (float(numpy.linalg.norm(seen)) / size,
             float(numpy.linalg.norm(in_kernel)) / size))

    # The recovered vector should equal the visible part exactly, and hold nothing of the rest.
    visible_gap = float(numpy.linalg.norm(recovered - seen)) / size
    kernel_kept = float(numpy.linalg.norm(null.T.dot(recovered))) / size
    print("    the recovery reproduces the outside-kernel part to %.4e" % visible_gap)
    print("    the recovery holds %.4e of any kernel component" % kernel_kept)
    print("    total recovery error %.4e, which is the kernel part and nothing else" % error_all)
    print("")
    print("  SO THE READING LOSES EXACTLY THE KERNEL COMPONENT AND LOSES NOTHING ELSE. The part")
    print("  it can see comes back at the floor. That is the precise sense in which a truncated")
    print("  reading fails to carry information, and it is a statement about the truncation.")
    print("")
    print("  MY EARLIER CLAIM WAS WRONG AS STATED. I said the reading conserves one quantity, the")
    print("  monopole, rather than conserving information. That describes a reading truncated")
    print("  below the source count. At degree 15 and above the same map carries all %d numbers"
          % COUNT)
    print("  and conserves the object exactly. Douglas's objection was correct: the kernel of a")
    print("  truncated reading is background the reading is not reading, and the degrees above")
    print("  read it.")
    return 0


def _radiate():
    """Does any finite combination of these sources radiate nothing at all?

    The nonradiating obstruction is real in the continuum and the question here is whether it
    touches a finite point-source model. If some combination were nonradiating, the kernel dimension
    would stop falling and settle on that combination's dimension no matter how high the degree
    went. It does not: it reaches zero and stays.
    """
    print("  If a nonzero combination of these sources radiated nothing, the kernel would never")
    print("  empty however high the degree went, because that combination would sit in it at every")
    print("  degree. Sweeping past the count to see whether anything survives:")
    print("")
    print("  %7s %11s %7s %10s %18s" % ("degree", "coeffs", "rank", "kernel", "least live value"))

    for top in (15, 16, 18, 20, 24):
        matrix = reading_map(top)
        rank, singular = live_rank(matrix)
        print("  %7d %11d %7d %10d %18.4e"
              % (top, (top + 1) ** 2, rank, COUNT - rank, singular[rank - 1]))

    print("")
    print("  THE KERNEL EMPTIES AND STAYS EMPTY, so no combination of these sources is")
    print("  nonradiating. Distinct point sources are linearly independent as distributions, and")
    print("  this is that fact measured rather than quoted.")
    print("")
    print("  THE NONRADIATING CLASS IS THEREFORE NOT REACHABLE IN ANY MODEL IN THIS TREE. It needs")
    print("  a continuum, where a volume distribution has infinitely many degrees of freedom and")
    print("  particular ones cancel in the exterior. A finite set of point sources cannot express")
    print("  one, so the obstruction is real and does not bind here.")
    print("")
    print("  WHAT DOES BIND IS CONDITIONING AND IT IS A DIFFERENT AXIS. The least live singular")
    print("  value above says how much noise the recovery tolerates, not whether the information")
    print("  is present. Degree 15 is complete and badly conditioned; 16 is complete and far")
    print("  better. Completeness and usability are separate questions and this file answers only")
    print("  the first.")
    return 0


def _check():
    lines = []
    failed = 0
    generator = numpy.random.default_rng(4)

    # THE POSITIVE CASE. At a degree past the source count the recovery must land at the floor, or
    # the claim that information is carried there is false.
    weights = generator.normal(size=COUNT)
    matrix = reading_map(16)
    rank, _singular = live_rank(matrix)
    error, _recovered = round_trip(matrix, weights)
    lines.append("  degree 16: rank %d of %d, recovery error %.4e" % (rank, COUNT, error))
    if rank != COUNT:
        lines.append("    FAIL the map is not full rank where counting says it must be")
        failed += 1
    if error > 1e-8:
        lines.append("    FAIL a full-rank map did not recover its own object")
        failed += 1

    # THE NEGATIVE CASE, and it is what makes the positive one mean something. A truncated reading
    # must FAIL to recover, or the test passes everything and measures nothing.
    short = reading_map(8)
    short_rank, _singular = live_rank(short)
    short_error, recovered = round_trip(short, weights)
    lines.append("  degree 8: rank %d of %d, recovery error %.4e"
                 % (short_rank, COUNT, short_error))
    if short_rank >= COUNT:
        lines.append("    FAIL a degree-8 reading cannot have rank 256, it has only 81 numbers")
        failed += 1
    if short_error < 0.1:
        lines.append("    FAIL a reading with a 175-dimensional kernel recovered the object, so")
        lines.append("         the recovery is not honest")
        failed += 1

    # The lost part must be EXACTLY the kernel component. This is the claim the report rests on, so
    # it is asserted rather than displayed: the recovery must reproduce the visible part at the
    # floor and must hold none of the kernel.
    null = kernel_basis(short)
    in_kernel = null.dot(null.T.dot(weights))
    seen = weights - in_kernel
    size = float(numpy.linalg.norm(weights))
    visible_gap = float(numpy.linalg.norm(recovered - seen)) / size
    kernel_kept = float(numpy.linalg.norm(null.T.dot(recovered))) / size
    lines.append("  the visible part comes back to %.3e and the recovery holds %.3e of the kernel"
                 % (visible_gap, kernel_kept))
    if visible_gap > 1e-8:
        lines.append("    FAIL the part the map can see did not come back exactly")
        failed += 1
    if kernel_kept > 1e-8:
        lines.append("    FAIL the recovery invented a kernel component it could not have read")
        failed += 1

    # An object placed entirely in the kernel must read as nothing. That is the delta null
    # primitive, and it is the strongest statement about what a truncated reading cannot see.
    if null.shape[1] > 0:
        hidden = null[:, 0]
        reading = short.dot(hidden)
        relative = float(numpy.linalg.norm(reading)) / max(
            float(numpy.linalg.norm(short.dot(seen))), 1e-30)
        lines.append("  an object drawn from the kernel reads %.3e against a visible object"
                     % relative)
        if relative > 1e-10:
            lines.append("    FAIL a kernel vector produced a reading, so it is not the kernel")
            failed += 1

    # And that same hidden object must be VISIBLE at a degree past the count, which is the whole of
    # Douglas's objection stated as a test. If it stayed invisible it would be nonradiating.
    if null.shape[1] > 0:
        hidden = null[:, 0]
        full = reading_map(16)
        seen_now = float(numpy.linalg.norm(full.dot(hidden)))
        scale = float(numpy.linalg.norm(full.dot(weights))) / size
        lines.append("  the same kernel object at degree 16 reads %.4e, against a per-unit scale"
                     " of %.4e" % (seen_now, scale))
        if seen_now < 1e-6:
            lines.append("    FAIL what degree 8 could not see is still invisible at degree 16,")
            lines.append("         which would make it nonradiating rather than truncated")
            failed += 1

    # The kernel must empty as the degree passes the count and must stay empty, or some combination
    # really is nonradiating.
    never = []
    for top in (16, 18, 20):
        matrix = reading_map(top)
        rank, _singular = live_rank(matrix)
        if rank != COUNT:
            never.append("%d at rank %d" % (top, rank))
    lines.append("  the kernel is empty at degrees 16, 18 and 20: %s"
                 % ("yes" if not never else "NO: " + ", ".join(never)))
    if never:
        lines.append("    FAIL something survives at every degree, so it is nonradiating")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="does a reading carry its object")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--radiate", action="store_true")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.radiate:
        sys.exit(_radiate())
    sys.exit(_report())
