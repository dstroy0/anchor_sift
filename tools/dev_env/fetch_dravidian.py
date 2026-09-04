#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch a family whose branchings are dated, on one fixed text, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_dravidian.py
#
# The family result here was scored against a tree that is argued from cognates and sound
# correspondences, which was recorded as a weakness: where the reading and the tree disagree nothing says
# which is wrong. Dravidian is a better case. Its branchings are old and its separations are long, so the
# order of them is not much in dispute, and it gives a graded prediction instead of a yes or no.
#
# What is expected before anything is measured: Tamil and Malayalam nearest each other, having separated
# around the ninth century; Kannada beside that pair inside South Dravidian; Telugu furthest, being South
# Central and split far earlier. An ordering of three distances is a great deal harder to satisfy by
# chance than a grouping.
#
# All four come from one parallel text so the content is fixed and cannot carry the result, which the
# earlier reading of these languages could not claim. Sanskrit comes with them: it is Indo-European and
# not Dravidian at all, so it is the outside case that must sit apart from every one of them, and if it
# does not then the reading is measuring the writing systems of the subcontinent and not its languages.

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
CORPUS = "QED"
LEAST = 60000
PAUSE = 0.5

WANTED = {
    "ta": "tamil", "ml": "malayalam", "kn": "kannada", "te": "telugu",
    "sa": "sanskrit", "hi": "hindi", "mr": "marathi", "bn": "bengali",
}


def get(url, timeout=240):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  %-14s %-10s %s\n" % ("language", "characters", "note"))

    landed = 0
    for code in sorted(WANTED):
        name = WANTED[code]
        target = os.path.join(CORPORA, "drav_%s.txt" % name)
        if os.path.isfile(target) and (os.path.getsize(target) >= LEAST):
            out.write("  %-14s %-10d already held\n" % (name, os.path.getsize(target)))
            landed += 1
            continue
        try:
            payload = json.loads(get(API + "?" + urllib.parse.urlencode(
                {"corpus": CORPUS, "source": code, "preprocessing": "mono",
                 "version": "latest"})).decode("utf-8"))
            entries = payload.get("corpora", []) if isinstance(payload, dict) else []
            time.sleep(PAUSE)
            if not entries:
                out.write("  %-14s %-10s not offered on its own\n" % (name, "0"))
                continue
            entries.sort(key=lambda entry: -int(entry.get("size", 0) or 0))
            url = entries[0].get("url")
            blob = get(url)
            if url.endswith(".gz"):
                import gzip
                blob = gzip.decompress(blob)
            text = blob.decode("utf-8", errors="replace")
        except Exception as trouble:
            out.write("  %-14s %-10s %s\n" % (name, "0", str(trouble)[:56]))
            continue

        if len(text) < LEAST:
            out.write("  %-14s %-10d too little text\n" % (name, len(text)))
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        out.write("  %-14s %-10d\n" % (name, len(text)))
        landed += 1
        out.flush()

    out.write("\n  %d languages of one text landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
