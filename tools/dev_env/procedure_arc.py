#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure how a procedure is arranged, across several centuries of writing them down, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/procedure_arc.py
#
# Everything read in this work is either a procedure written to be executed exactly, which is source code,
# or not a procedure at all. A recipe is the case in between. It tells someone how to do a thing in the
# order it is done and leaves out everything the reader is assumed to know, and what a reader was assumed
# to know in 1390 is gone. The measurements, the ingredients and the preparations are lost, some of the
# plants no longer exist, and what survives on the page is the shape of an instruction with its content
# taken away by time.
#
# Two claims about that shape are testable without knowing any of the content, which is the only reason
# this corpus is worth measuring at all.
#
# The first is arrangement. A modern recipe is canonically ordered, the things needed and then the steps
# in the sequence performed, and an older one is arranged by some other logic. An ordering that matters
# is one a text loses by being shuffled, so a text whose blocks can be moved without changing much was not
# arranged the way a modern one is.
#
# The second is uniformity. Recording a procedure was standardized late, so before that every author
# arranged their own way and the books should disagree with each other more. That is a spread between
# books of one period and it needs no reference to any standard.
#
# What confounds this and cannot be removed: the Roman book is a modern English translation and the
# medieval one comes through a later edition, so the date a text was composed and the date its language
# belongs to are different variables here. Where they separate is stated per book and not averaged over.

import io
import os
import re
import statistics
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 400000
LEAST = 90000
RANKS = 48
BLOCKS = 120
SEED = 0x51F7



def from_catalog():
    """Title and author dates for each book, as the catalog states them.

    Dating a book by the first four digit number printed in it put a 1919 cookbook in 1600, because that
    number is as likely to be a street address or a page count as a date. These come from the catalog
    that supplied the books.
    """
    path = os.path.join(ROOT, "build", "recipe_dates.csv")
    if not os.path.isfile(path):
        return {}
    known = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle.read().splitlines()[1:]:
            parts = line.split(",")
            if len(parts) < 4:
                continue
            try:
                number = int(parts[0])
            except ValueError:
                continue
            born = int(parts[-2]) if parts[-2].strip().isdigit() else None
            known["recipe_%d" % number] = (",".join(parts[1:-2])[:44], born)
    return known


def clustering(text):
    """How tightly each word keeps to one part of the book, against the same words scattered.

    Arrangement is a property of the whole book and the character web is a property of neighbouring
    letters, so shuffling blocks left that web almost unmoved: every value came back under 0.03 and the
    reading said nothing. What arrangement does show in is where a word sits. A book laid out as separate
    recipes keeps the word for an ingredient inside the recipe that calls for it, and a book that wanders
    spreads the same word through the whole of itself.

    Measured as the spread of the gaps between one use of a word and the next, over the words common
    enough to have gaps worth measuring, against the same words shuffled through the book.
    """
    words = [word for word in re.findall(r"[a-z]+", text.lower()) if len(word) > 2]
    if len(words) < 20000:
        return None

    def spread_of(series):
        seen = {}
        for index, word in enumerate(series):
            seen.setdefault(word, []).append(index)
        marks = []
        for word, spots in seen.items():
            if len(spots) < 24:
                continue
            gaps = numpy.diff(numpy.asarray(spots, dtype=numpy.float64))
            middle = gaps.mean()
            if middle > 0:
                marks.append(gaps.std() / middle)
        return statistics.fmean(marks) if len(marks) >= 20 else None

    straight = spread_of(words)
    scattered = list(words)
    __import__("random").Random(SEED).shuffle(scattered)
    loose = spread_of(scattered)
    if (straight is None) or (loose is None) or (loose <= 0):
        return None
    return straight / loose


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    known = from_catalog()
    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("recipe_") and name.endswith(".txt")):
            continue
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            whole = handle.read(CAP)
        text = whole.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) < LEAST:
            continue
        title, born = known.get(name[:-4], ("unnamed", None))
        moved = clustering(text)
        values = web(text, RANKS)
        if (moved is None) or (values is None):
            continue
        rows.append((name[:-4], title, born, born, moved, values))

    if len(rows) < 5:
        out.write("  too few cookery books to compare\n")
        out.flush()
        return 0

    out.write("  %-40s %-9s %-9s %s\n" % ("book", "written", "language", "words kept in place"))
    for _, title, written, language, moved, _ in sorted(
            rows, key=lambda row: row[2] if row[2] else 9999):
        out.write("  %-40s %-9s %-9s %.4f\n"
                  % (title[:40], written if written else "unknown",
                     language if language else "unknown", moved))

    dated = [row for row in rows if row[2] is not None]
    if len(dated) >= 5:
        years = numpy.asarray([float(row[2]) for row in dated])
        moved = numpy.asarray([row[4] for row in dated])
        ranked = float(numpy.corrcoef(numpy.argsort(numpy.argsort(years)),
                                      numpy.argsort(numpy.argsort(moved)))[0, 1])
        out.write("\n  clustering against when the author was born: rho %.3f over %d books\n"
                  % (ranked, len(dated)))
        out.write("  a positive value means the later a book is, the more its order carries\n")

        # How far the books of a period sit from each other, which is what a standard would shrink
        early = [row for row in dated if row[2] < 1810]
        late = [row for row in dated if row[2] >= 1810]
        if (len(early) >= 2) and (len(late) >= 2):
            def spread(group):
                return statistics.fmean(
                    float(numpy.linalg.norm(one[5] - two[5]))
                    for index, one in enumerate(group) for two in group[index + 1:])
            out.write("\n  authors born before 1810 sit %.4f from each other, %d of them\n"
                      % (spread(early), len(early)))
            out.write("  authors born from 1810 on sit %.4f from each other, %d of them\n"
                      % (spread(late), len(late)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
