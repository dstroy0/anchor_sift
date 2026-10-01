"""How much of a reading's change a rigid motion cannot explain, per unit of source movement.

    python examples/00_blob_viz_tools/deform_rate.py --check
    python examples/00_blob_viz_tools/deform_rate.py                 the scalar across topologies and moves

THE SCALAR, AND WHY IT IS ONE NUMBER AND NOT A CHOICE OF UNITS

The definition: propagation speed here is a conceptual scalar standing for anisotropic field
deformation, read through torsion and deflection. That is constructible, and it is worth saying
first what it is NOT: no kernel in this tree has a kinematic signal speed. Depth is elliptic and
conduction is the heat semigroup, and both have instantaneous global dependence. So the quantity
below is an IMPEDANCE. Its reciprocal is the thing called speed, and neither is a velocity.

The construction falls out of how the two instruments behave under a rotation:

    a rigid rotation by alpha    multiplies the (l,m) coefficient by exp(-i m alpha)
    deflection                   power per degree, a rotation does not move it AT ALL
    torsion                      phase per (l,m), a rotation moves it by exactly -m alpha

That gives a decomposition with nothing invented in it. Take the reading before and after a move,
read the rigid angle off the order-one phase, apply that rotation to the before reading, and ask how
much of the change is left:

    scalar = || after - rotated(before) ||  /  || after - before ||

Dimensionless, between zero and one, and no unit conversion between a power and a phase is required
because both readings live in the one complex coefficient vector the norm is taken over.

    0     the move was rigid. The reading turned and did not deform.
    1     no rotation helps. The change is entirely shape.

THE NULL IS EXACT AND IT IS THE POINT

A pure rotation must return zero, and it must return zero for every topology and every angle. That
is not a tolerance, it is an identity: the rotated before-reading IS the after-reading. So the
number this tool reports is measured against a floor that belongs to the arithmetic, the same way
every other floor in this tree does, and not against a threshold anybody chose.

WHY TOPOLOGY IS THE OTHER AXIS

The claim: the trick to increasing computation is to explode without confounding the topology,
and the information dissipates more readily. Read as a claim about this scalar it is testable, because the
scalar is deformation per unit of source movement and the source arrangement is free:

    points      sources at one depth, golden placed. The arrangement every reading here uses.
    bubbles     concentric shells at several depths. Depth enters as (r/R)^l. Shells at
                different radii are weighted differently by degree before anything moves.
    foam        sources on the walls between seeds, and not at the seeds. A wall structure
                has its mass between the cells instead of in them.

WHAT THIS DOES NOT ESTABLISH

It measures a property of the READING MAP under a stated move, not a property of any physical field.
Nothing here shows that information in any medium propagates at any rate. And the scalar is silent
on whether the deformation it reports carries anything worth having: a large shape change in
directions the map cannot resolve is still a large number here.
"""

import argparse
import cmath
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import boundary_read

TOP = 12          # reading degree. High enough that a shell's depth weighting separates degrees.
COUNT = 192       # sources, divisible by 3 so the bubble shells come out even


def gain(top, depth):
    """The per-degree depth gain (r/R)^l, one number per degree."""
    out = []
    climb = 1.0
    for _ in range(top + 1):
        out.append(climb)
        climb *= depth
    return out


def reading_of(places, top=TOP):
    """The complex coefficient table of a set of (direction, depth) pairs, depth gain applied.

    Each source carries its own depth. The shells in a bubble arrangement are weighted per degree
    before any move happens. Summed over sources, because the boundary has no way to report which
    source put a given part of the field there.
    """
    total = {}
    for point, depth in places:
        angles = boundary_read.as_angles([point])
        table = boundary_read.complex_coefficients(angles, [0], top)
        scale = gain(top, depth)
        for key, (real, imaginary) in table.items():
            degree = key[0]
            held = total.get(key, 0j)
            total[key] = held + complex(real, imaginary) * scale[degree]
    return total


