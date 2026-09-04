#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Cut one paper out of an extracted proceedings volume so it can be read whole, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/paper_slice.py icsnl2016 203-224 vaneijk
#
# A volume extracted by icsnl_probe.py holds two hundred pages of unrelated papers in one file, and a
# keyword hit inside it locates a line without giving the argument the line sits in. Reading a matched
# line and concluding from it is the same defect as reading part of a source file and describing the
# whole, and it has produced confident wrong statements in this work before.
#
# So a paper is cut out at its own page boundaries and written as its own file, which can then be read
# from its first line to its last. The page markers are kept in the cut, since an example numbered in the
# paper is cited by the page it sits on.

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAPERS = os.path.join(ROOT, "build", "papers")


def pages_of(path):
    """Every page of an extracted volume, keyed by the page number written into it."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        blob = handle.read()
    held = {}
    parts = re.split(r"\n===== page (\d+) =====\n", blob)
    walk = 1
    while walk + 1 <= len(parts) - 1:
        held[int(parts[walk])] = parts[walk + 1]
        walk += 2
    return held


def main():
    if len(sys.argv) < 4:
        print("usage: paper_slice.py <volume name> <first-last> <paper name>")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    volume, span, name = sys.argv[1], sys.argv[2], sys.argv[3]
    source = os.path.join(PAPERS, "%s.txt" % volume)
    if not os.path.isfile(source):
        out.write("  no %s, run icsnl_probe.py first\n" % source)
        out.flush()
        return 1

    first, last = (int(one) for one in span.split("-"))
    held = pages_of(source)
    target = os.path.join(PAPERS, "%s_%s.txt" % (volume, name))
    written = 0
    with open(target, "w", encoding="utf-8", newline="") as handle:
        for number in range(first, last + 1):
            if number not in held:
                continue
            handle.write("\n===== page %d =====\n%s" % (number, held[number]))
            written += 1

    out.write("  %d pages of %s written to %s\n" % (written, volume, target))
    out.write("  %d bytes\n" % os.path.getsize(target))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
