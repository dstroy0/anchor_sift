"""Reports which bench outputs differ between optimisation arms, ignoring wall clock.

A bench built at -O0 and at -O2 runs at different speeds, so any line reporting elapsed time or a
rate differs between arms for a reason that has nothing to do with arithmetic. Comparing whole
files marks almost every bench as compiler-dependent and the finding is worthless.

The question is whether a *measured* number moved. This drops timing lines and then compares, and
prints the surviving differences in full so that each one is judged on what it says and not on
a hash.

Usage: python maint/audit/audit_diff.py <audit directory>
"""

import re
import sys
from pathlib import Path

ARMS = ["O0", "O2", "NOFMA"]

# Lines carrying a speed and no result. Written to match the reporting vocabulary
# actually used in this tree, without any attempt to be generic.
TIMING = re.compile(
    r"elapsed|MH/s|GH/s|hashes per second|\brate\b|seconds\b|throughput|per second|wall"
    # "2097150 candidates in 23.9 s" is a stopwatch reading too, and the vocabulary for one is not
    # limited to the word elapsed.
    r"|\bin \d+(\.\d+)? ?s\b|\b\d+\.\d+ ?s\b",
    re.IGNORECASE,
)


def substantive(path):
    if not path.exists() or path.stat().st_size == 0:
        return None
    kept = []
    for line in path.read_text(errors="replace").splitlines():
        if TIMING.search(line):
            continue
        kept.append(line.rstrip())
    return kept


def main():
    work = Path(sys.argv[1])
    names = sorted({p.stem for p in (work / "O2").glob("*.out")})

    clean = []
    dirty = []
    pending = []

    for name in names:
        arms = {arm: substantive(work / arm / (name + ".out")) for arm in ARMS}
        if any(value is None for value in arms.values()):
            pending.append(name)
            continue

        base = arms["O0"]
        differences = []
        for arm in ARMS[1:]:
            other = arms[arm]
            if other == base:
                continue
            for number, (left, right) in enumerate(zip(base, other)):
                if left != right:
                    differences.append((arm, number + 1, left, right))
            if len(other) != len(base):
                differences.append((arm, 0, "%d lines" % len(base), "%d lines" % len(other)))

        if differences:
            dirty.append((name, differences))
        else:
            clean.append(name)

    print("=" * 78)
    print("  Same numbers at -O0, -O2 and -O2 -ffp-contract=off")
    print("=" * 78)
    for name in clean:
        print("  %s" % name)

    print()
    print("=" * 78)
    print("  Numbers that moved with the optimiser")
    print("=" * 78)
    if not dirty:
        print("  none")
    for name, differences in dirty:
        print()
        print("  %s  (%d differing lines)" % (name, len(differences)))
        for arm, number, left, right in differences[:12]:
            print("    line %-5s O0    : %s" % (number, left.strip()[:96]))
            print("    line %-5s %-5s : %s" % (number, arm, right.strip()[:96]))

    if pending:
        print()
        print("  still running, not yet judged: %s" % ", ".join(pending))

    print()
    print("  %d clean, %d moved, %d pending" % (len(clean), len(dirty), len(pending)))


main()
