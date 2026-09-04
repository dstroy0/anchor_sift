#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find out what the German and Austrian archives serve and on what terms, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/german_archives_probe.py
#
# Two questions here need corpora that nothing gathered so far can answer.
#
# One writer against another needs several works by each with the language fixed, and scraping a book
# catalog by name gave seven writers of the ten asked for, in editions prepared differently from each
# other, chosen by how popular they are.
#
# One century against another needs dates that are right. The cookery books were dated by the first four
# digit number printed in each, which put a 1919 book in 1600, and by author lifetimes after that, which
# gave fourteen books mostly inside one century and one medieval text dated to its eighteenth century
# editor.
#
# A prepared archive answers both: consistent editions, real dates, and enough of a span that a century is
# a variable and not an accident. This asks what each one offers and how it may be used, and downloads
# nothing. An archive that must be applied for is one to ask about and not one to take from.

import io
import json
import re
import sys
import urllib.error
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

TRIES = (
    ("german text archive", "https://www.deutschestextarchiv.de/"),
    ("its listing of works", "https://www.deutschestextarchiv.de/list"),
    ("its download page", "https://www.deutschestextarchiv.de/download"),
    ("the dwds corpora page", "https://www.dwds.de/d/korpora"),
    ("austrian newspapers", "https://anno.onb.ac.at/"),
    ("austrian library labs", "https://labs.onb.ac.at/en/"),
    ("german open data", "https://www.govdata.de/"),
)


def flatten(html):
    html = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
    html = re.sub(r"(?is)<br[^>]*>|</p>|</div>|</li>|</h[1-6]>|</tr>", "\n", html)
    text = re.sub(r"(?s)<[^>]+>", " ", html)
    for code, plain in (("&nbsp;", " "), ("&amp;", "&"), ("&#39;", "'"), ("&quot;", '"'),
                        ("&uuml;", "u"), ("&auml;", "a"), ("&ouml;", "o"), ("&szlig;", "ss")):
        text = text.replace(code, plain)
    lines = [line.strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for label, url in TRIES:
        out.write("  %-24s %s\n" % (label, url))
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=90) as response:
                blob = response.read(500000)
                final = response.geturl()
        except urllib.error.HTTPError as refused:
            out.write("      refused with %s\n\n" % refused.code)
            continue
        except Exception as trouble:
            out.write("      failed: %s\n\n" % str(trouble)[:80])
            continue

        html = blob.decode("utf-8", errors="replace")
        if final.rstrip("/") != url.rstrip("/"):
            out.write("      went to %s\n" % final)
        text = flatten(html)
        for line in text.splitlines()[:8]:
            out.write("      | %s\n" % line[:104])

        links = sorted(set(re.findall(r'href="([^"]+)"', html)))
        wanted = [link for link in links
                  if re.search(r"(?i)\.(zip|tar|gz|tgz|csv|tsv|txt|xml|json)$"
                               r"|download|dump|api|corpu|licen|terms|opendata", link)]
        if wanted:
            out.write("      worth following:\n")
            for link in wanted[:12]:
                out.write("        %s\n" % link[:118])
        out.write("\n")
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
