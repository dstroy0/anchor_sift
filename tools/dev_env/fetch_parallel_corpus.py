#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch one text in many languages, so a comparison holds content fixed, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_parallel_corpus.py
#
# Every cross language reading in this work so far compares different books. Greek is epic poetry, Dutch
# is a novel, several are encyclopedia articles, and one Greek text turned out to be a dictionary and had
# to be thrown out after it had already been measured. A difference between two of those is a difference
# between two books that happen to be in different languages, and nothing in the measurement separates the
# two.
#
# A translation of one text into many languages removes it. The content is held fixed by construction, so
# what remains between two versions is the language. It also reaches languages a book catalog does not
# carry, including Vietnamese and Urdu, and it reaches them without hammering an encyclopedia that has
# been refusing these requests all evening.
#
# What is fetched is one side of a parallel corpus per language, which is that language's whole text with
# no alignment needed, since nothing here compares sentence to sentence. Files are named so their source
# and their nature are never in doubt, and the languages already held from books stay where they are so
# the two kinds can be measured against each other.

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

API = "https://opus.nlpl.eu/opusapi/"
CORPUS = "bible-uedin"
PAUSE = 0.6
LEAST = 60000

NAMES = {
    "vi": "vietnamese", "ur": "urdu", "hi": "hindi", "bn": "bengali", "ta": "tamil",
    "ko": "korean", "id": "indonesian", "uk": "ukrainian", "ar": "arabic", "fa": "persian",
    "th": "thai", "sw": "swahili", "tr": "turkish", "ms": "malay", "he": "hebrew",
    "el": "greek", "ru": "russian", "pl": "polish", "cs": "czech", "hu": "hungarian",
    "fi": "finnish", "de": "german", "es": "spanish", "fr": "french", "it": "italian",
    "nl": "dutch", "sv": "swedish", "da": "danish", "no": "norwegian", "ro": "romanian",
    "pt": "portuguese", "zh": "chinese", "ja": "japanese", "af": "afrikaans",
    "eo": "esperanto", "et": "estonian", "lt": "lithuanian", "lv": "latvian",
    "sl": "slovenian", "sq": "albanian", "hy": "armenian", "ka": "georgian",
    "kk": "kazakh", "my": "burmese", "ne": "nepali", "mr": "marathi", "te": "telugu",
    "ml": "malayalam", "gu": "gujarati", "pa": "punjabi", "am": "amharic",
    "ceb": "cebuano", "tl": "tagalog", "mg": "malagasy", "ht": "haitian",
}


def get(url, timeout=180):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def offered():
    """Which languages the parallel corpus holds."""
    payload = json.loads(get(API + "?" + urllib.parse.urlencode(
        {"corpus": CORPUS, "languages": "True"})).decode("utf-8"))
    values = payload if isinstance(payload, list) else list(payload.values())[0]
    return [str(one) for one in values]


def link_for(code):
    """The download the corpus offers for one language on its own."""
    payload = json.loads(get(API + "?" + urllib.parse.urlencode(
        {"corpus": CORPUS, "source": code, "preprocessing": "mono",
         "version": "latest"})).decode("utf-8"))
    entries = payload.get("corpora", []) if isinstance(payload, dict) else []
    for entry in entries:
        url = entry.get("url", "")
        if url.endswith(".txt.gz") or url.endswith(".txt"):
            return url
    return entries[0].get("url") if entries else None


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)

    try:
        have = offered()
    except Exception as trouble:
        out.write("  could not list the corpus: %s\n" % trouble)
        out.flush()
        return 1

    wanted = [code for code in NAMES if code in have]
    out.write("  the corpus holds %d languages, %d of them named here\n\n" % (len(have), len(wanted)))
    out.write("  %-14s %-10s %s\n" % ("language", "characters", "note"))

    landed = 0
    for code in sorted(wanted):
        name = NAMES[code]
        target = os.path.join(CORPORA, "para_%s.txt" % name)
        if os.path.isfile(target) and (os.path.getsize(target) >= LEAST):
            out.write("  %-14s %-10d already held\n" % (name, os.path.getsize(target)))
            landed += 1
            continue
        try:
            url = link_for(code)
            time.sleep(PAUSE)
            if not url:
                out.write("  %-14s %-10s no download offered\n" % (name, "0"))
                continue
            blob = get(url)
            if url.endswith(".gz"):
                import gzip
                blob = gzip.decompress(blob)
            text = blob.decode("utf-8", errors="replace")
        except Exception as trouble:
            out.write("  %-14s %-10s %s\n" % (name, "0", str(trouble)[:60]))
            continue

        if len(text) < LEAST:
            out.write("  %-14s %-10d too little text\n" % (name, len(text)))
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        out.write("  %-14s %-10d\n" % (name, len(text)))
        landed += 1
        out.flush()
        time.sleep(PAUSE)

    out.write("\n  %d languages of one text landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
