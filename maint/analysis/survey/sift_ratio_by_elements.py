#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Split the cascade's survivor ratio by how many elements the structure holds.
#
#   Usage:  python maint/analysis/survey/sift_ratio_by_elements.py RUN_FILE
#
# WHY THE SPLIT IS THE RESULT AND NOT A REFINEMENT OF IT
#
# examples/crystallography/5_sift/lattice_breaks_the_product_rule.py closes with one median over
# every needle it drew, and at its default limit of 12 that median is near 4.5. The line under it
# says the product rule is out by that factor. Run the same file over the whole cache and the corpus
# stops being twelve multi-element minerals: the 9013xxx block of the archive is elemental phases,
# one element each, and those come back at ratios near 0.1.
#
# Both are the product rule being wrong and they are wrong in OPPOSITE DIRECTIONS. A single
# median over the mixture reports a number that describes neither population and moves with whatever
# the fetch happened to gather. That is not a sharper version of the original claim. It is the
# reason the original claim needs a denominator attached to it.
#
# THE MECHANISM, STATED BEFORE THE NUMBERS
#
# The product rule predicts survivors as the product of the anchors' own rates. An anchor is
# `element E at displacement d`, and the rate it is given credit for is how often E occurs.
#
# In a structure with one element every anchor matches compositionally at every occupied place.
# Each rate is 1 and the rule predicts that nothing is filtered. What actually filters an alignment
# there is whether the displacement lands on an occupied place at all, which is geometry and which
# the rule does not model. So the rule OVER predicts and the ratio falls below one.
#
# In a structure with several elements the rates are genuinely below one, and the rule's error is the
# other one: it assumes the anchors are positioned independently, and a lattice is where they are
# least independent of anything. So the rule UNDER predicts and the ratio rises above one.
#
# One failure is the rule ignoring occupancy. The other is the rule ignoring correlation. Reporting
# their median together hides both.
#
# WHAT THIS READS
#
# The table the cascade already writes, one row per structure, which carries the element count and
# the per-structure median. It does not re-run the cascade, and it therefore reports a median OF
# PER-STRUCTURE MEDIANS and never the cascade's own median over every needle. Those are different
# statistics and the output says so on the line that prints one.

import argparse
import io
import os
import statistics
import sys


def rows(path):
    """(entry, points, elements, median, worst) for every data row of a cascade run.

    A row is taken only where all five fields parse as the table's own types. The run writes a
    header, a blank line and a closing paragraph into the same stream, and anything that is not a
    data row is skipped and not guessed at.
    """
    found = []
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.split()
            if len(parts) != 6:
                continue
            try:
                found.append(
                    (
                        parts[0],
                        int(parts[1]),
                        int(parts[2]),
                        float(parts[3]),
                        float(parts[4]),
                    )
                )
            except ValueError:
                continue
    return found


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("run", help="output file of lattice_breaks_the_product_rule.py")
    args = parser.parse_args()

    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    out.write("\n  run %s\n\n" % args.run)

    if not os.path.isfile(args.run):
        out.write(
            "  REFUSED: no file at that path. This is not a split of zero rows.\n\n"
        )
        out.flush()
        return 1

    found = rows(args.run)
    if not found:
        out.write(
            "  REFUSED: no data rows parsed out of that file. This is not a split of zero.\n\n"
        )
        out.flush()
        return 1

    single = [row for row in found if row[2] == 1]
    several = [row for row in found if row[2] > 1]

    out.write("  %d structures in the run\n\n" % len(found))
    out.write(
        "  %-26s %-10s %-12s %s\n"
        % ("population", "structures", "median", "share over 1")
    )

    for name, group in (
        ("one element", single),
        ("more than one element", several),
        ("every structure", found),
    ):
        if not group:
            out.write("  %-26s %-10d %-12s %s\n" % (name, 0, "none", "none"))
            continue
        medians = [row[3] for row in group]
        over = sum(1 for value in medians if value > 1.0)
        out.write(
            "  %-26s %-10d %-12.2f %.1f%%\n"
            % (name, len(group), statistics.median(medians), 100.0 * over / len(group))
        )

    out.write(
        "\n  These are medians OF PER-STRUCTURE MEDIANS, read off the table the run wrote.\n"
    )
    out.write(
        "  The cascade's own closing figure is a median over every needle and is not this.\n\n"
    )

    out.write("  %-12s %-12s %s\n" % ("elements", "structures", "median of medians"))
    counts = {}
    for row in found:
        counts.setdefault(row[2], []).append(row[3])
    for elements in sorted(counts):
        out.write(
            "  %-12d %-12d %.2f\n"
            % (elements, len(counts[elements]), statistics.median(counts[elements]))
        )
    out.write("\n")

    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