def rotated(table, alpha):
    """The same reading with the whole set turned by alpha, exactly.

    A rotation in longitude multiplies the (l,m) entry by exp(-i m alpha). This is not an
    approximation of a rotation. It is what a rotation does to these coefficients, and the null
    below is an identity.
    """
    return {key: value * cmath.exp(-1j * key[1] * alpha) for key, value in table.items()}


def norm_between(one, two):
    """The norm of the difference of two coefficient tables, orders above zero counted twice.

    The doubling matches `boundary_read.deflection`: a real expansion carries every order above zero
    as a matched pair and only the zonal term stands alone. Using a different weighting here than
    the deflection reading uses would measure a different object than the one the tree reports.
    """
    total = 0.0
    for key in set(one) | set(two):
        weight = 1.0 if key[1] == 0 else 2.0
        gap = one.get(key, 0j) - two.get(key, 0j)
        total += weight * (gap.real * gap.real + gap.imag * gap.imag)
    return math.sqrt(total)


def best_angle(before, after):
    """The rotation that MINIMIZES the leftover difference, not the one the order-one phase names.

    THE FIRST VERSION READ THE ANGLE OFF THE ORDER-ONE PHASE AND THE TOOL PRINTED A SCALAR OF 2.65.
    That is impossible for a quantity documented as a fraction between zero and one, and the reason
    is worth keeping: the order-one phase is the exact rotation only when the move IS a rotation.
    For a move that is partly shape, it names an angle that is not the best rigid fit, and applying
    it can leave MORE difference than doing nothing. A scalar above one was the tool reporting that
    its own rotation estimate had made things worse.

    The minimization is done properly here and it is nearly free, because the objective is a
    trigonometric polynomial. Expanding the squared norm,

        || after - rot(before) ||^2 = sum w (|a|^2 + |b|^2) - 2 sum_m Re( c_m exp(-i m alpha) )

    where c_m collects conj(after) times before over every degree at that order. Only the second
    term moves with alpha. Minimizing the norm is maximizing a band-limited sum over orders up to
    the reading degree. A scan at a resolution far finer than that band, refined by a parabola
    through the best three samples, finds the maximum to well under the arithmetic floor.

    Alpha zero is always in the search. The returned angle can never be worse than no rotation
    and the scalar is genuinely bounded above by one.
    """
    weights = {}
    for key in set(before) | set(after):
        order = key[1]
        weight = 1.0 if order == 0 else 2.0
        term = weight * (after.get(key, 0j).conjugate() * before.get(key, 0j))
        weights[order] = weights.get(order, 0j) + term

    def objective(alpha):
        return sum((value * cmath.exp(-1j * order * alpha)).real
                   for order, value in weights.items())

    # Sixteen samples per cycle of the fastest order present is far past what the band needs.
    top_order = max(weights) if weights else 0
    steps = max(720, 16 * (top_order + 1) * 4)
    best = 0.0
    best_value = objective(0.0)
    span = 2.0 * math.pi / steps
    for step in range(steps):
        alpha = step * span
        value = objective(alpha)
        if value > best_value:
            best_value = value
            best = alpha

    # NEWTON ON THE DERIVATIVE, NOT A PARABOLA THROUGH THREE SAMPLES. The parabola was the second
    # version of this and it left the null at 3.3e-07 instead of 1e-13, because it only approximates
    # the peak and the scan's own spacing then sets the accuracy. The objective is a sum of cosines
    # with known coefficients. Its first two derivatives are exact and Newton reaches the
    # stationary point at the arithmetic floor in a handful of steps.
    #
    #   f(a)   = sum_m Re( c_m exp(-i m a) )
    #   f'(a)  = sum_m m Im( c_m exp(-i m a) )
    #   f''(a) = sum_m -m^2 Re( c_m exp(-i m a) )
    for _ in range(60):
        slope = 0.0
        curve = 0.0
        for order, value in weights.items():
            turned_value = value * cmath.exp(-1j * order * best)
            slope += order * turned_value.imag
            curve -= order * order * turned_value.real
        if curve == 0.0:
            break
        step = slope / curve
        best -= step
        if abs(step) < 1e-17:
            break
    return best % (2.0 * math.pi)


