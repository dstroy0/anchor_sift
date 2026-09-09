#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Joining the two nearest groups over and over, and checking whether the tree represents anything.
#
#   Usage:  from measure.clustering import agglomerate, cophenetic_correlation, as_brackets
#
# Average linkage agglomerative clustering, which was written out twice in this tree under two names
# that did not know about each other.
#
# The check matters more than the tree. A tree can be built from any distance matrix whatsoever and
# will look like a result, so what says whether it represents the distances is comparing the height
# at which each pair first landed in one group against the distance actually measured between them.
# A low value means the tree is imposing structure the distances do not carry, and it should then be
# read as an ordering and not as a grouping.
#
# Average linkage is used here. Ward's pushes toward equal sized groups, and the question is
# usually whether unequal groups are there at all.
#
# Reading curves by eye is where this work has gone wrong before: a curve that looks like its
# neighbor is an impression, and the impression survives until something counts it.

import math
import statistics


def separation(first, second):
    """Straight line distance between two readings."""
    return math.sqrt(sum((one - two) ** 2 for one, two in zip(first, second)))


def correlation(first, second):
    """How closely two lists move together, as Pearson's coefficient."""
    left_middle = statistics.fmean(first)
    right_middle = statistics.fmean(second)
    together = sum((one - left_middle) * (two - right_middle) for one, two in zip(first, second))
    left_spread = math.sqrt(sum((one - left_middle) ** 2 for one in first))
    right_spread = math.sqrt(sum((two - right_middle) ** 2 for two in second))
    if (left_spread == 0.0) or (right_spread == 0.0):
        return float("nan")
    return together / (left_spread * right_spread)


def between_groups(left, right, apart):
    """Average distance from every member of one group to every member of the other."""
    return statistics.fmean(apart[(one, two)] for one in left for two in right)


def agglomerate(names, apart):
    """Join the two closest groups until one is left, keeping the height of every join.

    `apart` maps a pair of names to the distance between them. Returns the joins in the order they
    were made, each as (height, left group, right group). Those joins are the tree, and their
    heights are its scale.
    """
    groups = [(name,) for name in names]
    joins = []

    while len(groups) > 1:
        closest = None
        for first in range(len(groups)):
            for second in range(first + 1, len(groups)):
                height = between_groups(groups[first], groups[second], apart)
                if (closest is None) or (height < closest[0]):
                    closest = (height, first, second)

        height, first, second = closest
        joins.append((height, groups[first], groups[second]))
        joined = groups[first] + groups[second]
        groups = [groups[index] for index in range(len(groups))
                  if index not in (first, second)] + [joined]
    return joins


def cophenetic(joins):
    """For every pair, the height of the join that first put them in one group."""
    heights = {}
    for height, left, right in joins:
        for one in left:
            for two in right:
                heights[(one, two)] = height
                heights[(two, one)] = height
    return heights


def cophenetic_correlation(joins, names, apart):
    """How well the tree represents the distances it was built from.

    This is the check that separates a grouping from a picture. Low means the branching is imposed.
    """
    heights = cophenetic(joins)
    measured = []
    implied = []
    for first in range(len(names)):
        for second in range(first + 1, len(names)):
            pair = (names[first], names[second])
            measured.append(apart[pair])
            implied.append(heights[pair])
    return correlation(measured, implied)


def as_brackets(joins, names):
    """The tree as nested brackets, innermost join first."""
    label = {(name,): name for name in names}
    root = ""
    for _, left, right in joins:
        root = "(%s, %s)" % (label[left], label[right])
        label[left + right] = root
    return root


def standardized(readings, names):
    """Each column centered on its own average and divided by its own scatter.

    Needed whenever the columns being clustered are in unlike units, which is most of the time. One
    set here ran a vocabulary growth to ten percent against a benefit of nine hundredths, and
    clustering those as they stand lets the larger number decide everything.

    `readings` maps a name to a sequence of numbers, all the same length.
    """
    width = len(next(iter(readings.values())))
    columns = []
    for place in range(width):
        values = [readings[name][place] for name in names]
        middle = statistics.fmean(values)
        scatter = statistics.pstdev(values)
        columns.append((middle, scatter if scatter else 1.0))

    return {name: [(readings[name][place] - columns[place][0]) / columns[place][1]
                   for place in range(width)]
            for name in names}


def nearest_neighbors(names, apart):
    """For each name, the other it sits nearest. The mistakes are usually the informative part."""
    found = {}
    for name in names:
        found[name] = min((apart[(name, other)], other) for other in names if other != name)[1]
    return found
