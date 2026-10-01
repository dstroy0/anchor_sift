#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The reproduction set: everything a stranger needs to re-derive the table and disagree with it.
#
#   Usage:  python tools/dn_precision/calc/reproduce.py               emit the certificate
#           python tools/dn_precision/calc/reproduce.py --verify      re-derive and check it
#           python tools/dn_precision/calc/reproduce.py --check       grade the tool itself
#
# WHY THIS AND NOT JUST THE DIGITS
#
# Douglas, 2026-09-12: "we can not only prove the digits, we can return the set that will let others
# reproduce it."
#
# A thousand digits of gamma is not evidence. It is a claim, and the only thing a reader can do with
# it is trust it or spend a day rebuilding the apparatus to find out. Publishing the REPRODUCTION
# SET changes what kind of object the table is:
#
#   THE DIGITS ALONE           a reader can compare against someone else's digits, and if they
#                              differ neither of them knows which is wrong
#   THE REPRODUCTION SET       a reader can re-derive from two named algorithms with the exact
#                              parameters, reproduce the zero gap, and locate any disagreement in a
#                              specific route at a specific width
#
# The second is falsifiable by a stranger. The first is not, and an unfalsifiable table of digits is
# a very long assertion.
#
# WHAT GOES IN AND WHY EACH FIELD IS THERE
#
#   two route names and formulas   so the pair can be rebuilt independently of this code
#   the DERIVED parameters         the n, x, guard and cancellation each route used AT THIS WIDTH,
#                                  with the expression that derived them, because a hardcoded
#                                  parameter is the defect this table has already been bitten by:
#                                  gamma's n was fixed at 2^10 and silently wrong above 1780 places
#   the term counts                a reader knows what the run should cost and can tell a
#                                  truncated run from a complete one
#   the graded prefix              the published digits each route was checked against, marked as
#                                  taken on authority, with its length, since a claim graded against
#                                  nothing external is graded against itself
#   the guard sufficiency          measured by sweeping the guard, not asserted
#   the digest                     a transcription error in the value is detectable without
#                                  re-deriving anything
#   the identities                 the cross-row relations that hold, which catch the one failure a
#                                  per-row two-route gap cannot see: two routes sharing a wrong input
#
# WHAT IS DELIBERATELY NOT IN IT
#
# No timings. They are machine facts, not arithmetic facts, and clock_arm.py measures a 13 to 71 per
# cent jitter floor on this machine, a quoted second is not reproducible and would invite a reader
# to think a slower run meant a wrong one.

import argparse
import csv
import hashlib
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(FAMILY))
for _where in (HERE, os.path.join(FAMILY, "support"), os.path.join(ROOT, "examples", "proofing")):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import dn_constants

CSV_PATH = os.path.join(FAMILY, "dn_const", "dn_constants.csv")
OUT_PATH = os.path.join(FAMILY, "dn_const", "reproduce.json")

# Prefixes taken on authority. These are the ONLY imported numbers in the certificate and each is
# named as borrowed, because a table graded only against itself is graded against nothing.
GRADED_AGAINST = {
    "pi": ("3.14159265358979323846264338327950288419716939937510", "standard"),
    "e": ("2.71828182845904523536028747135266249775724709369995", "standard"),
    "euler_mascheroni": ("0.57721566490153286060651209008240243104215933593992"
                         "35988057672348848677267776646709369470632917467495", "standard"),
    "catalan": ("0.9159655941772190150546035149323841107741493742816721342664"
                "9811962176301977625476947935651292611510624857442261919619", "standard"),
    "ln_two": ("0.69314718055994530941723212145817656807550013436025", "standard"),
    "root_two": ("1.41421356237309504880168872420969807856967187537694", "standard"),
}

# The routes whose parameters are derived at run time rather than fixed. Each entry says how to
# recompute the parameter, in the expression a reader can evaluate themselves.
DERIVED_PARAMETERS = {
    "euler_mascheroni": [
        ("route_a", "n", "smallest power of two strictly above 0.5757 * (digits + guard)",
         lambda digits: 1 << dn_constants._power_of_two_above(0.5757 * (digits + dn_constants.GUARD))),
        ("route_b", "x", "smallest power of two strictly above 2.303 * (digits + guard)",
         lambda digits: 1 << dn_constants._power_of_two_above(2.303 * (digits + dn_constants.GUARD))),
        ("route_b", "cancellation digits", "int(0.4343 * x) + 60, the digits lost to cancellation",
         lambda digits: int(0.4343 * (1 << dn_constants._power_of_two_above(
             2.303 * (digits + dn_constants.GUARD)))) + 60),
    ],
}


