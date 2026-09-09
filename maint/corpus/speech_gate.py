#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Refuse recorded speech that the community it came from has not said we may hold.
#
#   python maint/corpus/speech_gate.py           what is held, and under whose permission
#   python maint/corpus/speech_gate.py --check   fail while a file sits under no granted source
#   python maint/corpus/speech_gate.py --bypass  answer the gate without satisfying it
#
# WHY THE PERMISSION IS A GATE
#
# The papers here are under copyright, which is answered by not redistributing them. A recording
# is a separate question. Nations hold their own archives and an administrator sets file by file
# what is public, and that setting is the condition this corpus records per table.
#
# Reachable and holdable are two different states. They come apart when a directory is fetched
# because it answered, so the permission is checked at commit time instead of remembered.
#
# HOW A FILE IS TIED TO A PERMISSION
#
# speech/<source key>/... , where the source key is the address column of SPEECH.tsv cut down to
# its host, or the body where there is no address. One directory per source. The tie is the path,
# and there is no second list to keep in step.
#
# SCOPE
#
# This gate covers reconstruction. The public tree carries what an outsider needs to rebuild the
# corpus, and this decides what may be in it: a recording is holdable when the community it came
# from has granted it, and SPEECH.tsv carries the terms.
#
# It does not cover regeneration. That is governed by distribution: the code that produces the
# representation lives in the closed repository under the terms in its LICENSE. No check here
# detects a fitted model.
#
# WHAT THIS DOES NOT DO
#
# It does not check that a permission is real. A person writing "granted" in a column they filled
# in themselves is taken at their word; the alternative is a checker pretending to audit consent.
# What it catches is material arriving with nobody having asked.

import io
import os
import sys
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

NAME = "SPEECH.tsv"
SPEECH = "speech"
BYPASS_ENV = "ANCHOR_SIFT_BYPASS"

# What counts as holdable, and the two are not the same claim.
#
#   granted    a community said we may hold it. The strongest basis and the only one that can
#              cover a recording that was never public.
#   published  it was published with its paper, is held here for calculation, and is not
#              redistributed. No community was asked, because the publication is the basis.
#
# They are reported apart so nobody reads a published row as a community grant later. A withdrawal
# request reaches both: publication is a basis for holding and it is not a waiver of anything.
GRANTED = "granted"
PUBLISHED = "published"
HOLDABLE = (GRANTED, PUBLISHED)


def private_root():
    """The closed corpus, resolved the way private_sync.py resolves it."""
    named = os.environ.get("ANCHOR_SIFT_PRIVATE")
    if named:
        return os.path.abspath(named)
    for candidate in (os.path.join(ROOT, "deps", "salishan_corpus"),
                      os.path.join(os.path.dirname(ROOT), "private_repos", "salishan_corpus")):
        if os.path.isdir(candidate):
            return candidate
    return os.path.join(ROOT, "deps", "salishan_corpus")


def key_of(row):
    """The directory name one source's recordings live under.

    The host out of the address, because that is stable and short, and the body's name where there
    is no address. A source with neither cannot hold anything and is a row waiting to be filled in.
    """
    address = (row.get("address") or "").strip()
    if address:
        rest = address.split("://", 1)[-1]
        return rest.split("/", 1)[0].lower()
    # A body with no address becomes a directory name, so it is lowercased and its spaces closed.
    # "ICSNL proceedings" as a literal directory is a path with a space in it on every tool that
    # touches it.
    return "_".join((row.get("body") or "").strip().lower().split())


def read_register(root):
    """SPEECH.tsv as source key against the row, and every row for reporting."""
    target = os.path.join(root, NAME)
    rows = []
    if not os.path.isfile(target):
        return rows
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
            rows.append(dict(zip(header, parts)))
    return rows


def held_under(root):
    """Every file under speech/, as the source key it sits in against its paths."""
    base = os.path.join(root, SPEECH)
    held = {}
    if not os.path.isdir(base):
        return held
    for where, dirs, names in os.walk(base):
        dirs[:] = [one for one in dirs if one != "__pycache__"]
        for name in sorted(names):
            full = os.path.join(where, name)
            shown = os.path.relpath(full, root).replace("\\", "/")
            parts = shown.split("/")
            # speech/<key>/... , and a file dropped straight into speech/ has no key at all.
            key = parts[1] if len(parts) > 2 else ""
            held.setdefault(key, []).append(shown)
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    checking = "--check" in sys.argv
    bypassing = ("--bypass" in sys.argv) or bool(os.environ.get(BYPASS_ENV))

    root = private_root()
    out.write("\n  %s\n" % root.replace("\\", "/"))
    if not os.path.isdir(root):
        out.write("  no closed corpus there, so there is nothing to gate.\n\n")
        out.flush()
        return 0

    rows = read_register(root)
    if not rows:
        out.write("  no %s. Nothing may be held under speech/ until there is one.\n\n" % NAME)
        out.flush()
        return 0 if not held_under(root) else 1

    granted = {}
    for row in rows:
        if (row.get("permission") or "").strip().lower() in HOLDABLE:
            granted[key_of(row)] = row

    asked = sum(1 for row in rows
                if (row.get("permission") or "").strip().lower() not in ("", "not asked"))
    out.write("    %d source(s) in the register, %d asked, %d holdable "
              "(%d granted, %d published)\n"
              % (len(rows), asked, len(granted),
                 sum(1 for one in granted.values()
                     if (one.get("permission") or "").strip().lower() == GRANTED),
                 sum(1 for one in granted.values()
                     if (one.get("permission") or "").strip().lower() == PUBLISHED)))

    held = held_under(root)
    total = sum(len(one) for one in held.values())
    out.write("    %d file(s) under %s/\n" % (total, SPEECH))

    ungranted = {}
    for key, paths in held.items():
        if key not in granted:
            ungranted[key] = paths

    for key, row in sorted(granted.items()):
        basis = (row.get("permission") or "").strip().lower()
        out.write("\n  %-9s %s\n" % (basis.upper(), key or "no key"))
        if basis == GRANTED:
            out.write("      by %s on %s\n" % (row.get("granted_by") or "nobody named",
                                               row.get("granted_on") or "no date"))
        else:
            out.write("      no community was asked. The publication is the basis.\n")
        if row.get("terms"):
            for line in textwrap.wrap(row["terms"], 86):
                out.write("      %s\n" % line)
        out.write("      %d file(s) held\n" % len(held.get(key, [])))

    if ungranted:
        out.write("\n  HELD UNDER NO GRANTED SOURCE (%d)\n" % sum(len(one)
                                                                  for one in ungranted.values()))
        for key in sorted(ungranted):
            out.write("    %s\n" % (key or "speech/ with no source directory"))
            for one in ungranted[key][:6]:
                out.write("        %s\n" % one)
            if len(ungranted[key]) > 6:
                out.write("        and %d more\n" % (len(ungranted[key]) - 6))

    if checking and ungranted:
        if bypassing:
            out.write("\n  held with no granted source. Bypassed.\n\n")
            out.flush()
            return 0
        out.write("\n  this material is somebody's speech and nobody has said we may hold it.\n")
        out.write("  ask them, write what they said into %s, and commit again.\n" % NAME)
        out.write("  to commit without answering it:  %s=1 git commit ...\n\n" % BYPASS_ENV)
        out.flush()
        return 1

    out.write("\n  a row is a place to ask. Held means granted by a community, or published with\n")
    out.write("  its paper and kept here to calculate over. Neither is a licence to pass it on.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
