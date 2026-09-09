#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Track every ICSNL paper from the archive index to converted text, one row per paper.
#
#   python tools/Salishan/paper_supervisor.py --plan          write the work list
#   python tools/Salishan/paper_supervisor.py                 what is held and what is not
#   python tools/Salishan/paper_supervisor.py --adopt DIR     take PDFs from a download directory
#   python tools/Salishan/paper_supervisor.py --fetch         fetch what is missing, where it can
#   python tools/Salishan/paper_supervisor.py --remaining     print the addresses still needed
#
# WHY A PLAN FILE AND NOT A LOOP
#
# 993 papers is more than one run. A loop that walks the index start to finish loses everything it
# learned the moment it is interrupted, and the next run re-asks the server for what it already
# has. The plan is a table on disk: every paper, its address, its state, and what happened last
# time. Any of the four commands above can be run in any order, any number of times, and each one
# only touches rows whose state gives it something to do.
#
# THE STATES
#
#   missing    in the index, not on disk
#   held       the PDF is on disk
#   text       the PDF is on disk and its text is beside it. The readers need this one
#   refused    the server answered with something that is not a PDF, and said why
#
# WHERE THE BYTES COME FROM
#
# --fetch asks the archive, exactly the way get_papers.py does, with the same named client and the
# same pause. Where the archive answers with a browser verification page instead of a file, that is
# a check meant to be passed by a person, and the run stops and says so. It is not retried, not
# routed around, and not asked again from somewhere else. Two ways past it, both of them real:
#
#   Ask the archive for bulk access. The client string names a contact for exactly this.
#   Download in a browser and point --adopt at the download directory.
#
# --adopt makes the second route cheap. Download a batch however many at a time, drop them in, and
# it verifies each one is a PDF, names it by its stem, converts it, and marks the row. --remaining
# then prints the addresses still needed, and that list is the next batch to download.

import argparse
import io
import os
import shutil
import sys
import time

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

PAPERS = os.path.join(ROOT, "build", "papers")
PLAN = os.path.join(ROOT, "build", "papers_plan.tsv")
INDEX_TABLE = os.path.join(PAPERS, "icsnl_index.tsv")

FIELDS = ("stem", "state", "bytes", "address", "said")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# The page UBC serves in place of every file while its browser check is up. Recognizing it lets a
# run report one honest sentence instead of 846 copies of a wrong one.
VERIFICATION = ("browser verification", "verify your browser", "javascript required")


def index_rows():
    """Every paper the archive lists, as stem against address, from the saved index table."""
    held = {}
    if not os.path.isfile(INDEX_TABLE):
        return held
    with io.open(INDEX_TABLE, encoding="utf-8", errors="replace") as handle:
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
            if row.get("kind") != "pdf" or not row.get("url"):
                continue
            stem = os.path.splitext(os.path.basename(row["url"]))[0]
            held.setdefault(stem, row["url"])
    return held


def state_of(stem):
    """What is on disk for one paper."""
    if os.path.isfile(os.path.join(PAPERS, "%s.txt" % stem)):
        return "text"
    if os.path.isfile(os.path.join(PAPERS, "%s.pdf" % stem)):
        return "held"
    return "missing"


def read_plan():
    rows = {}
    if not os.path.isfile(PLAN):
        return rows
    with io.open(PLAN, encoding="utf-8") as handle:
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
            if row.get("stem"):
                rows[row["stem"]] = {one: row.get(one, "") for one in FIELDS}
    return rows


