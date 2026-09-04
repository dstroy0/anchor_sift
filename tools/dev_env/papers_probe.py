#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find where the same problem has been worked on language by language, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/papers_probe.py
#
# Everything measured here has been measured before, language by language, by people identifying
# languages and attributing authorship for their own reasons. What is worth taking from that work is not
# its conclusions but its settings. A paper that reports the character run length it settled on for
# Chinese, or the one it settled on for Finnish, has measured something about that language and written
# it down as a configuration.
#
# Those settings are a fact about the language whether or not anyone treated them as one. An
# agglutinative language with long words needs longer runs to reach a morpheme than an isolating one
# does. A logographic script needs shorter ones because a single character already carries what an
# alphabet spells out. If the settings across many papers line up with what kind of language each is
# about, that is a constant nobody set out to publish.
#
# This asks only what the archives serve and how they may be queried. Nothing is downloaded and no claim
# is made about what is in them.

import io
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

TRIES = (
    ("arxiv, its query interface",
     "http://export.arxiv.org/api/query?search_query=all:%22character+n-gram%22+AND+"
     "all:%22authorship%22&max_results=3"),
    ("the acl anthology listing", "https://aclanthology.org/anthology.bib"),
    ("its machine readable index", "https://aclanthology.org/anthology+abstracts.bib.gz"),
    ("semantic scholar", "https://api.semanticscholar.org/graph/v1/paper/search"
     "?query=character%20n-gram%20language%20identification&limit=3&fields=title,year,abstract"),
)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for label, url in TRIES:
        out.write("  %-32s\n" % label)
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=120) as response:
                blob = response.read(200000)
                kind = response.headers.get("Content-Type", "")
        except urllib.error.HTTPError as refused:
            out.write("      refused with %s\n\n" % refused.code)
            continue
        except Exception as trouble:
            out.write("      failed: %s\n\n" % str(trouble)[:80])
            continue

        out.write("      answered %d bytes, %s\n" % (len(blob), kind[:40]))
        text = blob.decode("utf-8", errors="replace")
        if "json" in kind:
            try:
                payload = json.loads(text)
                found = payload.get("data", payload if isinstance(payload, list) else [])
                for entry in (found or [])[:3]:
                    out.write("        %s (%s)\n"
                              % (str(entry.get("title", ""))[:80], entry.get("year", "")))
            except Exception:
                out.write("        could not be read as a listing\n")
        else:
            titles = re.findall(r"<title>([^<]{6,120})</title>", text)
            for title in titles[1:4]:
                out.write("        %s\n" % title.replace("\n", " ")[:88])
            if not titles:
                out.write("        begins: %s\n" % text[:160].replace("\n", " "))
        out.write("\n")
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
