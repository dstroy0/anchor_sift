#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Assemble the method paper and the scripts it describes into one directory that runs without this
# repository, for docs/research/anchor-sift-method.md.
#
#   Usage:  python tools/dev_env/whitepaper_archive.py
#
# A paper that cites tools/dev_env/... is unreadable to anyone who does not hold this tree, and a reader
# who is being asked to accept or reject what the instrument reports has to be able to run it. So the
# paper travels with its code.
#
# The contents are taken from the paper's own Scope line instead of from a list kept here. A list kept
# here would be correct on the day it was written and would drift the first time the paper gained a
# section, and nothing would report the drift. Reading the Scope line means the archive is wrong only
# when the paper is wrong about itself.
#
# Local imports are followed, since a cited script that imports a sibling is not runnable without it.
# The follow is transitive and stops at the standard library, which the reader already has.
#
# Nothing is minified, renamed or stripped. The file blocks explain why each measurement is built the way
# it is, and those explanations are most of what a reader needs to judge whether the measurement is sound.

import io
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOLS = os.path.join(ROOT, "tools", "dev_env")
PAPER = os.path.join(ROOT, "docs", "research", "anchor-sift-method.md")
ARCHIVE = os.path.join(ROOT, "build", "whitepaper")

SCOPE = re.compile(r"^\*\*Scope:\*\*\s*(.+)$", re.MULTILINE)
CITED = re.compile(r"`(tools/dev_env/[A-Za-z0-9_]+\.py)`")
IMPORTED = re.compile(r"^\s*(?:from\s+([A-Za-z0-9_]+)\s+import|import\s+([A-Za-z0-9_]+))",
                      re.MULTILINE)


def scope_scripts(text):
    """The scripts the paper names in its Scope line, in the order it names them."""
    found = SCOPE.search(text)
    if not found:
        return []
    seen = []
    for path in CITED.findall(found.group(1)):
        if path not in seen:
            seen.append(path)
    return seen


def local_imports(path):
    """The sibling modules a script imports, ignoring the standard library."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    wanted = []
    for first, second in IMPORTED.findall(text):
        name = first or second
        if not name:
            continue
        beside = os.path.join(TOOLS, "%s.py" % name)
        if os.path.isfile(beside) and (name not in wanted):
            wanted.append(name)
    return wanted


def closure(starting):
    """Every script needed to run the named ones, following sibling imports until nothing is added."""
    held = []
    pending = list(starting)
    while pending:
        path = pending.pop(0)
        if path in held:
            continue
        held.append(path)
        beside = os.path.join(ROOT, path.replace("/", os.sep))
        if not os.path.isfile(beside):
            continue
        for name in local_imports(beside):
            nearby = "tools/dev_env/%s.py" % name
            if nearby not in held:
                pending.append(nearby)
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isfile(PAPER):
        out.write("  no %s\n" % PAPER)
        out.flush()
        return 1

    with open(PAPER, encoding="utf-8", errors="replace") as handle:
        paper = handle.read()

    named = scope_scripts(paper)
    if not named:
        out.write("  the paper's Scope line names no scripts, nothing to archive\n")
        out.flush()
        return 1

    everything = closure(named)
    pulled_in = [path for path in everything if path not in named]

    os.makedirs(ARCHIVE, exist_ok=True)
    shutil.copyfile(PAPER, os.path.join(ARCHIVE, os.path.basename(PAPER)))

    out.write("  %-42s %-9s %s\n" % ("file", "bytes", "why it is here"))
    out.write("  %-42s %-9d %s\n"
              % (os.path.basename(PAPER), os.path.getsize(PAPER), "the paper"))

    missing = []
    for path in everything:
        source = os.path.join(ROOT, path.replace("/", os.sep))
        if not os.path.isfile(source):
            missing.append(path)
            continue
        target = os.path.join(ARCHIVE, os.path.basename(path))
        shutil.copyfile(source, target)
        out.write("  %-42s %-9d %s\n"
                  % (os.path.basename(path), os.path.getsize(source),
                     "named in Scope" if path in named else "imported by one that is"))

    manifest = os.path.join(ARCHIVE, "MANIFEST.txt")
    with open(manifest, "w", encoding="utf-8", newline="") as handle:
        handle.write("anchor-sift method paper and the scripts it describes\n\n")
        handle.write("Every script here is plain Python 3 and uses only the standard library, with\n")
        handle.write("one exception noted below. Run any of them from the directory above this one,\n")
        handle.write("as python <name>.py, and read the block at the top of the file first. That\n")
        handle.write("block says what the measurement is for and what it cannot see.\n\n")
        handle.write("named in the paper's Scope line:\n")
        for path in named:
            handle.write("  %s\n" % os.path.basename(path))
        if pulled_in:
            handle.write("\nincluded because a script above imports it:\n")
            for path in pulled_in:
                handle.write("  %s\n" % os.path.basename(path))
        handle.write("\nicsnl_probe.py needs pypdf to read a PDF. Nothing else needs anything.\n")
        handle.write("\nThe corpora these run on are not included. They are fetched by the scripts\n")
        handle.write("that fetch them, from the archives that publish them.\n")

    out.write("\n  %d files written to %s\n" % (len(everything) + 1, ARCHIVE))
    if missing:
        out.write("  the paper's Scope names %d file(s) that are not in the tree:\n" % len(missing))
        for path in missing:
            out.write("    %s\n" % path)

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
