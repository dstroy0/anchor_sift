"""Drives the device packer across shapes and dimensions, and grades what comes back.

    python tools/view/gpu_pack.py --check
    python tools/view/gpu_pack.py --dims 19 --fraction 0.66

The device counts, and does nothing further. Every surface measure, every constant and every verdict is
computed here, from closed forms that never read a count. That split is the point: one side is a
packing on a card, the other is geometry on a page, and a constant that holds across shapes is only
worth reporting because the two had no way to agree by construction.

WHAT IS BEING ASKED

Whether the number of separable readings a boundary holds is set by its measure over the resolution,
raised to the boundary's own dimension, with the shape not entering. Spherical harmonics settle the
dimension half exactly, but they exist only on spheres: a cube has no such formula. So the shape
half has to be packed, and packing in nineteen dimensions is what the card is for.

WHY THE DEVICE ANSWER IS CHECKED AGAINST THE HOST

A packing count on a card is a number nobody can eyeball. So the same protocol runs on the host at
low dimensions where it can still reach, and the two have to land on the same constant. They draw
their candidates from different generators, so the counts differ by the sampling noise of a few
hundred points and the constants have to agree inside it.
"""

import io
import math
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACKER = os.path.join(HERE, "pack_shapes.exe")

SHAPES = ("sphere", "cube", "orthoplex")


