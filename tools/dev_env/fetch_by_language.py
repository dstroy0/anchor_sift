#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch several texts in each of several languages, to test whether a language carries a constant, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_by_language.py [texts per language]
#
# The claim under test is that every language has an idiom of its own and that the idiom is constant. It
# predicts something checkable: two texts in one language should agree with each other more closely than
# either agrees with a text in another language, on whatever quantity carries it.
#
# Nothing here can test that yet. English holds twelve texts and every other language holds one or two,
# so there is no within language spread to compare a between language spread against. The comparison
# needs several texts per language, which is what this fetches.
#
# Texts are taken from Project Gutenberg's own per language index so the selection is not hand picked,
# and the boilerplate is cut as elsewhere. Nothing lands outside build/corpora.

import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "corpora")
INDEX = "https://www.gutenberg.org/browse/languages/%s"
AGENT = {"User-Agent": "MMgr-research/1.0 (https://github.com/dstroy0/MMgr; dquigg123@gmail.com)"}

# Code, name, and the script family, so a logographic case sits beside the alphabetic ones
LANGUAGES = (
    ("fr", "french"), ("de", "german"), ("es", "spanish"), ("it", "italian"),
    ("nl", "dutch"), ("pt", "portuguese"), ("fi", "finnish"), ("zh", "chinese"),
)

STARTS = ("*** START OF THE PROJECT GUTENBERG", "*** START OF THIS PROJECT GUTENBERG")
ENDS = ("*** END OF THE PROJECT GUTENBERG", "*** END OF THIS PROJECT GUTENBERG")
FLOOR = 200000
CEIL = 3000000


def strip(text):
    opened = -1
    for mark in STARTS:
        found = text.find(mark)
        if found >= 0:
            opened = text.find("\n", found)
            break
    closed = -1
    for mark in ENDS:
        found = text.find(mark)
        if found >= 0:
            closed = found
            break
    if (opened >= 0) and (closed > opened):
        return text[opened:closed]
    return None


def get(url, timeout=120):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def ids_for(code, limit):
    """Ebook numbers listed on Gutenberg's index for one language."""
    page = get(INDEX % code, timeout=180)
    found = []
    for match in re.finditer(r'/ebooks/(\d+)"', page):
        number = int(match.group(1))
        if number not in found:
            found.append(number)
        if len(found) >= limit * 6:
            break
    return found


def body(number):
    for url in ("https://www.gutenberg.org/cache/epub/%d/pg%d.txt" % (number, number),
                "https://www.gutenberg.org/files/%d/%d-0.txt" % (number, number)):
        try:
            return strip(get(url, timeout=180))
        except Exception:
            continue
    return None


def main():
    wanted = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    os.makedirs(OUT, exist_ok=True)

    for code, name in LANGUAGES:
        try:
            numbers = ids_for(code, wanted)
        except Exception as trouble:
            print("  %-12s index failed: %s" % (name, str(trouble)[:50]))
            continue

        kept = 0
        for number in numbers:
            if kept >= wanted:
                break
            target = os.path.join(OUT, "lang_%s_%d.txt" % (name, number))
            if os.path.isfile(target):
                kept += 1
                continue
            time.sleep(1.0)
            text = body(number)
            if (text is None) or not (FLOOR <= len(text.encode("utf-8")) <= CEIL):
                continue
            with open(target, "w", encoding="utf-8", newline="") as handle:
                handle.write(text)
            kept += 1
            print("  lang_%-10s %-8d %d KB" % (name, number, len(text.encode("utf-8")) // 1024))
        print("  %-12s %d of %d kept\n" % (name, kept, wanted))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
