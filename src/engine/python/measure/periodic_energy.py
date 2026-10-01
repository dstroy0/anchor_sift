#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The period a coherent addend keeps, read off how much energy its phase splits away from a shuffle.
#
#   Usage:  from measure.periodic_energy import between_classes, against_a_shuffle, recover_period
#
# There are two coherent things a period can name and they need two detectors. shift_agreement reads
# EXACT self-equality. It finds a coherent TARGET: a sequence that repeats, whose every match at
# the period is an equality between whole values. An impulse breaks a few of those equalities and the
# family rule survives it. That detector carries the replacement-noise case.
#
# It cannot find a coherent NOISE component hiding in a target that does not repeat. A hum added to
# speech makes x[n] equal x[n+P] only where the speech already did, which is nowhere. Exact
# agreement reads nothing while the hum is plainly there. What the hum does leave is energy: the
# positions of one phase all carry the same addend. Grouping by phase concentrates that addend's
# energy into the class means and a wrong period does not. This detector reads that concentration.
#
# The quantity is the between-class sum of squares, the energy that sits in the differences between
# the phase means and not inside the classes. It rises with the period on its own, because more
# classes hold more between-class variance whatever the data. The count alone means nothing. The
# only thing that means anything is the amount above what the same histogram reaches with its
# positions shuffled: reference.shuffles.permuted holds every value and destroys every phase. Its
# between-class energy at a period is the mechanical part, and the live reading minus it is the part
# the phase actually carries. This is against_a_shuffle from shift_agreement, in energy.
#
# WHY A RATIO AND NOT A RAW ENERGY
#
# Between-class energy rises with the period on its own: more classes hold more of it whatever the
# data. The raw quantity picks the longest period every time and every multiple of a true period
# outscores the period itself. The fix comes from analysis of variance, which has used it for a century. Divide
# the between-class energy by its degrees of freedom, the period minus one, and divide the within-class
# energy by its own, the length minus the period, and take the ratio. The ratio does not grow with the
# period, and a multiple of the true period splits the same energy across more classes for more
# degrees of freedom. It scores strictly below the fundamental. A period that explains nothing sits
# near one, the value with no structure, and the true period stands far above it.
#
# The perfectly periodic case, where a period drives the within-class energy to zero, is not this
# detector's. A sequence that repeats exactly is a coherent TARGET and shift_agreement reads it by
# exact equality; here that case is declined and not reported. The two detectors never both
# claim one reading.
#
# NOTHING IS BOUNDED HERE
#
# `reach`, the longest period considered, is a declared input reported beside the reading, not a
# ceiling chosen until the answer appeared; the difference set has no ceiling and this scan states
# the one it used. The energy and the ratio are exact rational. The null is drawn, never derived, and
# it is the same null the tree already uses: a period that stands above its own shuffle carries phase
# the shuffle could not, and the shuffle's ratio is reported beside the live one so the reader sees
# the floor it cleared.
#
# WHICH OF THESE THE ENGINE HOLDS IN C
#
# The engine's form is src/sims/cu/engine/analysis/art/periodic_energy.h, which the fixed_pattern and
# classify_reject_recover sims call, and the functions named for it below are its Python route:
# energy_ratio, energy_recover, energy_shuffle, energy_band_top, energy_above,
# energy_welford, energy_reduction and energy_print. utils/test/python/periodic_energy_test.py grades them
# against the header through utils/test/src/cu/engine/analysis/periodic_energy_probe.cu, and the two share no code.
#
# The header's ratio is the value dispersion_ratio returns, held unreduced as the header holds it:
# both energies scaled by the length times the two member counts. Its recover returns no reading at
# a reach below 2 where recover_period raises the reach
# to 2, it draws its shuffles from sim_draw where these draw from
# reference.shuffles, and its null keeps the band's top and the count of shuffles that reached a
# period, where null_band keeps every ratio. between_classes, total_energy, dispersion_ratio,
# against_a_shuffle, recover_period and null_band have no C counterpart.
#
# The header holds the phase sums, the Welford steps and the reduction's per-value terms in 64 bit
# words, and its comments bound them for its callers' values and member counts below 2^16. The
# Python holds them exact, and the two agree where the header's words hold.

import collections
from fractions import Fraction
from functools import cmp_to_key

