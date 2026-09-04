#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch African languages on the text already held in 43 others, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_african.py
#
# Nothing measured here is African except Afrikaans, which is Germanic, and Arabic, which arrived through
# scripture. Four families are reachable on the parallel text this work already holds in 43 languages, so
# the content is fixed and they arrive directly comparable to everything measured on it: Bantu in Zulu,
# Xhosa and Shona, Cushitic in Somali, Semitic in Amharic, and Atlantic in Wolof.
#
# One pair in that set is the test the earlier failures have been building toward. Zulu and Xhosa are both
# Nguni, close enough to be partly mutually intelligible, and both are written in the Latin alphabet in
# the same corpus. Tamil and Malayalam are as close and came out the widest apart of seven, and the excuse
# available there was that their scripts encode different distinctions. Zulu and Xhosa remove that excuse:
# same family, same closeness, same script, same content, same translators.
#
# So the prediction has no way out. If the reading pairs them, it can find a close relationship when
# nothing about the writing gets in the way. If it does not, then what the earlier failures showed is not
# that scripts confuse it but that it does not read language at all.

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
CORPUS = "bible-uedin"
LEAST = 60000
PAUSE = 0.5

WANTED = {
    "zu": ("zulu", "bantu, nguni"),
    "xh": ("xhosa", "bantu, nguni"),
    "sn": ("shona", "bantu, further off"),
    "am": ("amharic", "semitic"),
    "so": ("somali", "cushitic"),
    "wo": ("wolof", "atlantic"),
    "af": ("afrikaans", "germanic, for contrast"),
}


def get(url, timeout=300):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  %-14s %-22s %-10s %s\n" % ("language", "family", "characters", "note"))

    landed = 0
    for code in sorted(WANTED):
        name, family = WANTED[code]
        target = os.path.join(CORPORA, "afr_%s.txt" % name)
        if os.path.isfile(target) and (os.path.getsize(target) >= LEAST):
            out.write("  %-14s %-22s %-10d already held\n"
                      % (name, family, os.path.getsize(target)))
            landed += 1
            continue
        try:
            payload = json.loads(get(API + "?" + urllib.parse.urlencode(
                {"corpus": CORPUS, "source": code, "preprocessing": "mono",
                 "version": "latest"})).decode("utf-8"))
            entries = payload.get("corpora", []) if isinstance(payload, dict) else []
            time.sleep(PAUSE)
            if not entries:
                out.write("  %-14s %-22s %-10s not offered on its own\n" % (name, family, "0"))
                continue
            entries.sort(key=lambda entry: -int(entry.get("size", 0) or 0))
            url = entries[0].get("url")
            blob = get(url)
            if url.endswith(".gz"):
                blob = gzip.decompress(blob)
            text = blob.decode("utf-8", errors="replace")
        except Exception as trouble:
            out.write("  %-14s %-22s %-10s %s\n" % (name, family, "0", str(trouble)[:44]))
            continue

        if len(text) < LEAST:
            out.write("  %-14s %-22s %-10d too little text\n" % (name, family, len(text)))
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        out.write("  %-14s %-22s %-10d\n" % (name, family, len(text)))
        landed += 1
        out.flush()

    out.write("\n  %d languages landed on the text already held in 43 others\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
