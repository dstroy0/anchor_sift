#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Take apart what makes two German books read differently, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/german_variation.py
#
# Four centuries of change in German spelling, capitalization and typesetting move the reading by five
# percent, and what swamps it is that two books are two books. That is a residue with a name and no
# contents, so this opens it.
#
# The archive names every text for its author and its year, so three comparisons are available on one
# prepared corpus with nothing fetched and nothing guessed. Two works by one author. Two works by two
# authors of one century. Two works from two centuries. Each is the one before it plus one more thing
# changing, so the differences between them are what that thing is worth.
#
# What the night predicts: the century should be worth almost nothing, since it was worth five percent
# already. The author should be worth little, since seven English writers sharing an alphabet were told
# apart only 35 percent of the time by this same reading. If both are small then most of what separates
# two books is neither of them, and the residue has a size even where it has no name.
#
# Length is held equal because it has to be. A reading taken over more text is steadier, so a long book
# and a short one differ for that reason alone before anything about either of them is considered.

import io
import os
import re
import statistics
import sys
import zipfile

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CENTURIES = ("1600-1699", "1700-1799", "1800-1899")
SAME_LENGTH = 60000
RANKS = 64
MOST_PER_AUTHOR = 6


def read_all(century):
    """Every text of one century long enough to read, with its author and year."""
    path = os.path.join(CORPORA, "dta_%s.zip" % century)
    if not os.path.isfile(path):
        return []
    found = []
    with zipfile.ZipFile(path) as bundle:
        for name in sorted(bundle.namelist()):
            if not name.endswith(".txt"):
                continue
            stem = os.path.basename(name)[:-4]
            year = re.search(r"_(1[5-9][0-9]{2})$", stem)
            if not year:
                continue
            author = stem.split("_", 1)[0]
            try:
                text = bundle.read(name).decode("utf-8", errors="replace")
            except Exception:
                continue
            text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
            if len(text) < SAME_LENGTH:
                continue
            found.append((author, int(year.group(1)), century, text[:SAME_LENGTH]))
    return found


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    gathered = []
    for century in CENTURIES:
        held = read_all(century)
        out.write("  %s: %d texts long enough, %d authors\n"
                  % (century, len(held), len({row[0] for row in held})))
        gathered.extend(held)

    if len(gathered) < 60:
        out.write("\n  only %d texts\n" % len(gathered))
        out.flush()
        return 0

    # An author with many works would otherwise decide the whole same author figure by themselves
    by_author = {}
    for row in gathered:
        by_author.setdefault(row[0], []).append(row)
    kept = []
    for author, works in by_author.items():
        kept.extend(sorted(works, key=lambda row: row[1])[:MOST_PER_AUTHOR])

    rows = []
    for author, year, century, text in kept:
        values = web(text, RANKS)
        if values is not None:
            rows.append((author, year, century, values))

    repeated = sorted(author for author in {row[0] for row in rows}
                      if sum(1 for row in rows if row[0] == author) >= 2)
    out.write("\n  %d texts read, %d authors, %d of them with more than one work\n"
              % (len(rows), len({row[0] for row in rows}), len(repeated)))

    same_author = []
    same_century = []
    other_century = []
    for index, one in enumerate(rows):
        for two in rows[index + 1:]:
            distance = float(numpy.linalg.norm(one[3] - two[3]))
            if one[0] == two[0]:
                same_author.append(distance)
            elif one[2] == two[2]:
                same_century.append(distance)
            else:
                other_century.append(distance)

    out.write("\n  %-38s %-9s %s\n" % ("two works that share", "pairs", "how far apart"))
    for label, marks in (("the author, and so the century", same_author),
                         ("the century, not the author", same_century),
                         ("neither", other_century)):
        if len(marks) >= 20:
            out.write("  %-38s %-9d %.4f\n" % (label, len(marks), statistics.fmean(marks)))

    if (len(same_author) >= 20) and (len(same_century) >= 20) and (len(other_century) >= 20):
        author_worth = statistics.fmean(same_century) - statistics.fmean(same_author)
        century_worth = statistics.fmean(other_century) - statistics.fmean(same_century)
        floor = statistics.fmean(same_author)
        widest = statistics.fmean(other_century)
        out.write("\n  sharing an author is worth        %.4f\n" % author_worth)
        out.write("  sharing a century is worth        %.4f\n" % century_worth)
        out.write("  what remains between two works    %.4f\n" % floor)
        out.write("  the whole distance between two unrelated works is %.4f, of which\n" % widest)
        out.write("    the author accounts for %.0f percent\n" % (100.0 * author_worth / widest))
        out.write("    the century accounts for %.0f percent\n" % (100.0 * century_worth / widest))
        out.write("    neither accounts for    %.0f percent\n" % (100.0 * floor / widest))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
