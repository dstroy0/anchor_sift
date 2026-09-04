#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch instruction written for rulers, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_statecraft.py
#
# A recipe is procedure written informally for a reader whose assumed knowledge has been lost. Instruction
# written for a ruler is the same register at another scale: how to hold a province, what a campaign
# needs, how many days of grain a march carries, what an army is fed on and by whom. Vegetius counts
# rations, Xenophon lays out the running of an estate, and the advice books written for princes across
# several centuries teach government as a practice with the reasons left unstated because the reader was
# assumed to hold them.
#
# It matters here for the same reason the cookery does and covers a gap the cookery leaves. Between source
# code, which is procedure written to be executed exactly, and narrative, which is not procedure at all,
# there was one band and it was a domestic one written mostly in the nineteenth century. This is the same
# band at the scale of logistics and it reaches back much further, because a manual on feeding an army was
# worth copying for a thousand years and a cookbook usually was not.
#
# Stored apart from the cookery, since these differ from it in subject as well as in period and the two
# should not be able to stand in for each other in any reading.

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
WANTED = 16
PAUSE = 0.4

SEARCHES = (
    "military institutions romans", "art of war", "the prince machiavelli",
    "cyropaedia", "oeconomicus xenophon", "arthashastra", "deeds of arms chivalry",
    "government of princes", "statecraft", "commentaries caesar",
    "anabasis xenophon", "strategemata",
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
    out.write("  %-8s %-46s %-8s %s\n" % ("number", "title", "chars", "author born"))

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

        for entry in payload.get("results", [])[:4]:
            if landed >= WANTED:
                break
            number = entry.get("id")
            if number in seen:
                continue
            seen.add(number)
            target = os.path.join(CORPORA, "rule_%d.txt" % number)
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
            out.write("  %-8d %-46s %-8d %s\n"
                      % (number, (entry.get("title") or "").replace("\n", " ")[:46],
                         len(text), born if born else "unknown"))
            out.flush()
            landed += 1

    out.write("\n  %d books of instruction for rulers landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
