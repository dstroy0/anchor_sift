#!/usr/bin/env python3
# repotools-stamp: repo/repo_maint/corpus_manifest.py c0985e7ee26eb5cf
# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The master inventory of the private corpus, and the check that reconciles a tree against it.
#
#   python maint/corpus/corpus_manifest.py            reconcile, and say what disagrees
#   python maint/corpus/corpus_manifest.py --write    rewrite the inventory from what is on disk
#   python maint/corpus/corpus_manifest.py --root D   work on the tree at D
#   python maint/corpus/corpus_manifest.py --bypass   answer the gate without satisfying it
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
# TWO TREES TAKE THIS
#
# salishan_corpus holds the hand extractions and the papers they were read off. anchor_sift_citations
# holds the math the measurements are built on, which is published work under its own copyright and
# is closed for that reason and not for the community one. The reasons differ and the inventory does
# not: both answer the question of which exact bytes a number was taken over, and both are signed at
# the inventory so the answer survives the file. --root picks the tree.
#
# WHAT RECONCILING CATCHES
#
# Three disagreements, and each one is a different mistake:
#
#   missing      the inventory lists it and the tree does not have it. Something was deleted, or a
#                checkout is partial, and any measurement citing it is now unreproducible.
#   unrecorded   the tree has it and the inventory does not. A file arrived without being entered,
#                and an untracked table ends up inside a published result that way.
#   changed      both have it and the bytes differ. A repair was applied and the inventory was not
#                rewritten, so every hash quoted since is wrong.
#
# Any of the three exits non-zero, leaving it usable as a commit gate. Run it with no
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
AUDIO = "AUDIO_MANIFEST.tsv"

# The directory the audio inventory covers, and the one the main inventory leaves alone.
SPEECH = "speech"

# Two inventories, each signed on its own: the name, and what it covers.
#
# Recordings are inventoried apart from the rest because they answer to a different question. A
# paper is somebody's copyright and stays put. A recording is a person talking, held on terms that
# community can change, and a withdrawal takes recordings out without touching a single paper.
# Separate files mean that withdrawal rewrites and re-signs one inventory, and the signature over
# everything else still verifies against bytes nobody moved.
INVENTORIES = ((NAME, False), (AUDIO, True))

# The one way past the gate, spelled the same here and in citations.py because a person who has
# met one of them should not have to learn a second name for the same thing. The variable is how
# the flag reaches a commit hook, where nobody is typing arguments.
BYPASS_ENV = "ANCHOR_SIFT_BYPASS"

# Written by the tool and never entered as content, so they are not themselves inventoried.
# __pycache__ joined this list once the corpus started carrying code. A .pyc is generated, it
# changes with the interpreter version, and inventorying one puts a file in the record that moves
# without anybody touching the corpus.
#
# build/ is here for a different reason. A sound representation is a derivation of a recording and
# it is faithful enough to put the recording back, so it stays inside the closed repository and is
# never written into a public tree. It is not inventoried and not committed: what the record has
# to pin is the recording and the code, and the derivation follows from those two.
IGNORED = (NAME, NAME + ".asc", AUDIO, AUDIO + ".asc", ".git", ".gitignore", "hooks",
           "README.md", "__pycache__", "build")


def rows_in(path):
    """Data rows of a tab separated table, or an empty string for anything else.

    Taking line one as the header and counting everything after it was wrong for a table that
    opens with a comment block. SOURCES.tsv has nine of those and reported 28 rows against its 18
    sources. The header is the first line that is neither blank nor a comment, and the count is
    what comes after that.
    """
    if not path.endswith(".tsv"):
        return ""
    count = 0
    header = False
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            if not header:
                header = True
                continue
            count += 1
    return str(count)


def digest(path):
    """The SHA-256 of one file, read in blocks. A 40 MB PDF never lands in memory whole."""
    state = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            state.update(block)
    return state.hexdigest()


def walk(root, speech):
    """Every file one inventory covers, as a path relative to the tree, in sorted order.

    speech True gives only the recordings under speech/. False gives everything except them. The
    two together are the whole tree, and neither one overlaps the other.
    """
    held = []
    for base, dirs, names in os.walk(root):
        dirs[:] = [one for one in dirs if one not in IGNORED]
        for name in sorted(names):
            if name in IGNORED:
                continue
            full = os.path.join(base, name)
            shown = os.path.relpath(full, root).replace("\\", "/")
            under = shown.split("/")[0] == SPEECH
            if under == speech:
                held.append(shown)
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


def read_manifest(root, name=NAME):
    """The inventory as it stands, keyed by path. An absent file is an empty inventory."""
    target = os.path.join(root, name)
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


