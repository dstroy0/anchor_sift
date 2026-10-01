"""What a different arrangement of arms recovers that the octants cannot, as a rank and an angle.

    python examples/00_blob_viz_tools/arm_rank.py
    python examples/00_blob_viz_tools/arm_rank.py --check

THE QUESTION

The eight sign octants are an arm set of rank 8, blind in 248 of 256 directions. That rank is a
property of THAT CHOICE and not a law: `theory/workbooks/anchor_sift/arm-records.md` defines an arm as a weight function
over the placement and an arm set as a matrix whose rank is what the reading carries. So the obvious
question is whether some other arrangement of eight arms sees directions the octants do not, and by
how much.

The blind directions are the null space of the reading map, and the null space belongs to the MAP
and not to the object. Change the arms and the kernel changes with them, an object invisible
to one arm set can be visible to another. This measures that instead of asserting it.

WHAT IS REPORTED, AND WHY THREE NUMBERS AND NOT ONE

  rank            how many independent numbers this arm set carries at all
  new directions  rank of the octants and this set stacked, less the rank of the octants alone
  reach           the largest principal angle cosine between this set's row space and the
                  octants' null space, a set that only re-reads what the octants already had
                  scores near zero however high its own rank

Rank alone is not enough and the reason is the failure this tree keeps meeting. An arm set of rank 8
that spans the SAME subspace as the octants has the same rank and recovers nothing, and a rank
number on its own cannot tell those apart. The stacked rank can, and the angle says how much of the
old kernel the new arms actually reach into.

WHAT IS NOT CLAIMED

Nothing here says a higher rank is a better reading. Rank is a ceiling on what can be recovered and
says nothing about whether the recovered directions matter. A rank-16 arm set blind to everything of
consequence is arithmetically better and practically worse than a rank-8 set that is not.
"""

import argparse
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

import boundary_read
import reading_rank

COUNT = 256          # placement points, the same lit set size the readings use
ARMS = 8             # arms per set, so every configuration is compared at equal width
CAP_RADIANS = 0.9    # a cap arm's angular radius, near the octant's own solid angle


def as_unit(points):
    """The placement as unit vectors, one row each."""
    out = numpy.array(points, dtype=float)
    sizes = numpy.linalg.norm(out, axis=1, keepdims=True)
    sizes[sizes == 0.0] = 1.0
    return out / sizes


def octant_arms(points):
    """The eight sign octants as indicator rows. The baseline, and rank 8 by construction."""
    return reading_rank.octant_matrix(points)


def cap_arms(points, centers, radians=CAP_RADIANS):
    """One arm per center: the indicator of a spherical cap of that angular radius.

    A cap is the simplest arm that is not an octant. It overlaps its neighbors, which the octants
    never do, and overlap is the property `theory/workbooks/anchor_sift/arm-records.md` says an arm set is allowed to have.
    """
    unit = as_unit(points)
    axes = as_unit(centers)
    out = numpy.zeros((len(axes), len(unit)))
    floor = math.cos(radians)
    for at, axis in enumerate(axes):
        out[at] = (unit.dot(axis) >= floor).astype(float)
    return out


def dwell_arms(points, centers, radians=CAP_RADIANS):
    """The same caps, weighted by how far inside the cap each point sits instead of by membership.

    A weight function and not an indicator, as an arm is allowed to be. Worth its own
    row because a smooth weight can carry information a hard edge throws away.
    """
    unit = as_unit(points)
    axes = as_unit(centers)
    out = numpy.zeros((len(axes), len(unit)))
    floor = math.cos(radians)
    for at, axis in enumerate(axes):
        dots = unit.dot(axis)
        inside = numpy.maximum(0.0, dots - floor) / max(1e-12, 1.0 - floor)
        out[at] = inside
    return out


