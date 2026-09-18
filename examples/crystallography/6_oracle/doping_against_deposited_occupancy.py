#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-6-002
#
# Check doping found by incidence against the occupancy column that finding never read.
#
#   Usage:  python examples/crystallography/6_oracle/doping_against_deposited_occupancy.py [entries]
#
# WHAT MAKES THIS AN ORACLE AND NOT A RESTATEMENT
#
# Stage four finds a doped site by incidence: two elements written at the same three fractional
# coordinates. It never opens _atom_site_occupancy. The deposit publishes that column separately,
# and it is a different measurement by the same people: how much of each element sits there.
#
# So there is a prediction to test. If two elements genuinely share one position, the deposit
# should not be claiming both are fully present. Each occupancy should be under 1, and the
# occupancies at that position should sum to about 1, because the site is one site.
#
# If instead a shared position comes back with every occupancy at 1, one of two things is true: the
# detection is wrong, or the deposit is internally inconsistent. Either is worth knowing and
# neither can be seen from one column alone.
#
# A FALSIFIER YOU CANNOT TELL FROM A DEPOSIT DEFECT IS NOT A FALSIFIER YET
#
# This file said for a while that the full occupancy count "is the one that would falsify the
# detection", and that was a badly built test. It named a number whose appearance was supposed to
# settle the question, and the number cannot settle it: a shared position with two full occupancies
# is the reading being wrong OR the deposit contradicting itself, and the count is identical either
# way. Stating a falsifier without stating how to tell it from the alternative leaves a test that
# looks decisive and is not.
#
# The repair is to say what distinguishes them, which is reading the deposit. COD 1011256, from
# 1933, writes `Si1 Si4+ 8 d 0.25 0.25 0.875 1.` and `Al1 Al3+ 8 d 0.25 0.25 0.875 1.`: identical
# coordinates, identical Wyckoff letter, both at full occupancy, sixteen atoms on eight places. The
# coordinates being character for character the same is what rules out the reading and leaves the
# deposit. That is an older convention for a disordered site, naming both partners without
# normalizing, and not a substitution this instrument invented.
#
# THE CONVERSE IS THE HALF THAT IS EASY TO MISS
#
# A site published under full occupancy that is NOT shared with anything is a vacancy, not a
# dopant. Nothing substitutes there; the atom is simply absent some of the time. A detector that
# called every occupancy under 1 a dopant would be wrong on exactly these, and they are more
# numerous than the doped sites. Both counts are reported, because a detector is characterized by
# what it declines as much as by what it finds.
#
# WHOSE TOLERANCE THIS IS
#
# The sum test carries a tolerance and the period measures in this subject do not. The difference
# matters and it is not a softening of the standard. A coordinate is a position and two sites
# either were written at the same one or were not, which is an equality. An occupancy is a measured
# quantity, published rounded, and two of them summing to 0.999 is a deposit reporting a full site
# to the precision it had. The tolerance below is the deposit's own and not this instrument's, and
# it is applied to the deposit's numbers. The sum itself is
# computed exactly, as integers.

import io
import os
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation import exact  # noqa: E402
from representation.structure import crystal  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")

# How far a sum of published occupancies may sit from a full site and still count as one. This is
# slack for the deposit's rounding, not for any arithmetic done here. Expressed at the scale so the
# comparison stays integer throughout: 0.02 of a site.
SLACK = 2 * (10 ** (exact.SCALE_DIGITS - 2))
FULL = 10**exact.SCALE_DIGITS

# Entries listed one by one before the run is summarized.
SHOWN = 18


def sites_at_positions(text):
    """The deposit's sites grouped by exact fractional position, as {position: [(element, occ)]}.

    `occ` is the occupancy text as published, or None where the deposit carries no such column.
    A site whose coordinates are not plain decimal text is skipped and counted.
    """
    # A projection of crystal.exact_sites, which is where the reading lives. This one keeps the
    # occupancy, the field stage four deliberately does not look at, and groups by
    # position so a shared site arrives as one entry holding several elements.
    grouped = {}
    sites, skipped = crystal.exact_sites(text)
    for position, element, occupancy in sites:
        grouped.setdefault(position, []).append((element, occupancy))
    return grouped, skipped


