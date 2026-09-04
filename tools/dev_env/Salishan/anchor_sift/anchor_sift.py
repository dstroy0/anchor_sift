#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The algorithm of docs/research/anchor-sift-method.md, and nothing else.
#
#   Usage:  from anchor_sift import squash, distance, self_distance, reading
#
# Sections 1 to 4, written once. There is no per-language term anywhere in this file and there is
# nothing to tune. Every question is asked by feeding it a different pair of corpora.
#
#   squash(texts)          section 1, text to a distribution over 2^16 cells
#   distance(P, Q)         section 2, total variation
#   self_distance(texts)   section 3, the corpus split at its midpoint against itself
#   reading(P, Q, ...)     section 3 applied, a distance with a verdict on whether it is readable
#
# Everything that went wrong before this file existed went wrong because the measure carried a term
# that depended on which corpus it was measuring. Charging an unseen byte pair by reference size
# made the smallest anchor win every comparison. Smoothing over the full square made the largest win
# instead. Normalizing each anchor by its own spread was a third version of the same mistake: an
# adjustment per language is a thumb on the scale, and the method has none.
#
# Total variation between normalized distributions has no such term. What it does have is a
# resolution, and section 3 is how that gets respected: a distance below D_self is not a small
# difference, it is no reading at all.

import math

BUCKETS = 65536


def pairs(text):
    """Adjacent byte pairs of a string as flat indices, k = 256*b_i + b_(i+1)."""
    data = text.encode("utf-8")
    return [(data[at] << 8) | data[at + 1] for at in range(len(data) - 1)]


def squash(texts):
    """Section 1. A body of text as its distribution over the 2^16 cells, with its pair count."""
    counts = {}
    total = 0
    for one in texts:
        for pair in pairs(one):
            counts[pair] = counts.get(pair, 0) + 1
            total += 1
    if not total:
        return {}, 0
    return {k: c / total for k, c in counts.items()}, total


def distance(first, second):
    """Section 2. Total variation, half the summed absolute difference. In [0, 1]."""
    run = 0.0
    for k in set(first) | set(second):
        run += abs(first.get(k, 0.0) - second.get(k, 0.0))
    return run / 2.0


def self_distance(texts):
    """Section 3. The corpus cut at its midpoint and measured against itself.

    The resolution of the estimator at this sample size. Nothing measured against this corpus is
    interpretable unless it is well clear of this number.
    """
    held = [one for one in texts if one]
    if len(held) < 2:
        return 1.0
    middle = len(held) // 2
    first, _ = squash(held[:middle])
    second, _ = squash(held[middle:])
    if not first or not second:
        return 1.0
    return distance(first, second)


def support(profile):
    """Section 4. How many cells the distribution occupies."""
    return sum(1 for one in profile.values() if one > 0)


def entropy(profile):
    """Section 4. H(P) in bits."""
    return -sum(one * math.log2(one) for one in profile.values() if one > 0)


def reading(against, resolution, margin=2.0):
    """Section 3 applied to a set of candidate distances.

    Takes [(distance, name), ...] and the resolution below which nothing is readable. Returns the
    nearest name, its distance, the gap to the runner-up, and whether that gap clears the
    resolution by the given factor.

    The verdict is the point. A gap of 0.015 between candidates when the estimator resolves 0.2 is
    not a close call, it is the absence of a measurement, and reporting the nearest name without
    saying so is how a ranking of noise gets published as a result.
    """
    ranked = sorted(against)
    if not ranked:
        return None, 1.0, 0.0, False
    if len(ranked) == 1:
        return ranked[0][1], ranked[0][0], 0.0, False
    gap = ranked[1][0] - ranked[0][0]
    return ranked[0][1], ranked[0][0], gap, gap > (margin * resolution)


def convergence(texts, steps=8):
    """How D_self falls as the corpus grows, which is what says where its distribution is going.

    A corpus of n members is a sample of a distribution, not the distribution. Section 3 measures
    the estimator's resolution at one n; this measures it across n, and the shape of that curve is
    what a limiting distribution looks like from inside a finite sample.

    It matters for deciding membership. A candidate that looks nothing like anything already in the
    corpus is not thereby excluded, because the corpus at this n does not yet cover its own support:
    support is still climbing with n. What can be asked is whether adding the candidate leaves the
    corpus on its curve or throws it off, and that question is answerable at any n.

    Returns [(members, pairs, D_self, support, entropy), ...] at increasing fractions of the whole.
    """
    held = [one for one in texts if one]
    if len(held) < 4:
        return []
    out = []
    for step in range(1, steps + 1):
        take = max(2, (len(held) * step) // steps)
        part = held[:take]
        profile, total = squash(part)
        if not total:
            continue
        out.append((take, total, self_distance(part), support(profile), entropy(profile)))
    return out


def blocked(texts, floor=6707):
    """A body of text cut into blocks each carrying at least floor bytes.

    The unit the method resolves at. Section 3 was measured on corpora cut to 6707 bytes, so that
    is the default here: a line is three orders of magnitude below it and cannot be asked anything.
    """
    held = []
    run = []
    size = 0
    for one in texts:
        run.append(one)
        size += len(one.encode("utf-8"))
        if size >= floor:
            held.append(run)
            run = []
            size = 0
    if run and (size >= floor // 2):
        held.append(run)
    return held
