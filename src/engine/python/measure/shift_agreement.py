#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How often a sequence agrees with itself at a fixed offset, which reads a period from nothing.
#
#   Usage:  from measure.shift_agreement import agreement, strongest_lags, recover_period
#
# The second of the two instruments in this work, and the only one with an answer from outside it.
#
# What it has read, with nothing told to it. Published cell edges from the Crystallography Open
# Database, tiled and voxelized: 453 axes over 151 structures, every one recovered inside one voxel
# of 0.25 angstroms, at a mean absolute error of 0.0124 and a worst of 0.0554. An image read as a
# byte sequence returns its own width. A Vigenere cipher returns its key length.
#
# Three of those axes missed before the family rule was fixed, all short by a factor near two thirds.
# The cause was dimensional. Family size grew as the candidate shrank. A short wrong candidate held
# more multiples and only had to catch one good lag among them. A cell edge is not a whole
# number of voxels, and the remainder supplied the good lag: on a 4.148 angstrom axis the period is
# 16.59 voxels, so lag 16 sits 0.59 away while lag 33 sits 0.18 from twice it. Lag 33 therefore
# agreed better than the fundamental, and it fell inside the family of 11 and outside the family of
# 16. Capping every family at two multiples equalized the comparison and the three came back.
#
# It is not the null permutation identity and the two are not interchangeable as evidence. Three
# separate claims in this work merged them: a positive control was reported for the measure that
# never received one, a cross media claim was written for a measure that had not been run on two of
# the media, and an ordering of structure meters was drawn between them. Each was corrected after
# the fact, and the pattern recurred three times without being noticed once.
#
# What it can and cannot find. It tests one hypothesis, that the sequence agrees with itself at a
# fixed offset, so periodicity is the only thing it can report. English prose and C source read
# nothing above their own shuffles, and English peaks below its shuffle. Both have structure.
# Neither has agreement with itself at a fixed offset.
#
# A raw count carries no information on its own. Tests of one shift share read positions, and a
# standard error computed as though they were independent comes out far too small. The first run
# reported
# twelve findings on SHA-256 output, and a shuffle of the same bytes reported sixteen. Only a
# null permutation makes a count mean anything.

import numpy

# Positions sampled per lag. A coprime stride keeps the sample from landing on the period itself.
STRIDE = 7


def agreement(data, lag, stride=STRIDE):
    """Share of positions equal to the position one lag away.

    Sampled every `stride` positions, which keeps a long sequence affordable. The stride is coprime
    to the periods usually looked for, so it does not line up with the thing being measured.
    """
    if lag >= len(data):
        return 0.0
    total = len(data) - lag
    spots = range(0, total, stride)
    hits = sum(1 for index in spots if data[index] == data[index + lag])
    return hits / float(len(spots))


