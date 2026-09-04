#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch the four cases that separate a language from its writing inside Chinese, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_chinese_pairs.py
#
# Everything measured so far confounds a language with what it is written in. Dravidian gave close
# languages in unlike scripts and the reading pulled them apart. Uralic gave a family without shared
# contact and the reading lost it. What is missing is the case where one changes and the other does not,
# and Chinese supplies both halves of it.
#
# Mandarin and Cantonese are not mutually intelligible in speech and are written in the same characters.
# Simplified and traditional are one language written in two character sets, which is a script change with
# no language change at all.
#
# So the prediction is sharp and it is a pair. If the reading follows writing, Mandarin and Cantonese sit
# close while simplified and traditional sit far apart, which is the opposite of what the languages
# themselves would give. If it follows language, the two results swap.
#
# Subtitles carry Cantonese, which almost nothing else freely available does. Software translations carry
# the simplified and traditional pair, which is a narrow kind of writing and is used here only against
# itself.

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
CAP = 8000000
LEAST = 40000
PAUSE = 0.6

WANTED = (
    ("OpenSubtitles", "zh", "sinitic_mandarin"),
    ("OpenSubtitles", "yue", "sinitic_cantonese"),
    ("GNOME", "zh_CN", "sinitic_simplified"),
    ("GNOME", "zh_TW", "sinitic_traditional"),
    ("GNOME", "zh_HK", "sinitic_hongkong"),
)


def get(url, timeout=300, cap=None):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read(cap) if cap else response.read()


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  %-22s %-10s %s\n" % ("corpus", "characters", "note"))

    for corpus, code, name in WANTED:
        target = os.path.join(CORPORA, "%s.txt" % name)
        if os.path.isfile(target) and (os.path.getsize(target) >= LEAST):
            out.write("  %-22s %-10d already held\n" % (name, os.path.getsize(target)))
            continue
        try:
            payload = json.loads(get(API + "?" + urllib.parse.urlencode(
                {"corpus": corpus, "source": code, "preprocessing": "mono",
                 "version": "latest"})).decode("utf-8"))
            entries = payload.get("corpora", []) if isinstance(payload, dict) else []
            time.sleep(PAUSE)
            if not entries:
                out.write("  %-22s %-10s not offered on its own\n" % (name, "0"))
                continue
            # Smallest first, since a subtitle archive runs to gigabytes and only a slice is wanted
            entries.sort(key=lambda entry: int(entry.get("size", 0) or 0))
            picked = next((entry for entry in entries
                           if int(entry.get("size", 0) or 0) > 0), entries[0])
            blob = get(picked["url"], cap=CAP * 4)
            if picked["url"].endswith(".gz"):
                try:
                    blob = gzip.decompress(blob)
                except Exception:
                    blob = gzip.GzipFile(fileobj=io.BytesIO(blob)).read(CAP * 2)
            text = blob.decode("utf-8", errors="replace")[:CAP]
        except Exception as trouble:
            out.write("  %-22s %-10s %s\n" % (name, "0", str(trouble)[:52]))
            continue

        if len(text) < LEAST:
            out.write("  %-22s %-10d too little text\n" % (name, len(text)))
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        out.write("  %-22s %-10d\n" % (name, len(text)))
        out.flush()

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
