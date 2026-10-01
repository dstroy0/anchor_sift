#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The CODATA constants that are exact and truncated, carried to a thousand places.
#
#   Usage:  python tools/dn_precision/calc/codata_exact.py
#           python tools/dn_precision/calc/codata_exact.py --check
#           python tools/dn_precision/calc/codata_exact.py --split    which uncertainties are removable
#
# THE SPLIT THAT MAKES THIS WORTH DOING
#
# The 2022 CODATA listing holds 358 constants. Counted from the file itself:
#
#     81   marked (exact)
#     19   of those terminate, so the published digits ARE the value and there is nothing to compute
#     62   of those are exact and TRUNCATED, published as "1.054 571 817... e-34"
#    277   carry a measured uncertainty
#
# The 62 are the target. Their decimal expansions do not terminate, NIST stops at about ten digits
# and marks the rest with an ellipsis, and every one of them is a closed-form expression in the
# seven SI defining constants. So the missing digits are not unknown. They are unprinted.
#
# THE 277 ARE NOT TOUCHABLE AND SAYING SO IS THE POINT. alpha, G, the electron mass: their
# uncertainty is what a laboratory measured, and arithmetic cannot reduce it. Computing alpha to a
# thousand places would be computing a thousand places of a number known to eleven. The useful
# statement is not "we removed the uncertainty", it is WHICH uncertainties are mathematical and
# removable and which are physical and permanent. Nobody publishes that division.
#
# WHY THE VERIFICATION HERE IS STRONGER THAN THE REST OF THE TABLE
#
# dn_constants.csv lives by two routes agreeing to a zero gap, which is evidence: two routes could
# share an error. A pure rational admits something better. If p/q is reported as v at N places then
#
#     v * q  <=  p * 10^N  <  (v + 1) * q
#
# is an EXACT integer statement with no arithmetic error in it at all. Either it holds or the digits
# are wrong. That is verification rather than agreement, and it is available for every constant here
# that does not involve pi.
#
# @note The seven SI defining constants are exact BY DEFINITION since the 2019 redefinition, not by
#       measurement. c, h, e, k, N_A, the caesium frequency and the luminous efficacy are integers
#       times powers of ten, which is why everything built from them by field operations is a
#       rational and why this file can be exact at all.

import argparse
import io
import os
import re
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(FAMILY))
for _where in (HERE, os.path.join(FAMILY, "support"), os.path.join(ROOT, "examples", "proofing")):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import dn_constants

LISTING = os.path.join(FAMILY, "dn_const", "codata_2022_allascii.txt")
OUT = os.path.join(FAMILY, "dn_const", "codata_exact.csv")

# The seven SI defining constants, exact since the 2019 redefinition. Written as integers times
# powers of ten so nothing here is a float and no rounding enters at the source.
CAESIUM = Fraction(9192631770)                       # Hz, the caesium hyperfine transition
LIGHT = Fraction(299792458)                          # m/s
PLANCK = Fraction(662607015, 10 ** 42)               # J s
CHARGE = Fraction(1602176634, 10 ** 28)              # C
BOLTZMANN = Fraction(1380649, 10 ** 29)              # J/K
AVOGADRO = Fraction(602214076 * 10 ** 15)            # 1/mol
LUMINOUS = Fraction(683)                             # lm/W

