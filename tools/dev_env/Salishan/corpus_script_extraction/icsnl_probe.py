#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Pull down a volume of the Salish and neighbouring languages proceedings and find what it documents
# about morphology, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/icsnl_probe.py [url] [name]
#
# Every measurement here so far needed a corpus with the grammar of each word written beside it, and no
# such thing exists for any Salishan language. What does exist is description. The International
# Conference on Salish and Neighbouring Languages has met since 1966 and its papers are posted openly by
# the University of British Columbia, and those papers carry affix inventories, ordering templates and
# glossed examples written down by people who did the field work.
#
# That is the same move Zaliznyak makes possible for Russian. A published account of the system gives the
# readings a form can carry without counting a corpus at all, which matters twice over here. A corpus
# count is limited to what the text happened to use, and for these languages the text belongs to the
# communities that hold it. Description written for publication is the right source and the only one
# taken here.
#
# The volumes run to several megabytes and are born digital, so the text comes out with pypdf and is kept
# beside the file. The keyword pass afterward is a locator and not a reading: it says which pages to open,
# and nothing is concluded from a matched line until the page around it has been read.

import io
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAPERS = os.path.join(ROOT, "build", "papers")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

VOLUME = ("https://static1.squarespace.com/static/5e0ee192d258d6433fe709b4/t/"
          "5e12c1f508c15a57c8655ca2/1578287642070/ICSNL2016-fullonline.pdf")

# What a description of a morphological system is called on the page
WANTED = ("reduplicat", "lexical suffix", "affix", "paradigm", "morphem", "transitiv",
          "aspect", "inventory", "template", "allomorph", "nominaliz", "predicat")


def download(url, target):
    """The file at a URL, kept on disk, skipped where it is already held."""
    if os.path.isfile(target) and (os.path.getsize(target) > 100000):
        return os.path.getsize(target), "already held"
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=600) as response:
        blob = response.read()
    with open(target, "wb") as handle:
        handle.write(blob)
    return len(blob), "fetched"


def extract(source, target):
    """Every page's text, kept one page to a block with the page number on it."""
    import pypdf

    reader = pypdf.PdfReader(source)
    pages = []
    for number, page in enumerate(reader.pages, 1):
        try:
            text = page.extract_text() or ""
        except Exception:
            text = ""
        pages.append(text)
    with open(target, "w", encoding="utf-8", newline="") as handle:
        for number, text in enumerate(pages, 1):
            handle.write("\n===== page %d =====\n%s" % (number, text))
    return pages


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(PAPERS, exist_ok=True)

    url = sys.argv[1] if len(sys.argv) > 1 else VOLUME
    name = sys.argv[2] if len(sys.argv) > 2 else "icsnl2016"
    source = os.path.join(PAPERS, "%s.pdf" % name)
    target = os.path.join(PAPERS, "%s.txt" % name)

    size, how = download(url, source)
    out.write("  %s, %d bytes, %s\n" % (os.path.basename(source), size, how))

    pages = extract(source, target)
    empty = sum(1 for text in pages if len(text.strip()) < 20)
    out.write("  %d pages, %d of them with no text layer\n" % (len(pages), empty))
    out.write("  text at %s\n" % target)

    if empty > (len(pages) / 2):
        out.write("\n  most pages carry no text, so this volume is a scan and the keyword\n")
        out.write("  pass below has nothing to work on\n")
        out.flush()
        return 0

    out.write("\n  the papers in the volume, from the pages that name them\n")
    seen = []
    for number, text in enumerate(pages[:6], 1):
        for line in text.splitlines():
            trimmed = line.strip()
            if len(trimmed) > 24 and re.search(r"\.\s?\.\s?\.|\.{3,}", trimmed):
                seen.append(trimmed)
    for line in seen[:40]:
        out.write("  %s\n" % line[:110])
    if not seen:
        out.write("  no contents listing found in the first pages\n")

    out.write("\n  %-16s %-7s %s\n" % ("what to look for", "hits", "first pages carrying it"))
    for word in WANTED:
        pages_with = [number for number, text in enumerate(pages, 1)
                      if word in text.lower()]
        if not pages_with:
            continue
        out.write("  %-16s %-7d %s\n"
                  % (word, len(pages_with),
                     " ".join(str(number) for number in pages_with[:14])))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
