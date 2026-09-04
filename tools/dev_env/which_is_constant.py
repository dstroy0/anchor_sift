#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Compare how stable two candidate invariants are across sources, for the ledger entry on collision
# entropy in docs/research/anchor-sift-ledger.md.
#
#   Usage:  python tools/dev_env/which_is_constant.py corpus.sym [more.sym ...]
#
# Collision entropy was recorded as near constant for a language at 3.800 bits over ten Gutenberg texts,
# and it moves by 0.13 to 0.24 bits when the same language is measured from a different source. The
# cause is the character inventory: one source keeps accents and punctuation the other flattens, and a
# larger inventory admits a higher $H_2$.
#
# The distance between boundaries should not care about that. It is set by how long words are, and a rare
# accented letter appearing a few times per thousand symbols moves it by almost nothing. This measures
# both quantities on every corpus given and reports the spread of each, so which one is stable is decided
# by the numbers instead of argued.

import io
import math
import os
import statistics
import sys


def measures(seats):
    counts = {}
    for value in seats:
        counts[value] = counts.get(value, 0) + 1
    total = float(len(seats))

    collision = sum((count / total) ** 2 for count in counts.values())
    bits = -math.log2(collision)

    # The commonest symbol is the boundary in every corpus measured here, and the mean distance between
    # its occurrences is the reciprocal of its share
    top = max(counts.values()) / total
    return bits, 1.0 / top, len(counts)


def main():
    if len(sys.argv) < 2:
        print("usage: which_is_constant.py corpus.sym [more.sym ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  %-30s %-9s %-11s %s\n" % ("corpus", "H2 bits", "mean gap", "symbols"))

    rows = []
    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, "rb") as handle:
            seats = handle.read()
        if len(seats) < 200000:
            continue
        bits, gap, distinct = measures(seats)
        rows.append((bits, gap, distinct, os.path.basename(path)[:-4]))

    for bits, gap, distinct, name in sorted(rows, key=lambda row: row[3]):
        out.write("  %-30s %-9.3f %-11.3f %d\n" % (name, bits, gap, distinct))

    if len(rows) >= 3:
        bits_all = [row[0] for row in rows]
        gaps_all = [row[1] for row in rows]
        # Reported as a coefficient of variation so two quantities in different units can be compared
        out.write("\n  %-16s %-10s %-10s %-10s %s\n"
                  % ("quantity", "mean", "sd", "cv", "range"))
        out.write("  %-16s %-10.3f %-10.3f %-10.4f %.3f to %.3f\n"
                  % ("H2 bits", statistics.fmean(bits_all), statistics.pstdev(bits_all),
                     statistics.pstdev(bits_all) / statistics.fmean(bits_all),
                     min(bits_all), max(bits_all)))
        out.write("  %-16s %-10.3f %-10.3f %-10.4f %.3f to %.3f\n"
                  % ("mean gap", statistics.fmean(gaps_all), statistics.pstdev(gaps_all),
                     statistics.pstdev(gaps_all) / statistics.fmean(gaps_all),
                     min(gaps_all), max(gaps_all)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
