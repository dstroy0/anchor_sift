#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The registry of the mathematics this work rests on, and what is used here without a reference.
#
#   python maint/citations/citations.py           what is registered, and what is used and is not
#   python maint/citations/citations.py --seed    enter the names found in the tree, fields empty
#   python maint/citations/citations.py --check   fail while a name is used and unregistered
#   python maint/citations/citations.py --bypass  answer the gate without satisfying it
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
# uses and first_use are facts about this tree. They are recomputed every run. Everything else
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
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# What git exports into a hook. They name the repository git is already operating on, and a
# rev-parse that inherits them answers about THAT instead of about the directory it was asked from.
# The specific way it goes wrong is quiet: with GIT_DIR set and no work tree named, --show-toplevel
# comes back as the current directory. This file's own directory became the repository root and
# every scanned path hung off maint/citations/. It was caught only because the layout guard below
# refuses a root with no repotools.toml in it; with the old silent fallback it would have scanned
# almost nothing and exited 0.
GIT_ENV = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_COMMON_DIR")


def git_answer(arguments):
    """One git query about the tree this file sits in, or None where git will not say.

    Asked with the hook's own git variables cleared. The answer is about the directory asked
    from and not about whatever repository invoked us.
    """
    environment = dict(os.environ)
    for key in GIT_ENV:
        environment.pop(key, None)

    try:
        answer = subprocess.check_output(
            ["git"] + list(arguments), cwd=HERE, stderr=subprocess.PIPE, env=environment
        )
    except (OSError, subprocess.CalledProcessError):
        return None

    said = answer.decode("utf-8", "replace").strip()
    return said or None


def working_tree():
    """The tree this tool is part of, which is not the tree it used to walk up to.

    ROOT was found by climbing from this file until a directory holding build/ appeared. build/ is
    generated and a linked worktree does not have one. From a worktree the climb went straight
    past the worktree root and stopped at the MAIN checkout. The gate then scanned main's tree while
    reporting on a commit being made from somewhere else, and it did that silently, because landing
    on a real repository with real files looks exactly like working.

    It also has a second failure at the other end: a clone that has never built anything has no
    build/ anywhere. The climb runs to the filesystem root and every scanned path is wrong.

    git answers the question directly and answers it the same way for the main worktree and a linked
    one. The climb is kept only as the fallback for an exported tree with no history, and it looks
    for src/engine rather than build/ because src/engine is TRACKED: a marker the repository
    contains is present in every checkout of it, and a marker the repository produces is present in
    none of them until something has already run. This fallback originally kept build/, which left
    one file climbing to a generated marker after the other fifty-two had stopped.

    Not to be confused with main_checkout() below, which deliberately wants the OTHER answer: this
    one is the tree being read, that one is the tree the closed repositories sit beside.
    """
    top = git_answer(["rev-parse", "--show-toplevel"])
    if top and os.path.isdir(top):
        return os.path.abspath(top)

    climbed = HERE
    while (climbed != os.path.dirname(climbed)) \
            and not os.path.isdir(os.path.join(climbed, "src", "engine")):
        climbed = os.path.dirname(climbed)
    return climbed


ROOT = working_tree()

NAME = "SOURCES.tsv"

# The one way past the gate. A flag reaches the tool when a person runs it, and the variable is how
# the same flag reaches it from inside a commit hook, where nobody is typing arguments.
BYPASS_ENV = "ANCHOR_SIFT_BYPASS"
FIELDS = ("key", "bucket", "author", "year", "title", "identifier", "file", "differs",
          "uses", "first_use")

# differs says what this work does that the source does not. Building on a result and departing
# from it are two different relationships to it, and a registry recording only the first leaves a
# reader to guess which one a row means. Horspool is the clearest case: the algorithm is what the
# sift is benchmarked against, and the anchor rule is the part that is not his.

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
ENTERED = ("bucket", "author", "year", "title", "identifier", "file", "differs")

SKIP = ("__pycache__", ".git", "build", "deps", "site")

# What counts as text this tree wrote. A source a reader can find in the tree and the gate cannot
# read is a source the gate cannot ask about, and the extension list is the whole of what it reads.
#
# The six added here were each hiding a real registry question. .tsv hid maint/texbuild/
# ledger_days.tsv, which carries the fullest bibliographic strings in the repository. .json hid
# test/vectors/MANIFEST.json, which holds the NIST CAVP and Wycheproof provenance with archive
# SHA-256s -- a provenance record the citation gate could not see is the exact case this tool
# exists for. .html hid two citations inside a built view, .rsp is the CAVP response format, and
# .cff is the repository's own citation file, which it would be absurd for a citation gate to skip.
TEXT = (".md", ".tex", ".py", ".c", ".h", ".R", ".m", ".sh", ".bib",
        ".html", ".js", ".json", ".tsv", ".rsp", ".cff")

