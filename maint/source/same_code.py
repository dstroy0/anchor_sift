#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Check that an edit changed comments and blank lines and no code.

    python maint/source/same_code.py BEFORE AFTER
    python maint/source/same_code.py --tree BEFORE_DIR AFTER_DIR

Both sides are stripped by maint/source/strip_comments.py and compared line by line with blank
lines dropped. Identical code prints "same code" and exits 0. The first differing line prints with
its number on each side and exits 1. With --tree, every file under BEFORE_DIR is paired with the
file at the same relative path under AFTER_DIR, and a file missing from either side is a
difference.

A recomment pass is only a recomment pass where this passes. A comment edit that also moved a brace
or renamed a variable changes what the compiler builds, and reading the diff does not reliably catch
that among a thousand added comment lines.
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import strip_comments  # noqa: E402


def code_lines(path):
    """The file's code with comments gone, as (line number in the stripped text, line) pairs."""
    text = io.open(path, encoding="utf-8", errors="replace", newline="").read()
    stripped = strip_comments.rewrite(text, False, os.path.splitext(path)[1])
    return [(number, line.rstrip()) for number, line in enumerate(stripped.split("\n"), start=1)
            if line.strip()]


def compare(before, after):
    """None where the two files carry the same code, or a description of the first difference."""
    left = code_lines(before)
    right = code_lines(after)
    for (left_number, left_line), (right_number, right_line) in zip(left, right):
        if left_line != right_line:
            return ("%s:%d: %s\n%s:%d: %s"
                    % (before, left_number, left_line, after, right_number, right_line))
    if len(left) != len(right):
        return "%s has %d code lines and %s has %d" % (before, len(left), after, len(right))
    return None


def main():
    arguments = sys.argv[1:]
    pairs = []
    if arguments[:1] == ["--tree"] and len(arguments) == 3:
        before_root, after_root = arguments[1], arguments[2]
        names = set()
        for root in (before_root, after_root):
            for directory, _, files in os.walk(root):
                if "__pycache__" in directory:
                    continue
                for name in files:
                    if os.path.splitext(name)[1] in (strip_comments.C_SUFFIXES
                                                     | strip_comments.PYTHON_SUFFIXES
                                                     | strip_comments.SHELL_SUFFIXES):
                        names.add(os.path.relpath(os.path.join(directory, name), root))
        for name in sorted(names):
            pairs.append((os.path.join(before_root, name), os.path.join(after_root, name)))
    elif len(arguments) == 2:
        pairs.append((arguments[0], arguments[1]))
    else:
        print(__doc__)
        return 2

    differing = 0
    for before, after in pairs:
        if not os.path.isfile(before) or not os.path.isfile(after):
            print("MISSING %s or %s" % (before, after))
            differing += 1
            continue
        found = compare(before, after)
        if found is not None:
            print("DIFFERS\n%s" % found)
            differing += 1
    print("%d file(s) compared, %d differ" % (len(pairs), differing))
    if differing == 0:
        print("same code")
    return 1 if differing else 0


if __name__ == "__main__":
    raise SystemExit(main())
