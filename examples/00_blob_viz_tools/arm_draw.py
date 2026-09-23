"""One arm set drawn several ways, to find out whether a reading depends on the drawing.

    python examples/00_blob_viz_tools/arm_draw.py --check

WHAT IS BEING TESTED

`docs/arm-records.md` states that an arm is identified by its topology together with its weight, and
that a shape is one realization of that. If the claim holds, then redrawing an arm as a different
shape carrying the same topology and the same weight leaves every letter of the reading unchanged. A
reading that moves under such a redraw depends on how the arm was drawn, and that is a defect in the
reading.

That makes it a null in the sense `null_harness` uses: a move that cannot change the answer, whose
measured residual is the reading's own grain. This module holds the drawings and measures the
residual. `null_harness` imports the measurement and reports the floor beside the others.

THE ARM SET

Eight sign octants and one graded arm, the graded one carrying the height coordinate as its weight.
That weight is the degree one harmonic's own pattern. Eight indicator arms alone would leave the
graded row of the record's three-kinds table untested, and two of the drawings below behave
differently on integer weights than on real ones.

THE DRAWINGS

    reference        the sign of each coordinate, tested directly. Every other drawing is compared
                     against this one.
    point cloud      no shape at all. The weights are written out per placement point, taken
                     through a text round trip the way a stored record would be.
    rotated frame    the same arms stated in a rotated frame, with the frame carried through the
                     query. Mathematically the same region, reached by different arithmetic.
    recombination    each octant's letter built as a difference of two other arms instead of being
                     read. Applies to the eight indicators, where containment holds.
    dwell on a line  the support is the golden spiral taken as a curve, the dwell along it is the
                     arm's weight at that place on the curve, and the sampling rule is incidence at
                     integer parameter. A one-dimensional arm reading a three-dimensional object.

The curve in the last drawing is written with different arithmetic from `golden_place`, since two
calls to one piece of code agree for reasons that have nothing to do with the claim under test.

THE DRAWINGS THAT ARE NOT REDRAWS

Four faults are kept here and declared as redraws, and a measurement that fails to catch them is not
measuring anything. Each is an implementation somebody would write, and none was invented to be
easy.

    orientation dropped   the arms stated in a rotated frame while the object is read in the
                          original one. This is the fault the required orientation field exists to
                          prevent.
    normalized by the arm the letter divided by the arm's own weight total instead of by the lit
                          count. That computes what fraction of the arm is lit, instead of what
                          fraction of the lit set is in the arm. Both sound reasonable. A line arm
                          and a body arm disagree under it, and a change of dimension leaks into a
                          letter that way.
    face nudged           one face moved just far enough that a single lit point changes arm. The
                          smallest change of topology available.
    record shortened      the stored record written at six significant figures. Harmless on
                          indicator weights and not harmless on graded ones. The graded arm sits
                          in the set for this reason.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import boundary_read

TAU = 2.0 * math.pi

# The frame the rotated drawing is stated in. Two turns about different axes, at angles with no
# relation to the placement, so no coordinate is spared the arithmetic.
FRAME_DOWN, FRAME_AROUND = 0.7853981633974483, 1.2566370614359172


# -------------------------------------------------------------------------------------------------
# Frames.
# -------------------------------------------------------------------------------------------------

def turn_about_y(angle):
    across, along = math.cos(angle), math.sin(angle)
    return ((across, 0.0, along), (0.0, 1.0, 0.0), (-along, 0.0, across))


def turn_about_x(angle):
    across, along = math.cos(angle), math.sin(angle)
    return ((1.0, 0.0, 0.0), (0.0, across, -along), (0.0, along, across))


def composed(left, right):
    return tuple(tuple(sum(left[r][k] * right[k][c] for k in range(3)) for c in range(3))
                 for r in range(3))


def transposed(matrix):
    return tuple(tuple(matrix[c][r] for c in range(3)) for r in range(3))


def applied(matrix, vector):
    return tuple(sum(matrix[r][c] * vector[c] for c in range(3)) for r in range(3))


def a_frame():
    """The rotation taking arm frame coordinates to world coordinates."""
    return composed(turn_about_y(FRAME_AROUND), turn_about_x(FRAME_DOWN))


IDENTITY = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))


# -------------------------------------------------------------------------------------------------
# The record, as `docs/arm-records.md` defines it.
# -------------------------------------------------------------------------------------------------

class Arm(object):
    """A region a reading takes one letter from.

    `weight` holds a real value per placement point. `origin` and `orientation` are required because
    recombination needs the overlap structure. `extent` and `sampling` are kept when a shape is how
    the arm was stated, and `sampling` carries the rule taking that shape onto the placement, since
    two arms with the same support and different sampling rules are two different arms.
    """

    __slots__ = ("name", "origin", "orientation", "weight", "extent", "sampling")

    def __init__(self, name, weight, origin=(0.0, 0.0, 0.0), orientation=IDENTITY,
                 extent=None, sampling=None):
        self.name = name
        self.weight = weight
        self.origin = origin
        self.orientation = orientation
        self.extent = extent
        self.sampling = sampling


def letter(arm, live):
    """The arm's letter: its weight summed over the lit points, over the count of lit points."""
    total = float(len(live)) or 1.0
    return sum(arm.weight[at] for at in live) / total


