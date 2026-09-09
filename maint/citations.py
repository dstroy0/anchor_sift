#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The registry of the mathematics this work rests on, and what is used here without a reference.
#
#   python maint/citations.py           what is registered, and what is used and is not
#   python maint/citations.py --seed    enter the names found in the tree, fields empty
#   python maint/citations.py --check   fail while a name is used and unregistered
#   python maint/citations.py --bypass  answer the gate without satisfying it
#
# THE GATE REFUSES, AND --bypass IS THE WAY PAST
#
# --check refuses a commit two ways: a name used here with no row, and the closed repository absent
# so the question cannot be asked at all. The second one catches everybody outside this work, and
# the flag is there for them. ANCHOR_SIFT_BYPASS=1 carries it into a commit hook, where nobody is
# typing arguments. A bypass says so in the output every time and never changes the registry.
#
# WHY A REGISTRY AND NOT A COMMENT
#
# A surname in a comment is not a citation. "the Zipf slope" tells a reader which idea is being
# used and gives them nothing to go and read, and the tree has 39 of those for Zipf alone. What
# turns one into a reference is an author, a year, a title and an identifier a reader can follow,
# and none of those four is derivable from the surname. They are entered by hand, once, by somebody
# who has the source open.
#
# This is the same question the Salishan check asks, one domain over. corpus_crossref asks whether
# the person whose language a form is has been named. This asks whether the person whose result a
# measurement is has been named. Neither is answerable by a heuristic, and both are owed.
#
# WHAT IS AUTOMATIC AND WHAT IS NOT
#
# uses and first_use are facts about this tree, so they are recomputed every run. Everything else
# is the owner's and is never overwritten. A row entered by --seed carries its key, no author, no
# year and no title. That is the honest state of a source nobody has looked up, and it holds until
# somebody looks it up.
#
# APPEND ONLY, LIKE THE CATALOG NEXT DOOR
#
# A key is entered once. A source that stops being used keeps its row and is reported as unused,
# because a reference already written down somewhere else still resolves to it. Nothing is deleted
# by this tool.
#
# HOW A NEW SOURCE IS FOUND
#
# The registry's own keys are the vocabulary, matched as whole words. That finds nothing new by
# itself. A second pass reads the citation shape, a capitalized name against a year, and reports
# any that no key covers. That is how a source added to the tree next month turns up here without
# an edit to this file.
#
# WHERE THE REGISTRY LIVES
#
# In the closed citations repository, beside the sources themselves, resolved the way
# private_sync.py resolves the corpus. Those sources are published work under their authors'
# copyright. The corpus next door is closed for a different reason. Both carry the same inventory:
# MANIFEST.tsv records every file, and the signature covers it.

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

NAME = "SOURCES.tsv"

# The one way past the gate. A flag reaches the tool when a person runs it, and the variable is how
# the same flag reaches it from inside a commit hook, where nobody is typing arguments.
BYPASS_ENV = "ANCHOR_SIFT_BYPASS"
FIELDS = ("key", "bucket", "author", "year", "title", "identifier", "file", "uses", "first_use")

# bucket is field then category, written as one path: physics/information_theory. It is entered by
# hand from what a source is used for in this tree, which is not always what the name suggests.
# Fisher here is the Fisher-Yates shuffle in a lattice bench, not Fisher information. Kolmogorov is
# the Kolmogorov-Sinai entropy of a partition, not Kolmogorov complexity.
#
# Language sources take a third level, language/<language>/<subcat>, because the language is the
# thing somebody looking for a source searches on and it sits below the field. A corpus covering
# many languages at once takes multilingual in that slot. Two levels are enough everywhere else.
#
# The bucket is also the path under sources/ where a copy of that source goes.
BUCKET = re.compile(r"^[a-z_]+(/[a-z_]+){1,3}$")

# The owner's columns. --seed writes them empty and no run of this tool ever writes them again.
ENTERED = ("bucket", "author", "year", "title", "identifier", "file")

# Where this tree's own writing lives. build/ is fetched material and deps/ is somebody else's.
SEARCHED = ("theory", "docs", "src", "tools", "examples", "README.md", "SECURITY.md",
            "CONTRIBUTING.md")
