#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch cookery books across several centuries, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_recipes.py
#
# Everything read here is either formal procedure or no procedure at all. Source code is a procedure
# written to be executed exactly, and every other corpus is narrative, scripture or reference. A recipe
# is the case in between: it tells someone how to do something, in the order it must be done, and it
# leaves out most of what the reader is assumed to know.
#
# That omission is the point of testing it. A recipe written in 1390 assumes a kitchen, a set of tools and
# a shared sense of how much is enough, none of which it states and none of which survives. What is left
# on the page is the shape of the instruction with its content removed by time, which is the same
# situation as an undeciphered script and a better one to work in, since these are in a language that can
# be read even where the practice cannot.
#
# The prediction the fetch is for: if a procedural register leaves a signature that does not depend on
# being formal, recipes sit between source code and narrative prose. If register is only formality, they
# sit with the prose they are written in.
#
# Books are taken across as many centuries as the catalog holds, so anything constant across them is not a
# property of one era's writing.

import io
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

CATALOG = "https://gutendex.com/books"
LEAST = 90000
WANTED = 14
PAUSE = 0.4

SEARCHES = ("cookery", "cook book", "recipes", "household management", "confectionery")


def get(url, timeout=120):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def strip_wrapper(text):
    start = re.search(r"\*\*\*\s*START OF TH[EI]S? PROJECT GUTENBERG[^\*]*\*\*\*", text)
    if start:
        text = text[start.end():]
    stop = re.search(r"\*\*\*\s*END OF TH[EI]S? PROJECT GUTENBERG[^\*]*\*\*\*", text)
    if stop:
        text = text[:stop.start()]
    return text


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  %-38s %-8s %s\n" % ("title", "chars", "author born"))

    seen = set()
    landed = 0
    for term in SEARCHES:
        if landed >= WANTED:
            break
        query = urllib.parse.urlencode({"search": term, "languages": "en",
                                        "mime_type": "text/plain"})
        try:
            payload = json.loads(get("%s?%s" % (CATALOG, query)).decode("utf-8"))
        except Exception as trouble:
            out.write("  search for %s failed: %s\n" % (term, str(trouble)[:50]))
            continue

        for entry in payload.get("results", []):
            if landed >= WANTED:
                break
            number = entry.get("id")
            if number in seen:
                continue
            seen.add(number)
            target = os.path.join(CORPORA, "recipe_%d.txt" % number)
            if os.path.isfile(target):
                landed += 1
                continue

            link = None
            for kind, address in entry.get("formats", {}).items():
                if kind.startswith("text/plain") and not address.endswith(".zip"):
                    link = address
                    break
            if not link:
                continue
            try:
                text = strip_wrapper(get(link).decode("utf-8", errors="replace"))
                time.sleep(PAUSE)
            except Exception:
                continue
            if len(text) < LEAST:
                continue

            with open(target, "w", encoding="utf-8", newline="") as handle:
                handle.write(text)
            authors = entry.get("authors", [])
            born = authors[0].get("birth_year") if authors else None
            out.write("  %-38s %-8d %s\n"
                      % (entry.get("title", "")[:38], len(text), born if born else "unknown"))
            out.flush()
            landed += 1

    out.write("\n  %d cookery books landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
