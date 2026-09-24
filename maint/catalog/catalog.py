#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Give every example a catalog number, and keep it.
#
#   python maint/catalog/catalog.py            what is registered and what is not
#   python maint/catalog/catalog.py --assign   number the new ones and write it into their headers
#   python maint/catalog/catalog.py --check    fail where a header and the registry disagree
#   python maint/catalog/catalog.py --header   give a file with no license header one. --assign
#                                              has a line to write its number under
#
# WHY A NUMBER AND NOT A PATH
#
# The theory books cite examples, and a path is the wrong identifier for that. A file that moves
# breaks every citation to it, and this tree has already reorganized examples once, from
# examples/language_testing/natural_languages into examples/language/4_measure, leaving 190 of 252
# cited paths pointing at nothing. A catalog number survives a move. At 98 examples the paths were
# still followable by hand; at a thousand they will not be.
#
# HOW A NUMBER IS BUILT
#
#   LNG-4-012      domain, pipeline stage, ordinal within that pair
#
# The domain is the directory under examples/ and the stage is the numbered directory under it, and
# a reader knows where to look before opening the registry. The ordinal is assigned once.
#
# ASSIGNED ONCE, NEVER RECOMPUTED
#
# catalog.tsv is the registry and it is append only. Numbering alphabetically on every run would be
# simpler and would be wrong: one example added at the head of a directory would renumber everything
# after it and silently invalidate every citation already written down. A new file takes the next
# free ordinal in its own domain and stage. A deleted file keeps its number, retired and never
# reissued. A citation to it then resolves to a retirement instead of to another file.
#
# A MOVE KEEPS THE NUMBER AND CHANGES THE PREFIX
#
# Those disagree, and the registry keeps the number it issued. An example that moves from one domain
# to another is the same example. --assign updates the path against the existing number and
# leaves the number alone, prefix included. The prefix says where it was first filed; the path in
# the registry says where it is.

import io
import os
import re
import subprocess
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))


def _repository_root():
    """This repository, asked of git and not inferred from a marker directory.

    The marker climbed to before was build/, which the repository PRODUCES and not CONTAINS.
    A linked worktree and a never-built clone both lack it. The climb then walked past the root it
    was looking for into another checkout entirely, and every path derived from it pointed at a
    different tree than the tool was run from. That lands on a real repository with real files,
    which is indistinguishable from working.

    A marker infers the root. Git answers it. The climb below is kept only for an exported tree with
    no git directory, and it looks for src/engine, which is TRACKED: a marker the repository
    contains is present in every checkout of it, and a marker the repository produces is present in
    none of them until something has already run.

    Git's own variables are cleared first. Inside a hook GIT_DIR is exported, and a rev-parse that
    inherits it answers about that repository and not about the directory it was asked from,
    returning the current directory instead of the root.
    """
    start = os.path.dirname(os.path.abspath(__file__))
    environment = dict(os.environ)
    for key in (
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_PREFIX",
        "GIT_COMMON_DIR",
    ):
        environment.pop(key, None)

    try:
        said = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=start,
            stderr=subprocess.PIPE,
            env=environment,
        )
    except (OSError, subprocess.CalledProcessError):
        said = b""

    top = said.decode("utf-8", "replace").strip()
    if top and os.path.isdir(top):
        return os.path.abspath(top)

    climbed = start
    while (climbed != os.path.dirname(climbed)) and not os.path.isdir(
        os.path.join(climbed, "src", "engine")
    ):
        climbed = os.path.dirname(climbed)
    return climbed


ROOT = _repository_root()

EXAMPLES = os.path.join(ROOT, "examples")
REGISTRY = os.path.join(HERE, "catalog.tsv")

# Three letters per domain, which lets a number be read without the registry open.
DOMAIN = {
    "00_blob_viz_tools": "VIZ",
    "0_experimental": "EXP",
    "any_corpus": "ANY",
    "art": "ART",
    "cell_tracking": "CEL",
    "chemistry": "CHM",
    "crystallography": "CRY",
    "game_theory": "GAM",
    "language": "LNG",
    "proteins": "PRO",
    "proofs": "PRF",
    "sound": "SND",
    "source": "SRC",
}