from reference.exact_ratio import whole, add, sub, over, compare, ratio_text
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
        return whole(0)
    sums = [0] * period
    counts = [0] * period
    for index, value in enumerate(values):
        phase = index % period
        sums[phase] += value
        counts[phase] += 1
    within = whole(0)
    for phase in range(period):
        if counts[phase]:
            within = add(within, (sums[phase] * sums[phase], counts[phase]))
    grand = (sum(sums) ** 2, length)
    return sub(within, grand)


def total_energy(values):
    """The energy in the values about their grand mean, exact. Between plus within always sums to it.

    Written with one division at the end: the length times the summed squares, less the summed value
    squared, over the length.
    """
    length = len(values)
    if length == 0:
        return whole(0)
    summed = sum(values)
    squares = sum(value * value for value in values)
    return (length * squares - summed * summed, length)


def dispersion_ratio(values, period):
    """The between-class energy per degree of freedom over the within-class energy per its own.

    The analysis-of-variance ratio for grouping the values by phase. The between-class part is divided
    by the period less one and the within-class part, the total less the between, by the
    length less the period. It does not grow with the period and it suppresses a multiple of the true
    period, which splits the same energy over more classes. A grouping that explains nothing sits near
    one and the true period stands far above.

    Returns the ratio as an exact rational, or None where a degree of freedom runs out or the period
    explains all the energy. The second is the perfectly periodic case, a repeating target, which is
    shift_agreement's reading and is declined here so the two detectors never both claim it.
    """
    length = len(values)
    between = between_classes(values, period)
    within = sub(total_energy(values), between)
    freedom_between = period - 1
    freedom_within = length - period
    if (
        (freedom_between <= 0)
        or (freedom_within <= 0)
        or (compare(within, whole(0)) <= 0)
    ):
        return None
    return over(
        over(between, whole(freedom_between)), over(within, whole(freedom_within))
    )


def against_a_shuffle(values, period, seed=SEED):
    """The dispersion ratio at a period, and the ratio a shuffle of the same values reaches.

    The shuffle holds the histogram exactly and destroys every phase. Its ratio is what this
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
    because the multiple spends more degrees of freedom on the same energy. `reach` is the only
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
        if (best is None) or (compare(ratio, best) > 0):
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

    The whole spread is returned, not just its top. A caller can report how much of a margin is the
    effect and how much is the draw. At a large separation the spread does not matter; at a single-digit
    ratio it is the difference between a finding and a shuffle that got lucky. The boundary a reading
    must clear is the last element; the first and last together are the spread.

    Returns the sorted list of ratios the shuffles reached, empty where none reached one. `draws` is a
    small sample. Widen it for a marginal case instead of trusting one draw.
    """
    values = list(values)
    ratios = []
    for step in range(draws):
        _, ratio, _ = recover_period(
            list(permuted(values, seed + step)), reach, seed + step + 1
        )
        if ratio is not None:
            ratios.append(ratio)
    return sorted(ratios, key=cmp_to_key(compare))


# The engine's form, src/sims/cu/engine/analysis/art/periodic_energy.h.

_MASK64 = 0xFFFFFFFFFFFFFFFF

EnergyMeasurement = collections.namedtuple("EnergyMeasurement", ["found", "period", "numerator", "denominator"])
_NONE = EnergyMeasurement(False, 0, 0, 0)


def _mix(word):
    mixed = (word + 0x9E3779B97F4A7C15) & _MASK64
    mixed = ((mixed ^ (mixed >> 30)) * 0xBF58476D1CE4E5B9) & _MASK64
    mixed = ((mixed ^ (mixed >> 27)) * 0x94D049BB133111EB) & _MASK64
    return mixed ^ (mixed >> 31)


def _draw(key, counter):
    """sim_draw in src/sims/cu/sim.h."""
    return _mix((key & _MASK64) ^ _mix(counter & _MASK64))


