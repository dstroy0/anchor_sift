#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Build and dismantle collections, to test what word burstiness is reading, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/heterogeneity_control.py
#
# Section 4.13.09 finds single works scoring between 0.758 and 0.833 and collections between 0.509 and
# 0.667, and reads the quantity as how many separate subjects a text covers. Every corpus there arrived
# already being one thing or the other, so the finding is an observation over texts that were labelled
# by hand and could be tracking anything those labels correlate with.
#
# Two manipulations decide it. Joining single works into one corpus should walk the score down as works
# are added, and cutting a collection into equal pieces should walk each piece up, since a piece spans
# fewer of its books. Both are done on the same texts already measured, and length is held near constant
# in the joining arm so the walk cannot be a length effect.

import os
import re
import statistics
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
SCORER = os.path.join(ROOT, "tools", "dev_env", "word_burstiness.py")

# English single works, so the walk is not a change of language
JOINED = ("english_1813_austen", "english_1667_milton_epic", "english_1720_pope_iliad_epic")
SPLIT = "english_1611_kjv"
PIECES = 8
BUDGET = 900000


def read(name):
    with open(os.path.join(CORPORA, name + ".txt"), encoding="utf-8", errors="replace") as handle:
        return handle.read()


def write(name, text):
    path = os.path.join(CORPORA, name + ".txt")
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    return path


def score(path):
    """The corpus average column from the scorer, so one implementation produces every figure here."""
    done = subprocess.run([sys.executable, SCORER, path], capture_output=True, text=True)
    for line in done.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[0] == os.path.basename(path)[:-4]:
            return float(fields[2]) if fields[1] == "-" else float(fields[2])
    return None


def main():
    print("  joining single works, total length held near %d characters" % BUDGET)
    for count in range(1, len(JOINED) + 1):
        share = BUDGET // count
        text = "\n".join(read(name)[:share] for name in JOINED[:count])
        path = write("control_joined_%d" % count, text)
        print("    %d work(s)   %s" % (count, score(path)))

    whole = read(SPLIT)
    print("  cutting a collection of 66 books, whole scores %s" % score(
        os.path.join(CORPORA, SPLIT + ".txt")))

    # Sweeping the cut says whether the climb continues as a piece spans fewer books, which is what
    # reading the quantity as a count of subjects requires
    for count in (PIECES, PIECES * 2, PIECES * 4, PIECES * 8):
        span = len(whole) // count
        marks = []
        for piece in range(count):
            path = write("control_piece", whole[piece * span:(piece + 1) * span])
            value = score(path)
            if value is not None:
                marks.append(value)
        if marks:
            print("    %-3d pieces, about %4.1f books each   %.3f mean, %.3f to %.3f"
                  % (count, 66.0 / count, statistics.fmean(marks), min(marks), max(marks)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