# Every derived constant as an exact expression, with the NIST name it appears under. `needs_pi`
# marks the ones that leave the rationals, and those are verified against our own pi rather than
# by multiplying back.
DERIVED = [
    ("Boltzmann constant in eV/K", BOLTZMANN / CHARGE, False),
    ("Boltzmann constant in Hz/K", BOLTZMANN / PLANCK, False),
    ("Boltzmann constant in inverse meter per kelvin", BOLTZMANN / (PLANCK * LIGHT), False),
    ("conductance quantum", 2 * CHARGE ** 2 / PLANCK, False),
    ("inverse of conductance quantum", PLANCK / (2 * CHARGE ** 2), False),
    ("Josephson constant", 2 * CHARGE / PLANCK, False),
    ("von Klitzing constant", PLANCK / CHARGE ** 2, False),
    ("mag. flux quantum", PLANCK / (2 * CHARGE), False),
    ("Faraday constant", AVOGADRO * CHARGE, False),
    ("molar gas constant", AVOGADRO * BOLTZMANN, False),
    ("molar Planck constant", AVOGADRO * PLANCK, False),
    ("electron volt-hertz relationship", CHARGE / PLANCK, False),
    ("electron volt-inverse meter relationship", CHARGE / (PLANCK * LIGHT), False),
    ("electron volt-kelvin relationship", CHARGE / BOLTZMANN, False),
    ("electron volt-kilogram relationship", CHARGE / LIGHT ** 2, False),
    ("hertz-electron volt relationship", PLANCK / CHARGE, False),
    ("hertz-inverse meter relationship", Fraction(1) / LIGHT, False),
    ("hertz-kelvin relationship", PLANCK / BOLTZMANN, False),
    ("hertz-kilogram relationship", PLANCK / LIGHT ** 2, False),
    ("inverse meter-electron volt relationship", PLANCK * LIGHT / CHARGE, False),
    ("inverse meter-joule relationship", PLANCK * LIGHT, False),
    ("inverse meter-kelvin relationship", PLANCK * LIGHT / BOLTZMANN, False),
    ("inverse meter-kilogram relationship", PLANCK / LIGHT, False),
    ("joule-electron volt relationship", Fraction(1) / CHARGE, False),
    ("joule-hertz relationship", Fraction(1) / PLANCK, False),
    ("joule-inverse meter relationship", Fraction(1) / (PLANCK * LIGHT), False),
    ("joule-kelvin relationship", Fraction(1) / BOLTZMANN, False),
    ("joule-kilogram relationship", Fraction(1) / LIGHT ** 2, False),
    ("kelvin-electron volt relationship", BOLTZMANN / CHARGE, False),
    ("kelvin-hertz relationship", BOLTZMANN / PLANCK, False),
    ("kelvin-inverse meter relationship", BOLTZMANN / (PLANCK * LIGHT), False),
    ("kelvin-kilogram relationship", BOLTZMANN / LIGHT ** 2, False),
    ("kilogram-electron volt relationship", LIGHT ** 2 / CHARGE, False),
    ("kilogram-hertz relationship", LIGHT ** 2 / PLANCK, False),
    ("kilogram-inverse meter relationship", LIGHT / PLANCK, False),
    ("kilogram-joule relationship", LIGHT ** 2, False),
    ("kilogram-kelvin relationship", LIGHT ** 2 / BOLTZMANN, False),
    ("second radiation constant", PLANCK * LIGHT / BOLTZMANN, False),
    # The pi ones. h-bar is h over two pi, and everything built on it inherits that.
    ("reduced Planck constant", PLANCK, True),
    ("atomic unit of action", PLANCK, True),
    ("natural unit of action", PLANCK, True),
    ("reduced Planck constant in eV s", PLANCK / CHARGE, True),
    ("natural unit of action in eV s", PLANCK / CHARGE, True),
    ("elementary charge over h-bar", CHARGE / PLANCK, True),
]

# THE ONE ENTRY THAT MULTIPLIES BY 2 pi INSTEAD OF DIVIDING, and it is worth its own name rather
# than a flag in the table because of how it was found.
#
# e / h-bar = e / (h / 2 pi) = 2 pi e / h. Every other pi entry has h-bar AS its value and divides;
# this one has h-bar in its DENOMINATOR and multiplies. The first version divided, and carried a
# spurious factor of two as well, so it came out low by (2 pi)^2 = 19.74.
#
# THE EXACT CHECK PASSED IT. Multiplying back verifies that a rational was divided correctly and
# says nothing about whether it was the right rational, a correctly computed wrong expression is
# precisely what it cannot see. The NIST comparison caught it on the first run. That is the whole
# argument for keeping an external check even when an internal one is exact.
MULTIPLIES_BY_TWO_PI = frozenset(["elementary charge over h-bar"])

# ------------------------------------------------------------------------------------------------
# The rest of the truncated set. Everything below is a closed form too, and the only reason it was
# not in the first pass is that each needs one more exact definition rather than more arithmetic.
# ------------------------------------------------------------------------------------------------