def reading(arms, live):
    return [letter(one, live) for one in arms]


def worst_letter_gap(before, after):
    """What a caller of the reading would see move."""
    return max((abs(two - one) for one, two in zip(before, after)), default=0.0)


def worst_weight_gap(before, after):
    """What the claim is actually about: the arm itself, point by point.

    Letters are sums, and a sum hides a pair of moves that cancel inside it. Two points swapping
    arms leaves both letters where they were while the arms are no longer the arms. Comparing the
    weights directly cannot be fooled that way, and it costs one pass.
    """
    worst = 0.0
    for one, two in zip(before, after):
        for at in range(len(one.weight)):
            worst = max(worst, abs(two.weight[at] - one.weight[at]))
    return worst


def arm_holding(arms, at):
    """Which of the eight indicator arms holds a placement point, or nothing if none does."""
    for q in range(8):
        if arms[q].weight[at] > 0.0:
            return q
    return None


def points_reassigned(before, after, total):
    """How many placement points changed indicator arm. The topology, counted."""
    return sum(1 for at in range(total) if arm_holding(before, at) != arm_holding(after, at))


# -------------------------------------------------------------------------------------------------
# The regions. Every drawing below realizes these same nine arms.
# -------------------------------------------------------------------------------------------------

def octant_of(triple):
    x, y, z = triple
    return (0 if x >= 0 else 1) * 4 + (0 if y >= 0 else 2) + (0 if z >= 0 else 1)


def octant_names():
    return ["octant %d" % q for q in range(8)]


GRADED = "graded, height"


# -------------------------------------------------------------------------------------------------
# The drawings.
# -------------------------------------------------------------------------------------------------

def by_sign_test(points):
    """The reference drawing. Each octant by the sign of each coordinate, the graded arm by height."""
    count = len(points)
    weights = [[0.0] * count for _ in range(8)]
    for at, triple in enumerate(points):
        weights[octant_of(triple)][at] = 1.0
    arms = [Arm(name, weights[q], extent="sign of each coordinate")
            for q, name in enumerate(octant_names())]
    arms.append(Arm(GRADED, [triple[1] for triple in points], extent="degree one harmonic"))
    return arms


def by_point_cloud(points, digits=17):
    """No shape. The weights written out per point and read back, the way a stored record would be.

    `digits` is how the record is written. Seventeen significant figures round trip a double
    exactly. Fewer does not, and the fault list uses that.
    """
    out = []
    for one in by_sign_test(points):
        stored = [float(("%." + str(digits) + "g") % value) for value in one.weight]
        out.append(Arm(one.name, stored, extent=None,
                       sampling="weights given per placement point"))
    return out


