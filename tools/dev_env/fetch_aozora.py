#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch a corpus outside Indo-European that can carry the same questions, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_aozora.py
#
# What separates two German books was taken apart and came out at 11 percent for the author, 1 percent
# for the century and 88 percent for the book itself. That is a strong result on 1244 texts and it
# describes Germanic prose, which is one branch of one family, and it is written down as though it
# described writing.
#
# The languages tested for breadth here run wide, 26 of them outside Indo-European. The questions that
# take the reading apart do not: every one of them was asked of English or German. A family that shares
# inherited structure, an alphabet and a thousand years of borrowing will hand back constants that are
# facts about the family, and nothing inside the family can tell those from facts about language.
#
# Japanese is the corpus that can carry the same questions. It is outside the family entirely, it is
# written in a mixture of three scripts where the Chinese-derived characters are morphemes and the two
# syllabaries are not, and this archive holds thousands of works with the author and the dates named for
# each. That last part is what the German archive had and everything before it lacked.

import io
import json
import os
import re
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

INDEX = "https://www.aozora.gr.jp/index_pages/list_person_all_extended_utf8.zip"
LEAST = 20000
WANTED_AUTHORS = 40
PER_AUTHOR = 6
PAUSE = 0.35


def get(url, timeout=240):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)

    try:
        import zipfile
        blob = get(INDEX)
        with zipfile.ZipFile(io.BytesIO(blob)) as bundle:
            name = bundle.namelist()[0]
            listing = bundle.read(name).decode("utf-8", errors="replace")
    except Exception as trouble:
        out.write("  could not read the archive listing: %s\n" % str(trouble)[:70])
        out.flush()
        return 1

    # Read as real comma separated values. Pulling the quoted runs out with a pattern was tried and put
    # every column in the wrong place, because the file quotes some fields and not others, so the count
    # of quoted runs on a line is not the count of columns. It reported two authors holding three works
    # in an archive of nineteen thousand.
    import csv
    rows = list(csv.reader(io.StringIO(listing)))
    header = rows[0] if rows else []
    out.write("  the listing holds %d rows and %d columns\n\n" % (len(rows), len(header)))

    def column(wanted, exact=True):
        for place, part in enumerate(header):
            part = part.strip("﻿")
            if (part == wanted) if exact else (wanted in part):
                return place
        return None

    where_title = column("作品名")
    where_person = column("人物ID")
    where_family = column("姓ローマ字")
    where_born = column("生年月日")
    where_url = column("テキストファイルURL")

    if (where_url is None) or (where_person is None):
        out.write("  the listing does not name the columns expected, nothing taken\n")
        out.flush()
        return 1

    by_author = {}
    for row in rows[1:]:
        if len(row) <= max(where_url, where_person):
            continue
        address = row[where_url]
        if not address.endswith(".zip"):
            continue
        # Keyed on the person and named by the romanized surname, so two writers of one name stay apart
        # and a filename holds no characters a filesystem argues about
        person = row[where_person]
        family = (row[where_family] if where_family is not None else "") or person
        title = row[where_title] if where_title is not None else ""
        born = row[where_born] if where_born is not None else ""
        by_author.setdefault((person, family, born), []).append((title, address))

    many = sorted((author for author in by_author if len(by_author[author]) >= 3),
                  key=lambda author: -len(by_author[author]))[:WANTED_AUTHORS]
    out.write("  %d authors hold three works or more, taking %d of them\n\n" % (
        sum(1 for author in by_author if len(by_author[author]) >= 3), len(many)))

    landed = 0
    for author in many:
        person, family, born = author
        short = re.sub(r"[^0-9A-Za-z]", "", family).lower()[:14] or ("p%s" % person)
        kept = 0
        for title, address in by_author[author][:PER_AUTHOR * 3]:
            if kept >= PER_AUTHOR:
                break
            target = os.path.join(CORPORA, "jp_%s_%s_%d.txt" % (short, person, kept))
            if os.path.isfile(target):
                kept += 1
                landed += 1
                continue
            try:
                import zipfile
                blob = get(address)
                with zipfile.ZipFile(io.BytesIO(blob)) as bundle:
                    inner = [one for one in bundle.namelist() if one.lower().endswith(".txt")]
                    if not inner:
                        continue
                    text = bundle.read(inner[0]).decode("shift_jis", errors="replace")
                time.sleep(PAUSE)
            except Exception:
                continue
            text = re.sub(r"《[^》]*》|［[^］]*］|\｜", "", text)
            text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
            if len(text) < LEAST:
                continue
            with open(target, "w", encoding="utf-8", newline="") as handle:
                handle.write(text)
            kept += 1
            landed += 1
        if kept:
            out.write("  %-20s %d works\n" % (author[:20], kept))
            out.flush()

    out.write("\n  %d works landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
