#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The period a coherent addend keeps, read off how much energy its phase splits away from a shuffle.
#
#   Usage:  from measure.periodic_energy import between_classes, against_a_shuffle, recover_period
#
# There are two coherent things a period can name and they need two detectors. shift_agreement reads
# EXACT self-equality, so it finds a coherent TARGET: a sequence that repeats, whose every match at
# the period is an equality between whole values. An impulse breaks a few of those equalities and the
# family rule survives it, so that detector carries the replacement-noise case.
#
# It cannot find a coherent NOISE component hiding in a target that does not repeat. A hum added to
# speech makes x[n] equal x[n+P] only where the speech already did, which is nowhere, so exact
# agreement reads nothing while the hum is plainly there. What the hum does leave is energy: the
# positions of one phase all carry the same addend, so grouping by phase concentrates that addend's
# energy into the class means and a wrong period does not. This detector reads that concentration.
#
# The quantity is the between-class sum of squares, the energy that sits in the differences between
# the phase means rather than inside the classes. It rises with the period on its own, because more
# classes hold more between-class variance whatever the data, so the count alone means nothing. The
# only thing that means anything is the amount above what the same histogram reaches with its
# positions shuffled: reference.shuffles.permuted holds every value and destroys every phase, so its
# between-class energy at a period is the mechanical part, and the live reading minus it is the part
# the phase actually carries. This is against_a_shuffle from shift_agreement, in energy.
#
# WHY A RATIO AND NOT A RAW ENERGY
#
# Between-class energy rises with the period on its own: more classes hold more of it whatever the
# data, so the raw quantity picks the longest period every time and every multiple of a true period
# outscores the period itself. The fix is the one analysis of variance has used for a century. Divide
# the between-class energy by its degrees of freedom, the period minus one, and divide the within-class
# energy by its own, the length minus the period, and take the ratio. The ratio does not grow with the
# period, and a multiple of the true period splits the same energy across more classes for more
# degrees of freedom, so it scores strictly below the fundamental. A period that explains nothing sits
# near one, the value with no structure, and the true period stands far above it.
#
# The perfectly periodic case, where a period drives the within-class energy to zero, is not this
# detector's. A sequence that repeats exactly is a coherent TARGET and shift_agreement reads it by
# exact equality; here that case is declined rather than reported, so the two detectors never both
# claim one reading.
#
# NOTHING IS BOUNDED HERE
#
# `reach`, the longest period considered, is a declared input reported beside the reading, not a
# ceiling chosen until the answer appeared; the difference set has no ceiling and this scan states
# the one it used. The energy and the ratio are exact rational. The null is drawn, never derived, and
# it is the one null the tree already uses: a period that stands above its own shuffle carries phase
# the shuffle could not, and the shuffle's ratio is reported beside the live one so the reader sees
# the floor it cleared.

from fractions import Fraction

from reference.shuffles import permuted, SEED


def between_classes(values, period):
    """The energy carried by the differences between the phase means, exact.

    The phase classes are the positions congruent modulo `period`. This is the sum over classes of
    the class count times the squared distance of the class mean from the grand mean, written so no
    division happens until the end: the class term is its summed value squared over its count, and
    the grand term is the whole summed value squared over the length. A period that groups a repeating
    addend together makes the class means spread far apart and this large; a period that does not
    leaves them near the grand mean and this near zero.
    """
    length = len(values)
    if length == 0:
        return Fraction(0)
    sums = [0] * period
    counts = [0] * period
    for index, value in enumerate(values):
        phase = index % period
        sums[phase] += value
        counts[phase] += 1
    within = sum(Fraction(sums[phase] * sums[phase], counts[phase])
                 for phase in range(period) if counts[phase])
    grand = Fraction(sum(sums) ** 2, length)
    return within - grand


