#!/usr/bin/env python3
# repotools-stamp: repo/repo_maint/inventory.py 960d950d19c85cf7
# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Which tool is written more than once across every repository, measured instead of remembered.

  inventory.py survey <dir> ...     group the tools under these trees by shape, across repositories
  inventory.py show <shape-id>      every copy of one shape, with the lines they differ by
  inventory.py candidates <dir> ... the same survey, cut to what is worth promoting into the toolkit

At a thousand files a person cannot hold the answer, and the answer changes every week. A byte
comparison finds almost none of it: the copies of `codemask.py` measured here differ in a header
line, a project name inside a docstring, a formatter's line break and one identifier. Every one of
those is invisible to a reader and fatal to an exact hash.

So the comparison is over shape. Comments and docstrings come off, string literals fold to one
token, and identifiers renumber by first appearance. What is left is the algorithm, and two copies
of one tool land in the same bucket after four years of separate prose edits.

WHAT COUNTS AS A CANDIDATE

A shape held by two or more repositories, in a file that is a tool. `candidates` applies one further
cut: a shape whose copies all sit in the same repository is that repository's own repetition and is
somebody else's problem. Promotion is for the ones that cross a repository boundary, because those
are the ones where a fix lands in one tree and never reaches the other three.

WHAT IT WILL NOT TELL YOU

Whether a shape should be promoted. Two fetch scripts that agree on shape may disagree on what they
are for, and a survey cannot read intent. It narrows a thousand files to a list a person can read,
and the reading is the part it does not do.
"""

import os
import sys

_at = os.path.dirname(os.path.abspath(__file__))
while _at != os.path.dirname(_at) and not os.path.isdir(os.path.join(_at, "lib", "repotools")):
    _at = os.path.dirname(_at)
sys.path.insert(0, os.path.join(_at, "lib"))

from repotools import shape  # noqa: E402

# Directories a tool never lives in. A vendored dependency holds thousands of files that are not
# this work's, and a survey that reads them reports somebody else's duplication.
SKIP = {
    ".git",
    ".claude",
    "__pycache__",
    "node_modules",
    "build",
    "build-cov",
    "build-bench",
    "build-werror",
    "site",
    "vendor",
    "_vendor",
    ".pio",
    ".pio_cov",
    "coverage_reports",
    ".venv",
    "venv",
}

TOOL_EXTENSIONS = (".py", ".sh", ".ps1", ".cjs")

# The smallest shape worth reporting. Below this a shape is an import block or a two line wrapper,
# and every tree holds hundreds of those.
MIN_TOKENS = 40


def repository_of(path, roots):
    """Which surveyed tree `path` sits under, by longest matching prefix.

    Longest match, because `git_project` and `git_project/private_repos` are both roots that were
    handed in, and the shorter one would claim every file under the longer one.
    """
    best = ""
    full = os.path.abspath(path)
    for one in roots:
        one = os.path.abspath(one)
        if full.startswith(one + os.sep) and len(one) > len(best):
            best = one
    return best or os.path.dirname(full)


def walk(where):
    """Every tool file under `where`, sorted, with the skipped and vendored directories pruned.

    A directory holding its own `.git` is another repository checked out inside this one: a
    submodule, or a vendored dependency. Its files are already maintained upstream, so counting them
    reports duplication that vendoring has already solved. Leaving them in put four copies of the
    MMgr tool tree into a survey whose whole purpose is finding the copies nobody is maintaining.

    The tree handed in is never pruned by this rule, or a survey of one repository would read
    nothing at all.
    """
    out = []
    for here, dirs, names in os.walk(where):
        dirs[:] = sorted(
            name
            for name in dirs
            if name not in SKIP and not os.path.exists(os.path.join(here, name, ".git"))
        )
        for name in sorted(names):
            if name.endswith(TOOL_EXTENSIONS):
                out.append(os.path.join(here, name))
    return sorted(out)


def survey(roots):
    """Group every tool under `roots` by shape.

    Returns `{shape_id: [ShapeOf, ...]}` and the list of files that could not be tokenized. The
    second list is returned and never discarded: a survey that silently drops what it cannot read
    reports a smaller problem than the one it was asked about.
    """
    groups = {}
    unshaped = []
    # One file reached by two paths is one file. Linking a tool from a second tree is already the end
    # state a promotion is trying to reach, so counting the link as a copy recommends solving a
    # problem that the link solved. It also counts the same lines twice in the saving.
    seen_real = set()
    for one in roots:
        if not os.path.isdir(one):
            raise SystemExit(
                "inventory: %s is not a directory. A root that is not there contributes no files "
                "and would let this report success over nothing." % one
            )
        for path in walk(one):
            real = os.path.realpath(path)
            if real in seen_real:
                continue
            seen_real.add(real)
            found = shape.of(path)
            if found.unshaped():
                unshaped.append(found)
                continue
            if found.tokens < MIN_TOKENS:
                continue
            groups.setdefault(found.shaped, []).append(found)
    return groups, unshaped


def spread(members, roots):
    """How many distinct repositories a shape's copies sit in."""
    return len({repository_of(one.path, roots) for one in members})


