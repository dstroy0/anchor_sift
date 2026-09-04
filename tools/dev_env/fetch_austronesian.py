#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch the family that crossed an ocean, with its relatives and its neighbours, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_austronesian.py
#
# Uralic was the test that told descent from contact and the reading followed contact: Finnish went to
# Swedish, Hungarian to Czech, and not one of the three found a relative. Malagasy is the same test set up
# by geography instead of by history.
#
# It is Austronesian, spoken in Madagascar, and its nearest relatives are in Borneo across the Indian
# Ocean. Everything it has borrowed from since is African and French. So descent points one way, several
# thousand kilometres east, and contact points the other, at the coast it sits off. Nothing about the two
# is confounded here in the way that everything in Europe is confounded.
#
# Its relatives and its neighbours are taken from one collection so the content is fixed across all of
# them, which is what the Uralic test could not manage: there the languages came from books, encyclopedia
# articles and translated works mixed together.
#
# Ancient Malagasy is not reachable and is worth naming as absent. What survives of it is Sorabe, written
# in Arabic script, held in manuscript and not published as text, so what is measured here is the modern
# language only.

import gzip
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

API = "https://opus.nlpl.eu/opusapi/"
CORPUS = "TED2020"
LEAST = 60000
CAP = 4000000
PAUSE = 0.5

WANTED = {
    "mg": ("malagasy", "austronesian, in africa"),
    "id": ("indonesian", "austronesian, its family"),
    "ms": ("malay", "austronesian, its family"),
    "tl": ("tagalog", "austronesian, its family"),
    "ceb": ("cebuano", "austronesian, its family"),
    "fr": ("french", "what it borrowed from"),
    "sw": ("swahili", "the coast it sits off"),
    "am": ("amharic", "the region, unrelated"),
    "so": ("somali", "the region, unrelated"),
    "pt": ("portuguese", "a control, neither"),
}


def get(url, timeout=300):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  %-14s %-28s %-10s %s\n" % ("language", "why it is here", "characters", "note"))

    landed = 0
    for code in sorted(WANTED):
        name, why = WANTED[code]
        target = os.path.join(CORPORA, "aus_%s.txt" % name)
        if os.path.isfile(target) and (os.path.getsize(target) >= LEAST):
            out.write("  %-14s %-28s %-10d already held\n" % (name, why, os.path.getsize(target)))
            landed += 1
            continue
        try:
            payload = json.loads(get(API + "?" + urllib.parse.urlencode(
                {"corpus": CORPUS, "source": code, "preprocessing": "mono",
                 "version": "latest"})).decode("utf-8"))
            entries = payload.get("corpora", []) if isinstance(payload, dict) else []
            time.sleep(PAUSE)
            if not entries:
                out.write("  %-14s %-28s %-10s not offered on its own\n" % (name, why, "0"))
                continue
            entries.sort(key=lambda entry: -int(entry.get("size", 0) or 0))
            url = entries[0].get("url")
            blob = get(url)
            if url.endswith(".gz"):
                blob = gzip.decompress(blob)
            text = blob.decode("utf-8", errors="replace")[:CAP]
        except Exception as trouble:
            out.write("  %-14s %-28s %-10s %s\n" % (name, why, "0", str(trouble)[:38]))
            continue

        if len(text) < LEAST:
            out.write("  %-14s %-28s %-10d too little text\n" % (name, why, len(text)))
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        out.write("  %-14s %-28s %-10d\n" % (name, why, len(text)))
        landed += 1
        out.flush()

    out.write("\n  %d languages landed, all from one collection\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
