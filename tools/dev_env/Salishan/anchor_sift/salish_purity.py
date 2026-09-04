#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find out which extracted papers kept the writing and which quietly lost it, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/salish_purity.py
#
# Van Eijk lists the Lillooet resonants and the extraction returned "m   n   l   ḷ   γ   ʕ   ʕw w   y  z",
# where every gap held a glottalized consonant that is now gone. Those are phonemes. Two words that differ
# only in glottalization are one word after that loss, and every count taken on the file is a count on a
# language with a smaller inventory than Lillooet has. Robertson's paper in the same volume came through
# with ɬəw̓ál̓məš whole, combining marks and all, so this is a property of the file and not of the family.
#
# The gate in corpus_gate.py cannot catch it. What survives the loss is still writing, still in the script
# it claims, and still passes at any floor. The check has to look for what should be there instead of what
# should not, which means naming the characters a Salish orthography cannot do without and counting them.
#
# Two things are counted. The presence of the inventory, since a page of Salish with no glottal stop and
# no schwa in it did not extract. And the gaps themselves, since a dropped glyph leaves its space behind
# and a damaged line reads as letters separated by runs of blanks.
#
# Nothing here decides that a paper is usable. It sorts the papers so that the ones worth copying by hand
# are known before the copying starts, and so that a paper that has to be read off the page visually is
# known to need that.

import io
import os
import re
import sys
import unicodedata

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")

# What a Salish orthography cannot be written without. Glottal stop and pharyngeal, the lateral
# fricative, the barred lambda, schwa, the labialization mark, and the combining marks that carry
# glottalization and the wedge on the uvulars.
INVENTORY = {
    "glottal stop": "ʔɁˀʼ’",
    "pharyngeal": "ʕˁ",
    "lateral fricative": "ɬλ",
    "barred lambda": "ƛǁ",
    "schwa": "ə",
    "labialized": "ʷ",
    "uvular fricative": "χx̌",
}

# A glottalization or wedge written as its own combining character
COMBINING = re.compile(r"[̀-ͯ]")

# What a dropped glyph leaves behind: letters with a run of blanks wedged between them
GAP = re.compile(r"[A-Za-zɐ-ʯͰ-Ͽ]\s{2,}[A-Za-zɐ-ʯͰ-Ͽ]")


def measure(text):
    """What of the writing is present, and how much of it looks to have fallen out."""
    letters = sum(1 for symbol in text if symbol.isalpha())
    if letters < 200:
        return None

    held = {}
    for name, symbols in INVENTORY.items():
        held[name] = sum(1 for symbol in text if symbol in symbols)
    combining = len(COMBINING.findall(text))
    gaps = len(GAP.findall(text))

    # How many of the named sets turned up at all
    present = sum(1 for name in held if held[name] > 0)
    return held, combining, gaps, letters, present


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = []
    for name in sorted(os.listdir(PAPERS)):
        if not name.endswith(".txt"):
            continue
        if name.endswith("_glosses.tsv") or name.startswith("icsnl_index"):
            continue
        path = os.path.join(PAPERS, name)
        with open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        taken = measure(text)
        if taken is None:
            continue
        held, combining, gaps, letters, present = taken
        rows.append((name[:-4], letters, present, combining, gaps,
                     1000.0 * combining / letters, 1000.0 * gaps / letters, held))

    # The worst are the ones with the inventory missing and the gaps heavy
    rows.sort(key=lambda row: (row[2], -row[6]))

    out.write("  %-42s %-9s %-6s %-8s %-8s %s\n"
              % ("paper", "letters", "sets", "marks", "gaps", "gaps per 1000 letters"))
    for stem, letters, present, combining, gaps, mark_rate, gap_rate, held in rows:
        out.write("  %-42s %-9d %-6d %-8d %-8d %.2f\n"
                  % (stem[:42], letters, present, combining, gaps, gap_rate))

    out.write("\n  sets is how many of the %d named parts of the inventory appear at all\n"
              % len(INVENTORY))
    out.write("  marks is combining glottalization and wedges, which drop first\n")
    out.write("  gaps is letters with blanks wedged between them, the shape a lost glyph leaves\n")

    out.write("\n  which of the inventory each paper is missing\n")
    for stem, letters, present, combining, gaps, mark_rate, gap_rate, held in rows:
        absent = [name for name in sorted(held) if held[name] == 0]
        if not absent:
            continue
        out.write("  %-42s no %s\n" % (stem[:42], ", ".join(absent)))

    clean = [row for row in rows if (row[2] >= 5) and (row[6] < 2.0)]
    out.write("\n  %d of %d papers hold at least five of the sets with few gaps\n"
              % (len(clean), len(rows)))
    for stem, letters, present, combining, gaps, mark_rate, gap_rate, held in clean:
        out.write("  %s\n" % stem)

    out.write("\n  a paper absent from that list is not proof of damage and a paper on it\n")
    out.write("  is not proof of soundness. It says where to look first and where a page\n")
    out.write("  has to be read off the image instead of out of the file\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
