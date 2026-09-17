#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The elements as one ledger: an atomic number, its symbol, and the electrons of the neutral atom.
#
#   Usage:  from representation.atom.element import SYMBOLS, MADELUNG, symbol, atomic_number, electrons
#
# One transcribed table for the whole tree. Two subjects read it, particle_physics for the periodic
# law and chemistry for bonding, and a second copy of the element data is one edit away from
# disagreeing with the first about what an element is.
#
# THE IDEAL FILLING
#
# electrons() fills Madelung order, lowest principal plus azimuthal first, and Hund's rule inside a
# subshell, every magnetic orbital taking a spin-up electron before any takes spin-down. That is the
# ideal filling. Real atoms deviate: chromium, copper and others fill against the order, and those
# measured configurations are the oracle stage, cited to a measurement, not this file. This field is
# the necessary condition, the filling the periodic law would follow if nothing competed with it.
#
# An electron is a point at an integer state (principal, azimuthal, magnetic, doubled_spin) carrying
# its subshell as text. The spin is carried as its double, +1 and -1 for the two halves, so the state
# stays an integer, the way representation/structure/symmetry.py carries thirds in units of 1/24. No
# scale is needed and none is used: representation.exact carries 1024 digits for decimal coordinates,
# and an electron count is already an integer.
#
# Madelung order fills 1s through 7p, and its capacities run to 118 exactly, so the order names every
# element from hydrogen to oganesson and no further. The symbols and atomic numbers are the IUPAC
# table, canonical reference that needs no source.

# The four subshell types by azimuthal number, 0 through 3.
SUBSHELL = ("s", "p", "d", "f")

# Madelung filling order as (principal, azimuthal). A subshell holds capacity(azimuthal) electrons,
# and the running total reaches 118 at the final entry, so this order names every element.
MADELUNG = (
    (1, 0), (2, 0), (2, 1), (3, 0), (3, 1), (4, 0), (3, 2), (4, 1), (5, 0), (4, 2),
    (5, 1), (6, 0), (4, 3), (5, 2), (6, 1), (7, 0), (5, 3), (6, 2), (7, 1),
)

# Element symbols by atomic number, the symbol for Z at index Z - 1. The IUPAC table.
SYMBOLS = (
    "H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne",
    "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca",
    "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn",
    "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr",
    "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn",
    "Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", "Nd",
    "Pm", "Sm", "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb",
    "Lu", "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg",
    "Tl", "Pb", "Bi", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th",
    "Pa", "U", "Np", "Pu", "Am", "Cm", "Bk", "Cf", "Es", "Fm",
    "Md", "No", "Lr", "Rf", "Db", "Sg", "Bh", "Hs", "Mt", "Ds",
    "Rg", "Cn", "Nh", "Fl", "Mc", "Lv", "Ts", "Og",
)

# How many elements the ledger names. A count over a literal, settled at import, not a read.
ELEMENT_COUNT = len(SYMBOLS)

# The atomic number of a symbol, the reverse of SYMBOLS, built once over the literal above.
_NUMBER_OF_SYMBOL = {written: index + 1 for index, written in enumerate(SYMBOLS)}


def capacity(azimuthal):
    """How many electrons a subshell of this azimuthal number holds: two per magnetic orbital."""
    return 2 * (2 * azimuthal + 1)


def symbol(atomic_number):
    """The IUPAC symbol for an atomic number. Raises where the number falls past the end of the ledger."""
    if not 1 <= atomic_number <= ELEMENT_COUNT:
        raise ValueError("atomic number %r is outside 1 to %d" % (atomic_number, ELEMENT_COUNT))
    return SYMBOLS[atomic_number - 1]


def atomic_number(written):
    """The atomic number of a symbol. Raises on a symbol the ledger does not carry."""
    if written not in _NUMBER_OF_SYMBOL:
        raise ValueError("%r is not an element symbol" % (written,))
    return _NUMBER_OF_SYMBOL[written]


def electrons(atomic_number):
    """The neutral atom of `atomic_number` as its electrons, each an exact state carrying its subshell.

    Fills Madelung order and, inside a subshell, Hund's rule: every magnetic orbital takes a spin-up
    electron before any takes spin-down. Returns a list of (state, subshell), the state an integer
    tuple (principal, azimuthal, magnetic, doubled_spin) and the subshell text like "2p". The list is
    Z long, one entry per electron, and a reader counts the states without leaning on the labels.

    Raises where the ledger does not name the number, because a caller that meant Z and got fewer
    electrons than Z carries a defect an empty list would hide.
    """
    if not 1 <= atomic_number <= ELEMENT_COUNT:
        raise ValueError("atomic number %r is outside 1 to %d" % (atomic_number, ELEMENT_COUNT))
    placed = []
    remaining = atomic_number
    for principal, azimuthal in MADELUNG:
        if remaining <= 0:
            break
        written = "%d%s" % (principal, SUBSHELL[azimuthal])
        for doubled_spin in (1, -1):
            for magnetic in range(-azimuthal, azimuthal + 1):
                if remaining <= 0:
                    break
                placed.append(((principal, azimuthal, magnetic, doubled_spin), written))
                remaining -= 1
            if remaining <= 0:
                break
    return placed


def group_signature(electron_set):
    """The differentiating electron's azimuthal type and its subshell's population, principal stripped.

    The differentiating electron is the last one Madelung order added. Its signature is (azimuthal,
    population), population being how many electrons stand in that same subshell in this element.
    Sodium and lithium both close on a lone s electron and both read (0, 1); carbon and silicon both
    close on a second p electron and both read (1, 2). The principal number is dropped. It is the only
    difference between sodium and lithium, so without it they read as one signature, and that signature
    repeats down the table as the periodic law.
    """
    state, _ = electron_set[-1]
    principal, azimuthal = state[0], state[1]
    population = sum(1 for other_state, _ in electron_set
                     if other_state[0] == principal and other_state[1] == azimuthal)
    return azimuthal, population
