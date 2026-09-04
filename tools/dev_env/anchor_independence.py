#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure how far a cascade of anchors departs from the product of its anchor rates, and whether the
# departure follows the clustering of the anchors chosen. For Section 4.6 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/anchor_independence.py corpus.sym [more.sym ...]
#
# Section 4.6 sizes a cascade by multiplying the rate of each anchor, which is correct when the anchors
# refute independently, and Section 4.6.1 records the product underestimating the survivors by up to four
# orders of magnitude on structured data. Section 5.5 records independence failing wherever it is tested.
# Neither states a mechanism.
#
# Section 7.4.1 supplies a candidate. The rule selects an anchor because its symbol is rare, and the rare
# half of the distribution is the half whose occurrences gather into passages. So the selection rule
# chooses, by construction, the symbols least likely to be positioned independently, and a cascade of them
# should survive more often than the product predicts.
#
# The test holds everything else fixed. Needles are drawn from the corpus itself, anchors are chosen inside
# each needle by rarity as the library chooses them, and the same procedure runs against corpora with no
# structure at all, where the product has to be correct.

import os
import random
import statistics
import sys

NEEDLE = 24
ANCHORS = 3
TRIALS = 300
MIN_OCCURRENCES = 40


def burstiness(seats, symbol, counts, seed):
    """Gap variability of one symbol against a shuffle, below 1 where its occurrences gather."""
    positions = [index for index, value in enumerate(seats) if value == symbol]
    if len(positions) < MIN_OCCURRENCES:
        return None

    def spread(marks):
        gaps = [marks[step] - marks[step - 1] for step in range(1, len(marks))]
        mean = statistics.fmean(gaps)
        return None if mean <= 0.0 else statistics.pstdev(gaps) / mean

    live = spread(positions)
    shuffled = list(seats)
    random.Random(seed).shuffle(shuffled)
    moved = [index for index, value in enumerate(shuffled) if value == symbol]
    dead = spread(moved) if len(moved) >= 2 else None
    if (live is None) or (dead is None) or (live <= 0.0):
        return None
    return dead / live


