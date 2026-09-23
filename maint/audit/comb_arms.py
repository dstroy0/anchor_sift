"""Combs the survey arms: pooled depth, and the agreement between them.

Eight arms each survey the same nonce range under a different header. Pooling them tightens the
estimate as the square root of the total, which is what more of anything buys. The agreement
between them buys something else, and it is the reason to run arms rather than one longer arm:

    a bias in the construction pushes EVERY arm the same way
    a bias in one header pushes one arm and leaves the rest alone
    noise pushes each arm independently

So the sign of a position's deviation, read across arms, separates the three. Under the null each
arm's sign is a fair coin, so all eight agreeing has probability two in two hundred fifty six, and
over 256 positions chance alone delivers about two such positions. That is the bar, and it is
computed rather than chosen.

Every comparison is integer. A position set c times out of N deviates by 2c - N exactly, pooling is
addition, and testing against k standard errors is (sum of deviations) squared against k squared
times (sum of N). Nothing divides and nothing takes a root.

    python maint/audit/comb_arms.py
    python maint/audit/comb_arms.py --dir path/to/arms
"""

import argparse
import glob
import io
import json
import os

DEFAULT_DIR = os.path.join(os.path.expanduser("~"), ".claude", "jobs", "52b29cc3", "tmp")


def reach_of(deviation, samples):
    """Whole standard errors, by integer comparison only."""
    squared = deviation * deviation
    reach = 0
    while reach < 12 and squared >= (reach + 1) * (reach + 1) * samples:
        reach += 1
    return reach


