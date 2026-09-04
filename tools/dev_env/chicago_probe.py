#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find out what a curated novel collection offers and on what terms, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/chicago_probe.py
#
# Testing whether a writer has a signature of their own needs several works by each of several writers,
# and nothing held here has two works by one person. Scraping a book catalog by author name was the first
# attempt and it is a poor basis: the search matches a name anywhere, the editions are prepared
# differently from each other, and how many works a writer has in it follows their popularity and not
# anything about them.
#
# A collection built for literary measurement is a better basis, being consistently prepared and large
# enough that a writer arrives with more than three books. This asks what it offers and how it may be
# used, and downloads nothing. A collection that has to be requested, or that carries terms this work
# would breach, is one to ask about instead of one to take.

import io
import re
import sys
import urllib.error
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

PAGES = (
    "https://textual-optics-lab.uchicago.edu/us_novel_corpus",
)


def flatten(html):
    """The readable text of a page, with its markup and scripts taken out."""
    html = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
    html = re.sub(r"(?is)<br[^>]*>|</p>|</div>|</li>|</h[1-6]>", "\n", html)
    text = re.sub(r"(?s)<[^>]+>", " ", html)
    text = text.replace("&nbsp;", " ").replace("&amp;", "&").replace("&#39;", "'")
    lines = [line.strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for url in PAGES:
        out.write("  %s\n" % url)
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=90) as response:
                blob = response.read(600000)
                final = response.geturl()
        except urllib.error.HTTPError as refused:
            out.write("      refused with %s\n\n" % refused.code)
            continue
        except Exception as trouble:
            out.write("      failed: %s\n\n" % str(trouble)[:90])
            continue

        html = blob.decode("utf-8", errors="replace")
        if final != url:
            out.write("      redirected to %s\n" % final)
        text = flatten(html)
        out.write("      %d characters of readable text\n" % len(text))
        for line in text.splitlines()[:40]:
            out.write("      | %s\n" % line[:110])

        # Every link, since the filtered search found nothing and a collection of novels still in
        # copyright will not offer a plain download even where it offers the texts some other way
        links = sorted(set(re.findall(r'href="([^"]+)"', html)))
        out.write("      %d links, all of them:\n" % len(links))
        for link in links:
            if link.startswith("#") or link.startswith("javascript"):
                continue
            out.write("        %s\n" % link[:140])
        out.write("\n")
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
