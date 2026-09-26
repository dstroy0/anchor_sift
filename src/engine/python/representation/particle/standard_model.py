#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The confirmed Standard Model particles as exact integer quantum numbers, with no mass in the reading.
#
#   Usage:  from representation.particle.standard_model import PARTICLES, fermions, by_generation, signature
#
# CHARGE IN THIRDS, SPIN DOUBLED. EVERY QUANTUM NUMBER IS AN INTEGER
#
# Electric charge is quantized in thirds of the electron charge: an up quark is +2, a down quark is -1,
# a charged lepton is -3, a neutrino is 0, a W is plus or minus 3. Carrying charge in thirds makes it an
# exact integer, the way representation/structure/symmetry.py carries thirds in units of 1/24 and the
# atom ledger carries spin in halves. Spin is doubled the same way: a fermion is 1, a gauge boson is 2,
# the Higgs is 0. Baryon number is carried in thirds too, a quark being 1.
#
# The point of the integers is what the sift kernel reads a field through: equality. Two particles carry
# the same charge or they do not, the same generation or not, and a generation's charges either sum to
# zero or they do not. No mass enters, and no tolerance is chosen, because a mass would force a bound,
# and a bound is what this reading refuses. The masses are measured, they belong to the particle data,
# and they are not here.
#
# What the exact numbers hold is the structure: three generations that recur with identical quantum
# numbers, and a per-generation electric charge that sums to zero once each quark is counted in its three
# colors. That second fact is why an atom is neutral, the proton's quarks and the electron balancing to
# the digit, and it is the thread from this ledger to the atom ledger.
#
# Source: the Particle Data Group Review of Particle Physics, hosted at CERN, for the confirmed content,
# three generations of quarks and leptons, the four gauge bosons and the Higgs. The quantum numbers are
# the Standard Model's exact assignments, not measured values.

import collections

# One particle as the exact numbers the structure is read from. Charge and baryon number are in thirds,
# spin is doubled, generation is zero for a boson that has none, and color_states is how many color
# charges the particle carries, three for a quark and eight for the gluon.
Particle = collections.namedtuple(
    "Particle",
    ("name", "symbol", "kind", "charge_thirds", "doubled_spin", "generation",
     "color_states", "baryon_thirds", "lepton_number"),
)

# The confirmed particles. Antiparticles are the conjugates of these and are not listed separately.
PARTICLES = (
    Particle("up", "u", "quark", 2, 1, 1, 3, 1, 0),
    Particle("down", "d", "quark", -1, 1, 1, 3, 1, 0),
    Particle("charm", "c", "quark", 2, 1, 2, 3, 1, 0),
    Particle("strange", "s", "quark", -1, 1, 2, 3, 1, 0),
    Particle("top", "t", "quark", 2, 1, 3, 3, 1, 0),
    Particle("bottom", "b", "quark", -1, 1, 3, 3, 1, 0),
    Particle("electron", "e", "lepton", -3, 1, 1, 1, 0, 1),
    Particle("electron neutrino", "nu_e", "lepton", 0, 1, 1, 1, 0, 1),
    Particle("muon", "mu", "lepton", -3, 1, 2, 1, 0, 1),
    Particle("muon neutrino", "nu_mu", "lepton", 0, 1, 2, 1, 0, 1),
    Particle("tau", "tau", "lepton", -3, 1, 3, 1, 0, 1),
    Particle("tau neutrino", "nu_tau", "lepton", 0, 1, 3, 1, 0, 1),
    Particle("photon", "gamma", "gauge", 0, 2, 0, 1, 0, 0),
    Particle("gluon", "g", "gauge", 0, 2, 0, 8, 0, 0),
    Particle("W plus", "W+", "gauge", 3, 2, 0, 1, 0, 0),
    Particle("W minus", "W-", "gauge", -3, 2, 0, 1, 0, 0),
    Particle("Z", "Z", "gauge", 0, 2, 0, 1, 0, 0),
    Particle("Higgs", "H", "scalar", 0, 0, 0, 1, 0, 0),
)

# The kinds that carry a generation and make up matter.
FERMION_KINDS = ("quark", "lepton")


def fermions():
    """The matter particles, the quarks and leptons, the only ones carrying a generation."""
    return tuple(one for one in PARTICLES if one.kind in FERMION_KINDS)


def generations():
    """The generation numbers present among the fermions, in order."""
    return tuple(sorted({one.generation for one in fermions()}))


def by_generation(number):
    """The fermions of one generation, in the order they are listed."""
    return tuple(one for one in fermions() if one.generation == number)


def signature(particle):
    """A fermion's quantum numbers with the generation and the name stripped, what recurs across generations.

    Two fermions with the same signature differ only in generation and in mass, which is not read here.
    The up, charm and top quarks share one signature; so do the three charged leptons, and so on. That
    shared signature repeating three times is the generation structure, read by equality alone.
    """
    return (particle.kind, particle.charge_thirds, particle.doubled_spin,
            particle.color_states, particle.baryon_thirds, particle.lepton_number)


def charge_sum_thirds(particles):
    """The electric charge of a set of particles in thirds, each quark counted in its color states.

    A generation summed this way is zero: the quark charges, tripled for color, cancel the lepton
    charges exactly. That exact zero is the anomaly-free condition and the reason matter is neutral.
    """
    return sum(one.charge_thirds * one.color_states for one in particles)