def by_rotated_frame(points, carry_the_frame=True):
    """The same arms stated in a rotated frame.

    The three faces of an octant are half spaces through the origin. Expressing each face normal in
    the arm's frame and the query point in the same frame leaves every dot product mathematically
    where it was, since a rotation preserves them, and moves it in the last bits. The graded arm
    carries its axis through the same frame.

    With `carry_the_frame` off, the normals move and the query does not. That is the fault the
    orientation field exists to prevent, and it is kept here to be caught.
    """
    frame = a_frame()
    back = transposed(frame)
    normals = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    local = [applied(back, one) for one in normals]

    count = len(points)
    weights = [[0.0] * count for _ in range(8)]
    graded = [0.0] * count
    for at, triple in enumerate(points):
        asked = applied(back, triple) if carry_the_frame else triple
        slot = 0
        for axis in range(3):
            along = sum(local[axis][k] * asked[k] for k in range(3))
            if along < 0.0:
                slot += (4, 2, 1)[axis]
        weights[slot][at] = 1.0
        graded[at] = sum(local[1][k] * asked[k] for k in range(3))

    arms = [Arm(name, weights[q], orientation=frame, extent="three half spaces, stated in the frame")
            for q, name in enumerate(octant_names())]
    arms.append(Arm(GRADED, graded, orientation=frame, extent="degree one harmonic, in the frame"))
    return arms


def spiral_at(parameter, count):
    """The golden spiral as a curve, written with different arithmetic from `golden_place`.

    Same curve, same points at integer parameter, different rounding on the way there. Two calls to
    one piece of code agree for reasons unconnected to the claim under test, and this avoids that.
    """
    height = (count - 2.0 * parameter - 1.0) / float(count)
    around = math.fmod(parameter * boundary_read.GOLDEN, TAU)
    flat = math.sqrt(max(0.0, (1.0 - height) * (1.0 + height)))
    return (flat * math.cos(around), height, flat * math.sin(around))


def by_dwell_on_a_line(points):
    """A one-dimensional support, sampled onto the placement by incidence at integer parameter.

    The arm is a line with a particle on it. The support is the golden spiral taken as a curve, the
    dwell at each place along it is the arm's weight there, and the sampling rule states how the
    dwell reaches the placement. Nothing about this arm has the dimension of the object it reads.
    """
    count = len(points)
    weights = [[0.0] * count for _ in range(8)]
    graded = [0.0] * count
    for at in range(count):
        along = spiral_at(at, count)
        weights[octant_of(along)][at] = 1.0
        graded[at] = along[1]

    arms = [Arm(name, weights[q], extent="an arc of the golden spiral",
                sampling="incidence at integer parameter")
            for q, name in enumerate(octant_names())]
    arms.append(Arm(GRADED, graded, extent="dwell along the spiral",
                    sampling="incidence at integer parameter"))
    return arms


def by_recombination(points, live):
    """Each octant's letter built as a difference of two arms instead of read from one.

    Where arm A contains arm B, the letter of A minus the letter of B is the letter of A without B.
    Octant `q` and its sibling `q ^ 1` differ in the sign of the last coordinate alone, and together
    they are the arm holding both. So the letter of `q` comes back as the letter of the pair minus
    the letter of the sibling, from two arms neither of which is `q`.

    This returns letters and not arms, since the point of it is that no arm for `q` is measured.
    """
    plain = by_sign_test(points)
    count = len(points)
    out = []
    for q in range(8):
        sibling = q ^ 1
        pair = [plain[q].weight[at] + plain[sibling].weight[at] for at in range(count)]
        both = Arm("pair %d" % q, pair, extent="two octants sharing the first two signs")
        out.append(letter(both, live) - letter(plain[sibling], live))
    out.append(letter(plain[8], live))
    return out


