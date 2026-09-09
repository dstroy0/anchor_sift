#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ANY-5-001
#
# Four selection rules on the same needles, and the two columns that are graded differently.
#
#   Usage:  python examples/any_corpus/5_sift/selection_rules.py corpus.sym [more.sym ...]
#
# An anchor is a condition copied out of the needle. A position genuinely holding the needle
# satisfies every anchor whatever chose it. Correctness cannot turn on the rule. What the rule moves
# is how many false candidates survive, which is cost. This prints both, and only one of them is
# allowed to move.
#
# The sizing column is the other half. Multiplying the rate of each anchor is correct when the
# anchors refute independently, and rarity chooses, by construction, the symbols least likely to be
# positioned independently: the rare half of a distribution is the half whose occurrences gather
# into passages. A cascade of rare anchors therefore survives more often than the product predicts.
#
# The needle source matters and is swept. A needle cut from the corpus is guaranteed to occur, so
# every search confirms one true occurrence and that hit is not a false positive. The construction
# is specified against a pattern that is unknown and of arbitrary width, and such a pattern is almost
# never present. A needle drawn independently over the same alphabet is the stated problem.

import io
import os
import random
import statistics
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from sift.anchors import cell_rarest, jittered, positions_by_symbol, rarest, spread, survivors  # noqa: E402

NEEDLE = 24
ANCHORS = 3
TRIALS = 200
SEED = 0xA9C40


def report(out, path):
    with open(path, "rb") as handle:
        seats = bytearray(handle.read())
    if len(seats) < 50000:
        return

    total = len(seats)
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    places = positions_by_symbol(seats)
    alphabet = sorted(places)

    out.write("%s, %d symbols over %d\n" % (os.path.basename(path)[:-4], total, len(alphabet)))
    out.write("  %-14s %-13s %-13s %-13s %s\n"
              % ("rule", "needle", "passed", "sizing error", "lost a true hit"))

    for source in ("from corpus", "independent"):
        rng = random.Random(SEED)
        drawn = []
        for _ in range(TRIALS):
            start = rng.randrange(0, total - NEEDLE)
            if source == "from corpus":
                drawn.append((start, seats[start:start + NEEDLE]))
            else:
                drawn.append((None, bytearray(rng.choice(alphabet) for _ in range(NEEDLE))))

        for name, pick in (("rarest", lambda needle: rarest(needle, counts, ANCHORS)),
                           ("spread", lambda needle: spread(NEEDLE, ANCHORS)),
                           ("jittered", lambda needle: jittered(NEEDLE, ANCHORS,
                                                                random.Random(SEED))),
                           ("cell_rarest", lambda needle: cell_rarest(needle, counts, ANCHORS))):
            passed = []
            errors = []
            lost = 0
            for start, needle in drawn:
                offsets = pick(needle)
                kept = survivors(places, needle, offsets)

                predicted = float(total - NEEDLE)
                for offset in offsets:
                    predicted *= counts[needle[offset]] / float(total)

                # The needle's own occurrence is not a false positive, so the excess is what counts
                excess = max(len(kept) - (1 if start is not None else 0), 0)
                passed.append(excess)
                if predicted > 0.0:
                    errors.append(excess / predicted)
                if (start is not None) and (start not in kept):
                    lost += 1

            out.write("  %-14s %-13s %-13.1f %-13.2f %s\n"
                      % (name, source, statistics.fmean(passed),
                         statistics.median(errors) if errors else float("nan"),
                         "NONE" if lost == 0 else "%d of %d" % (lost, TRIALS)))
    out.write("\n")


def main():
    if len(sys.argv) < 2:
        print("usage: selection_rules.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for path in sys.argv[1:]:
        if os.path.isfile(path):
            report(out, path)

    out.write("  passed and sizing error are cost and are expected to move with the rule.\n")
    out.write("  the last column is correctness and has one acceptable value.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
