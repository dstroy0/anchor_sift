#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Get how the sound words are said, not how they are spelled, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_ipa.py
#
# Words for sounds follow the border and not the family: every bordering pair of languages measured came
# out closer than every non-bordering pair, and Hungarian sat nearer Czech, which it is unrelated to, than
# Finnish, which is its own family. That was measured on spelling with the accents stripped off, and
# spelling is the wrong thing to measure for this.
#
# Hungarian writes sz for one consonant and Polish writes sz for another. Two words said the same way are
# counted far apart, and two written the same way are counted close when they are not. The effect showed
# through that, which means the noise was working against it, but the reading is still of letters.
#
# The dictionary carries transcriptions beside the words. Fetching those replaces the letters with the
# sounds and removes the whole confound, which is the difference between saying these words resemble each
# other and saying these spellings do.
#
# Pages are asked for fifty at a time, since asking one at a time would be twelve hundred requests, and
# the pace is kept slow because this interface has refused this work several times tonight for asking too
# quickly.

import io
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

API = "https://en.wiktionary.org/w/api.php"
BATCH = 50
PAUSE = 1.4
RETRIES = 3

LANGUAGES = {
    "hungarian": ("Hungarian", "hu"),
    "polish": ("Polish", "pl"),
    "finnish": ("Finnish", "fi"),
    "czech": ("Czech", "cs"),
    "estonian": ("Estonian", "et"),
}


def ask(titles):
    query = {
        "action": "query", "format": "json", "prop": "revisions",
        "rvprop": "content", "rvslots": "main", "titles": "|".join(titles),
    }
    url = API + "?" + urllib.parse.urlencode(query)
    for attempt in range(RETRIES):
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception:
            time.sleep(PAUSE * (3 ** (attempt + 1)))
    return None


def transcription(wikitext, heading, code):
    """The transcription a page gives for one language, where it gives one.

    A page holds every language that spells a word that way, so the section has to be found first or a
    Polish word can come back with its Czech pronunciation.
    """
    if not wikitext:
        return None
    start = wikitext.find("==%s==" % heading)
    if start < 0:
        return None
    end = wikitext.find("\n==", start + 4)
    section = wikitext[start:end if end > 0 else len(wikitext)]

    found = re.search(r"\{\{IPA\|%s\|([^}|]+)" % code, section)
    if not found:
        found = re.search(r"\{\{IPA\|([^}|]*/[^}|]+)", section)
    if not found:
        return None
    said = found.group(1).strip().strip("/[]")
    said = re.sub(r"[ˈˌ\.\s]", "", said)
    return said or None


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-12s %-9s %-9s %s\n" % ("language", "words", "with ipa", "share"))

    for language, (heading, code) in sorted(LANGUAGES.items()):
        source = os.path.join(CORPORA, "onom_%s.txt" % language)
        target = os.path.join(CORPORA, "ipa_%s.txt" % language)
        if not os.path.isfile(source):
            continue
        if os.path.isfile(target):
            with open(target, encoding="utf-8") as handle:
                held = [line for line in handle if line.strip()]
            out.write("  %-12s %-9s %-9d already held\n" % (language, "", len(held)))
            continue

        with open(source, encoding="utf-8") as handle:
            words = [line.strip() for line in handle if line.strip()]

        said = {}
        for start in range(0, len(words), BATCH):
            payload = ask(words[start:start + BATCH])
            time.sleep(PAUSE)
            if payload is None:
                out.write("  %-12s refused partway, keeping %d\n" % (language, len(said)))
                break
            for page in payload.get("query", {}).get("pages", {}).values():
                title = page.get("title", "")
                revisions = page.get("revisions", [])
                if not revisions:
                    continue
                content = revisions[0].get("slots", {}).get("main", {}).get("*", "")
                heard = transcription(content, heading, code)
                if heard:
                    said[title] = heard

        if said:
            with open(target, "w", encoding="utf-8", newline="") as handle:
                for word in sorted(said):
                    handle.write("%s\t%s\n" % (word, said[word]))
        out.write("  %-12s %-9d %-9d %.2f\n"
                  % (language, len(words), len(said), len(said) / float(max(len(words), 1))))
        out.flush()

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
