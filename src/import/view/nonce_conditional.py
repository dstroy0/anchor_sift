#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""At step n, do nonces grouped by their first word's local entropy land in one topological region.

    python tools/view/nonce_conditional.py --check     the controls, each able to fail
    python tools/view/nonce_conditional.py             the conditional reading over one header

THE QUESTION

The torsion is high because the local information space is small: one word is thirty-two bits folded
deep, a small change swings the local shape hard. So group the nonces by a LOCAL property, the
entropy of their first state word at round n, and ask whether each group lands in its own region of
the topology. If it does, a cheap local reading of one word predicts where the whole shape sits, which
is a local handle on a global object.

WHAT IS MEASURED

For each nonce at round n: the local entropy of word 0, bucketed, is the grouping variable. The
topological region is the octant the set bits of words 1 through 7 centre on, computed WITHOUT word 0
so that a dependence is not word 0 sitting trivially in its own field but word 0's entropy predicting
where the OTHER words land. The mutual information between the group and the region says how much the
one tells about the other, in bits.

THE NULL

Mutual information over finite samples is positive by chance, more so with more buckets, so the floor
is drawn, not derived. Shuffle the region labels against the groups many times and read the mutual
information each shuffle gives. Real dependence clears that band; a value inside it is the estimator's
own bias and not structure.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402
import build_sha_sphere_view  # noqa: E402
import nonce_local  # noqa: E402
import nonce_support  # noqa: E402

MASK = 0xFFFFFFFF
ROUNDS = 64
WIDTH = 256


def word_local_entropy_bucket(word, buckets):
    """Bucket a 32-bit word by its set-bit count, its local structure.

    Popcount and not the binary entropy of the fraction: entropy is symmetric, a word of weight 10
    and one of weight 22 fall together, and once a word is well mixed every nonce sits at weight 16 and
    entropy near one, which collapses the grouping to a single bucket at any round past the mixing. The
    count keeps its spread at every round and is the local structure the entropy is a function of.
    """
    population = bin(word & MASK).count("1")
    index = (population * buckets) // 33
    return index if index < buckets else buckets - 1


def region_of_tail(words, vectors):
    """The octant the set bits of words 1 through 7 centre on, ignoring word 0.

    The centroid of the lit directions, read as its octant, is where the tail of the state sits on the
    sphere. Word 0 is left out a dependence on it is a real cross-word one and not word 0 in its own
    field.
    """
    x = y = z = 0.0
    lit = 0
    for slot in range(1, 8):
        word = words[slot]
        for shift in range(31, -1, -1):
            if (word >> shift) & 1:
                index = (slot * 32) + (31 - shift)
                x += vectors[index][0]
                y += vectors[index][1]
                z += vectors[index][2]
                lit += 1
    if lit == 0:
        return 0
    return ((1 if x < 0 else 0) << 2) | ((1 if y < 0 else 0) << 1) | (1 if z < 0 else 0)


def mutual_information(pairs, groups, regions):
    """The mutual information in bits between the group label and the region label over the pairs."""
    joint = {}
    group_count = {}
    region_count = {}
    for group, region in pairs:
        joint[(group, region)] = joint.get((group, region), 0) + 1
        group_count[group] = group_count.get(group, 0) + 1
        region_count[region] = region_count.get(region, 0) + 1
    total = float(len(pairs))
    information = 0.0
    for (group, region), count in joint.items():
        joint_p = count / total
        marginal = (group_count[group] / total) * (region_count[region] / total)
        if joint_p > 0.0 and marginal > 0.0:
            information += joint_p * math.log2(joint_p / marginal)
    return information


def drawn_band(pairs, draws, seed):
    """Mutual information under shuffled region labels: the floor the estimator's bias sits at."""
    groups = [group for group, _ in pairs]
    regions = [region for _, region in pairs]
    generator = random.Random(seed)
    scores = []
    for _ in range(draws):
        shuffled = regions[:]
        generator.shuffle(shuffled)
        scores.append(mutual_information(list(zip(groups, shuffled)), None, None))
    scores.sort()
    count = len(scores)
    return (scores[int(0.025 * (count - 1))], scores[int(0.5 * (count - 1))],
            scores[int(0.975 * (count - 1))])


