#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""cell_sass_probe_main.c cut into two along the line it already divides on.

    probe_split.py

What the part is asked, and what the part is asked to weigh, move to cell_sass_probe_ask.c; finding each form's
operations and each operation's fields stays. The cut is by line number, taken once, and the lines move whole.
Nothing here rewrites a line.
"""

import os
import sys

TOP = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CELL = os.path.join(TOP, "utils", "test", "engine", "compiler", "cell")
MAIN = os.path.join(CELL, "cell_sass_probe_main.c")
ASK = os.path.join(CELL, "cell_sass_probe_ask.c")

# the two runs of lines that move, 1-based and inclusive: running a cubin and reading the clock, then every question
# of the cell's own and every question of preference
MOVED = ((260, 306), (344, 690))

HEAD = """// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_sass_probe_ask.c: the questions the cell puts to the part in code no toolchain wrote. Every other piece here
// reads what the part's own tools say about it; this one runs the part and reads back what it answers. Nothing else
// tells an encoding the part executes from one its disassembler merely named
#include "cell_sass_probe.h"

#include <stdlib.h>
#include <string.h>

"""


def main():
    with open(MAIN, "r", encoding="utf-8", newline="") as file:
        lines = file.readlines()
    if len(lines) < MOVED[-1][1]:
        print("  %s holds %d lines, fewer than the cut" % (MAIN, len(lines)))
        return 1
    moved = []
    kept = []
    for number, line in enumerate(lines, start=1):
        inside = any(first <= number <= last for first, last in MOVED)
        (moved if inside else kept).append(line)
    with open(ASK, "w", encoding="utf-8", newline="") as file:
        file.write(HEAD)
        file.write("".join(moved).strip("\n") + "\n")
    with open(MAIN, "w", encoding="utf-8", newline="") as file:
        file.write("".join(kept))
    print("  %s: %d lines" % (os.path.basename(MAIN), len(kept)))
    print("  %s: %d lines" % (os.path.basename(ASK), len(moved) + HEAD.count("\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
