#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-1-004
#
# The hadrons the light quarks make, and the integer charge a color-neutral combination forces.
#
#   Usage:  python examples/particle_physics/1_represent/hadrons_from_quarks.py
#
# The quarks come from the ledger, the light three u, d and s that make the common hadrons. A baryon is
# three quarks and a meson is a quark and an antiquark, the color-neutral combinations, and this takes
# each one's charge as the exact sum in thirds. Nothing is derived about why quarks bind or what a
# hadron weighs. The charge is an integer sum and it is read as one, with no mass and no tolerance.
#
# What comes out is that every color-neutral combination carries an integer charge, a multiple of three
# thirds, where a single quark carries a fraction. That is confinement stated in charge alone: the free
# thing is the integer-charged one. The observed charges fall out, the proton at +1, the neutron at 0
# and the omega at -1, and the proton balancing the electron is the reason a hydrogen atom is neutral,
# the thread back to the first stage of this subject.
#
# The arithmetic is integer only, charge carried in thirds, with no library and no rounding. Source: the
# Particle Data Group at CERN, for the quark content of each named hadron.

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

# The light quarks, the three that make the common hadrons, in charge order.
LIGHT = ("u", "d", "s")

# The quark content of the named ground-state baryons, keyed by the sorted symbols. Cited to the
# Particle Data Group. Two of these, the proton and the neutron, are the whole reason an atom holds
# together.
BARYON_NAMES = {
    "uuu": "Delta++", "duu": "proton", "ddu": "neutron", "ddd": "Delta-",
    "suu": "Sigma+", "dsu": "Lambda", "dds": "Sigma-",
    "ssu": "Xi0", "dss": "Xi-", "sss": "Omega-",
}

# The named charged mesons, keyed by (quark symbol, antiquark's quark symbol). The neutral combinations
# mix and are left unnamed here.
MESON_NAMES = {
    ("u", "d"): "pi+", ("d", "u"): "pi-",
    ("u", "s"): "K+", ("s", "u"): "K-",
    ("d", "s"): "K0", ("s", "d"): "K0bar",
}


def light_quarks():
    """The u, d and s quarks pulled from the ledger, in the LIGHT order."""
    found = {one.symbol: one for one in standard_model.PARTICLES if one.kind == "quark"}
    return [found[symbol] for symbol in LIGHT]


def charge_text(charge_thirds):
    """A charge carried in thirds as it reads in whole units, exactly, no decimal."""
    whole, remainder = divmod(charge_thirds, 3)
    if remainder == 0:
        return "%+d" % whole
    return "%+d/3" % charge_thirds


def baryons(quarks):
    """Every three-quark combination of the given quarks, as (symbols, charge in thirds).

    The three are drawn with repetition and in order. Each color-neutral content appears once. The
    charge is the sum of the three quark charges, in thirds.
    """
    made = []
    for first in range(len(quarks)):
        for second in range(first, len(quarks)):
            for third in range(second, len(quarks)):
                triple = (quarks[first], quarks[second], quarks[third])
                symbols = "".join(sorted(one.symbol for one in triple))
                charge = sum(one.charge_thirds for one in triple)
                made.append((symbols, charge))
    return made


def mesons(quarks):
    """Every quark and antiquark combination, as (quark symbol, antiquark symbol, charge in thirds).

    An antiquark carries the negative of its quark's charge. The meson charge is the difference of
    the two quark charges, in thirds.
    """
    made = []
    for quark in quarks:
        for antiquark in quarks:
            charge = quark.charge_thirds - antiquark.charge_thirds
            made.append((quark.symbol, antiquark.symbol, charge))
    return made


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    quarks = light_quarks()
    if len(quarks) != len(LIGHT):
        out.write("\n  the ledger did not carry the light quarks.\n\n")
        out.flush()
        return 2

    made_baryons = baryons(quarks)
    made_mesons = mesons(quarks)

    out.write("\n  BARYONS. Three quarks, color-neutral, charge the sum in thirds.\n\n")
    out.write("    %-8s %-12s %s\n" % ("content", "charge", "known as"))
    for symbols, charge in made_baryons:
        out.write("    %-8s %-12s %s\n"
                  % (" ".join(symbols), charge_text(charge), BARYON_NAMES.get(symbols, "")))

    out.write("\n  MESONS. A quark and an antiquark, charge the difference in thirds.\n\n")
    out.write("    %-8s %-12s %s\n" % ("content", "charge", "known as"))
    for quark, antiquark, charge in made_mesons:
        content = "%s %sbar" % (quark, antiquark)
        out.write("    %-8s %-12s %s\n"
                  % (content, charge_text(charge), MESON_NAMES.get((quark, antiquark), "")))

    charges = [charge for _, charge in made_baryons] + [charge for _, _, charge in made_mesons]
    integer = sum(1 for charge in charges if charge % 3 == 0)

    out.write("\n  %d of %d combinations carry an integer charge, a multiple of three thirds.\n"
              % (integer, len(charges)))
    out.write("  A single quark carries a fraction and is never free; a color-neutral combination\n")
    out.write("  carries an integer and is. Confinement in charge alone, by exact arithmetic.\n")
    out.write("  The proton is uud at +1 and the electron is -1. A hydrogen atom is neutral, which\n")
    out.write("  is where the first stage of this subject started.\n\n")
    out.flush()
    return 0 if integer == len(charges) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