def deformation_scalar(before, after):
    """The fraction of the change that no rigid rotation explains, and the angle it removed.

    Returns (scalar, alpha, total). A total of zero means nothing moved at all, and the scalar is
    then reported as zero and not as a division by nothing.
    """
    total = norm_between(before, after)
    if total == 0.0:
        return 0.0, 0.0, 0.0
    alpha = best_angle(before, after)
    left = norm_between(rotated(before, alpha), after)
    return left / total, alpha, total


# -------------------------------------------------------------------------------------------------
# The topologies. Each returns a list of (unit direction, depth).
# -------------------------------------------------------------------------------------------------

def points_at(count=COUNT, depth=0.62):
    """Sources at one depth, golden placed. The arrangement every reading in this tree uses."""
    return [(point, depth) for point in boundary_read.golden_place(count)]


def bubbles_at(count=COUNT, depths=(0.45, 0.62, 0.79)):
    """Concentric shells. The same directions at three depths. Degree weighting differs by shell.

    Split evenly and taken as consecutive runs of the golden spiral and not interleaved. Each
    shell is itself a well spread set instead of a third of one.
    """
    places = boundary_read.golden_place(count)
    share = count // len(depths)
    out = []
    for at, depth in enumerate(depths):
        for point in places[at * share:(at + 1) * share]:
            out.append((point, depth))
    return out


def foam_at(count=COUNT, depth=0.62, seeds=24):
    """Sources on the walls between seeds and not at the seeds.

    A seed set is golden placed, then each source sits at the normalized midpoint of a seed and its
    nearest other seed, which is a point on the wall between two cells. The mass therefore lies
    between the cells instead of in them, the structural difference a foam has from a point
    cloud and the only property of a foam this claims to carry.
    """
    anchors = boundary_read.golden_place(seeds)
    out = []
    drawn = boundary_read.golden_place(count)
    for at, point in enumerate(drawn):
        near = None
        best = -2.0
        for other in anchors:
            dot = sum(a * b for a, b in zip(point, other))
            if dot > best:
                best = dot
                near = other
        second = None
        best_two = -2.0
        for other in anchors:
            if other is near:
                continue
            dot = sum(a * b for a, b in zip(point, other))
            if dot > best_two:
                best_two = dot
                second = other
        wall = tuple(a + b for a, b in zip(near, second))
        length = math.sqrt(sum(one * one for one in wall)) or 1.0
        out.append((tuple(one / length for one in wall), depth))
    return out


TOPOLOGIES = (("points", points_at), ("bubbles", bubbles_at), ("foam", foam_at))


# -------------------------------------------------------------------------------------------------
# The moves.
# -------------------------------------------------------------------------------------------------

def turn_all(places, alpha):
    """A rigid rotation of every source about the polar axis. THE NULL: no deformation at all."""
    out = []
    for (x, y, z), depth in places:
        out.append(((x * math.cos(alpha) - z * math.sin(alpha), y,
                     x * math.sin(alpha) + z * math.cos(alpha)), depth))
    return out


def squash(places, amount):
    """Push half the sources deeper, chosen by hemisphere. Pure shape, and no rotation in it."""
    return [(point, depth * (1.0 - amount) if point[1] >= 0.0 else depth)
            for point, depth in places]


def shear(places, alpha):
    """Turn the northern hemisphere only. A rotation in part of the set, a mixed move."""
    out = []
    for (x, y, z), depth in places:
        if y >= 0.0:
            out.append(((x * math.cos(alpha) - z * math.sin(alpha), y,
                         x * math.sin(alpha) + z * math.cos(alpha)), depth))
        else:
            out.append(((x, y, z), depth))
    return out


