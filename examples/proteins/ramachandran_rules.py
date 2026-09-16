#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-x-005
# Catalog: PRO-RULES
#
# The Ramachandran rules, held in one place so the protein stages read them the same way.
#
#   Usage:  from ramachandran_rules import angle, load_contours, region, score
#
# The engine hands back a torsion as exact integer terms and stops there, because the atan2 that
# turns them into a degree is the one irrational step in the path and does not belong in the reader.
# This is where it is taken, in decimal and to a precision stated below, well under the grid the
# answer is read against. Nothing here imports numpy or any other computing library. Python's own
# integers and decimals are the whole of the arithmetic.
#
# The rules themselves are not this work's. The contour grids are the Top8000 percentile contours
# published by the Richardson laboratory, the same grids MolProbity and the wwPDB validation
# pipeline score a deposit against. They are fetched from the laboratory's public repository and
# cached, exactly as the crystallography oracle fetches a published cell edge from the COD. A
# recovered outlier rate is then checked against a number this work did not produce.
#
#   Source:  https://github.com/rlabduke/reference_data  (Top8000 ramachandran_pct_contour_grids)
#   License: CC BY 4.0, as declared in that repository.
#
# WHAT IS A TOLERANCE HERE AND WHAT IS NOT
#
# Crystallography needs no tolerance: a lattice displacement lands on an occupied place or does not.
# A protein cannot be read that way, and the crystallography README says why. A backbone is a cloud
# of real valued coordinates, so a torsion is an irrational the deposit never wrote, and the rules
# are published on a grid of two degrees, not as a formula. So there is a quantum here, and the
# honest thing is to declare where it comes from rather than pick one.
#
# It comes from the reference. The grid is two degrees because the Richardson laboratory published
# it at two degrees; the favored and allowed cutoffs below are the numbers MolProbity scores with,
# named here rather than tuned. The decimal precision the angle is taken to is set far under the
# grid so that it decides nothing. No number in this file was chosen to make a result come out, and
# every stage that uses one reports it.

import os
import urllib.request
from decimal import Decimal, getcontext

# Digits carried through the atan2. The reference grid is two degrees, and forty digits places the
# angle roughly forty orders of magnitude under that, so the precision cannot decide a bin. Raising
# it changes no classification; this is headroom, not a knob.
getcontext().prec = 40

AGENT = {"User-Agent": "anchor-sift-research/1.0 "
                       "(https://github.com/dstroy0/anchor_sift; dquigg123@gmail.com)"}

GRID_BASE = ("https://raw.githubusercontent.com/rlabduke/reference_data/master/"
             "Top8000/Top8000_ramachandran_pct_contour_grids/")

# One contour per residue class, with the favored and allowed cutoffs MolProbity reads it at. A
# value at or above the allowed cutoff is inside the rules; below it is an outlier. These cutoffs
# are the published MolProbity numbers and are reported by every stage that applies them, so the
# reading can be repeated against the same rules and no cutoff hides in the code.
CONTOURS = {
    #  class      file                              favored          allowed
    "general":  ("rama8000-general-noGPIVpreP.data", Decimal("0.02"), Decimal("0.0005")),
    "glycine":  ("rama8000-gly-sym.data",            Decimal("0.02"), Decimal("0.0005")),
    "cispro":   ("rama8000-cispro.data",             Decimal("0.02"), Decimal("0.0020")),
    "transpro": ("rama8000-transpro.data",           Decimal("0.02"), Decimal("0.0020")),
    "prepro":   ("rama8000-prepro-noGP.data",        Decimal("0.02"), Decimal("0.0020")),
    "ileval":   ("rama8000-ileval-nopreP.data",      Decimal("0.02"), Decimal("0.0005")),
}

# The grid runs -179 to 179 in steps of two, wrapping. A residue below this omega magnitude is read
# as a cis peptide, which selects the cis proline contour instead of the trans one.
CIS_BELOW = Decimal(90)


