#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Bring the closed corpus into build/, checking every file against the signed inventory on the way.
#
#   python tools/maintain/private_sync.py           copy what is missing or wrong
#   python tools/maintain/private_sync.py --check   say what would happen and copy nothing
#
# WHERE THE CORPUS IS
#
# ANCHOR_SIFT_PRIVATE names it. Without that, ../private_repos/salishan_corpus beside this checkout.
# The papers are somebody else's copyright and the hand extractions are transcribed out of those
# papers, so neither is this work's to redistribute and neither is in the public repository.
#
# WHY A COPY AND NOT A LINK
#
# A junction would put the corpus in one place and cost nothing, and it would also mean that an
# `rm -rf build/` walks into the closed repository and deletes 12,338 rows of work that took a
# person months and cannot be fetched again from anywhere. build/ is the directory this tree treats
# as disposable. Nothing irreplaceable is reachable through it.
#
# WHAT THE CHECK IS FOR
#
# Every copy is verified against the SHA-256 in MANIFEST.tsv, the file the corpus owner signs. After
# a clean run the bytes under build/ are the bytes that signature covers, and a number measured here
# ties to that signature.
#
# A file already present with the right hash is left alone. A second run costs one pass of hashing
# and no copying.

import hashlib
import io
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

# What lands where. The corpus keeps its own names and build/ mirrors them one level down.
WANTED = (("oracles", os.path.join(ROOT, "build", "oracles")),
          ("papers", os.path.join(ROOT, "build", "papers")))

MANIFEST = "MANIFEST.tsv"


def private_root():
    """The closed corpus, taken from the first of three places that has it.

    ANCHOR_SIFT_PRIVATE wins, for a checkout that keeps it somewhere of its own. Then the clone
    get_deps leaves under deps/, the route onto a machine that only consumes it. Then
    the authoring copy beside this checkout, which is where it is edited and signed before being
    pushed anywhere.
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
    """The inventory, as path against its hash."""
    held = {}
    target = os.path.join(root, MANIFEST)
    if not os.path.isfile(target):
        return held
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


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    check = "--check" in sys.argv
    source = private_root()

    out.write("\n  %s\n" % source.replace("\\", "/"))
    if not os.path.isdir(source):
        out.write("  not there. Clone the closed corpus, or set ANCHOR_SIFT_PRIVATE.\n")
        out.write("  Everything in this repository that does not read papers or tables still runs.\n\n")
        out.flush()
        return 2

    hashes = recorded(source)
    if not hashes:
        out.write("  no %s. Run tools/maintain/corpus_manifest.py --write first.\n\n" % MANIFEST)
        out.flush()
        return 2

    if not os.path.isfile(os.path.join(source, MANIFEST + ".asc")):
        out.write("  the inventory is not signed. Copying anyway, and saying so.\n")

    copied = 0
    fresh = 0
    absent = []
    unrecorded = []

    for name, target in WANTED:
        base = os.path.join(source, name)
        if not os.path.isdir(base):
            absent.append(name)
            continue
        for holder, dirs, names in os.walk(base):
            dirs[:] = [one for one in dirs if one != ".git"]
            for one in sorted(names):
                full = os.path.join(holder, one)
                under = os.path.relpath(full, base).replace("\\", "/")
                key = "%s/%s" % (name, under)
                want = hashes.get(key)
                if want is None:
                    unrecorded.append(key)
                    continue
                landing = os.path.join(target, under)
                if os.path.isfile(landing) and digest(landing) == want:
                    fresh += 1
                    continue
                if check:
                    copied += 1
                    continue
                os.makedirs(os.path.dirname(landing), exist_ok=True)
                shutil.copy2(full, landing)
                if digest(landing) != want:
                    out.write("  HASH MISMATCH AFTER COPY  %s\n" % key)
                    out.flush()
                    return 1
                copied += 1

    out.write("    %d already current\n" % fresh)
    out.write("    %d %s\n" % (copied, "would be copied" if check else "copied"))
    for name in absent:
        out.write("    no %s/ in the corpus\n" % name)
    if unrecorded:
        out.write("\n  ON DISK AND NOT IN THE INVENTORY (%d), not copied\n" % len(unrecorded))
        for one in sorted(unrecorded)[:20]:
            out.write("    %s\n" % one)
        out.write("  rewrite the inventory in the corpus before trusting a measurement.\n")

    out.write("\n  build/oracles and build/papers now hold what the signature covers.\n\n")
    out.flush()
    return 1 if unrecorded else 0


if __name__ == "__main__":
    raise SystemExit(main())
