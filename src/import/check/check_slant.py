"""Slant-stack: is there structure along diagonals in the input-bit field?

An earlier test averaged each input bit's value over the rounds and found nothing. That test cannot
see a diagonal and never could: if the structure lies at bit = offset + slope*round, averaging down
the round axis smears it over every bit position and washes it out by construction. It refuted a
horizontal-stripe hypothesis, which was not the one being made.

The right instrument sums along lines of every slope and not along one. That is a Radon or
Hough transform, and it is the same operation as the Doppler scan a few arms earlier - integrate
along a hypothesised trajectory and see which hypothesis adds coherently - carried out in
(bit, round) space instead of (residue, round).

Each round is standardized across its own 512 bits first. The very large shallow values and the
quiet deep ones contribute on the same scale and a stack is not simply reporting where the light
cone is.

    python tools/check_slant.py
"""

import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "bench", "shadows.csv")

BITS = 512
STEPS = 161
SLOWEST = -40.0
FASTEST = 40.0


def load():
    field = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] == "inbit":
                field.setdefault(int(row["round"]), {})[int(row["a"])] = float(row["value"])
    return field


# A cell outside the causal cone sits at 256*(n-1) exactly, which is 67,108,608 at n = 2^18. That
# is not a measurement, it is the absence of one, and it dwarfs everything real by three orders of
# magnitude. Left in, a horizontal line drawn through the bedrock outscores any genuine feature and
# the stack reports the plateau's edge and not the interior of the field.
PLATEAU = 6.0e7


def standardise(values):
    """Z-score within one round, over the live cells only.

    Dead cells are set to zero and never dropped, so every round keeps the same 512 positions and
    a line through the bedrock contributes nothing instead of contributing the most.
    """
    live = [v for v in values if abs(v) < PLATEAU]
    if len(live) < 8:
        return [0.0] * len(values)
    mean = sum(live) / len(live)
    var = sum((v - mean) ** 2 for v in live) / (len(live) - 1)
    spread = math.sqrt(var) if var > 0 else 1.0
    return [0.0 if abs(v) >= PLATEAU else ((v - mean) / spread) for v in values]


def stack(rounds, planes):
    """Largest slant-stack over slope and offset, with the slope and offset that carried it."""
    depth = len(rounds)
    gain = math.sqrt(float(depth))
    best = 0.0
    best_slope = 0.0
    best_offset = 0

    for step in range(STEPS):
        slope = SLOWEST + (((FASTEST - SLOWEST) * step) / (STEPS - 1))
        for offset in range(BITS):
            total = 0.0
            for index in range(depth):
                where = int(round(offset + (slope * index))) % BITS
                total += planes[index][where]
            value = (total / depth) * gain
            if abs(value) > abs(best):
                best = value
                best_slope = slope
                best_offset = offset
    return best, best_slope, best_offset


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no shadows.csv\n")
        return 1

    field = load()

    windows = [("all rounds", 1, 64), ("shallow", 1, 22), ("deep", 24, 64)]
    cells = float((STEPS * BITS))
    peak = math.sqrt(2.0 * math.log(cells))

    print("Slant-stack of the input-bit field. Each round standardised across its own 512 bits,")
    print("then summed along every line of slope %.0f to %.0f bits per round at every offset.\n"
          % (SLOWEST, FASTEST))
    print("A stack over %d rounds gains sqrt(rounds) on anything lying along that line." % 64)
    print("The largest of %.0f cells peaks near %.2f sigmas under a null whatever the data does.\n"
          % (cells, peak))

    print("  %-12s %8s %10s %10s %10s %10s"
          % ("window", "rounds", "loudest", "slope", "offset", "verdict"))
    print("  %-12s %8s %10s %10s %10s %10s"
          % ("-" * 12, "-" * 8, "-" * 10, "-" * 10, "-" * 10, "-" * 10))

    for label, first, last in windows:
        rounds = [r for r in range(first, last + 1) if r in field]
        if len(rounds) < 4:
            continue
        planes = [standardise([field[r][b] for b in range(BITS)]) for r in rounds]
        best, slope, offset = stack(rounds, planes)
        verdict = "STRUCTURE" if abs(best) > peak else "flat"
        print("  %-12s %8d %10.2f %10.2f %10d %10s"
              % (label, len(rounds), best, slope, offset, verdict))

    # -- named slopes, and how many distinct positions each actually visits -----------------------
    #
    # A line at slope s over R rounds advances s*R bits. When that is a multiple of 512 the line
    # closes and revisits the same few positions. A resonant slope samples far fewer independent
    # cells than a generic one and cannot be compared to it on a single null. Slope 32 over 64
    # rounds advances exactly 4*512 and touches only 16 distinct bits, precisely the slope
    # the schedule predicts - so the comparison has to be made with the coverage on the page.
    print("\nNamed slopes, best over all offsets, with the coverage each one actually gets.\n")
    print("  %8s %10s %12s %10s" % ("slope", "best", "distinct bits", "why"))
    print("  %8s %10s %12s %10s" % ("-" * 8, "-" * 10, "-" * 12, "-" * 10))

    rounds = [r for r in range(1, 23) if r in field]
    planes = [standardise([field[r][b] for b in range(BITS)]) for r in rounds]
    depth = len(rounds)
    gain = math.sqrt(float(depth))

    for slope, why in [(0.0, "flat"), (16.0, "half word"), (30.0, "measured"),
                       (32.0, "schedule"), (-32.0, "schedule"), (64.0, "two words")]:
        best = 0.0
        seen = set()
        for offset in range(BITS):
            total = 0.0
            for index in range(depth):
                where = int(round(offset + (slope * index))) % BITS
                if offset == 0:
                    seen.add(where)
                total += planes[index][where]
            value = (total / depth) * gain
            if abs(value) > abs(best):
                best = value
        print("  %8.1f %10.2f %12d %10s" % (slope, best, len(seen), why))

    print("\n  The message schedule predicts one slope and only one: 32 bits per round, because a")
    print("  word is 32 bits wide and each enters one round after the last. A peak there is the")
    print("  light cone. A peak at any other slope is not accounted for by anything known here.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
