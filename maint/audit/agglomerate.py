"""Agglomerative clustering on the survey arms: do output positions move together?

Every other test in this tree is univariate. Each asks whether one position is biased, or whether
the arms agree about one position, and all of them are blind to the same thing: two positions can
each be unbiased on their own and still move together across arms. That is co-variation, it is
structure, and no amount of per-position testing detects it.

The arms are what make it askable. With k arms each position carries a VECTOR of k deviations
rather than a single number, so positions can be correlated with each other and the correlation
matrix has something in it. A shared cause inside the compression would show as a cluster of
positions whose deviations track one another arm after arm, while each stays unremarkable alone.

METHOD

    distance      one minus the absolute correlation of two positions' deviation vectors, so
                  positions that track each other OR track each other inverted are near
    linkage       average, because single linkage chains through noise and complete linkage is
                  dominated by the one worst pair in a cluster
    statistic     the tightest cluster of at least four positions, measured by its mean internal
                  distance. That is what a real shared cause would produce.

THE NULL IS DRAWN, NOT DERIVED

Correlations of 256 vectors give 32640 pairs, and the largest of those has no usable closed form.
So the null permutes each position's arm order INDEPENDENTLY, which destroys co-variation while
holding every position's own distribution exactly fixed, and reclusters. Anything the real data
does that the permuted data cannot is co-variation and nothing else.

    python maint/audit/agglomerate.py
    python maint/audit/agglomerate.py --draws 200
"""

import argparse
import glob
import io
import json
import math
import os
import random

ARM_DIR = os.path.join(os.path.expanduser("~"), ".claude", "jobs", "52b29cc3", "tmp")
POSITIONS = 256
MIN_CLUSTER = 4


def load_arms(directory):
    """Per-position deviation vectors: rows are positions, columns are arms."""
    paths = sorted(glob.glob(os.path.join(directory, "survey_arm_*.json")),
                   key=lambda p: int(os.path.basename(p).split("_")[2].split(".")[0]))
    vectors = [[] for _ in range(POSITIONS)]
    for path in paths:
        with io.open(path, encoding="utf-8") as handle:
            arm = json.load(handle)
        samples = int(arm["nonces"])
        for position in range(POSITIONS):
            vectors[position].append(2 * int(arm["bits"][position]) - samples)
    return vectors, len(paths)


def standardise(vectors):
    """Centre and scale each position's vector so correlation is a dot product."""
    out = []
    for row in vectors:
        count = len(row)
        mean = sum(row) / float(count)
        centred = [v - mean for v in row]
        norm = math.sqrt(sum(v * v for v in centred))
        out.append([v / norm for v in centred] if norm > 0 else [0.0] * count)
    return out


def tightest_cluster(unit, verbose=False):
    """Average-linkage agglomeration; returns the tightest cluster of at least MIN_CLUSTER.

    Distance is one minus the absolute correlation, so a pair that tracks each other inverted is
    as near as one that tracks directly. Sign is not the question here; moving together is.
    """
    count = len(unit)
    distance = {}
    for left in range(count):
        for right in range(left + 1, count):
            dot = 0.0
            row_left, row_right = unit[left], unit[right]
            for index in range(len(row_left)):
                dot += row_left[index] * row_right[index]
            distance[(left, right)] = 1.0 - abs(dot)

    members = {index: [index] for index in range(count)}
    between = dict(distance)
    best_mean, best_group = 1.0, None

    while len(members) > 1:
        pair, gap = None, None
        for key, value in between.items():
            if gap is None or value < gap:
                pair, gap = key, value
        if pair is None:
            break
        left, right = pair
        joined = members[left] + members[right]

        if len(joined) >= MIN_CLUSTER:
            total, seen = 0.0, 0
            for a_index in range(len(joined)):
                for b_index in range(a_index + 1, len(joined)):
                    one, two = sorted((joined[a_index], joined[b_index]))
                    total += distance[(one, two)]
                    seen += 1
            mean_inside = total / seen
            if mean_inside < best_mean:
                best_mean, best_group = mean_inside, sorted(joined)

        # Average linkage: the new distance to any other cluster is the size-weighted mean.
        del members[left]
        del members[right]
        new_key = count + len(between)
        members[new_key] = joined
        rebuilt = {}
        for key, value in between.items():
            if left in key or right in key:
                continue
            rebuilt[key] = value
        for other in members:
            if other == new_key:
                continue
            total, seen = 0.0, 0
            for one in joined:
                for two in members[other]:
                    lo, hi = sorted((one, two))
                    total += distance[(lo, hi)]
                    seen += 1
            rebuilt[tuple(sorted((new_key, other)))] = total / seen
        between = rebuilt

    return best_mean, best_group


def main():
    parser = argparse.ArgumentParser(description="Cluster survey positions by co-variation.")
    parser.add_argument("--dir", default=ARM_DIR)
    parser.add_argument("--draws", type=int, default=60)
    given = parser.parse_args()

    vectors, arms = load_arms(given.dir)
    if arms < 12:
        raise SystemExit("need at least twelve arms for a correlation to mean anything, found %d"
                         % arms)
    print("  %d arms, %d positions, so each position carries a vector of %d"
          % (arms, POSITIONS, arms))
    print("  a correlation on %d points has a standard error near %.4f"
          % (arms, 1.0 / math.sqrt(arms)))
    print()

    unit = standardise(vectors)
    observed, group = tightest_cluster(unit)

    print("=" * 76)
    print("  THE TIGHTEST CLUSTER IN THE REAL ARMS")
    print("=" * 76)
    print()
    print("    mean internal distance   %.5f   (1 - |correlation|, so lower is tighter)" % observed)
    if group:
        print("    size                     %d positions" % len(group))
        print("    members                  %s%s"
              % (", ".join(str(v) for v in group[:14]), " ..." if len(group) > 14 else ""))
        words = {}
        for position in group:
            words[position // 32] = words.get(position // 32, 0) + 1
        print("    by state word            %s"
              % ", ".join("%s:%d" % ("abcdefgh"[w], n) for w, n in sorted(words.items())))
    print()

    print("=" * 76)
    print("  THE SAME STATISTIC WITH CO-VARIATION DESTROYED")
    print("=" * 76)
    print()
    print("  Each position's arm order is permuted independently, which holds every position's own")
    print("  distribution exactly and removes only the relationship between positions.")
    print()
    rng = random.Random(0xC1057)
    draws = []
    for _ in range(given.draws):
        shuffled = []
        for row in vectors:
            copy = list(row)
            rng.shuffle(copy)
            shuffled.append(copy)
        value, _ = tightest_cluster(standardise(shuffled))
        draws.append(value)
    draws.sort()

    below = sum(1 for v in draws if v <= observed)
    print("    permuted draws           %d" % len(draws))
    print("    their tightest, mean     %.5f" % (sum(draws) / len(draws)))
    print("    their 5th percentile     %.5f" % draws[max(0, int(0.05 * len(draws)) - 1)])
    print("    real data                %.5f" % observed)
    print("    draws at or below real   %d of %d   ->  p = %.4f"
          % (below, len(draws), below / float(len(draws))))
    print()
    if below <= 0.05 * len(draws):
        print("    -> positions co-vary. A cluster this tight cannot be made by permuting, so")
        print("       something inside the compression moves these positions together, and no")
        print("       per-position test in this tree could have seen it.")
    else:
        print("    -> no co-variation. The tightest real cluster is what independent positions")
        print("       produce, so the output bits are not merely unbiased one at a time, they are")
        print("       unrelated to each other. That is the stronger statement and it needed the")
        print("       arms to make it.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