def displacement(before, after):
    """Root mean square movement of the sources in space. Moves can be compared across shapes.

    The depth multiplies the direction, since a source at depth r sits at r times its unit vector,
    and a change of depth is a real displacement that a direction-only measure would miss.
    """
    total = 0.0
    for (one, first), (two, second) in zip(before, after):
        gap = [a * first - b * second for a, b in zip(one, two)]
        total += sum(value * value for value in gap)
    return math.sqrt(total / max(1, len(before)))


MOVES = (("rotate whole set", turn_all, 0.30, "the null: rigid, so the scalar must be zero"),
         ("deepen one hemisphere", squash, 0.12, "pure shape, no rotation available"),
         ("turn one hemisphere", shear, 0.30, "part rigid and part shape"))


def quarter_turns(table, quarters):
    """Turn the reading by a whole number of quarter turns, with NO arithmetic error whatsoever.

    A rotation by alpha multiplies the (l,m) coefficient by exp(-i m alpha). At alpha = pi/2 that
    factor is a power of i, and multiplying a complex number by a power of i is a swap of the real
    and imaginary parts with a sign change. No multiply, no trigonometry, no rounding:

        i^0 z = (a, b)      i^1 z = (-b, a)      i^2 z = (-a, -b)      i^3 z = (b, -a)

    So this is the exact rotation and not a floating-point approximation of one. `cmath.exp(-1j *
    m * pi/2)` would NOT be exact, because pi/2 is not representable and the exponential rounds.
    This routine exists for the distinction: the same mathematical operation has an exact
    implementation and an inexact one, and which one is used decides whether a null is zero or
    merely small.
    """
    out = {}
    for (degree, order), value in table.items():
        step = (-order * quarters) % 4
        if step == 0:
            out[(degree, order)] = value
        elif step == 1:
            out[(degree, order)] = complex(-value.imag, value.real)
        elif step == 2:
            out[(degree, order)] = complex(-value.real, -value.imag)
        else:
            out[(degree, order)] = complex(value.imag, -value.real)
    return out