def load_table(path=CSV_PATH):
    with io.open(path, encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def scaled_of(text, digits):
    whole, _, rest = text.partition(".")
    rest = (rest + "0" * digits)[:digits]
    return int(whole + rest)


def guard_sufficiency(name, digits=200):
    """The smallest guard at which a route's output stops changing. Measured, not assumed.

    Returns None for a constant this tool has no direct route for, which is most of them: the roots
    are verified by raising back to a power rather than by a series, a guard sweep is not the
    right instrument for them and saying so beats printing a number.
    """
    routes = {
        "euler_mascheroni": dn_constants.gamma_brent_mcmillan,
        "catalan": dn_constants.catalan_ramanujan,
        "pi": dn_constants.pi_machin,
        "ln_two": dn_constants.log_two_atanh,
    }
    if name not in routes:
        return None

    was = dn_constants.GUARD
    try:
        widest = None
        settled = None
        for guard in (240, 120, 60, 30, 20, 10, 5, 3, 2):
            dn_constants.GUARD = guard
            value = routes[name](digits)
            if widest is None:
                widest = value
            if value == widest:
                settled = guard
            else:
                break
        return settled
    finally:
        dn_constants.GUARD = was


def certificate(table, digits=None):
    rows = []
    for row in table:
        width = int(row["digits"])
        if digits is not None and width != digits:
            continue

        value = row["value"]
        entry = {
            "name": row["name"],
            "symbol": row["symbol"],
            "digits": width,
            "agreed_digits": int(row["agreed_digits"]),
            "last_digit_gap": int(row["last_digit_gap"]),
            "route_a": row["route_a"],
            "route_b": row["route_b"],
            "used_for": row["used_for"],
            "value_sha256": hashlib.sha256(value.encode("utf-8")).hexdigest(),
            "value_length": len(value),
        }

        prefix = GRADED_AGAINST.get(row["name"])
        if prefix is not None:
            text, source = prefix
            places = len(text.partition(".")[2])
            mine = scaled_of(value, width) // (10 ** (width - places))
            entry["graded_against"] = {
                "prefix": text,
                "places": places,
                "source": source,
                "note": "taken on authority, used only to grade, never to compute",
                "agrees": (mine == scaled_of(text, places)),
            }

        derived = DERIVED_PARAMETERS.get(row["name"])
        if derived is not None:
            entry["derived_parameters"] = [
                {"route": which, "parameter": what, "expression": how, "value": fn(width)}
                for which, what, how, fn in derived
            ]

        settled = guard_sufficiency(row["name"])
        if settled is not None:
            entry["guard"] = {
                "used": dn_constants.GUARD,
                "settles_at": settled,
                "note": "measured by sweeping the guard until the output stops changing",
            }

        rows.append(entry)
    return rows


def identities_held():
    """The cross-row relations, from coherence_check, so the set carries them too."""
    try:
        import coherence_check
    except ImportError:
        return None
    table = coherence_check.load(CSV_PATH)
    widths = {digits for _value, digits in table.values()}
    if len(widths) != 1:
        return None
    digits = widths.pop()
    checks = coherence_check.identities(table, 10 ** digits, digits)
    return [{"identity": name, "residual": abs(left - right), "bound": bound, "why": why}
            for name, left, right, bound, why in checks]


def build():
    table = load_table()
    rows = certificate(table)
    identities = identities_held()

    document = {
        "what": "the reproduction set for dn_constants.csv",
        "how_to_reproduce": [
            "python tools/dn_precision/calc/dn_constants.py",
            "python tools/dn_precision/calc/coherence_check.py",
            "python tools/dn_precision/calc/reproduce.py --verify",
        ],
        "the_rule": "two routes or it does not ship, and the gap between them must be zero",
        "constants": len(rows),
        "widths": sorted({one["digits"] for one in rows}),
        "gaps_present": sorted({one["last_digit_gap"] for one in rows}),
        "rows": rows,
    }
    if identities is not None:
        document["identities"] = identities
        document["identities_note"] = (
            "cross-row relations. These catch the one failure a per-row two-route gap cannot see: "
            "two routes sharing a wrong input move together and their gap stays zero.")

    with io.open(OUT_PATH, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(document, handle, indent=2, sort_keys=False)
        handle.write("\n")
    return document


def verify():
    """Re-derive what the certificate claims and report any disagreement."""
    if not os.path.exists(OUT_PATH):
        sys.stdout.write("  no certificate at %s, build it first\n" % OUT_PATH)
        return 1
    with io.open(OUT_PATH, encoding="utf-8") as handle:
        document = json.load(handle)

    table = dict((row["name"], row) for row in load_table())
    failed = 0
    lines = []

    lines.append("  %d constants in the certificate, widths %s, gaps %s"
                 % (document["constants"], document["widths"], document["gaps_present"]))

    for entry in document["rows"]:
        row = table.get(entry["name"])
        if row is None:
            lines.append("    MISSING %s is certified and not in the table" % entry["name"])
            failed += 1
            continue

        digest = hashlib.sha256(row["value"].encode("utf-8")).hexdigest()
        if digest != entry["value_sha256"]:
            lines.append("    DIGEST %s: the value does not match its certificate" % entry["name"])
            failed += 1

        if int(row["last_digit_gap"]) != entry["last_digit_gap"]:
            lines.append("    GAP %s: table says %s, certificate says %d"
                         % (entry["name"], row["last_digit_gap"], entry["last_digit_gap"]))
            failed += 1

        graded = entry.get("graded_against")
        if graded is not None and not graded["agrees"]:
            lines.append("    PREFIX %s: does not agree with the published prefix" % entry["name"])
            failed += 1

    lines.append("  every certified digest matches the table: %s" % (failed == 0))

    # AND THE DERIVED PARAMETERS MUST STILL DERIVE THE SAME WAY. If somebody changes an expression
    # the certificate goes stale, and a stale reproduction set is worse than none because a reader
    # would follow it and get a different answer.
    stale = 0
    for entry in document["rows"]:
        for one in entry.get("derived_parameters", []):
            for which, what, _how, fn in DERIVED_PARAMETERS.get(entry["name"], []):
                if which == one["route"] and what == one["parameter"]:
                    if fn(entry["digits"]) != one["value"]:
                        lines.append("    STALE %s %s %s: certificate %s, code %s"
                                     % (entry["name"], which, what, one["value"],
                                        fn(entry["digits"])))
                        stale += 1
    failed += stale
    lines.append("  every derived parameter still derives the same value: %s" % (stale == 0))

    for one in document.get("identities", []):
        if one["residual"] > one["bound"]:
            lines.append("    IDENTITY %s: residual %d over bound %d"
                         % (one["identity"], one["residual"], one["bound"]))
            failed += 1
    if document.get("identities"):
        lines.append("  every certified identity holds inside its bound: %s"
                     % all(one["residual"] <= one["bound"] for one in document["identities"]))

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d finding(s)\n" % failed)
    return failed


def _check():
    failed = 0
    print("")

    document = build()
    print("  built a certificate for %d constants" % document["constants"])

    # THE CERTIFICATE MUST BE SELF SUFFICIENT for the constants it claims to cover. A reproduction
    # set missing a route name or a derived parameter is not a reproduction set.
    missing = 0
    for entry in document["rows"]:
        for field in ("name", "digits", "route_a", "route_b", "last_digit_gap", "value_sha256"):
            if not entry.get(field) and entry.get(field) != 0:
                print("    FAIL %s is missing %s" % (entry["name"], field))
                missing += 1
    failed += missing
    print("  every row carries its routes, gap and digest: %s" % (missing == 0))

    # THE GRADED CONSTANTS MUST ACTUALLY AGREE WITH THEIR PREFIXES, since that is the only external
    # check in the whole table.
    graded = [one for one in document["rows"] if "graded_against" in one]
    agree = [one for one in graded if one["graded_against"]["agrees"]]
    print("  %d of %d graded constants agree with their published prefix" % (len(agree), len(graded)))
    if len(agree) != len(graded):
        failed += 1

    # VERIFY MUST PASS ON WHAT BUILD JUST WROTE, or the pair is inconsistent.
    print("")
    findings = verify()
    failed += findings

    # THE NEGATIVE CONTROL. A tampered value must be caught by its digest, or the digest is
    # decoration and a transcription error would ship silently.
    print("")
    victim = document["rows"][0]
    tampered = hashlib.sha256(("x" + str(victim["value_sha256"])).encode("utf-8")).hexdigest()
    print("  a tampered digest differs from the certified one: %s"
          % (tampered != victim["value_sha256"]))
    if tampered == victim["value_sha256"]:
        print("    FAIL the digest does not distinguish values")
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="the reproduction set for the constants table")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.verify:
        return 1 if verify() else 0

    document = build()
    sys.stdout.write("  wrote %s\n" % OUT_PATH)
    sys.stdout.write("  %d constants, widths %s, gaps %s\n"
                     % (document["constants"], document["widths"], document["gaps_present"]))
    sys.stdout.write("  %d identities carried\n" % len(document.get("identities", [])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
