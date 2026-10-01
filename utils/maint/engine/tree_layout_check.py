# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Reads TREE_LAYOUT_PLAN.tsv against the tree and names what a tree is missing.

    python utils/maint/engine/tree_layout_check.py            each tree's count, and every file out of place
    python utils/maint/engine/tree_layout_check.py --write    and every file still to write

A row holds where a file is now and where it goes. A row is met where its file is at either, and lost where it is
at neither. A copy is a file whose twin is already where it goes. A file the map holds no row for is outside the map. A row to write is met once its file is there.
Exit 1 where a row is lost or a file is outside the map.
"""
import collections
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
MAP = os.path.join(ROOT, "TREE_LAYOUT_PLAN.tsv")
# the trees the map covers, and the two files it brings in from utils/maint and utils/test
ROOTS = ("src", "utils/test", "evidence", "examples")
OUTSIDE = ("src/import/",)


def tracked():
    out = subprocess.run(["git", "ls-files", *ROOTS], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return {p for p in out.split("\n") if p and not p.startswith(OUTSIDE)}


def main():
    show_written = "--write" in sys.argv[1:]
    files = tracked()
    rows = []
    with open(MAP, encoding="utf-8") as table:
        next(table)
        for line in table:
            tree, now, goes_to, state, rule = line.rstrip("\n").split("\t")
            rows.append((tree, None if now == "-" else now, goes_to, state))
    held = set()
    counts = collections.defaultdict(collections.Counter)
    lost = []
    unwritten = []
    for tree, now, goes_to, state in rows:
        here = os.path.exists(os.path.join(ROOT, goes_to))
        if now is not None:
            held.add(now)
        held.add(goes_to)
        if state == "to write":
            counts[tree]["written" if here else "to write"] += 1
            if not here:
                unwritten.append(goes_to)
        elif state in ("copy", "differs") and os.path.exists(os.path.join(ROOT, now)):
            counts[tree]["copy"] += 1
        elif here and (now is None or now == goes_to):
            counts[tree]["in place"] += 1
        elif here:
            counts[tree]["moved"] += 1
        elif os.path.exists(os.path.join(ROOT, now)):
            counts[tree]["to move"] += 1
        else:
            counts[tree]["lost"] += 1
            lost.append(now)
    outside = sorted(files - held)
    for tree in sorted(counts):
        print("%-9s %s" % (tree, ", ".join("%s %d" % (k, counts[tree][k]) for k in
                                         ("in place", "moved", "to move", "copy", "written", "to write", "lost")
                                         if counts[tree][k])))
    for path in lost:
        print("lost: %s" % path)
    for path in outside:
        print("outside the map: %s" % path)
    if show_written:
        for path in unwritten:
            print("to write: %s" % path)
    return 1 if lost or outside else 0


if __name__ == "__main__":
    sys.exit(main())
