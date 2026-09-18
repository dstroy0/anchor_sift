#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-1-003
#
# The Standard Model particles as exact charges, and the structure the exact numbers emit on their own.
#
#   Usage:  python examples/particle_physics/1_represent/particles_as_exact_charges.py
#
# The particles and their masses come from the Particle Data Group, hosted at CERN, and are represented
# in representation/particle/standard_model.py by exact integer quantum numbers, charge in thirds and
# spin doubled. This reads the structure back out. Nothing is derived from first principles here: the
# particles are put in, and what emerges is how the exact numbers organize themselves.
#
# The reading is by equality and by exact sums, never by a bound. No mass enters, because a mass forces
# a tolerance and a tolerance is the decision this refuses. Two particles carry the same charge or
# they do not; a generation's charges sum to zero or they do not; a charge divides by three or it does
# not. Every question is truthy or falsy, and the census ranks by magnitude, total minus a count, the
# rarest first, the same way the sift kernel probes a field.
#
# Three things emerge. The three generations recur with identical quantum numbers. The up, charm and
# top quarks are one signature seen three times, as the periodic table's groups were one signature seen
# down a column. The electric charge of a generation, each quark counted in its three colors, sums to
# exactly zero, the anomaly-free condition and the reason an atom is neutral: the proton's quarks and
# the electron balance to the digit. And the free particles, the leptons and the bosons, carry a charge
# that divides by three, an integer charge, while the quarks do not, and a quark is never seen alone.

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

from representation.particle import standard_model  # noqa: E402


def charge_text(charge_thirds):
    """A charge carried in thirds as it reads in whole units, exactly, no decimal."""
    whole, remainder = divmod(charge_thirds, 3)
    if remainder == 0:
        return "%+d" % whole
    return "%+d/3" % charge_thirds


def generations_recur(out):
    """Show the generation quantum numbers are one signature seen three times, by equality alone."""
    out.write("\n  THE GENERATIONS RECUR. Each generation's fermions, by exact quantum numbers.\n\n")
    numbers = standard_model.generations()
    signatures = {}
    for number in numbers:
        members = standard_model.by_generation(number)
        signatures[number] = tuple(sorted(standard_model.signature(one) for one in members))
        names = " ".join("%s(%s)" % (one.symbol, charge_text(one.charge_thirds)) for one in members)
        out.write("    generation %d: %s\n" % (number, names))
    first = signatures[numbers[0]]
    same = all(signatures[number] == first for number in numbers)
    out.write("\n    the three signature sets are equal: %s. One structure, seen %d times, and the\n"
              % (same, len(numbers)))
    out.write("    only difference between the generations is a mass this reading never looked at.\n")
    return same


def charge_sums_vanish(out):
    """Show each generation's color-weighted charge sums to exactly zero, the reason atoms are neutral."""
    out.write("\n  THE CHARGE SUM VANISHES. Each quark counted in its three colors, summed in thirds.\n\n")
    all_zero = True
    for number in standard_model.generations():
        members = standard_model.by_generation(number)
        total = standard_model.charge_sum_thirds(members)
        all_zero = all_zero and (total == 0)
        out.write("    generation %d: sum = %d thirds\n" % (number, total))
    out.write("\n    every generation sums to zero exactly. That is the anomaly-free condition, and it\n")
    out.write("    is why the proton and the electron balance and an atom carries no net charge.\n")
    return all_zero


def charge_is_quantized(out):
    """Show which particles carry an integer charge, dividing by three, and which are fractional quarks."""
    out.write("\n  CHARGE DIVIDES BY THREE, OR IT DOES NOT. Integer-charge particles run free.\n\n")
    integer = [one for one in standard_model.PARTICLES if one.charge_thirds % 3 == 0]
    fractional = [one for one in standard_model.PARTICLES if one.charge_thirds % 3 != 0]
    out.write("    integer charge (%d): %s\n"
              % (len(integer), " ".join(one.symbol for one in integer)))
    out.write("    fractional charge (%d): %s\n"
              % (len(fractional), " ".join(one.symbol for one in fractional)))
    out.write("\n    every fractional particle is a quark, and a quark is never seen alone; the free\n")
    out.write("    particles carry a charge that divides by three.\n")
    return all(one.kind == "quark" for one in fractional)


def spin_census(out):
    """Rank the spins by magnitude, total minus count, the rarest first, the way the sift probes."""
    out.write("\n  THE SPIN CENSUS. Magnitude is the total minus the count, larger meaning rarer.\n\n")
    total = len(standard_model.PARTICLES)
    counts = {}
    for one in standard_model.PARTICLES:
        counts[one.doubled_spin] = counts.get(one.doubled_spin, 0) + 1
    ranked = sorted(counts.items(), key=lambda pair: (-(total - pair[1]), pair[0]))
    for doubled_spin, count in ranked:
        out.write("    spin %-3s count %-2d  magnitude %d\n"
                  % (("%d/2" % doubled_spin if doubled_spin % 2 else "%d" % (doubled_spin // 2)),
                     count, total - count))
    out.write("\n    the scalar is rarest. A sift over the particles probes the Higgs first, the one\n")
    out.write("    the collider found last.\n")


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("\n  %d confirmed particles, read by exact quantum numbers and no mass.\n"
              % len(standard_model.PARTICLES))

    recur = generations_recur(out)
    neutral = charge_sums_vanish(out)
    confined = charge_is_quantized(out)
    spin_census(out)

    out.write("\n")
    out.flush()
    return 0 if (recur and neutral and confined) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