def total_energy(values):
    """The energy in the values about their grand mean, exact. Between plus within always sums to it.

    Written with one division at the end: the length times the summed squares, less the summed value
    squared, over the length.
    """
    length = len(values)
    if length == 0:
        return Fraction(0)
    summed = sum(values)
    squares = sum(value * value for value in values)
    return Fraction(length * squares - summed * summed, length)


def dispersion_ratio(values, period):
    """The between-class energy per degree of freedom over the within-class energy per its own.

    The analysis-of-variance ratio for grouping the values by phase. The between-class part is divided
    by the period less one and the within-class part, which is the total less the between, by the
    length less the period. It does not grow with the period and it suppresses a multiple of the true
    period, which splits the same energy over more classes. A grouping that explains nothing sits near
    one and the true period stands far above.

    Returns the ratio as an exact rational, or None where a degree of freedom runs out or the period
    explains all the energy. The second is the perfectly periodic case, a repeating target, which is
    shift_agreement's reading and is declined here so the two detectors never both claim it.
    """
    length = len(values)
    between = between_classes(values, period)
    within = total_energy(values) - between
    freedom_between = period - 1
    freedom_within = length - period
    if (freedom_between <= 0) or (freedom_within <= 0) or (within <= 0):
        return None
    return (between / freedom_between) / (within / freedom_within)


def against_a_shuffle(values, period, seed=SEED):
    """The dispersion ratio at a period, and the ratio a shuffle of the same values reaches.

    The shuffle holds the histogram exactly and destroys every phase, so its ratio is what this
    grouping reaches with no phase to find, which is near one. Only the live standing above it means
    anything, exactly as a raw self-agreement count means nothing until a shuffle is drawn beside it.
    """
    live = dispersion_ratio(values, period)
    dead = dispersion_ratio(list(permuted(values, seed)), period)
    return live, dead


def recover_period(values, reach, seed=SEED):
    """The period whose phase grouping stands highest by the dispersion ratio, over a stated reach.

    Every period from two to `reach` is scored by its dispersion ratio and the highest is returned.
    The ratio needs no family rule: it already scores a multiple of the true period below the period,
    because the multiple spends more degrees of freedom on the same energy. `reach` is the one
    declared input, and it bounds the search and not the answer.

    Returns the period, its live ratio, and the ratio its own shuffle reaches, or (None, None, None)
    where no grouping stands above the ground.
    """
    values = list(values)
    length = len(values)
    if length < 4:
        return None, None, None
    reach = max(2, min(int(reach), length - 1))

    best = None
    chosen = None
    for period in range(2, reach + 1):
        ratio = dispersion_ratio(values, period)
        if ratio is None:
            continue
        if (best is None) or (ratio > best):
            best = ratio
            chosen = period

    if chosen is None:
        return None, None, None

    live, dead = against_a_shuffle(values, chosen, seed)
    return chosen, live, dead


def null_band(values, reach, draws=8, seed=SEED):
    """The dispersion ratios a shuffle of these values reaches, over `draws` shuffles, sorted.

    recover_period always returns its best period, because the best of a set is always something; a
    structureless sequence has one too, and its ratio is not one but a spread, since which period looks
    best wanders from shuffle to shuffle. This draws that spread. A live reading means a period is
    present only when it stands above the top of this band, which is drawn from the data and never a
    threshold chosen here. `draws` is a declared input.

    The whole spread is returned, not just its top, so a caller can report how much of a margin is the
    effect and how much is the draw. At a large separation the spread does not matter; at a single-digit
    ratio it is the difference between a finding and a shuffle that got lucky. The boundary a reading
    must clear is the last element; the first and last together are the spread.

    Returns the sorted list of ratios the shuffles reached, empty where none reached one. `draws` is a
    small sample, so widen it for a marginal case rather than trusting one draw.
    """
    values = list(values)
    ratios = []
    for step in range(draws):
        _, ratio, _ = recover_period(list(permuted(values, seed + step)), reach, seed + step + 1)
        if ratio is not None:
            ratios.append(ratio)
    return sorted(ratios)
