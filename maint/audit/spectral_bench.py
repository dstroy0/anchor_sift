"""Spectral bench: what the reading keeps when the observer moves, and what it only appears to keep.

A previous framing here separated the per-degree power from the phases and treated them as
independent - magnitude invariant, phase observer-dependent. That split is clean only on the
one-parameter subgroup of rotations about the reading axis, where

    a_lm  ->  a_lm times e^(-i m alpha)

is a pure phase shift and every per-order magnitude survives untouched. Under a GENERAL rotation it
is false: the coefficients mix,

    a_lm  ->  sum over m' of D^l_(m'm)(R) times a_lm'

so magnitude redistributes across orders inside a degree, and only the SUM of squared magnitudes
over m is preserved. Reporting that sum and calling it the invariant hides the mixing, because
summing over m is exactly the operation that makes the mixing invisible.

So this bench reports both, side by side, and never one without the other:

    P_l           sum over m of |a_lm|^2, which must not move under any rotation
    the spread    how far the individual |a_lm| move within the degree, which must

A reading where both are flat is not measuring general rotations - it is sweeping the axis and
calling it a sweep. A reading where P_l moves is a reading that does not realise the Wigner
structure, at that rank or that placement.

    python maint/audit/spectral_bench.py
    python maint/audit/spectral_bench.py --top 10 --steps 24
"""

import argparse
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "examples", "00_blob_viz_tools"))
sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))

import boundary_read
import state_deflection


def turn_axis(points, angle):
    """Rotation about the reading axis: the trivial case, kept as the internal control."""
    around = math.cos(angle), math.sin(angle)
    out = []
    for x, y, z in points:
        out.append((x * around[0] - z * around[1], y, x * around[1] + z * around[0]))
    return out


def turn_general(points, yaw, pitch, roll):
    """A general rotation, composed of three axis turns so it reaches all of SO(3)."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)
    out = []
    for x, y, z in points:
        x1, z1 = x * cy - z * sy, x * sy + z * cy
        y2, z2 = y * cp - z1 * sp, y * sp + z1 * cp
        x3, y3 = x1 * cr - y2 * sr, x1 * sr + y2 * cr
        out.append((x3, y3, z2))
    return out


def spectrum(points, live, top):
    """Per-degree power and the per-order magnitudes it is built from, kept separate."""
    angles = boundary_read.as_angles(points)
    table = boundary_read.complex_coefficients(angles, live, top)
    power = [0.0] * (top + 1)
    orders = {}
    for (degree, order), (real, imaginary) in table.items():
        size = (real * real) + (imaginary * imaginary)
        weight = 1.0 if order == 0 else 2.0
        power[degree] += weight * size
        orders[(degree, order)] = math.sqrt(size)
    return power, orders


def sweep(points, live, top, steps, general, rng):
    """Read the same state from `steps` observer positions and collect both quantities."""
    powers = []
    order_tracks = {}
    for step in range(steps):
        if general:
            moved = turn_general(points, rng.uniform(0, 2 * math.pi),
                                 rng.uniform(0, math.pi), rng.uniform(0, 2 * math.pi))
        else:
            moved = turn_axis(points, (step / float(steps)) * 2.0 * math.pi)
        power, orders = spectrum(moved, live, top)
        powers.append(power)
        for key, value in orders.items():
            order_tracks.setdefault(key, []).append(value)
    return powers, order_tracks


def band_of(values):
    """Relative band width: how far a quantity moved across the sweep, against its own size."""
    top_value, low = max(values), min(values)
    middle = sum(values) / len(values)
    return (top_value - low) / (abs(middle) if middle else 1.0)


def report(name, powers, tracks, top):
    print()
    print("    %s" % name)
    print("      degree   P_l band          widest |a_lm| band within that degree")
    worst_power = 0.0
    widest_order = 0.0
    for degree in range(top + 1):
        column = [row[degree] for row in powers]
        if max(column) <= 0:
            continue
        power_band = band_of(column)
        worst_power = max(worst_power, power_band)
        inside = [band_of(values) for (d, _), values in tracks.items()
                  if d == degree and max(values) > 0]
        order_band = max(inside) if inside else 0.0
        widest_order = max(widest_order, order_band)
        print("      %6d   %.6e      %.6e" % (degree, power_band, order_band))
    return worst_power, widest_order


def main():
    parser = argparse.ArgumentParser(description="Spectral invariance under a moving observer.")
    parser.add_argument("--top", type=int, default=8)
    parser.add_argument("--steps", type=int, default=16)
    given = parser.parse_args()

    points = boundary_read.golden_place(256)
    block = [0x80000000] + [0] * 15
    live = state_deflection.lit_of(state_deflection.states_of(block)[32])
    rng = random.Random(0x5BEC)

    print("  256 points, degree %d, %d observer positions, SHA state after 32 rounds"
          % (given.top, given.steps))
    print()
    print("=" * 78)
    print("  CONTROL: rotation about the reading axis, where the split IS clean")
    print("=" * 78)
    powers, tracks = sweep(points, live, given.top, given.steps, False, rng)
    axis_power, axis_order = report("about the axis", powers, tracks, given.top)
    print()
    print("      Both flat is expected here and proves nothing: a z-rotation multiplies each")
    print("      coefficient by a phase and touches no magnitude at all.")

    print()
    print("=" * 78)
    print("  THE REAL SWEEP: general rotations, where the coefficients mix")
    print("=" * 78)
    powers, tracks = sweep(points, live, given.top, given.steps, True, rng)
    gen_power, gen_order = report("general SO(3)", powers, tracks, given.top)

    print()
    print("=" * 78)
    print("  READING")
    print("=" * 78)
    print()
    print("    widest P_l band, about the axis      %.3e" % axis_power)
    print("    widest P_l band, general rotations   %.3e" % gen_power)
    print("    widest |a_lm| band, about the axis   %.3e" % axis_order)
    print("    widest |a_lm| band, general          %.3e" % gen_order)
    print()
    if gen_order < 1e-6:
        print("    The per-order magnitudes did not move under general rotation, which cannot")
        print("    happen if the rotations are general. The sweep is not reaching SO(3).")
    elif gen_power < 1e-9:
        print("    The coefficients mixed - per-order magnitudes moved by %.1e - and the summed" % gen_order)
        print("    power did not, to %.1e. That cancellation is the Wigner structure, and it is" % gen_power)
        print("    a real invariance rather than a quantity that had nowhere to go.")
        print()
        print("    Which is the point: P_l is invariant BECAUSE the mixing cancels, not because")
        print("    nothing moved. Reporting P_l alone shows a flat band either way and cannot")
        print("    tell those two apart.")
    else:
        print("    P_l moved by %.3e under general rotation. Either the placement is uneven at" % gen_power)
        print("    this rank or the reading does not realise the Wigner structure, and both are")
        print("    faults in the instrument rather than facts about the state.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
