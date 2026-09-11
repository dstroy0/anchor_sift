#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Point at the examples whose description and code have drifted apart.
#
#   python maint/catalog/catalog_verify.py            every check
#   python maint/catalog/catalog_verify.py --quiet    only the files with a finding
#
# WHAT THIS IS AND IS NOT
#
# Heuristics. Each one below is cheap, mechanical, and wrong sometimes. None of them reads what a
# script means. A finding here is a place worth opening and not a defect. The value is in
# the ratio: a hundred examples is more than anyone rereads, and this narrows it to the few where
# the header and the file disagree about something checkable.
#
# The register checker is next door and answers a different question. docs_check reads how a comment
# is written. This reads whether it is still true.
#
# THE CHECKS
#
#   usage        the Usage line names a path, and the file is at that path
#   stage        a 4_measure script imports from measure, a 1_represent one from representation
#   cites        the section a header points at exists in the theory it names
#   writes       a header saying it writes something has a write in it, and the reverse
#   fetches      a header saying it fetches has a network call in it, and the reverse
#   silent       a script with no output call, which usually means a header promising a report
#   catalog      the stamped number matches the registry
#
# WHY THE PAIRS RUN BOTH WAYS
#
# A header that promises less than the code does is the more dangerous half and the easier one to
# miss. A script described as reading a corpus that also writes one has an effect nobody reviewing
# the description would expect, and it will be run by somebody who read only the description.

import io
import itertools
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

EXAMPLES = os.path.join(ROOT, "examples")
REGISTRY = os.path.join(HERE, "catalog.tsv")

CATALOG = re.compile(r"^#\s*Catalog:\s*([A-Z]{3}-[0-9x]-[0-9]{3})\s*$", re.MULTILINE)
USAGE = re.compile(r"^#\s+(?:Usage:\s+)?python\s+(\S+\.py)", re.MULTILINE)
SECTION = re.compile(r"[Ss]ection\s+([0-9]+\.[0-9]+(?:\.[0-9]+)?)")
# A chapter heading carries its own number first: \paragraph{4.13.09 Frequency-Stratified Structure}
HEADING_NUMBER = re.compile(
    r"\\(?:section|subsection|subsubsection|paragraph)\*?\{([0-9]+\.[0-9]+(?:\.[0-9]+)?)\s")

# The pipeline stage a directory name carries, against the engine package it should be reaching for.
STAGE_PACKAGE = {
    "1": "representation",
    "2": "partition",
    "3": "reference",
    "4": "measure",
    "5": "sift",
    "6": "oracle",
}

WRITES = re.compile(r"\bopen\([^)]*[\"'][wax]|\.write_text\(|\.write_bytes\(|makedirs\(")
FETCHES = re.compile(r"urllib|requests\.|urlopen|\bhttps?://")
PRINTS = re.compile(r"\bprint\(|out\.write\(|sys\.stdout")

# A header claims a file write only when it names something written somewhere. The bare verb caught
# "Written as the decomposition it names" and fired on 42 of 98 examples, which is a checker nobody
# would read twice.
# The destination has to be a place, not an infinitive. Accepting a bare "to" matched "a procedure
# written to be carried out exactly", which is prose about procedures and not a claim about output.
SAYS_WRITE = re.compile(
    r"\b(writes?|written|emits?|saves?)\b[^.]{0,60}?"
    r"(build/|\.tsv|\.csv|\.txt|\.json|\.png|\.md"
    r"|\b(?:in)?to (?:a |the |its )?(?:file|corpus|table|document|record|disk|directory))", re.I)
SAYS_FETCH = re.compile(r"\b(fetch|fetches|download|downloads|pull|pulls|reach|reaches)\b", re.I)


def header_of(text):
    """The comment block above the first import, which is where a script describes itself."""
    held = []
    for line in text.split("\n"):
        bare = line.strip()
        if bare.startswith("#") or not bare:
            held.append(bare.lstrip("#").strip())
            continue
        if bare.startswith('"""'):
            held.append(bare.strip('"').strip())
            continue
        break
    return "\n".join(held)