def write_manifest(root, rows, out, name=NAME):
    """One inventory, sorted by path, with the totals it is worth stating once."""
    target = os.path.join(root, name)
    total = sum(int(one["bytes"]) for one in rows.values())
    tables = [one for one in rows.values() if one["rows"]]
    with io.open(target, "w", encoding="utf-8", newline="\n") as handle:
        # Two closed repositories take this tool, so the line names the one it was pointed at.
        # A citations inventory headed "the private Salishan corpus" is a false statement about
        # what was signed, and the signature is the whole reason the header is read.
        handle.write("# %s of %s.\n"
                     % ("Recordings" if name == AUDIO else "Master inventory",
                        os.path.basename(root.rstrip("/\\"))))
        handle.write("# Rewritten by maint/corpus/corpus_manifest.py --write in anchor_sift.\n")
        handle.write("# Reconciled before every commit. Sign this file, not the corpus.\n")
        if name == AUDIO:
            handle.write("#\n")
            handle.write("# Recordings are inventoried apart from the rest. A withdrawal takes\n")
            handle.write("# recordings out and touches no paper, so it rewrites and re-signs this\n")
            handle.write("# file alone and the other signature still verifies.\n")
            handle.write("# Permission for each source is in SPEECH.tsv. Being listed here is a\n")
            handle.write("# record of what is held and is not a permission.\n")
        handle.write("#\n")
        handle.write("# %d files, %d bytes, %d tables holding %d rows.\n"
                     % (len(rows), total, len(tables),
                        sum(int(one["rows"]) for one in tables)))
        handle.write("\t".join(FIELDS))
        handle.write("\n")
        for one in sorted(rows):
            handle.write("\t".join(rows[one][field] for field in FIELDS))
            handle.write("\n")
    out.write("  %s\n" % os.path.join(root, name).replace("\\", "/"))
    out.write("    %d files, %d bytes\n" % (len(rows), total))
    if tables:
        out.write("    %d tables, %d rows\n"
                  % (len(tables), sum(int(one["rows"]) for one in tables)))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    bypassing = ("--bypass" in sys.argv) or bool(os.environ.get(BYPASS_ENV))
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
        out.write("  set --root, or clone it there.\n")
        if bypassing:
            out.write("  bypassed.\n\n")
            out.flush()
            return 0
        out.write("  to commit without answering it:  %s=1 git commit ...\n\n" % BYPASS_ENV)
        out.flush()
        return 2

    out.write("\n  %s\n" % root.replace("\\", "/"))

    if "--write" in sys.argv:
        for name, speech in INVENTORIES:
            found = walk(root, speech)
            if not found and speech:
                continue
            write_manifest(root, measured(root, found), out, name)
            out.write("    sign it:  gpg --armor --detach-sign --yes %s\n" % name)
        out.write("\n")
        out.flush()
        return 0

    missing = []
    unrecorded = []
    changed = []
    counted = 0
    for name, speech in INVENTORIES:
        on_disk = walk(root, speech)
        recorded = read_manifest(root, name)
        if not on_disk and not recorded:
            continue
        counted += 1
        if not recorded:
            out.write("    %s covers %d file(s) and does not exist yet\n" % (name, len(on_disk)))
            unrecorded.extend(on_disk)
            continue
        shared = [one for one in on_disk if one in recorded]
        fresh = measured(root, shared)
        missing.extend(one for one in recorded if one not in set(on_disk))
        unrecorded.extend(one for one in on_disk if one not in recorded)
        changed.extend(one for one in shared
                       if fresh[one]["sha256"] != recorded[one].get("sha256"))
        out.write("    %-20s %3d file(s) on disk, %3d in the inventory\n"
                  % (name, len(on_disk), len(recorded)))

    if not counted:
        out.write("  no inventory yet. Run with --write.\n\n")
        out.flush()
        return 2

    for label, held in (("missing", missing), ("unrecorded", unrecorded), ("changed", changed)):
        if not held:
            continue
        out.write("\n  %s (%d)\n" % (label.upper(), len(held)))
        for one in sorted(held)[:40]:
            out.write("    %s\n" % one)
        if len(held) > 40:
            out.write("    and %d more\n" % (len(held) - 40))

    if missing or unrecorded or changed:
        if bypassing:
            out.write("\n  the tree and the inventory disagree. Bypassed, and nothing is signed.\n\n")
            out.flush()
            return 0
        out.write("\n  the tree and the inventory disagree. Nothing is signed until they do not.\n")
        out.write("  to commit without answering it:  %s=1 git commit ...\n\n" % BYPASS_ENV)
        out.flush()
        return 1

    out.write("  every file is recorded and every hash matches.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