# One entry of the [layout] table: a bare string, or a list of them.
LAYOUT_ENTRY = re.compile(r"^\s*([a-z_]+)\s*=\s*(.+?)\s*$")

# The layout kinds that hold writing of this tree's own. Asked for by KIND and never by directory.
#
# This is the repair for the defect that brought me here. The list used to name "tools", and this
# repository has no tools/ directory -- README.md:59 says so deliberately, because the code lives
# under maint/. os.walk over a directory that does not exist yields nothing and raises nothing, so
# the entry scanned zero files and reported zero findings, while maint/, evidence/ and test/ were
# never named at all and so were never scanned either. A gate that reads nothing exits 0.
#
# Worth recording rather than quietly fixing: objective 5 moves the tools into tools/, which would
# have made that directory exist and REPAIRED this half by accident. The gate would have started
# working and nobody would have learned it had been blind, nor that maint/ had never been in the
# list in the first place. Inheriting a fix by luck is worse than making it, because the second
# defect rides out on the first one's coattails.
WRITTEN_KINDS = ("docs", "source", "examples", "tests", "tools")

# Places with no layout kind of their own. evidence/ holds the proofs that pin the numbers, and the
# three files are the loose ones at the root.
EXTRA_SEARCHED = ("evidence", "README.md", "SECURITY.md", "CONTRIBUTING.md", "CITATION.cff")


def layout_table():
    """The [layout] table of repotools.toml, every value as a tuple of names.

    Reads both spellings the table uses: `tools = "maint"` and `docs = ["docs", "theory"]`. An
    absent file returns an empty table, which the caller turns into a stopped run rather than a
    silent one.
    """
    path = os.path.join(ROOT, "repotools.toml")
    if not os.path.isfile(path):
        return {}

    table = {}
    inside = False
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("["):
                inside = stripped == "[layout]"
                continue
            if not inside or not stripped or stripped.startswith("#"):
                continue
            entry = LAYOUT_ENTRY.match(line)
            if entry:
                table[entry.group(1)] = tuple(re.findall(r'"([^"]*)"', entry.group(2)))
    return table


def searched_names():
    """Every place this tree's own writing lives, resolved through repotools.toml.

    Refuses rather than guesses, in all three ways it can be wrong: no table, a missing kind, or a
    named directory that is not on disk. Each of those otherwise reads as a smaller scan that
    reports fewer findings and exits 0, which is the failure this whole function is about.
    """
    table = layout_table()
    if not table:
        raise SystemExit("citations: no [layout] table in %s. The directories to scan are named "
                         "there, and guessing them is how this gate came to scan a tools/ "
                         "directory that does not exist." % os.path.join(ROOT, "repotools.toml"))

    names = []
    for kind in WRITTEN_KINDS:
        if kind not in table:
            raise SystemExit("citations: repotools.toml [layout] has no %s key. A kind that is "
                             "not listed is not scanned, and an unscanned tree reports no missing "
                             "citations." % kind)
        for one in table[kind]:
            if one not in names:
                names.append(one)

    for one in EXTRA_SEARCHED:
        if one not in names:
            names.append(one)

    absent = [one for one in names if not os.path.exists(os.path.join(ROOT, one))]
    if absent:
        raise SystemExit("citations: %s named for scanning and not on disk. os.walk over a "
                         "directory that is not there yields nothing and raises nothing. This "
                         "stops instead." % ", ".join(absent))

    return tuple(names)


SEARCHED = searched_names()

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
# It finds sources this file has never heard of, and it also finds every date in the tree. What
# it reports is a list to read and not a list to enter.
SHAPED = re.compile(r"\b([A-Z][A-Za-zéáíóúüñ]{3,}"
                    r"(?:(?: and | & |, )[A-Z][A-Za-zéáíóúüñ]{3,})*),? \(?((?:19|20)[0-9]{2})\)?")

# Words that open the citation shape and are not names. Months and the like.
NOT_A_NAME = frozenset((
    "January", "February", "March", "April", "June", "July", "August", "September", "October",
    "November", "December", "Recorded", "English", "Languages", "Copyright", "Version", "Retrieved",
    "Accessed", "Updated", "Published", "Since", "Before", "After", "Between", "During",
))


