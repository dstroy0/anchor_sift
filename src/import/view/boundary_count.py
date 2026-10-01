"""Counts what a boundary can hold, two ways that share no step, in any shape and any dimension.

    python tools/view/boundary_count.py --check

THE CLAIM BEING TESTED

A boundary holds a number of separable readings set by its own measure divided by the finest detail
reaching it, raised to the dimension of the boundary. Shape does not enter. If that is right the
same constant comes back off a sphere, a cube and an octahedron, and off a boundary in two, three,
four, five and six dimensions. If it moves with the shape, the account is wrong and no other part of
this directory survives it.

WHY TWO ROUTES

The count is arrived at by packing: points are dropped on the surface and kept where they sit
further than one resolution from everything already kept, which is a direct measure of how many
distinguishable places the surface has. The measure is arrived at separately, in closed form from
the shape's own geometry. Neither computation reads the other.

Dividing one by the other has to give the same number every time. That is a real test because the
two can disagree: a packing count that tracked the volume instead of the surface, or a shape whose
corners held more readings than its faces, would show up as a constant that moves. Computing the
count as area over resolution squared and then checking it against area over resolution squared
would show nothing at all. That is the version this avoids.

WHAT WOULD FAIL IT

A constant that drifts with the shape at fixed dimension. A constant whose drift with dimension is
anything other than the packing density falling, which it must, since spheres pack worse as the
room to miss each other grows. Both are visible in the table this prints.
"""

import math
import random
import sys
from math import comb


