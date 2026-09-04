#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Reach the languages the book catalog does not carry, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_wikipedia_languages.py
#
# Vietnamese and Urdu have no plain text holdings in the book catalog, and neither do Hindi, Bengali,
# Tamil, Korean or Indonesian. Vietnamese is the one language worth the most here: it is isolating the way
# Chinese is and it is written in a Latin alphabet, so it is the only case on hand that separates what a
# language does from what it is written in. Every other pairing available has those two travelling
# together.
#
# An encyclopedia carries all of them. It is also a different kind of writing from a novel, and comparing
# encyclopedia text in one language against a novel in another would put that difference inside every
# comparison without it being visible. So languages already held from the book catalog are fetched here as
# well, and the gap between a language's two readings is the size of the genre effect, measured instead of
# assumed. Anything fetched here is named so its source is never in doubt.

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

WANTED_CHARACTERS = 220000
PER_REQUEST = 20
MOST_REQUESTS = 40
# One language at a time with a pause between requests. Six at once with no pacing was refused outright
# for every language, and a public interface that answers 429 is asking to be asked more slowly. The
# waits are kept short: quadrupling four times means a language whose requests are all refused takes
# hours to report that it failed, which is how the first attempt spent its time.
WORKERS = 1
PAUSE = 1.1
RETRIES = 2

MISSING = ("vi", "ur", "hi", "bn", "ta", "ko", "id", "uk", "ar", "fa", "th", "sw", "tr", "ms")
# Held from the book catalog as well, so the difference between an encyclopedia and a novel is a number
CONTROLS = ("de", "es", "zh", "ja", "fi", "el")

NAMES = {
    "vi": "vietnamese", "ur": "urdu", "hi": "hindi", "bn": "bengali", "ta": "tamil",
    "ko": "korean", "id": "indonesian", "uk": "ukrainian", "ar": "arabic", "fa": "persian",
    "th": "thai", "sw": "swahili", "tr": "turkish", "ms": "malay",
    "de": "german", "es": "spanish", "zh": "chinese", "ja": "japanese",
    "fi": "finnish", "el": "greek",
}


def pull(code, seen, offset):
    """A batch of article texts from one language's encyclopedia, longest first.

    Random articles are almost all stubs in a smaller encyclopedia: eight of them returned 178 characters
    in Vietnamese, so reaching a usable length that way would take thousands of requests. Searching
    instead for articles and taking them by size gets real prose in a few.
    """
    query = {
        "action": "query", "format": "json", "generator": "search",
        "gsrsearch": "a", "gsrlimit": str(PER_REQUEST), "gsroffset": str(offset),
        "gsrsort": "just_match", "gsrnamespace": "0",
        "prop": "extracts", "explaintext": "1", "exlimit": "max",
    }
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
            # Backing off further each time, since a refusal means the last pace was still too fast
            time.sleep(PAUSE * (3 ** (attempt + 1)))
    if payload is None:
        raise RuntimeError("refused after %d attempts" % RETRIES)
    time.sleep(PAUSE)

    found = []
    for page in payload.get("query", {}).get("pages", {}).values():
        text = page.get("extract", "")
        title = page.get("title", "")
        if (len(text) > 600) and (title not in seen):
            seen.add(title)
            found.append(text)
    return found


def gather(code):
    """Enough text in one language to measure, written to a file naming its source."""
    name = NAMES.get(code, code)
    target = os.path.join(CORPORA, "wiki_%s_1.txt" % name)
    if os.path.isfile(target) and (os.path.getsize(target) >= WANTED_CHARACTERS):
        return name, os.path.getsize(target), "already held"

    pieces = []
    total = 0
    seen = set()
    trouble = ""
    offset = 0
    for _ in range(MOST_REQUESTS):
        if total >= WANTED_CHARACTERS:
            break
        try:
            found = pull(code, seen, offset)
        except Exception as failure:
            trouble = str(failure)
            break
        offset += PER_REQUEST
        if not found:
            break
        for text in found:
            pieces.append(text)
            total += len(text)
    if total < 40000:
        return name, total, trouble or "too little text"

    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("\n".join(pieces))
    return name, total, ""


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)

    codes = list(MISSING) + list(CONTROLS)
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        running = {pool.submit(gather, code): code for code in codes}
        for done in concurrent.futures.as_completed(running):
            try:
                name, total, note = done.result()
            except Exception as failure:
                out.write("  %-14s failed outright: %s\n" % (running[done], failure))
                continue
            out.write("  %-14s %-9d %s\n" % (name, total, note))
            out.flush()

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
