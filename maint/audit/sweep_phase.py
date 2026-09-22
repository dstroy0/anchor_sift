"""Compares the deficit ratios across window phases, against the control's own spread.

A phase is a different symbolisation of the same 256 bits, not a different read of the same one.
If SHA256d's output carries structure at an offset of one to seven bits, the aligned windows every
run in this tree has used split it across two symbols and see nothing, and one of the other seven
phases sees it.

The splitmix control is measured at every phase too. A pseudorandom function has no preferred
alignment, so its spread across phases is the floor: a difference on the real function smaller than
that difference on the control is not a difference.

Usage: python tools/sweep_phase.py <phase sweep directory>
"""

import re
import statistics
import sys
from pathlib import Path

SOURCE = re.compile(r"^  (Control three|SHA256d over)")
FAMILY = re.compile(r"windows (\d+), bins (\d+), mean count")
ROW = re.compile(r"^\s+(0|1/2|1|2|3|4|inf)\s+(\S+)\s+(\S+)\s+(\S+)\s")


def readings(path):
    """Returns {(source, bins, order): ratio} for one run."""
    found = {}
    source = None
    bins = None
    for line in path.read_text(errors="replace").splitlines():
        head = SOURCE.match(line)
        if head:
            source = "control" if head.group(1).startswith("Control") else "sha"
            continue
        family = FAMILY.search(line)
        if family:
            bins = int(family.group(2))
            continue
        row = ROW.match(line)
        if row and source and bins:
            try:
                found[(source, bins, row.group(1))] = float(row.group(4))
            except ValueError:
                continue
    return found


def main():
    work = Path(sys.argv[1])
    runs = {}
    for path in sorted(work.glob("phase*.out")):
        phase = int(re.search(r"phase(\d+)", path.name).group(1))
        runs[phase] = readings(path)

    if len(runs) < 2:
        print("need at least two phases")
        return

    phases = sorted(runs)
    common = set(runs[phases[0]])
    for phase in phases[1:]:
        common &= set(runs[phase])

    print("=" * 84)
    print("  Deficit ratio against phase, with the control as the floor")
    print("=" * 84)
    print()
    print("  %-8s %6s %6s %10s %10s %10s %12s" %
          ("source", "bins", "order", "lowest", "highest", "spread", "phase range"))
    print("  %-8s %6s %6s %10s %10s %10s %12s" %
          ("--------", "------", "------", "----------", "----------", "----------",
           "------------"))

    summary = {}
    for key in sorted(common, key=lambda k: (k[0], k[1], k[2])):
        values = [runs[phase][key] for phase in phases]
        source, bins, order = key
        spread = statistics.pstdev(values)
        summary.setdefault((source, bins), []).append(spread)
        print("  %-8s %6d %6s %10.5f %10.5f %10.6f %12.6f" %
              (source, bins, order, min(values), max(values), spread, max(values) - min(values)))

    print()
    for bins in sorted({key[1] for key in common}):
        control = summary.get(("control", bins))
        sha = summary.get(("sha", bins))
        if not control or not sha:
            continue
        print("  bins %d: mean spread across phases, control %.6f, SHA256d %.6f, ratio %.3f"
              % (bins, statistics.fmean(control), statistics.fmean(sha),
                 statistics.fmean(sha) / statistics.fmean(control)))

    print()
    print("  A ratio near one says SHA256d varies with phase exactly as much as a pseudorandom")
    print("  function does, which is to say not at all. A ratio well above one says one phase")
    print("  sees something the aligned read does not, and the phase column above says which.")


main()
