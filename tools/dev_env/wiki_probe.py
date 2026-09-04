#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Ask the encyclopedia once, to find out whether it is answering at all.
#
#   Usage:  python tools/dev_env/wiki_probe.py
#
# The fetch that should have brought back Vietnamese and Urdu has printed nothing for a long time, and it
# retries four times with the wait quadrupling each time, so a language whose every request is refused
# takes hours to say so. That is a fault in how it was written and not a fact about the source.
#
# One request settles which. If it answers, the pacing was the problem and a slower fetch will work. If it
# refuses, the earlier run with six at once is still being held against this address and the wait has to
# be longer than any of this is worth.

import io
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for code in ("vi", "ur"):
        query = {
            "action": "query", "format": "json", "generator": "random",
            "grnnamespace": "0", "grnlimit": "8", "prop": "extracts", "explaintext": "1",
            "exlimit": "max",
        }
        url = "https://%s.wikipedia.org/w/api.php?%s" % (code, urllib.parse.urlencode(query))
        started = time.time()
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.loads(response.read().decode("utf-8"))
            pages = payload.get("query", {}).get("pages", {})
            total = sum(len(page.get("extract", "")) for page in pages.values())
            out.write("  %-4s answered in %.1fs with %d pages and %d characters\n"
                      % (code, time.time() - started, len(pages), total))
        except urllib.error.HTTPError as refused:
            out.write("  %-4s refused with %s after %.1fs\n" % (code, refused.code,
                                                                time.time() - started))
        except Exception as trouble:
            out.write("  %-4s failed: %s\n" % (code, trouble))
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
