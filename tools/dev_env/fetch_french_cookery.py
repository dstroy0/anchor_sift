#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch French cookery, which is where the old material actually is, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_french_cookery.py
#
# The cookery books already held were fetched with the language fixed to English, which was written into
# the search and never reconsidered. The consequence showed up as a property of the corpus instead of a
# property of that choice: fourteen books with author dates, spanning 1588 to 1858 and clustered in the
# nineteenth century, and a test of how procedure recording changed over centuries run against a corpus
# that barely covers one.
#
# The old material is French. Le Viandier is around 1300, the Menagier de Paris around 1393, and Chiquart
# around 1420, all of them written down when nothing about recording a procedure was settled, and all of
# them documented at length. English cookery of that period survives mostly through later editors, which
# is how the one medieval English book here arrives dated to its eighteenth century editor instead of to
# itself.
#
# Anything found is stored apart from the English books, since a difference between the two sets would
# otherwise be read as a difference between periods when it is also a difference between languages.

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
LEAST = 60000
PAUSE = 0.4

SEARCHES = (
    "viandier", "menagier", "cuisine", "cuisinier", "cuisiniere",
    "gastronomie", "patissier", "office cuisine", "art culinaire",
)


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
    out.write("  %-8s %-44s %-8s %s\n" % ("number", "title", "chars", "author born"))

    seen = set()
    landed = 0
    for term in SEARCHES:
        query = urllib.parse.urlencode({"search": term, "languages": "fr",
                                        "mime_type": "text/plain"})
        try:
            payload = json.loads(get("%s?%s" % (CATALOG, query)).decode("utf-8"))
        except Exception as trouble:
            out.write("  search for %s failed: %s\n" % (term, str(trouble)[:50]))
            continue

        for entry in payload.get("results", []):
            number = entry.get("id")
            if number in seen:
                continue
            seen.add(number)
            target = os.path.join(CORPORA, "frecipe_%d.txt" % number)
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
            out.write("  %-8d %-44s %-8d %s\n"
                      % (number, (entry.get("title") or "")[:44], len(text),
                         born if born else "unknown"))
            out.flush()
            landed += 1

    out.write("\n  %d French cookery books landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
