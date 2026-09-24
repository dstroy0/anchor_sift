import re
import sys

BITS = range(5, 11)


def main():
    sample = None
    table = {}
    samples = []
    for line in open(sys.argv[1], encoding="utf-8"):
        head = re.match(r"^  (\S+)\s+\d+ frames, (\d+) windows", line)
        if head:
            sample = head.group(1)
            table = {}
            samples.append((sample, table))
            continue
        row = re.match(r"^\s+(\d+)((?:\s+\d+)+)\s*$", line)
        if row and sample is not None and not line.strip().startswith("bit"):
            table[int(row.group(1))] = [int(value) for value in row.group(2).split()]
    print("  %-16s %-40s %6s %8s %6s %6s %s" % ("sample", "bits 5-10 summed, per mille, by window", "peak", "vs med",
                                                   "first", "last", "direction"))
    for sample, table in samples:
        if not all(bit in table for bit in BITS):
            continue
        windows = len(table[5])
        sums = [sum(table[bit][window] for bit in BITS) for window in range(windows)]
        ordered = sorted(sums)
        median = ordered[len(ordered) // 2]
        peak = max(range(windows), key=lambda window: sums[window])
        direction = "toward order" if sums[-1] < sums[0] else ("toward the floor" if sums[-1] > sums[0] else "level")
        print("  %-16s %-40s %6d %7d%% %6d %6d %s" % (sample, " ".join("%d" % value for value in sums), peak,
                                                        (100 * sums[peak]) // median if median else 0, sums[0], sums[-1],
                                                        direction))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
