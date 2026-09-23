"""Reading a set of lit points on a boundary: where they sit, how they push it, how they twist it.

    python examples/00_blob_viz_tools/boundary_read.py --check

A library and not a tool. Nothing here knows what the lit points mean, so it serves a hash, a solar
system, or a file of bytes without changing. The part that knows is the caller.

WHAT IS IN HERE

    placements    where an index sits on the sphere. A golden-angle spiral, and rings of equal
                  width. A placement is a choice and it shapes what can be read, so the two that
                  the tools here use are both offered and neither is a default.

    readings      three ways to read one lit set:

                  deflection    the magnitude, as power per degree. A rotation of the whole set
                                leaves every number of it alone.
                  torsion       the phase of the same coefficients. A rotation by alpha moves the
                                phase of order m by exactly m alpha, sign included.
                  octant share  what fraction of the set sits in each of the eight octants.

    screws        the rigid move that shifting every index by one amount comes to on a golden
                  placement: a turn, an axial slide, and one pitch for every amount.

WHY DEFLECTION AND TORSION ARE BOTH HERE

They answer opposite questions and a caller usually wants to know which one carries its signal.
Deflection is rotation blind by construction: the power per degree is a magnitude and a magnitude
does not care how the object is turned. Torsion measures the turn exactly and its sign gives the
handedness. A caller whose operations are rotations reads the twist; a caller who wants a quantity
that survives being turned reads the push. The check below holds both to that claim.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import sphere_field

GOLDEN = math.pi * (3.0 - math.sqrt(5.0))

# The eight octants, by the sign of each coordinate. Every one of them has a trilateral right-angle
# corner at the origin, all eight corners meet at that single point, and the eight regions tile
# space with no gap and no overlap. On the boundary the same split cuts eight congruent spherical
# triangles, each with three right angles, each of area pi/2.
OCTANTS = tuple((sx, sy, sz) for sx in (1, -1) for sy in (1, -1) for sz in (1, -1))


# -------------------------------------------------------------------------------------------------
# Placements.
# -------------------------------------------------------------------------------------------------

def golden_place(count):
    """The Fibonacci placement: index k at height 1 - 2(k + 0.5)/count, longitude k gamma.

    Even coverage without a seam or a pole pile, and the property the screw below depends on: one
    step in the index is one fixed rigid move, the same move everywhere along the spiral.
    """
    out = []
    for k in range(count):
        height = 1.0 - 2.0 * (k + 0.5) / float(count)
        around = (k * GOLDEN) % (2.0 * math.pi)
        flat = math.sqrt(max(0.0, 1.0 - height * height))
        out.append((flat * math.cos(around), height, flat * math.sin(around)))
    return out


def ring_place(rings, width):
    """Rings of equal width: the ring index chooses a latitude, the position chooses a longitude.

    The latitudes are the interiors of the equal bands, so no ring lands on a pole where every point
    of it would pile into one place. A shift along a ring is a pure rotation about the ring axis,
    and that property makes this placement the right one to test a rotation on.
    """
    out = []
    for ring in range(rings):
        down = math.pi * (ring + 0.5) / float(rings)
        across = math.sin(down)
        for step in range(width):
            around = 2.0 * math.pi * step / float(width)
            out.append((across * math.cos(around), math.cos(down), across * math.sin(around)))
    return out


def as_angles(points):
    """Colatitude and longitude of each point, in the form the harmonics want."""
    out = []
    for x, y, z in points:
        radius = math.sqrt(x * x + y * y + z * z) or 1.0
        out.append((math.acos(max(-1.0, min(1.0, y / radius))), math.atan2(z, x)))
    return out


# -------------------------------------------------------------------------------------------------
# Readings.
# -------------------------------------------------------------------------------------------------

def complex_coefficients(angles, live, top):
    """The complex boundary coefficients of a lit set, as {(degree, order): (real, imaginary)}.

    A lit point at (colatitude, longitude) contributes P_lm(cos colatitude) times exp(-i m
    longitude), summed over the lit set. Moving every longitude by alpha multiplies the order m
    entry by exp(-i m alpha), so the magnitude holds still and the phase moves by m alpha. Both
    readings below come off this one table, so it is formed once and handed to them.
    """
    out = {}
    for order in range(top + 1):
        real = [0.0] * (top + 1)
        imaginary = [0.0] * (top + 1)
        for at in live:
            down, around = angles[at]
            column = sphere_field.legendre_column(top, order, math.cos(down))
            turn = order * around
            cosine = math.cos(turn)
            sine = math.sin(turn)
            for degree in range(order, top + 1):
                real[degree] += column[degree] * cosine
                imaginary[degree] -= column[degree] * sine
        for degree in range(order, top + 1):
            out[(degree, order)] = (real[degree], imaginary[degree])
    return out


def deflection(table, top):
    """The magnitude reading: power per degree, summed over the orders. Blind to a rotation.

    The orders above zero are counted twice, because a real expansion carries each of them as a
    matched pair and only the zonal term stands alone.
    """
    out = [0.0] * (top + 1)
    for (degree, order), (real, imaginary) in table.items():
        weight = 1.0 if order == 0 else 2.0
        out[degree] += weight * (real * real + imaginary * imaginary)
    return out


def torsion(table, top):
    """The twist reading: the phase of each entry, as {(degree, order): radians}.

    The zonal terms carry no phase, since order zero has no longitude in it, so they are left out
    instead of being reported as a phase of nothing.
    """
    out = {}
    for (degree, order), (real, imaginary) in table.items():
        if order == 0:
            continue
        if abs(real) + abs(imaginary) < 1e-12:
            continue
        out[(degree, order)] = math.atan2(imaginary, real)
    return out


def turn_between(before, after, order=1):
    """The rotation that carries one lit set to another, in radians, read off the phase.

    Positive is the direction the longitudes run. The coefficients carry exp(-i m longitude), so the
    phase moves against the rotation and undoing that minus is undoing the convention they are
    written in. Order one is asked by default because it pins the angle down without a wrap of its
    own; a higher order divides the angle and returns it only up to its own fraction of a turn.

    None where neither set has a usable entry at that order.
    """
    for degree in range(order, order + 64):
        key = (degree, order)
        if key in before and key in after:
            return (-(after[key] - before[key]) / float(order)) % (2.0 * math.pi)
    return None


def octant_share(points, live):
    """What fraction of the lit set sits in each of the eight octants.

    A point exactly on an octant face is placed by the sign convention, and the eight shares add to
    one because the convention sends every point to exactly one octant.

    An earlier version of this note said a face is measure zero on a placement of this kind. That is
    false for `golden_place` and was refuted by measurement in `arm_draw`. Index 0 has longitude
    `0 * GOLDEN`, which is exactly zero, and the sine of exactly zero is exactly zero, so its third
    coordinate is exactly zero at every placement size: 64, 128, 256, 512, 1024 and 4096 were
    checked and all of them put index 0 on the face. One point of the placement is decided by the
    convention and not by its position, and a caller comparing two conventions gets two answers
    for it.
    """
    counts = [0] * 8
    for at in live:
        x, y, z = points[at]
        slot = (0 if x >= 0 else 1) * 4 + (0 if y >= 0 else 2) + (0 if z >= 0 else 1)
        counts[slot] += 1
    total = float(len(live)) or 1.0
    return [one / total for one in counts]


def octant_delta(before, after):
    """How much of the reading moved between two octant shares, as a percentage of the whole.

    Halved, because a share that leaves one octant arrives in another and the two ends of one move
    would otherwise be counted as two.
    """
    return 100.0 * sum(abs(after[q] - before[q]) for q in range(8)) / 2.0


# -------------------------------------------------------------------------------------------------
# Screws.
# -------------------------------------------------------------------------------------------------

def screw_of(count, amount):
    """The rigid move that shifting every index by this amount comes to on a golden placement.

    Returns the turn in radians, the axial slide, and the pitch, the slide per unit of turn. The
    pitch comes to -2/(count gamma) whatever the amount is, so one axis and one pitch serve every
    amount and a shift is a slide of the whole pattern along one fixed helix.
    """
    turn = amount * GOLDEN
    slide = -2.0 * amount / float(count)
    return turn, slide, (slide / turn if turn else float("nan"))


def wrap_arm(count, amount):
    """The indices a shift runs off the end of, which return as a second arm.

    They reappear a full axial extent away from where the screw alone would put them, rigidly. A
    shift is the screw plus this arm, and where a lit point lands is fixed once the amount is known.
    """
    return list(range(count - amount, count))


# -------------------------------------------------------------------------------------------------
# Checks.
# -------------------------------------------------------------------------------------------------

def _check():
    lines = []
    failed = 0

    def say(text):
        lines.append(text)

    # A golden placement moves as one rigid screw, and its pitch does not depend on the amount.
    count = 256
    places = golden_place(count)
    worst_turn = 0.0
    worst_slide = 0.0
    pitches = []
    for amount in (1, 3, 7, 11, 16, 25):
        turn, slide, pitch = screw_of(count, amount)
        pitches.append(pitch)
        for k in range(0, count - amount, 7):
            x0, y0, z0 = places[k]
            x1, y1, z1 = places[k + amount]
            moved = (math.atan2(z1, x1) - math.atan2(z0, x0) - turn) % (2.0 * math.pi)
            if moved > math.pi:
                moved -= 2.0 * math.pi
            worst_turn = max(worst_turn, abs(moved))
            worst_slide = max(worst_slide, abs((y1 - y0) - slide))
    spread = max(pitches) - min(pitches)
    say("  a golden placement against the screw it should be")
    say("    worst turn error %.3e rad, worst slide error %.3e" % (worst_turn, worst_slide))
    say("    pitch %.9f over six amounts, spread %.3e" % (pitches[0], spread))
    if worst_turn > 1e-12 or worst_slide > 1e-12:
        say("  FAIL the placement does not move as a rigid screw")
        failed += 1
    if spread > 1e-12:
        say("  FAIL the pitch depends on the amount")
        failed += 1

    # Deflection is rotation blind and torsion recovers the rotation exactly.
    top = 8
    rings, width = 8, 32
    ring_points = ring_place(rings, width)
    ring_angles = as_angles(ring_points)
    lit = [k for k in range(rings * width) if (k * 7 + k // 5) % 3]
    base = complex_coefficients(ring_angles, lit, top)
    base_defl = deflection(base, top)
    base_tors = torsion(base, top)

    worst_defl = 0.0
    worst_err = 0.0
    for steps in (1, 2, 5, 8, 13, 17, 31):
        # The same lit set, every point moved along its own ring by the same number of steps, which
        # on this placement is exactly a rotation of the object about the ring axis.
        moved_set = []
        for at in lit:
            ring = at // width
            step = (at % width + steps) % width
            moved_set.append(ring * width + step)
        table = complex_coefficients(ring_angles, moved_set, top)

        defl = deflection(table, top)
        for degree in range(top + 1):
            scale = max(1e-30, abs(base_defl[degree]))
            worst_defl = max(worst_defl, abs(defl[degree] - base_defl[degree]) / scale)

        want = 2.0 * math.pi * steps / float(width)
        got = turn_between(base_tors, torsion(table, top))
        if got is None:
            say("  FAIL torsion had no usable entry at order one")
            failed += 1
            continue
        worst_err = max(worst_err, abs(((got - want + math.pi) % (2.0 * math.pi)) - math.pi))

    say("  a rotation, read two ways")
    say("    deflection moved by %.3e, which is nothing" % worst_defl)
    say("    torsion recovered the angle to %.3e radians" % worst_err)
    if worst_defl > 1e-9:
        say("  FAIL deflection moved, so it is not rotation blind")
        failed += 1
    if worst_err > 1e-9:
        say("  FAIL torsion did not recover the rotation")
        failed += 1

    # The eight octant shares add to one, and a share that does not move reports no delta.
    share = octant_share(ring_points, lit)
    total = sum(share)
    say("  the eight octant shares add to %.15f" % total)
    if abs(total - 1.0) > 1e-12:
        say("  FAIL the octant shares do not add to one")
        failed += 1
    if abs(octant_delta(share, share)) > 1e-15:
        say("  FAIL a share compared against itself reported a move")
        failed += 1

    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        sys.exit(1 if _check() else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
