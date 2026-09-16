#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CRY-4-002
#
# Find substitutional doping by incidence alone, without reading an occupancy.
#
#   Usage:  python examples/crystallography/4_measure/doping_from_shared_sites.py [entries]
#
# WHAT IS BEING DETECTED
#
# A substitutional dopant is two elements sharing one crystallographic position. That is a
# statement about incidence: two things sitting in the same place. It needs no distance, no
# tolerance and no chemistry, and representation.exact.contested returns exactly it.
#
# No occupancy is read here. The deposit publishes _atom_site_occupancy and that column is the
# answer key, so it belongs to stage six and not to this stage. What this measure sees is only
# where the atoms are and what they are, which is what every other reading in this subject sees.
#
# ONE CELL, NOT A TILING
#
# Doping is a property of the motif and not of the lattice. A mixed site is written once and
# repeats in every cell, so tiling multiplies the count without adding an observation: entry
# 1000091 has four shared positions, and tiled four times an axis it reports 256 of them, being
# the same four seen sixty four times. Read at one cell the count is the number of shared sites
# the deposit actually published.
#
# That is also the reason doping does not disturb the recovered period. The cell repeats exactly
# whatever it contains, dopant included, so the lattice is untouched and the edge comes back
# unchanged. An ideal doped crystal is still perfectly periodic. Stage four's period measure and
# this one are reading two different things out of the same points.
#
# NO CELL IS READ, AND THAT IS NOT AN OPTIMIZATION
#
# This measure does not go through crystal.exact_points, and the first version of it did. That
# version inherited a dependency it had no use for and paid for it immediately: exact_points
# refuses any cell that is not right angled, and 498 of 697 entries came back unreadable, because
# the minerals that carry doping are overwhelmingly monoclinic and triclinic. The measure looked
# like it was failing on three quarters of the corpus. It was not; it was being handed three
# quarters less corpus.
#
# Two sites share a position when the deposit wrote the same three fractional coordinates twice.
# That is a fact about the atom site loop alone. It needs no cell edge, no angle, no tiling and no
# conversion to angstroms, so none of those are read. The coordinates are still carried exactly,
# as integers through representation.exact, because a shared position is decided by equality and
# an equality decided on rounded values is not one.
#
# The general lesson is the one the subject's README already records twice: reach for the smallest
# reading that answers the question. A measure that asks for more of the pipeline than it needs
# inherits every limit that pipeline has.
#
# WHAT THE READER WOULD DO TO THIS, AND WHAT IT ACTUALLY DOES TODAY
#
# representation.exact.placed keeps the last value at a repeated position, so a shared site would
# arrive downstream as one element, chosen by the order the deposit happened to list its rows in.
# Measured on entry 1010929, which puts Cu and Fe on one position: read forward the site is Fe2+,
# read with its rows reversed the same site is Cu2+.
#
# That is a latent hazard and not a live defect, and the distinction is worth stating precisely
# rather than letting the stronger version stand. Two things keep it from biting today. `placed`
# has no callers anywhere in this tree. And `along`, which every period measure here goes through,
# does not overwrite at all: it gathers every value sitting at a coordinate into a sorted tuple, so
# it returns the same arrangement whatever order the rows arrive in. That was checked rather than
# assumed, on the same entry.
#
# So no published result in this subject is affected. What is true is that the first reading to
# reach for `placed` on a structure carrying shared positions inherits a silent dependence on file
# order, and nothing in its signature would say so. `contested` is the primitive that declines to
# make that choice during ingestion and hands the question back to the domain, where it belongs.

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

# Entries listed one by one before the run is summarized.
SHOWN = 20


def doped_sites(text):
    """Positions in one cell carrying more than one element, as {position: (element, ...)}.

    The deposit's own fractional coordinates, carried exactly as integers, with no cell and no
    tiling. Returns None where the entry has no atom site loop, which keeps an entry that cannot
    be read distinct from one that is clean.

    Raises nothing on a malformed coordinate: the site is skipped and counted by the caller. A
    deposit that writes ? for a coordinate is declining to give one, and a site with no position
    cannot share a position with anything.
    """
    rows = crystal.site_table(text)
    if not rows:
        return None, 0
    points = []
    skipped = 0
    for along_a, along_b, along_c, element, _occupancy in rows:
        try:
            position = (exact.scaled(along_a), exact.scaled(along_b), exact.scaled(along_c))
        except ValueError:
            skipped += 1
            continue
        points.append((position, element))
    return exact.contested(points), skipped


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(CACHE):
        out.write("\n  nothing cached under build/cod. Run the oracle or a fetcher to fill it.\n\n")
        out.flush()
        return 1

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    names = sorted(name for name in os.listdir(CACHE) if name.endswith(".cif"))
    if limit:
        names = names[:limit]

    out.write("\n  Substitutional doping read off incidence, with no occupancy column consulted.\n\n")
    out.write("  %-12s %-7s %-9s %s\n" % ("entry", "sites", "shared", "elements sharing a site"))

    read = 0
    unreadable = 0
    doped = 0
    shared_total = 0
    skipped_sites = 0
    pairs = {}
    listed = 0
    started = time.time()

    for name in names:
        with io.open(os.path.join(CACHE, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        found, skipped = doped_sites(text)
        skipped_sites += skipped
        if found is None:
            unreadable += 1
            continue
        read += 1
        if not found:
            continue
        doped += 1
        shared_total += len(found)
        for elements in found.values():
            pairs[elements] = pairs.get(elements, 0) + 1
        if listed < SHOWN:
            listed += 1
            sites = len(crystal.site_table(text))
            shown = sorted({elements for elements in found.values()})
            out.write("  %-12s %-7d %-9d %s\n"
                      % (name[:-4], sites, len(found),
                         "  ".join("/".join(one) for one in shown[:4])))
            out.flush()

    out.write("\n  %d entries read, %d with no atom site loop, %.1fs\n"
              % (read, unreadable, time.time() - started))
    if skipped_sites:
        out.write("  %d sites skipped for a coordinate that is not plain decimal text\n"
                  % skipped_sites)
    out.write("  %d entries carry at least one shared site\n" % doped)
    out.write("  %d shared sites in total\n" % shared_total)
    if read:
        out.write("  %.1f%% of readable entries are doped by this measure\n"
                  % (100.0 * doped / read))

    out.write("\n  the substitutions found, most common first\n")
    for elements, count in sorted(pairs.items(), key=lambda pair: -pair[1])[:20]:
        out.write("     %-28s %d\n" % ("/".join(elements), count))

    out.write("\n  no occupancy was read. Stage six checks these against the published column.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
