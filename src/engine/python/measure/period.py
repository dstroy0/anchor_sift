#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The engine's period reader in Python: period_read and period_draw.
#
#   Usage:  from measure.period import read, draw
#
# The Python route to src/engine/analysis/period/period_*.cu at anchor_sift 1789287. That file reads a
# volume of 16 bit lanes on the device and returns, for each axis, the period the volume carries
# along it, and this reads the same volume on the host in exact integers and returns the same
# reading field for field. The two share no code, and utils/test/python/period_test.py grades them
# against each other through utils/test/src/cu/engine/analysis/period/period_probe.cu, which calls the engine's entry points.
#
# WHAT IS READ
#
# Along an axis of extent n, lag L runs from 1 to n // 2, and each lag compares the same pairs: every
# voxel whose place along the axis is below n - n // 2 against the voxel L further along. The count
# of equal pairs at each lag is the agreement. A candidate period P is a peak when the agreement at P
# exceeds both its neighbors and the agreement at 2P exceeds both of its, and the peak's height is
# the smaller of the two rises. A candidate that peaks at P and not at 2P is not taken.
#
# The null is drawn per axis. Each line along the axis is shuffled alone, a Fisher-Yates walk keyed
# by the volume's content signum and a counter, and the strongest peak the shuffled axis reaches is
# one draw of that axis's band. Shuffling every line along one axis destroys that axis's coherence
# and leaves every other axis's structure and every line's values in place. A global shuffle would
# drop the whole volume's agreement and read a period on an axis carrying none whenever another axis
# is structured. The period is the smallest candidate whose height, over the pairs a lag compares,
# exceeds the band's top, compared as exact ratios by cross multiplying. Where none does, the period
# is 0 and the candidate shown is the strongest peak, the smallest on a tie.
#
# NOT THE SAME COMPUTATION AS periodicity.py OR reference/periodic.py
#
# measure/periodicity.py reads one sequence's agreement with itself at every lag and takes the lag
# that stays stable across windows. reference/periodic.py builds the background a period allows,
# phase by phase. Neither is this reading, and neither has a C counterpart. The engine form of
# shift_agreement.recover_lattice_period, a candidate scored with its double, is this module.

import collections

ARRAY_RANK = 8
VALUES = 65536
VOXELS_MOST = 0xFFFFFFFF
ROUNDS = 4
SIGNUM_BYTES = 32
_MASK32 = 0xFFFFFFFF
_MASK64 = 0xFFFFFFFFFFFFFFFF

Axis = collections.namedtuple("Axis", [
    "extent", "period", "candidate", "lags", "pairs_per_lag", "agreement_at_candidate",
    "agreement_beside_candidate", "agreement_at_double", "agreement_beside_double", "margin",
    "band_count", "band_bottom", "band_top"])
Reading = collections.namedtuple("Reading", [
    "rank", "voxels", "collisions", "draws", "axis", "agreement", "band"])


