#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: SND-4-002
#
# Incoherent replacement noise removed off a target that repeats, by the value each phase agrees on.
#
#   Usage:  python examples/sound/4_measure/impulses_removed_to_the_bit.py
#
# An impulse is the incoherent kind of noise: it replaces a sample with a value drawn from nowhere,
# at a position drawn from nowhere. It has no period, so it cannot be identified on its own. What
# identifies it is the target it lands on. When the target repeats, shift_agreement.recover_exact_period
# reads the period off the target's own difference set, and the family rule survives the few equalities
# an impulse breaks. Each phase class then holds the true value in most of its members and a wrong
# value in a few, and the value the class agrees on is the true one.
#
# reference.periodic rejects the impulse by that consensus: every position becomes the value its phase
# class agrees on, so the overwritten members are restored from the many that were not. Where every
# corrupted class keeps a clean majority the restoration equals the clean signal to the last bit, as
# integers and not inside a tolerance. That is a full rejection of the impulses.
#
# WHAT MAKES THE READING EVIDENCE
#
# Two consensus routes, and here they can genuinely disagree, which is what makes their agreement
# mean something. The count route takes the value of greatest count; the median route sorts the class
# and takes the middle. Where a class carries a clean majority the two land on the same value. Where a
# class has no majority they split, and that split is not a defect: it is the floor, the density of
# impulses past which no value in a class is the one most members hold, and neither route can invent
# the answer the data no longer contains.
#
# THE NULL, AND THE FLOOR
#
# The null is drawn: the samples are shuffled, which holds the histogram and destroys the period, so
# the period detector no longer reads the target and a consensus taken at a wrong period restores
# nothing. The floor is swept, not assumed: the impulse density is raised until a phase class loses
# its clean majority, and the reduction is reported at each density so the reader sees where the
# rejection stops being exact and why.
#
# A native-C route for the consensus is the natural hardening and is not claimed here. Both routes
# below are Python, independent in algorithm.

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

from measure.shift_agreement import recover_exact_period  # noqa: E402
from reference.periodic import consensus_majority, consensus_median, restore  # noqa: E402
from reference.shuffles import permuted  # noqa: E402
from representation.exact import placed  # noqa: E402

# The declared inputs, printed with every reading and chosen by nothing the output showed.
PERIOD = 5
CYCLES = 24
CLEAN = (30, 90, 150, 210, 60)   # one cycle of the target, tiled CYCLES times
REACH = 40                        # the longest period the detector considers, a bound on the search
SEED = 0x1A9E


def clean_signal(period, cycles, cycle):
    return [cycle[n % period] for n in range(period * cycles)]


def inject(signal, period, per_class, seed):
    """Replace up to `per_class` samples in each phase class with a value from nowhere.

    The cap keeps every corrupted class below half corrupted while the density is under study, so the
    control is a control and not already the floor. Returns the corrupted signal and the positions
    touched, and the value written is never the value it replaced.
    """
    rng = random.Random(seed)
    out = list(signal)
    touched = []
    hits = [0] * period
    order = list(range(len(signal)))
    rng.shuffle(order)
    for position in order:
        phase = position % period
        if hits[phase] >= per_class:
            continue
        value = rng.randrange(256)
        if value == out[position]:
            value = (value + 1) % 256
        out[position] = value
        touched.append(position)
        hits[phase] += 1
    return out, touched


def inject_stuck(signal, period, phase, count, value, seed):
    """Write one fixed wrong value into `count` members of a single phase class.

    Scattered impulses each land on a different value, so no wrong value ever out-counts the true one
    and the plurality route recovers them however many there are. A stuck value is the opposite: one
    value repeated. When it fills more of a class than the true value holds, it becomes the plurality
    and the count route returns it. This is the count route's floor, and it is a different floor from
    the median's.
    """
    rng = random.Random(seed)
    out = list(signal)
    members = list(range(phase, len(signal), period))
    rng.shuffle(members)
    for position in members[:count]:
        out[position] = value
    return out


