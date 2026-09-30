#!/usr/bin/env python3
"""Report which prose findings a research paper change added or removed, from two runs of the prose gate.

    python tools/research_paper/prose_delta.py before.txt after.txt

The prose gate is anchor_sift's maint/prose/docs_check.py. A research paper carries findings older than any one change,
and a change is therefore graded on the difference: run the gate over copies of the changed files at the base commit
and in the working tree, save both outputs, and hand them here. Run the gate with PYTHONIOENCODING=utf-8:
under a cp1252 console it can crash on a finding's text and exit 1, which reads like a breaking finding.
Findings are matched on file, tier and message and not on line number, because an edit above a finding
moves its line without changing it.

IT FAILS CLOSED. Exit 3 when either output holds no finding line and no "file(s) checked" summary, since an
output that is not a gate run reads the same as a clean one. Exit 1 when the change added a finding. Exit 0
when it added none. Exit 2 on a usage error.
"""

import collections
import re
import sys

FINDING = re.compile(r"^\s*(prose|breaking)\s+(.*):(\d+):\s*(.*)$")
SUMMARY = re.compile(r"(\d+) file\(s\) checked, (\d+) breaking, (\d+) prose")


def read(path):
    counted = collections.Counter()
    lines_of = collections.defaultdict(list)
    summary = None
    roots = []
    reading_roots = False
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            # The gate prints the roots it scanned before any finding, one per indented line. A file is keyed
            # relative to its root. Two copies of one tree placed under different directories compare as
            # the same file.
            if "roots configured:" in line:
                reading_roots = True
                continue
            match = FINDING.match(line)
            if reading_roots and not match and line.startswith("    "):
                roots.append(line.strip().replace("\\", "/").rstrip("/") + "/")
                continue
            reading_roots = False
            if match:
                file_path = match.group(2).replace("\\", "/")
                root = next((one for one in roots if file_path.startswith(one)), "")
                key = (match.group(1), file_path[len(root):], match.group(4))
                counted[key] += 1
                lines_of[key].append(int(match.group(3)))
                continue
            found = SUMMARY.search(line)
            if found:
                summary = found.group(0)
    return counted, lines_of, summary


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    before, before_lines, before_summary = read(sys.argv[1])
    after, after_lines, after_summary = read(sys.argv[2])
    print("before: %s" % before_summary)
    print("after:  %s" % after_summary)
    if before_summary is None or after_summary is None:
        print("prose_delta: an input is not a docs_check.py run. Refusing to compare.")
        return 3
    added = after - before
    removed = before - after
    for key, count in sorted(added.items()):
        print("ADDED   x%d %s %s: %s (after, lines %s)" % (count, key[0], key[1], key[2], after_lines[key]))
    for key, count in sorted(removed.items()):
        print("REMOVED x%d %s %s: %s (before, lines %s)" % (count, key[0], key[1], key[2], before_lines[key]))
    print("added %d, removed %d" % (sum(added.values()), sum(removed.values())))
    return 1 if added else 0


if __name__ == "__main__":
    sys.exit(main())
