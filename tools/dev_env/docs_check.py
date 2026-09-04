#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# What the prose standard says, checked instead of remembered.
#
#   Usage:  python tools/dev_env/docs_check.py [root]
#
# It exists because a table header was left standing with every row removed under it, and that
# rendered as an empty table on the site for a day before anyone looked. Nothing read the documents
# and nothing could have caught it. Each check below is a defect that actually reached a published
# page, and none of them is a matter of taste.
#
# Exit status is the count of findings, so it fails a pipeline without needing a flag.

import os
import re
import sys

# The tokens the writing standard bans outright, and the British spellings it bans by pattern.
BANNED = (
    r"\brather\b",
    r"\badd up\b",
    r"\bso a\b",
    r"load-bearing",
    r"\blabelled\b",
    r"\bmodelled\b",
    r"\bneighbour",
    r"\bbehaviour",
    r"\bcolour",
    r"\bcentre\b",
    r"\bwhilst\b",
    r"\bamongst\b",
    r"\borganis",
    r"\banalyse\b",
)

EM_DASH = "—"

# A markdown table separator: | --- | --- |
SEPARATOR = re.compile(r"^\s*\|[\s:|-]+\|\s*$")
ROW = re.compile(r"^\s*\|")

# A relative markdown link, skipping anything with a scheme and anything anchored to a heading.
LINK = re.compile(r"\[[^\]]*\]\(([^)#][^)]*)\)")


def empty_tables(lines):
    """A separator row with no data row under it renders as a table with a head and no body."""
    found = []
    for at, line in enumerate(lines):
        if not SEPARATOR.match(line):
            continue
        following = lines[at + 1] if (at + 1) < len(lines) else ""
        if not ROW.match(following):
            found.append((at + 1, "table header with no rows under it"))
    return found


def banned_tokens(lines):
    found = []
    for at, line in enumerate(lines):
        for pattern in BANNED:
            for hit in re.finditer(pattern, line, re.IGNORECASE):
                found.append((at + 1, "banned token %r" % hit.group(0)))
    return found


def em_dashes(lines):
    return [(at + 1, "em dash") for at, line in enumerate(lines) if EM_DASH in line]


def dead_links(path, lines):
    """A relative link to a file that is not there. Absolute and external links are left alone."""
    here = os.path.dirname(path)
    found = []
    for at, line in enumerate(lines):
        for hit in LINK.finditer(line):
            target = hit.group(1).split("#")[0].strip()
            if (not target) or ("://" in target) or target.startswith("/"):
                continue
            if not os.path.exists(os.path.join(here, target)):
                found.append((at + 1, "link to a file that is not there: %s" % target))
    return found


def main():
    # Structure fails a commit. Prose is reported and does not, because the prose backlog predates
    # this check and a hook nobody can satisfy is a hook somebody turns off. Pass --strict to fail
    # on everything, which is what a cleanup pass wants.
    strict = "--strict" in sys.argv
    where_given = [one for one in sys.argv[1:] if not one.startswith("-")]
    root = where_given[0] if where_given else "docs"

    breaking = 0
    prose = 0
    checked = 0

    for here, _, names in os.walk(root):
        for name in sorted(names):
            if not name.endswith(".md"):
                continue
            path = os.path.join(here, name)
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
            checked += 1

            # A reader sees these as a broken page, so they stop a commit.
            structural = empty_tables(lines) + dead_links(path, lines) + em_dashes(lines)
            # These read wrong and render fine.
            wording = banned_tokens(lines)

            for at, what in sorted(structural):
                print("  BREAK %s:%d: %s" % (path.replace("\\", "/"), at, what))
            for at, what in sorted(wording):
                print("  prose %s:%d: %s" % (path.replace("\\", "/"), at, what))

            breaking += len(structural)
            prose += len(wording)

    print("  %d file(s) checked, %d breaking, %d prose" % (checked, breaking, prose))
    return (breaking + prose) if strict else breaking


if __name__ == "__main__":
    raise SystemExit(main())