def main():
    parser = argparse.ArgumentParser(description="Comb the survey arms.")
    parser.add_argument("--dir", default=DEFAULT_DIR)
    given = parser.parse_args()

    paths = sorted(glob.glob(os.path.join(given.dir, "survey_arm_*.json")))
    if len(paths) < 3:
        raise SystemExit("need at least three arms, found %d in %s" % (len(paths), given.dir))

    arms = []
    for path in paths:
        with io.open(path, encoding="utf-8") as handle:
            arms.append(json.load(handle))

    width = len(arms)
    depths = [int(a["nonces"]) for a in arms]
    total = sum(depths)

    # Arms need not share a depth. Each one carries its own N and its own exact zero at 2c - N, so
    # the deviations add and their variances add with them, and no calibration step exists to get
    # wrong. An earlier version printed arms[0]'s depth as though it were everyone's, which was
    # only ever a display fault because the arithmetic below never used it.
    if min(depths) == max(depths):
        print("  %d arms, %s nonces each, %s in total"
              % (width, format(min(depths), ","), format(total, ",")))
    else:
        print("  %d arms of mixed depth, %s to %s nonces, %s in total"
              % (width, format(min(depths), ","), format(max(depths), ","), format(total, ",")))
        print("  mixed depths pool exactly: every arm is referenced to 2c - N, so deviations add")
        print("  and variances add with them. Nothing is fitted and nothing is normalised.")
    print("  each arm is a DIFFERENT header, so the arms are independent observations of the")
    print("  construction rather than deeper observations of one instance")
    print()

    # Per position: each arm's deviation, the pooled deviation, and how many arms agree on sign.
    print("=" * 78)
    print("  1. POOLED DEPTH")
    print("=" * 78)
    pooled = []
    for position in range(256):
        deviations = [2 * int(a["bits"][position]) - int(a["nonces"]) for a in arms]
        pooled.append((position, sum(deviations), deviations))

    worst = max(pooled, key=lambda row: abs(row[1]))
    reach = reach_of(worst[1], total)
    squared_sum = sum(row[1] * row[1] for row in pooled)
    # Sum of squared z over 256 positions, exact rational scaled by a million.
    sum_z = (squared_sum * 1000000) // total
    print()
    print("    standard error per position falls as the square root of the pooled count")
    print("    loudest pooled position   %d, deviation %s, reaching %d whole sd"
          % (worst[0], format(worst[1], ","), reach))
    print("    sum of squared z          %d.%06d over 256, expectation 256"
          % (sum_z // 1000000, sum_z % 1000000))
    print()
    over = [row for row in pooled if reach_of(row[1], total) >= 4]
    print("    positions reaching 4 sd or more: %d" % len(over))
    print("    chance alone over 256 positions delivers about 0.02, so any is worth a look")

    print()
    print("=" * 78)
    print("  2. AGREEMENT  -  the thing depth cannot buy")
    print("=" * 78)
    print()
    unanimous = []
    counts = {}
    for position, total_dev, deviations in pooled:
        positives = sum(1 for d in deviations if d > 0)
        agree = max(positives, width - positives)
        counts[agree] = counts.get(agree, 0) + 1
        if agree == width:
            unanimous.append((position, total_dev, positives))

    print("    how many of the %d arms agreed on a position's sign:" % width)
    for agree in sorted(counts, reverse=True):
        bar = "#" * counts[agree]
        print("      %d of %d   %-40s %d positions" % (agree, width, bar, counts[agree]))

    # Under the null, all-agree has probability 2 / 2^width, and this is exact even where the arms
    # differ in depth: the SIGN of 2c - N is a fair coin at every N, so a shallow arm votes with
    # exactly the same weight as a deep one and the binomial does not care.
    #
    # The power is not depth-independent, and that is the part worth saying. A shallow arm is less
    # likely to show a REAL bias's sign, so mixing depths keeps the false-positive rate exact while
    # diluting sensitivity. Short arms are free to add and never mislead; they simply carry less.
    expected_unanimous = (256 * 2) / float(1 << width)
    print()
    print("    unanimous positions observed  %d" % len(unanimous))
    print("    expected by chance            %.2f   (256 * 2 / 2^%d)" % (expected_unanimous, width))
    print()
    if unanimous:
        print("      position   pooled deviation   sd   arms high")
        for position, total_dev, positives in sorted(unanimous, key=lambda r: -abs(r[1]))[:10]:
            print("      %8d   %16s   %2d   %d of %d"
                  % (position, format(total_dev, ","), reach_of(total_dev, total), positives, width))
    print()
    real = [u for u in unanimous if reach_of(u[1], total) >= 4]
    if not real:
        print("    No position is both unanimous across arms and past four standard errors pooled.")
        print("    A structural bias would have to be both, so there is none at this depth: the")
        print("    construction is flat to one part in %s." % format(int(total ** 0.5), ","))
    else:
        print("    %d position(s) are unanimous AND past four sd. Those are the only candidates" % len(real))
        print("    for structure rather than noise, and each wants its own arm to confirm.")

    print()
    print("=" * 78)
    print("  3. WHERE EACH ARM'S LOUDEST FELL")
    print("=" * 78)
    print()
    print("    A structural bias is loudest in the SAME position in every arm. Noise wanders.")
    print()
    print("      arm   loudest position   deviation      sd")
    seen = {}
    for index, arm in enumerate(arms):
        best, best_dev = 0, 0
        for position in range(256):
            deviation = 2 * int(arm["bits"][position]) - int(arm["nonces"])
            if abs(deviation) > abs(best_dev):
                best, best_dev = position, deviation
        seen[best] = seen.get(best, 0) + 1
        print("      %3d   %16d   %11s   %5d" % (index, best, format(best_dev, ","),
                                                 reach_of(best_dev, int(arm["nonces"]))))
    repeated = [p for p, n in seen.items() if n > 1]
    print()
    if repeated:
        print("    positions loudest in more than one arm: %s  <- worth chasing" % repeated)
    else:
        print("    No position was loudest in more than one arm. That is what noise does, and it")
        print("    is a stronger statement than any single arm could make however deep it ran.")

    print()
    print("=" * 78)
    print("  4. WHAT ANOTHER ARM BUYS")
    print("=" * 78)
    print()
    print("  An arm costs nothing to keep. The counters are 256 numbers and 33 bins whatever the")
    print("  depth, and the device buffers are allocated once, so memory is flat in the arm count.")
    print("  What the arms buy is not flat, and the two things they buy do not scale alike:")
    print()
    print("    pooled depth   improves as the square root of the arm count, which is what more of")
    print("                   anything buys and is why it saturates")
    print("    agreement      improves as two to the arm count, because every additional arm halves")
    print("                   the chance that a run of agreeing signs is coincidence")
    print()
    print("    arms   pooled se falls by   unanimous by chance, over 256 positions")
    for k in (4, 8, 16, 32, 64, 128):
        by = k ** 0.5
        expect = (256 * 2) / float(1 << k) if k < 200 else 0.0
        if expect >= 0.01:
            shown = "%.2f positions" % expect
        else:
            shown = "%.2e positions" % expect
        mark = "  <- you are here" if k == width else ""
        print("    %4d   %14.2fx      %s%s" % (k, by, shown, mark))
    print()
    print("  So depth answers how large a bias is, and arms answer whether it is a bias at all.")
    print("  Past about thirty two arms any unanimous position is a finding rather than a")
    print("  coincidence, and that is a threshold depth alone never reaches.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
