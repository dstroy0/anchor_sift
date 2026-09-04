#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Ask how writing moves over three centuries, with dates nobody here chose, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/german_centuries.py
#
# The same question was asked of fourteen cookery books and could not be answered. They were dated by the
# first four digit number printed in each, which put a 1919 book in 1600. Dated again by author lifetimes
# they covered 1588 to 1858 with most inside one century, one medieval text was dated to its eighteenth
# century editor, and the periods were split at 1810 because that put five books on one side.
#
# This archive fixes every one of those faults. It is one language, prepared to one standard, each text
# carrying its year in its name, split into centuries by the archive and not by me, and licensed for use
# with attribution. Its texts are the German printed record from 1600 to 1899.
#
# Two questions, and the second is the real one. Whether a century can be told from another century is a
# yes or no. Whether the distance between two texts grows with the years between them is a shape, and a
# shape is far harder to satisfy by accident: it has to hold across two hundred years, for pairs inside a
# century as well as pairs across two of them, and it cannot be produced by any single boundary being
# drawn well.
#
# What the night's results predict: the reading follows the surface of a writing system, and German
# spelling, capitalization and typesetting all moved a great deal across this span, so the years should
# come out strongly. If they do not, the reading is weaker than everything so far suggests.

import io
import os
import random
import re
import sys
import zipfile

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CENTURIES = ("1600-1699", "1700-1799", "1800-1899")
PER_CENTURY = 70
SAME_LENGTH = 60000
RANKS = 64
SEED = 0x51F7


def read_texts(century):
    """Texts from one century's archive, with the year each carries in its name."""
    path = os.path.join(CORPORA, "dta_%s.zip" % century)
    if not os.path.isfile(path):
        return []
    found = []
    with zipfile.ZipFile(path) as bundle:
        names = [name for name in bundle.namelist() if name.endswith(".txt")]
        rng = random.Random(SEED)
        rng.shuffle(names)
        for name in names:
            if len(found) >= PER_CENTURY:
                break
            year = re.search(r"_(1[5-9][0-9]{2})\.txt$", name)
            if not year:
                continue
            try:
                text = bundle.read(name).decode("utf-8", errors="replace")
            except Exception:
                continue
            text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
            if len(text) < SAME_LENGTH:
                continue
            found.append((int(year.group(1)), os.path.basename(name)[:-4], text[:SAME_LENGTH]))
    return found


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for century in CENTURIES:
        held = read_texts(century)
        out.write("  %s: %d texts long enough, years %s\n"
                  % (century, len(held),
                     ("%d to %d" % (min(row[0] for row in held), max(row[0] for row in held)))
                     if held else "none"))
        for year, name, text in held:
            values = web(text, RANKS)
            if values is not None:
                rows.append((year, century, name, values))

    if len(rows) < 30:
        out.write("\n  only %d texts, too few\n" % len(rows))
        out.flush()
        return 0

    out.write("\n  %d texts in all, each read from %d characters\n" % (len(rows), SAME_LENGTH))

    # Whether a century can be told from another, holding each text out
    centuries = sorted({row[1] for row in rows})
    correct = 0
    for index, (_, century, _, values) in enumerate(rows):
        best = None
        picked = None
        for other in centuries:
            kept = [row[3] for position, row in enumerate(rows)
                    if row[1] == other and position != index]
            if not kept:
                continue
            distance = float(numpy.linalg.norm(values - numpy.mean(numpy.stack(kept), axis=0)))
            if (best is None) or (distance < best):
                best = distance
                picked = other
        correct += 1 if picked == century else 0
    out.write("  a text lands in its own century %d of %d, guessing gets %.1f percent\n"
              % (correct, len(rows), 100.0 / len(centuries)))

    # Whether the distance between two texts grows with the years between them
    gaps = []
    apart = []
    for index, one in enumerate(rows):
        for two in rows[index + 1:]:
            gaps.append(abs(one[0] - two[0]))
            apart.append(float(numpy.linalg.norm(one[3] - two[3])))
    gaps = numpy.asarray(gaps, dtype=numpy.float64)
    apart = numpy.asarray(apart, dtype=numpy.float64)
    ranked = float(numpy.corrcoef(numpy.argsort(numpy.argsort(gaps)),
                                  numpy.argsort(numpy.argsort(apart)))[0, 1])
    out.write("\n  years between two texts against how far apart they read: rho %.3f over %d pairs\n"
              % (ranked, len(gaps)))

    out.write("  %-18s %-11s %s\n" % ("years between", "pairs", "how far apart"))
    for low, high in ((0, 25), (25, 50), (50, 100), (100, 150), (150, 200), (200, 400)):
        inside = (gaps >= low) & (gaps < high)
        if int(inside.sum()) >= 20:
            out.write("  %-18s %-11d %.4f\n"
                      % ("%d to %d" % (low, high), int(inside.sum()), float(apart[inside].mean())))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
