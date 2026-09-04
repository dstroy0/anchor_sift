#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# List every volume of the Salish and neighbouring languages proceedings that can be downloaded, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/icsnl_index.py [page url]
#
# The conference has met every year since 1966 and the University of British Columbia posts the whole run,
# with the volumes from 1966 to 1999 held as the Kinkade Collection and the rest published since. That is
# fifty and more volumes of description of a family with no annotated corpus anywhere, which makes the
# archive the corpus.
#
# The links are pulled out of the page here instead of through a summarizer, because a summarizer given a
# page of links returns prose about the links and drops the addresses, which it did on the first attempt at
# this page. The addresses are the only part that matters.
#
# Nothing is downloaded by this. It writes the list and stops, since the run is several hundred megabytes
# and what to take from it is a decision, not a default.

import io
import os
import re
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAPERS = os.path.join(ROOT, "build", "papers")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

VOLUMES = "https://lingpapers.sites.olt.ubc.ca/icsnl-volumes/"

LINK = re.compile(r'href=["\']([^"\']+)["\'][^>]*>(.*?)</a>', re.IGNORECASE | re.DOTALL)
TAGS = re.compile(r"<[^>]+>")
YEAR = re.compile(r"\b(19[6-9]\d|20[0-2]\d)\b")
NUMBER = re.compile(r"\b([1-9]\d?)(?:st|nd|rd|th)?\b")


def readable(blob):
    """The visible words of a link, with the markup taken out."""
    text = TAGS.sub(" ", blob)
    text = text.replace("&amp;", "&").replace("&#8217;", "'").replace("&nbsp;", " ")
    return " ".join(text.split())


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(PAPERS, exist_ok=True)
    page = sys.argv[1] if len(sys.argv) > 1 else VOLUMES

    request = urllib.request.Request(page, headers=AGENT)
    with urllib.request.urlopen(request, timeout=300) as response:
        blob = response.read().decode("utf-8", errors="replace")
    out.write("  %s, %d bytes\n" % (page, len(blob)))

    found = []
    for href, label in LINK.findall(blob):
        address = urllib.parse.urljoin(page, href.strip())
        words = readable(label)
        found.append((address, words))

    pdfs = [(address, words) for address, words in found if address.lower().endswith(".pdf")]
    inside = [(address, words) for address, words in found
              if ("icsnl" in address.lower() or "icsnl" in words.lower())
              and not address.lower().endswith(".pdf")]

    out.write("  %d links, %d of them PDFs, %d others naming the conference\n"
              % (len(found), len(pdfs), len(inside)))

    target = os.path.join(PAPERS, "icsnl_index.tsv")
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write("kind\tyear\turl\tlabel\n")
        for address, words in pdfs:
            season = YEAR.search(words) or YEAR.search(address)
            handle.write("pdf\t%s\t%s\t%s\n"
                         % (season.group(1) if season else "", address, words[:120]))
        for address, words in inside:
            season = YEAR.search(words) or YEAR.search(address)
            handle.write("page\t%s\t%s\t%s\n"
                         % (season.group(1) if season else "", address, words[:120]))
    out.write("  written to %s\n" % target)

    if pdfs:
        out.write("\n  PDFs, newest first by the year in the link\n")
        ordered = sorted(pdfs, key=lambda pair: (YEAR.search(pair[1] + pair[0]) or
                                                 re.match(r"(0000)", "0000")).group(1),
                         reverse=True)
        for address, words in ordered[:40]:
            out.write("  %-52s %s\n" % (words[:50], address[:96]))

    if inside:
        out.write("\n  pages naming the conference, which may each hold a volume\n")
        for address, words in inside[:40]:
            out.write("  %-52s %s\n" % (words[:50], address[:96]))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
