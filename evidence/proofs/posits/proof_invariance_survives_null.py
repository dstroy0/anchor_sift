#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-012
#
# Proof of the posit that an exact invariant of the field survives a drawn null while a non-invariant
# does not, from the posits section of theory/workbooks/anchor_sift (exact_inspection_and_the_cloud_clock).
#
#   Usage:  python evidence/proofs/posits/proof_invariance_survives_null.py
#
# The posit. A partition groups the cells of the atom field into bands. A band is an exact invariant when
# every member holds one value, a bit-exact fact read through reference/bitfield.py, one bit per band.
# The null is drawn as the union over many shuffles of the object's own values under the same partition.
# The cells the object holds that the union never reaches are the object's real invariance, read as
# presence and a popcount, with no ratio, threshold, or magnitude.
#
# The drawn null has to exclude two faults, and the proof names both. The first is a false invariant that
# survives by accident: a band that is invariant in the object only by coincidence, which some shuffle
# also makes invariant. The union absorbs it and it does not survive. The size-one core is the clean
# instance, invariant in every arrangement. It never survives. The second is the instrument defect of
# a real invariant that a null drawn too hard erases: a genuinely uniform multi-cell shell must survive
# even a large draw, or the null is destroying truth. The proof shows the real shell surviving 128 draws.
#
# Proven over reference/bitfield.py and reference/atom.py through measure/invariance.py, with cases fixed
# by construction. Two routes read the invariant bands, one testing every member against the first and
# one testing the value the band agrees on against every member, and they must agree.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from reference.atom import bands  # noqa: E402
from measure.invariance import (invariant_cells, invariant_cells_by_consensus,  # noqa: E402
                                 null_union, surviving)
from reference.bitfield import count, same, only_in  # noqa: E402

SIZE = 5
CORE, SHELL = 0, 3
HEAVY_DRAWS = 128
SEED = 0x1A70


def build_field(band_list):
    """A field of vector magnitudes: a full uniform outer shell, a size-one core, distinct elsewhere.

    The uniform shell is a real invariant. The core is invariant only because it holds one cell. Every
    other cell holds a distinct magnitude. No other band is uniform.
    """
    magnitudes = [0] * (SIZE * SIZE)
    fill = 10
    for position, members in enumerate(band_list):
        if position == SHELL:
            for cell in members:
                magnitudes[cell] = 7            # one value across the whole shell: a real invariant
        elif position == CORE:
            magnitudes[members[0]] = 3          # the single core cell
        else:
            for cell in members:
                fill += 1
                magnitudes[cell] = fill         # distinct everywhere else. These bands are not uniform
    return magnitudes


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    band_list = bands(SIZE)
    magnitudes = build_field(band_list)

    out.write("  posit: an exact invariant band survives the drawn null; a non-invariant does not\n")
    out.write("  a %dx%d atom field, %d radial bands, sizes %s\n\n"
              % (SIZE, SIZE, len(band_list), [len(members) for members in band_list]))

    route_a = invariant_cells(magnitudes, band_list)
    route_b = invariant_cells_by_consensus(magnitudes, band_list)
    routes_agree = same(route_a, route_b)
    out.write("  invariant bands in the object (every member one value): %s\n" % bin(route_a))
    out.write("  two routes read the invariant bands identically: %s\n\n" % routes_agree)

    union = null_union(magnitudes, band_list, HEAVY_DRAWS, SEED)
    survived = surviving(magnitudes, band_list, HEAVY_DRAWS, SEED)
    out.write("  draw the null: the union over %d shuffles of the same magnitudes\n" % HEAVY_DRAWS)
    out.write("  bands any shuffle made invariant: %s\n" % bin(union))
    out.write("  bands the object holds that no shuffle reached: %s\n\n" % bin(survived))

    core_bit = 1 << CORE
    shell_bit = 1 << SHELL
    shell_survives = bool(survived & shell_bit)                 # fault two excluded: real invariant kept
    core_excluded = not (survived & core_bit)                   # fault one excluded: coincidence dropped
    core_in_union = bool(union & core_bit)                      # the coincidence is what the null absorbed
    only_the_shell = (survived == shell_bit)

    out.write("  fault one, a false invariant surviving by accident:\n")
    out.write("    the size-one core is invariant in the object: %s\n" % bool(route_a & core_bit))
    out.write("    every shuffle also makes it invariant (in the union): %s\n" % core_in_union)
    out.write("    so the core does not survive: %s (excluded)\n\n" % core_excluded)
    out.write("  fault two, a real invariant erased by a null drawn too hard:\n")
    out.write("    the uniform shell (band %d) survives %d draws: %s (excluded)\n\n"
              % (SHELL, HEAVY_DRAWS, shell_survives))

    surviving_count = count(survived)
    ok = routes_agree and shell_survives and core_excluded and only_the_shell
    out.write("  the only band that survives is the real uniform shell: %s (%d surviving)\n"
              % (only_the_shell, surviving_count))
    out.write("  read without a ratio or a threshold, in exact bits. any fault admitted refutes the\n")
    out.write("  posit: %s\n" % ("holds" if ok else "refuted"))
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