def write_plan(rows, out):
    tally = {}
    for row in rows.values():
        tally[row["state"]] = tally.get(row["state"], 0) + 1
    os.makedirs(os.path.dirname(PLAN), exist_ok=True)
    with io.open(PLAN, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Every ICSNL paper, its address, and how far it has got.\n")
        handle.write("# Written by tools/Salishan/paper_supervisor.py. Safe to delete and rebuild.\n")
        handle.write("#\n")
        handle.write("# %s\n" % ", ".join("%d %s" % (tally[one], one) for one in sorted(tally)))
        handle.write("\t".join(FIELDS))
        handle.write("\n")
        for stem in sorted(rows):
            handle.write("\t".join(rows[stem].get(one, "") for one in FIELDS))
            handle.write("\n")
    out.write("  %s\n" % os.path.relpath(PLAN, ROOT).replace("\\", "/"))
    for one in sorted(tally):
        out.write("    %-10s %d\n" % (one, tally[one]))


def refresh(rows):
    """Bring every row's state back in line with what is actually on disk."""
    for stem, row in rows.items():
        found = state_of(stem)
        row["state"] = found
        if found == "missing":
            row["bytes"] = ""
            continue
        source = os.path.join(PAPERS, "%s.pdf" % stem)
        row["bytes"] = str(os.path.getsize(source)) if os.path.isfile(source) else ""
    return rows


def looks_verified(path):
    """Whether a downloaded file is the browser check page wearing a PDF's name."""
    with open(path, "rb") as handle:
        head = handle.read(4096).lower()
    if head.startswith(b"%pdf"):
        return False
    return any(one.encode("ascii") in head for one in VERIFICATION)


def convert_one(out, stem):
    """One PDF to the text the readers read, through get_papers so there is one converter."""
    from get_papers import converted
    source = os.path.join(PAPERS, "%s.pdf" % stem)
    target = os.path.join(PAPERS, "%s.txt" % stem)
    if os.path.isfile(target) or not os.path.isfile(source):
        return False
    pages, unmapped = converted(source, target)
    out.write("      %d pages%s\n" % (pages, "  NOT THE PAGE" if unmapped else ""))
    return True


def run_adopt(out, rows, where):
    """Take PDFs out of a download directory, verify each, name it, and convert it."""
    if not os.path.isdir(where):
        out.write("  no directory at %s\n" % where)
        return 2
    os.makedirs(PAPERS, exist_ok=True)
    taken = 0
    refused = 0
    unknown = []
    for name in sorted(os.listdir(where)):
        if not name.lower().endswith(".pdf"):
            continue
        stem = name[:-4]
        source = os.path.join(where, name)
        if looks_verified(source):
            out.write("    %-46s the browser check page, not a paper\n" % stem[:46])
            refused += 1
            continue
        with open(source, "rb") as handle:
            if not handle.read(4).startswith(b"%PDF"):
                out.write("    %-46s does not start with %%PDF\n" % stem[:46])
                refused += 1
                continue
        if stem not in rows:
            unknown.append(stem)
        target = os.path.join(PAPERS, name)
        if not os.path.isfile(target):
            shutil.copy2(source, target)
        out.write("    %-46s %d KB\n" % (stem[:46], os.path.getsize(target) // 1024))
        convert_one(out, stem)
        taken += 1
    out.write("\n  %d adopted, %d refused\n" % (taken, refused))
    if unknown:
        out.write("  %d not in the archive index by that name, kept anyway:\n" % len(unknown))
        for stem in unknown[:12]:
            out.write("    %s\n" % stem)
    return 0


def run_fetch(out, rows, pause):
    """Ask the archive for what is missing, and stop at the browser check instead of working it."""
    try:
        import requests
    except ImportError:
        out.write("  requests is not installed:  python -m pip install requests\n")
        return 1
    from get_papers import AGENT

    session = requests.Session()
    session.headers["User-Agent"] = AGENT
    os.makedirs(PAPERS, exist_ok=True)

    wanted = [stem for stem in sorted(rows) if rows[stem]["state"] == "missing"]
    out.write("  %d missing, asking for them one at a time\n\n" % len(wanted))
    got = 0
    for stem in wanted:
        address = rows[stem]["address"]
        if not address:
            continue
        try:
            answer = session.get(address, timeout=120, stream=True)
            answer.raise_for_status()
        except Exception as trouble:
            rows[stem]["said"] = str(trouble)[:110]
            out.write("    %-46s %s\n" % (stem[:46], str(trouble)[:60]))
            time.sleep(pause)
            continue
        kind = answer.headers.get("content-type", "")
        if "pdf" not in kind.lower():
            body = answer.content[:4096].lower()
            if any(one.encode("ascii") in body for one in VERIFICATION):
                rows[stem]["state"] = "refused"
                rows[stem]["said"] = "browser verification page"
                out.write("\n  the archive answered with its browser verification page.\n")
                out.write("  That check is meant to be passed by a person and this stops here.\n")
                out.write("  Two ways on, both of them real:\n")
                out.write("    ask the archive for bulk access, the client string names a contact\n")
                out.write("    download in a browser, then --adopt that directory\n")
                out.write("  %d fetched before it stopped.\n" % got)
                return 2
            rows[stem]["state"] = "refused"
            rows[stem]["said"] = "answered with %s" % (kind or "nothing")
            out.write("    %-46s answered with %s\n" % (stem[:46], kind or "nothing"))
            time.sleep(pause)
            continue
        target = os.path.join(PAPERS, "%s.pdf" % stem)
        part = target + ".part"
        with open(part, "wb") as handle:
            for block in answer.iter_content(65536):
                handle.write(block)
        os.replace(part, target)
        rows[stem]["state"] = "held"
        rows[stem]["bytes"] = str(os.path.getsize(target))
        out.write("    %-46s %d KB\n" % (stem[:46], os.path.getsize(target) // 1024))
        convert_one(out, stem)
        got += 1
        time.sleep(pause)
    out.write("\n  %d fetched\n" % got)
    return 0


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", action="store_true", help="rebuild the work list from the index")
    parser.add_argument("--adopt", metavar="DIR", help="take PDFs from a download directory")
    parser.add_argument("--fetch", action="store_true", help="ask the archive for what is missing")
    parser.add_argument("--remaining", action="store_true", help="print the addresses still needed")
    parser.add_argument("--pause", type=float, default=1.0, help="seconds between requests")
    given = parser.parse_args()

    listed = index_rows()
    rows = read_plan()

    if given.plan or not rows:
        if not listed:
            out.write("\n  no archive index at %s\n"
                      % os.path.relpath(INDEX_TABLE, ROOT).replace("\\", "/"))
            out.write("  it is written by get_papers.py when it reads the archive page, and it is\n")
            out.write("  carried in the closed corpus. Run private_sync.py, or fetch the index.\n\n")
            out.flush()
            return 2
        for stem, address in listed.items():
            row = rows.get(stem) or dict.fromkeys(FIELDS, "")
            row["stem"] = stem
            row["address"] = address
            rows[stem] = row
        # A paper on disk that the index does not list is still a paper, and dropping it from the
        # plan would report it missing forever. icsnl2016.pdf and Hall-et-al_-ICSNL_61-1.pdf are
        # both like that today.
        if os.path.isdir(PAPERS):
            for name in sorted(os.listdir(PAPERS)):
                if not name.lower().endswith(".pdf"):
                    continue
                stem = name[:-4]
                if stem not in rows:
                    rows[stem] = {"stem": stem, "state": "", "bytes": "",
                                  "address": "", "said": "not in the index"}

    refresh(rows)

    # Before the banner, because this one is written to be piped into a downloader and a blank
    # first line is a blank first argument.
    if given.remaining:
        for stem in sorted(rows):
            if rows[stem]["state"] == "missing" and rows[stem]["address"]:
                out.write("%s\n" % rows[stem]["address"])
        out.flush()
        return 0

    out.write("\n")

    code = 0
    if given.adopt:
        code = run_adopt(out, rows, given.adopt)
        refresh(rows)
    elif given.fetch:
        code = run_fetch(out, rows, given.pause)
        refresh(rows)

    out.write("\n")
    write_plan(rows, out)
    held = sum(1 for row in rows.values() if row["state"] in ("held", "text"))
    out.write("\n  %d of %d papers are on disk, %d have text\n"
              % (held, len(rows),
                 sum(1 for row in rows.values() if row["state"] == "text")))
    out.write("  --remaining prints the addresses still needed, one per line\n\n")
    out.flush()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
