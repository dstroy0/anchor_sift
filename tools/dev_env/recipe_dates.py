#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Get real dates for the cookery books, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/recipe_dates.py
#
# Dating these books by the earliest year printed in their opening pages put a 1919 cookbook in 1600,
# because the first four digit number in a file is as likely to be a street address, a page count or a
# year mentioned in a preface as it is to be a date of publication. Every reading that used those dates
# is void, including a correlation against time and a comparison of one century against another.
#
# The files are named by the catalog's own numbers, so the catalog can be asked directly. What it gives
# is the author's dates, which is not a publication date either, but an author's lifetime bounds when a
# book could have been written and does not depend on what number happens to appear first in a preface.
# The distinction is kept in the output: this is when the author lived, and it is used as a date only
# because it is the honest one available.

import io
import json
import os
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(ROOT, "build", "recipe_dates.csv")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

CATALOG = "https://gutendex.com/books/"
PAUSE = 0.3


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    numbers = []
    for name in sorted(os.listdir(CORPORA)):
        if name.startswith("recipe_") and name.endswith(".txt"):
            try:
                numbers.append(int(name[7:-4]))
            except ValueError:
                continue

    out.write("  %-8s %-46s %-12s %s\n" % ("number", "title", "author born", "author died"))
    rows = []
    for number in numbers:
        try:
            request = urllib.request.Request("%s%d" % (CATALOG, number), headers=AGENT)
            with urllib.request.urlopen(request, timeout=90) as response:
                entry = json.loads(response.read().decode("utf-8"))
            time.sleep(PAUSE)
        except Exception as trouble:
            out.write("  %-8d %s\n" % (number, str(trouble)[:60]))
            continue

        authors = entry.get("authors", [])
        born = authors[0].get("birth_year") if authors else None
        died = authors[0].get("death_year") if authors else None
        title = (entry.get("title") or "").replace("\n", " ").replace(",", ";")
        rows.append((number, title, born, died))
        out.write("  %-8d %-46s %-12s %s\n"
                  % (number, title[:46], born if born else "unknown",
                     died if died else "unknown"))
        out.flush()

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("number,title,born,died\n")
        for number, title, born, died in rows:
            handle.write("%d,%s,%s,%s\n" % (number, title[:80],
                                            born if born else "", died if died else ""))

    dated = [row for row in rows if row[2] is not None]
    out.write("\n  %d of %d books have an author with dates\n" % (len(dated), len(rows)))
    out.write("  wrote %s\n" % TARGET)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