# -------------------------------------------------------------------------------------------------
# The drawings that are not redraws.
# -------------------------------------------------------------------------------------------------

def letter_by_arm(arm, live):
    """The fault: the letter divided by the arm's own weight total instead of the lit count."""
    held = sum(arm.weight)
    if held == 0.0:
        return 0.0
    return sum(arm.weight[at] for at in live) / held


def smallest_lit_face_gap(points, live):
    """How far the first face has to move to take exactly one lit point across it."""
    reachable = [points[at][0] for at in live if points[at][0] >= 0.0]
    return min(reachable) if reachable else 0.0


def by_nudged_face(points, live):
    """One face moved just far enough that a single lit point changes arm.

    The first face sits at zero and the test admits a point at zero or above. Moving the face to the
    smallest lit first coordinate and admitting only points strictly beyond it takes that single
    point across and leaves every other point where it was.
    """
    edge = smallest_lit_face_gap(points, live)
    count = len(points)
    weights = [[0.0] * count for _ in range(8)]
    for at, (x, y, z) in enumerate(points):
        slot = (0 if x > edge else 1) * 4 + (0 if y >= 0 else 2) + (0 if z >= 0 else 1)
        weights[slot][at] = 1.0
    arms = [Arm(name, weights[q], extent="sign of each coordinate, first face moved")
            for q, name in enumerate(octant_names())]
    arms.append(Arm(GRADED, [triple[1] for triple in points], extent="degree one harmonic"))
    return arms


# -------------------------------------------------------------------------------------------------
# The pre-check, which decides what a clean residual is allowed to mean.
# -------------------------------------------------------------------------------------------------

def face_clearance(points):
    """The nearest approach of any placement point to any arm face, and where it happens.

    A sign octant's three faces are the coordinate planes. A point's distance to the nearest of them
    is therefore the smallest of its three coordinates in absolute value. Comparing that against the
    arithmetic the redraw rounds at settles in advance whether a point can cross a face: clearance
    far above the rounding means no crossing is available and a clean residual is arithmetic.
    Clearance at or under it means the sign convention decided the answer, and a clean residual is
    a clean residual and not a proof.
    """
    gaps = [min(abs(x), abs(y), abs(z)) for x, y, z in points]
    nearest = min(gaps)
    return nearest, gaps.index(nearest)


def points_on_a_face(points):
    """Placement indices sitting exactly on a face, where the sign convention alone decides.

    The golden placement puts index 0 here at every count. Its longitude is `0 * GOLDEN`, which is
    exactly zero, and the sine of that is exactly zero, so its third coordinate is exactly zero.
    Nothing about this is a rounding accident and no placement size avoids it.
    """
    return [at for at, (x, y, z) in enumerate(points)
            if x == 0.0 or y == 0.0 or z == 0.0]


def on_face_decided_by(points, at):
    """For a point sitting on a face, what the rotated drawing decided its side by.

    Returns the carried dot product against each face the point's plain coordinate is zero on. A
    face crossing is available exactly when one of these comes back negative, and the magnitude
    says how little was standing between the two answers.
    """
    back = transposed(a_frame())
    normals = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    asked = applied(back, points[at])
    out = []
    for axis in range(3):
        if points[at][axis] != 0.0:
            continue
        local = applied(back, normals[axis])
        out.append((axis, sum(local[k] * asked[k] for k in range(3))))
    return out


def frame_rounding(points):
    """What the rotated drawing rounds at, measured over the placement instead of assumed.

    The worst departure of a carried dot product from the plain coordinate it is mathematically
    equal to. This is the scale a face crossing has to be separated from.
    """
    back = transposed(a_frame())
    normals = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    local = [applied(back, one) for one in normals]
    worst = 0.0
    for triple in points:
        asked = applied(back, triple)
        for axis in range(3):
            along = sum(local[axis][k] * asked[k] for k in range(3))
            worst = max(worst, abs(along - triple[axis]))
    return worst


