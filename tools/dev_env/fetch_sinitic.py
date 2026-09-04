#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch languages that share a writing system and do not share speech, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_sinitic.py
#
# Dravidian gave close languages written in unlike scripts, and the reading pulled them apart. The Sinitic
# languages are the same experiment run backwards. Mandarin, Cantonese, Hokkien, Wu and Hakka are not
# mutually intelligible in speech, they separated a very long time ago, and they are written in almost
# entirely the same characters. Calling them dialects is a political convention and not a linguistic
# finding.
#
# So the prediction follows from what the earlier failures suggest the reading is sensitive to. If it
# follows a writing system, these five should sit on top of each other however far apart their speech is,
# and the collapse should be as strong as the Dravidian separation was. If it follows language, they
# should come apart despite the shared characters.
#
# Either answer is worth having and they cannot both be true, which is what makes this worth fetching. The
# encyclopedia is the source because these varieties have their own editions of it and very little else
# that is written down and freely available in any quantity.

import concurrent.futures
import io
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

WANTED_CHARACTERS = 200000
PER_REQUEST = 20
MOST_REQUESTS = 150
PAUSE = 1.1
RETRIES = 2

VARIETIES = (
    ("zh", "mandarin"),
    ("zh-yue", "cantonese"),
    ("nan", "hokkien"),
    ("wuu", "wu"),
    ("hak", "hakka"),
    ("gan", "gan"),
    ("zh-classical", "classical"),
)


def pull(code, offset):
    # Listed and not searched. The search was given the letter a as its query, which is a reasonable term
    # in a Latin encyclopedia and almost absent from one written in Chinese characters, so every one of
    # these varieties came back with nothing and looked like an empty encyclopedia.
    #
    # Opening sections only. A full extract is served one page at a time whatever limit is asked for, so
    # every request was returning a single article and often a stub, which read as an empty encyclopedia.
    # Opening sections are served twenty at a time and are still ordinary prose.
    query = {
        "action": "query", "format": "json", "generator": "allpages",
        "gaplimit": str(PER_REQUEST), "gapnamespace": "0", "gapfilterredir": "nonredirects",
        "prop": "extracts", "explaintext": "1", "exintro": "1", "exlimit": "20",
    }
    if offset:
        query["gapcontinue"] = offset
    url = "https://%s.wikipedia.org/w/api.php?%s" % (code, urllib.parse.urlencode(query))
    request = urllib.request.Request(url, headers=AGENT)

    payload = None
    for attempt in range(RETRIES):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                payload = json.loads(response.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as refused:
            if refused.code != 429:
                raise
            time.sleep(PAUSE * (3 ** (attempt + 1)))
    if payload is None:
        raise RuntimeError("refused after %d attempts" % RETRIES)
    time.sleep(PAUSE)

    found = []
    for page in payload.get("query", {}).get("pages", {}).values():
        text = page.get("extract", "")
        if len(text) > 120:
            found.append(text)
    # Where the listing continues is carried by the answer, since pages are walked and not counted
    onward = payload.get("continue", {}).get("gapcontinue", "")
    return found, onward


def gather(code, name):
    target = os.path.join(CORPORA, "sinitic_%s.txt" % name)
    if os.path.isfile(target) and (os.path.getsize(target) >= WANTED_CHARACTERS):
        return name, os.path.getsize(target), "already held"

    pieces = []
    total = 0
    offset = ""
    trouble = ""
    for _ in range(MOST_REQUESTS):
        if total >= WANTED_CHARACTERS:
            break
        try:
            found, offset = pull(code, offset)
        except Exception as failure:
            trouble = str(failure)[:50]
            break
        for text in found:
            pieces.append(text)
            total += len(text)
        if not offset:
            break

    if total < 60000:
        return name, total, trouble or "too little text"
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("\n".join(pieces))
    return name, total, ""


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  %-14s %-10s %s\n" % ("variety", "characters", "note"))

    for code, name in VARIETIES:
        try:
            landed, total, note = gather(code, name)
        except Exception as failure:
            out.write("  %-14s failed: %s\n" % (name, str(failure)[:50]))
            continue
        out.write("  %-14s %-10d %s\n" % (landed, total, note))
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
