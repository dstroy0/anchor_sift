#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# What the partition says, checked instead of remembered.
#
#   Usage:  python tools/book/check_partition.py [repository_root]
#
# The partition is a rule about which measurements reach the general public. Held as a rule someone
# remembers, it survives exactly as long as nobody builds a book without thinking about it. The name
# guard in hooks/pre-commit makes this argument about a product name and the argument is the same
# here, with a larger blast radius: a name in a banner is embarrassing, and a held chapter bound into
# a published PDF cannot be recalled from anyone who downloaded it.
#
# WHAT THIS CATCHES
#
# theory/cryptography/sha256/main.tex includes eleven chapters. Six were published from anchor_sift.
# Five postdate them and are held. Nothing in the build refuses that combination, so `build_theory.sh`
# produces one PDF carrying both halves and looking finished. That is the defect this exists for.
#
# HOW IT FAILS
#
# Closed, in three directions. An unlisted artifact is HELD, so a new document is private until
# somebody classifies it and never public by being forgotten. PENDING is HELD, so an undecided
# judgment call cannot reach a public build by nobody getting round to the decision. A missing or
# unreadable manifest refuses the run outright, because a gate that skips itself when its input moves
# is worse than no gate: every build after that passes while still looking gated.
#
# Exit status is the count of findings, so it fails a pipeline without needing a flag.

import os
import re
import sys

MANIFEST = os.path.join("theory", "PARTITION.tsv")

# Order matters. A book takes the strictest class of anything it reaches, and strictness increases
# down this list.
#
# EXTERNAL is the precision work: arbitrary-precision arithmetic, the certified NTT moduli, integer
# relation detection. Douglas ruled it fair on 2026-09-11 - "precision fair" - because a
# general-purpose multiply does not reveal what it is aimed at, and the advantage is the aiming.
#
# It ranks with PUBLIC and not below it. PUBLIC means already published in anchor_sift and therefore
# settled; EXTERNAL means cleared for publication and not yet out. Neither constrains a book, so they
# carry the same strictness, and keeping them distinct is what lets "cleared but unpublished" be
# counted rather than assumed.
#
# An unknown class is NOT silently ranked. `strictest` used to reach into this table directly, so a
# typo in the manifest would have produced a KeyError at best and a wrong rank at worst; classify()
# now refuses a class this table does not name.
RANK = {"PUBLIC": 0, "EXTERNAL": 0, "PENDING": 1, "HELD": 2}

# \include{chapters/foo} and \input{../macros.tex}. The argument is a path with the extension
# usually left off, which is how LaTeX writes it.
INCLUDE = re.compile(r"\\(?:include|input|subfile)\s*\{([^}]+)\}")

# Prose that a build could reach. A .py or .cu file is not bound into a PDF, so it is out of scope
# here and governed by the license instead.
PROSE = (".tex", ".md")

# Directories holding nothing a reader receives.
SKIP = {".git", "build", "__pycache__", "node_modules", "logs", "audit"}


