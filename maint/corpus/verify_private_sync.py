#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Verify that what build/ reaches is the corpus the signature covers.
#
#   python maint/corpus/verify_private_sync.py           verify, and say what disagrees
#   python maint/corpus/verify_private_sync.py --quiet   only what disagrees
#   python maint/corpus/verify_private_sync.py --bypass  answer the gate without satisfying it
#
# WHY THIS VERIFIES AND NO LONGER COPIES
#
# It used to copy the corpus into build/ and hash each copy on the way. build/oracles, build/papers
# and build/audio are symbolic links to the corpus now, so there is no copy to make and nothing to
# drift. What is left is the question the copy was really answering: is the corpus reachable from
# here the corpus somebody signed.
#
# The 186 MB duplicate is gone with it. It existed so an rm -rf build/ could not reach the closed
# repository, and a symbolic link under POSIX removal answers that: rm takes the link and leaves
# the target. PowerShell's Remove-Item -Recurse has followed directory links, so clearing build/
# from PowerShell means deleting the three links first.
#
# WHAT DISAGREEING MEANS
#
#   missing       the inventory lists it and nothing is reachable at that path. A measurement
#                 citing it cannot be reproduced from here.
#   changed       the bytes under build/ are not the bytes the inventory records. Every number
#                 taken since is against something else.
#   unrecorded    reachable and in neither inventory. Nothing signed covers it, so nothing
#                 measured over it can be tied to a signature.
#   unlinked      build/ has a real directory where a link belongs, the old copy left
#                 behind. It can be right by accident and it is not what the signature covers.
#
# Any of them exits non-zero, which makes this usable as a commit gate. --bypass answers it without
# satisfying it, spelled the same as every other gate here, and says so every time.

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

# The corpus directory, and where build/ reaches it. The corpus keeps its own names.
WANTED = (("oracles", os.path.join(ROOT, "build", "oracles")),
          ("papers", os.path.join(ROOT, "build", "papers")),
          ("speech", os.path.join(ROOT, "build", "audio")))

# Two signed inventories cover the corpus between them. The recordings sit in their own, which
# lets a withdrawal rewrite and re-sign that one alone. Reading only the first reported every
# recording as uninventoried.
MANIFESTS = ("MANIFEST.tsv", "AUDIO_MANIFEST.tsv")

BYPASS_ENV = "ANCHOR_SIFT_BYPASS"


def private_root():
    """The closed corpus, taken from the first of three places that has it.

    ANCHOR_SIFT_PRIVATE wins, for a checkout that keeps it somewhere of its own. Then the clone
    get_deps leaves under deps/, the route onto a machine that only consumes it. Then the authoring
    copy beside this checkout, which is where it is edited and signed before being pushed anywhere.
    """
    named = os.environ.get("ANCHOR_SIFT_PRIVATE")
    if named:
        return os.path.abspath(named)
    for candidate in (os.path.join(ROOT, "deps", "salishan_corpus"),
                      os.path.join(os.path.dirname(ROOT), "private_repos", "salishan_corpus")):
        if os.path.isdir(candidate):
            return candidate
    return os.path.join(ROOT, "deps", "salishan_corpus")


def digest(path):
    state = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            state.update(block)
    return state.hexdigest()


def recorded(root):
    """Both inventories, as path against its hash. They do not overlap."""
    held = {}
    for name in MANIFESTS:
        target = os.path.join(root, name)
        if not os.path.isfile(target):
            continue
        with io.open(target, encoding="utf-8") as handle:
            header = None
            for line in handle:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if header is None:
                    header = parts
                    continue
                row = dict(zip(header, parts))
                if row.get("path"):
                    held[row["path"]] = row.get("sha256", "")
    return held


def reachable(target):
    """Every file under one build/ path, as its path relative to that root."""
    held = {}
    if not os.path.isdir(target):
        return held
    for holder, dirs, names in os.walk(target):
        dirs[:] = [one for one in dirs if one not in (".git", "__pycache__")]
        for one in sorted(names):
            full = os.path.join(holder, one)
            held[os.path.relpath(full, target).replace("\\", "/")] = full
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    quiet = "--quiet" in sys.argv
    bypassing = ("--bypass" in sys.argv) or bool(os.environ.get(BYPASS_ENV))
    source = private_root()

    out.write("\n  %s\n" % source.replace("\\", "/"))
    if not os.path.isdir(source):
        out.write("  not there. Clone the closed corpus, or set ANCHOR_SIFT_PRIVATE.\n")
        out.write("  Everything here that does not read a paper or a table still runs.\n\n")
        out.flush()
        return 0 if bypassing else 2

    hashes = recorded(source)
    if not hashes:
        out.write("  no %s. Run maint/corpus/corpus_manifest.py --write first.\n\n"
                  % " or ".join(MANIFESTS))
        out.flush()
        return 0 if bypassing else 2

    unsigned = [one for one in MANIFESTS
                if os.path.isfile(os.path.join(source, one))
                and not os.path.isfile(os.path.join(source, one + ".asc"))]

    matched = 0
    missing = []
    changed = []
    unrecorded = []
    unlinked = []

    for name, target in WANTED:
        if os.path.isdir(target) and not os.path.islink(target):
            unlinked.append(os.path.relpath(target, ROOT).replace("\\", "/"))
        found = reachable(target)
        under = {one[len(name) + 1:]: one for one in hashes if one.startswith(name + "/")}
        for rest, key in sorted(under.items()):
            full = found.pop(rest, None)
            if full is None:
                missing.append(key)
                continue
            if digest(full) != hashes[key]:
                changed.append(key)
                continue
            matched += 1
        for rest in sorted(found):
            unrecorded.append("%s/%s" % (name, rest))

    out.write("    %d file(s) match the signed inventory\n" % matched)
    for one in unsigned:
        out.write("    %s is not signed\n" % one)

    for label, held in (("missing", missing), ("changed", changed),
                        ("unrecorded", unrecorded), ("unlinked", unlinked)):
        if not held:
            continue
        out.write("\n  %s (%d)\n" % (label.upper(), len(held)))
        for one in sorted(held)[:20]:
            out.write("    %s\n" % one)
        if len(held) > 20:
            out.write("    and %d more\n" % (len(held) - 20))

    trouble = missing or changed or unrecorded or unlinked
    if trouble:
        if bypassing:
            out.write("\n  build/ and the signature disagree. Bypassed.\n\n")
            out.flush()
            return 0
        out.write("\n  build/ does not reach what the signature covers.\n")
        out.write("  to commit without answering it:  %s=1 git commit ...\n\n" % BYPASS_ENV)
        out.flush()
        return 1

    if not quiet:
        out.write("\n  build/ reaches exactly the corpus those signatures cover.\n")
    out.write("\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
