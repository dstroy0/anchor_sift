#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch several works by each of several writers, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_authors.py
#
# Nothing held here has two works by one writer. Every English text in the corpus is one book by one
# person, so a comparison between two of them is a comparison between two writers as much as anything
# else, and a language reading taken across them carries whoever wrote them inside it.
#
# That matters because it would explain a result already recorded. One language read from two places sits
# 0.0867 apart and two languages read from one place sit 0.0936 apart, a margin of seven percent, and part
# of what fills the first of those numbers may be that the two places were written by different people.
#
# Separating them needs a set where the language is fixed and the writer changes, which is what this
# fetches: several works by each of several writers, all in English, all prose, mostly one century apart
# at the widest. Whether a writer can be told from another writer at all is a settled question in the
# literature and the answer is yes, so this is a check on the instrument as much as on the claim: a
# reading that cannot separate writers is not reading everything a text holds.

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
LEAST = 150000
PER_AUTHOR = 5
PAUSE = 0.4

WRITERS = (
    ("austen", "Austen, Jane"),
    ("dickens", "Dickens, Charles"),
    ("twain", "Twain, Mark"),
    ("conrad", "Conrad, Joseph"),
    ("melville", "Melville, Herman"),
    ("doyle", "Doyle, Arthur Conan"),
    ("wells", "Wells, H. G."),
    ("eliot", "Eliot, George"),
    ("hardy", "Hardy, Thomas"),
    ("stevenson", "Stevenson, Robert Louis"),
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
    out.write("  %-12s %-46s %s\n" % ("writer", "title", "chars"))

    landed = 0
    for short, full in WRITERS:
        query = urllib.parse.urlencode({"search": full, "languages": "en",
                                        "mime_type": "text/plain", "sort": "popular"})
        try:
            payload = json.loads(get("%s?%s" % (CATALOG, query)).decode("utf-8"))
        except Exception as trouble:
            out.write("  %-12s search failed: %s\n" % (short, str(trouble)[:50]))
            continue

        kept = 0
        for entry in payload.get("results", []):
            if kept >= PER_AUTHOR:
                break
            # The search matches a name anywhere, so an entry about a writer is not one by them
            authors = entry.get("authors", [])
            if not authors or (full.split(",")[0].lower() not in authors[0].get("name", "").lower()):
                continue
            number = entry.get("id")
            target = os.path.join(CORPORA, "author_%s_%d.txt" % (short, number))
            if os.path.isfile(target):
                kept += 1
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
            out.write("  %-12s %-46s %d\n"
                      % (short, (entry.get("title") or "").replace("\n", " ")[:46], len(text)))
            out.flush()
            kept += 1
            landed += 1

    out.write("\n  %d works landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
