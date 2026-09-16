#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: SND-4-001
#
# A coherent addend of a fixed period, identified and rejected off a target that does not repeat.
#
#   Usage:  python examples/sound/4_measure/coherent_hum_removed_to_the_bit.py
#
# A hum is the coherent kind of noise: it repeats. It adds the same short cycle over and over, so
# every position of one phase carries the same addend and the addend's energy gathers into the phase
# means. The target it rides on does not repeat, so exact self-agreement reads nothing of the hum,
# and measure.periodic_energy reads it instead, by how far the phase grouping stands above a shuffle
# of the same samples.
#
# Once the period is identified the addend is rejected using the target itself. reference.periodic
# builds the phase mean, which is the maximum entropy background the period allows, and the residual
# is the target with the hum gone. Where the target sums to zero inside every phase class -- where it
# sits orthogonal to the period the hum keeps -- the phase mean IS the hum, exactly, because the
# target contributes nothing to it, and the residual is the target to the last bit. That is a full
# rejection, and it is shown here as the residual equalling the clean target as integers, not inside
# a tolerance.
#
# WHAT MAKES THE READING EVIDENCE
#
# Two routes build the phase mean and they must be able to disagree, or their agreeing says nothing.
# The batch route sums each class and divides once; the incremental route grows each class mean one
# member at a time. A deliberately broken third route is run beside them to show the check has teeth:
# it splits from both. Only then does the two routes landing on the same rationals mean the code is
# right, and only then does the residual landing on the clean target mean the rejection is real.
#
# THE NULL, AND THE FLOOR
#
# The null is drawn, not assumed: the samples are shuffled, which holds the histogram and destroys
# the phase, and the detector no longer stands above the ground. Removing at a period the null
# suggests takes nothing real away.
#
# The floor is stated, not hidden. When the target carries its own component of the hum's period --
# when a phase class does not sum to zero -- that component is inside the hum's subspace and cannot be
# told from it. The rejection removes it along with the hum, and the reduction falls below 100%. The
# amount it falls is the target's own energy at the hum's period, and it is reported as the floor this
# instrument cannot clear: noise shaped exactly like the target is not rejectable, which is the
# information limit and not a defect.
#
# A second, native-C route for the phase mean is the natural hardening of this result and is not
# claimed here. The two routes below are both Python, independent in algorithm and in arithmetic.

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

from measure.periodic_energy import recover_period, against_a_shuffle, dispersion_ratio  # noqa: E402
from reference.periodic import (mean_background, mean_background_incremental,  # noqa: E402
                                mean_residual)
from reference.shuffles import permuted  # noqa: E402

# The declared inputs of this demonstration, printed with every reading and chosen by nothing the
# output showed.
#
# The hum sums to zero. A constant added to every sample is the period-one coherent noise and any
# grouping removes it, so leaving it in would let a wrong period claim most of the reduction by
# removing the constant alone. Zeroing the hum's mean leaves only the part a period actually carries,
# and then a wrong period removes nothing and the reading is honest.
#
# The target and hum are small and signed, so the signal runs through zero. The detector shuffles its
# input and the tree's shuffle takes bytes, so the detector reads a copy shifted up by a pedestal into
# the byte range; a shift moves no variance, so the period it reads is the same. The rejection and the
# reduction are computed on the signed signal, where no pedestal enters the arithmetic.
PERIOD = 4
CYCLES = 48
SWING = 30           # the target's amplitude inside a phase class
HUM = (-48, -16, 16, 48)   # sums to zero: no constant part for a wrong period to claim
PEDESTAL = 128       # shifts the signed signal into the byte range for the detector's shuffle only
REACH = 32           # the longest period the detector considers; it bounds the search, not the answer
SEED = 0x50D1


def zero_sum_target(period, cycles, swing, seed):
    """A target whose every phase class sums to zero, so it sits orthogonal to `period`.

    Each class is built from matched pairs, a value and its negative, so the class sum is zero as an
    integer and every member stays inside [-swing, swing]. Cancelling by a single last member instead
    would leave one member as large as the sum of all the others, which walks the signal out of range;
    pairs keep it bounded. The members are shuffled inside the class, so the target carries no order of
    its own at the period and contributes nothing to the phase mean, which is why the rejection leaves
    it untouched.
    """
    rng = random.Random(seed)
    length = period * cycles
    target = [0] * length
    half = cycles // 2
    for phase in range(period):
        members = [rng.randint(1, swing) for _ in range(half)]
        members = members + [-value for value in members]
        if cycles % 2:
            members.append(0)
        rng.shuffle(members)
        for step, value in enumerate(members):
            target[phase + step * period] = value
    return target