def total_occupancy(holders):
    """The published occupancies at one position, summed exactly. None where any is missing.

    Returns (total, count_under_full). The sum is integer arithmetic at the scale: no float enters,
    so the only inexactness in this check is the deposit's own rounding, which SLACK covers.
    """
    total = 0
    under = 0
    for _element, occupancy in holders:
        if occupancy is None:
            return None, 0
        try:
            value = exact.scaled(occupancy)
        except ValueError:
            return None, 0
        total += value
        if value < FULL:
            under += 1
    return total, under


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    if not os.path.isdir(CACHE):
        out.write("\n  nothing cached under build/cod. Run a fetcher to fill it.\n\n")
        out.flush()
        return 1

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    names = sorted(name for name in os.listdir(CACHE) if name.endswith(".cif"))
    if limit:
        names = names[:limit]

    out.write(
        "\n  Doping found by incidence, checked against the occupancy column it never read.\n\n"
    )
    out.write(
        "  %-12s %-9s %-22s %s\n"
        % ("entry", "shared", "elements", "published occupancies")
    )

    entries = 0
    shared_seen = 0
    agreed = 0
    part_vacant = 0
    impossible = 0
    full_at_shared = 0
    no_column = 0
    vacancies = 0
    skipped_sites = 0
    listed = 0
    started = time.time()

    for name in names:
        with io.open(
            os.path.join(CACHE, name), encoding="utf-8", errors="replace"
        ) as handle:
            text = handle.read()
        grouped, skipped = sites_at_positions(text)
        skipped_sites += skipped
        if not grouped:
            continue
        entries += 1

        for position, holders in grouped.items():
            elements = sorted({element for element, _ in holders})
            if len(elements) < 2:
                # Not shared. A single element under full occupancy is a vacancy and not a dopant,
                # the case stage four correctly declines to report.
                total, under = total_occupancy(holders)
                if (total is not None) and under:
                    vacancies += 1
                continue

            shared_seen += 1
            total, under = total_occupancy(holders)
            if total is None:
                no_column += 1
                continue
            if abs(total - FULL) <= SLACK:
                agreed += 1
            elif total < FULL:
                part_vacant += 1
            else:
                impossible += 1
                out.write(
                    "  OVER  %-12s %-22s sum exceeds a full site\n"
                    % (name[:-4], "/".join(elements)[:22])
                )
            if under == 0:
                full_at_shared += 1

            if listed < SHOWN:
                listed += 1
                written = "  ".join(
                    occupancy if occupancy else "none"
                    for _element, occupancy in holders
                )
                out.write(
                    "  %-12s %-9s %-22s %s\n"
                    % (name[:-4], "yes", "/".join(elements)[:22], written[:44])
                )
                out.flush()

    checked = agreed + part_vacant + impossible
    out.write("\n  %d entries, %.1fs\n" % (entries, time.time() - started))
    if skipped_sites:
        out.write(
            "  %d sites skipped for a coordinate that is not plain decimal text\n"
            % skipped_sites
        )

    out.write("\n  shared positions found by incidence      %d\n" % shared_seen)
    out.write("  of those, no occupancy column published  %d\n" % no_column)
    out.write("  of those, checkable against the column   %d\n" % checked)

    # Three outcomes, not two. The first draft of this scored pass against fail and reported the
    # second line below as a 16.3% failure, which was the wrong question asked of the right data.
    # A site can be substituted AND partly vacant at once, and the deposit saying so is not a
    # disagreement with anything. Only the third line is an inconsistency.
    out.write("\n  sum to a full site, pure substitution     %d\n" % agreed)
    out.write(
        "  sum under a full site, substitution over a partly vacant site  %d\n"
        % part_vacant
    )
    out.write(
        "  sum over a full site, more atoms than the site holds           %d\n"
        % impossible
    )
    if checked:
        out.write(
            "\n  physically consistent                     %d of %d  (%.1f%%)\n"
            % (checked - impossible, checked, 100.0 * (checked - impossible) / checked)
        )
    out.write(
        "  shared positions where every element is published at full occupancy  %d\n"
        % full_at_shared
    )
    out.write(
        "     A deposit claiming two elements are both entirely present at one position\n"
    )
    out.write(
        "     contradicts either this reading or itself, and the count alone does not say\n"
    )
    out.write(
        "     which. It is a flag to open, not a verdict. Every one inspected in this\n"
    )
    out.write("     corpus has been the deposit: COD 1011256, from 1933, writes\n")
    out.write(
        "     `Si1 Si4+ 8 d 0.25 0.25 0.875 1.` and `Al1 Al3+ 8 d 0.25 0.25 0.875 1.`,\n"
    )
    out.write(
        "     identical coordinates and Wyckoff letter, both at full occupancy, which is\n"
    )
    out.write(
        "     sixteen atoms on eight places. It is how an older deposit describes a\n"
    )
    out.write("     disordered site: name both partners, do not normalize.\n")

    out.write(
        "\n  single element positions under full occupancy, which are vacancies and not\n"
    )
    out.write(
        "  doping, and which stage four correctly does not report   %d\n" % vacancies
    )
    out.write(
        "\n  the incidence reading never opened the occupancy column. Where the two agree,\n"
    )
    out.write(
        "  two independent fields of the same deposit are saying the same thing.\n\n"
    )
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