def _exact():
    """Which nulls are EXACTLY zero and which are only small, and what decides it.

    The claim: against the most entropic noise in existence, the noise floor is zero.

    It holds for a class of moves and the class has a sharp boundary. The useful answer is
    the boundary and not a yes or a no. A null is exactly zero when the move is exact in the
    representation the reading is stored in. It is the format's floor when the reading has to be
    recomputed, because then the same quantity is reached by two different routes and the routes
    round differently.
    """
    places = points_at()
    table = reading_of(places)

    print("  A null is the residual of a move that cannot change the reading. Some of these are")
    print("  EXACTLY zero and some are the format's floor, and the difference is not precision.")
    print("")
    print("  %-54s %18s" % ("the move, and whether it is exact in the representation", "residual"))

    # 1. The identity. Nothing done at all.
    print("  %-54s %18.0e" % ("nothing: the reading against itself", norm_between(table, table)))

    # 2. Four quarter turns. Each is a swap and a sign. The composition is exact.
    four = quarter_turns(quarter_turns(quarter_turns(quarter_turns(table, 1), 1), 1), 1)
    print("  %-54s %18.0e" % ("four quarter turns, by swap and sign", norm_between(table, four)))

    # 3. Two half turns. Each multiplies by (-1)^m, an exact sign flip.
    twice = quarter_turns(quarter_turns(table, 2), 2)
    print("  %-54s %18.0e" % ("two half turns, by sign flip", norm_between(table, twice)))

    # 4. Deflection under one quarter turn. Power per degree cannot move under a rotation, and the
    #    magnitude of a swapped-and-negated pair is the same sum of squares. This is exact too.
    turned = quarter_turns(table, 1)
    first = [0.0] * (TOP + 1)
    second = [0.0] * (TOP + 1)
    for (degree, order), value in table.items():
        weight = 1.0 if order == 0 else 2.0
        first[degree] += weight * (value.real * value.real + value.imag * value.imag)
    for (degree, order), value in turned.items():
        weight = 1.0 if order == 0 else 2.0
        second[degree] += weight * (value.real * value.real + value.imag * value.imag)
    worst = max(abs(a - b) for a, b in zip(first, second))
    print("  %-54s %18.0e" % ("deflection under a quarter turn, exact", worst))

    print("")
    print("  EVERY ROW ABOVE IS EXACTLY ZERO, not small. Those moves are sign flips and swaps of")
    print("  numbers already held. There is no arithmetic in them to round. That is true in")
    print("  float32, in float64 and at a thousand decimal digits, and it is true forever: a")
    print("  floor of zero is not a precision setting and nothing can be lower.")
    print("")
    print("  NOW THE SAME ROTATIONS DONE THE OTHER WAY, as any ordinary tool does.")
    print("")
    print("  %-54s %18s" % ("the move, recomputed and not relabeled", "residual"))

    # The same quarter turn, but by moving the sources and running the whole pipeline again.
    spun = turn_all(places, math.pi / 2.0)
    recomputed = reading_of(spun)
    print("  %-54s %18.3e"
          % ("quarter turn, sources moved and reading rebuilt",
             norm_between(quarter_turns(table, 1), recomputed)))

    # And an angle that is not a quarter turn at all, which has no exact form.
    arbitrary = 0.3
    spun_any = reading_of(turn_all(places, arbitrary))
    print("  %-54s %18.3e"
          % ("0.3 radians, no exact representation exists",
             norm_between(rotated(table, arbitrary), spun_any)))

    size = norm_between(table, {})
    print("")
    print("  reading scale for comparison: %.3e" % size)
    print("")
    print("  SO THE ANSWER IS A BOUNDARY. A null is exactly zero when the move is")
    print("  exact in the representation the reading is held in: relabelings, sign flips, swaps,")
    print("  quarter and half turns, the identity. It is the format's floor the moment the reading")
    print("  has to be rebuilt, because then one quantity is reached by two routes that round")
    print("  differently. The floor can be zero, and the reason is not that")
    print("  the precision is high. It is that there is no arithmetic to be wrong.")
    print("")
    print("  WHERE THE CLAIM DOES OVERREACH, STATED PLAINLY. A null of zero says the instrument")
    print("  is exactly self-consistent under that move. It does NOT say the instrument resolves a")
    print("  signal against physical noise at zero error, because that is a different quantity:")
    print("  the null measures the reader against itself and a detection measures the reader")
    print("  against an object. Only the first can be zero, and this file measures only the first.")
    return 0