def with_own_period_component(target, period, depth):
    """The same target with a component added at `period`, so a phase class no longer sums to zero.

    This is the floor case: the added component is shaped exactly like the hum and cannot be told
    from it. `depth` is how much is added to one phase, reported with the reduction it costs.
    """
    shaped = list(target)
    for step in range(len(shaped) // period):
        shaped[step * period] += depth
    return shaped


def broken_background(values, period):
    """A deliberately wrong phase mean, to prove the two-route check can fail.

    It divides each class sum by one more than the count. It is not a route this ships; it is here so
    that the good routes agreeing is shown to be a property the wrong one does not have.
    """
    sums = [0] * period
    counts = [0] * period
    for index, value in enumerate(values):
        sums[index % period] += value
        counts[index % period] += 1
    means = [Fraction(sums[phase], counts[phase] + 1) for phase in range(period)]
    return [means[index % period] for index in range(len(values))]


def reduction(noisy, cleaned, target):
    """The share of the injected noise energy that the rejection removed, exact.

    One minus the residual error energy over the injected error energy. A residual equal to the target
    makes the numerator zero and the reduction exactly one.
    """
    injected = sum((Fraction(noisy[n]) - target[n]) ** 2 for n in range(len(target)))
    left = sum((cleaned[n] - target[n]) ** 2 for n in range(len(target)))
    if injected == 0:
        return Fraction(1)
    return Fraction(1) - Fraction(left, 1) / injected


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    target = zero_sum_target(PERIOD, CYCLES, SWING, SEED)
    signal = [target[n] + HUM[n % PERIOD] for n in range(len(target))]
    byte_view = [value + PEDESTAL for value in signal]
    if not all(0 <= value <= 255 for value in byte_view):
        out.write("control left the byte range; adjust SWING, HUM or PEDESTAL\n")
        out.flush()
        return 1

    out.write("  coherent hum removed to the bit\n")
    out.write("  declared inputs: period=%d cycles=%d swing=%d hum=%s pedestal=%d reach=%d seed=0x%X\n\n"
              % (PERIOD, CYCLES, SWING, HUM, PEDESTAL, REACH, SEED))

    # 1. identify the period on the byte view, against the drawn null. A shift moves no variance, so
    #    the period read off the byte view is the period of the signed signal.
    found, live, dead = recover_period(byte_view, REACH)
    out.write("  identify: detector period %s (true %d)\n" % (found, PERIOD))
    out.write("  identify: dispersion ratio live %.3f vs its own shuffle %.3f  (near 1 is no phase)\n"
              % (float(live), float(dead)))

    # 2. reject with two routes that must be able to disagree
    back_batch = mean_background(signal, found)
    back_incr = mean_background_incremental(signal, found)
    back_broken = broken_background(signal, found)
    routes_agree = back_batch == back_incr
    broken_splits = (back_batch != back_broken) and (back_incr != back_broken)
    out.write("  reject: batch and incremental routes agree bit-exact: %s\n" % routes_agree)
    out.write("  reject: the broken route splits from both (the check has teeth): %s\n" % broken_splits)

    cleaned = mean_residual(signal, found, back_batch)
    exact = all(cleaned[n] == target[n] for n in range(len(target)))
    nrr = reduction(signal, cleaned, target)
    out.write("  reject: residual equals the clean target as integers: %s\n" % exact)
    out.write("  reject: noise reduction ratio %s = %.4f%%\n\n"
              % (nrr, float(nrr) * 100.0))

    # 3. the null: a shuffle has no phase to find, and removing at a wrong period takes nothing real
    shuffled = list(permuted(byte_view, SEED))
    null_found, null_live, null_dead = recover_period(shuffled, REACH)
    out.write("  null: shuffled signal detector period %s live %.3f vs shuffle %.3f\n"
              % (null_found, float(null_live) if null_live is not None else float("nan"),
                 float(null_dead) if null_dead is not None else float("nan")))
    wrong = 3 if found != 3 else 5
    wrong_cleaned = mean_residual(signal, wrong)
    wrong_nrr = reduction(signal, wrong_cleaned, target)
    out.write("  null: rejecting at the wrong period %d reduces noise by %.4f%% (near zero)\n\n"
              % (wrong, float(wrong_nrr) * 100.0))

    # 4. the floor: a target component at the hum's period is shaped like the hum and is not rejectable
    out.write("  floor: a target component at the hum's period cannot be told from the hum\n")
    out.write("  %-10s %-14s %s\n" % ("depth", "reduction", "what the loss is"))
    for depth in (0, 5, 15, 30):
        shaped = with_own_period_component(target, PERIOD, depth)
        dirty = [shaped[n] + HUM[n % PERIOD] for n in range(len(shaped))]
        got = mean_residual(dirty, PERIOD)
        floor_nrr = reduction(dirty, got, shaped)
        note = "full rejection" if depth == 0 else "target energy at the hum's period, unrejectable"
        out.write("  %-10d %-14.4f %s\n" % (depth, float(floor_nrr) * 100.0, note))

    out.write("\n  a full rejection is the depth-zero row: the hum is identifiable and the target is\n")
    out.write("  not, so the target is kept and the hum is removed to the last bit. every row below\n")
    out.write("  it is the information limit, not a defect: noise shaped exactly like the target is\n")
    out.write("  the one thing no instrument can reject.\n")
    out.flush()
    return 0 if (routes_agree and broken_splits and exact) else 1


if __name__ == "__main__":
    raise SystemExit(main())