def _atan_unit(t):
    """atan(t) in radians for any decimal t, by halving the argument until the series is quick."""
    reductions = 0
    limit = Decimal("0.05")
    while abs(t) > limit:
        t = t / (1 + (1 + t * t).sqrt())
        reductions += 1
    term = t
    total = t
    square = t * t
    step_at = 1
    tiny = Decimal(10) ** (-(getcontext().prec - 2))
    while True:
        term = -term * square
        step_at += 2
        step = term / step_at
        total += step
        if abs(step) < tiny:
            break
    return total * (2 ** reductions)


# pi by Machin's formula, in decimal, computed once. No float constant enters the path.
PI = 16 * _atan_unit(Decimal(1) / 5) - 4 * _atan_unit(Decimal(1) / 239)


def angle(terms):
    """A torsion's exact integer terms (Y, C, S) rendered to degrees in (-180, 180].

    The engine returns X of the atan2 split as C * sqrt(S), because the sqrt is the irrational. Here
    x = C * sqrt(S) and the angle is 2 * atan(Y / (r + x)) with r = sqrt(x*x + Y*Y), and x*x is the
    integer C*C*S so r is a decimal square root of an integer. The negative real axis, where r + x
    is zero, is the single angle of 180 and is returned directly.
    """
    y_int, c_int, s_int = terms
    y = Decimal(y_int)
    x = Decimal(c_int) * Decimal(s_int).sqrt()
    if y == 0 and x < 0:
        return Decimal(180)
    r = Decimal(c_int * c_int * s_int + y_int * y_int).sqrt()
    return 2 * _atan_unit(y / (r + x)) * 180 / PI


def load_contours(cache):
    """Every contour grid, fetched once to `cache` and read from there after.

    Returns {class: (grid, favored, allowed)} where grid maps a (phi center, psi center) pair to the
    published percentile value at it.
    """
    os.makedirs(cache, exist_ok=True)
    loaded = {}
    for name, (filename, favored, allowed) in CONTOURS.items():
        path = os.path.join(cache, filename)
        if not os.path.isfile(path):
            with urllib.request.urlopen(urllib.request.Request(GRID_BASE + filename, headers=AGENT),
                                        timeout=180) as response:
                body = response.read().decode("utf-8", "replace")
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.write(body)
        grid = {}
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if line.startswith("#") or not line.strip():
                    continue
                left, right, value = line.split()
                grid[(int(round(float(left))), int(round(float(right))))] = Decimal(value)
        loaded[name] = (grid, favored, allowed)
    return loaded


def _center(a):
    """The grid center at -179, -177, ... 179 for a decimal angle in (-180, 180]."""
    index = int((float(a) + 180) // 2) % 180
    return -179 + 2 * index


def value_at(grid, phi, psi):
    """The published percentile at the bin a (phi, psi) falls in, wrapping the edges."""
    return grid.get((_center(phi), _center(psi)), Decimal(0))


def region(name, next_name, is_cis):
    """The contour class a residue is scored against, by its own type and its neighbor's."""
    if name == "GLY":
        return "glycine"
    if name == "PRO":
        return "cispro" if is_cis else "transpro"
    if next_name == "PRO":
        return "prepro"
    if name in ("ILE", "VAL"):
        return "ileval"
    return "general"


def score(contours, residues):
    """Score a structure's residues against the rules.

    `residues` is what engine.representation.structure.protein.phi_psi returns. Each is turned into
    a phi and a psi, a cis peptide is told from its omega, the class is chosen, and the published
    value at the bin is compared to the cutoffs. Returns a list of dicts carrying the angle, the
    class, the value, and whether the residue is favored, allowed or an outlier.
    """
    read = []
    for residue in residues:
        phi = angle(residue["phi"])
        psi = angle(residue["psi"])
        is_cis = residue["name"] == "PRO" and abs(angle(residue["omega"])) < CIS_BELOW
        klass = region(residue["name"], residue["next_name"], is_cis)
        grid, favored, allowed = contours[klass]
        value = value_at(grid, phi, psi)
        read.append({
            "chain": residue["chain"], "seq": residue["seq"], "name": residue["name"],
            "region": klass, "phi": phi, "psi": psi, "value": value,
            "favored": value >= favored, "outlier": value < allowed,
        })
    return read