def reduction(noisy, restored, clean):
    """The share of the injected replacement energy that the restoration removed, exact."""
    injected = sum((Fraction(noisy[n]) - clean[n]) ** 2 for n in range(len(clean)))
    left = sum((Fraction(restored[n]) - clean[n]) ** 2 for n in range(len(clean)))
    if injected == 0:
        return Fraction(1)
    return Fraction(1) - left / injected


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    clean = clean_signal(PERIOD, CYCLES, CLEAN)
    out.write("  impulses removed to the bit\n")
    out.write("  declared inputs: period=%d cycles=%d cycle=%s reach=%d seed=0x%X\n\n"
              % (PERIOD, CYCLES, CLEAN, REACH, SEED))

    # a sparse density: few enough per class that a clean majority always survives
    sparse = max(1, CYCLES // 8)
    noisy, touched = inject(clean, PERIOD, sparse, SEED)

    # 1. identify the target's period off its own difference set, robust to the broken equalities
    found, agree = recover_exact_period(placed(list(enumerate(noisy))), families=2)
    out.write("  identify: exact-period detector %s (true %d), agreement %s\n"
              % (found, PERIOD, agree))

    # 2. reject by consensus, two routes that can disagree
    by_count = consensus_majority(noisy, found)
    by_median = consensus_median(noisy, found)
    routes_agree = by_count == by_median
    exact = by_count == clean
    nrr = reduction(noisy, by_count, clean)
    out.write("  reject: count and median routes agree: %s\n" % routes_agree)
    out.write("  reject: restored equals the clean signal as integers: %s\n" % exact)
    out.write("  reject: corrupted samples %d, reduction %s = %.4f%%\n\n"
              % (len(touched), nrr, float(nrr) * 100.0))

    # 3. the null: a shuffle has no period, so a consensus taken at a wrong period restores nothing
    shuffled = list(permuted(noisy, SEED))
    null_found, _ = recover_exact_period(placed(list(enumerate(shuffled))), families=2)
    wrong = 3 if found != 3 else 4
    wrong_restored = restore(noisy, wrong, consensus_majority)
    wrong_nrr = reduction(noisy, wrong_restored, clean)
    out.write("  null: shuffled signal exact-period detector %s (no target to read)\n" % null_found)
    out.write("  null: restoring at the wrong period %d reduces noise by %.4f%% (below zero: a wrong\n"
              "        period does not restore, it corrupts, replacing samples with a foreign class)\n\n"
              % (wrong, float(wrong_nrr) * 100.0))

    # 3c. negative controls: the score must be able to NOT be 100. A clean signal has nothing to
    #     restore, and a COHERENT noise is the class majority itself, so consensus keeps it rather than
    #     removing it -- that is the other detector's job. Both must fail to reach a real reduction.
    out.write("  negative controls (must not read 100 against the clean signal):\n")
    out.write("  %-24s %-14s %s\n" % ("case", "period", "outcome"))
    hum = (-40, 20, -20, 40, 0)                          # a coherent addend: the wrong KIND for this
    wrong_kind = [clean[n] + hum[n % len(hum)] for n in range(len(clean))]
    for label, arm, has_noise in (
            ("matched impulses", noisy, True),
            ("no noise", list(clean), False),
            ("wrong kind (a hum)", wrong_kind, True)):
        per, _ = recover_exact_period(placed(list(enumerate(arm))), families=2)
        if per is None:
            out.write("  %-24s %-14s %s\n" % (label, "none", "decline -> nothing removed"))
            continue
        got = consensus_majority(arm, per)
        if not has_noise:
            outcome = "returned untouched: %s" % (got == clean)
        else:
            got_nrr = reduction(arm, got, clean)
            outcome = "reduction %.2f%%" % (float(got_nrr) * 100.0)
        out.write("  %-24s %-14d %s\n" % (label, per, outcome))
    out.write("\n")

    # 4a. scattered impulses: each lands on its own value, so no wrong value out-counts the true one.
    #     the count route recovers them however dense, and the median route is the one that gives way.
    out.write("  floor, scattered impulses (each a value from nowhere), of %d members per class:\n" % CYCLES)
    out.write("  %-14s %-16s %-14s %s\n" % ("per class", "count reduction", "count exact", "routes agree"))
    for per_class in (sparse, CYCLES // 3, CYCLES // 2, (2 * CYCLES) // 3):
        dirty, _ = inject(clean, PERIOD, per_class, SEED)
        r_count = consensus_majority(dirty, PERIOD)
        r_median = consensus_median(dirty, PERIOD)
        floor_nrr = reduction(dirty, r_count, clean)
        out.write("  %-14d %-16.4f %-14s %s\n"
                  % (per_class, float(floor_nrr) * 100.0, r_count == clean, r_count == r_median))

    # 4b. a stuck value: one wrong value repeated. when it fills more of a class than the true value
    #     holds, it becomes the plurality and the count route returns it. this is the count's floor.
    out.write("\n  floor, one stuck value in a single class (the count route's own floor):\n")
    out.write("  %-14s %-16s %s\n" % ("stuck count", "count reduction", "count exact"))
    for stuck in (sparse, CYCLES // 3, (CYCLES // 2) + 1, (2 * CYCLES) // 3):
        dirty = inject_stuck(clean, PERIOD, 0, stuck, 255, SEED)
        r_count = consensus_majority(dirty, PERIOD)
        floor_nrr = reduction(dirty, r_count, clean)
        out.write("  %-14d %-16.4f %s\n" % (stuck, float(floor_nrr) * 100.0, r_count == clean))

    out.write("\n  the top table is the useful surprise: a plurality is robust to scattered impulses well\n")
    out.write("  past half a class, because a value from nowhere is a different nowhere each time and\n")
    out.write("  never out-counts the truth. the median gives way first, and the routes splitting is the\n")
    out.write("  median's floor, not the count's. the count's floor is the second table: a stuck value\n")
    out.write("  that fills more of a class than the truth holds is the one impulse a plurality cannot\n")
    out.write("  reject, because it is no longer incoherent -- it has become a coherent addend, and that\n")
    out.write("  is the other detector's problem, not this one's.\n")
    out.flush()
    return 0 if (routes_agree and exact) else 1


if __name__ == "__main__":
    raise SystemExit(main())