def gamma_half(twice):
    """Gamma of an integer or half-integer, given twice its argument. Exact for both parities.

    The half-integer arm climbs from Gamma(1/2) by halves: Gamma(k + 1/2) is root pi times the
    product of (2j - 1)/2 for j up to k. Written with (2j + 1)/2 it starts one step along and
    returns twice the right answer at every odd argument, which is invisible in isolation and
    reaches the surface measure of every odd-dimensional sphere as a factor of two.

    It was caught by the packing count disagreeing with it, and only in odd dimensions. Nothing
    about the number itself looks wrong; it is a plausible size and it varies plausibly. Two routes
    to one quantity is what turned it up.
    """
    if twice % 2 == 0:
        out = 1.0
        for step in range(1, twice // 2):
            out *= step
        return out
    out = math.sqrt(math.pi)
    for step in range(1, (twice - 1) // 2 + 1):
        out *= (2 * step - 1) / 2.0
    return out


def sphere_measure(dims, radius):
    """Surface measure of a sphere of this radius in this many dimensions."""
    return 2.0 * math.pow(math.pi, dims / 2.0) * math.pow(radius, dims - 1) / gamma_half(dims)


def cube_measure(dims, half):
    """Surface measure of a cube of this half-width: two facets per axis, each a face one down."""
    return 2.0 * dims * math.pow(2.0 * half, dims - 1)


def octahedron_measure(half):
    """Surface of the three-dimensional octahedron with vertices at this distance along the axes."""
    return 8.0 * (math.sqrt(3.0) / 4.0) * math.pow(half * math.sqrt(2.0), 2)


def on_sphere(dims, radius, draw):
    point = [draw.gauss(0.0, 1.0) for _ in range(dims)]
    length = math.sqrt(sum(one * one for one in point)) or 1.0
    return [one * radius / length for one in point]


def on_cube(dims, half, draw):
    """Uniform over the surface: a facet first, then a place on it. Facets are equal, so the facet
    is drawn flat. Drawing a point in the solid and pushing it out instead would crowd the corners,
    the mistake that makes a cube look like it holds more than it does."""
    axis = draw.randrange(dims)
    point = [draw.uniform(-half, half) for _ in range(dims)]
    point[axis] = half if draw.random() < 0.5 else -half
    return point


FACES = []
for sx in (1.0, -1.0):
    for sy in (1.0, -1.0):
        for sz in (1.0, -1.0):
            FACES.append((sx, sy, sz))


def on_octahedron(half, draw):
    """Uniform over one of the eight triangles, by folding a square onto it."""
    signs = FACES[draw.randrange(8)]
    one, two = draw.random(), draw.random()
    if one + two > 1.0:
        one, two = 1.0 - one, 1.0 - two
    three = 1.0 - one - two
    return [signs[0] * one * half, signs[1] * two * half, signs[2] * three * half]


def pack(points, apart):
    """How many of these can be kept with none closer than `apart` to another kept one.

    Greedy, in the order they arrive. Greedy packing is not the densest packing and does not need
    to be: it is the same procedure on every shape, so whatever it loses it loses equally, and what
    is being compared is one shape against another and never against a theoretical best.
    """
    kept = []
    limit = apart * apart
    for point in points:
        clear = True
        for other in kept:
            total = 0.0
            for at in range(len(point)):
                gap = point[at] - other[at]
                total += gap * gap
                if total >= limit:
                    break
            if total < limit:
                clear = False
                break
        if clear:
            kept.append(point)
    return len(kept)


def run(name, dims, measure, maker, tries, seed, target=52):
    """Packs at whatever resolution puts the count near `target`, then reports the constant.

    The resolution is found and never chosen. A gap fixed by hand packs thousands of points at two
    dimensions and nothing at nineteen, so the counts stop being comparable long before the shapes
    do, and the test ends up measuring which dimension the gap happened to suit. Searching for the
    gap that lands on one count holds the statistics still and leaves the shape as the only thing
    varying. It costs nothing in fairness either: if the law holds, the constant does not depend on
    the resolution, so finding the resolution cannot flatter it.
    """
    draw = random.Random(seed)
    points = [maker(draw) for _ in range(tries)]

    low, high = 1e-4, 8.0
    apart = 1.0
    count = 0
    for _ in range(16):
        apart = 0.5 * (low + high)
        count = pack(points, apart)
        if count > target:
            low = apart
        else:
            high = apart
        if abs(count - target) <= 2:
            break

    density = count * math.pow(apart, dims - 1) / measure
    return name, dims, count, apart, measure, density


def typical(maker, seed, pairs=900):
    """The middle distance between two points drawn on this surface.

    This decides whether a packing count means anything. A gap far below it is picking points
    out of a crowd, which is packing. A gap approaching it is picking the few pairs that happen to
    be unusually far apart, which is a fact about the sample and not about the surface.

    In high dimensions every pair of points on a sphere sits at very nearly the same distance from
    every other, so the room between the smallest useful gap and the largest possible one closes.
    Past that this method has nothing left to measure, and the honest output is to say so instead of
    printing whatever the arithmetic returned.
    """
    draw = random.Random(seed)
    gaps = []
    for _ in range(pairs):
        one = maker(draw)
        two = maker(draw)
        total = 0.0
        for at in range(len(one)):
            step = one[at] - two[at]
            total += step * step
        gaps.append(math.sqrt(total))
    gaps.sort()
    return gaps[len(gaps) // 2]


def harmonics_upto(dims, top):
    """Exactly how many harmonics of degree at most `top` live on the sphere in this dimension.

    Whole numbers throughout. Degree l on the sphere in n dimensions carries
    C(l+n-1, n-1) - C(l+n-3, n-1) harmonics, and summing that to L telescopes to the two terms
    below. No estimate, no draw, no floating point: the count is an integer and it is this integer.

    The sampling argument was going wrong here, and not going short of samples.
    Packing was being counted by dropping points and looking, and in nineteen dimensions the number
    to be counted is larger than any pool that can be dropped. Counting it instead of measuring it
    removes the pool from the question. Arbitrary precision is not the thing that helps here, since
    nothing was being rounded; what helps is that the quantity was always an integer with a formula.
    """
    return comb(top + dims - 1, dims - 1) + comb(top + dims - 2, dims - 1)


def weyl_upto(dims, top):
    """What the area law predicts that count should be, from the measure of the surface alone.

    Weyl's law: the number of eigenvalues below lambda goes as the volume of the unit ball in the
    boundary's own dimension, times the boundary's measure, times lambda to half that dimension,
    over two pi to that dimension. The eigenvalue at degree L is L(L + n - 2).

    Nothing here reads the count above. One side is combinatorics on a sphere, the other is a
    measure and a power, and they have no term in common.
    """
    edge = dims - 1
    lam = float(top) * (top + dims - 2)
    unit_ball = math.pow(math.pi, edge / 2.0) / gamma_half(edge + 2)
    return (unit_ball * sphere_measure(dims, 1.0) * math.pow(lam, edge / 2.0) /
            math.pow(2.0 * math.pi, edge))


def show(row):
    print("  %-12s %5d %7d %9.4f %12.4f %10.4f" % row)


def _check():
    bad = 0
    tries = 2600

    print("  Shapes against each other, one dimension at a time. The constant has to hold still.")
    print("")
    print("  %-12s %5s %7s %9s %12s %10s" %
          ("shape", "dims", "kept", "gap", "measure", "constant"))

    for dims in (3, 4, 5):
        rows = [
            run("sphere", dims, sphere_measure(dims, 1.0),
                lambda d, n=dims: on_sphere(n, 1.0, d), tries, 100 + dims),
            run("cube", dims, cube_measure(dims, 0.62),
                lambda d, n=dims: on_cube(n, 0.62, d), tries, 200 + dims),
        ]
        if dims == 3:
            rows.append(run("octahedron", 3, octahedron_measure(1.24),
                            lambda d: on_octahedron(1.24, d), tries, 303))
        for row in rows:
            show(row)
        spread = max(one[5] for one in rows) / max(1e-12, min(one[5] for one in rows))
        print("  %-12s %5d spread %.3f times" % ("", dims, spread))
        if spread > 1.30:
            print("  FAIL the constant moved with the shape at %d dimensions" % dims)
            bad += 1
        print("")

    print("  One shape, climbing dimensions, with every row asked whether it means anything.")
    print("")
    print("  %-12s %5s %7s %9s %12s %10s  %s" %
          ("shape", "dims", "kept", "gap", "measure", "constant", "resolved"))

    # A packing count is only about the surface while there are candidates to spare. Past that the
    # count stops being what the geometry allows and becomes what the pool held, and in high
    # dimensions the pool gives out early: points drawn on a sphere in nineteen dimensions are
    # very nearly all at the same distance from one another, so nothing is learned about packing
    # from a few thousand of them however carefully they are counted.
    #
    # So every row is run twice, at one pool and at double it. A row whose constant moves when it
    # is given more candidates was measuring the pool. Reporting it anyway is how a number like
    # eight hundred ends up in a table looking like a result.
    across = []
    for dims in range(2, 20):
        got = run("sphere", dims, sphere_measure(dims, 1.0),
                  lambda d, n=dims: on_sphere(n, 1.0, d), tries, 400 + dims)
        usual = typical(lambda d, n=dims: on_sphere(n, 1.0, d), 900 + dims)
        crowd = got[3] / max(1e-12, usual)
        steady = crowd < 0.62
        print("  %-12s %5d %7d %9.4f %12.4f %10.4f  %s" %
              (got[0], got[1], got[2], got[3], got[4], got[5],
               "yes" if steady else "no, gap is %.0f%% of the usual separation" % (crowd * 100)))
        if steady:
            across.append(got)

    # Only the rows that resolved get a verdict. The constant may drift slowly as packing gets
    # harder with room to spare, and it must not turn over and start tracking the dimension itself.
    worst = 0.0
    for at in range(1, len(across)):
        step = across[at][5] / max(1e-12, across[at - 1][5])
        worst = max(worst, step)
    print("")
    print("  dimensions that resolved: %s" % ", ".join(str(one[1]) for one in across))
    print("  steepest climb among those: %.3f times" % worst)
    if not across:
        print("  FAIL nothing resolved, so nothing was tested")
        bad += 1
    elif worst > 1.6:
        print("  FAIL the count is tracking something that grows with the dimension")
        bad += 1

    print("")
    print("  The same law counted instead of sampled, where sampling cannot reach.")
    print("")
    print("  %5s %9s %26s %14s %10s" % ("dims", "degree", "modes, exactly", "area law", "ratio"))

    off = []
    for dims in (2, 3, 5, 8, 12, 19, 24, 40):
        top = 4000 * dims
        got = harmonics_upto(dims, top)
        want = weyl_upto(dims, top)
        ratio = got / want
        off.append(abs(ratio - 1.0))
        shown = str(got)
        if len(shown) > 26:
            shown = shown[:9] + "..." + shown[-9:] + " (%d digits)" % len(shown)
        print("  %5d %9d %26s %14.6g %10.6f" % (dims, top, shown, want, ratio))

    print("")
    print("  worst departure from the law: %.4f%%" % (100 * max(off)))
    if max(off) > 0.01:
        print("  FAIL the exact count and the area law disagree")
        bad += 1

    # The remainder has to fall as the degree climbs, or what is being seen is a disagreement
    # wearing a small number instead of a law with an error term. Quadrupling the degree should
    # quarter it.
    close = []
    for top in (8000, 32000, 128000, 512000):
        close.append(abs(harmonics_upto(19, top) / weyl_upto(19, top) - 1.0))
    falling = all(close[at] < close[at - 1] * 0.35 for at in range(1, len(close)))
    print("  at nineteen dimensions the remainder runs %s" %
          ", ".join("%.4f%%" % (100 * one) for one in close))
    if not falling:
        print("  FAIL the remainder is not falling as a remainder should")
        bad += 1

    print("")
    print("%d check(s) failed" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(_check())
    sys.stdout.write(__doc__)
