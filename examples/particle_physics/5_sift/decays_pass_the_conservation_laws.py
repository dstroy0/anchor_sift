#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-5-002
#
# A decay passes only where its conserved integers balance, the necessary condition read by equality.
#
#   Usage:  python examples/particle_physics/5_sift/decays_pass_the_conservation_laws.py
#
# A sift is a necessary condition, and conservation is one: a decay can happen only where the electric
# charge, the baryon number and the lepton number of the products equal the parent's. Each of the
# three is an exact integer, charge and baryon carried in thirds. The check is a sum and an equality,
# a decay balances or it does not, with no tolerance and no mass. Whether a balanced decay is fast or
# slow, or happens at all, is dynamics this does not read; conservation is only the gate every decay
# has to pass.
#
# The fundamental particles' numbers come from the ledger. The antiparticles negate theirs, and the few
# composite hadrons carry the numbers their quark content gives, cited to the Particle Data Group. The
# decays themselves are the measured channels, one of them a channel never seen: a proton to a positron
# and a photon, which balances the charge and breaks the baryon number. The gate closes on it, and the
# proton's stability is that closed gate read in integers.
#
# Integer arithmetic only, in thirds, with no library and no rounding.

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

# The composite hadrons a decay names, as (charge_thirds, baryon_thirds, lepton_number). Their numbers
# are the sums their quark content gives: a proton is uud, a neutron udd, a pion a quark and antiquark.
# Cited to the Particle Data Group. Baryon number is carried in thirds, and a three-quark baryon is 3.
COMPOSITES = {
    "p": (3, 3, 0),
    "n": (0, 3, 0),
    "pi+": (3, 0, 0),
    "pi0": (0, 0, 0),
    "pi-": (-3, 0, 0),
}

# An antiparticle name maps to the fundamental it conjugates; its numbers are that one's negated.
ANTI = {"e_bar": "e", "mu_bar": "mu", "nu_e_bar": "nu_e", "nu_mu_bar": "nu_mu"}

# The measured decay channels, parent to products, and one channel never observed. Cited to the
# Particle Data Group.
DECAYS = (
    ("beta decay", "n", ("p", "e", "nu_e_bar")),
    ("muon decay", "mu", ("e", "nu_mu", "nu_e_bar")),
    ("charged pion", "pi+", ("mu_bar", "nu_mu")),
    ("neutral pion", "pi0", ("gamma", "gamma")),
    ("proton decay, never seen", "p", ("e_bar", "gamma")),
)

# The three conserved quantities, by the index they sit at in a (charge, baryon, lepton) triple.
CONSERVED = ("charge", "baryon", "lepton")


def fundamental_numbers():
    """The (charge_thirds, baryon_thirds, lepton_number) of each fundamental particle, by symbol."""
    return {one.symbol: (one.charge_thirds, one.baryon_thirds, one.lepton_number)
            for one in standard_model.PARTICLES}


def numbers_of(name, fundamentals):
    """The conserved triple of a named particle: fundamental, antiparticle or composite. Raises if unknown."""
    if name in COMPOSITES:
        return COMPOSITES[name]
    if name in ANTI:
        base = fundamentals[ANTI[name]]
        return tuple(-value for value in base)
    if name in fundamentals:
        return fundamentals[name]
    raise ValueError("no conserved numbers for %r" % name)


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    fundamentals = fundamental_numbers()

    out.write("\n  THE GATE. A decay passes only where every conserved integer balances.\n\n")
    out.write("    %-26s %-8s %-8s %-8s %s\n" % ("decay", "charge", "baryon", "lepton", "passes"))
    passed = 0
    for label, parent, products in DECAYS:
        before = numbers_of(parent, fundamentals)
        after = [0, 0, 0]
        for product in products:
            triple = numbers_of(product, fundamentals)
            after = [after[at] + triple[at] for at in range(3)]
        balanced = [before[at] == after[at] for at in range(3)]
        if all(balanced):
            passed += 1
        marks = ["yes" if one else "NO" for one in balanced]
        out.write("    %-26s %-8s %-8s %-8s %s\n"
                  % (label, marks[0], marks[1], marks[2], "yes" if all(balanced) else "no"))

    out.write("\n  %d of %d channels pass every conservation law.\n" % (passed, len(DECAYS)))
    out.write("  The proton to a positron and a photon balances the charge and breaks the baryon\n")
    out.write("  number and the lepton number. The gate closes on it. The proton is stable because\n")
    out.write("  that gate is closed, read here in integers with no tolerance.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
