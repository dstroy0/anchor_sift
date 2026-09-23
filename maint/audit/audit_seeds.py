"""Lines a bench's runs up across seeds and reports how far each number moves.

Every number a bench prints sits at a fixed place in its output: a line index and a position within
that line. Running the same binary at several seeds and reading the same place each time gives a
sample of that statistic across draws, never yet looked at in this tree.

What is reported per bench is the number that moved the most, in units of its own mean, together
with the line it came from. A headline whose spread across seeds is comparable to its distance from
the null was never a measurement of the null's failure.

Usage: python maint/audit/audit_seeds.py <seed sweep directory>
"""

import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

NUMBER = re.compile(r"[-+]?\d+\.\d+(?:[eE][-+]?\d+)?|[-+]?\d+(?:[eE][-+]?\d+)?")

# Lines whose numbers describe the machine and not the measurement.
NOISE = re.compile(r"elapsed|MH/s|GH/s|\brate\b|seconds\b|per second|\bin \d+(\.\d+)? ?s\b|seed",
                   re.IGNORECASE)


def readings(path):
    """Returns {(line index, slot): value} for every number in the file."""
    found = {}
    for index, line in enumerate(path.read_text(errors="replace").splitlines()):
        if NOISE.search(line):
            continue
        for slot, match in enumerate(NUMBER.finditer(line)):
            try:
                found[(index, slot)] = (float(match.group()), line.strip())
            except ValueError:
                continue
    return found


def main():
    work = Path(sys.argv[1])
    runs = defaultdict(dict)
    for path in sorted(work.glob("*.out")):
        stem = path.name[: -len(".out")]
        bench, _, seed = stem.rpartition(".")
        runs[bench][seed] = readings(path)

    print("=" * 92)
    print("  Seed sweep: how far each printed number moves when only the draw changes")
    print("=" * 92)

    for bench in sorted(runs):
        seeds = sorted(runs[bench])
        if len(seeds) < 2:
            print("\n  %-18s only one run, nothing to compare" % bench)
            continue

        common = set(runs[bench][seeds[0]])
        for seed in seeds[1:]:
            common &= set(runs[bench][seed])

        moved = []
        for place in common:
            values = [runs[bench][seed][place][0] for seed in seeds]
            if max(values) == min(values):
                continue
            centre = statistics.fmean(values)
            spread = statistics.pstdev(values)
            scale = abs(centre) if abs(centre) > 1e-300 else max(abs(value) for value in values)
            moved.append((spread / scale if scale > 0 else 0.0, place, values,
                          runs[bench][seeds[0]][place][1]))

        moved.sort(reverse=True)
        stable = len(common) - len(moved)

        print()
        print("  %s" % bench)
        print("    %d numbers compared across %d seeds: %d identical, %d moved"
              % (len(common), len(seeds), stable, len(moved)))

        for relative, place, values, line in moved[:6]:
            print("      spread/mean %8.4f   %s" % (relative, line[:70]))
            print("        %s" % "  ".join("%.6g" % value for value in values))

    print()
    print("  A number identical across every seed is either exact or is not a function of the")
    print("  draw. A number whose spread is the same size as the effect it reports is a draw.")


main()