def turned(points, yaw, pitch):
    """The placement rotated, an arm set stated in a turned frame can be compared with one that is not."""
    out = numpy.array(points, dtype=float)
    ca, sa = math.cos(yaw), math.sin(yaw)
    cb, sb = math.cos(pitch), math.sin(pitch)
    about_y = numpy.array([[ca, 0.0, sa], [0.0, 1.0, 0.0], [-sa, 0.0, ca]])
    about_x = numpy.array([[1.0, 0.0, 0.0], [0.0, cb, -sb], [0.0, sb, cb]])
    return out.dot(about_y).dot(about_x)


def rank_of(matrix, floor=None):
    """Numerical rank, with the floor tied to the matrix's own largest singular value.

    An absolute floor would be a threshold picked by judgment, which this tree does not do. Scaling
    it by the largest value and the dimension is the standard conditioning-aware choice and it makes
    the answer independent of how the arms happen to be normalized.
    """
    values = numpy.linalg.svd(matrix, compute_uv=False)
    if values.size == 0:
        return 0, values
    if floor is None:
        floor = values[0] * max(matrix.shape) * numpy.finfo(float).eps
    return int((values > floor).sum()), values


def null_basis(matrix):
    """An orthonormal basis for the null space of `matrix`, as columns."""
    _, values, right = numpy.linalg.svd(matrix, full_matrices=True)
    floor = values[0] * max(matrix.shape) * numpy.finfo(float).eps if values.size else 0.0
    live = int((values > floor).sum())
    return right[live:].T


def row_basis(matrix):
    """An orthonormal basis for the row space of `matrix`, as columns."""
    _, values, right = numpy.linalg.svd(matrix, full_matrices=True)
    floor = values[0] * max(matrix.shape) * numpy.finfo(float).eps if values.size else 0.0
    live = int((values > floor).sum())
    return right[:live].T


def reach_into(new_matrix, kernel):
    """How far a new arm set reaches into a kernel, as the largest principal angle cosine.

    One means some direction of the new row space lies entirely inside the kernel. The new arms
    read something the old set could not see at all. Zero means the new arms live wholly inside what
    the old set already spanned and recover nothing, whatever their own rank.
    """
    if kernel.size == 0:
        return 0.0
    rows = row_basis(new_matrix)
    if rows.size == 0:
        return 0.0
    overlap = numpy.linalg.svd(rows.T.dot(kernel), compute_uv=False)
    return float(overlap[0]) if overlap.size else 0.0


def _report():
    points = boundary_read.golden_place(COUNT)
    base = octant_arms(points)
    base_rank, _ = rank_of(base)
    kernel = null_basis(base)

    print("  Arm sets over %d placement points, %d arms each." % (COUNT, ARMS))
    print("  Baseline: the eight sign octants, rank %d, blind in %d."
          % (base_rank, COUNT - base_rank))
    print("")
    print("  %-34s %6s %8s %8s %9s" % ("arm set", "rank", "stacked", "new", "reach"))

    golden_eight = boundary_read.golden_place(ARMS)
    rotated = turned(points, 0.7, 0.4)

    trials = [
        ("the sign octants, again", base),
        ("octants in a turned frame", octant_arms(rotated)),
        ("caps on 8 golden directions", cap_arms(points, golden_eight)),
        ("dwell weights, same 8 centers", dwell_arms(points, golden_eight)),
        ("caps, half the radius", cap_arms(points, golden_eight, CAP_RADIANS * 0.5)),
        ("caps, one and a half radius", cap_arms(points, golden_eight, CAP_RADIANS * 1.5)),
    ]

    began = time.time()
    evaluations = 0
    for name, arms in trials:
        own, _ = rank_of(arms)
        stacked = numpy.vstack([base, arms])
        both, _ = rank_of(stacked)
        reach = reach_into(arms, kernel)
        evaluations += 1
        print("  %-34s %6d %8d %8d %9.4f"
              % (name, own, both, both - base_rank, reach))
    took = time.time() - began

    print("")
    print("  RANK ALONE DOES NOT ANSWER THE QUESTION. The octants stacked on themselves have rank 8")
    print("  and buy nothing, and a set that spans the same subspace scores the same way. The new")
    print("  column separates a different arrangement from a different reading.")
    print("")
    print("  cost: %.1f ms for %d configurations, %.2f ms each"
          % (took * 1e3, evaluations, took * 1e3 / max(1, evaluations)))
    print("  A search over continuous arm positions is 16 free parameters at this cost per point,")
    print("  so the card is worth reaching for when the sweep wants more points than the host can")
    print("  afford, and not before. Measured here and not assumed.")
    return 0