def strongest_lags(data, most=1200, keep=8, stride=STRIDE):
    """The lags where the sequence agrees with itself most, strongest first.

    A real period shows with its neighbors beside it and its harmonics behind it. A lag that won by
    chance has neither.
    """
    marks = []
    for lag in range(1, min(most, len(data) // 4)):
        marks.append((agreement(data, lag, stride), lag))
    marks.sort(reverse=True)
    return marks[:keep]


def recover_period(data, most=1200, stride=STRIDE):
    """The period and the fraction between the two lags straddling it.

    Quantization does not lose the true period, it moves it into the ratio between two lags. A cell
    of 10.1000 angstroms at a voxel of 0.25 is 40.40 voxels, so successive tiles land alternately on
    40 and 41, and the share of agreement at the upper one carries the fraction. Measured, that
    share gives 0.407 against a true 0.400, which recovers the edge to 0.0018 angstroms against a
    grid of 0.25.

    Returns the whole lag, the fraction, and the agreement at the whole lag.
    """
    marks = strongest_lags(data, most, keep=4, stride=stride)
    if not marks:
        return None, None, None

    score, lag = marks[0]
    above = agreement(data, lag + 1, stride)
    below = agreement(data, lag - 1, stride) if lag > 1 else 0.0
    neighbor = above if above >= below else below
    share = neighbor / (score + neighbor) if (score + neighbor) > 0.0 else 0.0
    return lag, (share if above >= below else -share), score


def lattice_agreement(grid, axis, lag):
    """Share of occupied cells whose neighbor `lag` along one axis carries the same value.

    The same reading `agreement` performs on a line, taken on a grid of any rank. Empty cells are
    not counted: a voxel grid built from atom sites is mostly empty, and counting the emptiness
    would report how empty it is, which every structure agrees on.

    Returns 0.0 where the lag reaches past the axis or nothing is occupied.
    """
    if lag >= grid.shape[axis]:
        return 0.0

    below = [slice(None)] * grid.ndim
    above = [slice(None)] * grid.ndim
    below[axis] = slice(0, grid.shape[axis] - lag)
    above[axis] = slice(lag, grid.shape[axis])

    left = grid[tuple(below)]
    right = grid[tuple(above)]
    occupied = left != 0
    tried = int(occupied.sum())
    if tried == 0:
        return 0.0
    return float(((left == right) & occupied).sum()) / float(tried)


def exact_agreement(placed, lag):
    """How many exact places carry the same value as the place exactly one lag away.

    `placed` maps an integer position to the value sitting there, at whatever scale the caller
    chose. A lag is an integer at that same scale, so the comparison is equality between integers
    and carries no tolerance at all. Nothing is sampled and nothing is bounded.

    This is the sparse counterpart of agreement(). That one walks an array and samples every
    STRIDE positions to keep a long sequence affordable; a point set has nothing to walk, the
    occupied places are few, and a dictionary lookup costs the same whatever the scale. Precision
    is free here in a way it is not there, and a larger scale runs no slower.

    The value has to be compared and not just the position. Ignoring it reads a rocksalt cell at
    half its published edge, correctly: the two sublattices interleave, so the positions alone do
    repeat every a/2 and only the elements distinguish the two halves. lattice_agreement compares
    element codes on the grid for the same reason.
    """
    return sum(1 for one, value in placed.items() if placed.get(one + lag) == value)


def recover_exact_period(placed, families=2):
    """The period of an exact point set, read off the whole of its own difference set.

    Every difference between two places is a candidate, and that set is complete: a period that
    agrees with anything at all appears in it. There is no sweep, no ceiling and no stride, so
    nothing here narrows what can be found.

    The family rule matches recover_lattice_period and it is needed for the same reason. A
    set with period P agrees with itself at 2P and 3P as well, so the tallest lag alone reports a
    harmonic. A candidate is scored as the mean over itself and its multiples, and the family is
    capped at `families` members: a family growing as the candidate shrinks lets a short wrong
    candidate win by holding more members, needing only one good lag among them.

    Returns (period, agreement at it) as exact integers, or (None, None) where nothing agreed.
    """
    if len(placed) < 3:
        return None, None

    ordered = sorted(placed)
    candidates = set()
    for at, first in enumerate(ordered):
        for second in ordered[at + 1:]:
            candidates.add(second - first)
    if not candidates:
        return None, None

    scores = {}
    for lag in candidates:
        scores[lag] = exact_agreement(placed, lag)

    best = None
    period = None
    for candidate in sorted(candidates):
        family = [scores[candidate * step] for step in range(1, families + 1)
                  if (candidate * step) in scores]
        if len(family) < families:
            continue
        mean = sum(family) / float(len(family))
        if (best is None) or (mean > best):
            best = mean
            period = candidate

    if period is None:
        return None, None
    return period, scores[period]


def recover_lattice_period(grid, axis, most=None):
    """The period along one axis of a grid, and the fraction between the two lags straddling it.

    Scored on a candidate and all of its multiples, never on the single tallest lag. A lattice of
    period P agrees with itself just as well at 2P and 3P, so the tallest of those is settled by
    noise and taking it reports a harmonic. Read that way, published cell edges came back at almost
    exactly twice their value on ten of eighteen axes.

    A candidate needs two of its multiples inside the range to be scored at all. That excludes the
    first harmonic, because a sweep a little past 2P leaves 2P holding only itself.

    A cell edge is not a whole number of voxels, so successive tiles land alternately on two lags
    and the share of agreement at the upper one carries the fraction between them. Quantization
    moves the true period into that ratio instead of destroying it.

    Returns (lag, fraction, agreement at the lag), or (None, None, None) where nothing agreed.
    """
    reach = most if most is not None else (grid.shape[axis] // 2)
    reach = max(4, int(reach))

    agreements = {lag: lattice_agreement(grid, axis, lag) for lag in range(1, reach + 1)}
    if not any(value > 0.0 for value in agreements.values()):
        return None, None, None

    best_margin = None
    lag = None
    for period in range(2, (reach // 2) + 1):
        # Exactly two multiples for every candidate, never more. Family size otherwise grows as the
        # candidate shrinks, and the score is a mean over the family. A short wrong candidate can
        # win by holding more members. It only has to catch one good lag among them.
        #
        # A cell edge is not a whole number of voxels, and that supplies the good lag. On a
        # 4.148 angstrom axis at 0.25 the period is 16.59 voxels, so lag 16 is off by 0.59 and lag 33
        # is off by 0.18. Lag 33 therefore agrees better than the fundamental does. A sweep to
        # 2P + 6 puts 33 inside the family of 11 and outside the family of 16, and 11 wins an axis
        # it has no business winning. Herzenbergite, molybdite and one more all failed this way, each
        # reading short by a factor near two thirds.
        family = [agreements[step] for step in (period, 2 * period) if step <= reach]
        outside = [value for step, value in agreements.items() if (step % period) != 0]
        if (len(family) < 2) or (not outside):
            continue
        margin = (sum(family) / len(family)) - (sum(outside) / len(outside))
        if (best_margin is None) or (margin > best_margin):
            best_margin = margin
            lag = period

    if (lag is None) or (best_margin is None) or (best_margin <= 0.0):
        return None, None, None

    score = agreements[lag]
    above = agreements.get(lag + 1, lattice_agreement(grid, axis, lag + 1))
    below = agreements.get(lag - 1, 0.0) if lag > 1 else 0.0
    neighbor = above if above >= below else below
    share = (neighbor / (score + neighbor)) if (score + neighbor) > 0.0 else 0.0
    return lag, (share if above >= below else -share), score


def against_a_shuffle(data, seed=0x51F7, most=1200, stride=STRIDE):
    """The strongest agreement, and the strongest a shuffle of the same bytes reaches.

    The shuffle holds the histogram and destroys the positions. Only the difference between the two
    counts means anything. On SHA-256 output the live count was twelve and the shuffled count was
    sixteen, so the raw count carried nothing at all.
    """
    live = strongest_lags(data, most, keep=1, stride=stride)
    scattered = numpy.asarray(bytearray(data), dtype=numpy.uint8).copy()
    numpy.random.default_rng(seed).shuffle(scattered)
    dead = strongest_lags(bytes(scattered), most, keep=1, stride=stride)
    return (live[0] if live else None), (dead[0] if dead else None)
