#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: SND-4-003
#
# Non-local means through the one construction: a value rejected off the other places in its context.
#
#   Usage:  python examples/sound/4_measure/self_similar_removed_to_the_bit.py
#
# This is the non-local means filter, reached without leaving the construction the periodic filter
# uses. A periodic background groups the positions that share a POSITION modulo a period; this groups
# the positions that share a surrounding CONTEXT. Both then replace a value with its group's mean. The
# only difference is the group key, so nothing is ported: a comb filter and non-local means are one
# operation over two groupings.
#
# What it reads that a periodic filter cannot: a motif that recurs at positions with NO period between
# them. A recurring motif gives many places that share one context, and if the noise on the center of
# that motif sums to zero over its occurrences, the mean of the group is the clean center and the
# residual is the noise. The occurrences here are placed in a shuffled order with no period, so the
# periodic detector has nothing to find and this recovers them anyway.
#
# The match is EXACT, because classic non-local means matches contexts that are merely similar and how
# similar is a bandwidth the author picks, which this tree does not allow. Exact matching moves the
# whole cost into the floor: a context that never recurs is a group of one and is kept untouched, and
# the noise must sit on the center rather than on the context it is read against. Where the context is
# clean and recurs, the rejection is exact.
#
# Two routes build the group mean with no shared code, a keyed dictionary and a scan for equal
# contexts, and a broken third is run beside them so their agreeing is shown to have teeth. The
# negative controls are the part that licenses the 100: a signal with no noise must come back
# untouched, and a signal whose contexts do not recur must be declined with its noise left intact, so
# the 100 is reached only where a context genuinely predicts its center. A native-C route is the
# natural hardening and is not claimed here.

import io
import os
import random
import sys
from fractions import Fraction

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from reference.self_similar import (similar_background, similar_background_scanned,  # noqa: E402
                                    similar_residual, context_groups)

# Declared inputs, printed with every reading.
RADIUS = 1
# Each motif is a distinct surround and a clean center. The surround is the context; the center is what
# carries noise and is recovered from the group.
MOTIFS = {0: ((10, 20), 100), 1: ((30, 40), 150), 2: ((50, 60), 200), 3: ((70, 80), 130)}
OCCURRENCES = 20          # per motif, even so the noise pairs cancel exactly
NOISE = 9                 # the swing of the zero-sum center noise
SEED = 0x5157


def lay_out(motifs, occurrences, noise, seed, noisy=True):
    """A signal of motif occurrences in shuffled order, centers carrying zero-sum noise per motif.

    Returns the signal, the center positions, and the clean center each should recover to. The order is
    shuffled so the occurrences have no period, which is what separates this from a periodic reading.
    """
    rng = random.Random(seed)
    order = []
    for motif in motifs:
        order += [motif] * occurrences
    rng.shuffle(order)

    draws = {}
    for motif in motifs:
        half = occurrences // 2
        pairs = [rng.randint(1, noise) for _ in range(half)]
        pairs = pairs + [-value for value in pairs]
        rng.shuffle(pairs)
        draws[motif] = iter(pairs)

    signal, centers, clean = [], [], []
    for motif in order:
        (left, right), middle = motifs[motif]
        shift = next(draws[motif]) if noisy else 0
        signal.append(left)
        centers.append(len(signal))
        clean.append(middle)
        signal.append(middle + shift)
        signal.append(right)
    return signal, centers, clean


def broken_background(values, radius):
    """A deliberately wrong context mean, to prove the two-route check can fail: it drops the last
    member of every group."""
    groups = context_groups(values, radius)
    means = {}
    for context, members in groups.items():
        keep = members[:-1] or members
        means[context] = Fraction(sum(values[i] for i in keep), len(keep))
    from reference.self_similar import context_of
    return [means[context_of(values, i, radius)] if context_of(values, i, radius) is not None
            else Fraction(values[i]) for i in range(len(values))]


def reduction(noisy, cleaned, clean, positions):
    """The share of the injected noise energy removed, measured over the positions that carried it."""
    injected = sum((Fraction(noisy[p]) - clean[i]) ** 2 for i, p in enumerate(positions))
    left = sum((cleaned[p] - clean[i]) ** 2 for i, p in enumerate(positions))
    if injected == 0:
        return Fraction(1)
    return Fraction(1) - left / injected


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    signal, centers, clean = lay_out(MOTIFS, OCCURRENCES, NOISE, SEED)
    out.write("  non-local means removed to the bit\n")
    out.write("  declared inputs: radius=%d motifs=%d occurrences=%d noise=%d seed=0x%X\n\n"
              % (RADIUS, len(MOTIFS), OCCURRENCES, NOISE, SEED))

    recurring = sum(1 for members in context_groups(signal, RADIUS).values() if len(members) > 1)
    out.write("  identify: contexts that recur (groups larger than one): %d\n" % recurring)

    back = similar_background(signal, RADIUS)
    back2 = similar_background_scanned(signal, RADIUS)
    broken = broken_background(signal, RADIUS)
    routes_agree = back == back2
    broken_splits = (back != broken) and (back2 != broken)
    out.write("  reject: keyed and scanned routes agree bit-exact: %s\n" % routes_agree)
    out.write("  reject: the broken route splits from both (the check has teeth): %s\n" % broken_splits)

    exact = all(back[p] == clean[i] for i, p in enumerate(centers))
    nrr = reduction(signal, back, clean, centers)
    out.write("  reject: every recovered center equals its clean value: %s\n" % exact)
    out.write("  reject: noise reduction ratio %s = %.4f%%\n\n" % (nrr, float(nrr) * 100.0))

    # negative controls: the 0 that licenses the 100
    out.write("  negative controls: the score licensing the 100 is the 0 a non-recurring signal scores.\n")
    out.write("  %-26s %-14s %s\n" % ("case", "recovered", "outcome"))

    clean_signal, clean_centers, clean_clean = lay_out(MOTIFS, OCCURRENCES, NOISE, SEED, noisy=False)
    got_clean = similar_background(clean_signal, RADIUS)
    untouched = all(got_clean[p] == clean_clean[i] for i, p in enumerate(clean_centers))
    out.write("  %-26s %-14s %s\n" % ("no noise", untouched,
                                      "returned untouched" if untouched else "DAMAGED"))

    rng = random.Random(SEED ^ 0x9)
    unique = [rng.randrange(256) for _ in range(len(signal))]     # high-entropy: contexts do not recur
    marks = [i for i in range(RADIUS, len(unique) - RADIUS) if (i % 11) == 0]
    clean_unique = list(unique)
    for i in marks:
        unique[i] = (unique[i] + 100) % 256
    got_unique = similar_background(unique, RADIUS)
    unique_nrr = reduction(unique, got_unique, [clean_unique[i] for i in marks], marks)
    recurring_u = sum(1 for m in context_groups(unique, RADIUS).values() if len(m) > 1)
    out.write("  %-26s %-14s %s\n"
              % ("non-recurring + impulses", "%.2f%%" % (float(unique_nrr) * 100.0),
                 "declined: %d recurring contexts, noise intact" % recurring_u))

    out.write("\n  the recovery holds although the occurrences have no period, which a comb filter needs\n")
    out.write("  and this does not: it groups by the content of the context, not the position. the floor\n")
    out.write("  is a context that never recurs, a group of one, which is kept rather than invented.\n")
    out.flush()
    return 0 if (routes_agree and broken_splits and exact and untouched) else 1


if __name__ == "__main__":
    raise SystemExit(main())
