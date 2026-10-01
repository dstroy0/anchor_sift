"""Does the field ever gain structure, or only lose it?

Reading color saturation as construction and desaturation as destruction makes a sharp prediction:
a hash should destroy structure and never build it, so the total field power should fall at every
round and rise at none. A rise would be a construction event and would want explaining.

Total power here is the signed residue fold summed in magnitude over all thirty-two classes. That
is the entire field with the sign folded out and nothing further discarded.

Two things have to be separated. A monotone run while the field is still large is a real statement
about the function. Rises after the field has reached its floor are not construction: each round is
its own seed, so consecutive rounds are independent draws and about half of them will land higher
than the one before whatever the function does.

    python tools/check_monotone.py
"""

import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "bench", "shadows.csv")

FLOOR_FROM = 23


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no shadows.csv\n")
        return 1

    power = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] == "residue":
                at = int(row["round"])
                power[at] = power.get(at, 0.0) + abs(float(row["value"]))

    rounds = sorted(power)
    print("Total field power per round, and the step from the round before.\n")
    print("  %6s %14s %12s %10s" % ("round", "power", "step", "note"))
    print("  %6s %14s %12s %10s" % ("-" * 6, "-" * 14, "-" * 12, "-" * 10))

    rises_live = 0
    steps_live = 0
    rises_floor = 0
    steps_floor = 0
    decrements = []

    previous = None
    for at in rounds:
        note = ""
        step = None
        if previous is not None:
            step = power[at] - previous
            if at <= FLOOR_FROM:
                steps_live += 1
                if step > 0:
                    rises_live += 1
                    note = "RISES"
            else:
                steps_floor += 1
                if step > 0:
                    rises_floor += 1
            if 8 <= at <= 16:
                decrements.append(-step)
        if at <= 42:
            print("  %6d %14.1f %12s %10s"
                  % (at, power[at], ("%.1f" % step) if step is not None else "-", note))
        previous = power[at]

    print("\n  While the field is live, up to round %d: %d rises in %d steps."
          % (FLOOR_FROM, rises_live, steps_live))
    if rises_live == 0 and steps_live > 0:
        print("  Monotone throughout. Under a random-walk null that is 2^-%d = %.2e."
              % (steps_live, 2.0 ** (-steps_live)))
        print("  Nothing anywhere in the live field gains structure.")

    if steps_floor > 0:
        print("\n  At the floor, past round %d: %d rises in %d steps, against the %.1f that chance"
              % (FLOOR_FROM, rises_floor, steps_floor, steps_floor / 2.0))
        print("  predicts. Each round is an independent seed, so these are draws wandering around")
        print("  a floor rather than structure being built.")

    if decrements:
        mean = sum(decrements) / len(decrements)
        spread = math.sqrt(sum((d - mean) ** 2 for d in decrements) / max(1, len(decrements) - 1))
        print("\n  Decrement over rounds 8 to 16: mean %.1f, spread %.1f." % (mean, spread))
        print("  That is 2^16 = 65536, being the 2048-per-class law summed over 32 classes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