def read_manifest(root):
    """Reads PARTITION.tsv into {normalised path: (class, reason)}.

    Returns None when the manifest cannot be read, which the caller turns into a refusal. A parse
    that quietly returns an empty mapping would classify the entire tree as unlisted, and unlisted
    is HELD, so the run would report every file as a finding and bury the real cause.
    """
    full = os.path.join(root, MANIFEST)
    if not os.path.isfile(full):
        return None

    entries = {}
    with open(full, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 3:
                continue
            # AN UNKNOWN CLASS IS REPORTED, NOT SKIPPED. Skipping it silently is fail-closed, since
            # the row then falls through to unlisted-is-HELD - but it is also invisible, so a
            # misspelled class holds a file while its author believes it was classified. That bit
            # for real: the fifteen EXTERNAL rows added on 2026-09-11 were dropped by this line
            # until RANK learned the class, and nothing said so.
            #
            # A file quietly held is the safe direction and still the wrong outcome, because the
            # manifest is the record of a decision and a decision that did not take is not recorded.
            if fields[1] == "class":
                continue                      # the column header, which carries no leading hash
            if fields[1] not in RANK:
                print("  MANIFEST: unknown class %r for %s, treated as unlisted and therefore HELD"
                      % (fields[1], fields[0]))
                continue

            # A SECOND ROW FOR ONE PATH IS REPORTED. This dict silently keeps the last row for a
            # path, so two rows disagreeing about a file resolve to whichever sits lower with no
            # sign that the other existed. That happened: docs/twiddle-proof.md was appended as
            # EXTERNAL while an older HELD row for it stood twelve lines up, and the file's class
            # then depended on line order alone.
            #
            # Silent last-write-wins is the wrong failure whichever way it lands. If the later row is
            # right the manifest still carries a contradiction; if the earlier one is right a file is
            # published on a row nobody meant to keep.
            key = normalise(fields[0])
            if key in entries:
                print("  MANIFEST: %s listed twice, as %s and %s; the later row wins"
                      % (fields[0], entries[key][0], fields[1]))
            entries[key] = (fields[1], fields[3] if len(fields) > 3 else "")
    return entries


def normalise(path):
    """One spelling for one file, so a manifest row and a walked path compare equal."""
    return os.path.normpath(path).replace("\\", "/").lstrip("./")


def classify(path, manifest):
    """The class of one artifact. Unlisted is HELD, stated here once so the default is visible."""
    return manifest.get(normalise(path), ("HELD", "not listed in the manifest"))


def resolve(argument, build_dir, root):
    """Turns a LaTeX include argument into a path on disk.

    LaTeX resolves every path against the directory the compiler was invoked from, and not against
    the file holding the include. theory/preamble.tex says `\\input{../macros.tex}` and that reaches
    theory/cryptography/macros.tex when main.tex is built from theory/cryptography/sha256, which is
    the documented way to build it. An earlier version of this resolved against the including file
    and reported the shared preamble as missing on a tree where the build works.
    """
    candidate = os.path.normpath(os.path.join(build_dir, argument))
    for suffix in ("", ".tex"):
        if os.path.isfile(candidate + suffix):
            return os.path.relpath(candidate + suffix, root)
    return None


def reachable(book, root, seen=None, build_dir=None):
    """Every file a book pulls in, following includes through as many levels as they go.

    A chapter that includes a fragment puts that fragment in the book, so a check reading only the
    top level would pass a book whose held material sits one level down.
    """
    if seen is None:
        seen = []
    full = os.path.join(root, book)
    if build_dir is None:
        build_dir = os.path.dirname(full)
    if not os.path.isfile(full):
        return seen

    with open(full, encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    # A commented-out include is not in the book.
    text = re.sub(r"(?<!\\)%.*", "", text)

    for match in INCLUDE.finditer(text):
        target = resolve(match.group(1), build_dir, root)
        if target is None:
            seen.append((match.group(1), None))
            continue
        if any(target == known for known, _ in seen):
            continue
        seen.append((target, classify(target, MANIFEST_CACHE)[0]))
        reachable(target, root, seen, build_dir)
    return seen


def walk_prose(root):
    """Every .tex and .md in the tree that a build could reach."""
    found = []
    for base in ("docs", "theory", "."):
        start = os.path.join(root, base)
        if not os.path.isdir(start):
            continue
        for dirpath, dirnames, filenames in os.walk(start):
            dirnames[:] = [d for d in dirnames if d not in SKIP]
            for name in filenames:
                if name.endswith(PROSE):
                    found.append(os.path.relpath(os.path.join(dirpath, name), root))
            if base == ".":
                break
    return sorted(set(normalise(p) for p in found))


MANIFEST_CACHE = {}


def main(argv):
    global MANIFEST_CACHE

    root = argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
    root = os.path.abspath(root)

    manifest = read_manifest(root)
    if manifest is None:
        print("  partition: no manifest at %s" % os.path.join(root, MANIFEST))
        print("  the partition cannot be checked, so nothing is published from this run.")
        return 2
    MANIFEST_CACHE = manifest

    books = [p for p, (klass, _) in manifest.items() if _looks_like_book(p, manifest)]
    findings = 0
    checked = 0

    print("  partition: %d artifacts classified, %d books" % (len(manifest), len(books)))

    for book in sorted(books):
        declared = manifest[normalise(book)][0]
        if not os.path.isfile(os.path.join(root, book)):
            print("  SKIP  %s: declared in the manifest and not on disk" % book)
            continue
        checked += 1
        parts = reachable(book, root)
        worst = declared
        for target, klass in parts:
            if target is None or klass is None:
                continue
            if RANK[klass] > RANK[worst]:
                worst = klass

        if RANK[worst] > RANK[declared]:
            findings += 1
            print("")
            print("  LEAK  %s is declared %s and reaches %s material:" % (book, declared, worst))
            for target, klass in parts:
                if klass and RANK[klass] > RANK[declared]:
                    print("          %-8s %s" % (klass, target))
            print("        a build of this book puts the above in front of the general public.")
        else:
            print("  ok    %-52s %-7s (%d files)" % (book, declared, len(parts)))

        for target, klass in parts:
            if klass is None:
                findings += 1
                print("  BREAK %s includes %s, which is not on disk" % (book, target))

    unlisted = [p for p in walk_prose(root) if p not in manifest]
    if unlisted:
        print("")
        print("  %d prose artifacts are not in the manifest. Each is HELD until classified:" % len(unlisted))
        for path in unlisted:
            print("          %s" % path)
        findings += len(unlisted)

    # Checking nothing is not passing. docs_check.py learned this the expensive way and the lesson
    # transfers without modification.
    if checked == 0:
        print("  no book was read. Nothing was checked, so nothing passed.")
        return 2

    print("")
    print("  %d book(s) checked, %d finding(s)" % (checked, findings))
    return findings


def _looks_like_book(path, manifest):
    """A book is an artifact the manifest tagged as one in its subject column."""
    full = manifest.get(normalise(path))
    return bool(full) and path.endswith(".tex") and "main" in os.path.basename(path)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
