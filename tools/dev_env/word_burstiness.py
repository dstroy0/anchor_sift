#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Score individual words for clustering against a permutation null, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/word_burstiness.py corpus.txt [more.txt ...]
#
# Section 7.4.1 scores symbols and finds the rare half clustering, which Section 7.4.4 places at spans
# above a sentence. The reading offered there is that a word clusters because a passage concerns what it
# names. That reading has a consequence for words naming things people do constantly instead of things a
# passage is about: those should appear throughout a text and not gather anywhere.
#
# Each word is scored as the coefficient of variation of the gaps between its occurrences, divided into
# the same quantity on a shuffle of the word sequence. A value near 1 is a word spread as evenly as
# chance allows and below 1 is a word that gathers. Words are compared only against others of similar
# frequency, since the estimate depends on how many occurrences there are.
#
# The comparison set is supplied here and is not derived from the corpus, so it states an expectation
# instead of discovering one. It reaches nothing about other languages, where the same test would need
# both a translation and a lemmatizer.

import collections
import io
import os
import random
import re
import statistics
import sys

WORD = re.compile(r"[^\W\d_]+", re.UNICODE)
MIN_OCCURRENCES = 40

# Things people do or have constantly, so a text should mention them throughout
CONSTANT = ("eat", "eating", "ate", "drink", "sleep", "see", "saw", "come", "came", "go", "went",
            "give", "gave", "take", "took", "know", "knew", "say", "said", "hand", "eye", "water")


def ratios(words):
    """Coefficient of variation of the gaps between occurrences, against a shuffle, per word."""
    seen = {}
    for index, word in enumerate(words):
        seen.setdefault(word, []).append(index)

    shuffled = list(words)
    random.Random(0x51F7).shuffle(shuffled)
    moved = {}
    for index, word in enumerate(shuffled):
        moved.setdefault(word, []).append(index)

    def spread(positions):
        gaps = [positions[step] - positions[step - 1] for step in range(1, len(positions))]
        mean = statistics.fmean(gaps)
        if mean <= 0.0:
            return None
        return statistics.pstdev(gaps) / mean

    out = {}
    for word, positions in seen.items():
        if len(positions) < MIN_OCCURRENCES:
            continue
        live = spread(positions)
        dead = spread(moved[word])
        if (live is None) or (dead is None) or (live <= 0.0):
            continue
        out[word] = (len(positions), dead / live)
    return out


def main():
    if len(sys.argv) < 2:
        print("usage: word_burstiness.py corpus.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-28s %-10s %-10s %-8s\n" % ("corpus", "constant", "all words", "scored"))

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            out.write("  no corpus at %s\n" % path)
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            words = WORD.findall(handle.read().lower())

        scored = ratios(words)
        if len(scored) < 20:
            continue
        picked = [value for word, (_, value) in scored.items() if word in CONSTANT]
        every = [value for _, value in scored.values()]
        # The supplied set is English, so it matches nothing in the other corpora. The corpus average
        # is defined for all of them and is the column that carries the comparison
        shown = ("%-10.3f" % statistics.fmean(picked)) if picked else ("%-10s" % "-")
        out.write("  %-28s %s %-10.3f %d of %d\n"
                  % (os.path.basename(path)[:-4], shown, statistics.fmean(every),
                     len(picked), len(scored)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
