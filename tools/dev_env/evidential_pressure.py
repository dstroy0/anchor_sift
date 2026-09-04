#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether languages that mark where a claim came from are found where the surroundings are hardest,
# for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/wals_fetch.py        (once, to get the tables)
#           python tools/dev_env/evidential_pressure.py
#
# The claim is that where many things in the surroundings kill people, the pressure to teach is severe,
# and a language under that pressure grammaticalizes what reliable teaching needs: where a claim came
# from, and whether the outcome was anyone's to control. nɬeʔkepmxcín marks both. English marks neither
# and lets you say either optionally.
#
# Two things have to be handled or the answer is worthless.
#
# Languages are not independent of each other. Neighbours share features because they are neighbours and
# relatives share features because they are relatives, so counting languages counts history twice. This is
# Galton's problem and it is old. The fix used here is to draw one language per family, many times, and
# report what the draws do. A pattern that survives one language per family is not simply a large family
# being counted many times.
#
# And cold is the wrong measure of hard. The largest concentration of grammatical evidentiality on earth
# is Amazonia, which is equatorial, and lethal by disease, by what lives there and by having no sightlines.
# A test on distance from the equator would score the strongest case for this claim as the mildest place
# in the sample. So latitude is reported because it is what the data holds, and it is reported as a weak
# proxy that is expected to fail rather than as the test.
#
# What this cannot see: WALS records what a feature is, not why. A correlation here would be consistent
# with the claim and would not establish it, since anything else that follows the same map, contact and
# descent above all, would produce the same number.

import csv
import io
import os
import random
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WALS = os.path.join(ROOT, "build", "wals")

EVIDENTIAL = "78A"
DISTINCTIONS = "77A"
ASPECT = "65A"

DRAWS = 300
SEED = 0x5A15

BANDS = ((0, 15), (15, 30), (30, 45), (45, 60), (60, 90))


def read_table(name):
    """One CLDF table as a list of rows."""
    path = os.path.join(WALS, name)
    with open(path, encoding="utf-8", errors="replace", newline="") as handle:
        return list(csv.DictReader(handle))


def rate_by_family(members, has, rng):
    """The share holding a feature, drawing one language per family, over many draws."""
    families = {}
    for language in members:
        families.setdefault(language["Family"] or "isolate", []).append(language)
    marks = []
    for _ in range(DRAWS):
        drawn = [rng.choice(group) for group in families.values()]
        if not drawn:
            continue
        marks.append(sum(1 for one in drawn if has.get(one["ID"])) / float(len(drawn)))
    if not marks:
        return float("nan"), float("nan"), 0
    return statistics.fmean(marks), statistics.pstdev(marks), len(families)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(WALS):
        out.write("  no %s, run wals_fetch.py first\n" % WALS)
        out.flush()
        return 1

    codes = read_table("codes.csv")
    out.write("  what the readings of feature %s mean\n" % EVIDENTIAL)
    absent = set()
    for row in codes:
        if row["Parameter_ID"] != EVIDENTIAL:
            continue
        out.write("  %-10s %s\n" % (row["ID"], row["Name"]))
        if "no grammatical" in row["Name"].lower():
            absent.add(row["ID"])
    out.write("  the readings counted as marking it are all but %s\n" % ", ".join(sorted(absent)))

    languages = {row["ID"]: row for row in read_table("languages.csv")}
    values = read_table("values.csv")

    has = {}
    for row in values:
        if row["Parameter_ID"] != EVIDENTIAL:
            continue
        has[row["Language_ID"]] = row["Code_ID"] not in absent

    members = [languages[key] for key in has if key in languages]
    out.write("\n  %d languages carry a reading for %s\n" % (len(members), EVIDENTIAL))

    rng = random.Random(SEED)

    out.write("\n  by part of the world, one language drawn per family\n")
    out.write("  %-16s %-9s %-11s %-11s %s\n"
              % ("where", "languages", "families", "share marking", "spread"))
    areas = {}
    for language in members:
        areas.setdefault(language["Macroarea"] or "unknown", []).append(language)
    for area in sorted(areas, key=lambda key: -len(areas[key])):
        share, spread, families = rate_by_family(areas[area], has, rng)
        out.write("  %-16s %-9d %-11d %-11.3f %.3f\n"
                  % (area, len(areas[area]), families, share, spread))

    out.write("\n  by distance from the equator, one language drawn per family\n")
    out.write("  %-16s %-9s %-11s %-11s %s\n"
              % ("degrees", "languages", "families", "share marking", "spread"))
    for low, high in BANDS:
        band = []
        for language in members:
            try:
                far = abs(float(language["Latitude"]))
            except (TypeError, ValueError):
                continue
            if (far >= low) and (far < high):
                band.append(language)
        if len(band) < 12:
            continue
        share, spread, families = rate_by_family(band, has, rng)
        out.write("  %-16s %-9d %-11d %-11.3f %.3f\n"
                  % ("%d to %d" % (low, high), len(band), families, share, spread))

    whole, spread, families = rate_by_family(members, has, rng)
    out.write("\n  everywhere, one language per family   %.3f, spread %.3f, over %d families\n"
              % (whole, spread, families))

    out.write("\n  the same for obligatory aspect, feature %s\n" % ASPECT)
    aspect_absent = set()
    for row in codes:
        if row["Parameter_ID"] != ASPECT:
            continue
        if "no grammatical" in row["Name"].lower():
            aspect_absent.add(row["ID"])
    aspect_has = {}
    for row in values:
        if row["Parameter_ID"] != ASPECT:
            continue
        aspect_has[row["Language_ID"]] = row["Code_ID"] not in aspect_absent
    aspect_members = [languages[key] for key in aspect_has if key in languages]
    out.write("  %-16s %-9s %-11s %-11s %s\n"
              % ("where", "languages", "families", "share marking", "spread"))
    aspect_areas = {}
    for language in aspect_members:
        aspect_areas.setdefault(language["Macroarea"] or "unknown", []).append(language)
    for area in sorted(aspect_areas, key=lambda key: -len(aspect_areas[key])):
        share, spread, families = rate_by_family(aspect_areas[area], aspect_has, rng)
        out.write("  %-16s %-9d %-11d %-11.3f %.3f\n"
                  % (area, len(aspect_areas[area]), families, share, spread))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
