#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Report the prose findings that land on lines a change added, and none of the older ones.

    python maint/prose/prose_on_changed_lines.py                  working tree against HEAD
    python maint/prose/prose_on_changed_lines.py --staged         the index against HEAD
    python maint/prose/prose_on_changed_lines.py --base <rev>     working tree against <rev>

docs_check.py reports every finding in a file, and a file carrying a hundred older findings buries
the three a change just wrote. This runs docs_check.py over exactly the files the diff touches and
keeps the findings whose line the diff added. A file new to the tree counts every line as added.

A finding never fails the run, the same as in docs_check.py, because a person decides each site.
It exits nonzero only where it could not run: git failing, or the checker printing no file count.
Zero changed files prints its own line, which no count of findings can be mistaken for.
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = os.path.join(HERE, "docs_check.py")

# A hunk header in unified diff output: the new file's first line and how many lines follow.
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")

# One finding line from docs_check.py: "  prose <path>:<line>: ..." or "  BREAK <path>:<line>: ...".
FINDING = re.compile(r"^\s+(prose|BREAK)\s+(.+?):(\d+):\s")


def repository_root():
    """This repository's top level, from git, with git's own variables cleared first."""
    environment = dict(os.environ)
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_COMMON_DIR"):
        environment.pop(key, None)
    said = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=HERE,
                                   env=environment)
    return os.path.abspath(said.decode("utf-8", "replace").strip())


def added_lines(root, diff_arguments):
    """Map each changed file to the set of line numbers the diff added in it."""
    text = subprocess.check_output(["git", "diff", "-U0", "--no-color"] + diff_arguments,
                                   cwd=root).decode("utf-8", "replace")
    added = {}
    current = None
    for line in text.splitlines():
        if line.startswith("+++ "):
            name = line[4:]
            current = None if name == "/dev/null" else name[2:] if name.startswith("b/") else name
            if current is not None:
                added.setdefault(current, set())
            continue
        found = HUNK.match(line)
        if found and current is not None:
            first = int(found.group(1))
            count = 1 if found.group(2) is None else int(found.group(2))
            added[current].update(range(first, first + count))
    return added


def untracked_files(root):
    """Files git does not track yet and does not ignore. Every line of one is added."""
    text = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard"],
                                   cwd=root).decode("utf-8", "replace")
    return [one for one in text.splitlines() if one]


def main():
    arguments = sys.argv[1:]
    diff_arguments = []
    include_untracked = True
    if "--staged" in arguments:
        diff_arguments = ["--cached"]
        include_untracked = False
    if "--base" in arguments:
        at = arguments.index("--base")
        if at + 1 >= len(arguments):
            print("  --base needs a revision")
            return 2
        diff_arguments = [arguments[at + 1]]

    root = repository_root()
    added = added_lines(root, diff_arguments)
    if include_untracked:
        for name in untracked_files(root):
            with open(os.path.join(root, name), encoding="utf-8", errors="replace") as handle:
                added[name] = set(range(1, len(handle.read().splitlines()) + 1))

    changed = sorted(name for name, lines in added.items() if lines)
    if not changed:
        print("  no changed lines. No prose was checked")
        return 0

    run = subprocess.run([sys.executable, CHECKER] + [os.path.join(root, one) for one in changed],
                         cwd=root, capture_output=True, text=True, encoding="utf-8",
                         errors="replace")
    if "file(s) checked" not in run.stdout:
        print("  docs_check.py did not report a count. Its findings cannot be trusted")
        print(run.stdout[-2000:])
        print(run.stderr[-2000:])
        return 2

    kept = []
    for line in run.stdout.splitlines():
        found = FINDING.match(line)
        if found is None:
            continue
        path = os.path.relpath(found.group(2), root).replace("\\", "/")
        if int(found.group(3)) in added.get(path, ()):
            kept.append(line)

    print("  %d changed file(s), %d changed line(s), %d finding(s) on changed lines"
          % (len(changed), sum(len(added[one]) for one in changed), len(kept)))
    for line in kept:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
