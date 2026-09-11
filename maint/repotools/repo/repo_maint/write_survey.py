#!/usr/bin/env python3
# repotools-stamp: repo/repo_maint/write_survey.py 3c958f60de41b808
# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every file this tree writes, and where it lands.
#
#   Usage:  python repo/repo_maint/write_survey.py [--all]
#
# WHY THIS EXISTS
#
# Generated output belongs under build/, and the harm from a stray is not that the file is wrong. It
# is that a person finds it months later beside the source, cannot tell whether it was written by
# hand or by a run, and has to open the tool to find out. A repository where that question has an
# answer only by inspection is a repository nobody can clean.
#
# So this reads every script for the places it opens a file for writing and reports the directory
# each one targets. A destination under build/ is correct and is counted and not listed. Anything
# else is named, because that is the list worth reading.
#
# WHAT IT CAN AND CANNOT SEE
#
# The target is resolved from the source text and not from a run. A path built at runtime out of a
# variable this cannot follow comes back as unresolved and is reported that way instead of being
# guessed at. Unresolved writes are the calls a person still has to read, and they are counted
# separately so the resolved figures stay honest.
#
# Reading a file for writing is what is looked for, in the forms this tree actually uses: the open
# builtin with a mode carrying w, a or x, io.open the same way, and pathlib's write_text and
# write_bytes. os.makedirs is reported too, since a directory created outside build/ is the same
# question one step earlier.

import ast
import io
import os
import re
import sys

_at = os.path.dirname(os.path.abspath(__file__))
while _at != os.path.dirname(_at) and not os.path.isdir(os.path.join(_at, "lib", "repotools")):
    _at = os.path.dirname(_at)
sys.path.insert(0, os.path.join(_at, "lib"))

from repotools import config as _config  # noqa: E402

# The repository under maintenance. The marker was `build`, a directory that is absent on a fresh
# clone, so this walked past the repository to the filesystem root on exactly the checkout where a
# survey is most worth running.
CFG = _config.load()
ROOT = CFG.where

SKIP = ("build", "deps", ".git", "__pycache__", "site", "node_modules")

# Names a path is commonly assembled from here, and the directory each one stands for. Resolving
# these is what turns "os.path.join(ROOT, 'build', 'papers')" into a destination instead of a shrug.
ANCHOR = {
    "ROOT": "",
    "HERE": "<tool>",
    "BUILD": "build",
    "PAPERS": "build/papers",
    "ORACLES": "build/oracles",
    "AUDIO": "build/audio",
    "SOUND": "build/sound",
    "CORPORA": "build/corpora",
    "APART": "build/corpora/claude_prose_by_source",
    "CHAPTERS": "theory/<book>/chapters",
    "OUT": "<out>",
    "TARGET": "<target>",
}

WRITING = re.compile(r"[wax]")


