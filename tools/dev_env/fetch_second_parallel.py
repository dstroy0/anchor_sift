#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch a second work in many languages, and its original, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_second_parallel.py
#
# One work in 43 languages showed that holding the content fixed costs the family result almost nothing.
# It cannot show whether a language reads the same way when the fixed content changes, because there was
# only one. A second work in the same languages answers that: a reading that belongs to a language holds
# across both, and one that belongs to a book does not.
#
# This one is worth more than a second sample. The languages in it are translations of a work whose
# original is classical Arabic, and that original is here too, so the poetic source sits beside forty
# renderings of itself. Earlier work here found that translation compresses a vocabulary, and this is the
# case where that can be measured with the content held exactly fixed and only the act of translating
# varying.
#
# The original is stored under its own name so it is never mistaken for one of the translations, since it
# is the only text in the set that nobody translated.

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
CORPUS = "Tanzil"
PAUSE = 0.5
LEAST = 60000

NAMES = {
    "ar": "arabic", "ur": "urdu", "hi": "hindi", "bn": "bengali", "ta": "tamil",
    "ko": "korean", "id": "indonesian", "uk": "ukrainian", "fa": "persian",
    "th": "thai", "sw": "swahili", "tr": "turkish", "ms": "malay", "he": "hebrew",
    "el": "greek", "ru": "russian", "pl": "polish", "cs": "czech", "hu": "hungarian",
    "fi": "finnish", "de": "german", "es": "spanish", "fr": "french", "it": "italian",
    "nl": "dutch", "sv": "swedish", "no": "norwegian", "ro": "romanian",
    "pt": "portuguese", "zh": "chinese", "ja": "japanese", "az": "azerbaijani",
    "bg": "bulgarian", "bs": "bosnian", "dv": "divehi", "ha": "hausa",
    "ml": "malayalam", "sd": "sindhi", "so": "somali", "sq": "albanian",
    "tg": "tajik", "tt": "tatar", "ug": "uyghur", "am": "amharic",
}


def get(url, timeout=180):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def fetch_one(code):
    payload = json.loads(get(API + "?" + urllib.parse.urlencode(
        {"corpus": CORPUS, "source": code, "preprocessing": "mono",
         "version": "latest"})).decode("utf-8"))
    entries = payload.get("corpora", []) if isinstance(payload, dict) else []
    if not entries:
        return None
    entries.sort(key=lambda entry: -int(entry.get("size", 0) or 0))
    url = entries[0].get("url")
    if not url:
        return None
    blob = get(url)
    if url.endswith(".gz"):
        import gzip
        blob = gzip.decompress(blob)
    return blob.decode("utf-8", errors="replace")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)

    try:
        payload = json.loads(get(API + "?" + urllib.parse.urlencode(
            {"corpus": CORPUS, "languages": "True"})).decode("utf-8"))
        have = [str(one) for one in
                (payload if isinstance(payload, list) else list(payload.values())[0])]
    except Exception as trouble:
        out.write("  could not list the work: %s\n" % trouble)
        out.flush()
        return 1

    wanted = [code for code in NAMES if code in have]
    out.write("  the work exists in %d languages, %d of them named here\n\n" % (len(have), len(wanted)))
    out.write("  %-14s %-10s %s\n" % ("language", "characters", "note"))

    landed = 0
    for code in sorted(wanted):
        name = NAMES[code]
        # The original is not a translation and is kept apart, since every question below turns on that
        stem = "source_arabic" if code == "ar" else "para2_%s" % name
        target = os.path.join(CORPORA, "%s.txt" % stem)
        if os.path.isfile(target) and (os.path.getsize(target) >= LEAST):
            out.write("  %-14s %-10d already held\n" % (name, os.path.getsize(target)))
            landed += 1
            continue
        try:
            text = fetch_one(code)
            time.sleep(PAUSE)
        except Exception as trouble:
            out.write("  %-14s %-10s %s\n" % (name, "0", str(trouble)[:56]))
            continue
        if (text is None) or (len(text) < LEAST):
            out.write("  %-14s %-10d too little text\n" % (name, len(text or "")))
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        out.write("  %-14s %-10d %s\n" % (name, len(text), "the original" if code == "ar" else ""))
        landed += 1
        out.flush()

    out.write("\n  %d languages of the second work landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