def report(path):
    with open(path, "rb") as handle:
        seats = bytearray(handle.read())

    total = len(seats)
    counts = {}
    # Where each symbol sits, so a cascade is an intersection of short lists and never a scan of the
    # corpus. The anchors are the rare symbols, so these lists are exactly the short ones
    places = {}
    for index, value in enumerate(seats):
        counts[value] = counts.get(value, 0) + 1
        places.setdefault(value, []).append(index)
    for value in places:
        places[value] = set(places[value])

    # Burstiness depends on the symbol and not on the needle it was drawn into, so it is computed once
    cached = {}

    alphabet = sorted(places)
    rng = random.Random(0xA9C40)
    ratios = []
    passed = []
    clustering = []
    chained_errors = []

    for _ in range(TRIALS):
        # Where the needle comes from is the confound in every performance row this work has taken. A
        # needle cut from the corpus is guaranteed to occur in it, so every search confirms one true
        # occurrence at a cost of m reads and that floor is charged to both arms. The construction is
        # specified against a pattern that is unknown and of arbitrary width, and such a pattern is
        # almost never present, so drawing one at random over the same alphabet removes the floor
        start = rng.randrange(0, total - NEEDLE)
        if NEEDLE_SOURCE == "corpus":
            needle = seats[start:start + NEEDLE]
        else:
            needle = bytearray(rng.choice(alphabet) for _ in range(NEEDLE))

        # Two selection rules. The first is the library's: take the rarest symbols in the needle, which
        # needs the needle in hand and analyzed. The second needs nothing of the needle at all, spreading
        # the anchors as far apart as the needle length allows, since a rule that cannot examine what it
        # is looking for can still choose where to look
        if RULE == "rarest":
            offsets = sorted(range(NEEDLE), key=lambda index: counts[needle[index]])[:ANCHORS]
        elif RULE == "spread":
            step = (NEEDLE - 1) / float(ANCHORS - 1)
            offsets = [int(round(step * slot)) for slot in range(ANCHORS)]
        elif RULE == "jitter":
            # Even spacing is a comb, and a comb resonates with any period the domain happens to carry,
            # which puts the anchors back on correlated positions. One offset drawn inside each cell
            # keeps the spread and gives the set no period of its own
            cell = NEEDLE / float(ANCHORS)
            offsets = [min(NEEDLE - 1, int(cell * slot) + rng.randrange(max(1, int(cell))))
                       for slot in range(ANCHORS)]
        else:
            # Rarity is what makes an anchor refute, and separation is what keeps two of them from
            # refuting the same alignments. Taking the rarest symbol inside each cell asks for both
            # instead of trading one against the other
            cell = NEEDLE / float(ANCHORS)
            offsets = []
            for slot in range(ANCHORS):
                low = int(cell * slot)
                high = max(low + 1, min(NEEDLE, int(cell * (slot + 1))))
                offsets.append(min(range(low, high), key=lambda index: counts[needle[index]]))

        predicted = float(total - NEEDLE)
        for offset in offsets:
            predicted *= counts[needle[offset]] / total
        if predicted <= 0.0:
            continue

        # An alignment survives when every anchor matches, which is the intersection of each anchor's
        # own positions shifted back by where it sits in the needle. The count after the second anchor is
        # kept, since it is an observed joint frequency and standing in for one is what the product rule
        # is doing wrong
        survivors = None
        seen_pair = None
        for rank, offset in enumerate(offsets):
            shifted = {index - offset for index in places[needle[offset]]}
            survivors = shifted if survivors is None else (survivors & shifted)
            if rank == 1:
                seen_pair = len(survivors)
            if not survivors:
                break

        # Kac's lemma makes the expected distance between occurrences the reciprocal of their frequency,
        # so an observed count carries the joint that a product of marginals only assumes. Extending a
        # measured pair by the last anchor's own rate uses one of those and assumes only the other
        if (seen_pair is not None) and (ANCHORS >= 3):
            chained = seen_pair * (counts[needle[offsets[-1]]] / float(total))
            if chained > 0.0:
                chained_errors.append(max(len(survivors) - 1, 0) / chained)

        # The needle was cut from this corpus, so its own occurrence always survives and would count as
        # a departure from the prediction on its own. Only the survivors beyond it are evidence
        # Accuracy of the prediction and the size of what got through are different questions, and a
        # rule that predicts well because it filters badly is not an improvement. Both are kept
        ratios.append(max(len(survivors) - 1, 0) / predicted)
        passed.append(max(len(survivors) - 1, 0))
        for offset in offsets:
            symbol = needle[offset]
            if symbol not in cached:
                cached[symbol] = burstiness(seats, symbol, counts, 0x51F7)
            if cached[symbol] is not None:
                clustering.append(cached[symbol])

    if not ratios:
        print("  %-30s no usable needles" % os.path.basename(path))
        return

    # The median says what a typical search sees and says nothing about what a buffer has to hold. The
    # quantiles are where a sizing decision actually lives, and their spacing says which distribution
    # this is: even steps in the logarithm across the upper tail are a power law
    if QUANTILES:
        ordered = sorted(ratios)
        marks = []
        for share in (0.50, 0.75, 0.90, 0.95, 0.99):
            marks.append(ordered[min(len(ordered) - 1, int(share * len(ordered)))])
        print("  %-24s p50 %-10.2f p75 %-10.2f p90 %-10.2f p95 %-11.2f p99 %-12.2f max %.2f"
              % (os.path.basename(path)[:-4], marks[0], marks[1], marks[2], marks[3], marks[4],
                 max(ratios)))
        return

    # The ratio is heavy tailed: one needle that recurs many times carries a value thousands of times
    # the rest, and a mean over 25 trials is then mostly that one draw. The median says what a typical
    # search sees and the maximum is kept beside it so the tail stays visible
    print("  %-30s %-12.2f %-12.2f %-12.1f %-10.3f %-10.3f"
          % (os.path.basename(path)[:-4], statistics.median(ratios), max(ratios),
             statistics.fmean(passed),
             statistics.fmean(clustering) if clustering else float("nan"),
             statistics.median(chained_errors) if chained_errors else float("nan")))


def main():
    if len(sys.argv) < 2:
        print("usage: anchor_independence.py corpus.sym [more.sym ...]")
        return 1
    print("  %-30s %-10s %-10s %-10s" % ("corpus", "mean", "worst", "anchor clu"))
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            print("  no corpus at %s" % path)
            continue
        report(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