SKIP = ("__pycache__", ".git", "build", "deps", "site")
TEXT = (".md", ".tex", ".py", ".c", ".h", ".R", ".m", ".sh", ".bib")

# The names to enter on a first --seed. After that the registry is the vocabulary and this list is
# only the starting point, kept so an empty registry can be rebuilt from nothing.
STARTING = (
    "Bloom", "Boyer", "Crystallography Open Database", "Fisher", "Heaps", "Horspool", "Jaynes",
    "Kac", "Kolmogorov", "Montemurro", "Moore", "NIST SP 800-90B", "RFC 6234", "Renyi", "Rényi",
    "Shannon", "Sinai", "Wycheproof", "Zanette", "Zipf",
)

# The same source written two ways is one source. The registry key is on the right.
SAME = {"Rényi": "Renyi"}

# A capitalized name against a year, the form somebody writes a citation in.
# It finds sources this file has never heard of, and it also finds every date in the tree, so what
# it reports is a list to read and not a list to enter.
SHAPED = re.compile(r"\b([A-Z][A-Za-zéáíóúüñ]{3,}"
                    r"(?:(?: and | & |, )[A-Z][A-Za-zéáíóúüñ]{3,})*),? \(?((?:19|20)[0-9]{2})\)?")

# Words that open the citation shape and are not names. Months and the like.
NOT_A_NAME = frozenset((
    "January", "February", "March", "April", "June", "July", "August", "September", "October",
    "November", "December", "Recorded", "English", "Languages", "Copyright", "Version", "Retrieved",
    "Accessed", "Updated", "Published", "Since", "Before", "After", "Between", "During",
))


def private_root():
    """The closed citations repository, taken from the first of three places that has it.

    ANCHOR_SIFT_CITATIONS wins, for a checkout that keeps it somewhere of its own. Then the clone
    under deps/, the route onto a machine that only consumes it. Then the authoring copy
    beside this checkout, which is where it is edited and signed.
    """
    named = os.environ.get("ANCHOR_SIFT_CITATIONS")
    if named:
        return os.path.abspath(named)
    for candidate in (os.path.join(ROOT, "deps", "anchor_sift_citations"),
                      os.path.join(os.path.dirname(ROOT), "private_repos",
                                   "anchor_sift_citations")):
        if os.path.isdir(candidate):
            return candidate
    return os.path.join(ROOT, "deps", "anchor_sift_citations")


def tree_files():
    """Every file of this tree's own writing, this one excluded.

    STARTING holds the names. A scan that reads this file reports every one of them as used here
    and counts itself into the total. Heaps appeared once in the whole tree, in this list.
    """
    mine = os.path.abspath(__file__)
    for one in SEARCHED:
        full = os.path.join(ROOT, one)
        if os.path.isfile(full):
            yield full
            continue
        for base, dirs, names in os.walk(full):
            dirs[:] = [one for one in dirs if one not in SKIP]
            for name in sorted(names):
                if not name.endswith(TEXT):
                    continue
                found = os.path.join(base, name)
                if os.path.abspath(found) != mine:
                    yield found


def read_registry(root):
    """The registry as it stands, keyed by key, in the order it was written."""
    held = {}
    target = os.path.join(root, NAME)
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
            if row.get("key"):
                held[row["key"]] = {one: row.get(one, "") for one in FIELDS}
    return held


def write_registry(root, rows, out):
    """The registry, sorted by key. Only uses and first_use ever change under a written row."""
    target = os.path.join(root, NAME)
    unattributed = [one for one in rows.values() if not (one["author"] or one["identifier"])]
    with io.open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("# The sources the anchor sift measurements are built on.\n")
        handle.write("# Entered by maint/citations.py --seed in anchor_sift, which writes\n")
        handle.write("# the key and the use counts and never writes a bibliographic field.\n")
        handle.write("#\n")
        handle.write("# author, year, title and identifier are filled in by hand from the source\n")
        handle.write("# itself. A surname in a comment is not a citation and this tool cannot turn\n")
        handle.write("# one into a reference. file names the copy held under sources/, where there\n")
        handle.write("# is one.\n")
        handle.write("#\n")
        handle.write("# %d sources, %d with no author and no identifier yet.\n"
                     % (len(rows), len(unattributed)))
        handle.write("\t".join(FIELDS))
        handle.write("\n")
        for key in sorted(rows):
            handle.write("\t".join(rows[key].get(one, "") for one in FIELDS))
            handle.write("\n")
    out.write("  %s\n" % os.path.join(root, NAME).replace("\\", "/"))
    out.write("    %d sources, %d unattributed\n" % (len(rows), len(unattributed)))


