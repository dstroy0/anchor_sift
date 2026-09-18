# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fail when the two arm families stop naming the same instruction sets.
#
#     python maint/engine/check_arm_families.py
#
# The engine carries one operation per instruction set in two families: the steering scan in
# src/engine/c/engine/scan_<set>.c and the exact arithmetic in src/engine/c/no_rounding/arm_<set>.c.
# The CMake file states that a listing of the two directories names the same sets, because the
# portable arm is the reference in each and every other set exists to be faster at an answer portable
# already fixed. This check holds that invariant: it reads the two directories, takes the <set>
# suffix off every arm file, and exits non-zero when the two families disagree or when either family
# is missing its portable reference.
#
# It fails closed. A directory that does not resolve, or one that yields no arm at all, is a defect
# and exits non-zero. Every root it read is printed,
# a run that scanned the wrong tree says so instead of returning a number about a smaller tree than it
# names.

import sys
from pathlib import Path

# The repository root is two directories above this file, which sits at maint/engine/. Resolved from
# __file__ and not by walking up for a marker, since a marker the tree also produces can send the
# resolution off the top of the drive.
ROOT = Path(__file__).resolve().parents[2]
SCAN_DIR = ROOT / "src" / "engine" / "c" / "engine"
ARM_DIR = ROOT / "src" / "engine" / "c" / "no_rounding"

# The reference every other arm is graded against. A family without it has no baseline and is refused.
REFERENCE = "portable"


def sets_in(directory, prefix):
    """The instruction-set suffixes of prefix_<set>.c and prefix_<set>.cu in one directory.

    Returns a set of names. Portable, avx2, avx512, neon, sve and cuda come back whatever order
    the filesystem lists them in. A .cu counts the same as a .c: the device arm is an arm.
    """
    found = set()
    for path in directory.iterdir():
        name = path.name
        if not name.startswith(prefix + "_"):
            continue
        if path.suffix not in (".c", ".cu"):
            continue
        found.add(name[len(prefix) + 1 : -len(path.suffix)])
    return found


def main():
    print("  arm family homogeneity, engine/scan_<set> against no_rounding/arm_<set>")
    print("  roots scanned:")
    print("    " + str(SCAN_DIR))
    print("    " + str(ARM_DIR))

    problems = []

    if not SCAN_DIR.is_dir():
        problems.append("scan directory does not resolve: " + str(SCAN_DIR))
    if not ARM_DIR.is_dir():
        problems.append("arm directory does not resolve: " + str(ARM_DIR))
    if problems:
        for one in problems:
            print("  FAIL: " + one)
        return 1

    scan_sets = sets_in(SCAN_DIR, "scan")
    arm_sets = sets_in(ARM_DIR, "arm")

    print(
        "  scan family: " + ", ".join(sorted(scan_sets))
        if scan_sets
        else "  scan family: none"
    )
    print(
        "  arm family:  " + ", ".join(sorted(arm_sets))
        if arm_sets
        else "  arm family:  none"
    )

    # Fails closed. An empty family is a scan that read the wrong directory or a move that took the
    # arms with it, not a match.
    if not scan_sets:
        problems.append(
            "scan family is empty; no scan_<set> file under " + str(SCAN_DIR)
        )
    if not arm_sets:
        problems.append("arm family is empty; no arm_<set> file under " + str(ARM_DIR))

    if REFERENCE not in scan_sets:
        problems.append("scan family is missing its " + REFERENCE + " reference")
    if REFERENCE not in arm_sets:
        problems.append("arm family is missing its " + REFERENCE + " reference")

    scan_only = scan_sets - arm_sets
    arm_only = arm_sets - scan_sets
    for one in sorted(scan_only):
        problems.append(
            "scan_" + one + " has no matching arm_" + one + " in no_rounding/"
        )
    for one in sorted(arm_only):
        problems.append("arm_" + one + " has no matching scan_" + one + " in engine/")

    if problems:
        for one in problems:
            print("  FAIL: " + one)
        print("  " + str(len(problems)) + " problem(s)")
        return 1

    print("  OK: both families name the same " + str(len(scan_sets)) + " sets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
