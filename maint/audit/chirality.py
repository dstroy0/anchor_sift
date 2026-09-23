"""A counter-rotating arm: read the same state through both handednesses and difference them.

The golden placement winds one way. Index k sits at height 1 - 2(k + 0.5)/n and longitude k gamma,
so the arm is a helix with a handedness, and every reading taken through it inherits that
handedness. A second arm winding the other way - longitude MINUS k gamma, same heights - reads the
same state through the mirror.

If the object has no chirality the two readings are mirror images with identical statistics, and
their difference is zero up to the format. Any difference is handedness in the data.

WHY THIS IS THE RIGHT PLACE TO LOOK

SHA-256 is chiral by construction and it is not subtle about it. Every rotation in the round
function turns the same way:

    Sigma0 = ROTR2  xor ROTR13 xor ROTR22
    Sigma1 = ROTR6  xor ROTR11 xor ROTR25

Six rotations, all rightward, no leftward rotation anywhere in the design. The message schedule's
spreads are the same. So the function has a handedness in its transport, and the question is whether
that handedness survives into the boundary reading or is destroyed by the mixing.

Torsion is the statistic that can answer it, because torsion is itself chiral: it measures twist,
and twist has a sign. Deflection cannot - it is a magnitude and mirror-blind by construction, which
makes it the internal control. A reading where deflection matches and torsion differs is chirality;
one where both differ is a bug in the placement.

    python maint/audit/chirality.py
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "examples", "00_blob_viz_tools"))
sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))

import boundary_read
import state_deflection

GOLDEN = (3.0 - math.sqrt(5.0)) * math.pi


def helix_place(count, handed):
    """The golden placement, wound either way. handed is +1 for the tree's arm, -1 for its mirror.

    Heights are identical between the two; only the direction of the longitude advance changes. That
    keeps every other property - no seam, no pole pile, even coverage - exactly as it was, so a
    difference between the readings cannot be blamed on the placement being worse one way round.
    """
    out = []
    for k in range(count):
        height = 1.0 - 2.0 * (k + 0.5) / float(count)
        around = (handed * k * GOLDEN) % (2.0 * math.pi)
        flat = math.sqrt(max(0.0, 1.0 - height * height))
        out.append((flat * math.cos(around), height, flat * math.sin(around)))
    return out


def phase_residual(right_phases, left_phases):
    """How far the mirror's phases are from being the exact negation of the arm's.

    Reflecting a point set through a plane sends every longitude to its negative, and for real data
    that sends each coefficient to its conjugate, so the phases negate. That is a GEOMETRIC identity
    and it holds for any lit set whatever. So this residual is expected to be zero to the format's
    floor, and a nonzero one would mean the placement is wrong rather than that the data is handed.
    """
    total = 0.0
    scale = 0.0
    for key, phase in right_phases.items():
        other = left_phases.get(key)
        if other is None:
            continue
        gap = phase + other                       # zero when the mirror negates exactly
        while gap > math.pi:
            gap -= 2.0 * math.pi
        while gap < -math.pi:
            gap += 2.0 * math.pi
        total += abs(gap)
        scale += abs(phase)
    return total / (scale if scale > 0 else 1.0)


def read_through(points, live, top):
    angles = boundary_read.as_angles(points)
    table = boundary_read.complex_coefficients(angles, live, top)
    return (boundary_read.deflection(table, top), boundary_read.torsion(table, top))


def main():
    parser = argparse.ArgumentParser(description="Counter-rotating arm, chirality test.")
    parser.add_argument("--top", type=int, default=12)
    given = parser.parse_args()

    right = helix_place(256, +1)
    left = helix_place(256, -1)
    top = given.top

    print("  256 points, degree %d, two arms of opposite handedness over identical heights" % top)
    print()
    print("=" * 76)
    print("  CONTROL: a state with no handedness must read the same both ways")
    print("=" * 76)
    print()
    import random
    rng = random.Random(0xC417)
    flat_live = [index for index in range(256) if rng.getrandbits(1)]
    d_right, t_right = read_through(right, flat_live, top)
    d_left, t_left = read_through(left, flat_live, top)
    gap_d = sum(abs(d_right[l] - d_left[l]) for l in range(top + 1))
    gap_t = phase_residual(t_right, t_left)
    scale_d = sum(abs(v) for v in d_right) or 1.0
    scale_t = 1.0
    print("    random bits, deflection difference   %.3e of its own scale" % (gap_d / scale_d))
    print("    random bits, phase residual from exact negation  %.3e" % gap_t)
    print()
    print("    Deflection is a magnitude and is mirror-blind, so its difference is the floor the")
    print("    format imposes. Torsion has a sign and need not match even here.")

    print()
    print("=" * 76)
    print("  SHA-256 STATES, ROUND BY ROUND")
    print("=" * 76)
    print()
    block = [0x80000000] + [0] * 15
    states = state_deflection.states_of(block)
    print("    round   deflection gap    torsion gap     verdict")
    chiral_rounds = 0
    for step in (1, 4, 8, 12, 16, 24, 32, 48, 64):
        live = state_deflection.lit_of(states[step])
        d_right, t_right = read_through(right, live, top)
        d_left, t_left = read_through(left, live, top)
        gap_d = sum(abs(d_right[l] - d_left[l]) for l in range(top + 1))
        gap_t = phase_residual(t_right, t_left)
        scale_d = sum(abs(v) for v in d_right) or 1.0
        scale_t = 1.0
        rel_d = gap_d / scale_d
        rel_t = gap_t
        # Deflection must match: it is mirror-blind. If it does not, the placement is wrong and the
        # torsion reading means nothing.
        if rel_d > 1e-9:
            verdict = "PLACEMENT FAULT"
        elif rel_t > 1e-6:
            verdict = "handed"
            chiral_rounds += 1
        else:
            verdict = "mirror-symmetric"
        print("    %5d   %.6e    %.6e   %s" % (step, rel_d, rel_t, verdict))

    print()
    print("=" * 76)
    print("  READING")
    print("=" * 76)
    print()
    print("    SHA-256 uses six rightward rotations and no leftward one, so the transport is")
    print("    chiral by design. Whether that reaches the boundary is what the torsion column")
    print("    answers, and the deflection column is the control that says the two arms are")
    print("    otherwise identical.")
    print()
    if chiral_rounds:
        print("    %d of the sampled rounds read differently through the mirror. The handedness of" % chiral_rounds)
        print("    the round function survives into the boundary, and a single-handed arm has been")
        print("    reading half of something.")
    else:
        print("    No round reads differently through the mirror at this degree. The reading is")
        print("    mirror-symmetric even though the function is not, which means the harmonic")
        print("    magnitudes discard the handedness the rotations carry.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
