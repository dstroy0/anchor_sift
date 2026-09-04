#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find out whether one text in many languages can be had, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/parallel_probe.py
#
# Every comparison between languages in this work has genre inside it. Greek is epic poetry, Dutch is a
# novel, the encyclopedia texts are reference prose, and one of the Greek texts turned out to be a
# dictionary. A difference between two languages measured this way is a difference between two books that
# happen to be in different languages, and nothing separates the two.
#
# One text translated into many languages removes that completely. The content is fixed, so what is left
# between two versions is the language and nothing else, which is the comparison that was wanted all
# along. It also reaches languages a book catalog does not carry, including the two asked for here.
#
# This only asks what is available and downloads nothing. A source that cannot be listed cheaply is not
# worth building on, and a source whose files are not plain text is not worth parsing.

import io
import json
import sys
import urllib.error
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

TRIES = (
    ("ebible catalog", "https://ebible.org/Scriptures/translations.csv"),
    ("ebible listing", "https://ebible.org/download.php"),
    ("tatoeba stats", "https://tatoeba.org/en/stats/sentences_by_language"),
    ("opus catalog", "https://opus.nlpl.eu/opusapi/?corpora=True"),
    ("opus bible corpus", "https://opus.nlpl.eu/opusapi/?corpus=bible-uedin&languages=True"),
)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for label, url in TRIES:
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=90) as response:
                blob = response.read(400000)
            text = blob.decode("utf-8", errors="replace")
            out.write("  %-20s answered, %d bytes\n" % (label, len(blob)))
            if url.endswith("True"):
                try:
                    payload = json.loads(text)
                    values = payload if isinstance(payload, list) else list(payload.values())[0]
                    out.write("      holds %d entries, first few: %s\n"
                              % (len(values), ", ".join(str(one) for one in values[:12])))
                except Exception as trouble:
                    out.write("      could not be read as a listing: %s\n" % trouble)
            else:
                head = " | ".join(line.strip()[:90] for line in text.splitlines()[:3] if line.strip())
                out.write("      begins: %s\n" % head[:220])
        except urllib.error.HTTPError as refused:
            out.write("  %-20s refused with %s\n" % (label, refused.code))
        except Exception as trouble:
            out.write("  %-20s failed: %s\n" % (label, trouble))
        out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