def report(groups, unshaped, roots, crossing_only, stream=None):
    """Print the groups, largest duplicated line count first.

    Sorted by what a promotion would save, so the first row read is the one worth doing first.
    """
    stream = stream or sys.stdout
    rows = []
    for shape_id, members in groups.items():
        if len(members) < 2:
            continue
        across = spread(members, roots)
        if crossing_only and across < 2:
            continue
        # What a promotion removes: every copy after the first.
        saved = sum(one.lines for one in members) - max(one.lines for one in members)
        rows.append((saved, shape_id, members, across))

    rows.sort(reverse=True, key=lambda row: (row[0], row[1]))

    for saved, shape_id, members, across in rows:
        print(
            "\n%s  %d cop(ies) in %d repositor(ies), %d duplicated line(s)"
            % (shape_id, len(members), across, saved),
            file=stream,
        )
        for one in sorted(members, key=lambda member: member.path):
            print("    %s  (%d lines)" % (one.path.replace("\\", "/"), one.lines), file=stream)

    if unshaped:
        print("\n%d file(s) could not be tokenized and were not compared:" % len(unshaped), file=stream)
        for one in unshaped[:20]:
            print("    %s" % one.path.replace("\\", "/"), file=stream)
        if len(unshaped) > 20:
            print("    ... and %d more" % (len(unshaped) - 20), file=stream)

    total = sum(row[0] for row in rows)
    print(
        "\n  %d shape(s) held more than once, %d duplicated line(s) in total." % (len(rows), total),
        file=stream,
    )
    return rows


def show(groups, shape_id, stream=None):
    """One shape in full: every copy, and the lines on which two of them differ."""
    stream = stream or sys.stdout
    members = None
    for key, value in groups.items():
        if key.startswith(shape_id):
            members = value
            break
    if not members:
        raise SystemExit("inventory: no shape starting %s in this survey" % shape_id)

    members = sorted(members, key=lambda member: member.path)
    print("shape %s, %d cop(ies)" % (members[0].shaped, len(members)), file=stream)
    for one in members:
        print("    %s  exact=%s  %d lines" % (one.path.replace("\\", "/"), one.exact, one.lines), file=stream)

    exact = {one.exact for one in members}
    if len(exact) == 1:
        print("\n  Every copy is byte identical. Promotion is a move.", file=stream)
    else:
        print(
            "\n  %d distinct byte contents behind one shape. The copies have drifted in comments, "
            "names or layout, and promotion has to pick which text survives." % len(exact),
            file=stream,
        )
    return members


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0

    mode = argv[0]
    rest = [one for one in argv[1:] if not one.startswith("-")]

    if mode in ("survey", "candidates"):
        if not rest:
            raise SystemExit("inventory: name at least one directory to survey")
        # `candidates` drops every shape whose copies sit in one repository, so over a single tree it
        # answers zero every time and reads as a clean bill of health. Refusing is the only honest
        # response: the question asked cannot be answered by the command that was used.
        if mode == "candidates" and len(rest) < 2:
            raise SystemExit(
                "inventory: candidates reports shapes that cross a repository boundary, so over one "
                "tree it would answer zero whatever that tree holds. Name two or more trees, or use "
                "`survey %s` to see what this one repeats internally." % rest[0]
            )
        groups, unshaped = survey(rest)
        rows = report(groups, unshaped, rest, crossing_only=(mode == "candidates"))
        # Reporting nothing over a real tree is a result. Reporting nothing because no file was read
        # is a broken invocation, and the two look identical without this.
        read = sum(len(value) for value in groups.values()) + len(unshaped)
        if read == 0:
            print("  no files were read, so nothing was compared.")
            return 2
        return 0 if rows is not None else 1

    if mode == "show":
        if len(rest) < 2:
            raise SystemExit("inventory: show <shape-id> <dir> ...")
        groups, _ = survey(rest[1:])
        show(groups, rest[0])
        return 0

    raise SystemExit("inventory: no mode named %s. Modes are survey, candidates, show." % mode)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
