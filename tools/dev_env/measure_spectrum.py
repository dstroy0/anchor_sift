#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Report the permutation null ratio for every symbol in a corpus, by frequency rank, for Section 7.4
# of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/measure_spectrum.py corpus.sym [more.sym ...]
#
# The boundary detector in the bench returns one symbol, the one whose gaps are most regular, and it
# rejects any candidate occurring less often than once in 64 symbols. That rejection can only ever
# return a frequent symbol, so every result it has produced describes the head of the distribution.
#
# Under a Zipf distribution the head carries the token count and the tail carries the information, since
# the surprisal of a symbol is -log p and the many rare symbols each contribute more of it. This reads
# every symbol instead of one, so the head and the tail can be compared directly.
#
# Each symbol is scored the same way the bench scores its winner: the coefficient of variation of the
# gaps between successive occurrences, against the same quantity on a shuffle of the corpus. A shuffle
# preserves how often each symbol occurs and destroys where, so a ratio above one is structure in the
# positions and not in the counts.

import os
import random
import statistics
import sys

MIN_OCCURRENCES = 32


def dispersion_by_symbol(seats):
    """Coefficient of variation of the gaps between occurrences, per symbol."""
    seen = {}
    for index, value in enumerate(seats):
        seen.setdefault(value, []).append(index)

    out = {}
    for value, positions in seen.items():
        if len(positions) < MIN_OCCURRENCES:
            continue
        gaps = [positions[step] - positions[step - 1] for step in range(1, len(positions))]
        mean = statistics.fmean(gaps)
        if mean <= 0.0:
            continue
        out[value] = (mean, statistics.pstdev(gaps) / mean, len(positions))
    return out


def report(path):
    with open(path, "rb") as handle:
        seats = bytearray(handle.read())

    live = dispersion_by_symbol(seats)
    shuffled_seats = bytearray(seats)
    random.Random(0x51F7).shuffle(shuffled_seats)
    dead = dispersion_by_symbol(shuffled_seats)

    rows = []
    for value, (mean, spread, count) in live.items():
        if value not in dead:
            continue
        shuffled_spread = dead[value][1]
        if spread <= 0.0:
            continue
        rows.append((count, value, mean, spread, shuffled_spread / spread))

    rows.sort(reverse=True)
    print("%s  %d symbols scored" % (os.path.basename(path), len(rows)))
    print("  %-6s %-6s %-10s %-10s %-8s" % ("rank", "seat", "mean gap", "dispersion", "ratio"))

    # The head, then the best of the tail, since the question is whether the tail carries more
    for rank, row in enumerate(rows[:3], start=1):
        print("  %-6d %-6d %-10.2f %-10.4f %-8.2f" % (rank, row[1], row[2], row[3], row[4]))

    tail = rows[len(rows) // 2:]
    if tail:
        best = max(tail, key=lambda row: row[4])
        print("  %-6s %-6d %-10.2f %-10.4f %-8.2f"
              % ("tail*", best[1], best[2], best[3], best[4]))
        print("  %-6s %-6s %-10s %-10.4f %-8.2f"
              % ("tailav", "", "", statistics.fmean(row[3] for row in tail),
                 statistics.fmean(row[4] for row in tail)))
    print("  %-6s %-6s %-10s %-10.4f %-8.2f"
          % ("headav", "", "", statistics.fmean(row[3] for row in rows[:len(rows) // 2]),
             statistics.fmean(row[4] for row in rows[:len(rows) // 2])))
    return 0


def main():
    if len(sys.argv) < 2:
        print("usage: measure_spectrum.py corpus.sym [more.sym ...]")
        return 1
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            print("no corpus at %s" % path)
            continue
        report(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
