#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The background a fixed period allows, built out of the data by phase.
#
#   Usage:  from reference.periodic import mean_background, mean_residual, restore, consensus
#
# A period is a constraint the object supplies: once a period P is fixed, every position n is bound
# to the positions congruent to it modulo P, and to nothing else. Those positions are a phase class.
# The maximum entropy background under that one constraint is the value that asserts nothing beyond
# what each phase class already holds, and that is different for the two things noise does to a
# sample.
#
# Noise that ADDS to a sample (a hum, a periodic interference, an offset that repeats) leaves the
# phase class holding one number plus a spread. The least committal reconstruction of the addend,
# fixing only the class's first moment, is the mean of the class. Subtract that tiled mean and the
# residual is whatever varied inside the class, the part the period did not explain. When the
# thing that varies sums to zero inside every class -- the target sitting orthogonal to the period's
# subspace -- the mean is the addend exactly and the residual is the target exactly, to the last
# digit, because the arithmetic is Fraction and nothing here rounds.
#
# Noise that REPLACES a sample (an impulse, a dropout, a stuck value) leaves the phase class holding
# the true value in most of its members and a wrong value in a few. Fixing a first moment is the
# wrong background there: one large impulse drags the mean off the value every clean member agrees
# on. The least committal reconstruction under a fixed multiset is the value the class agrees on, the
# consensus, and where a clean majority survives the consensus is the true value exactly.
#
# NOTHING IS BOUNDED HERE
#
# The period is an input, not a constant chosen here; it comes from measure/ and is reported beside
# every number. The mean is exact rational and the consensus is an exact count. No tolerance, no
# threshold and no learned parameter sits between the data and the background. The two routes for each
# background share no code and no arithmetic. Where they disagree the disagreement is a defect in
# one of them and not a rounding either was allowed.
#
# Two routes for the mean: a batch sum divided once, and an incremental Welford mean that divides once
# per member. Two routes for the consensus: the value of greatest count, and the median of the sorted
# class. Each pair is a different algorithm reaching the same rational or the same integer, and the
# caller checks that they land on it.

from reference.exact_ratio import whole, add, sub, over, reduced


def phase_totals(values, period):
    """Each phase class's sum and its count, in one pass indexed by position modulo the period.

    A phase class is the positions congruent modulo `period`. This walks every position once and adds
    its value to the class its index falls in. The pair it returns is all the mean route needs and it
    is the batch half of the two-route mean.
    """
    sums = [0] * period
    counts = [0] * period
    for index, value in enumerate(values):
        phase = index % period
        sums[phase] += value
        counts[phase] += 1
    return sums, counts


def mean_background(values, period):
    """The phase mean tiled back over every position, as exact rationals. Route one, batch.

    Each position carries the mean of its phase class, computed as a single Fraction of the class sum
    over the class count. This is the maximum entropy background under the one constraint that a
    value depends only on its phase: it fixes each class's first moment and asserts nothing else.
    """
    sums, counts = phase_totals(values, period)
    means = [reduced(sums[phase], counts[phase]) for phase in range(period)]
    return [means[index % period] for index in range(len(values))]


def mean_background_incremental(values, period):
    """The same phase means, reached one member at a time down each phase. Route two, incremental.

    Each phase class is read on its own stride and its mean is grown by the Welford update, exact in
    Fraction: the mean after i members is the mean after i minus one plus the new member's distance
    from it over i. It shares no sum, no traversal and no division count with `mean_background`.
    """
    means = [None] * period
    length = len(values)
    for phase in range(period):
        running = whole(0)
        seen = 0
        index = phase
        while index < length:
            seen += 1
            running = add(
                running, over(sub(whole(values[index]), running), whole(seen))
            )
            index += period
        means[phase] = running
    return [means[index % period] for index in range(length)]


def mean_residual(values, period, background=None):
    """What each position holds above the phase mean, as exact rationals.

    This is the reject step for additive noise: the tiled mean is the identified periodic component
    and the residual is the target it was hiding. Pass a `background` already built to avoid building
    it twice, or leave it out and the batch route builds one.
    """
    if background is None:
        background = mean_background(values, period)
    return [sub(whole(value), back) for value, back in zip(values, background)]


def consensus_majority(values, period, on_tie=min):
    """Each phase class's value of greatest count, tiled back over every position. Route one.

    The reject step for replacement noise. A class holding the true value in most members and a wrong
    value in a few returns the true value, because the true value is the one most members carry. A
    tie is broken by `on_tie` over the tied values, a declared rule reported with the reading and not
    a value chosen until the output looked right; it only decides classes with no majority at all,
    which are the floor this cannot clear.
    """
    length = len(values)
    picked = [None] * period
    for phase in range(period):
        tally = {}
        index = phase
        while index < length:
            tally[values[index]] = tally.get(values[index], 0) + 1
            index += period
        most = max(tally.values())
        picked[phase] = on_tie(value for value, count in tally.items() if count == most)
    return [picked[index % period] for index in range(length)]


def consensus_median(values, period):
    """Each phase class's median, tiled back over every position. Route two.

    The lower of the two middle values on an even class, a declared rule. Where a phase class carries
    a strict majority of one value the median is that value. This agrees with the count route to
    the integer on every class a majority reaches. It sorts and selects where the other counts.
    """
    length = len(values)
    picked = [None] * period
    for phase in range(period):
        members = sorted(values[phase:length:period])
        picked[phase] = members[(len(members) - 1) // 2]
    return [picked[index % period] for index in range(length)]


def restore(values, period, route=consensus_majority):
    """The signal a period allows, with each position replaced by its phase consensus.

    The reconstruction for replacement noise: every position becomes the value its phase class agrees
    on. The few members that were overwritten are restored from the many that were not. `route`
    selects which consensus, and the two routes are checked against each other by the caller.
    """
    return route(values, period)