def literal(node):
    """A path expression reduced to text, or None where it cannot be read from the source."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return "$" + node.id
    if isinstance(node, ast.Attribute):
        return "$" + node.attr
    if isinstance(node, ast.JoinedStr):
        pieces = [literal(one) for one in node.values]
        return "".join(one or "?" for one in pieces)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left, right = literal(node.left), literal(node.right)
        if left is not None and right is not None:
            return left + right
        return None
    if isinstance(node, ast.Call):
        name = ""
        if isinstance(node.func, ast.Attribute):
            name = node.func.attr
        if name == "join":
            pieces = [literal(one) for one in node.args]
            if all(one is not None for one in pieces):
                return "/".join(one.strip("/") for one in pieces)
        if name in ("format", "abspath", "normpath", "expanduser"):
            return literal(node.func.value) if isinstance(node.func, ast.Attribute) else None
    return None


# The directories a repository path can start with. A write whose target begins with one of these,
# behind whatever local name held the repository root, is resolved to it.
#
# Taken from the repository's own layout instead of a fixed list, because the list was anchor_sift's
# nine directories and a tree that keeps headers under include/ would have every write to them read
# as landing somewhere outside the repository.
TOP = tuple(
    sorted(
        {os.path.basename(one) for one in CFG.source_roots() + CFG.docs_roots() + CFG.test_roots() + CFG.example_roots()}
        | {os.path.basename(CFG.tools_root())}
        | set(CFG.data.get("survey", {}).get("top", ()))
    )
)

ROOTED = re.compile(r"^\$[A-Za-z_][A-Za-z0-9_]*/(?=(?:%s)/)" % "|".join(TOP))


def destination(where):
    """The directory a written path lands in, as this tree names them."""
    if where is None:
        return None
    text = where.replace("\\", "/")
    for name, stands in ANCHOR.items():
        text = text.replace("$" + name, stands)
    # Most tools find the root by walking up from __file__ into a local name, so the target reads as
    # $something/build/corpora. Anything behind a name and in front of a real top directory is that
    # walk. Dropping it leaves a destination a reader can place.
    text = ROOTED.sub("", text)
    text = text.lstrip("/")
    if not text or text.startswith(("$", "<", "?")):
        return None
    parts = [one for one in text.split("/") if one and not one.startswith(("$", "<", "?"))]
    if not parts:
        return None
    if len(parts) == 1:
        return "." if ("." in parts[0]) else parts[0]
    return "/".join(parts[:-1]) if ("." in parts[-1]) else "/".join(parts)


def module_names(tree):
    """Module level names bound to a path, so `open(TARGET, "w")` resolves to what TARGET is.

    Almost every tool here names its destination once at the top and writes to that name later, so
    without this pass the common case is the unresolved case. Two rounds, because a destination is
    usually built from another constant: CORPORA from ROOT, then TARGET from CORPORA.
    """
    held = {}
    for _ in range(2):
        for node in tree.body:
            if not isinstance(node, ast.Assign):
                continue
            if len(node.targets) != 1 or not isinstance(node.targets[0], ast.Name):
                continue
            value = literal(node.value)
            if value is None:
                continue
            for name, stands in held.items():
                value = value.replace("$" + name, stands)
            held[node.targets[0].id] = value
    return held


def writes_in(path):
    """Every writing call in one file: its line, what it calls, and where it lands."""
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return []

    known = module_names(tree)

    def resolved(node):
        value = literal(node)
        if value is None:
            return None
        for name, stands in known.items():
            value = value.replace("$" + name, stands)
        return value

    found = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = ""
        if isinstance(node.func, ast.Name):
            name = node.func.id
        elif isinstance(node.func, ast.Attribute):
            name = node.func.attr

        if name in ("open",):
            mode = None
            if len(node.args) > 1:
                mode = literal(node.args[1])
            for word in node.keywords:
                if word.arg == "mode":
                    mode = literal(word.value)
            if mode is None or not WRITING.search(mode):
                continue
            found.append((node.lineno, "open", resolved(node.args[0]) if node.args else None))
        elif name in ("write_text", "write_bytes"):
            target = resolved(node.func.value) if isinstance(node.func, ast.Attribute) else None
            found.append((node.lineno, name, target))
        elif name == "makedirs":
            found.append((node.lineno, "makedirs", resolved(node.args[0]) if node.args else None))
    return found


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    show_all = "--all" in sys.argv

    inside = {}
    outside = {}
    unresolved = {}
    scanned = 0

    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [one for one in dirs if one not in SKIP]
        for name in sorted(names):
            if not name.endswith(".py"):
                continue
            path = os.path.join(base, name)
            shown = os.path.relpath(path, ROOT).replace("\\", "/")
            scanned += 1
            for line, kind, where in writes_in(path):
                lands = destination(where)
                row = (shown, line, kind, where or "")
                if lands is None:
                    unresolved.setdefault(shown, []).append(row)
                elif lands == "build" or lands.startswith("build/"):
                    inside.setdefault(lands, []).append(row)
                else:
                    outside.setdefault(lands, []).append(row)

    out.write("\n  %d python files read\n" % scanned)
    out.write("  %d write(s) land under build/\n"
              % sum(len(one) for one in inside.values()))
    out.write("  %d write(s) land somewhere else\n"
              % sum(len(one) for one in outside.values()))
    out.write("  %d write(s) build their path at run time and are not resolved here\n"
              % sum(len(one) for one in unresolved.values()))

    out.write("\n  UNDER build/, which is where generated output belongs\n")
    for lands in sorted(inside):
        out.write("    %-34s %d\n" % (lands, len(inside[lands])))

    out.write("\n  EVERYWHERE ELSE, worth a look one at a time\n")
    for lands in sorted(outside, key=lambda one: -len(outside[one])):
        out.write("    %s  (%d)\n" % (lands, len(outside[lands])))
        for shown, line, kind, where in sorted(outside[lands])[: (99 if show_all else 4)]:
            out.write("      %s:%d  %s  %s\n" % (shown, line, kind, where[:58]))

    if show_all:
        out.write("\n  PATH BUILT AT RUN TIME\n")
        for shown in sorted(unresolved):
            for _, line, kind, where in unresolved[shown]:
                out.write("    %s:%d  %s  %s\n" % (shown, line, kind, (where or "?")[:58]))

    out.write("\n  --all lists every site, including the unresolved ones.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
