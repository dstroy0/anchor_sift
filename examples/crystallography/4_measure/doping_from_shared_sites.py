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
# answer key. It belongs to stage six and not to this stage. What this measure sees is only
# where the atoms are and what they are, which is what every other reading in this subject sees.
#
# ONE CELL, NOT A TILING
#
# Doping is a property of the motif and not of the lattice. A mixed site is written once and
# repeats in every cell. Tiling multiplies the count without adding an observation: entry
# 1000091 has four shared positions, and tiled four times an axis it reports 256 of them, being
# the same four seen sixty four times. Read at one cell the count is the number of shared sites
# the deposit actually published.
#
# That is also the reason doping does not disturb the recovered period. The cell repeats exactly
# whatever it contains, dopant included. The lattice is untouched and the edge comes back
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
# conversion to angstroms. None of those are read. The coordinates are still carried exactly,
# as integers through representation.exact, because a shared position is decided by equality and
# an equality decided on rounded values is not one.
#
# The general lesson is the one the subject's README already records twice: reach for the smallest
# reading that answers the question. A measure that asks for more of the pipeline than it needs
# inherits every limit that pipeline has.
#
# WHAT THE READER WOULD DO TO THIS, AND WHAT IT ACTUALLY DOES TODAY
#
# representation.exact.placed keeps the last value at a repeated position. A shared site would
# arrive downstream as one element, chosen by the order the deposit happened to list its rows in.
# Measured on entry 1010929, which puts Cu and Fe on one position: read forward the site is Fe2+,
# read with its rows reversed the same site is Cu2+.
#
# That is a latent hazard and not a live defect, and the distinction is worth stating precisely
# . Two things keep it from biting today. `placed`
# has no callers anywhere in this tree. And `along`, which every period measure here goes through,
# does not overwrite at all: it gathers every value sitting at a coordinate into a sorted tuple, so
# it returns the same arrangement whatever order the rows arrive in. That was checked.
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


def symbol(written):
    """An element as deposited, reduced to its bare symbol. Fe2+, Fe+2, FE and Fe all give Fe.

    Used only for the folded summary at the end. Nothing in the detection passes through here: two
    sites share a position or they do not, and that is decided on the strings as written.
    """
    letters = "".join(one for one in written if one.isalpha())
    return letters.capitalize() if letters else written


