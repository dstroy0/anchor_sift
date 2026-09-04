#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Compare what the frequent and rare halves of an English corpus are made of, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/head_tail_parts.py corpus.txt [more.txt ...]
#
# Printing the head shows person reference in it for every language measured. The matching claim about
# the rare half, that it carries the actions, needs counting instead of looking, and no part of speech
# tagger is available here.
#
# English inflects its verbs, so the endings -ed and -ing stand in for one. The proxy is weak and its
# weakness runs one way: a gerund used as a noun and an adjective formed from a participle both carry
# these endings without being verbs, so the count is an upper bound. It applies to English only and
# says nothing about the other corpora.

import collections
import io
import os
import re
import sys

WORD = re.compile(r"[^\W\d_]+", re.UNICODE)
MARKS = ("ed", "ing")
FLOOR = 3


def inflected_share(types):
    if not types:
        return 0.0
    hits = sum(1 for word in types if (len(word) > 4) and word.endswith(MARKS))
    return 100.0 * hits / len(types)


def main():
    if len(sys.argv) < 2:
        print("usage: head_tail_parts.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-30s %-10s %-10s\n" % ("corpus", "head %", "tail %"))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            out.write("  no corpus at %s\n" % path)
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            counts = collections.Counter(WORD.findall(handle.read().lower()))

        # A type seen once or twice carries no reliable rank, and the rare half is mostly those
        ranked = [word for word, count in counts.most_common() if count >= FLOOR]
        if len(ranked) < 8:
            continue
        cut = len(ranked) // 2
        out.write("  %-30s %-10.1f %-10.1f\n"
                  % (os.path.basename(path)[:-4], inflected_share(ranked[:cut]),
                     inflected_share(ranked[cut:])))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