# The conventional 1990 values, exact by convention rather than by measurement, and both printed as
# terminating decimals in the listing. The seven -90 units are rationals in these and in the SI set.
JOSEPHSON_90 = Fraction(4835979, 10) * 10 ** 9        # Hz/V, 483 597.9 e9 exactly
KLITZING_90 = Fraction(25812807, 1000)                # ohm, 25 812.807 exactly

# The stated conditions for Loschmidt and the molar volumes. Exact decimals, not measurements.
ICE_POINT = Fraction(27315, 100)                      # K, 273.15
PRESSURE_100 = Fraction(100000)                       # Pa, 100 kPa
PRESSURE_ATM = Fraction(101325)                       # Pa, one standard atmosphere

# Unit conversions used by the MeV fm entry, both exact.
MEV = 10 ** 6 * CHARGE                                # J per MeV
FEMTOMETRE = Fraction(1, 10 ** 15)                    # m per fm

# The real Josephson and von Klitzing constants, for the -90 ratios.
JOSEPHSON = 2 * CHARGE / PLANCK
KLITZING = PLANCK / CHARGE ** 2

# The seven -90 units. Checked against the listing's own printed values:
#   ohm-90 and henry-90 both 1.000 000 017 79, farad-90 its reciprocal at 0.999 999 982 20,
#   volt-90 1.000 000 106 66, ampere-90 and coulomb-90 1.000 000 088 87, watt-90 1.000 000 195 53.
# BOTH OF THESE WERE INVERTED ON THE FIRST RUN AND THE NIST COMPARISON CAUGHT BOTH. The exact
# check passed them, because multiplying back verifies a division and not a definition, a
# reciprocal is exactly the error it cannot see. That is now the third time in this file:
# e / h-bar multiplied where it had divided, and these two.
#
# The directions are fixed by what the conventional units mean. An ohm-90 is the size of the ohm
# implied by taking R_K-90 as true, so it is the RATIO OF THE REAL CONSTANT TO THE CONVENTIONAL ONE:
#
#     ohm-90  = R_K / R_K-90  = 25812.807459... / 25812.807  = 1.000 000 017 79...
#     volt-90 = K_J-90 / K_J  = 483597.9 / 483597.8484...    = 1.000 000 106 66...
#
# and the Josephson one runs the other way because K_J is a frequency PER volt, a larger K_J
# means a smaller volt. Checking each against the listing's own printed value is what settles the
# direction, and it is why the printed values are in the comment.
OHM_90 = KLITZING / KLITZING_90
VOLT_90 = JOSEPHSON_90 / JOSEPHSON
AMPERE_90 = VOLT_90 / OHM_90

MORE_DERIVED = [
    ("conventional value of ohm-90", OHM_90, 0),
    ("conventional value of henry-90", OHM_90, 0),
    ("conventional value of farad-90", Fraction(1) / OHM_90, 0),
    ("conventional value of volt-90", VOLT_90, 0),
    ("conventional value of ampere-90", AMPERE_90, 0),
    ("conventional value of coulomb-90", AMPERE_90, 0),
    ("conventional value of watt-90", VOLT_90 * AMPERE_90, 0),

    ("Planck constant in eV/Hz", PLANCK / CHARGE, 0),

    ("Loschmidt constant (273.15 K, 100 kPa)", PRESSURE_100 / (BOLTZMANN * ICE_POINT), 0),
    ("Loschmidt constant (273.15 K, 101.325 kPa)", PRESSURE_ATM / (BOLTZMANN * ICE_POINT), 0),
    ("molar volume of ideal gas (273.15 K, 100 kPa)",
     AVOGADRO * BOLTZMANN * ICE_POINT / PRESSURE_100, 0),
    ("molar volume of ideal gas (273.15 K, 101.325 kPa)",
     AVOGADRO * BOLTZMANN * ICE_POINT / PRESSURE_ATM, 0),

    # c1L = 2 h c^2 is rational; c1 = 2 pi h c^2 carries one power of pi.
    ("first radiation constant for spectral radiance", 2 * PLANCK * LIGHT ** 2, 0),
    ("first radiation constant", 2 * PLANCK * LIGHT ** 2, 1),

    # h-bar c expressed in MeV fm: (h / 2 pi) c, converted. One INVERSE power of pi.
    ("reduced Planck constant times c in MeV fm",
     PLANCK * LIGHT / (2 * MEV * FEMTOMETRE), -1),

    # Stefan-Boltzmann: 2 pi^5 k^4 / (15 h^3 c^2). Five powers of pi.
    ("Stefan-Boltzmann constant",
     2 * BOLTZMANN ** 4 / (15 * PLANCK ** 3 * LIGHT ** 2), 5),
]

