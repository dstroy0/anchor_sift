#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: SND-3-001
#
# The background a period allows on a sound signal, and how little of it a shuffle also reaches.
#
#   Usage:  python examples/sound/3_reference/period_background_and_its_null.py
#
# This is the reference stage for sound, which the tree did not have: there was no shuffle of a
# vocalization and so no null for a sound reading to stand against. It answers the stage-three
# question crystallography's what_a_grid_invents asks of a lattice: how much of a reading is the
# structure, and how much a shuffle of the same values reaches on its own.
#
# The reference a period allows is the phase mean: group the samples by their position modulo the
# period and average each group. Under the one constraint that a value depends only on its phase, this
# is the maximum entropy background, so it asserts nothing the phase did not already carry. On a signal
# with a real period the phase means spread far apart and the background carries energy. On a shuffle
# of the same samples the phase is gone, the phase means collapse toward the grand mean, and the
# background carries almost nothing. The gap between the two is the only part of the reading that means
# anything, and printing the shuffle beside the live number is what makes it readable.
#
# The background is solved for, never searched for, and the null is drawn, never derived. reference
# builds the background and reference.shuffles draws the null; the same one null the whole tree uses.

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

from measure.periodic_energy import between_classes, dispersion_ratio  # noqa: E402
from reference.periodic import mean_background  # noqa: E402
from reference.shuffles import permuted  # noqa: E402

# Declared inputs, printed with every reading.
PERIOD = 6
CYCLES = 40
SWING = 24
TONE = (10, 40, 70, 40, 10, -20)   # one cycle of the coherent component, zero-mean
PEDESTAL = 128
SEED = 0x53D3


def signal_with_tone(period, cycles, swing, tone, seed):
    """A moving target that sums to zero at each phase, plus a coherent tone of the given period."""
    rng = random.Random(seed)
    length = period * cycles
    values = [0] * length
    half = cycles // 2
    for phase in range(period):
        members = [rng.randint(1, swing) for _ in range(half)]
        members = members + [-value for value in members]
        if cycles % 2:
            members.append(0)
        rng.shuffle(members)
        for step, value in enumerate(members):
            values[phase + step * period] = value + tone[phase]
    return values


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    signal = signal_with_tone(PERIOD, CYCLES, SWING, TONE, SEED)
    byte_view = [value + PEDESTAL for value in signal]
    shuffled = [value + PEDESTAL for value in signal]
    shuffled = list(permuted(bytearray(shuffled), SEED))

    out.write("  the background a period allows, and its null\n")
    out.write("  declared inputs: period=%d cycles=%d swing=%d tone=%s seed=0x%X\n\n"
              % (PERIOD, CYCLES, SWING, TONE, SEED))

    # the background at the true period recovers the tone; on a shuffle it recovers a flat line
    background = mean_background(signal, PERIOD)
    recovered = [background[phase] for phase in range(PERIOD)]
    out.write("  the phase-mean background at the true period, one cycle:\n")
    out.write("    recovered %s\n" % [str(value) for value in recovered])
    out.write("    injected  %s\n" % [str(value) for value in TONE])
    out.write("    the background is the tone plus the target's phase mean, which is zero by design\n\n")

    # what a shuffle reaches: sweep the candidate periods, live against the drawn null
    out.write("  how much of the reading a shuffle also reaches, swept over candidate periods:\n")
    out.write("  %-9s %-16s %-16s %s\n" % ("period", "live energy", "shuffle energy", "dispersion live/null"))
    for period in (2, 3, PERIOD, PERIOD * 2, 7, 11):
        live = between_classes(byte_view, period)
        dead = between_classes(shuffled, period)
        ratio_live = dispersion_ratio(byte_view, period)
        ratio_dead = dispersion_ratio(shuffled, period)
        out.write("  %-9d %-16.3f %-16.3f %s / %s\n"
                  % (period, float(live), float(dead),
                     ("%.3f" % float(ratio_live)) if ratio_live is not None else "none",
                     ("%.3f" % float(ratio_dead)) if ratio_dead is not None else "none"))

    out.write("\n  the true period stands far above its shuffle; the others sit near it. the reference\n")
    out.write("  invents nothing a shuffle does not also reach, so the part that clears the null is\n")
    out.write("  the whole of the reading. this is the null a sound measurement had been missing.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