def main_checkout():
    """The main working tree, which is the one the private repositories sit beside.

    A linked worktree lives at <repo>/.claude/worktrees/<name>. A sibling path computed from it
    lands inside .claude/ and finds nothing. Git knows the difference: --git-common-dir names the
    shared .git directory for the main tree and for every linked worktree alike, and its parent is
    the main checkout.

    Falls back to ROOT where git cannot answer, which covers an exported tree with no history. That
    fallback is the ordinary case and not a failure. It is silent; a private root that is looked
    for and not found is reported by the caller instead.
    """
    common = git_answer(["rev-parse", "--git-common-dir"])
    if not common:
        return ROOT
    if not os.path.isabs(common):
        common = os.path.join(HERE, common)
    base = os.path.dirname(os.path.abspath(common))
    return base if os.path.isdir(base) else ROOT


def private_candidates():
    """Every place the closed citations repository is looked for, in the order it is looked for.

    Returned rather than searched inline so the caller can say what it looked for when it finds
    nothing. A gate that reports only "not there" sends the reader to guess at paths, and the
    guessing is what left this tool pointing at private_repos/ for the whole of the migration.
    """
    base = main_checkout()
    return (
        # The authoring copy, at repos/owned/private/ beside repos/owned/public/. This is where the
        # registry actually lives after the move into owned/{public,private}, and its absence from
        # this list is why --check exited 2 on every commit and every commit needed the bypass.
        os.path.join(os.path.dirname(os.path.dirname(base)), "private", "anchor_sift_citations"),
        # The clone under deps/, the route onto a machine that only consumes it.
        os.path.join(base, "deps", "anchor_sift_citations"),
        # The layout before the move. Kept so a checkout that has not been reorganized still works.
        os.path.join(os.path.dirname(base), "private_repos", "anchor_sift_citations"),
    )


def private_root():
    """The closed citations repository, taken from the first place that has it.

    ANCHOR_SIFT_CITATIONS wins, for a checkout that keeps it somewhere of its own.
    """
    named = os.environ.get("ANCHOR_SIFT_CITATIONS")
    if named:
        return os.path.abspath(named)
    for candidate in private_candidates():
        if os.path.isdir(candidate):
            return candidate
    return private_candidates()[0]


# A file this tree produced rather than wrote, announced by its own first line. Matched across the
# comment leaders the tree uses so the test is about the marker and not about the language.
GENERATED = re.compile(r"^\s*(?:%+|#+|//+|/\*+)\s*Generated by\b", re.I)


def is_generated(path):
    """Whether a file says on its first line that something generated it.

    THE CIRCULARITY THIS PREVENTS, which is silent and lossy rather than merely untidy.

    theory_bucket/cryptography/sha256/chapters/chapter_sources.tex is written by the book build FROM
    the citations registry, and it lands inside theory_bucket, which is scanned. So the registry's
    own bibliography is a file full of the names in the registry. A --seed run over it rewrites
    first_use from the document that genuinely cites a work to the file that exists only because the
    row exists, and the real user of the source is erased. The registry ends up recording itself as
    the reason a source is used.

    It also inflates the use count: every key in a generated bibliography gets at least one hit from
    it. Such a row can never read as unused and --check cannot tell "cited by the work" from
    "listed in a bibliography the registry produced".

    Keyed on the file's first line rather than a list of paths, because a path list is a second
    place to remember something and the marker is already there. SKIP cannot reach this case: it
    filters directories, and this is a generated file inside a directory that is kept.
    """
    try:
        with io.open(path, encoding="utf-8", errors="replace") as handle:
            return bool(GENERATED.match(handle.readline()))
    except OSError:
        return False


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
                if os.path.abspath(found) == mine:
                    continue
                if is_generated(found):
                    continue
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
        handle.write("# Entered by maint/citations/citations.py --seed in anchor_sift, which writes\n")
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
        # Naming every place it looked, and not only the one it would have used. A gate that
        # reports a single path it did not find reads as "the repository is missing" when what
        # happened is that the repository moved and this list did not, which is the state this
        # tool was in for the whole of the migration.
        out.write("  looked for it at:\n")
        for candidate in private_candidates():
            out.write("      %s\n" % candidate.replace("\\", "/"))
        if bypassing:
            out.write("  bypassed.\n\n")
            out.flush()
            return 0
        out.write("  the gate cannot be answered without it. To commit anyway:\n")
        out.write("      python maint/citations/citations.py --check --bypass\n")
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
        out.write("\n  NO AUTHOR AND NO IDENTIFIER. Not yet a reference (%d)\n"
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
        out.write("      python maint/corpus/corpus_manifest.py --write --root %s\n"
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
