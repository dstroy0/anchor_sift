#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Print the most frequent words of each corpus, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/top_words.py corpus.txt [more.txt ...]
#
# Every measurement in this document is distributional and none of them reads a word. Section 7.4 finds
# the head of the distribution carrying the least information per token and Section 4.13.08 finds it the
# slowest part of a language to change over four centuries. Printing the head lets a reader see what
# occupies it, which is the one question the statistics cannot answer.
#
# Output is written as UTF-8 explicitly, since the Windows console encoding drops any script that is
# not Latin and would silently omit the corpora this comparison exists for.

import collections
import io
import os
import re
import sys

WORD = re.compile(r"[^\W\d_]+", re.UNICODE)
SHOWN = 12


def main():
    if len(sys.argv) < 2:
        print("usage: top_words.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            out.write("no corpus at %s\n" % path)
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            counts = collections.Counter(WORD.findall(handle.read().lower()))
        head = " ".join(word for word, _ in counts.most_common(SHOWN))
        out.write("%-30s %s\n" % (os.path.basename(path)[:-4], head))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