# CEL, GAM and EXP were added after seventeen examples had already been written carrying numbers
# their authors minted by pattern. A domain absent from this table makes slot_of return None, the
# file reports as NO DOMAIN and not numbered, and the hand-written header sits there looking issued.
# Two sessions did that independently and neither was told by anything until --check was run, which
# is the argument for running it instead of copying the shape of a number that is already there.
# CHM joined the same way, after three chemistry examples had landed with no number and --check
# failed on main naming them.
#
# EXP is the VIZ case again and not a ninth subject. 0_experimental holds work that reads no
# corpus yet. It names no domain in the sense the others do, and its files take stage x like
# anything outside a numbered pipeline directory. They are numbered because a number survives a
# move: an example that later earns a subject stage keeps the number it was issued here, and every
# citation written against it still resolves.

# VIZ is not a domain in the sense the other eight are. Those name what a corpus is of, and the
# viz tools read any blob: whatever arrives as points carrying values, with no domain in it. They
# sit first in the listing for that reason, and they carry numbers because they are tools this
# work uses, and a number survives a file moving where a path does not.
#
# They take stage x, like anything not under a numbered pipeline directory. Reading a blob is not
# a stage of the pipeline, it is a way of looking at any stage of it.

# The line a number is written on, directly under the SPDX line.
MARK = "# Catalog: "
CATALOG = re.compile(r"^#\s*Catalog:\s*([A-Z]{3}-[0-9x]-[0-9]{3})\s*$", re.MULTILINE)
STAGE = re.compile(r"^([0-9])_")


def slot_of(path):
    """The domain code and stage digit for one example, from where it sits."""
    parts = os.path.relpath(path, EXAMPLES).replace("\\", "/").split("/")
    if len(parts) < 2:
        return None, None
    code = DOMAIN.get(parts[0])
    if code is None:
        return None, None
    found = STAGE.match(parts[1]) if len(parts) > 2 else None
    # posits and anything else unstaged take x, which sorts apart from the six stages.
    return code, (found.group(1) if found else "x")


def examples():
    """Every example script, as a path relative to the repository."""
    held = []
    for base, dirs, names in os.walk(EXAMPLES):
        dirs[:] = sorted(one for one in dirs if one != "__pycache__")
        for name in sorted(names):
            if name.endswith(".py"):
                full = os.path.join(base, name)
                held.append(os.path.relpath(full, ROOT).replace("\\", "/"))
    return held


def read_registry():
    """The registry as number against path, in the order it was written."""
    held = {}
    if not os.path.isfile(REGISTRY):
        return held
    with io.open(REGISTRY, encoding="utf-8") as handle:
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
            if row.get("catalog"):
                held[row["catalog"]] = row
    return held


