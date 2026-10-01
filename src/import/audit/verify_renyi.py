"""Recomputes every prediction bench_renyi printed, independently of the binary that printed it.

Reading disassembly proves the hash calls happen and the counters are real memory. It does not
prove a folded constant was folded correctly. A compiler is free to evaluate any expression whose
inputs it knows at compile time, and the value it emits is then indistinguishable from a measured
one by inspection alone.

So this reimplements the predictions in another language against another libm and compares. Where
the two agree to the last printed digit the constant in the binary is the constant that was meant.
Where they disagree the binary is wrong, or this is, and either way the number stops being quotable
until that is settled.

Usage: python tools/verify_renyi.py <bench output file>
"""

import math
import re
import sys
from pathlib import Path

LN2 = math.log(2.0)


def linear_deficit(bins, total, alpha):
    """The random-function prediction where bins are full: alpha * var(e) / (2 ln 2)."""
    variance = (bins - 1.0) / total
    return alpha * variance / (2.0 * LN2)


def linear_support(bins, total):
    """Expected empty bins are r exp(-m), read as a deficit at order zero."""
    empty = bins * math.exp(-total / bins)
    return -math.log2(1.0 - (empty / bins))


def linear_peak(bins, total):
    """The largest of r near-normal deviations, to first order with its first correction."""
    variance = (bins - 1.0) / total
    logs = 2.0 * math.log(bins)
    peak = math.sqrt(variance) * (
        math.sqrt(logs) - ((math.log(math.log(bins)) + math.log(4.0 * math.pi)) / (2.0 * math.sqrt(logs)))
    )
    return math.log2(1.0 + peak)


def poisson_deficit(bins, total, alpha, kind):
    """The prediction where the mean count is near one and the counts go Poisson."""
    mean = total / bins
    weight = math.exp(-mean)
    moment = 0.0
    occupied = 0.0
    above = 1.0
    peak = 0

    for count in range(0, 256):
        if count > 0:
            weight *= mean / count
            occupied += weight
        if above * bins >= 1.0:
            peak = count
        above -= weight
        if kind == "peak" or count == 0:
            continue
        if kind == "shannon":
            moment += weight * count * math.log(count)
        elif kind == "power":
            moment += weight * (count ** alpha)

    if kind == "support":
        return -math.log(occupied) / LN2
    if kind == "peak":
        return math.log2(peak / mean)
    if kind == "shannon":
        # E[c log2 c] / mean, less log2 of the mean. The second term vanishes at mean one, the
        # full-domain case, and a version without it therefore agrees exactly where it is used
        # and nowhere else.
        return (moment / mean / LN2) - math.log2(mean)
    return math.log(moment / (mean ** alpha)) / LN2 / (alpha - 1.0)


ORDERS = [("0", 0.0), ("1/2", 0.5), ("1", 1.0), ("2", 2.0), ("3", 3.0), ("4", 4.0), ("inf", 0.0)]

FAMILY = re.compile(r"windows (\d+), bins (\d+), mean count")
# The wide window prints no "windows N, bins M" line of its own, so without this the rows below it
# would be checked against whatever family came last. That is a defect in this checker and not in
# the bench, and it produced twelve false mismatches before it was noticed.
WIDE = re.compile(r"32-bit window at digest bytes")
ROW = re.compile(r"^\s+(0|1/2|1|2|3|4|inf)\s+(\S+)\s+(\S+)\s+")
# A preimage-count table starts its rows with a small integer too, so matching rows by shape alone
# reads counts and ratios as though they were entropies. Only rows under a Renyi header count.
TABLE_HEAD = re.compile(r"^\s+order\s")


def main():
    text = Path(sys.argv[1]).read_text(errors="replace")

    bins = None
    windows = None
    total = None
    domain_match = re.search(r"Domain: 2\^(\d+) nonces", text)
    if domain_match:
        total = float(2 ** int(domain_match.group(1)))

    checked = 0
    failed = 0
    in_table = False

    for line in text.splitlines():
        family = FAMILY.search(line)
        if family:
            windows = int(family.group(1))
            bins = float(family.group(2))
            continue
        if WIDE.search(line):
            windows = 1
            bins = float(2 ** 32)
            in_table = False
            continue
        if TABLE_HEAD.match(line):
            in_table = True
            continue
        if not line.strip():
            in_table = False
            continue
        if not in_table:
            continue
        if bins is None or total is None:
            continue

        row = ROW.match(line)
        if not row:
            continue
        tag = row.group(1)
        try:
            predicted = float(row.group(3))
        except ValueError:
            continue

        alpha = dict(ORDERS)[tag]
        mean = total / bins
        sparse = mean < 8.0

        if sparse:
            kind = {"0": "support", "inf": "peak", "1": "shannon"}.get(tag, "power")
            mine = poisson_deficit(bins, total, alpha, kind)
        elif tag == "0":
            mine = linear_support(bins, total)
        elif tag == "inf":
            mine = linear_peak(bins, total)
        else:
            mine = linear_deficit(bins, total, alpha)

        # Compared at the precision the binary printed, which is nine significant figures.
        agree = (mine == predicted) or (
            predicted != 0.0 and abs(mine - predicted) <= abs(predicted) * 1e-8
        )
        checked += 1
        if not agree:
            failed += 1
            print(
                "MISMATCH bins=%g order=%-3s binary=%.12g  independent=%.12g  relative %.3g"
                % (bins, tag, predicted, mine, abs(mine - predicted) / max(abs(predicted), 1e-300))
            )

    print()
    print("%d predictions checked, %d disagree" % (checked, failed))
    if failed == 0:
        print("every constant the binary printed was recomputed here and matched.")


main()
