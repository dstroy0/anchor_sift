#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch three centuries of one language with dates that are right, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_dta.py
#
# Two questions here have been asked against corpora that could not answer them.
#
# How writing changes over centuries was asked of fourteen cookery books dated by the first four digit
# number printed in each, which put a 1919 book in 1600. Dated again by author lifetimes, they covered
# 1588 to 1858 with most of them in one century, and the one medieval text was dated to its eighteenth
# century editor.
#
# Whether a writer has a mark of their own was asked of books scraped from a catalog by name, which gave
# seven writers of the ten wanted, in editions prepared differently from each other.
#
# This archive answers both. It is one language, prepared consistently, cataloged by people who kept
# careful records, split by century by the archive itself, and licensed for use with attribution. The
# split is theirs and not mine, which matters: every century boundary drawn in this work so far was drawn
# by me and one of them was drawn at 1810 to make five books fall on one side.
#
# Sizes are read before anything is taken, since a century of books is not a file to fetch blind.

import io
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

BASE = "https://www.deutschestextarchiv.de/media/download"
STAMP = "2020-09-23"

CENTURIES = ("1500-1599", "1600-1699", "1700-1799", "1800-1899")


def head(url):
    """How large a thing is, without taking it."""
    request = urllib.request.Request(url, headers=AGENT, method="HEAD")
    with urllib.request.urlopen(request, timeout=90) as response:
        return int(response.headers.get("Content-Length", 0) or 0)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  what the archive offers, by century, as plain text\n")
    out.write("  %-14s %-14s %s\n" % ("century", "megabytes", "address"))

    found = []
    for century in CENTURIES:
        name = "dta_kernkorpus_%s_%s_text.zip" % (century, STAMP)
        url = "%s/%s" % (BASE, name)
        try:
            size = head(url)
        except urllib.error.HTTPError as refused:
            out.write("  %-14s %-14s not offered as text (%s)\n" % (century, "", refused.code))
            continue
        except Exception as trouble:
            out.write("  %-14s %-14s %s\n" % (century, "", str(trouble)[:50]))
            continue
        out.write("  %-14s %-14.1f %s\n" % (century, size / 1e6, name))
        found.append((century, url, size))

    if not found:
        out.write("\n  nothing offered under that stamp\n")
        out.flush()
        return 1

    out.write("\n  %.1f megabytes in all across %d centuries\n"
              % (sum(size for _, _, size in found) / 1e6, len(found)))
    out.write("  licensed CC BY-SA 4.0, which this work can use with attribution\n")
    out.write("\n  nothing has been downloaded. Run with --take to fetch them.\n")

    if "--take" not in sys.argv:
        out.flush()
        return 0

    for century, url, size in found:
        target = os.path.join(CORPORA, "dta_%s.zip" % century)
        if os.path.isfile(target) and (os.path.getsize(target) >= (size * 0.9)):
            out.write("  %s already held\n" % century)
            continue
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=900) as response:
                blob = response.read()
        except Exception as trouble:
            out.write("  %s failed: %s\n" % (century, str(trouble)[:60]))
            continue
        with open(target, "wb") as handle:
            handle.write(blob)
        out.write("  %s taken, %.1f megabytes\n" % (century, len(blob) / 1e6))
        out.flush()

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
