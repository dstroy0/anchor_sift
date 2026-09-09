#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Refuse recorded speech that the community it came from has not said we may hold.
#
#   python tools/maintain/speech_gate.py           what is held, and under whose permission
#   python tools/maintain/speech_gate.py --check   fail while a file sits under no granted source
#   python tools/maintain/speech_gate.py --bypass  answer the gate without satisfying it
#
# WHY THE PERMISSION IS A GATE
#
# The papers here are under copyright, and copyright is answered by not redistributing them. A
# recording is a different question. It is a person talking, held by their nation, and the nations
# put their archives behind an administrator who sets file by file what is public. That setting is
# the condition the speakers set, which this corpus already records per table.
#
# Reachable and ours to hold are two different things, and they come apart when somebody fetches a
# directory because it answered. A gate is how the difference gets checked instead of remembered.
#
# HOW A FILE IS TIED TO A PERMISSION
#
# speech/<source key>/... , where the source key is the address column of SPEECH.tsv cut down to
# its host, or the body where there is no address. One directory per source. The tie is the path,
# and there is no second list to keep in step.
#
# WHAT THIS DOES NOT DO
#
# It does not check that a permission is real. A person writing "granted" in a column they filled
# in themselves is taken at their word; the alternative is a checker pretending to audit consent.
# What it catches is material arriving with nobody having asked.

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

NAME = "SPEECH.tsv"
SPEECH = "speech"
BYPASS_ENV = "ANCHOR_SIFT_BYPASS"

GRANTED = "granted"


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
    return (row.get("body") or "").strip()


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
        if (row.get("permission") or "").strip().lower() == GRANTED:
            granted[key_of(row)] = row

    asked = sum(1 for row in rows
                if (row.get("permission") or "").strip().lower() not in ("", "not asked"))
    out.write("    %d source(s) in the register, %d asked, %d granted\n"
              % (len(rows), asked, len(granted)))

    held = held_under(root)
    total = sum(len(one) for one in held.values())
    out.write("    %d file(s) under %s/\n" % (total, SPEECH))

    ungranted = {}
    for key, paths in held.items():
        if key not in granted:
            ungranted[key] = paths

    for key, row in sorted(granted.items()):
        out.write("\n  GRANTED  %s\n" % (key or "no key"))
        out.write("      by %s on %s\n" % (row.get("granted_by") or "nobody named",
                                           row.get("granted_on") or "no date"))
        if row.get("terms"):
            out.write("      terms: %s\n" % row["terms"][:88])
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

    out.write("\n  a row is a place to ask. Only what a community granted may be held.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
