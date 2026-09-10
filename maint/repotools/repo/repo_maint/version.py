#!/usr/bin/env python3
# repotools-stamp: repo/repo_maint/version.py efa1ddfa43dc5315
# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Carry the version out of .bumpversion.cfg and into the source tree, and say when it has drifted.

.bumpversion.cfg is where the current version is stated, and `bump2version` moves it:

    bump2version patch                  0.1.0 -> 0.1.1
    bump2version minor                  0.1.0 -> 0.2.0
    bump2version major                  0.1.0 -> 1.0.0
    bump2version --dry-run --verbose minor        what it would write, and to what

That writes three files, and they are the three that carry a version as data and nothing else:
library.json and library.properties publish it to a package index, and CMakeLists.txt hands it to
project(). Those three were apart once already - both manifests said v0.0.0 while CMake and every
banner in the tree said 0.1.0 - which is the whole reason a version now has one home.

bump2version cannot write the other two forms, so this does:

    the IDEMIP_VERSION_* block in src/idemip_config.h, the only copy a consumer can reach from C.
    Four lines that have to move together, and bump2version 1.0.1 matches a single line at a time.

    the banner at the head of every file in the tree, in whichever comment the file's language
    takes. There are 184 of them and a new file appears whenever a unit does, so they are found by
    walking rather than by being listed.

Neither is a fixed string bump2version can be pointed at, and both go stale silently: a banner
reading v0.1.0 in a 0.2.0 tree is wrong in a way no compiler and no test can see.

    python tools/dev_env/version.py              what would change, and nothing written
    python tools/dev_env/version.py --sync       write it
    python tools/dev_env/version.py --check      exit nonzero when anything has drifted