def used(keys):
    """Where each key is written in the tree, and every citation shape that no key covers."""
    where = {}
    shaped = {}
    patterns = [(key, re.compile(r"\b%s\b" % re.escape(key))) for key in keys]
    for path in tree_files():
        shown = os.path.relpath(path, ROOT).replace("\\", "/")
        with io.open(path, encoding="utf-8", errors="replace") as handle:
            for at, line in enumerate(handle, 1):
                for key, pattern in patterns:
                    if pattern.search(line):
                        where.setdefault(key, []).append("%s:%d" % (shown, at))
                for found in SHAPED.finditer(line):
                    name = found.group(1)
                    if name.split()[0] in NOT_A_NAME:
                        continue
                    if any(key in name for key in keys):
                        continue
                    shaped.setdefault("%s %s" % (name, found.group(2)),
                                      []).append("%s:%d" % (shown, at))
    return where, shaped


def held_files(root):
    """Every source held under sources/, as a path relative to the repository."""
    base = os.path.join(root, "sources")
    if not os.path.isdir(base):
        return []
    held = []
    for where, dirs, names in os.walk(base):
        dirs[:] = [one for one in dirs if one not in SKIP]
        for name in sorted(names):
            full = os.path.join(where, name)
            held.append(os.path.relpath(full, root).replace("\\", "/"))
    return sorted(held)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    seeding = "--seed" in sys.argv
    checking = "--check" in sys.argv
    bypassing = ("--bypass" in sys.argv) or bool(os.environ.get(BYPASS_ENV))

    root = private_root()
    out.write("\n  %s\n" % root.replace("\\", "/"))
    if not os.path.isdir(root):
        out.write("  not there. Clone the closed citations repository, or set"
                  " ANCHOR_SIFT_CITATIONS.\n")
        if bypassing:
            out.write("  bypassed.\n\n")
            out.flush()
            return 0
        out.write("  the gate cannot be answered without it. To commit anyway:\n")
        out.write("      python maint/citations.py --check --bypass\n")
        out.write("      %s=1 git commit ...\n\n" % BYPASS_ENV)
        out.flush()
        return 2

    registry = read_registry(root)
    vocabulary = set(registry) | set(SAME) | (set(STARTING) if not registry else set())
    where, shaped = used(vocabulary)

    # The two ways one source is written collapse onto the registry's key before anything counts.
    for written, key in SAME.items():
        if written in where:
            where.setdefault(key, []).extend(where.pop(written))

    unregistered = sorted(one for one in where if one not in registry)
    for key in unregistered:
        if seeding:
            registry[key] = dict.fromkeys(FIELDS, "")
            registry[key]["key"] = key

    for key, row in registry.items():
        hits = sorted(set(where.get(key, [])))
        row["uses"] = str(len(hits))
        # Blanking this when the scan finds nothing wipes a hand entered pointer at another
        # repository, and the row then reads as retired on the next run. A scanned value always
        # carries a line number and a hand entered one does not. That separates them.
        row["first_use"] = hits[0] if hits else (row.get("first_use") or "")

    unattributed = sorted(one for one, row in registry.items()
                          if not (row["author"] or row["identifier"]))
    # A row with no uses here and a first_use pointing at another repository is cited from the
    # closed corpus, which this scan cannot read. Calling it retired would be wrong twice over: it
    # is in use, and the label would invite somebody to drop it.
    elsewhere = sorted(one for one, row in registry.items()
                       if row["uses"] == "0" and row["first_use"]
                       and ":" not in row["first_use"])
    unused = sorted(one for one, row in registry.items()
                    if row["uses"] == "0" and one not in set(elsewhere))
    on_disk = held_files(root)
    claimed = {row["file"] for row in registry.values() if row["file"]}
    unheld = sorted(one for one, row in registry.items()
                    if row["file"] and row["file"] not in set(on_disk))
    orphan = sorted(one for one in on_disk if one not in claimed)

    out.write("    %d source(s) registered, %d used in the tree\n"
              % (len(registry), sum(1 for row in registry.values() if row["uses"] != "0")))

    by_field = {}
    for key, row in registry.items():
        by_field.setdefault((row["bucket"] or "/").split("/")[0] or "unbucketed", []).append(key)
    for field in sorted(by_field):
        out.write("\n  %s\n" % field)
        for key in sorted(by_field[field],
                          key=lambda one: (registry[one]["bucket"], one)):
            out.write("    %-32s %-38s %s uses\n"
                      % (key, registry[key]["bucket"] or "no bucket", registry[key]["uses"]))

    malformed = sorted(one for one, row in registry.items()
                       if row["bucket"] and not BUCKET.match(row["bucket"]))
    if malformed:
        out.write("\n  BUCKET IS NOT field/category (%d)\n" % len(malformed))
        for key in malformed:
            out.write("    %-32s %s\n" % (key, registry[key]["bucket"]))

    if unregistered and not seeding:
        out.write("\n  USED AND UNREGISTERED (%d)\n" % len(unregistered))
        for key in unregistered:
            hits = sorted(set(where[key]))
            out.write("    %-32s %3d uses, first at %s\n" % (key, len(hits), hits[0]))
    if unattributed:
        out.write("\n  NO AUTHOR AND NO IDENTIFIER, so not yet a reference (%d)\n"
                  % len(unattributed))
        for key in unattributed:
            out.write("    %-32s %s uses\n" % (key, registry[key]["uses"]))
    if unheld:
        out.write("\n  FILE NAMED AND NOT UNDER sources/ (%d)\n" % len(unheld))
        for key in unheld:
            out.write("    %-32s %s\n" % (key, registry[key]["file"]))
    if orphan:
        out.write("\n  UNDER sources/ AND NAMED BY NO ROW (%d)\n" % len(orphan))
        for one in orphan:
            out.write("    %s\n" % one)
    if elsewhere:
        out.write("\n  CITED FROM ANOTHER REPOSITORY, not by this tree (%d)\n" % len(elsewhere))
        for key in elsewhere:
            out.write("    %-32s %s\n" % (key, registry[key]["first_use"]))
    if unused:
        out.write("\n  REGISTERED AND NO LONGER USED, row kept (%d)\n" % len(unused))
        for key in unused:
            out.write("    %s\n" % key)
    if shaped:
        out.write("\n  CITATION SHAPE, COVERED BY NO KEY (%d)\n" % len(shaped))
        for one in sorted(shaped)[:24]:
            out.write("    %-40s %s\n" % (one, sorted(set(shaped[one]))[0]))
        if len(shaped) > 24:
            out.write("    and %d more\n" % (len(shaped) - 24))
        out.write("    These are a list to read. Most are dates and some are sources.\n")

    if seeding:
        out.write("\n")
        write_registry(root, registry, out)
        out.write("\n  the bibliographic fields are empty and are yours to fill.\n")
        out.write("  reconcile and sign after:\n")
        out.write("      python maint/corpus_manifest.py --write --root %s\n"
                  % root.replace("\\", "/"))
        out.write("      gpg --armor --detach-sign --yes MANIFEST.tsv\n\n")
        out.flush()
        return 0

    if checking and unregistered:
        if bypassing:
            out.write("\n  %d name(s) used here and in no row. Bypassed.\n\n" % len(unregistered))
            out.flush()
            return 0
        out.write("\n  a name is used here and is in no row. Run --seed.\n")
        out.write("  to commit without answering it:\n")
        out.write("      %s=1 git commit ...\n\n" % BYPASS_ENV)
        out.flush()
        return 1

    out.write("\n  --seed enters what is used and is unregistered, with every field empty\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
