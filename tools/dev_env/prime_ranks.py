#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Where the semantic primes fall in a frequency ranking, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/prime_ranks.py corpus.txt [more.txt ...]
#
# Section 4.13.09 finds the frequent half of a corpus holding reference to persons, a conjunction, and a
# copula or a negation, in every language measured. The Natural Semantic Metalanguage of Wierzbicka and
# Goddard proposes 65 primes, words claimed to be undefinable and to have an exponent in every language.
# The two look similar and the resemblance may be an accident of which primes were noticed.
#
# NSM defines a prime by semantic indefinability, which says nothing about how often it is used, so there
# is no reason for a prime to be frequent. This checks it: if the primes cluster at the top of a ranking
# they are the same object as the head, and if they scatter across it they are not.
#
# The English exponents are taken from the published chart. Words with several exponents are listed by
# their commonest one.

import collections
import io
import os
import re
import statistics
import sys

WORD = re.compile(r"[^\W\d_]+", re.UNICODE)

# The 65 primes, by the group the chart puts them in
PRIMES = (
    ("substantives", ("i", "you", "someone", "people", "something", "thing", "body")),
    ("relational", ("kind", "part")),
    ("determiners", ("this", "same", "other", "else", "another")),
    ("quantifiers", ("one", "two", "some", "all", "much", "many", "little", "few")),
    ("evaluators", ("good", "bad")),
    ("descriptors", ("big", "small")),
    ("mental", ("think", "know", "want", "feel", "see", "hear")),
    ("speech", ("say", "words", "true")),
    ("actions", ("do", "happen", "move")),
    ("existence", ("be", "is", "there", "mine")),
    ("life", ("live", "die")),
    ("time", ("when", "time", "now", "before", "after", "moment")),
    ("space", ("where", "place", "here", "above", "below", "far", "near", "side", "inside", "touch")),
    ("logical", ("not", "maybe", "can", "because", "if")),
    ("intensifier", ("very", "more")),
    ("similarity", ("like", "as", "way")),
)


def main():
    if len(sys.argv) < 2:
        print("usage: prime_ranks.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            counts = collections.Counter(WORD.findall(handle.read().lower()))
        order = {word: rank for rank, (word, _) in enumerate(counts.most_common(), start=1)}
        total = len(order)

        out.write("%s, %d distinct words\n" % (os.path.basename(path)[:-4], total))
        out.write("  %-14s %-8s %-9s %-9s %s\n"
                  % ("group", "found", "median", "best", "worst"))

        every = []
        for label, words in PRIMES:
            ranks = [order[word] for word in words if word in order]
            if not ranks:
                continue
            every.extend(ranks)
            out.write("  %-14s %-8d %-9d %-9d %d\n"
                      % (label, len(ranks), int(statistics.median(ranks)), min(ranks), max(ranks)))

        if every:
            inside = sum(1 for rank in every if rank <= 100)
            out.write("  %-14s %-8d %-9d %-9d %d\n"
                      % ("all primes", len(every), int(statistics.median(every)),
                         min(every), max(every)))
            out.write("  %d of %d primes fall in the top 100, which is %.0f%%\n\n"
                      % (inside, len(every), 100.0 * inside / len(every)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
