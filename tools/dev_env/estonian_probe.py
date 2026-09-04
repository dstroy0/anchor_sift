#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find better Estonian than the reading currently has, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/estonian_probe.py
#
# Estonian is one of the three languages in the test that separated descent from contact, and it behaved
# worst of the three: its nearest of everything held was Romanian, which is neither its family nor a
# neighbour it borrowed from and is what a reading close to noise looks like. Finnish went to Swedish and
# Hungarian to Czech, which are contact relationships and mean something. Romanian means nothing.
#
# So the Uralic result rests on two languages behaving sensibly and one behaving randomly, and the
# Estonian held here is one short parallel text. Before that result is leaned on any further, Estonian
# needs a corpus worth the name.
#
# The country keeps its records carefully and publishes them. This asks what its archives and language
# resource centers serve and under what terms, and downloads nothing.

import io
import re
import sys
import urllib.error
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

TRIES = (
    ("language resources center", "https://www.keeleressursid.ee/en/"),
    ("its corpus listing", "https://metashare.ut.ee/"),
    ("national digital archive", "https://www.digar.ee/arhiiv/en"),
    ("national archives", "https://www.ra.ee/en/"),
    ("open data portal", "https://avaandmed.eesti.ee/"),
    ("university corpora", "https://www.cl.ut.ee/korpused/"),
)


def flatten(html):
    html = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", html)
    html = re.sub(r"(?is)<br[^>]*>|</p>|</div>|</li>|</h[1-6]>|</tr>", "\n", html)
    text = re.sub(r"(?s)<[^>]+>", " ", html)
    for code, plain in (("&nbsp;", " "), ("&amp;", "&"), ("&#39;", "'"), ("&quot;", '"')):
        text = text.replace(code, plain)
    return "\n".join(line.strip() for line in text.splitlines() if line.strip())


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for label, url in TRIES:
        out.write("  %-26s %s\n" % (label, url))
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=90) as response:
                blob = response.read(400000)
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
        for line in flatten(html).splitlines()[:7]:
            out.write("      | %s\n" % line[:100])

        links = sorted(set(re.findall(r'href="([^"]+)"', html)))
        wanted = [link for link in links
                  if re.search(r"(?i)\.(zip|tar|gz|txt|xml|json|csv)$"
                               r"|download|dump|corpu|korpus|licen|opendata|api", link)]
        for link in wanted[:10]:
            out.write("        %s\n" % link[:116])
        out.write("\n")
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
