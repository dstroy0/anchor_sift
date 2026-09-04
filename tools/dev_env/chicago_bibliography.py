#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# List the public novels and find the writers with enough works to test, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/chicago_bibliography.py
#
# Whether a writer leaves a mark of their own needs several works by each of several writers with the
# language held fixed, and nothing held here has two works by one person. Searching a book catalog by
# name was the first attempt and it is a poor basis, since the search matches a name anywhere it appears
# and how many works a writer has in it follows their popularity.
#
# This collection is 1276 novels published before 1923, prepared the same way as each other, and it
# answers in a machine readable form. What is wanted from it first is only the list: who wrote what, so
# the writers carrying enough works can be found before anything is downloaded.

import io
import json
import os
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TARGET = os.path.join(ROOT, "build", "chicago_novels.csv")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

BASE = "https://artflsrv04.uchicago.edu/philologic5/chicago_novel_corpus_pre1923"
PAGE = 200
PAUSE = 0.4
ENOUGH = 4


def ask(start, end, tries=4):
    """One page of the listing, asked again where the server does not answer.

    It answered a first probe and then timed out on the next request, so a single failure says nothing
    about whether the collection is reachable and should not end the run.
    """
    url = ("%s/reports/bibliography.py?report=bibliography&format=json&start=%d&end=%d"
           % (BASE, start, end))
    last = None
    for attempt in range(tries):
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=180) as response:
                return json.loads(response.read().decode("utf-8", errors="replace"))
        except Exception as trouble:
            last = trouble
            time.sleep(PAUSE * (2 ** attempt))
    raise last


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    first = ask(0, 1)
    total = int(first.get("results_length", 0))
    shape = first["results"][0]["metadata_fields"] if first.get("results") else {}
    out.write("  %d novels, each carrying: %s\n\n" % (total, ", ".join(sorted(shape))))

    rows = []
    start = 0
    while start < total:
        try:
            payload = ask(start, min(start + PAGE, total))
        except Exception as trouble:
            out.write("  stopped at %d: %s\n" % (start, str(trouble)[:70]))
            break
        found = payload.get("results", [])
        if not found:
            break
        for entry in found:
            fields = entry.get("metadata_fields", {})
            rows.append({
                "author": (fields.get("author") or "").strip(),
                "title": (fields.get("title") or "").strip().replace(",", ";"),
                "year": (fields.get("year") or fields.get("date") or "").strip(),
                "filename": (fields.get("filename") or "").strip(),
                "philo": entry.get("philo_id", [None])[0],
            })
        start += PAGE
        time.sleep(PAUSE)

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("philo,author,year,title,filename\n")
        for row in rows:
            handle.write("%s,%s,%s,%s,%s\n" % (row["philo"], row["author"].replace(",", ";"),
                                               row["year"], row["title"][:70], row["filename"]))

    counts = {}
    for row in rows:
        if row["author"]:
            counts.setdefault(row["author"], []).append(row)

    many = sorted((author for author in counts if len(counts[author]) >= ENOUGH),
                  key=lambda author: -len(counts[author]))
    out.write("  %d of %d novels name an author, %d writers have %d works or more\n\n"
              % (sum(len(counts[author]) for author in counts), len(rows), len(many), ENOUGH))
    out.write("  %-38s %-7s %s\n" % ("writer", "works", "years"))
    for author in many[:30]:
        held = counts[author]
        years = sorted(row["year"] for row in held if row["year"])
        out.write("  %-38s %-7d %s\n"
                  % (author[:38], len(held),
                     ("%s to %s" % (years[0], years[-1])) if years else "unknown"))

    out.write("\n  wrote %s\n" % TARGET)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
