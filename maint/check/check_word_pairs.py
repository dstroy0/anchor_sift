"""Is the word-pair distribution anything but the light cone and the register chains?

Seen from above, the word-pair shadow looks weighted from left to right. It has to be: input word
w is outside the cone for exactly w rounds, so the volume of dead plateau in a row is set by which
word it is, and the weighting follows from the geometry with nothing left to explain.

The question worth asking is what remains once that is removed. Aligning every input word to its
own wavefront takes the cone out, and what is left is the eight output words, which are two chains
of four: a, b, c, d are a delayed nought to three rounds, and e, f, g, h are e delayed the same.

So the prediction is exact. At a fixed offset past the wavefront the eight output words should show
two groups of four, each group stepping with its delay, and no other structure.

    python tools/check_word_pairs.py
"""

import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "bench", "shadows.csv")

NAMES = "abcdefgh"


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no shadows.csv\n")
        return 1

    field = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] == "word":
                field.setdefault(int(row["a"]), {}).setdefault(int(row["b"]), {})[
                    int(row["round"])] = float(row["value"])

    print("Word-pair values aligned to each input word's own wavefront, averaged over the")
    print("sixteen input words. Word w enters at round w+1, so offset 0 is that round.\n")

    print("  %6s" % "out", end="")
    for k in range(6):
        print(" %13s" % ("+%d" % k), end="")
    print()
    print("  %6s" % ("-" * 6), end="")
    for k in range(6):
        print(" %13s" % ("-" * 13), end="")
    print()

    table = {}
    for s in range(8):
        row = []
        for k in range(6):
            each = []
            for w in range(16):
                at = w + 1 + k
                if w in field and s in field[w] and at in field[w][s]:
                    each.append(field[w][s][at])
            row.append(sum(each) / len(each) if each else 0.0)
        table[s] = row
        print("  %6s" % NAMES[s], end="")
        for value in row:
            print(" %13.0f" % value, end="")
        print()

    # The two chains, compared at the same delay. a and e are both new every round; b and f are
    # both one behind; and so on. A difference between the pair at equal delay is the asymmetry
    # of the two halves and nothing to do with the cone.
    print("\nThe two chains at equal delay, offset +1:\n")
    print("  %10s %14s %14s %10s" % ("delay", "a-chain", "e-chain", "ratio"))
    print("  %10s %14s %14s %10s" % ("-" * 10, "-" * 14, "-" * 14, "-" * 10))
    for delay in range(4):
        left = table[delay][1]
        right = table[delay + 4][1]
        ratio = (right / left) if left != 0 else 0.0
        print("  %10d %14.0f %14.0f %10.4f" % (delay, left, right, ratio))

    print("\n  Equal delay means equal position in the chain, so a ratio away from one is the")
    print("  asymmetry of the two halves rather than anything the cone imposes. At round one both")
    print("  a and e are T1 plus a constant, but different constants, so the difference is carry")
    print("  geometry.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