def _report():
    print("  scalar = || after - rotated(before) || / || after - before ||")
    print("  Zero means a rigid motion explained the whole change. One means none of it.")
    print("  Reading degree %d, %d sources." % (TOP, COUNT))
    print("")
    print("  %-22s %-10s %9s %11s %13s %13s"
          % ("move", "topology", "scalar", "angle rad", "rms moved", "per unit"))

    held = {}
    for name, move, amount, _why in MOVES:
        for shape, build in TOPOLOGIES:
            places = build()
            after = move(places, amount)
            before_read = reading_of(places)
            after_read = reading_of(after)
            scalar, alpha, total = deformation_scalar(before_read, after_read)
            moved = displacement(places, after)
            per_unit = (scalar * total / moved) if moved > 0 else 0.0
            held[(name, shape)] = (scalar, per_unit)
            print("  %-22s %-10s %9.2e %11.4f %13.4e %13.4e"
                  % (name, shape, scalar, alpha, moved, per_unit))
        print("")

    print("  THE FIRST BLOCK IS THE CONTROL AND IT DECIDES WHETHER THE REST MEANS ANYTHING.")
    print("  A rigid rotation carries the reading exactly. The scalar there is arithmetic and")
    print("  nothing else. Every number in the other blocks is read against it.")
    print("")

    print("  IMPEDANCE AND ITS RECIPROCAL, the quantity called speed. Deformation")
    print("  per unit of source movement, on the shape move, lowest impedance first:")
    print("")
    ranked = sorted(((shape, held[("deepen one hemisphere", shape)][1])
                     for shape, _build in TOPOLOGIES), key=lambda pair: pair[1])
    for shape, rate in ranked:
        print("    %-10s impedance %13.4e    speed %13.4e" % (shape, rate, 1.0 / rate))
    print("")
    print("  A LOWER IMPEDANCE MEANS THE SAME SOURCE MOVEMENT CONTORTS THE READING LESS, which is")
    print("  the readable form of exploding without confounding the topology. The absolute values")
    print("  are in the norm's own units and carry no meaning on their own.")
    print("")
    print("  AND THE ORDERING IS NOT A CLEAN RESULT YET, FOR TWO REASONS WORTH STATING AND NOT")
    print("  RANKING THROUGH. Points and bubbles land within a few percent of each other,")
    print("  which is inside what a different choice of move amount would shift. And foam is")
    print("  confounded outright:")
    print("")
    for shape, build in TOPOLOGIES:
        places = build()
        print("    %-10s %4d sources requested, %4d distinct positions"
              % (shape, len(places), len(set(places))))
    print("")
    print("  The foam construction assigns every drawn point to its nearest pair of seeds. Many")
    print("  points land on the same wall and the set collapses. Its higher impedance may be that")
    print("  degeneracy instead of anything about a wall structure, and the two cannot be told")
    print("  apart from this run. The repair is to build the walls from distinct seed pairs")
    print("  directly instead of by assignment, and until that is done the foam row is not")
    print("  evidence about foam.")
    print("")
    print("  NOT A VELOCITY. No kernel in this tree has a signal speed: depth is elliptic and")
    print("  conduction is the heat semigroup, both with instantaneous global dependence. This is")
    print("  a property of the reading map under a stated move, and it says nothing about the rate")
    print("  at which anything physical propagates.")
    return 0