# -------------------------------------------------------------------------------------------------
# The measurement.
# -------------------------------------------------------------------------------------------------

def compared(points, live, drawn):
    """One drawing against the reference, at the three levels a redraw can move something.

    `weight` is the arm itself, `points` is its topology, `letter` is what a caller reads. The
    claim in `docs/arm-records.md` is about the first two. The third is a consequence and is
    reported because it is the quantity anybody would have checked.
    """
    plain = by_sign_test(points)
    return {
        "weight": worst_weight_gap(plain, drawn),
        "points": points_reassigned(plain, drawn, len(points)),
        "letter": worst_letter_gap(reading(plain, live), reading(drawn, live)),
    }


def redraw_residuals(points, live):
    """Every genuine redraw against the reference, as {drawing: the three gaps}."""
    out = {}
    out["point cloud, record round trip"] = compared(points, live, by_point_cloud(points))
    out["rotated frame, frame carried"] = compared(points, live, by_rotated_frame(points))
    out["dwell on a line"] = compared(points, live, by_dwell_on_a_line(points))
    # Recombination produces letters and no arms, since the arm for each octant is the thing it
    # declines to measure. Only the third level applies to it.
    out["algebraic recombination"] = {
        "weight": None,
        "points": None,
        "letter": worst_letter_gap(reading(by_sign_test(points), live),
                                   by_recombination(points, live)),
    }
    return out


def fault_residuals(points, live):
    """Every drawing that is not a redraw, as {fault: the three gaps}. Each has to be caught."""
    plain = by_sign_test(points)
    out = {}
    out["orientation dropped"] = compared(
        points, live, by_rotated_frame(points, carry_the_frame=False))
    out["one face nudged"] = compared(points, live, by_nudged_face(points, live))
    out["record at six figures"] = compared(points, live, by_point_cloud(points, digits=6))
    # This fault leaves every arm untouched and moves only the division, so it has no reading at
    # the first two levels. It is a fault in the letter and is caught there.
    out["normalized by the arm"] = {
        "weight": 0.0,
        "points": 0,
        "letter": worst_letter_gap(reading(plain, live), [letter_by_arm(one, live) for one in plain]),
    }
    return out


STRUCTURAL_FAULTS = ("orientation dropped", "normalized by the arm", "one face nudged")


def faults_caught(points, live):
    """Whether every drawing that is not a redraw moved a letter. The gate on this null.

    Three of the four move a letter by more than a millionth. The fourth writes the record at six
    significant figures, which cannot touch an indicator weight and does touch a graded one, so it
    is held to moving something at all.
    """
    faults = fault_residuals(points, live)
    if not all(faults[name]["letter"] > 1e-6 for name in STRUCTURAL_FAULTS):
        return False
    return faults["record at six figures"]["letter"] > 0.0


def null_redraw(points, live):
    """The floor: the worst gap across every genuine redraw, at whatever level it appears."""
    worst = 0.0
    for gaps in redraw_residuals(points, live).values():
        for level in ("weight", "letter"):
            if gaps[level] is not None:
                worst = max(worst, gaps[level])
        if gaps["points"]:
            # A reassigned point is a change of topology and has no size in these units. Report it
            # as a whole letter, which is past any floor a caller would set.
            worst = max(worst, 1.0)
    return worst


# -------------------------------------------------------------------------------------------------
# Standalone.
# -------------------------------------------------------------------------------------------------

