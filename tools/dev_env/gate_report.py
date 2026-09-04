#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Put every corpus in the tree through the gate and see what has been standing in the readings, for
# Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/gate_report.py
#
# The gate exists because two corpora were measured for hours before anyone looked at them, and both were
# found by accident. Now that there is one path that opens a corpus, the first thing worth doing is
# running everything already held through it, since every file gathered before the gate existed was
# gathered without one.
#
# Nothing here is changed on disk. This says what each file is, and which of them have been carrying
# something other than the language they are named for.

import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import FLOOR, load, script_of, share_of_own

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 400000
PREFIXES = ("lang_", "wiki_", "para_", "para2_", "drav_", "cc_", "source_")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    checked = []
    unchecked = 0
    for name in sorted(os.listdir(CORPORA)):
        if not (name.endswith(".txt") and name.startswith(PREFIXES)):
            continue
        language, wanted = script_of(name)
        if wanted is None:
            unchecked += 1
            continue
        with open(os.path.join(CORPORA, name), encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        share, letters = share_of_own(text, wanted)
        if letters >= 500:
            checked.append((share, name, language, letters))

    checked.sort()
    out.write("  %d corpora have a known writing and were checked, %d have none\n\n"
              % (len(checked), unchecked))
    out.write("  %-34s %-12s %-9s %s\n" % ("corpus", "should be", "is", "verdict"))
    for share, name, language, letters in checked:
        if share < FLOOR:
            verdict = "below the floor, would be refused"
        elif share < 0.90:
            verdict = "carries other writing"
        elif share < 0.98:
            verdict = "a little other writing"
        else:
            verdict = ""
        out.write("  %-34s %-12s %-9.3f %s\n" % (name[:34], language, share, verdict))

    bad = [row for row in checked if row[0] < FLOOR]
    mixed = [row for row in checked if FLOOR <= row[0] < 0.90]
    out.write("\n  %d would be refused outright, %d carry noticeable other writing\n"
              % (len(bad), len(mixed)))
    if bad:
        out.write("  refused: %s\n" % ", ".join(row[1] for row in bad))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