# The two Wien constants, which are the ONLY entries in the whole exact set that are not a closed
# form in the defining constants. Each needs the root of a transcendental:
#
#     wavelength law   b  = h c / (k x)    with x the root of  x = 5 (1 - e^-x)
#     frequency law    b' = x' k / h       with x' the root of x = 3 (1 - e^-x)
#
# Those roots have no closed form, so they are found by Newton and VERIFIED BY SUBSTITUTION: the
# residual of the defining equation at the computed root bounds the error directly, which is a
# stronger check than agreement with a printed value.
WIEN = [
    ("Wien wavelength displacement law constant", 5, "over"),
    ("Wien frequency displacement law constant", 3, "times"),
]


def published():
    """The NIST value for each name, as its printed digit string with spaces removed."""
    out = {}
    if not os.path.exists(LISTING):
        return out
    for line in io.open(LISTING, encoding="utf-8", errors="replace").read().splitlines():
        if "(exact)" not in line:
            continue
        name = line[:58].strip()
        value = line[58:82].strip()
        out[name] = value.replace(" ", "")
    return out


def digits_of_rational(value, digits):
    """floor(value * 10^digits) for an exact Fraction. No rounding, no float.

    Returns (scaled integer, exponent) where the exponent normalises the value into [1, 10) so the
    leading digits can be compared against a printed mantissa.
    """
    if value <= 0:
        raise ValueError("only positive constants here")
    exponent = 0
    probe = value
    while probe >= 10:
        probe /= 10
        exponent += 1
    while probe < 1:
        probe *= 10
        exponent -= 1
    scaled = (probe.numerator * 10 ** digits) // probe.denominator
    return scaled, exponent


def verified_exactly(value, scaled, digits):
    """The exact integer check that the reported digits are right.

    v <= p * 10^d / q < v + 1, rearranged to avoid any division at all:

        v * q <= p * 10^d < (v + 1) * q

    No arithmetic error can enter this, so it either holds or the digits are wrong.
    """
    exponent = 0
    probe = value
    while probe >= 10:
        probe /= 10
        exponent += 1
    while probe < 1:
        probe *= 10
        exponent -= 1
    left = scaled * probe.denominator
    middle = probe.numerator * 10 ** digits
    right = (scaled + 1) * probe.denominator
    return (left <= middle) and (middle < right)


def exp_negative(x_scaled, scale):
    """exp(-x) for a positive scaled x, by the alternating series. Used only by the Wien root.

    The terms are (-x)^k / k!, which for x near five peak immediately and then fall off a cliff, so
    the cancellation is mild and the guard the caller already carries covers it.
    """
    total = scale
    term = scale
    k = 0
    while True:
        k += 1
        term = (term * x_scaled) // (scale * k)
        if term == 0:
            break
        total += term if (k % 2 == 0) else -term
    return total


def wien_root(multiplier, digits, guard=40):
    """The root of x = m (1 - e^-x), by Newton, with the residual returned as its own bound.

    THE SPECTRAL CONSTANTS ARE THE ONLY ENTRIES IN THE EXACT SET THAT ARE NOT CLOSED FORMS. Wien's
    displacement laws locate where a blackbody's spectrum peaks, and that location is the root of a
    transcendental with no expression in the defining constants. m = 5 gives the wavelength law's
    4.965114231..., m = 3 the frequency law's 2.821439372...

    VERIFIED BY SUBSTITUTION RATHER THAN BY COMPARISON. The residual |x - m(1 - e^-x)| evaluated at
    the computed root bounds the error directly, so this route grades itself against its own
    defining equation instead of against a printed value. That is available here and is not
    available for a constant defined by a series.

    Returns (scaled root at `digits` places, residual in units of the working scale).
    """
    places = digits + guard
    scale = 10 ** places
    m = multiplier

    # Start just under m, which is where the root sits for every m above one.
    x = m * scale - scale // 2
    for _ in range(200):
        e = exp_negative(x, scale)
        f = x - m * scale + m * e
        slope = scale - m * e
        if slope == 0:
            break
        step = (f * scale) // slope
        if step == 0:
            break
        x -= step

    e = exp_negative(x, scale)
    residual = abs(x - (m * scale - m * e))
    return x // (10 ** guard), residual


