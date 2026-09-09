#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The master inventory of the private corpus, and the check that reconciles a tree against it.
#
#   python tools/maintain/corpus_manifest.py            reconcile, and say what disagrees
#   python tools/maintain/corpus_manifest.py --write    rewrite the inventory from what is on disk
#   python tools/maintain/corpus_manifest.py --root D   work on the tree at D
#
# WHY THE INVENTORY EXISTS
#
# The hand extractions are transcribed out of published papers, so the tables are those papers' text
# and not this work's to redistribute, and the papers themselves are somebody else's copyright. They
# live in a closed repository for that reason. What this repository can carry is a record of what
# was there and what it hashed to, which is enough to tie a number in the ledger to exact bytes
# without the bytes leaving the closed repository.
#
# The record survives a withdrawal. The corpus licence says the material can be refocused on the
# communities' request and never made available again, and a hash of a file that no longer exists is
# still a true statement about what a measurement was taken over. A copy of the file would not be.
#
# WHAT RECONCILING CATCHES
#
# Three disagreements, and each one is a different mistake:
#
#   missing      the inventory lists it and the tree does not have it. Something was deleted, or a
#                checkout is partial, and any measurement citing it is now unreproducible.
#   unrecorded   the tree has it and the inventory does not. A file arrived without being entered,
#                which is how an untracked table ends up inside a published result.
#   changed      both have it and the bytes differ. A repair was applied and the inventory was not
#                rewritten, so every hash quoted since is wrong.
#
# Any of the three exits non-zero. That is what a commit gate needs. Run it with no
# argument to check, and with --write only when the disagreement is one you meant.
#
# ROW COUNTS ARE PART OF THE RECORD
#
# A tab separated table also carries its row count, not counting the header. A hash says two files
# differ and a row count says how. A reader with both can see the change instead of guessing at it.
# The count is what pure_corpus_index reports and what the derivation is denominated in.

import hashlib
import io
import os
import sys

FIELDS = ("sha256", "bytes", "rows", "path")
NAME = "MANIFEST.tsv"

# Written by the tool and never entered as content, so they are not themselves inventoried.
IGNORED = (NAME, NAME + ".asc", ".git", ".gitignore", "hooks", "README.md")


def rows_in(path):
    """Data rows of a tab separated table, or an empty string for anything else."""
    if not path.endswith(".tsv"):
        return ""
    count = 0
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        for number, line in enumerate(handle):
            if number == 0:
                continue
            if line.strip():
                count += 1
    return str(count)


def digest(path):
    """The SHA-256 of one file, read in blocks. A 40 MB PDF never lands in memory whole."""
    state = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            state.update(block)
    return state.hexdigest()


def walk(root):
    """Every inventoried file under a tree, as a path relative to it, in sorted order."""
    held = []
    for base, dirs, names in os.walk(root):
        dirs[:] = [one for one in dirs if one not in IGNORED]
        for name in sorted(names):
            if name in IGNORED:
                continue
            full = os.path.join(base, name)
            held.append(os.path.relpath(full, root).replace("\\", "/"))
    return sorted(held)


def measured(root, paths):
    """The inventory rows for a list of relative paths."""
    held = {}
    for one in paths:
        full = os.path.join(root, one)
        held[one] = {
            "sha256": digest(full),
            "bytes": str(os.path.getsize(full)),
            "rows": rows_in(full),
            "path": one,
        }
    return held


def read_manifest(root):
    """The inventory as it stands, keyed by path. An absent file is an empty inventory."""
    target = os.path.join(root, NAME)
    held = {}
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
                held[row["path"]] = row
    return held


def write_manifest(root, rows, out):
    """The inventory, sorted by path, with the totals it is worth stating once."""
    target = os.path.join(root, NAME)
    total = sum(int(one["bytes"]) for one in rows.values())
    tables = [one for one in rows.values() if one["rows"]]
    with io.open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Master inventory of the private Salishan corpus.\n")
        handle.write("# Rewritten by tools/maintain/corpus_manifest.py --write in anchor_sift.\n")
        handle.write("# Reconciled before every commit. Sign this file, not the corpus.\n")
        handle.write("#\n")
        handle.write("# %d files, %d bytes, %d tables holding %d rows.\n"
                     % (len(rows), total, len(tables),
                        sum(int(one["rows"]) for one in tables)))
        handle.write("\t".join(FIELDS))
        handle.write("\n")
        for one in sorted(rows):
            handle.write("\t".join(rows[one][field] for field in FIELDS))
            handle.write("\n")
    out.write("  %s\n" % os.path.join(root, NAME).replace("\\", "/"))
    out.write("    %d files, %d bytes\n" % (len(rows), total))
    out.write("    %d tables, %d rows\n"
              % (len(tables), sum(int(one["rows"]) for one in tables)))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    root = None
    if "--root" in sys.argv:
        root = sys.argv[sys.argv.index("--root") + 1]
    if root is None:
        here = os.path.dirname(os.path.abspath(__file__))
        while (here != os.path.dirname(here)) and not os.path.isdir(os.path.join(here, "build")):
            here = os.path.dirname(here)
        root = os.path.join(os.path.dirname(here), "private_repos", "salishan_corpus")
    root = os.path.abspath(root)

    if not os.path.isdir(root):
        out.write("\n  no private corpus at %s\n" % root.replace("\\", "/"))
        out.write("  set --root, or clone it there.\n\n")
        out.flush()
        return 2

    out.write("\n  %s\n" % root.replace("\\", "/"))
    on_disk = walk(root)
    recorded = read_manifest(root)

    if "--write" in sys.argv:
        write_manifest(root, measured(root, on_disk), out)
        out.write("\n  sign it:  gpg --armor --detach-sign %s\n\n" % NAME)
        out.flush()
        return 0

    if not recorded:
        out.write("  no inventory yet. Run with --write.\n\n")
        out.flush()
        return 2

    missing = [one for one in recorded if one not in set(on_disk)]
    unrecorded = [one for one in on_disk if one not in recorded]
    shared = [one for one in on_disk if one in recorded]
    fresh = measured(root, shared)
    changed = [one for one in shared if fresh[one]["sha256"] != recorded[one].get("sha256")]

    out.write("    %d file(s) on disk, %d in the inventory\n" % (len(on_disk), len(recorded)))
    for label, held in (("missing", missing), ("unrecorded", unrecorded), ("changed", changed)):
        if not held:
            continue
        out.write("\n  %s (%d)\n" % (label.upper(), len(held)))
        for one in sorted(held)[:40]:
            out.write("    %s\n" % one)
        if len(held) > 40:
            out.write("    and %d more\n" % (len(held) - 40))

    if missing or unrecorded or changed:
        out.write("\n  the tree and the inventory disagree. Nothing is signed until they do not.\n\n")
        out.flush()
        return 1

    out.write("  every file is recorded and every hash matches.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