def gamma_half(twice):
    """Gamma of an integer or half-integer, given twice its argument."""
    if twice % 2 == 0:
        out = 1.0
        for step in range(1, twice // 2):
            out *= step
        return out
    out = math.sqrt(math.pi)
    for step in range(1, (twice - 1) // 2 + 1):
        out *= (2 * step - 1) / 2.0
    return out


def measure(shape, dims):
    """Surface measure of the unit form of this shape, in closed form.

    Each matches exactly what the device draws on: the sphere of radius one, the cube whose
    coordinates run to one, and the cross-polytope whose coordinates sum to one in absolute value.
    A measure computed for a different size than the one being packed is the quiet way to get a
    constant that looks shape-dependent and is unit-dependent.
    """
    if shape == "sphere":
        return 2.0 * math.pow(math.pi, dims / 2.0) / gamma_half(dims)
    if shape == "cube":
        # Two facets per axis, each a cube one dimension down with side two.
        return 2.0 * dims * math.pow(2.0, dims - 1)
    # Two to the dims facets, each a simplex on the axis points, each of volume root dims over
    # factorial of dims minus one.
    out = math.pow(2.0, dims) * math.sqrt(dims)
    for step in range(1, dims):
        out /= step
    return out


def on_sphere(dims, draw):
    point = [draw.gauss(0.0, 1.0) for _ in range(dims)]
    length = math.sqrt(sum(one * one for one in point)) or 1.0
    return [one / length for one in point]


def on_cube(dims, draw):
    axis = draw.randrange(dims)
    point = [draw.uniform(-1.0, 1.0) for _ in range(dims)]
    point[axis] = 1.0 if draw.random() < 0.5 else -1.0
    return point


def on_orthoplex(dims, draw):
    point = [-math.log(max(1e-12, draw.random())) for _ in range(dims)]
    total = sum(point) or 1.0
    return [(one / total) * (1.0 if draw.random() < 0.5 else -1.0) for one in point]


MAKERS = {"sphere": on_sphere, "cube": on_cube, "orthoplex": on_orthoplex}


def host_pack(shape, dims, fraction, candidates, seed):
    """The same protocol on the host: measure the typical separation, then pack at a fraction of it."""
    draw = random.Random(seed)
    maker = MAKERS[shape]
    sample = [maker(dims, draw) for _ in range(1500)]

    gaps = []
    for step in range(1200):
        one = sample[(step * 7919) % len(sample)]
        two = sample[(step * 104729 + 13) % len(sample)]
        gaps.append(math.sqrt(sum((one[at] - two[at]) ** 2 for at in range(dims))))
    gaps.sort()
    usual = gaps[len(gaps) // 2]
    gap = fraction * usual
    limit = gap * gap

    kept = []
    for _ in range(candidates):
        point = maker(dims, draw)
        clear = True
        for other in kept:
            total = 0.0
            for at in range(dims):
                step = point[at] - other[at]
                total += step * step
                if total >= limit:
                    break
            if total < limit:
                clear = False
                break
        if clear:
            kept.append(point)
    return gap, usual, len(kept)


def device_pack(shape, dims, fraction, candidates, seed, wide=0):
    if not os.path.exists(PACKER):
        sys.stderr.write("build it first: powershell tools/view/build_pack.ps1\n")
        raise SystemExit(1)
    done = subprocess.run([PACKER, "--shape", shape, "--dims", str(dims),
                           "--fraction", "%.6f" % fraction, "--candidates", str(candidates),
                           "--seed", str(seed), "--wide", str(wide)],
                          capture_output=True, text=True)
    parts = done.stdout.split()
    if len(parts) < 8:
        sys.stderr.write("the packer said: %s%s\n" % (done.stdout, done.stderr))
        raise SystemExit(1)
    return {"shape": parts[0], "dims": int(parts[1]), "gap": float(parts[2]),
            "typical": float(parts[3]), "kept": int(parts[4]), "tried": int(parts[5]),
            "state": parts[6], "math": parts[7]}


def constant(shape, dims, gap, kept):
    return kept * math.pow(gap, dims - 1) / measure(shape, dims)


# The gap has to be small against the shape's own geometry, and that is not the same as being a
# fraction of the typical distance between two points on it.
#
# The typical distance was the first criterion and it is worthless in high dimensions, where the
# separation between two points drawn on a sphere concentrates near root two whatever the dimension
# is. A gap held at half of that is half the radius of curvature, and a cap that wide is nothing
# like the flat disc the count assumes. The cube's facets are flat and suffer no such thing, so the
# two shapes part company and the answer reads as shape-dependence. At twelve dimensions that
# criterion passed a run whose constants spread by 2.1 times.
#
# Measured against the shape instead, at a gap of 0.12 of the typical separation and therefore well
# under every radius in play, the same three shapes give 0.664, 0.644 and 0.650 at three dimensions
# and hold to within a tenth of each other through five.
#
# The price is that staying in this regime costs points. Five dimensions took ten million candidates
# for twenty thousand kept, and the count needed grows with the dimension the way a packing number
# does. That is a structural limit and not a compute budget: no card makes the flat regime cheap at
# nineteen dimensions. The exact routes on a sphere and a flat torus are what reach up there.
SPAN = 0.30
FLOOR = 150

PLAN = [(3, 0.12, 30000000), (4, 0.12, 30000000), (5, 0.12, 30000000)]


def _check():
    bad = 0
    print("  Shapes against each other, on the device, one dimension at a time.")
    print("")
    print("  %-10s %5s %8s %9s %10s %14s %10s  %s" %
          ("shape", "dims", "kept", "gap", "tried", "measure", "constant", "state"))

    for dims, fraction, candidates in PLAN:
        rows = []
        for shape in SHAPES:
            got = device_pack(shape, dims, fraction, candidates, 7)
            here = constant(shape, dims, got["gap"], got["kept"])
            rows.append((shape, here, got))
            print("  %-10s %5d %8d %9.4f %10d %14.5g %10.4f  %s" %
                  (shape, dims, got["kept"], got["gap"], got["tried"],
                   measure(shape, dims), here, got["state"]))

        loose = [one for one in rows if one[2]["state"] != "saturated"]
        wide = [one for one in rows if one[2]["gap"] > SPAN]
        thin = [one for one in rows if one[2]["kept"] < FLOOR]

        if wide:
            print("  %-10s %5d out of regime, gap past %.2f of the shape itself: %s" %
                  ("", dims, SPAN, ", ".join(one[0] for one in wide)))
            print("  %-10s %5d not decided here" % ("", dims))
            print("")
            continue
        if thin:
            print("  %-10s %5d too few kept for the spread to mean anything: %s" %
                  ("", dims, ", ".join(one[0] for one in thin)))
            print("  %-10s %5d not decided here" % ("", dims))
            print("")
            continue
        if loose:
            print("  %-10s %5d did not saturate, so the count is a floor: %s" %
                  ("", dims, ", ".join(one[0] for one in loose)))
            print("  %-10s %5d not decided here" % ("", dims))
            print("")
            continue

        spread = max(one[1] for one in rows) / max(1e-12, min(one[1] for one in rows))
        print("  %-10s %5d spread %.3f times" % ("", dims, spread))
        if spread > 1.15:
            print("  FAIL the constant moved with the shape at %d dimensions" % dims)
            bad += 1
        print("")

    print("  The device against the host, where the host can still reach.")
    print("")
    print("  %-10s %5s %10s %10s %10s %10s" %
          ("shape", "dims", "host kept", "card kept", "host const", "card const"))
    for dims, fraction in ((3, 0.40), (5, 0.44)):
        for shape in SHAPES:
            gap, _, kept = host_pack(shape, dims, fraction, 24000, 31)
            mine = constant(shape, dims, gap, kept)
            got = device_pack(shape, dims, fraction, 4000000, 7)
            theirs = constant(shape, dims, got["gap"], got["kept"])
            apart = max(mine, theirs) / max(1e-12, min(mine, theirs))
            print("  %-10s %5d %10d %10d %10.4f %10.4f%s" %
                  (shape, dims, kept, got["kept"], mine, theirs,
                   "" if apart < 1.25 else "   APART %.2f times" % apart))
            if apart >= 1.25:
                bad += 1

    print("")
    print("  Single against double, on the same points.")
    print("")
    moved = 0
    for dims, fraction in ((3, 0.40), (8, 0.50), (19, 0.66)):
        for shape in SHAPES:
            one = device_pack(shape, dims, fraction, 6000000, 7, wide=0)
            two = device_pack(shape, dims, fraction, 6000000, 7, wide=1)
            same = one["kept"] == two["kept"]
            print("  %-10s %5d  single %7d  double %7d  %s" %
                  (shape, dims, one["kept"], two["kept"], "same" if same else "MOVED"))
            if not same:
                moved += 1
    if moved:
        print("  the accumulator width changes the count at %d settings" % moved)

    print("")
    print("%d check(s) failed" % bad)
    return 1 if bad else 0


def main():
    if "--check" in sys.argv:
        return _check()
    sys.stdout.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