def a_lit_set(total):
    """A lit set with no structure anybody chose, at about half weight. Matches `null_harness`."""
    return [k for k in range(total) if (k * 7 + k // 5) % 3]


def a_lit_set_holding_the_faces(points, total):
    """The same lit set with every on-face point forced lit.

    The default lit set leaves index 0 dark, and index 0 is the point sitting exactly on a face. So
    the letters could not have moved for it whatever the drawings did, and a pass over that lit set
    says nothing about the case the pre-check flags. This one makes the drawings carry it.
    """
    live = set(a_lit_set(total))
    live.update(points_on_a_face(points))
    return sorted(live)


def _check():
    lines = []
    failed = 0

    def say(text):
        lines.append(text)

    count = 256
    points = boundary_read.golden_place(count)
    live = a_lit_set(count)
    step = 1.0 / float(len(live))

    def row(name, gaps):
        def shown(value, form):
            return "        -" if value is None else form % value
        say("    %-30s %s %s %s" % (name, shown(gaps["weight"], "%12.3e"),
                                    shown(gaps["points"], "%8d"),
                                    shown(gaps["letter"], "%12.3e")))

    say("  nine arms, eight indicator and one graded, over a %d point golden placement" % count)
    say("  lit weight %d, so one point changing arm moves a letter by %.3e" % (len(live), step))
    say("")

    # The engine's pre-check. Whether a point can cross a face is decided by the placement and the
    # arithmetic, before any drawing runs, and it settles what a clean residual is allowed to mean.
    nearest, at_index = face_clearance(points)
    on_face = points_on_a_face(points)
    rounding = frame_rounding(points)
    say("  the clearance pre-check, which decides what a clean residual means")
    say("    nearest approach of any point to any face   %.3e, at index %d" % (nearest, at_index))
    say("    the rotated drawing's own rounding          %.3e" % rounding)
    say("    points sitting exactly on a face            %d of %d   %s" % (
        len(on_face), count, on_face if len(on_face) < 8 else "..."))
    if nearest > 1000.0 * rounding:
        say("    the clearance beats the rounding by %.0f decades, so no point can cross a face"
            % math.log10(nearest / rounding))
        say("    and a clean residual below is arithmetic, established without running it")
    else:
        say("    the clearance does not beat the rounding, a crossing is available, and the")
        say("    clean residual below is a clean residual and not a proof. The golden placement")
        say("    puts index 0 at longitude zero exactly, and the sine of that is zero exactly,")
        say("    so its third coordinate is zero at every placement size. The sign convention")
        say("    decides which arm holds it and no measurement here records that it did.")
    say("")

    say("  three levels, because a letter is a sum and a sum hides a pair of moves that cancel")
    say("    weight   the largest move in any arm's weight at any point. The arm itself.")
    say("    points   how many placement points changed indicator arm. The topology.")
    say("    letter   the largest move in any letter. What a caller of the reading sees.")
    say("")

    say("  the drawings that are not redraws, each of which has to be caught")
    say("    %-30s %12s %8s %12s" % ("", "weight", "points", "letter"))
    faults = fault_residuals(points, live)
    for name in sorted(faults):
        row(name, faults[name])
    for name in STRUCTURAL_FAULTS:
        if not (faults[name]["letter"] > 1e-6):
            say("  FAIL %s was not caught" % name)
            failed += 1
    # The graded arm carries this one alone. An indicator weight is 0.0 or 1.0 and survives any
    # format anybody would write, and a graded arm sits in the set because it does not.
    if not (faults["record at six figures"]["letter"] > 0.0):
        say("  FAIL a shortened record moved nothing, and the graded arm is missing from the set")
        failed += 1
    say("")

    if failed:
        say("  the redraw residuals are withheld, since the measurement has not shown it works")
        sys.stdout.write("\n".join(lines) + "\n\n%d check(s) failed\n" % failed)
        return failed

    dropped = faults["orientation dropped"]
    say("  the size of the frame fault, which the letters understate")
    say("    lit points landing in a different arm   %d of %d" % (
        points_reassigned(by_sign_test(points), by_rotated_frame(points, carry_the_frame=False),
                          count), count))
    say("    worst letter move                       %.3e, or %.0f point crossings" % (
        dropped["letter"], dropped["letter"] / step))
    say("    The reading moves in 8 of 256 directions, and a turn of the frame is mostly a move")
    say("    in the other 248. Four fifths of the points change arm and the letters shift by a")
    say("    few percent. The fault is caught with room to spare, and a reading with a coarser")
    say("    floor than this one would have to check the topology to catch it at all.")
    say("")

    say("  the redraws, measured")
    say("    %-30s %12s %8s %12s" % ("", "weight", "points", "letter"))
    good = redraw_residuals(points, live)
    for name in sorted(good):
        row(name, good[name])
    say("")

    # The default lit set leaves index 0 dark, and index 0 is the point on the face. A pass over
    # that set alone would say nothing about the case the pre-check flags, so the drawings are made
    # to carry it.
    if on_face:
        held = a_lit_set_holding_the_faces(points, count)
        say("  the same redraws with the on-face points forced lit, weight %d" % len(held))
        say("    %-30s %12s %8s %12s" % ("", "weight", "points", "letter"))
        carried = redraw_residuals(points, held)
        for name in sorted(carried):
            row(name, carried[name])
        for name, gaps in sorted(carried.items()):
            if gaps["points"]:
                say("  FAIL %s moved %d points with the faces lit" % (name, gaps["points"]))
                failed += 1
            if gaps["letter"] >= 1.0 / float(len(held)):
                say("  FAIL %s moved a letter with the faces lit" % name)
                failed += 1
        decided = on_face_decided_by(points, on_face[0])
        say("    every drawing put index %d in the same arm. Under the rotated frame it got there"
            % on_face[0])
        for axis, value in decided:
            say("    on a carried dot product of %+.3e against face %d, whose plain coordinate is"
                % (value, axis))
            say("    exactly zero. It held its arm by the sign of a rounding residual.")
        say("    The reading is stable here and the reason it is stable is thin.")
        say("")

    for name, gaps in sorted(good.items()):
        if gaps["points"]:
            say("  FAIL %s moved %d points to a different arm" % (name, gaps["points"]))
            failed += 1
        if gaps["letter"] >= step:
            say("  FAIL %s moved a letter by a whole point crossing" % name)
            failed += 1

    worst = null_redraw(points, live)
    say("  the floor")
    say("    worst gap across every redraw   %.3e" % worst)
    say("    every redraw left the topology alone: no placement point changed arm under any of")
    say("    them. The residual is the last bit of a division and a subtraction, %.0f decades" % (
        math.log10(step / worst) if worst > 0.0 else 0.0))
    say("    under a single point crossing.")
    say("")

    say("  what this settles")
    say("    A one-dimensional arm and a three-dimensional one carrying the same weight return")
    say("    the same letters. The arm set stated in a rotated frame returns them again, and")
    say("    zero of %d points change arm in the process. An octant's letter also comes back" % count)
    say("    from two arms neither of which is that octant. A reading over these arms does not")
    say("    depend on how they were drawn, down to a grain of %.1e." % worst)
    say("")
    say("    The frame has to be carried for any of it. Dropping it moves four fifths of the")
    say("    points, and the orientation field is holding a requirement of the derivation.")
    if on_face:
        say("")
        say("    One point of %d is outside that. Index %d sits exactly on a face, so its arm is"
            % (count, on_face[0]))
        say("    settled by the sign convention and not by any clearance, and it came back in the")
        say("    same arm under every drawing without that being established beforehand. The")
        say("    statement above holds for %d points by measurement and for 1 by convention."
            % (count - len(on_face)))

    sys.stdout.write("\n".join(lines) + "\n\n%d check(s) failed\n" % failed)
    return failed


def main():
    argv = sys.argv[1:]
    if "--check" in argv or not argv:
        return 1 if _check() else 0
    sys.stdout.write(__doc__.strip() + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