def doped_sites(text):
    """Positions in one cell carrying more than one element, as {position: (element, ...)}.

    The deposit's own fractional coordinates, carried exactly as integers, with no cell and no
    tiling. Returns None where nothing parsed, which keeps an entry that cannot be read distinct
    from one that is clean.

    THE TRIGGER FOR THAT None MOVED, AND IT MOVES A REPORTED NUMBER

    It used to be "the deposit has no atom site rows". It is now "no site parsed", because the
    reading is crystal.exact_sites and an entry whose coordinates all fail to parse comes back with
    an empty list. A deposit that has rows and no usable coordinate used to be
    counted readable with nothing shared, and is now counted unreadable.

    The new behaviour is the more correct one, an entry nothing could be read from is not an entry
    that was read and found clean, but it feeds the "entries read" figure directly, and nothing in
    the change announces itself at the call site. It is the reason this measure and the stage six
    oracle report slightly different counts of shared positions from one corpus: the oracle has no
    equivalent early return.

    Raises nothing on a malformed coordinate: the site is skipped and counted by the caller. A
    deposit that writes ? for a coordinate is declining to give one, and a site with no position
    cannot share a position with anything.
    """
    sites, skipped = crystal.exact_sites(text)
    if not sites:
        return None, skipped
    # The occupancy is dropped here and read at stage six. Which field this projects is the whole
    # difference between this reading and the oracle's; the reading itself is one function.
    return (
        exact.contested([(position, element) for position, element, _ in sites]),
        skipped,
    )


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    if not os.path.isdir(CACHE):
        out.write(
            "\n  nothing cached under build/cod. Run the oracle or a fetcher to fill it.\n\n"
        )
        out.flush()
        return 1

    limit = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    names = sorted(name for name in os.listdir(CACHE) if name.endswith(".cif"))
    if limit:
        names = names[:limit]

    out.write(
        "\n  Substitutional doping read off incidence, with no occupancy column consulted.\n\n"
    )
    out.write(
        "  %-12s %-7s %-9s %s\n"
        % ("entry", "sites", "shared", "elements sharing a site")
    )

    read = 0
    unreadable = 0
    doped = 0
    shared_total = 0
    skipped_sites = 0
    pairs = {}
    order = {}
    coupled = {}
    widest = []
    listed = 0
    started = time.time()

    for name in names:
        with io.open(
            os.path.join(CACHE, name), encoding="utf-8", errors="replace"
        ) as handle:
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
        kinds = set()
        for elements in found.values():
            pairs[elements] = pairs.get(elements, 0) + 1
            # How many elements share the one position. Two is the ordinary case and the tail is
            # where the interesting chemistry is: a rare earth site runs to ten.
            order[len(elements)] = order.get(len(elements), 0) + 1
            if len(elements) >= 4:
                widest.append((name[:-4], len(elements), "/".join(elements)))
            kinds.add(elements)
        # Distinct substitution types in one deposit. Two at once is a coupled substitution, which
        # is how a lattice stays charge balanced while swapping ions of different charge: the
        # plagioclase series runs Al/Si against Ca/Na, and neither half works alone.
        coupled[len(kinds)] = coupled.get(len(kinds), 0) + 1
        if listed < SHOWN:
            listed += 1
            sites = len(crystal.site_table(text))
            shown = sorted({elements for elements in found.values()})
            out.write(
                "  %-12s %-7d %-9d %s\n"
                % (
                    name[:-4],
                    sites,
                    len(found),
                    "  ".join("/".join(one) for one in shown[:4]),
                )
            )
            out.flush()

    out.write(
        "\n  %d entries read, %d with no atom site loop, %.1fs\n"
        % (read, unreadable, time.time() - started)
    )
    if skipped_sites:
        out.write(
            "  %d sites skipped for a coordinate that is not plain decimal text\n"
            % skipped_sites
        )
    out.write("  %d entries carry at least one shared site\n" % doped)
    out.write("  %d shared sites in total\n" % shared_total)
    if read:
        out.write(
            "  %.1f%% of readable entries are doped by this measure\n"
            % (100.0 * doped / read)
        )

    out.write(
        "\n  the substitutions found, as the deposits wrote them, most common first\n"
    )
    for elements, count in sorted(pairs.items(), key=lambda pair: -pair[1])[:15]:
        out.write("     %-28s %d\n" % ("/".join(elements), count))

    # Derived, and labelled as derived. The line above is the measurement: element strings exactly
    # as deposited. Those strings disagree across deposits for the same chemistry, and the corpus
    # carries Fe2+, Fe+2, Fe and FE for one element. The raw tally splits one substitution
    # across four rows and understates every one of them.
    #
    # The grouping below strips the charge and the case to put those back together. It is a reading
    # convenience and not a result, and it is kept separate for that reason: deciding that Fe2+ and
    # Fe+2 are the same element is chemistry this measure is not otherwise doing, and folding it
    # into the measurement would hide a judgement inside a count.
    folded = {}
    for elements, count in pairs.items():
        key = tuple(sorted({symbol(one) for one in elements}))
        if len(key) > 1:
            folded[key] = folded.get(key, 0) + count
    out.write(
        "\n  the same substitutions with charge and case folded together, which is a\n"
    )
    out.write("  reading convenience and not the measurement\n")
    for elements, count in sorted(folded.items(), key=lambda pair: -pair[1])[:15]:
        out.write("     %-28s %d\n" % ("/".join(elements), count))

    out.write("\n  how many elements share one position\n")
    for how_many, count in sorted(order.items()):
        out.write("     %-3d elements   %d positions\n" % (how_many, count))
    out.write(
        "     two is the ordinary case. The tail is not noise: a rare earth site takes\n"
    )
    out.write(
        "     whichever lanthanides were available when the crystal grew, and a spinel\n"
    )
    out.write("     will hold most of the first transition row at once.\n")

    if widest:
        out.write("\n  the widest sites found\n")
        for name, count, elements in sorted(widest, key=lambda row: -row[1])[:8]:
            out.write("     %-12s %-3d %s\n" % (name, count, elements[:58]))

    out.write("\n  distinct substitution types in one deposit\n")
    for how_many, count in sorted(coupled.items()):
        out.write("     %-3d distinct   %d entries\n" % (how_many, count))
    out.write(
        "     two at once is a coupled substitution. A lattice swapping ions of unequal\n"
    )
    out.write(
        "     charge has to balance it somewhere else, and the plagioclase series is the\n"
    )
    out.write(
        "     standard case: Al for Si on one site against Ca for Na on another.\n"
    )

    out.write(
        "\n  no occupancy was read. Stage six checks these against the published column.\n\n"
    )
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
