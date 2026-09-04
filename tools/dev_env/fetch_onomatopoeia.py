#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch the words each language keeps for sounds, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_onomatopoeia.py
#
# Hungarian and Polish belong to unrelated families and have farmed the same basin since the Magyars
# arrived into Slavic speaking country around 895. Hungarian took several hundred Slavic loanwords,
# concentrated in agriculture, livestock, tools and religion, which is where two populations sharing a
# livelihood borrow.
#
# Words for sounds are a good place to look for more of that. They sit outside core vocabulary, which
# resists borrowing, and they attach to shared activity: animal calls, tools, work. So the question is
# whether Hungarian and Polish words for sounds resemble each other more than two unrelated languages
# should.
#
# A dictionary that files words by what they are gives the lists directly, and the categories for words
# imitating sounds exist per language. What is fetched is those, for the pair in question and for the
# controls that make the answer readable: Hungarian against its own family, Polish against its own, and
# both against languages they have not shared a border with.
#
# Nothing here decides the question. It gathers the words, and the comparison is a separate matter.

import io
import json
import os
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

API = "https://en.wiktionary.org/w/api.php"
PAUSE = 1.2

WANTED = (
    ("hungarian", "the pair in question"),
    ("polish", "the pair in question"),
    ("finnish", "hungarian's family, no polish border"),
    ("estonian", "hungarian's family, no polish border"),
    ("czech", "polish's family and its neighbour"),
    ("slovak", "polish's family and its neighbour"),
    ("russian", "polish's family, further off"),
    ("german", "a neighbour of both, unrelated to either"),
    ("romanian", "the region, unrelated to both"),
    ("turkish", "far off, no border"),
    ("spanish", "far off, no border"),
    ("japanese", "far off, another continent"),
)


def members(category, keep=600):
    """Every page a dictionary files under one category."""
    found = []
    onward = ""
    while len(found) < keep:
        query = {
            "action": "query", "format": "json", "list": "categorymembers",
            "cmtitle": "Category:%s" % category, "cmlimit": "500", "cmnamespace": "0",
        }
        if onward:
            query["cmcontinue"] = onward
        request = urllib.request.Request(API + "?" + urllib.parse.urlencode(query), headers=AGENT)
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.loads(response.read().decode("utf-8"))
        for entry in payload.get("query", {}).get("categorymembers", []):
            title = entry.get("title", "")
            if title and (":" not in title):
                found.append(title)
        onward = payload.get("continue", {}).get("cmcontinue", "")
        time.sleep(PAUSE)
        if not onward:
            break
    return found


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  %-14s %-38s %-8s %s\n" % ("language", "why it is here", "words", "note"))

    landed = 0
    for language, why in WANTED:
        target = os.path.join(CORPORA, "onom_%s.txt" % language)
        if os.path.isfile(target):
            with open(target, encoding="utf-8") as handle:
                held = [line.strip() for line in handle if line.strip()]
            out.write("  %-14s %-38s %-8d already held\n" % (language, why, len(held)))
            landed += 1
            continue

        words = []
        # A dictionary files these under more than one name, so both are asked for
        for shape in ("%s onomatopoeias", "%s onomatopoeic terms"):
            try:
                words.extend(members(shape % language.capitalize()))
            except Exception as trouble:
                out.write("  %-14s %-38s %-8s %s\n"
                          % (language, why, "0", str(trouble)[:34]))
                words = []
                break
        words = sorted({word for word in words})
        if len(words) < 10:
            out.write("  %-14s %-38s %-8d too few to compare\n" % (language, why, len(words)))
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write("\n".join(words))
        out.write("  %-14s %-38s %-8d\n" % (language, why, len(words)))
        landed += 1
        out.flush()

    out.write("\n  %d languages have a list worth comparing\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
