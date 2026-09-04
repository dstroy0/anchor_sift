#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Put every corpus through the gate and write down the verdict, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/gate_sweep.py
#
# The gate stops a dirty file being measured, but only where a reading calls it, and a check each tool has
# to remember is the same check that was forgotten before. So the sweep is run once over everything and
# the answer is written to a file. A reading then consults the verdict instead of repeating the check, and
# a corpus that has never been through the gate is visible as one with no verdict.
#
# What this catches is worth stating plainly, because two of these were found by accident and cost hours
# each. A Greek to English lexicon standing in a Greek corpus. Untranslated English in seven Indic files,
# from 1.8 to 30.0 percent, which inverted a whole language family and drew three explanations before
# anyone looked. Neither is exotic and neither announces itself.
#
# Nothing is deleted or changed on disk. The manifest says what each file is, and a reading decides what
# to do about it.

import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_gate import FLOOR, script_of, share_of_own

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
TARGET = os.path.join(ROOT, "build", "corpus_manifest.csv")

CAP = 400000
LEAST_LETTERS = 500


def verdict_for(share):
    if share < FLOOR:
        return "refuse"
    if share < 0.90:
        return "clean"
    if share < 0.98:
        return "watch"
    return "pass"


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for name in sorted(os.listdir(CORPORA)):
        if not name.endswith(".txt"):
            continue
        path = os.path.join(CORPORA, name)
        language, wanted = script_of(name)
        if wanted is None:
            rows.append((name, "", 0.0, "unknown", 0))
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read(CAP)
        share, letters = share_of_own(text, wanted)
        if letters < LEAST_LETTERS:
            rows.append((name, language, share, "too short", letters))
            continue
        rows.append((name, language, share, verdict_for(share), letters))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("corpus,language,own_script,verdict,letters\n")
        for name, language, share, verdict, letters in rows:
            handle.write("%s,%s,%.4f,%s,%d\n" % (name, language, share, verdict, letters))

    counts = {}
    for _, _, _, verdict, _ in rows:
        counts[verdict] = counts.get(verdict, 0) + 1

    out.write("  %d corpora swept\n\n" % len(rows))
    out.write("  %-12s %-7s %s\n" % ("verdict", "count", "what it means"))
    meanings = {
        "pass": "its own writing throughout, measure it as it is",
        "watch": "a little foreign writing, usually names and citations",
        "clean": "carries enough foreign writing to cut out first",
        "refuse": "is not mostly the language it is named for",
        "unknown": "no writing registered for it, never checked",
        "too short": "not enough letters to judge",
    }
    for verdict in ("pass", "watch", "clean", "refuse", "unknown", "too short"):
        if verdict in counts:
            out.write("  %-12s %-7d %s\n" % (verdict, counts[verdict], meanings[verdict]))

    for verdict in ("refuse", "clean"):
        named = [row for row in rows if row[3] == verdict]
        if not named:
            continue
        out.write("\n  %s\n" % verdict)
        for name, language, share, _, _ in sorted(named, key=lambda row: row[2]):
            out.write("    %-34s %-12s %.3f\n" % (name[:34], language, share))

    unknown = sorted({row[0].rsplit("_", 1)[0] for row in rows if row[3] == "unknown"})
    if unknown:
        out.write("\n  never checked, by name: %s\n" % ", ".join(unknown[:24]))
        if len(unknown) > 24:
            out.write("  and %d more kinds\n" % (len(unknown) - 24))

    out.write("\n  wrote %s\n" % TARGET)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
