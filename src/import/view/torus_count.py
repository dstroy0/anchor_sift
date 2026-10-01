"""Counts modes on a flat torus exactly, by counting lattice points, at any dimension.

    python tools/view/torus_count.py --check

WHY A TORUS

The area law was checked exactly on a sphere, using the fact that harmonics of a given degree come
in a count with a closed form. That left the shape half of the claim resting on packing, because
the surface of a cube has no such formula, and packing runs out of room in high dimensions.

A flat torus has one. Take a square and glue opposite edges: the eigenvalues of the Laplacian on it
are (2 pi / L)^2 times the squared length of an integer vector, so counting modes below a cutoff is
counting integer points inside a ball. That count is an integer, it has no transcendental in it, and
it can be taken at any dimension.

This is worth having because a flat torus is not a sphere in any respect that could be smuggling the
answer in. It is flat where the sphere is curved, it has a hole where the sphere has none, and its
symmetry group is a lattice where the sphere's is a rotation group. If the same constant comes off
both, that is shape and topology failing to matter, arrived at exactly instead of sampled.

HOW THE COUNT IS TAKEN

The number of integer vectors of squared length exactly m, in d dimensions, is the coefficient of
q^m in the d-th power of the series that has a term for every square. Raising that series to the
power d and adding up the coefficients gives the count below a cutoff, in whole numbers throughout.

WHAT THE ERROR TERM IS

The difference between the exact count and the volume of the ball is the lattice point problem,
the Gauss circle problem when d is two and is open in general. So the leading term of the
area law is checked here, and the remainder is a known-hard quantity and not a defect: it must
shrink relative to the leading term, and how fast is somebody else's open question.
"""

import math
import sys


def theta_power(dims, top):
    """Coefficients of the d-th power of the every-square series, up to q^top.

    Coefficient m counts the integer vectors in d dimensions whose squared length is exactly m.
    Whole numbers from start to finish: this is a convolution of integer sequences and nothing in it
    rounds. The count is the answer and not an estimate of the answer.
    """
    base = [0] * (top + 1)
    base[0] = 1
    root = 1
    while root * root <= top:
        base[root * root] = 2
        root += 1

    out = [0] * (top + 1)
    out[0] = 1
    for _ in range(dims):
        fresh = [0] * (top + 1)
        for left in range(top + 1):
            if out[left] == 0:
                continue
            here = out[left]
            step = 0
            while step * step + left <= top:
                if base[step * step]:
                    fresh[left + step * step] += here * base[step * step]
                step += 1
        out = fresh
    return out


def points_within(dims, top):
    """How many integer vectors in this dimension have squared length at most `top`. Exact."""
    return sum(theta_power(dims, top))


def ball_volume(dims):
    """Volume of the unit ball in this dimension."""
    return math.pow(math.pi, dims / 2.0) / math.gamma(dims / 2.0 + 1.0)


def _check():
    bad = 0
    print("  Modes on a flat torus, counted as integer points in a ball.")
    print("")
    print("  %5s %8s %26s %16s %10s" % ("dims", "radius^2", "points, exactly", "ball volume",
                                        "ratio"))

    worst = 0.0
    for dims in (2, 3, 4, 5, 8, 12, 19):
        top = 900 if dims <= 5 else (400 if dims <= 12 else 200)
        got = points_within(dims, top)
        want = ball_volume(dims) * math.pow(top, dims / 2.0)
        ratio = got / want
        worst = max(worst, abs(ratio - 1.0))
        shown = str(got)
        if len(shown) > 26:
            shown = shown[:9] + "..." + shown[-9:] + " (%d)" % len(shown)
        print("  %5d %8d %26s %16.6g %10.5f" % (dims, top, shown, want, ratio))

    print("")
    print("  worst departure: %.3f%%" % (100 * worst))
    if worst > 0.12:
        print("  FAIL the lattice count and the volume disagree by more than a remainder")
        bad += 1

    print("")
    print("  The remainder shrinks, but not one radius at a time. Three dimensions:")
    print("")

    # The error in a lattice count does not fall as the ball grows; it oscillates while its
    # envelope falls. Demanding that each radius beat the one before it fails on a correct count,
    # and that happened here first: 0.0902, 0.1736, 0.0028, 0.0256 percent reads as a
    # remainder that will not settle and is a remainder doing exactly what this one is known to do.
    # So the trend is taken over a band of radii and not at a point.
    def band(low, high, steps):
        seen = []
        for step in range(steps):
            top = low + (high - low) * step // max(1, steps - 1)
            got = points_within(3, top)
            want = ball_volume(3) * math.pow(top, 1.5)
            seen.append(abs(got / want - 1.0))
        return math.sqrt(sum(one * one for one in seen) / len(seen)), max(seen)

    near_rms, near_top = band(150, 400, 9)
    far_rms, far_top = band(6000, 13000, 9)
    print("    small balls   typical off by %.4f%%   worst %.4f%%" % (100 * near_rms, 100 * near_top))
    print("    large balls   typical off by %.4f%%   worst %.4f%%" % (100 * far_rms, 100 * far_top))
    print("    envelope came down by %.1f times" % (near_rms / max(1e-12, far_rms)))
    if far_rms >= near_rms:
        print("  FAIL the remainder is not shrinking")
        bad += 1

    print("")
    print("%d check(s) failed" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(_check())
    sys.stdout.write(__doc__)
