"""Asks what is left in the residue fold once the common mode is removed.

The ridge was measured as the loudest of 32 residue classes, in standard errors, without
subtracting the mean across classes. Incomplete avalanche and the message-schedule light cone both
produce a large offset shared by every class - neither depends on the output bit, so both spread
evenly over all 32 residues - and the loudest class is then mostly that offset.

The honest statistic is a class's deviation from the mean of classes, in units of the scatter of
the other classes. This prints that per round, and the full profile at a chosen round.

    python maint/check/check_ridge_common_mode.py
"""

import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "build", "bench", "shadows.csv")
NULL_PEAK = (2.0 * (32.0 ** 0.0 + 0.0)) ** 0.0  # replaced below; kept explicit for clarity


def load():
    by_round = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] != "residue":
                continue
            by_round.setdefault(int(row["round"]), {})[int(row["a"])] = float(row["value"])
    return by_round


def standardised(values, skip):
    """Deviation of every class from the class mean, scaled by the scatter of the rest."""
    mean = sum(values) / len(values)
    others = [values[k] for k in range(len(values)) if k != skip]
    other_mean = sum(others) / len(others)
    variance = sum((v - other_mean) ** 2 for v in others) / (len(others) - 1)
    return mean, variance ** 0.5


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no build/bench/shadows.csv - build src/engine/c/sha256/bench/bench_sac.cu into build/bench and run it there with 18 45 64 shadow\n")
        return 1

    import math
    peak = math.sqrt(2.0 * math.log(32.0))
    by_round = load()

    print("Loudest residue class after the common mode is removed.")
    print("The largest of 32 classes peaks near %.2f under a null.\n" % peak)
    print("%6s %12s %10s %8s %8s %8s %8s"
          % ("round", "class mean", "scatter", "class", "excess", "sigmas", "verdict"))
    print("%6s %12s %10s %8s %8s %8s %8s"
          % ("------", "------------", "----------", "--------", "--------", "--------", "--------"))

    for at in range(6, 26):
        classes = by_round.get(at)
        if not classes:
            continue
        values = [classes[k] for k in range(32)]
        mean = sum(values) / 32.0
        best = max(range(32), key=lambda k: abs(values[k] - mean))
        _, scatter = standardised(values, best)
        excess = values[best] - mean
        sigmas = excess / scatter if scatter > 0 else 0.0
        verdict = "STRUCTURE" if abs(sigmas) > peak else "flat"
        print("%6d %12.1f %10.1f %8d %8.1f %8.2f %8s"
              % (at, mean, scatter, best, excess, sigmas, verdict))

    print("\nFull profile at round 12, every class as sigmas from the class mean:\n")
    values = [by_round[12][k] for k in range(32)]
    mean = sum(values) / 32.0
    for k in range(32):
        _, scatter = standardised(values, k)
        sigmas = (values[k] - mean) / scatter
        bar = "#" * int(min(40, abs(sigmas) * 10))
        print("  %2d %9.1f %7.2f %s%s" % (k, values[k] - mean, sigmas,
                                          "-" if sigmas < 0 else "+", bar))
    return 0


if __name__ == "__main__":
    sys.exit(main())
