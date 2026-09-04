#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Reach Urdu, which neither source used so far carries, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_urdu.py
#
# Urdu is not in the book catalog and not among the 102 languages of the parallel text that brought in
# Vietnamese, and the encyclopedia refused every request for it. It is worth the trouble because it is a
# second abjad beside Hebrew, so that script stops resting on one language, and because it is Indo-Aryan
# written in a Perso-Arabic script while Hindi is the same language family written in Devanagari. Those
# two together separate a script from a family more cleanly than anything else available.
#
# The same archive holds many parallel texts and not only the one already used. This asks which of them
# carry Urdu, prefers whichever is closest in kind to what the other languages were read from, and takes
# the largest that qualifies. A translation of one work into many languages keeps the content fixed the
# way the earlier fetch did, so Urdu arrives comparable to the rest instead of as an encyclopedia sample
# sitting beside a shelf of scripture.

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
WANT = "ur"
LEAST = 60000
PAUSE = 0.6

# Preferred in this order: one work translated many times keeps the content fixed the way the rest of
# these languages were read, and a pile of software strings or subtitles does not
FAVOR = ("Tanzil", "bible-uedin", "TED2020", "QED", "GlobalVoices", "Tatoeba", "wikimedia")


def get(url, timeout=180):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)

    try:
        payload = json.loads(get(API + "?" + urllib.parse.urlencode(
            {"source": WANT, "corpora": "True"})).decode("utf-8"))
        holding = payload if isinstance(payload, list) else list(payload.values())[0]
        holding = [str(one) for one in holding]
    except Exception as trouble:
        out.write("  could not ask which texts hold urdu: %s\n" % trouble)
        out.flush()
        return 1

    out.write("  %d texts hold urdu\n" % len(holding))
    ordered = [name for name in FAVOR if name in holding]
    ordered += [name for name in holding if name not in FAVOR]
    out.write("  trying in order: %s\n\n" % ", ".join(ordered[:8]))

    for corpus in ordered[:8]:
        try:
            payload = json.loads(get(API + "?" + urllib.parse.urlencode(
                {"corpus": corpus, "source": WANT, "preprocessing": "mono",
                 "version": "latest"})).decode("utf-8"))
            entries = payload.get("corpora", []) if isinstance(payload, dict) else []
            time.sleep(PAUSE)
            if not entries:
                out.write("  %-16s offers no single language download\n" % corpus)
                continue
            entries.sort(key=lambda entry: -int(entry.get("size", 0) or 0))
            url = entries[0].get("url")
            if not url:
                out.write("  %-16s gave no address\n" % corpus)
                continue

            blob = get(url)
            if url.endswith(".gz"):
                import gzip
                blob = gzip.decompress(blob)
            text = blob.decode("utf-8", errors="replace")
        except Exception as trouble:
            out.write("  %-16s failed: %s\n" % (corpus, str(trouble)[:70]))
            continue

        if len(text) < LEAST:
            out.write("  %-16s only %d characters\n" % (corpus, len(text)))
            continue

        target = os.path.join(CORPORA, "para_urdu.txt")
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        out.write("  %-16s %d characters, stored as para_urdu\n" % (corpus, len(text)))

        # Hindi from the same text where it exists, since the pair is the reason Urdu was worth chasing
        try:
            payload = json.loads(get(API + "?" + urllib.parse.urlencode(
                {"corpus": corpus, "source": "hi", "preprocessing": "mono",
                 "version": "latest"})).decode("utf-8"))
            entries = payload.get("corpora", []) if isinstance(payload, dict) else []
            if entries:
                entries.sort(key=lambda entry: -int(entry.get("size", 0) or 0))
                blob = get(entries[0]["url"])
                if entries[0]["url"].endswith(".gz"):
                    import gzip
                    blob = gzip.decompress(blob)
                hindi = blob.decode("utf-8", errors="replace")
                if len(hindi) >= LEAST:
                    with open(os.path.join(CORPORA, "para2_hindi.txt"), "w",
                              encoding="utf-8", newline="") as handle:
                        handle.write(hindi)
                    out.write("  %-16s %d characters of hindi from the same text\n"
                              % (corpus, len(hindi)))
        except Exception as trouble:
            out.write("  hindi from the same text failed: %s\n" % str(trouble)[:70])

        out.flush()
        return 0

    out.write("\n  nothing offered a usable download\n")
    out.flush()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
