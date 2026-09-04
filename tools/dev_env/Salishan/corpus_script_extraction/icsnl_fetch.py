#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Take the papers from the Salish proceedings that bear on what this work found, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/icsnl_fetch.py [word] [word] ...
#
# The index lists 993 papers over sixty years and there is no reason to take all of them. Four things came
# out of reading two papers by hand, and the titles in the index name papers about each one.
#
# Control, because Lillooet marks whether the actor had any, and a measurement built on kind and form has
# no column for it. Reduplication, because which side of the stressed vowel the copy lands on is what
# selects the meaning, which is the same question this work asks about position everywhere else.
# Toponyms and stories, because the claim under test is that meaning here follows the land and the story
# that gives the land its shape, and a paper on place names is that claim's evidence or its refutation.
#
# Each paper is its own PDF, a few hundred kilobytes. A targeted set costs little and the whole run
# would cost a great deal for material nobody asked a question about.
#
# What comes back is reported per paper and not pooled. A count of glossed examples across sixty years of
# authors would average over sixty glossing conventions, and the earlier harvest already showed what that
# produces: an abbreviation key read as the richest example in the volume.

import io
import os
import re
import sys
import time
import urllib.error
import urllib.request

from gloss_harvest import harvest
from icsnl_probe import extract

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAPERS = os.path.join(ROOT, "build", "papers")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

INDEX = os.path.join(PAPERS, "icsnl_index.tsv")
PAUSE = 0.4
CEILING = 60

# What this thread found, in the words a title would use for it
WANTED = ("control", "reduplicat", "lexical suffix", "toponym", "place name", "morpholog",
          "creat", "story", "stories", "narrative", "land", "inchoative", "transitiv")


def named(text):
    """A filename for a paper, from the last part of its address."""
    stem = text.rsplit("/", 1)[-1]
    stem = re.sub(r"\.pdf$", "", stem, flags=re.IGNORECASE)
    stem = re.sub(r"[^A-Za-z0-9_-]+", "_", stem)
    return stem[:60].strip("_") or "paper"


def read_index(path):
    """Every PDF in the index, as its address, the year on it, and its title."""
    rows = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != len(header):
                continue
            row = dict(zip(header, parts))
            if row.get("kind") != "pdf":
                continue
            rows.append((row["url"], row.get("year", ""), row.get("label", "")))
    return rows


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isfile(INDEX):
        out.write("  no %s, run icsnl_index.py first\n" % INDEX)
        out.flush()
        return 1

    words = [one.lower() for one in sys.argv[1:]] or list(WANTED)
    rows = read_index(INDEX)
    picked = [(address, year, label) for address, year, label in rows
              if any(word in label.lower() for word in words)]
    out.write("  %d papers indexed, %d match %s\n"
              % (len(rows), len(picked), ", ".join(words[:6]) + ("..." if len(words) > 6 else "")))
    if len(picked) > CEILING:
        out.write("  taking the first %d of them\n" % CEILING)
        picked = picked[:CEILING]

    out.write("\n  %-40s %-6s %-6s %-7s %s\n"
              % ("paper", "pages", "blank", "glosses", "title"))
    landed = 0
    for address, year, label in picked:
        stem = named(address)
        source = os.path.join(PAPERS, "%s.pdf" % stem)
        target = os.path.join(PAPERS, "%s.txt" % stem)

        if not (os.path.isfile(source) and (os.path.getsize(source) > 20000)):
            try:
                request = urllib.request.Request(address, headers=AGENT)
                with urllib.request.urlopen(request, timeout=300) as response:
                    blob = response.read()
                with open(source, "wb") as handle:
                    handle.write(blob)
                time.sleep(PAUSE)
            except urllib.error.HTTPError as refused:
                out.write("  %-40s refused (%s)\n" % (stem[:40], refused.code))
                continue
            except Exception as trouble:
                out.write("  %-40s %s\n" % (stem[:40], str(trouble)[:34]))
                continue

        try:
            pages = extract(source, target)
        except Exception as trouble:
            out.write("  %-40s could not read it, %s\n" % (stem[:40], str(trouble)[:30]))
            continue

        blank = sum(1 for text in pages if len(text.strip()) < 20)
        numbered = [(number, text) for number, text in enumerate(pages, 1)]
        glosses = len(harvest(numbered))
        out.write("  %-40s %-6d %-6d %-7d %s\n"
                  % (stem[:40], len(pages), blank, glosses, label[:44]))
        landed += 1
        out.flush()

    out.write("\n  %d papers held, text beside each PDF in %s\n" % (landed, PAPERS))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