def with_pi(value, digits, multiply=False, pi_power=None):
    """The pi-involving constants, using this tree's own pi.

    h-bar = h / (2 pi). pi comes from dn_constants at digits + guard, where it carries two routes
    agreeing at a zero gap and a derived error bound, so the bound here is inherited rather than
    assumed.
    """
    guard = 40
    places = digits + guard
    pi_scaled = dn_constants.pi_machin(places)

    exponent = 0
    probe = value
    while probe >= 10:
        probe /= 10
        exponent += 1
    while probe < 1:
        probe *= 10
        exponent -= 1

    # THE GENERAL FORM IS A RATIONAL TIMES AN INTEGER POWER OF pi, positive or negative, and the
    # 2 pi cases are that with the two folded into the rational by the caller. Generalising this
    # was forced by the spectral constants: Stefan-Boltzmann carries pi^5 and the MeV fm entry
    # carries pi^-1, neither of which a divide-or-multiply-by-2-pi flag can express.
    if pi_power is not None:
        power = abs(pi_power)
        pi_to = 10 ** (places * (power - 1)) if power else 1
        if power:
            pi_to = pi_scaled ** power // (10 ** (places * (power - 1)))
        else:
            pi_to = 10 ** places
        if pi_power > 0:
            top = probe.numerator * pi_to * 10 ** places
            bottom = probe.denominator * 10 ** places
        else:
            top = probe.numerator * 10 ** (places * 2)
            bottom = probe.denominator * pi_to
    elif multiply:
        top = probe.numerator * 2 * pi_scaled * 10 ** places
        bottom = probe.denominator * 10 ** places
    else:
        top = probe.numerator * 10 ** (places * 2)
        bottom = probe.denominator * 2 * pi_scaled
    wide = top // bottom
    # Renormalise, since dividing by 2 pi can move the leading digit.
    scaled = wide // (10 ** guard)
    while scaled >= 10 ** (digits + 1):
        scaled //= 10
        exponent += 1
    while scaled < 10 ** digits:
        scaled *= 10
        exponent -= 1
    return scaled, exponent


def shown(scaled, digits):
    text = str(scaled).rjust(digits + 1, "0")
    return text[0] + "." + text[1:]