def theory_sections():
    """Every section number the theory books actually carry."""
    held = set()
    # Both trees. The workbook stays in theory/ because it is the book about this engine, and the
    # other seven are pulled in under theory_bucket/ as a subtree. Walking only the first reports
    # every section those seven carry as missing.
    roots = (os.path.join(ROOT, "theory"), os.path.join(ROOT, "theory_bucket"))
    for base, dirs, names in itertools.chain.from_iterable(os.walk(one) for one in roots):
        dirs[:] = [one for one in dirs if one != "__pycache__"]
        for name in names:
            if not name.endswith(".tex"):
                continue
            with io.open(os.path.join(base, name), encoding="utf-8", errors="replace") as handle:
                body = handle.read()
            # Two shapes. A cross reference writes "Section 4.13", and a heading writes the number
            # first: \paragraph{4.13.09 Frequency-Stratified Structure}. Reading only the first
            # form reported every real subsection as missing.
            for found in SECTION.finditer(body):
                held.add(found.group(1))
            for found in HEADING_NUMBER.finditer(body):
                held.add(found.group(1))
            for one in list(held):
                # A heading numbered 4.13.05 also answers a citation to 4.13.
                parts = one.split(".")
                if len(parts) > 2:
                    held.add(".".join(parts[:2]))
    return held


def registry():
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
            if row.get("path"):
                held[row["path"]] = row["catalog"]
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    quiet = "--quiet" in sys.argv

    known = registry()
    sections = theory_sections()

    scanned = 0
    findings = 0
    tally = {}

    for base, dirs, names in os.walk(EXAMPLES):
        dirs[:] = sorted(one for one in dirs if one != "__pycache__")
        for name in sorted(names):
            if not name.endswith(".py"):
                continue
            path = os.path.join(base, name)
            shown = os.path.relpath(path, ROOT).replace("\\", "/")
            with io.open(path, encoding="utf-8", errors="replace", newline="") as handle:
                text = handle.read()
            head = header_of(text)
            body = text[len(head):]
            scanned += 1
            said = []

            found = CATALOG.search(text)
            number = found.group(1) if found else None
            if known.get(shown) and number != known.get(shown):
                said.append(("catalog", "header %s, registry %s"
                             % (number or "none", known[shown])))

            for cited in USAGE.findall(head):
                if cited != shown and not os.path.isfile(os.path.join(ROOT, cited)):
                    said.append(("usage", "Usage names %s" % cited))

            parts = os.path.relpath(path, EXAMPLES).replace("\\", "/").split("/")
            stage = parts[1][0] if (len(parts) > 2 and parts[1][:1].isdigit()) else None
            wanted = STAGE_PACKAGE.get(stage)
            if wanted and ("import" in body):
                reaches = re.findall(r"(?:from|import)\s+(representation|partition|reference"
                                     r"|measure|sift|oracle)\b", body)
                if reaches and (wanted not in reaches):
                    said.append(("stage", "in %s, imports %s"
                                 % (parts[1], ", ".join(sorted(set(reaches))))))

            for cited in set(SECTION.findall(head)):
                if sections and (cited not in sections):
                    said.append(("cites", "Section %s is in no book" % cited))

            writes = bool(WRITES.search(body))
            claims_write = bool(SAYS_WRITE.search(head))
            if writes and not claims_write:
                said.append(("writes", "writes a file, header does not say so"))
            if claims_write and not writes:
                said.append(("writes", "header says it writes, no write found"))

            gets = bool(FETCHES.search(body))
            claims_fetch = bool(SAYS_FETCH.search(head))
            if gets and not claims_fetch:
                said.append(("fetches", "reaches the network, header does not say so"))

            if not PRINTS.search(body):
                said.append(("silent", "no output call"))

            if said:
                findings += len(said)
                out.write("\n  %s  %s\n" % (number or "unnumbered", shown))
                for kind, why in said:
                    tally[kind] = tally.get(kind, 0) + 1
                    out.write("      %-9s %s\n" % (kind, why))
            elif not quiet:
                tally["clean"] = tally.get("clean", 0) + 1

    out.write("\n  %d examples read, %d finding(s)\n" % (scanned, findings))
    for kind in sorted(tally):
        out.write("    %-9s %d\n" % (kind, tally[kind]))
    out.write("\n  Heuristics. A finding is a file worth opening, not a defect.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
