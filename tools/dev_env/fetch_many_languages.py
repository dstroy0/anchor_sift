#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Widen the language corpus enough to test convergence, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_many_languages.py
#
# Under the tightest numbering four languages landed between 4.76 and 7.84 where they had spanned 15.61 to
# 31.44 as given, and Greek at 141 symbols sat on the same value as German at 73. Four languages cannot
# carry that, and all four use the same alphabet, so what looks like convergence could be one writing
# system measured four times.
#
# Widening it has to vary the writing system and the family separately, since they travel together in
# western Europe and neither can be blamed while they do. What is fetched here covers Cyrillic, Greek,
# Hebrew, Arabic and Japanese script alongside the Latin alphabet, and Slavic, Uralic, Turkic, Semitic,
# Japonic and Sino-Tibetan alongside Romance and Germanic. Chinese is already held and is the case that
# decides it, carrying thousands of symbols where the rest carry under two hundred.
#
# Texts come from a catalog that states its own language, so nothing here guesses at what a file is. They
# are fetched several at a time because each one waits on a distant server and the waiting is the whole
# cost.

import concurrent.futures
import io
import json
import os
import re
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0"}

CATALOG = "https://gutendex.com/books"
WANTED_PER_LANGUAGE = 4
LEAST = 80000
WORKERS = 8

LANGUAGES = (
    ("ru", "russian"), ("pl", "polish"), ("cs", "czech"), ("hu", "hungarian"),
    ("el", "greek"), ("la", "latin"), ("da", "danish"), ("sv", "swedish"),
    ("no", "norwegian"), ("ca", "catalan"), ("eo", "esperanto"), ("tl", "tagalog"),
    ("is", "icelandic"), ("cy", "welsh"), ("he", "hebrew"), ("ar", "arabic"),
    ("ro", "romanian"), ("bg", "bulgarian"), ("sr", "serbian"), ("et", "estonian"),
    ("ja", "japanese"), ("lt", "lithuanian"), ("sl", "slovenian"), ("af", "afrikaans"),
    # Vietnamese is isolating like Chinese and written in a Latin alphabet, which is the one pairing
    # that separates what a language does from what it is written in. Urdu is a second abjad beside
    # Hebrew, so that script family stops resting on one language.
    ("vi", "vietnamese"), ("ur", "urdu"), ("fa", "persian"), ("hi", "hindi"),
    ("bn", "bengali"), ("ta", "tamil"), ("ko", "korean"), ("id", "indonesian"),
    ("uk", "ukrainian"), ("ga", "irish"), ("br", "breton"), ("mi", "maori"),
)


def get(url, timeout=120):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def listing(code):
    """Books the catalog itself files under one language, newest listing first."""
    query = urllib.parse.urlencode({"languages": code, "mime_type": "text/plain"})
    try:
        payload = json.loads(get("%s?%s" % (CATALOG, query)).decode("utf-8"))
    except Exception:
        return []
    found = []
    for entry in payload.get("results", []):
        for kind, link in entry.get("formats", {}).items():
            if kind.startswith("text/plain") and not link.endswith(".zip"):
                found.append((entry.get("id"), link))
                break
    return found


def strip_wrapper(text):
    """Drop the catalog's own header and footer so only the work is measured."""
    start = re.search(r"\*\*\*\s*START OF TH[EI]S? PROJECT GUTENBERG[^\*]*\*\*\*", text)
    if start:
        text = text[start.end():]
    stop = re.search(r"\*\*\*\s*END OF TH[EI]S? PROJECT GUTENBERG[^\*]*\*\*\*", text)
    if stop:
        text = text[:stop.start()]
    return text


def gather(code, name):
    """Store up to the wanted count for one language, skipping anything too short to measure."""
    kept = 0
    notes = []
    for number, link in listing(code):
        if kept >= WANTED_PER_LANGUAGE:
            break
        target = os.path.join(CORPORA, "lang_%s_%s.txt" % (name, number))
        if os.path.isfile(target):
            kept += 1
            continue
        try:
            text = strip_wrapper(get(link).decode("utf-8", errors="replace"))
        except Exception as trouble:
            notes.append("%s failed: %s" % (number, trouble))
            continue
        if len(text) < LEAST:
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        kept += 1
    return name, kept, notes


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)

    landed = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        running = [pool.submit(gather, code, name) for code, name in LANGUAGES]
        for done in concurrent.futures.as_completed(running):
            try:
                name, kept, notes = done.result()
            except Exception as trouble:
                out.write("  a language failed outright: %s\n" % trouble)
                continue
            landed[name] = kept
            out.write("  %-14s %d\n" % (name, kept))
            out.flush()

    have = sum(1 for count in landed.values() if count >= 2)
    out.write("\n  %d languages landed with at least two texts, %d texts in all\n"
              % (have, sum(landed.values())))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