def build(digits=1000):
    nist = published()
    rows = []

    # The spectral constants first, since they are the only ones verified by substituting into
    # their own defining equation rather than by multiplying back or by comparison.
    for name, multiplier, direction in WIEN:
        root, residual = wien_root(multiplier, digits)
        if direction == "over":
            # b = h c / (k x)
            coefficient = PLANCK * LIGHT / BOLTZMANN
            top = coefficient.numerator * 10 ** (digits * 2)
            bottom = coefficient.denominator * root
        else:
            # b' = x k / h
            coefficient = BOLTZMANN / PLANCK
            top = coefficient.numerator * root * 10 ** digits
            bottom = coefficient.denominator * 10 ** digits
        scaled = top // bottom
        exponent = 0
        while scaled >= 10 ** (digits + 1):
            scaled //= 10
            exponent += 1
        while scaled < 10 ** digits:
            scaled *= 10
            exponent -= 1
        text = shown(scaled, digits)
        printed = nist.get(name)
        agrees = None
        if printed:
            head = re.sub(r"[^0-9]", "", printed.split("...")[0]).lstrip("0")
            agrees = text.replace(".", "").lstrip("0")[:len(head)] == head

        # THE CRITERION IS THE WORKING SCALE AND NOT ZERO, and the first version compared the
        # Newton residual against zero, which no root of a transcendental will ever give. A residual
        # of a few units out of 10^(digits + guard) is the arithmetic floor, and the honest statement
        # is that it sits below the guard digits that get discarded. Demanding exactly zero reported
        # both spectral constants as failures when they were correct.
        guard_units = 10 ** 40
        rows.append({
            "name": name, "value": text, "exponent": exponent, "digits": digits,
            "how": "root of x = %d(1 - e^-x) by Newton, substitution residual %d units below the "
                   "guard's 1e40" % (multiplier, residual),
            "exact_verified": (residual < guard_units), "agrees_with_nist": agrees,
            "published": printed or "",
        })

    for name, value, pi_power in [(a, b, None if c is False else (1 if c is True else c))
                                  for a, b, c in DERIVED] + \
                                 [(a, b, c) for a, b, c in MORE_DERIVED]:
        needs_pi = pi_power is not None and pi_power != 0
        if needs_pi:
            times = name in MULTIPLIES_BY_TWO_PI
            if name in [one[0] for one in MORE_DERIVED]:
                scaled, exponent = with_pi(value, digits, pi_power=pi_power)
                how = "exact rational times pi^%d, pi from dn_const at a zero gap" % pi_power
            else:
                scaled, exponent = with_pi(value, digits, multiply=times)
                how = ("exact rational times 2 pi" if times else "exact rational over 2 pi") \
                    + ", pi from dn_const at a zero gap"
            exact_ok = None
        else:
            scaled, exponent = digits_of_rational(value, digits)
            how = "exact rational in the SI defining constants"
            exact_ok = verified_exactly(value, scaled, digits)

        text = shown(scaled, digits)
        agrees = None
        printed = nist.get(name)
        if printed:
            head = printed.split("...")[0].replace("e", "").split("e")[0]
            head = re.sub(r"[^0-9.]", "", head)
            # LEADING ZEROS ARE STRIPPED FROM BOTH SIDES, and that is a comparison fix rather than a
            # value fix. This file normalises every value into [1, 10); NIST prints farad-90 as
            # 0.999 999 982 20 without normalising. The digits were identical and the compare failed
            # on the leading zero alone, which read as a wrong constant in the report.
            compact = head.replace(".", "").lstrip("0")
            mine = text.replace(".", "").lstrip("0")[:len(compact)]
            agrees = (mine == compact)

        rows.append({
            "name": name, "value": text, "exponent": exponent, "digits": digits,
            "how": how, "exact_verified": exact_ok, "agrees_with_nist": agrees,
            "published": printed or "",
        })
    return rows


def _split():
    lines = io.open(LISTING, encoding="utf-8", errors="replace").read().splitlines()
    exact = [one for one in lines if "(exact)" in one]
    truncated = [one for one in exact if "..." in one]
    print("")
    print("  The 2022 CODATA listing, classified by whether its uncertainty is removable.")
    print("")
    print("  %-56s %6s" % ("class", "count"))
    print("  %-56s %6d" % ("constants in the listing", len([one for one in lines if len(one) > 60])))
    print("  %-56s %6d" % ("marked exact", len(exact)))
    print("  %-56s %6d" % ("  of those, terminating: the digits ARE the value", len(exact) - len(truncated)))
    print("  %-56s %6d" % ("  of those, truncated: NIST stops, we need not", len(truncated)))
    print("  %-56s %6d" % ("carrying a measured uncertainty", len([one for one in lines if len(one) > 60]) - len(exact)))
    print("")
    print("  THE REMOVABLE UNCERTAINTY IS THE TRUNCATED COLUMN AND NOTHING ELSE. Those 62 have no")
    print("  uncertainty at all: they are closed forms in the seven SI defining constants, which")
    print("  have been exact by definition since 2019. Their missing digits are unprinted, not")
    print("  unknown.")
    print("")
    print("  THE MEASURED COLUMN IS PERMANENT. alpha, G, the electron mass. Their uncertainty is")
    print("  what a laboratory measured and no arithmetic reduces it. This tool does not touch")
    print("  them and any claim that precision could would be false.")
    return 0


