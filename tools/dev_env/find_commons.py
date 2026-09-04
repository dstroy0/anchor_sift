#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find the exact file titles for the paintings the abruptness test needs, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/find_commons.py
#
# The first attempt at the two extremes asked for a drip painting and a color field painting by guessed
# titles and got two 404s. The titles were wrong, and behind that both works are still in copyright, so
# the repository does not hold them at all and no title would have worked.
#
# The extremes have to come from painters whose work is out of copyright, and the test is unharmed by
# that, since what it needs is a range of abruptness and not any particular canvas. Hard edged flat
# regions and a pointillist surface stand in at the abrupt end, and an atmospheric painting stands in at
# the smooth end. Each search prints what the repository actually holds so a real title is copied from a
# result instead of guessed at again.

import io
import json
import sys
import urllib.parse
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0"}
API = "https://commons.wikimedia.org/w/api.php"

WANTED = (
    ("hard edged flat regions", "Mondrian composition red blue yellow"),
    ("pointillist surface", "Seurat Grande Jatte"),
    ("atmospheric and smooth", "Turner Rain Steam and Speed"),
    ("smooth tonal", "Whistler Nocturne black gold"),
)


def search(term, limit=6):
    query = {
        "action": "query",
        "format": "json",
        "list": "search",
        "srsearch": "filetype:bitmap %s" % term,
        "srnamespace": "6",
        "srlimit": str(limit),
    }
    url = API + "?" + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return [hit["title"][5:] for hit in payload.get("query", {}).get("search", [])]


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for label, term in WANTED:
        out.write("  %s\n" % label)
        try:
            for title in search(term):
                out.write("      %s\n" % title)
        except Exception as trouble:
            out.write("      search failed: %s\n" % trouble)
        out.write("\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