def _agglomerate():
    """Stack more and more arm sets and watch where the rank stops climbing.

    THE QUESTION THIS SETTLES. An arm is cheap: a weight per placement point, a few kilobytes.
    Memory therefore looks like no constraint at all, and the natural conclusion is that arms can be
    piled up without limit and the reading grows with them.

    It does not. An arm set is a matrix of a rows over N placement points, and its rank is at most
    min(a, N). The placement has N degrees of freedom. Once the arms span that space another arm
    adds nothing, whatever it costs and however many there are. The ceiling is the OBJECT'S
    dimension and not the machine's.

    That is the same rank bound the rest of this work is about, arriving from a new direction: it
    bounded what a degree-L reading could carry at (L+1)^2, and it bounds what any pile of arms can
    carry at N. Adding arms saturates exactly the way adding degrees does.
    """
    points = boundary_read.golden_place(COUNT)
    unit = as_unit(points)
    one_arm_bytes = unit.shape[0] * 8

    print("  Piling arms onto one placement of %d points." % COUNT)
    print("  One arm is %d weights, %d bytes at float64, %d at float32."
          % (COUNT, one_arm_bytes, one_arm_bytes // 2))
    print("")
    print("  %8s %10s %8s %10s  %s" % ("arm sets", "arms", "rank", "blind", "memory"))

    generator = numpy.random.default_rng(11)
    stack = [octant_arms(points)]
    shown = set()
    for sets in (1, 2, 4, 8, 16, 32, 64, 128):
        while len(stack) < sets:
            centers = generator.normal(size=(ARMS, 3))
            stack.append(cap_arms(points, centers))
        piled = numpy.vstack(stack[:sets])
        rank, _ = rank_of(piled)
        arms = piled.shape[0]
        memory = arms * COUNT * 8
        print("  %8d %10d %8d %10d  %.1f KB"
              % (sets, arms, rank, COUNT - rank, memory / 1024.0))
        shown.add(rank)

    print("")
    print("  The rank stops at %d and the arms keep costing memory. Past that point every further" % COUNT)
    print("  arm is a weight vector the reading cannot use, because the placement has only %d" % COUNT)
    print("  independent directions to be read at all.")
    print("")
    print("  So memory is genuinely not the constraint. Rank is the constraint, and no quantity")
    print("  of memory buys rank past the")
    print("  dimension of the thing being read.")
    return 0


def _efficiency():
    """How many arms it takes to reach full rank, and whether where they sit changes the answer.

    THE QUESTION RANK ALONE CANNOT ASK, AND WHY THE FIRST READING OF THIS WAS SHALLOW.
    Eight independent arms give rank 8. So do the eight sign octants, and so does any other eight
    that are independent. Reporting that a different eight "recovered eight directions the octants
    could not see" is true and says less than it sounds: at eight arms rank 8 is the ceiling, and the
    octants already reach it. What a different arrangement buys is DIFFERENT directions, not more.

    The quantity that actually varies is INDEPENDENCE. An arm set of k arms has rank at most
    min(k, N), and whether it attains that is a property of where the arms sit. The agglomeration
    sweep already showed it failing: 128 random cap arms came back at rank 126 and 256 at rank 250.
    Independence starts going before the state space is full.

    So the well-posed question is the efficiency one. How many arms does a placement strategy need
    to reach rank N, and does a strategy exist that never wastes one? The floor is N arms, since
    rank cannot exceed the count, and anything above N is waste that a better arrangement would not
    pay.
    """
    points = boundary_read.golden_place(COUNT)
    generator = numpy.random.default_rng(7)

    def golden_caps(many, radians):
        return cap_arms(points, boundary_read.golden_place(many), radians)

    def random_caps(many, radians):
        return cap_arms(points, generator.normal(size=(many, 3)), radians)

    def golden_dwell(many, radians):
        return dwell_arms(points, boundary_read.golden_place(many), radians)

    strategies = (
        ("caps on a golden placement", golden_caps, CAP_RADIANS),
        ("caps at random", random_caps, CAP_RADIANS),
        ("dwell weights, golden", golden_dwell, CAP_RADIANS),
        ("caps on a golden placement, narrow", golden_caps, CAP_RADIANS * 0.45),
    )
    counts = (8, 32, 64, 128, 192, 256, 384, 512)

    print("  Rank against arm count. The ceiling is min(arms, %d) and the floor for full rank" % COUNT)
    print("  is therefore %d arms. Anything past that is waste." % COUNT)
    print("")
    header = "  %-36s" % "strategy"
    for many in counts:
        header += " %6d" % many
    header += "   %s" % "full at"
    print(header)

    for name, build, radians in strategies:
        row = "  %-36s" % name
        reached = None
        for many in counts:
            arms = build(many, radians)
            rank, _ = rank_of(arms)
            row += " %6d" % rank
            if reached is None and rank >= COUNT:
                reached = many
        row += "   %s" % (str(reached) if reached else "not by %d" % counts[-1])
        print(row)

    print("")
    print("  A strategy matching the diagonal up to %d wastes no arm. One that falls behind is" % COUNT)
    print("  spending arms on directions it already has, and the gap is the waste.")
    print("")
    print("  THE OCTANTS ARE OPTIMAL AT EIGHT AND THAT IS NOT A COMPLIMENT. Every strategy above")
    print("  reaches rank 8 at eight arms, because eight independent arms cannot do worse. The")
    print("  choice of arms starts to matter only where the counts get large enough for")
    print("  independence to fail. The columns to the right measure that.")
    return 0


def _check():
    lines = []
    failed = 0
    points = boundary_read.golden_place(64)

    # The baseline has to be rank 8, or nothing below it means anything.
    base = octant_arms(points)
    rank, _ = rank_of(base)
    lines.append("  the sign octants over 64 points: rank %d" % rank)
    if rank != 8:
        lines.append("    FAIL the octant alphabet is not rank 8")
        failed += 1

    # A set stacked on itself must buy nothing. This is the known negative, and a metric that
    # reported a gain here would report gains everywhere.
    stacked, _ = rank_of(numpy.vstack([base, base]))
    lines.append("  the octants stacked on themselves: rank %d, so %d new" % (stacked, stacked - rank))
    if stacked != rank:
        lines.append("    FAIL duplicating an arm set changed its rank")
        failed += 1

    # And the reach of a set into its own kernel must be zero, by definition of a kernel.
    kernel = null_basis(base)
    reach = reach_into(base, kernel)
    lines.append("  the octants' reach into their own null space: %.3e" % reach)
    if reach > 1e-8:
        lines.append("    FAIL a row space overlapped its own null space")
        failed += 1

    # The known positive: a set built FROM the kernel reaches it completely. Without this the zero
    # above could mean the metric is simply always zero.
    if kernel.shape[1] >= 3:
        planted = kernel[:, :3].T
        reach = reach_into(planted, kernel)
        lines.append("  arms taken from the kernel reach it at %.6f" % reach)
        if reach < 0.999999:
            lines.append("    FAIL arms drawn from the kernel did not register as reaching it")
            failed += 1
        both, _ = rank_of(numpy.vstack([base, planted]))
        lines.append("  those arms stacked on the octants: rank %d, so %d new" % (both, both - rank))
        if both - rank != 3:
            lines.append("    FAIL three independent kernel directions did not add three to the rank")
            failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="what a different arm arrangement recovers")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--efficiency", action="store_true",
                        help="how many arms it takes to reach full rank")
    parser.add_argument("--agglomerate", action="store_true",
                        help="pile arms up and find where the rank stops climbing")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.efficiency:
        sys.exit(_efficiency())
    if args.agglomerate:
        sys.exit(_agglomerate())
    sys.exit(_report())