def _lattice(shape):
    """The C's PeriodLattice for a shape, or None where period_lattice_fill errors on it."""
    rank = len(shape)
    if rank < 1 or rank > ARRAY_RANK:
        return None
    count = 1
    for extent in shape:
        if extent < 1 or extent > VOXELS_MOST // count:
            return None
        count *= extent
    stride = [0] * rank
    running = 1
    for axis in range(rank - 1, -1, -1):
        stride[axis] = running
        running *= shape[axis]
    first = []
    total = 0
    for extent in shape:
        first.append(total)
        total += extent // 2
    return {
        "rank": rank,
        "extent": list(shape),
        "stride": stride,
        "usable": [extent - (extent // 2) for extent in shape],
        "pairs": [(extent - (extent // 2)) * (count // extent) for extent in shape],
        "first": first,
        "lag_total": total,
        "voxels": count,
    }


def _axis_agreement(lanes, lattice, axis):
    """The count of equal pairs at each lag 1 to extent // 2 along one axis."""
    extent = lattice["extent"][axis]
    stride = lattice["stride"][axis]
    usable = lattice["usable"][axis]
    outers = lattice["voxels"] // (extent * stride)
    same = []
    for lag in range(1, (extent // 2) + 1):
        reach = lag * stride
        count = 0
        for outer in range(outers):
            start = outer * extent * stride
            for along in range(usable):
                base = start + (along * stride)
                near = lanes[base:base + stride]
                far = lanes[base + reach:base + reach + stride]
                count += sum(1 for one, other in zip(near, far) if one == other)
        same.append(count)
    return same


def _beside(same, lag):
    return max(same[lag - 2], same[lag])


def _peak(same, candidate):
    """(at, beside, doubled, beside_double, height) at a candidate, or None where it is no peak."""
    at = same[candidate - 1]
    beside = _beside(same, candidate)
    doubled = same[(2 * candidate) - 1]
    beside_double = _beside(same, 2 * candidate)
    if at <= beside or doubled <= beside_double:
        return None
    return at, beside, doubled, beside_double, min(at - beside, doubled - beside_double)


def _candidates(lags):
    candidate = 2
    while (2 * candidate) + 1 <= lags:
        yield candidate
        candidate += 1


def _strongest(same, lags):
    """The largest peak, the smallest candidate on a tie, as (candidate, peak), or None."""
    best = None
    for candidate in _candidates(lags):
        peak = _peak(same, candidate)
        if peak is not None and (best is None or peak[4] > best[1][4]):
            best = (candidate, peak)
    return best


def _above(one, other):
    """Whether the ratio one exceeds the ratio other, each (numerator, denominator)."""
    return one[0] * other[1] > other[0] * one[1]


def _fundamental(same, lags, pairs, top):
    """The smallest candidate whose height over `pairs` exceeds `top`, as (candidate, peak), or None."""
    for candidate in _candidates(lags):
        peak = _peak(same, candidate)
        if peak is not None and _above((peak[4], pairs), top):
            return candidate, peak
    return None


def _mix(word):
    mixed = (word + 0x9E3779B97F4A7C15) & _MASK64
    mixed = ((mixed ^ (mixed >> 30)) * 0xBF58476D1CE4E5B9) & _MASK64
    mixed = ((mixed ^ (mixed >> 27)) * 0x94D049BB133111EB) & _MASK64
    return mixed ^ (mixed >> 31)


def _keys(content, counter):
    """The four 32 bit shuffle keys for one draw of one axis, from the content signum."""
    words = [int.from_bytes(content[8 * at:8 * (at + 1)], "little") for at in range(4)]
    return [_mix(words[round_ % 4] ^ _mix(((counter * ROUNDS) + round_) & _MASK64)) & _MASK32
            for round_ in range(ROUNDS)]


def _round(half, key):
    mixed = ((half ^ key) * 0x9E3779B1) & _MASK32
    mixed ^= mixed >> 15
    mixed = (mixed * 0x85EBCA77) & _MASK32
    return mixed ^ (mixed >> 13)


def _line_random(keys, line, step):
    hashed = _round((line & _MASK32) ^ keys[0], keys[1])
    hashed = _round(hashed ^ ((line >> 32) & _MASK32), keys[2])
    return _round(hashed ^ step, keys[3])


def _line_shuffle(lanes, lattice, axis, keys):
    """The lanes with every line along one axis permuted alone, as period_line_shuffle_kernel does."""
    shuffled = list(lanes)
    extent = lattice["extent"][axis]
    stride = lattice["stride"][axis]
    for line in range(lattice["voxels"] // extent):
        base = ((line // stride) * extent * stride) + (line % stride)
        for step in range(extent - 1, 0, -1):
            other = _line_random(keys, line, step) % (step + 1)
            here = base + (step * stride)
            there = base + (other * stride)
            shuffled[here], shuffled[there] = shuffled[there], shuffled[here]
    return shuffled


def _null_height(lanes, lattice, content, counter, axis):
    """One draw of an axis's band: the strongest peak its line shuffle reaches, over its pairs."""
    shuffled = _line_shuffle(lanes, lattice, axis, _keys(content, counter))
    best = _strongest(_axis_agreement(shuffled, lattice, axis), lattice["extent"][axis] // 2)
    return (best[1][4] if best is not None else 0), lattice["pairs"][axis]


def _checked(lanes, content, voxels):
    if len(lanes) != voxels:
        raise ValueError("%d lanes for a shape of %d voxels" % (len(lanes), voxels))
    if any(lane < 0 or lane >= VALUES for lane in lanes):
        raise ValueError("a lane outside 0 to 65535")
    if len(content) != SIGNUM_BYTES:
        raise ValueError("the content signum holds %d bytes and must hold 32" % len(content))
    return list(lanes), bytes(content)


def read(lanes, shape, draws, content, null_top=None):
    """period_read on the host. Returns a Reading, or None where the C errors on the request.

    `lanes` is the volume, flat and row major with the last axis fastest, each lane 0 to 65535.
    `content` is the volume's 32 byte content signum, which keys the shuffles. With `null_top`
    None the band is drawn, and `draws` must be 1 to 536870911; with a top given an axis, as
    (numerator, denominator) pairs, `draws` must be 0 and the top is used as given.

    The Reading carries the C's fields: `axis` a list of Axis, each margin and band edge an exact
    (numerator, denominator); `agreement` the counts at every lag of every axis, the first axis's
    lags first; `band` the draws an axis laid as the C lays them, each axis's `draws` entries with
    the heights that reached a peak first and sorted, and (0, 0) past them.
    """
    lattice = _lattice(shape)
    if lattice is None:
        return None
    if null_top is None:
        if draws < 1 or draws > VOXELS_MOST // ARRAY_RANK:
            return None
    elif draws != 0:
        return None
    elif len(null_top) < lattice["rank"]:
        raise ValueError("a null top for %d axes and a shape of %d" % (len(null_top), lattice["rank"]))
    lanes, content = _checked(lanes, content, lattice["voxels"])
    rank = lattice["rank"]
    voxels = lattice["voxels"]

    histogram = collections.Counter(lanes)
    collisions = sum(count * count for count in histogram.values())
    agreement = []
    for axis in range(rank):
        agreement.extend(_axis_agreement(lanes, lattice, axis))

    heights = [[] for _ in range(rank)]
    if voxels >= 2:
        for number in range(draws):
            for axis in range(rank):
                height = _null_height(lanes, lattice, content, (number * rank) + axis, axis)
                if height[0] != 0:
                    heights[axis].append(height)

    axes = []
    band = [(0, 0)] * (draws * rank)
    for axis in range(rank):
        pairs = lattice["pairs"][axis]
        lags = lattice["extent"][axis] // 2
        same = agreement[lattice["first"][axis]:lattice["first"][axis] + lags]
        # an axis's heights share its pairs as their denominator, and the numerators order them
        drawn = sorted(heights[axis])
        band[axis * draws:(axis * draws) + len(drawn)] = drawn
        bottom = top_edge = (0, 0)
        top = (0, pairs)
        if drawn:
            bottom, top_edge, top = drawn[0], drawn[-1], drawn[-1]
        if null_top is not None:
            bottom = top_edge = top = tuple(null_top[axis])
        chosen = _fundamental(same, lags, pairs, top)
        period = chosen[0] if chosen is not None else 0
        if chosen is None:
            chosen = _strongest(same, lags)
        if chosen is None:
            candidate, peak, margin = 0, (0, 0, 0, 0, 0), (0, 0)
        else:
            candidate, peak = chosen
            margin = (peak[4], pairs)
        axes.append(Axis(lattice["extent"][axis], period, candidate, lags, pairs, peak[0], peak[1],
                         peak[2], peak[3], margin, len(drawn), bottom, top_edge))
    return Reading(rank, voxels, collisions, draws, axes, agreement, band)


def draw(lanes, shape, number, content):
    """period_draw on the host: one draw's band height for each axis, or None where the C errors.

    Returns a list of (numerator, denominator) an axis, the numerator 0 where the shuffle reached
    no peak or the volume holds fewer than two voxels.
    """
    lattice = _lattice(shape)
    if lattice is None:
        return None
    lanes, content = _checked(lanes, content, lattice["voxels"])
    rank = lattice["rank"]
    heights = []
    for axis in range(rank):
        if lattice["voxels"] >= 2:
            heights.append(_null_height(lanes, lattice, content, (number * rank) + axis, axis))
        else:
            heights.append((0, lattice["pairs"][axis]))
    return heights