def _check():
    lines = []
    failed = 0

    # THE NULL IS AN IDENTITY, WITH NO TOLERANCE. A rigid rotation multiplies each
    # coefficient by a phase. The rotated before-reading IS the after-reading. Any residual is
    # the arithmetic of the decomposition. Checked on every topology, because a null that holds for
    # one arrangement and not another would be a property of that arrangement.
    for shape, build in TOPOLOGIES:
        places = build()
        before = reading_of(places)
        for alpha in (0.1, 0.75, 2.4):
            after = reading_of(turn_all(places, alpha))
            scalar, found, _total = deformation_scalar(before, after)
            lines.append("  %-8s rotated by %.2f: scalar %.3e, angle recovered %.4f"
                         % (shape, alpha, scalar, found))
            if scalar > 1e-6:
                lines.append("    FAIL a rigid rotation must leave nothing for the scalar to see")
                failed += 1
            if abs(((found - alpha + math.pi) % (2.0 * math.pi)) - math.pi) > 1e-6:
                lines.append("    FAIL the rotation angle was not recovered")
                failed += 1

    # THE POSITIVE CONTROL. A move with no rotation in it must give a scalar near one, or the tool
    # reports zero for everything and the null above proves nothing.
    places = points_at()
    before = reading_of(places)
    after = reading_of(squash(places, 0.12))
    scalar, _alpha, _total = deformation_scalar(before, after)
    lines.append("  a pure depth change, no rotation available: scalar %.4f" % scalar)
    if scalar < 0.5:
        lines.append("    FAIL a shape change was absorbed by a rotation, which cannot happen")
        failed += 1

    # Deflection must be blind to a rotation and torsion must not be, the property the
    # whole decomposition rests on. Taken off the tree's own instruments and not restated.
    angles = boundary_read.as_angles(boundary_read.golden_place(64))
    live = list(range(64))
    table = boundary_read.complex_coefficients(angles, live, 8)
    # turn_all works on (point, depth) pairs and as_angles wants bare points. The depths come
    # back off here.
    spun = turn_all([(point, 1.0) for point in boundary_read.golden_place(64)], 0.4)
    turned = boundary_read.as_angles([point for point, _depth in spun])
    turned_table = boundary_read.complex_coefficients(turned, live, 8)
    first = boundary_read.deflection(table, 8)
    second = boundary_read.deflection(turned_table, 8)
    worst = max(abs(a - b) for a, b in zip(first, second))
    scale = max(max(first), 1e-30)
    lines.append("  deflection under a rotation: worst change %.3e against a scale of %.3e"
                 % (worst, scale))
    if worst / scale > 1e-9:
        lines.append("    FAIL deflection moved under a rotation, so it is not the magnitude")
        lines.append("         reading the decomposition assumes")
        failed += 1

    # And the zero-move case must not divide by nothing.
    same = reading_of(points_at())
    scalar, _alpha, total = deformation_scalar(same, same)
    lines.append("  a reading against itself: scalar %.3e, total change %.3e" % (scalar, total))
    if scalar != 0.0 or total != 0.0:
        lines.append("    FAIL an unchanged reading did not report exactly no change")
        failed += 1

    # THE SCALAR MUST BE BOUNDED BY ONE, ON EVERY MOVE AND EVERY TOPOLOGY. Alpha zero is always in
    # the minimizer's search. No rotation can be worse than none and the residual cannot exceed
    # the total. A scalar read off the order-one phase breaks this bound on the mixed move.
    over = []
    for name, move, amount, _why in MOVES:
        for shape, build in TOPOLOGIES:
            places = build()
            scalar, _found, _total = deformation_scalar(reading_of(places),
                                                        reading_of(move(places, amount)))
            if scalar > 1.0 + 1e-9:
                over.append("%s/%s at %.4f" % (name, shape, scalar))
    lines.append("  the scalar stays at or under one on all %d move and topology pairs: %s"
                 % (len(MOVES) * len(TOPOLOGIES), "yes" if not over else "NO: " + ", ".join(over)))
    if over:
        lines.append("    FAIL a fraction of a change came out larger than the change")
        failed += 1

    # And the minimizer must find a rotation at least as good as doing nothing, the
    # property that bound rests on. Stated separately a regression names the cause.
    places = points_at()
    before = reading_of(places)
    after = reading_of(shear(places, 0.30))
    found = best_angle(before, after)
    with_rotation = norm_between(rotated(before, found), after)
    without = norm_between(before, after)
    lines.append("  on the mixed move the best rotation leaves %.4e against %.4e for no rotation"
                 % (with_rotation, without))
    if with_rotation > without + 1e-9:
        lines.append("    FAIL the rotation estimate made the difference larger")
        failed += 1

    # The topologies have to actually differ, or the comparison is three names for one shape.
    counts = {}
    for shape, build in TOPOLOGIES:
        places = build()
        counts[shape] = len(set(places))
    lines.append("  distinct source states per topology: %s" % counts)
    spread = set()
    for shape, build in TOPOLOGIES:
        spread.add(tuple(sorted(set(round(depth, 6) for _point, depth in build()))))
    lines.append("  the depth sets across topologies are distinct: %s" % (len(spread) > 1))
    if len(spread) <= 1:
        lines.append("    FAIL bubbles do not differ from points in depth, so the axis is inert")
        failed += 1

    # Foam must put its sources somewhere a point cloud does not. Compared as direction sets.
    point_dirs = set(tuple(round(v, 9) for v in p) for p, _d in points_at())
    foam_dirs = set(tuple(round(v, 9) for v in p) for p, _d in foam_at())
    overlap = len(point_dirs & foam_dirs)
    lines.append("  foam directions shared with the point cloud: %d of %d"
                 % (overlap, len(foam_dirs)))
    if overlap > len(foam_dirs) // 2:
        lines.append("    FAIL foam is mostly the point cloud, so it is not a distinct topology")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="deformation a rigid motion cannot explain")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--exact", action="store_true",
                        help="which nulls are exactly zero rather than merely small")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.exact:
        sys.exit(_exact())
    sys.exit(_report())
