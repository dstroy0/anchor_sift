"""Measured noise floors for the boundary readings, and the proof that the measuring works.

    python examples/00_blob_viz_tools/null_harness.py --check
    python examples/00_blob_viz_tools/null_harness.py --floors

WHAT A NULL IS HERE

A null is a move that cannot change a reading, paired with the reading it cannot change. Run the
move, read before and after, and the difference is not a result. It is the instrument's own grain,
measured on the instrument, in the units the reading reports. Quantize at that grain and a move
smaller than it becomes a move the reading cannot see, which is a null permutation and not a
finding.

WHY THIS EXISTS

Thresholds in this tree were chosen and not measured. `coherence` rounds octant signatures at one
part in a million by judgment, while the true grain of integer counts over an integer weight is
nearer 1e-16, so it was ten decades coarse in the safe direction and arbitrary in both. Deflection
and torsion carried no threshold at all. `sphere_field.live_modes` takes its floor as an argument,
so every caller picks one. A floor picked by a caller is a result picked by a caller.

THE RULE THIS APPLIES TO ITSELF

A checker that has never caught its own defect is a checker nobody has tested. So before any floor
here is offered, the harness is handed a move that is not a null while being told it is one, and it
has to catch it, and it is handed a genuine null and has to stay quiet. Both run first under
`--check` and the floors are refused if either misbehaves.

WHAT EACH NULL RESTS ON

    deflection under rotation     power per degree is a magnitude, so turning the object cannot
                                  move it. Stated in `boundary_read.deflection`.
    torsion under a whole turn    a rotation by a full turn is the identity on the object.
    octant share under relabeling moving a lit point to an unlit point in the same octant leaves
                                  every octant's count alone, so the eight shares are unchanged.
    octant delta against itself   the distance from a reading to itself.
    pitch across shift amounts    the pitch is -2/(count gamma) whatever the amount, so the spread
                                  over amounts is grain. Stated in `boundary_read.screw_of`.
    spectrum power under rotation power per degree does not depend on how the sphere is oriented.
                                  Stated in `sphere_field.power`, untested until here.
    a redraw of the arms          an arm is identified by its topology and its weight, and a shape
                                  is one realization of that, so redrawing the arms as different
                                  shapes carrying the same weight cannot move a letter. Stated in
                                  `docs/arm-records.md`, measured in `arm_draw`.

The last one is the floor `live_modes` should be given instead of a guessed one, since it is the
level below which a mode's power is arithmetic and not signal.

A companion that is not a null is reported beside them: torsion recovering a known angle. A null
asks whether a reading holds still when nothing happened. A known answer asks whether it moves the
right amount when something did. A reading wants both and they are not the same measurement.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import arm_draw
import boundary_read
import sphere_field

TAU = 2.0 * math.pi

# Sizes the shipped nulls run at. Small enough to run in a second, large enough that a floor
# measured here is the floor the callers see.
RINGS, WIDTH = 8, 32
COUNT = 256
TOP = 8


# -------------------------------------------------------------------------------------------------
# Comparing two readings.
# -------------------------------------------------------------------------------------------------

def worst_relative(before, after):
    """The largest relative change across two lists, guarded where the reference is near zero."""
    worst = 0.0
    for one, two in zip(before, after):
        scale = max(1e-30, abs(one))
        worst = max(worst, abs(two - one) / scale)
    return worst


def worst_absolute(before, after):
    """The largest absolute change across two lists."""
    return max((abs(two - one) for one, two in zip(before, after)), default=0.0)


def wrapped(angle):
    """An angle folded into plus or minus half a turn, leaving a near whole turn reading as small."""
    return ((angle + math.pi) % TAU) - math.pi


# -------------------------------------------------------------------------------------------------
# The lit set the readings are taken on, and the moves that cannot change them.
# -------------------------------------------------------------------------------------------------

def a_lit_set(total):
    """A lit set with no structure anybody chose, at about half weight."""
    return [k for k in range(total) if (k * 7 + k // 5) % 3]


def rotated_by_rings(live, steps):
    """The same lit set turned about the ring axis, exactly, by moving each point along its ring."""
    out = []
    for at in live:
        ring = at // WIDTH
        out.append(ring * WIDTH + (at % WIDTH + steps) % WIDTH)
    return out


def relabelled_within_octants(points, live):
    """Each lit point moved to an unlit point in its own octant, so no octant's count changes.

    The shares are counts over a weight and both are integers, so this move has to leave all eight
    of them bit for bit identical. Any residual comes from the division and from no other source.
    """
    def octant_of(at):
        x, y, z = points[at]
        return (0 if x >= 0 else 1) * 4 + (0 if y >= 0 else 2) + (0 if z >= 0 else 1)

    lit = set(live)
    free = {}
    for at in range(len(points)):
        if at not in lit:
            free.setdefault(octant_of(at), []).append(at)

    out = []
    for at in live:
        here = free.get(octant_of(at))
        out.append(here.pop() if here else at)
    return out


def moved_across_octants(points, live, how_many):
    """A move that is NOT a null: lit points sent to unlit points in a different octant.

    Kept here deliberately. It is the known positive the harness is tested against, and it has to be
    a move of the same shape as the real null so that catching it means something.
    """
    def octant_of(at):
        x, y, z = points[at]
        return (0 if x >= 0 else 1) * 4 + (0 if y >= 0 else 2) + (0 if z >= 0 else 1)

    lit = set(live)
    free = [at for at in range(len(points)) if at not in lit]
    out = list(live)
    moved = 0
    for slot, at in enumerate(out):
        if moved >= how_many:
            break
        for candidate in free:
            if octant_of(candidate) != octant_of(at):
                out[slot] = candidate
                free.remove(candidate)
                moved += 1
                break
    return out


# -------------------------------------------------------------------------------------------------
# The nulls themselves. Each returns a residual in the units its reading reports.
# -------------------------------------------------------------------------------------------------

def null_deflection_under_rotation():
    points = boundary_read.ring_place(RINGS, WIDTH)
    angles = boundary_read.as_angles(points)
    live = a_lit_set(RINGS * WIDTH)
    base = boundary_read.deflection(boundary_read.complex_coefficients(angles, live, TOP), TOP)
    worst = 0.0
    for steps in (1, 5, 13, 31):
        table = boundary_read.complex_coefficients(angles, rotated_by_rings(live, steps), TOP)
        worst = max(worst, worst_relative(base, boundary_read.deflection(table, TOP)))
    return worst


def null_torsion_under_whole_turn():
    points = boundary_read.ring_place(RINGS, WIDTH)
    angles = boundary_read.as_angles(points)
    live = a_lit_set(RINGS * WIDTH)
    base = boundary_read.torsion(boundary_read.complex_coefficients(angles, live, TOP), TOP)
    worst = 0.0
    for turns in (1, 2, 3):
        moved = rotated_by_rings(live, turns * WIDTH)
        table = boundary_read.complex_coefficients(angles, moved, TOP)
        got = boundary_read.turn_between(base, boundary_read.torsion(table, TOP))
        if got is None:
            return float("nan")
        worst = max(worst, abs(wrapped(got)))
    return worst


def known_torsion_recovers_the_angle():
    """Not a null. The companion measurement: a known move, read back."""
    points = boundary_read.ring_place(RINGS, WIDTH)
    angles = boundary_read.as_angles(points)
    live = a_lit_set(RINGS * WIDTH)
    base = boundary_read.torsion(boundary_read.complex_coefficients(angles, live, TOP), TOP)
    worst = 0.0
    for steps in (1, 2, 5, 8, 13, 17):
        table = boundary_read.complex_coefficients(angles, rotated_by_rings(live, steps), TOP)
        got = boundary_read.turn_between(base, boundary_read.torsion(table, TOP))
        if got is None:
            return float("nan")
        worst = max(worst, abs(wrapped(got - TAU * steps / float(WIDTH))))
    return worst


def null_octant_share_under_relabeling():
    points = boundary_read.golden_place(COUNT)
    live = a_lit_set(COUNT)
    before = boundary_read.octant_share(points, live)
    after = boundary_read.octant_share(points, relabelled_within_octants(points, live))
    return worst_absolute(before, after)


def null_octant_delta_against_itself():
    points = boundary_read.golden_place(COUNT)
    share = boundary_read.octant_share(points, a_lit_set(COUNT))
    return abs(boundary_read.octant_delta(share, share))


def null_pitch_across_amounts():
    pitches = [boundary_read.screw_of(COUNT, amount)[2] for amount in (1, 3, 7, 11, 16, 25)]
    return max(pitches) - min(pitches)


def null_spectrum_power_under_rotation():
    """The floor `live_modes` should be handed, measured instead of guessed."""
    sources = [
        (1.0, 0.30, 0.7, 0.4),
        (0.6, 0.55, 1.9, 2.7),
        (1.3, 0.80, 2.5, 5.1),
    ]
    base = sphere_field.power(sphere_field.coefficients(sources, TOP, 0.0))
    worst = 0.0
    for alpha in (0.3, 1.1, 2.9, 5.7):
        turned = [(s, r, down, around + alpha) for s, r, down, around in sources]
        moved = sphere_field.power(sphere_field.coefficients(turned, TOP, 0.0))
        worst = max(worst, worst_relative(base, moved))
    return worst


def null_reading_under_a_redraw():
    """The arms drawn four ways, including one of a different dimension. Measured in `arm_draw`.

    A point cloud, a rotated frame, a letter built by subtracting two other arms, and a line with a
    dwell particle on it. Every one carries the same topology and the same weight as the sign test
    the reading normally uses, so no letter can move. `arm_draw --check` reports the levels
    separately and holds four faults against itself first.
    """
    points = boundary_read.golden_place(COUNT)
    return arm_draw.null_redraw(points, a_lit_set(COUNT))


NULLS = (
    ("deflection under rotation", "a magnitude does not turn", null_deflection_under_rotation),
    ("torsion under a whole turn", "a full turn is the identity", null_torsion_under_whole_turn),
    ("octant share under relabeling", "counts per octant unchanged", null_octant_share_under_relabeling),
    ("octant delta against itself", "a reading against itself", null_octant_delta_against_itself),
    ("pitch across shift amounts", "the pitch has no amount in it", null_pitch_across_amounts),
    ("spectrum power under rotation", "power does not depend on orientation", null_spectrum_power_under_rotation),
    ("a redraw of the arms", "shape realizes topology", null_reading_under_a_redraw),
)


# -------------------------------------------------------------------------------------------------
# Using a floor.
# -------------------------------------------------------------------------------------------------

def floors():
    """Every shipped null, measured now, as {name: residual}."""
    return dict((name, run()) for name, _, run in NULLS)


def quantize(value, floor):
    """Snap a value to its floor, so anything under the grain reads as no move at all."""
    if floor <= 0.0 or not (floor == floor):
        return value
    return round(value / floor) * floor


def is_a_move(value, floor, margin=10.0):
    """Whether a reading moved by more than its own grain, with a margin over the floor."""
    return abs(value) > margin * floor


# -------------------------------------------------------------------------------------------------
# The harness tested on itself, before any floor above is offered.
# -------------------------------------------------------------------------------------------------

def self_test():
    """A move that is not a null, and one that is. Catch the first and stay quiet on the second.

    Both are octant share moves of the same shape, one staying inside each octant and one crossing
    between them, so catching the second is about the reading and not about the two moves differing
    in some other way.
    """
    points = boundary_read.golden_place(COUNT)
    live = a_lit_set(COUNT)
    before = boundary_read.octant_share(points, live)

    broken = boundary_read.octant_share(points, moved_across_octants(points, live, 12))
    genuine = boundary_read.octant_share(points, relabelled_within_octants(points, live))

    return worst_absolute(before, broken), worst_absolute(before, genuine)


def _check():
    lines = []
    failed = 0

    def say(text):
        lines.append(text)

    say("  the harness against itself, before any floor is offered")
    caught, quiet = self_test()
    say("    a move that is not a null, declared as one   %.3e" % caught)
    say("    a move that is a null                        %.3e" % quiet)
    if not (caught > 1e-3):
        say("  FAIL the harness did not catch a move that is not a null")
        failed += 1
    if not (quiet < 1e-12):
        say("  FAIL the harness reported a genuine null as a move")
        failed += 1
    if failed:
        say("")
        say("  floors withheld, since the harness has not shown it works")
        sys.stdout.write("\n".join(lines) + "\n\n%d check(s) failed\n" % failed)
        return failed

    if quiet == 0.0:
        say("    the null returned exactly zero, so the two are separated absolutely")
    else:
        say("    the two are separated by %.1e" % (caught / quiet))

    # The redraw null carries its own known positives, since the moves that break it are moves on
    # the arms and not on the lit set. Four of them, run before its floor is offered.
    points = boundary_read.golden_place(COUNT)
    live = a_lit_set(COUNT)
    if arm_draw.faults_caught(points, live):
        say("    the redraw null caught all four of its own faults, run arm_draw --check for them")
    else:
        say("  FAIL the redraw null missed a drawing that is not a redraw")
        failed += 1
        say("")
        say("  floors withheld, since the harness has not shown it works")
        sys.stdout.write("\n".join(lines) + "\n\n%d check(s) failed\n" % failed)
        return failed
    say("")

    say("  the floors, measured")
    for name, claim, run in NULLS:
        value = run()
        if value != value:
            say("    %-30s      no reading" % name)
            say("  FAIL %s returned nothing to measure" % name)
            failed += 1
            continue
        say("    %-30s %.3e   %s" % (name, value, claim))
        if value > 1e-6:
            say("  FAIL %s is not behaving as a null" % name)
            failed += 1
    say("")

    say("  a known answer, which is a different question from a null")
    known = known_torsion_recovers_the_angle()
    say("    torsion recovers a known angle to %.3e radians" % known)
    if not (known < 1e-9):
        say("  FAIL torsion did not recover the angle it was given")
        failed += 1
    say("")

    say("  what the floors are for")
    grain = null_octant_share_under_relabeling()
    weight = len(a_lit_set(COUNT))
    if grain == 0.0:
        # Reporting a small number here would be inventing a floor the measurement did not find,
        # and stopping that mistake is why this harness exists. The octant reading has no continuum of
        # small moves: a share is a count over a weight and both are integers, so the smallest move
        # it can register is one point changing octant.
        say("    the octant grain is exactly zero, so there is no small residual to allow for")
        say("    its smallest registrable move is one point crossing, or %.3e of a share"
            % (1.0 / weight))
        say("    coherence rounds at 1.0e-06, far under a move this reading can make at all")
    else:
        say("    a share moving by less than %.3e is a null permutation" % grain)
    say("    live_modes takes its floor as an argument, so hand it the spectrum figure above")

    sys.stdout.write("\n".join(lines) + "\n\n%d check(s) failed\n" % failed)
    return failed


def main():
    argv = sys.argv[1:]
    if "--floors" in argv:
        for name, value in floors().items():
            sys.stdout.write("%-32s %.6e\n" % (name, value))
        return 0
    if "--check" in argv or not argv:
        return 1 if _check() else 0
    sys.stdout.write(__doc__.strip() + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
