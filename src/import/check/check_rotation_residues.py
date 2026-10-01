"""Asks whether the positive residue classes are the round function's own rotation amounts.

SHA-256 moves bits across positions in exactly three ways: Sigma0 = ROTR2 ^ ROTR13 ^ ROTR22 on a,
Sigma1 = ROTR6 ^ ROTR11 ^ ROTR25 on e, and the carry chain, which moves them one position at a
time. If any of that survives into the dependency matrix it appears at those residues.

This ranks the classes at several depths after the common mode is removed, and says where the two
Sigma functions' amounts land in that ranking.

    python tools/check_rotation_residues.py
"""

import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "bench", "shadows.csv")

SIGMA0 = (2, 13, 22)
SIGMA1 = (6, 11, 25)


def load():
    by_round = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] != "residue":
                continue
            by_round.setdefault(int(row["round"]), {})[int(row["a"])] = float(row["value"])
    return by_round


def ranked(values):
    """Classes ordered by deviation from the class mean, most positive first."""
    mean = sum(values) / len(values)
    order = sorted(range(len(values)), key=lambda k: values[k] - mean, reverse=True)
    return order, mean


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no shadows.csv - run: src/bench/bench_sac.exe 18 45 64 shadow\n")
        return 1

    by_round = load()

    print("Top six residue classes by deviation from the class mean, most positive first.")
    print("Sigma0 rotates by %s, Sigma1 by %s.\n" % (SIGMA0, SIGMA1))
    print("%6s   %s" % ("round", "ranking"))
    print("%6s   %s" % ("------", "-" * 46))

    hits = 0
    looked = 0
    for at in range(6, 20):
        classes = by_round.get(at)
        if not classes:
            continue
        values = [classes[k] for k in range(32)]
        order, _ = ranked(values)
        top = order[:6]
        marked = []
        for k in top:
            if k in SIGMA1:
                marked.append("%d(S1)" % k)
            elif k in SIGMA0:
                marked.append("%d(S0)" % k)
            else:
                marked.append(str(k))
        print("%6d   %s" % (at, "  ".join(marked)))
        looked += 1
        if all(k in top for k in SIGMA1):
            hits += 1

    print("\nSigma1's three amounts are all in the top six at %d of %d depths." % (hits, looked))

    # How surprising is that for one depth? Choosing six of the thirty-one nonzero classes, the
    # number of choices containing three named ones against the number of choices at all.
    ways_with = math.comb(28, 3)
    ways_all = math.comb(31, 6)
    chance = ways_with / float(ways_all)
    print("For one depth by chance: %.5f, about one in %.0f." % (chance, 1.0 / chance))
    print("Doubling it because Sigma0 would have counted too: about one in %.0f." % (0.5 / chance))
    print("\nDepths are not independent - they are the same function measured deeper - so this is")
    print("one result repeated, not %d. The one-depth figure is the honest one." % looked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
