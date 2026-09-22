"""Compares the residue structure of two sources class by class, common mode removed.

Toggling between two ablations in the viewer shows which residue classes each one keeps. The eye
does that by flicker; this does it by subtraction, on the same fields, with the offset every class
shares taken out first - because the raw fold is dominated by that offset and would show the two as
identical whatever they carry.

    python tools/check_two_sources.py [left] [right]
"""

import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "bench", "sources.csv")

FIRST = 8
LAST = 16

DIAGONAL = 0
CARRY = 31
SIGMA0 = (2, 13, 22)
SIGMA1 = (6, 11, 25)


def load():
    packed = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] != "residue":
                continue
            packed.setdefault(row["source"], {}).setdefault(int(row["round"]), {})[
                int(row["a"])] = float(row["value"])
    return packed


def profile(rounds_map):
    """Mean deviation from the class mean, per class, over the window."""
    out = [0.0] * 32
    count = 0
    for at in range(FIRST, LAST + 1):
        if at not in rounds_map:
            continue
        values = [rounds_map[at][k] for k in range(32)]
        mean = sum(values) / 32.0
        for k in range(32):
            out[k] += values[k] - mean
        count += 1
    if count:
        out = [v / count for v in out]
    return out, count


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no sources.csv\n")
        return 1

    left = sys.argv[1] if len(sys.argv) > 1 else "no_addition"
    right = sys.argv[2] if len(sys.argv) > 2 else "no_sigma1"

    packed = load()
    for name in (left, right):
        if name not in packed:
            sys.stderr.write("no such source: %s (have %s)\n"
                             % (name, ", ".join(sorted(packed))))
            return 1

    a, count = profile(packed[left])
    b, _ = profile(packed[right])

    scale = max(max(abs(v) for v in a), max(abs(v) for v in b))
    if scale <= 0:
        scale = 1.0

    labels = {DIAGONAL: "diagonal", CARRY: "carry"}
    for k in SIGMA1:
        labels[k] = "S1"
    for k in SIGMA0:
        labels[k] = "S0"

    print("Residue structure with the common mode removed, rounds %d to %d (%d rounds).\n"
          % (FIRST, LAST, count))
    print("  %5s %-9s %12s %12s %10s" % ("class", "is", left, right, "flips?"))
    print("  %5s %-9s %12s %12s %10s" % ("-" * 5, "-" * 9, "-" * 12, "-" * 12, "-" * 10))

    flipped = []
    for k in range(32):
        mark = ""
        if abs(a[k]) > 0.15 * scale and abs(b[k]) > 0.15 * scale and (a[k] * b[k]) < 0:
            mark = "OPPOSITE"
            flipped.append(k)
        elif abs(a[k]) > 0.3 * scale and abs(b[k]) < 0.1 * scale:
            mark = "lost"
        elif abs(b[k]) > 0.3 * scale and abs(a[k]) < 0.1 * scale:
            mark = "gained"
        if labels.get(k) or mark:
            print("  %5d %-9s %12.1f %12.1f %10s"
                  % (k, labels.get(k, ""), a[k], b[k], mark))

    # How alike are the two profiles overall? A correlation near -1 would mean the two ablations
    # keep opposite halves of the transport, as the mechanism predicts.
    mean_a = sum(a) / 32.0
    mean_b = sum(b) / 32.0
    top = sum((a[k] - mean_a) * (b[k] - mean_b) for k in range(32))
    low = math.sqrt(sum((v - mean_a) ** 2 for v in a) * sum((v - mean_b) ** 2 for v in b))
    print("\n  correlation between the two profiles: %.3f" % (top / low if low > 0 else 0.0))
    if flipped:
        print("  classes carrying opposite sign: %s" % ", ".join(str(k) for k in flipped))
    return 0


if __name__ == "__main__":
    sys.exit(main())