def energy_members(length, period, phase):
    """The count of positions below `length` congruent to `phase` modulo `period`."""
    return (length // period) + (1 if phase < (length % period) else 0)


def energy_ratio(values, period):
    """The dispersion ratio at a period as the header holds it: (numerator, denominator), or None.

    Both energies are scaled by the length times the two member counts, the count of a phase with
    one member fewer and one with one more, and neither is reduced. The numerator is the between
    energy times the length less the period, the denominator the within energy times the period less
    one. None where the period is below 2 or not below the length, or the within energy is not above
    zero.
    """
    length = len(values)
    if period < 2 or period >= length:
        return None
    fewer = length // period
    more = fewer + 1
    sums = [sum(values[phase::period]) for phase in range(period)]
    fewer_squares = sum(sums[phase] * sums[phase] for phase in range(period)
                        if energy_members(length, period, phase) != more)
    more_squares = sum(sums[phase] * sums[phase] for phase in range(period)
                       if energy_members(length, period, phase) == more)
    integer_sum = sum(sums)
    integer_squares = sum(value * value for value in values)
    counts = fewer * more
    between = (length * more * fewer_squares) + (length * fewer * more_squares) - (integer_sum * integer_sum * counts)
    within = ((length * integer_squares) - (integer_sum * integer_sum)) * counts - between
    if within <= 0:
        return None
    return between * (length - period), within * (period - 1)


def _above(one, other):
    """Whether the ratio one exceeds the ratio other, each (numerator, denominator) of positive denominator."""
    return one[0] * other[1] > other[0] * one[1]


def energy_recover(values, reach):
    """The period of highest ratio from 2 to the reach, as an EnergyMeasurement, or None where the header fails.

    The reach is held at the length less one. The first period of the highest ratio is kept. The
    reading is not found where no period has a ratio. None where the length is below 4 or the reach
    below 2.
    """
    values = list(values)
    length = len(values)
    if length < 4:
        return None
    top = min(reach, length - 1)
    if top < 2:
        return None
    best = _NONE
    for period in range(2, top + 1):
        ratio = energy_ratio(values, period)
        if ratio is None:
            continue
        if not best.found or _above(ratio, (best.numerator, best.denominator)):
            best = EnergyMeasurement(True, period, ratio[0], ratio[1])
    return best


def energy_shuffle(values, key):
    """The values permuted by a Fisher-Yates walk from the last place down, each swap drawn by sim_draw."""
    shuffled = list(values)
    for at in range(len(shuffled) - 1, 0, -1):
        other = _draw(key, at) % (at + 1)
        shuffled[at], shuffled[other] = shuffled[other], shuffled[at]
    return shuffled


def energy_band_top(values, reach, draws, key):
    """The highest reading `draws` shuffles reach, and how many reached one, or None where one fails.

    Shuffle d is keyed by sim_draw(key, d). Returns (top, reached), the top an EnergyMeasurement that is
    not found where no shuffle reached a period.
    """
    top = _NONE
    reached = 0
    for number in range(draws):
        reading = energy_recover(energy_shuffle(values, _draw(key, number)), reach)
        if reading is None:
            return None
        if not reading.found:
            continue
        reached += 1
        if not top.found or _above((reading.numerator, reading.denominator), (top.numerator, top.denominator)):
            top = reading
    return top, reached


def energy_above(live, top):
    """Whether a live reading is found and stands strictly above the band's top, or the band has none."""
    if not live.found:
        return False
    if not top.found:
        return True
    return _above((live.numerator, live.denominator), (top.numerator, top.denominator))


def energy_welford(values, period):
    """Each phase's mean as (numerator, denominator) in lowest terms, the denominator positive.

    The header runs Welford's update in exact fractions and reduces each step by the common divisor,
    which leaves the phase's mean in lowest terms; a phase with no members reads 0/1.
    """
    means = []
    for phase in range(period):
        members = values[phase::period]
        mean = Fraction(sum(members), len(members)) if members else Fraction(0)
        means.append((mean.numerator, mean.denominator))
    return means


def energy_reduction(noisy, target, period, phase_sums):
    """The share of the injected energy that removing each phase's mean takes away, as (numerator, denominator).

    `phase_sums` holds one sum for each phase, as the header's caller hands it. The injected energy
    is the summed square of noisy less target. The left energy is the summed square of each value's
    member count times noisy less target, less its phase's sum, over the count squared. The share is
    one less the left over the injected, held over the square of both member counts, and 1/1 where
    nothing was injected.
    """
    length = len(noisy)
    fewer = length // period
    more = fewer + 1
    injected = sum((one - other) * (one - other) for one, other in zip(noisy, target))
    left_fewer = 0
    left_more = 0
    for at in range(length):
        members = energy_members(length, period, at % period)
        left = (members * (noisy[at] - target[at])) - phase_sums[at % period]
        if members == more:
            left_more += left * left
        else:
            left_fewer += left * left
    if injected == 0:
        return 1, 1
    energy = (left_fewer * more * more) + (left_more * fewer * fewer)
    denominator = (fewer * fewer) * (more * more) * injected
    return denominator - energy, denominator


def energy_print(reading, places=3):
    """energy_print: "none", or the reading's ratio to three decimals."""
    if not reading.found:
        return "none"
    return ratio_text(reading.numerator, reading.denominator, places)
