"""Reads the compositional assay: does removing a sub-function remove its residues?

A radar with a library of known materials can say what an unknown return is made of. Here the
library does not have to be collected, because the variants can be built: the same residue spectrum
is taken from SHA-256 with one sub-function shorted out at a time, and what disappears says which
channel that sub-function was carrying.

The predictions were written into src/bench/bench_sac.cu before the run:

    without Sigma1     classes 6, 11 and 25 go
    without Sigma0     classes 2, 13 and 22 go, and they were weak already
    without addition   class 31 goes, because -1 mod 32 is the carry
    without Choose     a large change, Choose being in T1
    without Majority   little change, Majority being in T2

A removed rotation whose residue still stands would refute the reading of the spectrum outright,
and that comparison is the point of running it.

    python tools/radar_assay.py
"""

import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "bench", "assay.csv")

FIRST = 8
LAST = 16
GUARD = 1

DIAGONAL = 0
CARRY = 31
SIGMA0 = (2, 13, 22)
SIGMA1 = (6, 11, 25)

WATCHED = [DIAGONAL, 6, 11, 25, CARRY, 2, 13, 22]


def load():
    """Reads the dump, dropping any round that is not complete.

    The bench writes this file as it runs. A read taken while it is still working sees a
    partial final round. A round missing classes would make the CFAR background be computed over
    a different population than the others, and that is a silent error and not a loud one, so
    incomplete rounds are dropped and never padded.
    """
    data = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            try:
                variant = row["variant"]
                at = int(row["round"])
                data.setdefault(variant, {}).setdefault(at, {})[int(row["residue"])] = \
                    float(row["value"])
            except (TypeError, ValueError):
                continue

    for variant in list(data.keys()):
        for at in list(data[variant].keys()):
            if len(data[variant][at]) != 32:
                del data[variant][at]
        if not data[variant]:
            del data[variant]
    return data


def median(values):
    ordered = sorted(values)
    count = len(ordered)
    middle = count // 2
    if count % 2 == 1:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2.0


def os_cfar(values, cell):
    count = len(values)
    training = []
    for other in range(count):
        gap = min(abs(other - cell), count - abs(other - cell))
        if gap > GUARD:
            training.append(values[other])
    level = median(training)
    spread = median([abs(v - level) for v in training]) * 1.4826
    return level, spread


def signature(rounds_map):
    """Integrated CFAR statistic per residue class for one variant."""
    span = [r for r in range(FIRST, LAST + 1) if r in rounds_map]
    if len(span) < 4:
        return None
    per_class = {k: [] for k in range(32)}
    for at in span:
        values = [rounds_map[at][k] for k in range(32)]
        for cell in range(32):
            level, spread = os_cfar(values, cell)
            per_class[cell].append((values[cell] - level) / spread if spread > 0 else 0.0)
    gain = math.sqrt(float(len(span)))
    return {k: (sum(v) / len(v)) * gain for k, v in per_class.items()}


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no assay.csv - run: src/bench/bench_sac.exe 18 45 64 assay\n")
        return 1

    data = load()
    order = ["full", "no_majority", "no_choose", "no_sigma0", "no_sigma1", "no_addition",
             "no_schedule", "no_constant"]
    present = [v for v in order if v in data]

    signatures = {}
    for variant in present:
        found = signature(data[variant])
        if found is not None:
            signatures[variant] = found

    print("Integrated CFAR per residue class, rounds %d to %d.\n" % (FIRST, LAST))
    header = "%-8s" % "class"
    for variant in present:
        header += " %12s" % variant.replace("no_", "-")
    print(header)
    print("%-8s" % ("-" * 8) + "".join(" %12s" % ("-" * 12) for _ in present))

    labels = {DIAGONAL: "diagonal", CARRY: "carry"}
    for k in SIGMA1:
        labels[k] = "S1"
    for k in SIGMA0:
        labels[k] = "S0"

    for cell in WATCHED:
        line = "%-8s" % ("%d %s" % (cell, labels.get(cell, "")))
        for variant in present:
            line += " %12.2f" % signatures[variant][cell] if variant in signatures else " %12s" % "-"
        print(line)

    # -- the pre-registered checks ---------------------------------------------------------------
    print("\nPre-registered predictions, each stated before the run:\n")

    def strength(variant, group):
        if variant not in signatures:
            return None
        return sum(abs(signatures[variant][k]) for k in group) / float(len(group))

    checks = [
        ("no_sigma1", SIGMA1, "Sigma1's amounts 6, 11, 25 go"),
        ("no_sigma0", SIGMA0, "Sigma0's amounts 2, 13, 22 go"),
        ("no_addition", (CARRY,), "the carry at 31 goes"),
    ]

    print("  %-14s %-34s %10s %10s %8s" % ("variant", "prediction", "full", "variant", "kept"))
    print("  %-14s %-34s %10s %10s %8s"
          % ("-" * 14, "-" * 34, "-" * 10, "-" * 10, "-" * 8))
    for variant, group, says in checks:
        was = strength("full", group)
        now = strength(variant, group)
        if was is None or now is None:
            print("  %-14s %-34s %10s %10s %8s" % (variant, says, "-", "-", "not run"))
            continue
        kept = (now / was) if was > 0 else 0.0
        verdict = "GONE" if kept < 0.35 else ("reduced" if kept < 0.8 else "STANDS")
        print("  %-14s %-34s %10.2f %10.2f %8s" % (variant, says, was, now, verdict))

    print("\n  GONE confirms the class was that sub-function's channel. STANDS would mean the")
    print("  spectral reading attributes a residue to an operation that is not producing it,")
    print("  which refutes the interpretation rather than merely weakening it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
