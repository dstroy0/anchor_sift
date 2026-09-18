#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Reject outliers by the invariant the inliers share: the largest mutually-compatible set is the sift
# theorem on a graph.
#
#   Usage:  from sift.invariant_consensus import compatibility_graph, max_clique, k_core, consensus
#
# anchors.py rejects false candidates by a necessary condition over one pattern: a position holding the
# pattern satisfies every anchor. No true occurrence is lost and only false candidates survive. This
# is the same theorem over a SET of measurements. Two measurements that both come from the target agree
# on an invariant the target supplies -- a distance preserved under a rigid motion, a common offset, a
# shared period -- and two that do not come from it do not, except by accident. So the inliers are all
# mutually compatible, which is to say they form a CLIQUE in the graph whose edges are pairwise
# compatibility. Rejecting outliers is then finding that clique.
#
# The guarantee is one-directional, the family's signature. Inliers are mutually compatible by
# construction. They are always a clique and are never split apart by the rule; an outlier survives
# only when it is compatible with the whole clique by accident, which is a false candidate, never a lost
# true one. Correctness cannot turn on which clique-finder runs, only the count of surviving outliers
# can, exactly as with the anchor cascade and the Bloom filter.
#
# This is ROBIN's construction (Shi, Yang, Carlone, "ROBIN: a Graph-Theoretic Approach to Reject
# Outliers in Robust Estimation using Invariants", arXiv:2011.03659), reached from this tree's side:
# there it rejects outlier correspondences before a pose solve, here it is the anchor sift's
# necessary-condition-consensus with the pattern's positions generalized to any measurements and the
# anchor generalized to any pairwise invariant. Nothing is ported; the two are the same object.
#
# TWO ROUTES, AND WHY THEY BRACKET THE ANSWER
#
# The maximum clique is the tight answer and costs exponential time in the worst case. The maximum
# k-core -- the largest set where every member has at least k neighbors inside it -- is the cheap
# relaxation, found by peeling low-degree vertices, and it CONTAINS the maximum clique because a clique
# of size s is an (s-1)-core. So clique and k-core bracket the inliers: both retain every inlier
# (soundness), and the k-core admits more outliers (cost). That they agree on retaining the inliers is
# the check; where they differ is the cost the relaxation pays, the soundness-versus-cost split
# the whole family rests on.
#
# NOTHING IS BOUNDED HERE. Compatibility is an exact predicate the caller supplies; there is no
# tolerance in this file. `k` for the k-core is a declared input reported with the reading. No model is
# solved and nothing is trained: the invariant is checked pairwise, never estimated.


def compatibility_graph(count, compatible):
    """The graph over `count` measurements whose edges are pairwise compatibility.

    `compatible(i, j)` returns whether measurements i and j can both be inliers, checked without
    solving anything. Returns an adjacency map from each index to the set of indices compatible with it.
    """
    adjacency = {index: set() for index in range(count)}
    for first in range(count):
        for second in range(first + 1, count):
            if compatible(first, second):
                adjacency[first].add(second)
                adjacency[second].add(first)
    return adjacency


def max_clique(adjacency):
    """The largest set of mutually-compatible measurements, exact, by Bron-Kerbosch with a pivot.

    The inliers are a clique. The maximum clique contains them whenever no set of outliers is both
    larger and mutually compatible. Returns the clique as a set of indices.
    """
    best = set()

    def expand(chosen, candidates, excluded):
        nonlocal best
        if not candidates and not excluded:
            if len(chosen) > len(best):
                best = set(chosen)
            return
        reach = candidates | excluded
        pivot = max(reach, key=lambda vertex: len(adjacency[vertex] & candidates))
        for vertex in list(candidates - adjacency[pivot]):
            expand(
                chosen | {vertex},
                candidates & adjacency[vertex],
                excluded & adjacency[vertex],
            )
            candidates = candidates - {vertex}
            excluded = excluded | {vertex}

    expand(set(), set(adjacency), set())
    return best


def k_core(adjacency, k):
    """The largest set where every member has at least `k` neighbors inside it, by peeling.

     The cheap relaxation of the clique: a clique of size s is a (k)-core for every k up to s minus one,
    , a k-core with k one below the expected inlier count contains the inlier clique and, usually, some
     outliers besides. `k` is the declared input.
    """
    degree = {vertex: len(neighbors) for vertex, neighbors in adjacency.items()}
    alive = set(adjacency)
    removing = True
    while removing:
        removing = False
        for vertex in list(alive):
            if degree[vertex] < k:
                alive.discard(vertex)
                for neighbor in adjacency[vertex]:
                    if neighbor in alive:
                        degree[neighbor] -= 1
                removing = True
    return alive


def consensus(count, compatible, method="clique", k=None):
    """The inlier set: the maximum clique of the compatibility graph, or its k-core relaxation.

    `method` is "clique" for the tight answer or "kcore" for the cheap one; "kcore" needs `k`. Returns
    the retained indices; everything else is rejected as an outlier.
    """
    adjacency = compatibility_graph(count, compatible)
    if method == "kcore":
        if k is None:
            raise ValueError("kcore needs a declared k")
        return k_core(adjacency, k)
    return max_clique(adjacency)