def write_registry(rows):
    with io.open(REGISTRY, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(
            "# The example catalog. Append only: a number is issued once and never moves.\n"
        )
        handle.write("# Written by maint/catalog/catalog.py --assign.\n")
        handle.write(
            "# state is live where the file is there and retired where it is gone.\n"
        )
        handle.write("catalog\tstate\tpath\n")
        for number in sorted(rows):
            row = rows[number]
            handle.write("%s\t%s\t%s\n" % (number, row["state"], row["path"]))


def standard_header():
    """The license header this tree puts at the top of every file, read from repotools.toml.

    Read and not spelled here, because a second copy of the SPDX string is a second place to
    change it and nothing compares the two. repotools.toml already holds the project name, the
    copyright line and the SPDX expression, and it is the file the rest of the toolkit asks.

    tomllib is the standard library's parser. citations.py hand-scans the same file for its own
    [layout] table, which predates this and works, but a hand-scanner reads what its author expected
    the file to look like and not what TOML says it is.
    """
    path = os.path.join(ROOT, "repotools.toml")
    if not os.path.isfile(path):
        return None
    with io.open(path, "rb") as handle:
        table = tomllib.load(handle)
    project = table.get("project", {})
    name = project.get("name")
    holder = project.get("copyright")
    spdx = project.get("spdx")
    if not (name and holder and spdx):
        return None
    return ["# %s - %s" % (name, holder), "# SPDX-License-Identifier: %s" % spdx]


def headed(text, header, runnable):
    """The same file with the license header above what it already says, or None where it has one.

    The shebang goes on only where the file is run. Twenty of the twenty-three this was written for
    carry a __main__ guard and three are imported modules, and a shebang on a module says it is an
    entry point when it is not.
    """
    if "# SPDX-License-Identifier:" in text:
        return None
    lines = (["#!/usr/bin/env python3"] if runnable else []) + header + ["#"]
    return "\n".join(lines) + "\n" + text


def stamped(text):
    """The catalog number written in a file's header, or None."""
    found = CATALOG.search(text)
    return found.group(1) if found else None


def stamp(text, number):
    """The same file with its number on the line under the SPDX line, or None where there is no
    SPDX line to put it under.

    Returning None and not the text unchanged is the whole point. A file
    already carrying the right number returns its text unchanged. The caller could not tell a file it had nothing to
    do to from a file it could not write to, and reported both as stamped. The registry then held a
    number for a file whose header would never carry it, --check reported it adrift forever, and the
    remedy --check named was the run that had just silently skipped it.
    """
    if CATALOG.search(text):
        return CATALOG.sub(MARK + number, text, count=1)
    lines = text.split("\n")
    for at, line in enumerate(lines):
        if line.startswith("# SPDX-License-Identifier:"):
            lines.insert(at + 1, MARK + number)
            return "\n".join(lines)
    return None


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    assigning = "--assign" in sys.argv
    checking = "--check" in sys.argv
    headering = "--header" in sys.argv

    registry = read_registry()
    by_path = {}
    for number, row in registry.items():
        by_path[row["path"]] = number

    found = examples()
    taken = {}
    for number in registry:
        code, stage, ordinal = number.split("-")
        taken.setdefault((code, stage), set()).add(int(ordinal))

    # A file that moved carries its own number in its header, and that stamp is what identifies it.
    # Matching on path alone reads a move as one example retired and another created, which burns a
    # number and breaks every citation to it. Claimed here before anything new is issued.
    moved = []
    present = set(found)
    for path in found:
        if path in by_path:
            continue
        with io.open(os.path.join(ROOT, path), encoding="utf-8", newline="") as handle:
            held = stamped(handle.read())
        if (held is None) or (held not in registry):
            continue
        was = registry[held]["path"]
        if was in present:
            # Both paths exist. That is a copy, and the copy takes a number of its own.
            continue
        registry[held]["path"] = path
        by_path.pop(was, None)
        by_path[path] = held
        moved.append((held, was, path))

    # A file the registry has never seen can still carry a number, stamped by its author and
    # published with it. Issuing that file a different ordinal changes what a citation to the stamp
    # resolves to, and the registry exists to stop that. The stamp is kept when its domain and stage
    # match where the file sits and no example already holds that number. Files are claimed in path
    # order, and a second file stamped with a number the first one claimed takes a fresh ordinal
    # below and shows up as adrift.
    claimed = []
    for path in found:
        if path in by_path:
            continue
        code, stage = slot_of(os.path.join(ROOT, path))
        if code is None:
            continue
        with io.open(os.path.join(ROOT, path), encoding="utf-8", newline="") as handle:
            held = stamped(handle.read())
        if (held is None) or (held in registry):
            continue
        held_code, held_stage, held_ordinal = held.split("-")
        if (held_code != code) or (held_stage != stage):
            continue
        used = taken.setdefault((code, stage), set())
        if int(held_ordinal) in used:
            continue
        used.add(int(held_ordinal))
        registry[held] = {"catalog": held, "state": "live", "path": path}
        by_path[path] = held
        claimed.append((held, path))

    issued = []
    unplaceable = []
    for path in found:
        if path in by_path:
            continue
        code, stage = slot_of(os.path.join(ROOT, path))
        if code is None:
            unplaceable.append(path)
            continue
        used = taken.setdefault((code, stage), set())
        ordinal = 1
        while ordinal in used:
            ordinal += 1
        used.add(ordinal)
        number = "%s-%s-%03d" % (code, stage, ordinal)
        registry[number] = {"catalog": number, "state": "live", "path": path}
        by_path[path] = number
        issued.append((number, path))

    retired = []
    for number, row in registry.items():
        was = row["state"]
        row["state"] = "live" if row["path"] in present else "retired"
        if row["state"] == "retired" and was != "retired":
            retired.append((number, row["path"]))

    # The header and the registry are two copies of one fact. They are compared every run.
    adrift = []
    for path in found:
        number = by_path.get(path)
        if number is None:
            continue
        with io.open(os.path.join(ROOT, path), encoding="utf-8", newline="") as handle:
            text = handle.read()
        if stamped(text) != number:
            adrift.append((path, number, stamped(text)))

    out.write(
        "\n  %d examples, %d numbers issued, %d retired\n"
        % (
            len(found),
            len(registry),
            sum(1 for one in registry.values() if one["state"] == "retired"),
        )
    )
    if unplaceable:
        out.write("\n  NO DOMAIN, not numbered (%d)\n" % len(unplaceable))
        for one in unplaceable:
            out.write("    %s\n" % one)
    if moved:
        out.write("\n  MOVED, number kept (%d)\n" % len(moved))
        for number, was, now in moved:
            out.write("    %s  %s\n            -> %s\n" % (number, was, now))
    if claimed:
        out.write(
            "\n  CLAIMED, the number its header already carried (%d)\n" % len(claimed)
        )
        for number, path in claimed[:12]:
            out.write("    %s  %s\n" % (number, path))
        if len(claimed) > 12:
            out.write("    and %d more\n" % (len(claimed) - 12))
    if issued:
        out.write("\n  NEW (%d)\n" % len(issued))
        for number, path in issued[:12]:
            out.write("    %s  %s\n" % (number, path))
        if len(issued) > 12:
            out.write("    and %d more\n" % (len(issued) - 12))
    if retired:
        out.write("\n  RETIRED, number kept and never reissued (%d)\n" % len(retired))
        for number, path in retired:
            out.write("    %s  %s\n" % (number, path))
    if adrift:
        out.write("\n  HEADER DISAGREES WITH THE REGISTRY (%d)\n" % len(adrift))
        for path, number, held in adrift[:12]:
            out.write(
                "    %s  registry %s, header %s\n" % (path, number, held or "none")
            )

    if headering:
        header = standard_header()
        if header is None:
            out.write(
                "\n  repotools.toml has no [project] with a name, a copyright and an spdx to\n"
            )
            out.write("  build a header from. Nothing written.\n\n")
            out.flush()
            return 1
        written = []
        for path in found:
            full = os.path.join(ROOT, path)
            with io.open(full, encoding="utf-8", newline="") as handle:
                text = handle.read()
            fresh = headed(text, header, "__main__" in text)
            if fresh is None:
                continue
            with io.open(full, "w", encoding="utf-8", newline="") as handle:
                handle.write(fresh)
            written.append(path)
        if written:
            out.write("\n  HEADER WRITTEN (%d)\n" % len(written))
            for path in written:
                out.write("    %s\n" % path)
            out.write(
                "\n  Run --assign to write each number into the header now under it.\n\n"
            )
        else:
            out.write("\n  every example already carries a header\n\n")
        out.flush()
        return 0

    if assigning:
        unstampable = []
        for path in found:
            number = by_path.get(path)
            if number is None:
                continue
            full = os.path.join(ROOT, path)
            with io.open(full, encoding="utf-8", newline="") as handle:
                text = handle.read()
            fresh = stamp(text, number)
            if fresh is None:
                unstampable.append((path, number))
                continue
            if fresh != text:
                with io.open(full, "w", encoding="utf-8", newline="") as handle:
                    handle.write(fresh)
        write_registry(registry)
        out.write(
            "\n  registry written to %s\n"
            % os.path.relpath(REGISTRY, ROOT).replace("\\", "/")
        )
        if unstampable:
            out.write("  headers stamped except %d\n" % len(unstampable))
            out.write("\n  NO SPDX LINE TO STAMP UNDER (%d)\n" % len(unstampable))
            for path, number in unstampable:
                out.write("    %s  needs %s\n" % (path, number))
            out.write(
                "\n  Each holds a number in the registry and has no header to write it into.\n"
            )
            out.write(
                "  --check reports these as adrift, --check says to run --assign, and --assign\n"
            )
            out.write(
                "  cannot reach them. The two instructions point at each other until one of\n"
            )
            out.write(
                "  these files gets the standard header. Giving them a header is the exit.\n\n"
            )
            out.flush()
            return 1
        out.write("  headers stamped\n\n")
        out.flush()
        return 0

    if checking and (adrift or unplaceable):
        out.write("\n  run --assign\n\n")
        out.flush()
        return 1

    out.write("\n  --assign writes the registry and stamps the headers\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