--check is the CI shape, beside guards.py, counters.py and deadstate.py. Note that .bumpversion.cfg
itself carries no banner and no SPDX line: bump2version rewrites that file through configparser on
every bump, which drops comments, so anything written there survives exactly until the next bump.
This docstring is where that explanation lives instead.
"""
import argparse
import configparser
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG = ".bumpversion.cfg"
CONFIG_H = os.path.join("src", "idemip_config.h")

# Directories a walk never enters. docs/learn is the RFC corpus as the RFC Editor published it and
# is not ours to stamp; the rest are build output, tooling caches and the vendored Unity clone.
SKIP_DIRS = {
    ".git",
    ".vscode",
    "__pycache__",
    "build",
    "build-cov",
    "Testing",
    "_deps",
    "node_modules",
}
SKIP_PATHS = {os.path.join("docs", "learn")}

# The banner, and the comment each language takes it in. The version is the one group that moves.
BANNER = re.compile(r"^(?P<lead>\s*(?://|#)\s*)idemIP v(?P<version>\d+\.\d+\.\d+)(?P<rest>\s+-\s+Copyright\b)")

# The block in idemip_config.h. Kept contiguous in the header so one pattern covers all four.
# \r?\n rather than \n because the file is read with its endings intact and may carry either.
VERSION_BLOCK = re.compile(
    r"#define IDEMIP_VERSION_MAJOR \d+(?P<eol>\r?\n)"
    r"#define IDEMIP_VERSION_MINOR \d+\r?\n"
    r"#define IDEMIP_VERSION_PATCH \d+\r?\n"
    r'#define IDEMIP_VERSION_STRING "\d+\.\d+\.\d+"'
)

# Only these are read. A banner in anything else is not one this tree writes.
SUFFIXES = (".c", ".h", ".py", ".cmake", ".cfg", ".yml", ".yaml", ".properties", ".json", ".txt", ".md")

# Files whose whole name is the extension, so endswith() above never reaches them.
NAMES = {"CMakeLists.txt", ".clangd"}

# A banner sits on the first line, unless the file opens with a shebang and it sits on the second.
# Every script under tools/dev_env and test/ is the second case, and reading only the first line
# silently skipped all eleven of them.
BANNER_MAX_LINE = 2


def current_version():
    """The version .bumpversion.cfg states, which is the only one this tree has."""
    parser = configparser.ConfigParser()
    path = os.path.join(ROOT, CONFIG)
    if not parser.read(path, encoding="utf-8"):
        sys.exit("{} is missing: it is where the current version is stated".format(CONFIG))
    try:
        return parser.get("bumpversion", "current_version")
    except (configparser.NoSectionError, configparser.NoOptionError):
        sys.exit("{} has no [bumpversion] current_version".format(CONFIG))


def walk():
    """Every file in the tree that could carry a banner, as a path relative to the root."""
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        rel_dir = os.path.relpath(dirpath, ROOT)
        rel_dir = "" if rel_dir == "." else rel_dir
        if any(rel_dir == s or rel_dir.startswith(s + os.sep) for s in SKIP_PATHS):
            dirnames[:] = []
            continue
        for name in sorted(filenames):
            if name.endswith(SUFFIXES) or name in NAMES:
                yield os.path.join(rel_dir, name) if rel_dir else name


def read(rel):
    """The file's text as it sits on disk, or None where it is not text this tool can read.

    newline="" so a CRLF arrives as a CRLF rather than being folded to a newline on the way in.
    This tool changes one line of a file and has no business changing the other several thousand:
    reading with the default and writing back would rewrite every ending in the tree to LF, which
    is a diff nobody asked for on a checkout that happens to use CRLF.
    """
    try:
        with open(os.path.join(ROOT, rel), "r", encoding="utf-8", newline="") as handle:
            return handle.read()
    except (UnicodeDecodeError, OSError):
        return None


def write(rel, text):
    """Write the file back exactly as read, endings and all."""
    with open(os.path.join(ROOT, rel), "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def banner_line(text):
    """Which line holds the banner, and the match on it, or (None, None).

    Only the head of the file is considered: a banner is metadata, and the same string further down
    is prose about a banner, which rewriting would edit as if it were metadata. A shebang takes the
    first line where there is one, so the banner is on the second - every script in this tree.
    """
    lines = text.split("\n")
    for index in range(min(BANNER_MAX_LINE, len(lines))):
        if index and not lines[0].startswith("#!"):
            break
        match = BANNER.match(lines[index])
        if match:
            return index, match
    return None, None


def restamp_banner(text, version):
    """The text with its banner at the stated version, and whether that changed anything."""
    index, match = banner_line(text)
    if match is None or match.group("version") == version:
        return text, False
    lines = text.split("\n")
    lines[index] = "{}idemIP v{}{}{}".format(
        match.group("lead"), version, match.group("rest"), lines[index][match.end():]
    )
    return "\n".join(lines), True


def restamp_block(text, version):
    """The text with the IDEMIP_VERSION_* block at the stated version, and whether that changed."""
    major, minor, patch = version.split(".")
    match = VERSION_BLOCK.search(text)
    if not match:
        sys.exit(
            "{} has no IDEMIP_VERSION_* block, or its four lines are no longer contiguous. "
            "They have to stay together: one pattern moves all four.".format(CONFIG_H)
        )
    eol = match.group("eol")
    block = eol.join(
        [
            "#define IDEMIP_VERSION_MAJOR {}".format(major),
            "#define IDEMIP_VERSION_MINOR {}".format(minor),
            "#define IDEMIP_VERSION_PATCH {}".format(patch),
            '#define IDEMIP_VERSION_STRING "{}"'.format(version),
        ]
    )
    updated = text[: match.start()] + block + text[match.end() :]
    return updated, updated != text


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--sync", action="store_true", help="write the version into the tree")
    mode.add_argument("--check", action="store_true", help="exit nonzero when anything has drifted")
    args = ap.parse_args()

    version = current_version()
    drifted = []

    text = read(CONFIG_H)
    if text is None:
        sys.exit("{} is unreadable".format(CONFIG_H))
    updated, changed = restamp_block(text, version)
    if changed:
        drifted.append(CONFIG_H + "  (IDEMIP_VERSION_* block)")
        if args.sync:
            write(CONFIG_H, updated)

    stamped = 0
    stale = 0
    for rel in walk():
        text = read(rel)
        if text is None:
            continue
        if banner_line(text)[1] is None:
            continue
        stamped += 1
        updated, changed = restamp_banner(text, version)
        if changed:
            stale += 1
            drifted.append(rel)
            if args.sync:
                write(rel, updated)

    print("{} states {}".format(CONFIG, version))
    print("{} banners read, {} at another version".format(stamped, stale))

    if not drifted:
        print("every version in the tree is {}".format(version))
        return 0

    verb = "wrote" if args.sync else "would write"
    print("\n{} {} to {} file(s):".format(verb, version, len(drifted)))
    for rel in drifted:
        print("  " + rel)

    if args.check:
        print(
            "\nrun `python tools/dev_env/version.py --sync` - a banner at the wrong version "
            "is wrong in a way no compiler and no test can see"
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
