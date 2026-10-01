#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""One exact text swapped for another in a file, once, with the file's line endings kept.

    prose_swap.py <file> <old> <new>

The old text is matched whole and must appear exactly once: a text that appears twice, or not at all, is a swap
whose reach nobody checked, and the file is left alone. sed cannot do this, because the texts here run over line
ends and carry the punctuation sed reads as its own.
"""

import sys


def main(arguments):
    if len(arguments) != 3:
        print(__doc__)
        return 2
    path, old, new = arguments
    with open(path, "r", encoding="utf-8", newline="") as file:
        held = file.read()
    found = held.count(old)
    if found != 1:
        print("  %s holds %d of that text, not one: left alone" % (path, found))
        return 1
    with open(path, "w", encoding="utf-8", newline="") as file:
        file.write(held.replace(old, new))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
