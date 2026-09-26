#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Whether a connected multigraph exists with a given list of vertex degrees, by three integer tests.
#
#   Usage:  from measure.graph_realizable import connected_multigraph
#
# A degree is how many edges meet a vertex. For a molecule the vertices are atoms and the degree is the
# valence, the bonds the atom makes, but nothing here knows that: it takes a list of integers and asks
# whether some connected multigraph carries exactly those degrees. Three conditions decide it, each an
# equality or a comparison on integers with no tolerance.
#
#   The degree sum is even. Every edge has two ends, and the ends total twice the edge count, an integer.
#   No vertex outweighs the rest: twice the largest degree is at most the sum, or the largest has more
#     edge ends than there are others to attach to.
#   There are enough edges to connect: the sum is at least twice the vertex count less one, the ends a
#     spanning tree needs.
#
# The three are necessary and together sufficient for a connected multigraph with no self-loops, the
# graph a molecule's bonds form. The reasons are graph words, not chemistry words; a caller that means
# atoms maps them to its own.

def connected_multigraph(degrees):
    """Whether a connected multigraph carries these vertex degrees, as (verdict, reason).

    `degrees` is a list of non-negative integers, one per vertex. A single vertex is a graph only where
    its degree is zero, since there is no other vertex to bond to.
    """
    vertices = len(degrees)
    if vertices == 0:
        return False, "no vertices"
    if vertices == 1:
        return degrees[0] == 0, "single vertex"
    total = sum(degrees)
    biggest = max(degrees)
    if total % 2 != 0:
        return False, "odd degree sum"
    if 2 * biggest > total:
        return False, "a vertex over-connected"
    if total < 2 * (vertices - 1):
        return False, "too few edges to connect"
    return True, "realizable"
