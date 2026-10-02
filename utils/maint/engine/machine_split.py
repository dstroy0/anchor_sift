#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""cell_sass_probe_machine.c cut along the line it already divides on.

    machine_split.py

Writing a cubin from text moves to cell_sass_probe_cubin.c; learning what the part holds stays. The cut is by line
number, taken once, and the lines move whole. Nothing here rewrites a line.
"""

import os
import sys

TOP = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CELL = os.path.join(TOP, "utils", "test", "src", "c", "transpiler", "cell")
MACHINE = os.path.join(CELL, "cell_sass_probe_machine.c")
CUBIN = os.path.join(CELL, "cell_sass_probe_cubin.c")

# the run of lines that moves, 1-based and inclusive: the cubin sizes, the buffers they need, reading and writing a
# file, the exit encoding, and the three entries that turn a listing back into a cubin
MOVED = (284, 396)

HEAD = """// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_sass_probe_cubin.c: a cubin written from text. The probe learns what the part holds by reading its tools;
// this is the other direction, putting instructions of the cell's own into a cubin the part will load and run, with
// a cubin the toolchain built standing as the pattern for everything an ELF carries that no instruction states
#include "cell_sass_probe.h"
#include "cubin_write.h"
#include "sass_assemble.h"

#include <stdio.h>
#include <string.h>

"""


def main():
    with open(MACHINE, "r", encoding="utf-8", newline="") as file:
        lines = file.readlines()
    first, last = MOVED
    if len(lines) < last:
        print("  %s holds %d lines, fewer than the cut" % (MACHINE, len(lines)))
        return 1
    moved = lines[first - 1:last]
    kept = lines[:first - 1] + lines[last:]
    with open(CUBIN, "w", encoding="utf-8", newline="") as file:
        file.write(HEAD)
        file.write("".join(moved).strip("\n") + "\n")
    with open(MACHINE, "w", encoding="utf-8", newline="") as file:
        file.write("".join(kept))
    print("  %s: %d lines" % (os.path.basename(MACHINE), len(kept)))
    print("  %s: %d lines" % (os.path.basename(CUBIN), len(moved) + HEAD.count("\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