def sample_pairs(block, nonces, round_index, buckets, vectors):
    """For each nonce, its word-0 entropy bucket at round n and the octant its tail centres on."""
    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, 0))
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
    pairs = []
    for nonce in nonces:
        _, second_block = build_bend_view.header_words(build_bend_view.header_bytes(block, nonce))
        state = build_bend_view.round_outputs(second_block, midstate)[round_index]
        group = word_local_entropy_bucket(state[0], buckets)
        region = region_of_tail(state, vectors)
        pairs.append((group, region))
    return pairs


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    # A PLANTED MAP IS SEEN. Where the region is a fixed function of the group, the mutual information
    # is the group entropy and far over the shuffled band. Where the region is independent, it sits in
    # the band. Both against the same estimator, so the band is calibrated to it.
    generator = random.Random(4)
    planted = [(generator.randrange(4), None) for _ in range(4000)]
    planted = [(group, group) for group, _ in planted]
    independent = [(generator.randrange(4), generator.randrange(8)) for _ in range(4000)]
    planted_mi = mutual_information(planted, None, None)
    independent_mi = mutual_information(independent, None, None)
    planted_band = drawn_band(planted, 400, 7)
    say("  planted map mutual information %.4f, shuffled band up to %.4f: %s"
        % (planted_mi, planted_band[2], "over" if planted_mi > planted_band[2] else "IN"))
    say("  independent mutual information %.4f, well below the planted %.4f: %s"
        % (independent_mi, planted_mi, "yes" if independent_mi < planted_mi / 10.0 else "NO"))
    if planted_mi <= planted_band[2]:
        say("    FAIL a planted map did not clear the shuffled band")
        failed += 1
    # Independent labels carry only the estimator's bias, which is the shuffled band's own scale, so
    # the honest control is that they sit far under a real map rather than exactly inside one draw of
    # the band, which a single independent sample clears 2.5 per cent of the time by construction.
    if independent_mi >= planted_mi / 10.0:
        say("    FAIL independent labels read as a real dependence")
        failed += 1

    # THE FEATURES ARE READABLE ON REAL STATES. Build a few and confirm both features take more than
    # one value, or the mutual information is zero for a trivial reason.
    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        say("  no chain corpus found, so the state controls cannot run")
        say("")
        say("%d check(s) failed" % failed)
        sys.stdout.write("\n".join(lines) + "\n")
        return failed
    block = blocks[len(blocks) // 2]
    vectors = nonce_local.unit_vectors()
    stream = build_sha_sphere_view.draw(1)
    pairs = sample_pairs(block, [next(stream) & MASK for _ in range(400)], 5, 6, vectors)
    groups = len(set(group for group, _ in pairs))
    regions = len(set(region for _, region in pairs))
    say("  over 400 nonces at round 6: %d distinct word-0 buckets, %d distinct tail regions"
        % (groups, regions))
    if groups < 2 or regions < 2:
        say("    FAIL a feature took one value, so there is nothing to relate")
        failed += 1

    say("")
    say("%d check(s) failed" % failed)
    sys.stdout.write("\n".join(lines) + "\n")
    return failed


def main(argv):
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 0
    if "--check" in argv:
        return 1 if _check() else 0

    buckets = 6
    count = 8000
    if "--buckets" in argv:
        buckets = int(argv[argv.index("--buckets") + 1])
    if "--nonces" in argv:
        count = int(argv[argv.index("--nonces") + 1])

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under tools/chain\n")
        return 2
    block = blocks[len(blocks) // 2]
    vectors = nonce_local.unit_vectors()
    stream = build_sha_sphere_view.draw(1)
    nonces = [next(stream) & MASK for _ in range(count)]

    print("  header height %d, %d nonces, word-0 local entropy into %d buckets, tail octant the region"
          % (block["height"], count, buckets))
    print("  %6s %16s %22s %10s" % ("round", "mutual info bits", "shuffled band", "verdict"))
    for round_index in (4, 5, 6, 7, 11, 15, 31, 63):
        pairs = sample_pairs(block, nonces, round_index, buckets, vectors)
        live = mutual_information(pairs, None, None)
        band = drawn_band(pairs, 200, 2000 + round_index)
        verdict = "OVER" if live > band[2] else "in band"
        print("  %6d %16.5f %10.5f to %.5f %10s"
              % (round_index + 1, live, band[0], band[2], verdict))
    print("")
    print("  mutual information OVER the shuffled band is the first word's local entropy predicting")
    print("  where the tail lands, a local handle on the shape. In band, the two are independent and")
    print("  the group tells nothing about the region beyond the estimator's own bias.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
