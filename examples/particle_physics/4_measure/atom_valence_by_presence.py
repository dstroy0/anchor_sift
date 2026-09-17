#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-4-002
#
# The atom read by presence: nothing is falsy, something is truthy, and the valence is measured.
#
#   Usage:  python examples/particle_physics/4_measure/atom_valence_by_presence.py
#
# The primitive is shaped like a physical atom. A dense core sits at the center of an n by n field and
# bands radiate outward, grouped by the squared magnitude of each cell's vector from the core, an exact
# integer. The object writes a vector magnitude into each cell. Zero is nothing and reads falsy; a
# nonzero magnitude is something and reads truthy. The engine stores none of what the object is. It
# measures the presence pattern over the bands and reads the outermost band that holds something. That
# outermost band is the valence.
#
# Nothing here divides, holds a ratio, or compares an energy. A band is exactly full or it is not, a
# boolean. The reading is presence and a popcount, a cardinality of quanta. The null is drawn as the
# union of many shuffles of the object's own magnitudes: scattered something fills a whole outer shell
# only by an accident the null rarely reaches, so a full shell that survives the null is a genuine band.
#
# Positive control: an atom with a full core and one full outer shell reads that shell as its valence,
# and the shell survives the null. Negative control: the same amount of something scattered at random
# fills no outer shell that survives. Two routes read each fact and must agree.

import io
import os
import random
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from reference.atom import bands, occupancy, occupied_bands, full_bands, valence  # noqa: E402
from reference.bitfield import present, count, only_in, same  # noqa: E402
from reference.shuffles import permuted  # noqa: E402

SIZE = 5
DRAWS = 64
SEED = 0xA70E  # a declared seed; nothing about the reading was chosen from output


def full_bands_by_count(cells, band_list):
    """Second route: a band is full when the count of its occupied cells equals its size."""
    field = 0
    for position, members in enumerate(band_list):
        occupied = sum(1 for cell in members if cells & (1 << cell))
        if members and occupied == len(members):
            field |= 1 << position
    return field


def null_union_full(magnitudes, band_list, draws, seed):
    """Draw the null as the union over shuffles of the full-band field: the shells chance can fill."""
    union = 0
    for step in range(draws):
        shuffled = list(permuted(magnitudes, seed + step))
        union |= full_bands(occupancy(shuffled), band_list)
    return union


def build_atom(band_list, filled):
    """A field of n*n vector magnitudes: every cell of the named bands holds something, the rest nothing."""
    magnitudes = [0] * (SIZE * SIZE)
    for position in filled:
        for cell in band_list[position]:
            magnitudes[cell] = position + 1          # a nonzero vector magnitude, growing outward
    return magnitudes


def scatter(count_wanted, seed):
    """The same amount of something, placed at random cells: a distribution with no shell structure."""
    rng = random.Random(seed)
    magnitudes = [0] * (SIZE * SIZE)
    for cell in rng.sample(range(SIZE * SIZE), count_wanted):
        magnitudes[cell] = 1
    return magnitudes


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    band_list = bands(SIZE)
    core, shell = 0, 3                                # the core, and one outer shell as the planted valence

    out.write("  the atom read by presence: nothing falsy, something truthy, valence measured\n")
    out.write("  a %dx%d field, %d bands by squared radial magnitude, core first\n"
              % (SIZE, SIZE, len(band_list)))
    out.write("  band sizes (core to edge): %s\n\n" % [len(members) for members in band_list])

    magnitudes = build_atom(band_list, (core, shell))
    cells = occupancy(magnitudes)
    planted = count(cells)

    occ = occupied_bands(cells, band_list)
    route_a = full_bands(cells, band_list)
    route_b = full_bands_by_count(cells, band_list)
    read_valence = valence(cells, band_list)

    out.write("  planted atom: full core (band %d) and one full outer shell (band %d)\n" % (core, shell))
    out.write("    something in %d of %d cells\n" % (planted, SIZE * SIZE))
    out.write("    occupied bands (presence per shell): %s\n" % bin(occ))
    out.write("    two routes read the full bands identically: %s\n" % same(route_a, route_b))
    out.write("    valence, the outermost band holding something: band %d\n\n" % read_valence)

    union = null_union_full(magnitudes, band_list, DRAWS, SEED ^ 0x11)
    survived = only_in(route_a, union)
    out.write("  draw the null: %d shuffles of the same magnitudes, the full shells chance can fill\n" % DRAWS)
    out.write("    full bands a shuffle ever filled: %s\n" % bin(union))
    out.write("    full bands the object holds that no shuffle reached: %s (%d)\n"
              % (bin(survived), count(survived)))
    survived_valence = survived.bit_length() - 1 if present(survived) else -1
    out.write("    the surviving shell is the valence: band %d\n\n" % survived_valence)

    noise = scatter(planted, SEED)
    noise_cells = occupancy(noise)
    noise_union = null_union_full(noise, band_list, DRAWS, SEED ^ 0x22)
    noise_survived = only_in(full_bands(noise_cells, band_list), noise_union)
    out.write("  negative control: the same %d something scattered at random\n" % planted)
    out.write("    full shells the object holds that no shuffle reached: %d\n\n" % count(noise_survived))

    verdict = (read_valence == shell) and same(route_a, route_b) \
        and (survived_valence == shell) and (not present(noise_survived))
    out.write("  reading: the valence is the outermost band that holds something, measured from the\n")
    out.write("  presence pattern. the planted shell survives the drawn null; scattered something does\n")
    out.write("  not. presence and a popcount, no ratio and no band crossing. verdict: %s\n" % verdict)
    out.flush()
    return 0 if verdict else 1


if __name__ == "__main__":
    raise SystemExit(main())