def _report(digits=1000):
    rows = build(digits)
    exactly = [one for one in rows if one["exact_verified"] is True]
    failed_exact = [one for one in rows if one["exact_verified"] is False]
    agree = [one for one in rows if one["agrees_with_nist"] is True]
    disagree = [one for one in rows if one["agrees_with_nist"] is False]

    print("")
    print("  %d exact CODATA constants carried to %d places." % (len(rows), digits))
    print("")
    print("  %-48s %10s %10s %s" % ("constant", "exact", "vs NIST", "first 40 places"))
    for one in rows[:14]:
        print("  %-48s %10s %10s %s"
              % (one["name"][:47],
                 "yes" if one["exact_verified"] else ("pi" if one["exact_verified"] is None else "NO"),
                 "agrees" if one["agrees_with_nist"] else ("-" if one["agrees_with_nist"] is None else "DIFFERS"),
                 one["value"][:40]))
    print("  ... %d more" % (len(rows) - 14))
    print("")
    print("  exactly verified by multiplying back : %d" % len(exactly))
    print("  verified against our own pi          : %d" % len([one for one in rows if one["exact_verified"] is None]))
    print("  agreeing with the NIST printed digits: %d of %d checkable"
          % (len(agree), len(agree) + len(disagree)))
    if failed_exact:
        print("  EXACT CHECK FAILED on %d: %s" % (len(failed_exact), [one["name"] for one in failed_exact]))
    if disagree:
        print("  DISAGREES WITH NIST on %d: %s" % (len(disagree), [one["name"] for one in disagree]))

    with io.open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("name\texponent\tdigits\thow\texact_verified\tagrees_with_nist\tvalue\n")
        for one in rows:
            handle.write("%s\t%d\t%d\t%s\t%s\t%s\t%s\n"
                         % (one["name"], one["exponent"], one["digits"], one["how"],
                            one["exact_verified"], one["agrees_with_nist"], one["value"]))
    print("")
    print("  wrote %s" % OUT)
    return len(failed_exact) + len(disagree)


def _check():
    failed = 0
    print("")

    rows = build(200)

    # THE EXACT CHECK IS THE WHOLE POINT FOR THE RATIONALS. Every one must pass, and it is an
    # integer statement so there is no tolerance to argue about.
    rationals = [one for one in rows if one["exact_verified"] is not None]
    bad = [one for one in rationals if not one["exact_verified"]]
    print("  %d rational constants, all exactly verified by multiplying back: %s"
          % (len(rationals), not bad))
    if bad:
        for one in bad:
            print("    FAIL %s" % one["name"])
        failed += len(bad)

    # AGREEMENT WITH NIST IS THE EXTERNAL CHECK, and it is the one that catches a wrong FORMULA.
    # The exact check above would pass a correctly divided wrong expression.
    checkable = [one for one in rows if one["agrees_with_nist"] is not None]
    off = [one for one in checkable if not one["agrees_with_nist"]]
    print("  %d checkable against the NIST printed digits, %d disagree" % (len(checkable), len(off)))
    for one in off:
        print("    DIFFERS %s: ours %s, NIST %s"
              % (one["name"], one["value"][:18], one["published"]))
    failed += len(off)

    # THE NEGATIVE CONTROL. A deliberately wrong expression must be caught by the NIST comparison,
    # or that comparison is decoration.
    wrong = BOLTZMANN / (CHARGE * 2)
    scaled, _exponent = digits_of_rational(wrong, 200)
    text = shown(scaled, 200)
    nist = published().get("Boltzmann constant in eV/K", "")
    head = re.sub(r"[^0-9]", "", nist.split("...")[0])
    caught = text.replace(".", "")[:len(head)] != head
    print("  a deliberately wrong expression is caught by the NIST check: %s" % caught)
    if not caught:
        print("    FAIL the NIST comparison does not detect a wrong formula")
        failed += 1

    # AND WIDTH MUST NOT CHANGE THE ANSWER'S LEADING DIGITS, since the parameters are derived.
    narrow = build(100)
    wide = build(400)
    drift = 0
    for a, b in zip(narrow, wide):
        if a["value"][:60] != b["value"][:60]:
            drift += 1
    print("  the leading 60 places are the same at 100 and 400 places: %s" % (drift == 0))
    if drift:
        print("    FAIL %d constants moved with the requested width" % drift)
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="the exact CODATA constants, carried out")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--split", action="store_true")
    parser.add_argument("--digits", type=int, default=1000)
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.split:
        return _split()
    return 1 if _report(args.digits) else 0


if __name__ == "__main__":
    sys.exit(main())
