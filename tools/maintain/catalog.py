#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Give every example a catalog number, and keep it.
#
#   python tools/maintain/catalog.py            what is registered and what is not
#   python tools/maintain/catalog.py --assign   number the new ones and write it into their headers
#   python tools/maintain/catalog.py --check    fail where a header and the registry disagree
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
# to another is the same example, so --assign updates the path against the existing number and
# leaves the number alone, prefix included. The prefix says where it was first filed; the path in
# the registry says where it is.

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

EXAMPLES = os.path.join(ROOT, "examples")
REGISTRY = os.path.join(HERE, "catalog.tsv")

# Three letters per domain, which lets a number be read without the registry open.
DOMAIN = {
    "any_corpus": "ANY",
    "art": "ART",
    "crystals": "CRY",
    "language": "LNG",
    "proteins": "PRO",
    "proofs": "PRF",
    "sound": "SND",
    "source": "SRC",
}

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
        handle.write("# The example catalog. Append only: a number is issued once and never moves.\n")
        handle.write("# Written by tools/maintain/catalog.py --assign.\n")
        handle.write("# state is live where the file is there and retired where it is gone.\n")
        handle.write("catalog\tstate\tpath\n")
        for number in sorted(rows):
            row = rows[number]
            handle.write("%s\t%s\t%s\n" % (number, row["state"], row["path"]))


def stamped(text):
    """The catalog number written in a file's header, or None."""
    found = CATALOG.search(text)
    return found.group(1) if found else None


def stamp(text, number):
    """The same file with its number on the line under the SPDX line."""
    if CATALOG.search(text):
        return CATALOG.sub(MARK + number, text, count=1)
    lines = text.split("\n")
    for at, line in enumerate(lines):
        if line.startswith("# SPDX-License-Identifier:"):
            lines.insert(at + 1, MARK + number)
            return "\n".join(lines)
    return text


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    assigning = "--assign" in sys.argv
    checking = "--check" in sys.argv

    registry = read_registry()
    by_path = {}
    for number, row in registry.items():
        by_path[row["path"]] = number

    found = examples()
    taken = {}
    for number in registry:
        code, stage, ordinal = number.split("-")
        taken.setdefault((code, stage), set()).add(int(ordinal))

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

    present = set(found)
    retired = []
    for number, row in registry.items():
        was = row["state"]
        row["state"] = "live" if row["path"] in present else "retired"
        if row["state"] == "retired" and was != "retired":
            retired.append((number, row["path"]))

    # The header and the registry are two copies of one fact, so they are compared every run.
    adrift = []
    for path in found:
        number = by_path.get(path)
        if number is None:
            continue
        with io.open(os.path.join(ROOT, path), encoding="utf-8", newline="") as handle:
            text = handle.read()
        if stamped(text) != number:
            adrift.append((path, number, stamped(text)))

    out.write("\n  %d examples, %d numbers issued, %d retired\n"
              % (len(found), len(registry), sum(1 for one in registry.values()
                                                if one["state"] == "retired")))
    if unplaceable:
        out.write("\n  NO DOMAIN, not numbered (%d)\n" % len(unplaceable))
        for one in unplaceable:
            out.write("    %s\n" % one)
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
            out.write("    %s  registry %s, header %s\n" % (path, number, held or "none"))

    if assigning:
        for path in found:
            number = by_path.get(path)
            if number is None:
                continue
            full = os.path.join(ROOT, path)
            with io.open(full, encoding="utf-8", newline="") as handle:
                text = handle.read()
            fresh = stamp(text, number)
            if fresh != text:
                with io.open(full, "w", encoding="utf-8", newline="") as handle:
                    handle.write(fresh)
        write_registry(registry)
        out.write("\n  registry written to %s\n"
                  % os.path.relpath(REGISTRY, ROOT).replace("\\", "/"))
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
