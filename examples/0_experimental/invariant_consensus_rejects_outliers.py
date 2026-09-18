#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-005
#
# Reject outlier correspondences by an invariant the inliers share: the anchor sift's theorem on a
# compatibility graph, which is ROBIN.
#
#   Usage:  python examples/0_experimental/invariant_consensus_rejects_outliers.py
#
# This reads no corpus. It sits in 0_experimental: an algorithm shown working, a robust-estimation
# filter beside the signal ones. The medium is new -- a graph whose vertices are MEASUREMENTS and whose
# edges are pairwise compatibility -- and the technique is new to this tree, but the theorem is the one
# the anchor cascade already proves.
#
# The setup is ROBIN's (arXiv:2011.03659): two integer point sets are related by a rigid motion, and
# correspondences pair a point in one with a point in the other. The inliers are the true pairs; the
# outliers are wrong pairs. A rigid motion preserves distance. For two inlier correspondences the
# distance between the two source points equals the distance between the two target points. That is the
# invariant, and it is checked pairwise as an exact integer equality of squared distances, without ever
# solving for the motion. Two inliers always satisfy it. The inliers are all mutually compatible and
# form a CLIQUE; an outlier satisfies it with an inlier only by accident. Rejecting the outliers is
# finding the clique.
#
# The guarantee is one-directional, the family's signature: the inliers are a clique by construction and
# are never split out, and an outlier survives only by joining the clique by accident, a false candidate
# and never a lost true one -- the same shape as the anchor cascade losing no true occurrence and the
# Bloom filter never reporting a member absent.
#
# Two routes bracket the answer: the maximum clique is tight and the k-core is the cheap relaxation that
# contains it. Both retain every inlier and the k-core admits more outliers, which is the
# soundness-versus-cost split again. A broken compatibility that links everything is run beside them to
# show the rule moves cost, not correctness. The null is drawn by shuffling the correspondences, which
# destroys the rigidity so no large clique remains. The floor is stated: when outliers conspire into a
# consistent set LARGER than the inliers, the largest mutually-compatible set is theirs, and the
# necessary condition cannot tell a large accident from the truth.

import io
import os
import random
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from sift.invariant_consensus import compatibility_graph, max_clique, k_core  # noqa: E402

SEED = 0x2B12


def rot90(point):
    return (-point[1], point[0])


def rot270(point):
    return (point[1], -point[0])


def dist2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2


def correspondences(inliers, outliers, seed, conspirators=0):
    """Point-pairs: `inliers` true rigid pairs, `outliers` random pairs, `conspirators` a second rigid
    set under a DIFFERENT motion (internally consistent. It forms its own clique)."""
    rng = random.Random(seed)
    pairs = []
    truth = []
    for _ in range(inliers):
        p = (rng.randint(0, 40), rng.randint(0, 40))
        q = (rot90(p)[0] + 10, rot90(p)[1] + 5)          # one rigid motion
        pairs.append((p, q)); truth.append("inlier")
    for _ in range(conspirators):
        p = (rng.randint(0, 40), rng.randint(0, 40))
        q = (rot270(p)[0] - 7, rot270(p)[1] + 3)          # a different rigid motion, self-consistent
        pairs.append((p, q)); truth.append("conspirator")
    for _ in range(outliers):
        p = (rng.randint(0, 40), rng.randint(0, 40))
        q = (rng.randint(0, 60), rng.randint(0, 60))       # a value from nowhere
        pairs.append((p, q)); truth.append("outlier")
    order = list(range(len(pairs)))
    rng.shuffle(order)
    return [pairs[i] for i in order], [truth[i] for i in order]


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  invariant consensus: reject outlier correspondences by a distance invariant (ROBIN)\n")
    out.write("  seed=0x%X; invariant: squared distance preserved under a rigid motion, exact integers\n\n"
              % SEED)

    pairs, truth = correspondences(12, 8, SEED)
    n = len(pairs)
    inliers = {i for i in range(n) if truth[i] == "inlier"}

    def compatible(i, j):
        return dist2(pairs[i][0], pairs[j][0]) == dist2(pairs[i][1], pairs[j][1])

    clique = max_clique(compatibility_graph(n, compatible))
    core = k_core(compatibility_graph(n, compatible), k=len(inliers) - 1)

    out.write("  positive control: %d inliers, %d outliers\n" % (len(inliers), n - len(inliers)))
    out.write("    max clique: kept %d, all inliers retained: %s, outliers surviving: %d\n"
              % (len(clique), inliers <= clique, len(clique - inliers)))
    out.write("    k-core(%d): kept %d, all inliers retained: %s, contains the clique: %s\n"
              % (len(inliers) - 1, len(core), inliers <= core, clique <= core))

    # divergence probe: a compatibility that links everything keeps the inliers but admits every outlier
    def broken(i, j):
        return True
    broken_clique = max_clique(compatibility_graph(n, broken))
    out.write("    broken 'always compatible' route: kept %d (splits from the invariant clique: %s)\n\n"
              % (len(broken_clique), broken_clique != clique))

    # drawn null: shuffle the target points among the correspondences, destroying the rigidity
    rng = random.Random(SEED ^ 0x55)
    targets = [pair[1] for pair in pairs]
    rng.shuffle(targets)
    shuffled = [(pairs[i][0], targets[i]) for i in range(n)]

    def compatible_null(i, j):
        return dist2(shuffled[i][0], shuffled[j][0]) == dist2(shuffled[i][1], shuffled[j][1])

    null_clique = max_clique(compatibility_graph(n, compatible_null))
    out.write("  drawn null: with the correspondences shuffled the rigidity is gone\n")
    out.write("    live clique %d vs shuffled clique %d (a shuffle reaches only chance agreement)\n\n"
              % (len(clique), len(null_clique)))

    # floor: outliers that conspire into a consistent set larger than the inliers win the clique
    out.write("  floor: when outliers conspire into a consistent set larger than the inliers\n")
    out.write("  %-14s %-14s %-16s %s\n" % ("inliers", "conspirators", "clique size", "inliers retained"))
    for con in (4, 10, 14):
        cp, ct = correspondences(8, 0, SEED ^ (con << 4), conspirators=con)
        m = len(cp)
        inl = {i for i in range(m) if ct[i] == "inlier"}

        def compat(i, j, cp=cp):
            return dist2(cp[i][0], cp[j][0]) == dist2(cp[i][1], cp[j][1])

        cq = max_clique(compatibility_graph(m, compat))
        out.write("  %-14d %-14d %-16d %s\n" % (len(inl), con, len(cq), inl <= cq))

    out.write("\n  the inliers are a clique because a rigid motion preserves every distance. The\n")
    out.write("  necessary condition never splits them out; an outlier is kept only by an accidental\n")
    out.write("  distance match, a false survivor and not a lost inlier. the floor is a large accident:\n")
    out.write("  a conspiracy bigger than the truth is the one thing a necessary condition cannot refuse.\n")
    out.flush()
    ok = (inliers <= clique) and (len(clique - inliers) == 0) and (clique <= core) and (len(null_clique) < len(clique))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
