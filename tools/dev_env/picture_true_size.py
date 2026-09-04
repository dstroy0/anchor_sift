#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Report the true dimensions of the stored pictures, for Section 4.11 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/picture_true_size.py
#
# The width recovery test needs an answer that neither instrument produced, and the run that stored these
# files printed the true width without saving it. This fetches the same three files and reports what the
# decoder says their dimensions are, which is the ground truth both instruments are then scored against.
#
# Nothing here is written to disk. The stored corpora are left as they are, and the byte length on disk is
# checked against the fetched dimensions so a file that no longer matches its source is caught instead of
# being scored against the wrong answer.

import io
import os
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0"}

WANTED = (
    ("art_hokusai", "The Great Wave off Kanagawa.jpg"),
    ("art_vermeer", "Johannes Vermeer (1632-1675) - The Girl With The Pearl Earring (1665).jpg"),
    ("art_starry", "Van Gogh - Starry Night - Google Art Project.jpg"),
)

SIDE = 512


def main():
    from PIL import Image

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-14s %-12s %-12s %-12s %s\n"
              % ("picture", "true width", "true height", "stored bytes", "match"))

    for name, title in WANTED:
        url = ("https://commons.wikimedia.org/wiki/Special:FilePath/"
               + urllib.parse.quote(title) + "?width=%d" % SIDE)
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=180) as response:
                blob = response.read()
        except Exception as trouble:
            out.write("  %-14s could not fetch: %s\n" % (name, trouble))
            continue

        picture = Image.open(io.BytesIO(blob)).convert("L")
        width, height = picture.size
        path = os.path.join(CORPORA, "%s.sym" % name)
        stored = os.path.getsize(path) if os.path.isfile(path) else 0
        out.write("  %-14s %-12d %-12d %-12d %s\n"
                  % (name, width, height, stored,
                     "yes" if (width * height) == stored else "no, do not score this one"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
