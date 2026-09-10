#!/usr/bin/env python3
# repotools-stamp: repo/repo_maint/promotion.py e385d61f6097e272
# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Which tools in this toolkit are finished, and which are pulled and not yet converted.

  promotion.py              every unfinished file, worst first
  promotion.py --all        every file, including the finished ones
  promotion.py <path>       one file, with the line number of each trace

A tool is PULLED when its bytes are here. It is PROMOTED when it holds no project name, no license
expression, no source root and no file extension list, and asks a Config instead. The gap between
those two states is invisible in a directory listing, and a half-converted tool looks exactly like a
finished one until somebody in another repository runs it.

So the gap is counted here rather than remembered. Copying a tool in is cheap and reversible;
believing it is ready when it is not is what puts a project's hardcoded root into three other trees.

WHY PULLING FIRST IS STILL RIGHT

Nobody's tools are deleted when a copy lands here, so a repository loses nothing by the toolkit
holding an unconverted copy, and the duplication is visible instead of scattered. The alternative
was leaving tools in eight trees until somebody had time to convert them, and the measurement says
what that costs: 32 shapes written more than once and 7,948 duplicated lines across six repositories,
up from 9 shapes and 3,332 lines a day earlier, because a viewer suite replicated between two trees
overnight while the conversion queue was the thing holding it up.

FILES THAT MATCH THEMSELVES

`fetch.py` holds the needles, so it matches every one of them. `polite.py` is the module the network
rule points at. The spine's own modules name projects in the comments that explain the rules. Those
are listed as self-referential and counted apart, because a report that cries wolf about its own
detector gets ignored along with everything else in it.
"""

import os
import sys

_at = os.path.dirname(os.path.abspath(__file__))
while _at != os.path.dirname(_at) and not os.path.isdir(os.path.join(_at, "lib", "repotools")):
    _at = os.path.dirname(_at)
sys.path.insert(0, os.path.join(_at, "lib"))

from repotools import boot, fetch, findings  # noqa: E402

# Files whose matches are the detector meeting its own vocabulary. Named individually, never by a
# pattern, so a genuinely unconverted file cannot hide by being renamed into a category.
SELF_REFERENTIAL = (
    "lib/repotools/fetch.py",
    "lib/retrieval/polite.py",
    "lib/repotools/root.py",
    "lib/repotools/config.py",
    "lib/repotools/boot.py",
    "lib/repotools/__init__.py",
    "lib/repotools/cli.py",
    "repo/repo_maint/gates.py",
    "repo/repo_maint/promotion.py",
)

SETS = (
    "lib/repotools",
    "lib/numerics",
    "lib/retrieval",
    "code/code_maint",
    "code/code_verify",
    "data/data_fetch",
    "docs/docs_gen",
    "docs/docs_maint",
    "measure",
    "media_tools",
    "repo/repo_maint",
)

READABLE = (".py", ".sh", ".ps1")


def walk(toolkit):
    """Every source file in every set, as toolkit-relative POSIX paths."""
    out = []
    for one in SETS:
        base = os.path.join(toolkit, one.replace("/", os.sep))
        if not os.path.isdir(base):
            continue
        for here, dirs, names in os.walk(base):
            dirs[:] = sorted(name for name in dirs if name != "__pycache__")
            for name in sorted(names):
                if name.endswith(READABLE):
                    full = os.path.join(here, name)
                    out.append(os.path.relpath(full, toolkit).replace(os.sep, "/"))
    return sorted(out)


def traces_in(toolkit, relative):
    with open(os.path.join(toolkit, relative.replace("/", os.sep)), encoding="utf-8", errors="replace") as handle:
        return fetch.project_traces(handle.read())


def main(argv):
    toolkit = boot.toolkit_root()
    named = [one for one in argv if not one.startswith("-")]

    if named:
        relative = named[0].replace("\\", "/")
        for line, what in traces_in(toolkit, relative):
            print("  %s:%d: %s" % (relative, line, what))
        return findings.EXIT_OK

    unfinished, self_ref, finished = [], [], []
    for relative in walk(toolkit):
        found = traces_in(toolkit, relative)
        if not found:
            finished.append(relative)
        elif relative in SELF_REFERENTIAL:
            self_ref.append((relative, len(found)))
        else:
            unfinished.append((relative, len(found), sorted({what for _line, what in found})))

    unfinished.sort(key=lambda row: -row[1])
    for relative, count, kinds in unfinished:
        print("  %-44s %3d  %s" % (relative, count, "; ".join(kinds)[:64]))

    if "--all" in argv:
        print("\n  self-referential, the detector meeting its own vocabulary:")
        for relative, count in self_ref:
            print("    %-42s %3d" % (relative, count))
        print("\n  %d file(s) carry no trace at all." % len(finished))

    total = len(unfinished) + len(self_ref) + len(finished)
    print(
        "\n  %d file(s), %d converted, %d self-referential, %d still to convert."
        % (total, len(finished), len(self_ref), len(unfinished))
    )
    # Reading nothing is never passing. A set list that has drifted from the tree yields no files,
    # and a promotion report over zero files would read as a finished toolkit.
    if total == 0:
        print("  no files were read, so nothing was assessed.")
        return findings.EXIT_READ_NOTHING
    return findings.EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
