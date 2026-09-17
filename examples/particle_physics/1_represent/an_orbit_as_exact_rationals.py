#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-1-002
#
# The Bohr orbit of one electron as exact rationals, and a trajectory reproduces with no rounding.
#
#   Usage:  python examples/particle_physics/1_represent/an_orbit_as_exact_rationals.py [Z | symbol ...]
#
# A hydrogen-like ion is one electron on a nucleus of charge Z. Bohr quantizes its angular momentum at
# an integer multiple of hbar, and the orbit that follows has radius n^2/Z in units of the Bohr radius
# and energy -Z^2/n^2 in units of the Rydberg. Both are exact rationals: an integer over an integer,
# with nothing to round. The quantum number n is an exact integer, so two orbits n and n+1 differ by
# (2n+1)/Z exactly and never merge, however large n gets. That is the trajectory reproduced with the
# infinite discrimination exact arithmetic gives, and it is why a float, which loses the gap between
# large orbits, is the wrong tool for it.
#
# The arithmetic here is integer rationals done by hand, add, subtract, multiply and compare, the host
# stand-in for the fixed-width limb integers in no_rounding on the device arm. No float and no bignum
# library sits in the path, the same discipline representation/exact.py keeps for decimal coordinates.
#
# Everything is carried in the natural units, the Bohr radius and the Rydberg, so no measured constant
# enters and no digit is approximate. The absolute size of an orbit in meters, and any comparison to a
# measured spectral line, needs the Rydberg constant, which is measured and cited, and that is the
# oracle stage and not this one. What is exact and physical-constant-free is the shape: the ratios.
# Within one spectral series the constant cancels, and a line ratio is a pure rational the model
# predicts with no measurement in it, for a later oracle to hold a measured ratio against.

import io
import os
import sys

# Walk up to the repository instead of counting directories to it, and stop at the filesystem root.
# A directory that is its own parent would otherwise loop the walk forever. Counting is what broke
# every path in this tree the last time anything moved.
ROOT = os.path.dirname(os.path.abspath(__file__))
while ROOT != os.path.dirname(ROOT) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
if not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    raise SystemExit("could not find src/engine above %s" % os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.atom import element  # noqa: E402

# Principal numbers detailed for the hydrogen orbits, and the Balmer series lines read as ratios.
SHELLS = (1, 2, 3, 4, 5, 6)
BALMER = (3, 4, 5, 6)


def greatest_common_divisor(left, right):
    """The greatest common divisor of two non-negative integers, by Euclid, native arithmetic only.

    Written out and not imported, because this subject does its own integer arithmetic and pulls in no
    math library.
    """
    while right:
        left, right = right, left % right
    return left


def rational(numerator, denominator):
    """An exact rational reduced to lowest terms, denominator kept positive. Raises on a zero one."""
    if denominator == 0:
        raise ValueError("a rational with denominator zero")
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    divisor = greatest_common_divisor(abs(numerator), denominator) or 1
    return (numerator // divisor, denominator // divisor)


def minus(left, right):
    """Left rational less right, exactly."""
    return rational(left[0] * right[1] - right[0] * left[1], left[1] * right[1])


def over(left, right):
    """Left rational divided by right, exactly. Raises where right is zero."""
    return rational(left[0] * right[1], left[1] * right[0])


def as_text(value):
    """A rational as `numerator/denominator`, or the integer alone where the denominator is one."""
    return "%d" % value[0] if value[1] == 1 else "%d/%d" % value


def orbit_radius(principal, charge):
    """The Bohr orbit radius in units of the Bohr radius: n^2 over Z, exactly."""
    return rational(principal * principal, charge)


def orbit_energy(principal, charge):
    """The Bohr orbit energy in units of the Rydberg: minus Z^2 over n^2, exactly."""
    return rational(-charge * charge, principal * principal)


def transition_energy(lower, upper, charge):
    """The photon energy of a fall from `upper` to `lower` in Rydbergs: Z^2 (1/lower^2 - 1/upper^2)."""
    return minus(rational(charge * charge, lower * lower), rational(charge * charge, upper * upper))


def hydrogen_orbits(out):
    """The hydrogen orbits as exact rationals, and the exact gap between neighboring shells."""
    out.write("\n  HYDROGEN ORBITS. Radius in Bohr radii, energy in Rydbergs, angular momentum in hbar.\n\n")
    out.write("    %-4s %-10s %-12s %-14s %s\n" % ("n", "L (hbar)", "radius", "energy", "gap to n+1"))
    for principal in SHELLS:
        radius = orbit_radius(principal, 1)
        energy = orbit_energy(principal, 1)
        gap = minus(orbit_radius(principal + 1, 1), radius)
        out.write("    %-4d %-10d %-12s %-14s %s\n"
                  % (principal, principal, as_text(radius), as_text(energy), as_text(gap)))
    out.write("\n    the gap is (2n+1)/Z exactly, so no two orbits ever fall on one radius.\n")


def hydrogen_like(atomic_number, out):
    """The ground orbit of a one-electron ion of nuclear charge Z, radius and energy exact in Z."""
    radius = orbit_radius(1, atomic_number)
    energy = orbit_energy(1, atomic_number)
    out.write("    %-3s Z=%-3d ground orbit  radius %-10s  energy %s\n"
              % (element.symbol(atomic_number), atomic_number, as_text(radius), as_text(energy)))


def balmer_ratios(out):
    """The Balmer line wavelengths as ratios to the first, exact and free of any measured constant."""
    out.write("\n  BALMER SERIES. Wavelength ratios to H-alpha, exact and constant-free (Z cancels).\n\n")
    reference = transition_energy(2, BALMER[0], 1)
    out.write("    %-8s %-12s %-10s %s\n" % ("line", "upper n", "ratio", "decimal"))
    names = ("H-alpha", "H-beta", "H-gamma", "H-delta")
    for name, upper in zip(names, BALMER):
        energy = transition_energy(2, upper, 1)
        # Wavelength is inverse to energy, so the wavelength ratio is the energy ratio flipped.
        ratio = over(reference, energy)
        out.write("    %-8s %-12d %-10s %.5f\n"
                  % (name, upper, as_text(ratio), ratio[0] / ratio[1]))
    out.write("\n    these ratios carry no Rydberg and no meter; a measured ratio meets them at the oracle.\n")


def wanted_numbers(argv):
    """The atomic numbers named on the command line, by Z or by symbol. Empty means a default span."""
    numbers = []
    for token in argv:
        if token.startswith("-"):
            continue
        if token.isdigit():
            candidate = int(token)
            if 1 <= candidate <= element.ELEMENT_COUNT:
                numbers.append(candidate)
            continue
        try:
            numbers.append(element.atomic_number(token))
        except ValueError:
            continue
    return numbers


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("\n  The Bohr orbit is an exact rational: radius n^2/Z, energy -Z^2/n^2. The quantum\n")
    out.write("  number is an integer, so the trajectory reproduces with no rounding and no drift.\n")

    hydrogen_orbits(out)

    out.write("\n  ONE ELECTRON ON A HEAVIER NUCLEUS. Radius falls as 1/Z, energy deepens as Z^2.\n\n")
    charges = wanted_numbers(argv) or [1, 2, 3, 26, 92]
    for atomic_number in charges:
        hydrogen_like(atomic_number, out)

    balmer_ratios(out)
    out.write("\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
