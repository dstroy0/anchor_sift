#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Compare the vocabulary of two corpora, for the drift measurement in docs/research/anchor-sift.md.
#
# Section 4.13 measures each text on its own. Drift is a claim about the distance between two of them,
# so it needs a comparison the per corpus measures cannot give.
#
#   Usage:  python tools/dev_env/measure_drift.py left.txt right.txt
#
# Two bands are reported because they answer different questions. The top 100 words of any English
# text are almost all function words, which carry the grammar and move slowly. The band from rank 500
# to 2000 is mostly content, which follows the subject and therefore the genre. A pair that agrees on
# the first and disagrees on the second differs in what it is about. A pair that disagrees on the
# first differs in the language itself.

import os
import re
import sys
from collections import Counter

WORD = re.compile(r"[^\W\d_]+", re.UNICODE)


def load(path):
    """Count words, lowercased, with digits and punctuation dropped."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read().lower()
    return Counter(WORD.findall(text))


def band(counts, low, high):
    """The set of words whose frequency rank falls in [low, high)."""
    ordered = [word for word, _ in counts.most_common()]
    return set(ordered[low:high])


def jaccard(left, right):
    """Overlap of two sets as a fraction of their union, 1.0 when identical."""
    union = left | right
    if not union:
        return 0.0
    return len(left & right) / len(union)


def main():
    if len(sys.argv) < 3:
        print("usage: measure_drift.py left.txt right.txt")
        return 1

    left_path = sys.argv[1]
    right_path = sys.argv[2]

    for path in (left_path, right_path):
        if not os.path.isfile(path):
            print("no corpus at %s" % path)
            return 1

    left = load(left_path)
    right = load(right_path)

    grammar = jaccard(band(left, 0, 100), band(right, 0, 100))
    content = jaccard(band(left, 500, 2000), band(right, 500, 2000))

    print("drift,%s,%s,%.4f,%.4f"
          % (os.path.basename(left_path), os.path.basename(right_path), grammar, content))
    return 0


if __name__ == "__main__":
    sys.exit(main())
