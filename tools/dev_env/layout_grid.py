#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Measure coordinate quantization in a board layout, for the symbol width discussion in Section 4.10 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/layout_grid.py layout.txt [more.txt ...]
#
# Every other measurement of a human layer in this work has to argue that some channel is not required.
# A board layout removes the argument in a different way from assembly. A coordinate in one can hold any
# value the format's precision allows, and the fabricator accepts it: physics does not prefer 12.7000 to
# 12.7031, and no rule of the format forbids either. Designers place on a grid anyway, because a person
# is moving the parts.
#
# So the share of coordinates landing on a round fraction measures a convention with no physical content
# and no format content. A machine generated layout, from an autorouter or a script, need not show it.

import io
import os
import re
import sys

NUMBER = re.compile(r"-?\d+\.\d+")
# Common design grids expressed in millimetres, plus the imperial hundredth that most tools default to
GRIDS = ((0.01, "0.01 mm"), (0.05, "0.05 mm"), (0.1, "0.1 mm"), (0.254, "10 mil"), (0.635, "25 mil"))


def snapped(values, step, tolerance=1e-6):
    hits = 0
    for value in values:
        remainder = abs(value / step - round(value / step))
        if remainder * step < tolerance:
            hits += 1
    return hits / float(len(values))


def main():
    if len(sys.argv) < 2:
        print("usage: layout_grid.py layout.txt [more.txt ...]")
        return 1

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()

        values = [float(match) for match in NUMBER.findall(text)]
        if len(values) < 200:
            out.write("%s: %d decimal numbers, too few\n" % (os.path.basename(path), len(values)))
            continue

        # How many decimal places are actually used, which bounds what any snap figure can mean
        places = {}
        for match in NUMBER.findall(text):
            width = len(match.split(".")[1])
            places[width] = places.get(width, 0) + 1
        shape = ", ".join("%d dp %.2f" % (width, count / float(len(values)))
                          for width, count in sorted(places.items()))

        out.write("%s, %d decimal numbers\n  %s\n" % (os.path.basename(path), len(values), shape))
        out.write("  %-10s %s\n" % ("grid", "share on grid"))
        for step, label in GRIDS:
            out.write("  %-10s %.3f\n" % (label, snapped(values, step)))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
