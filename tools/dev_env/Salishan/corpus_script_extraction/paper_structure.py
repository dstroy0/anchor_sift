#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Report the shape of an extracted paper so an extractor can be written against it.
#
#   Usage:  python tools/dev_env/paper_structure.py <name> [name ...]
#
# Every paper read so far has defeated an assumption carried from the one before it, and each failure was
# silent. Garcia numbered its third story differently from its first two and that story came back empty.
# Matthewson's footnote markers matched a bare number heading and cut a section from thirty-four blocks to
# two. Alexander's story sits entirely in subsections, so reading the bare numbers returned two appendices
# and none of the narrative. LaFontaine writes ł where others write ɬ, which makes every token invisible.
#
# All four were visible in the shape of the file and none of them were visible in a summary of it. This
# reports the shape: the headings, how many numbered blocks sit under each section, whether timestamps
# appear, and which characters the paper writes the language with. That is what an extractor has to be
# built against, and it is far less to read than forty pages.
#
# Nothing is extracted here and nothing is decided. A heading that looks wrong in this report is a heading
# that will be wrong in the extractor.

import io
import os
import re
import sys

from salish_marking import MARKED, PRACTICAL

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAPERS = os.path.join(ROOT, "build", "papers")

PAGE = re.compile(r"^===== page \d+ =====$")
NUMBERED_BLOCK = re.compile(r"^\((\d{1,4})\)")
CLOCK = re.compile(r"^\s*\[?\s*\d{1,2}:\d{2}\s*\]?\s*$")
APPENDIX = re.compile(r"^(Appendix\b.*|References\b.*)$", re.IGNORECASE)

# A heading is short and does not close with a period. A footnote opens with a bare marker and runs
# on into prose, which is what separates the two without naming either.
HEADING = re.compile(r"^(\d+(?:\.\d+)*)\s+(\S.*)$")

# Every character any of these papers writes the language with, so the report says which are in use
ALPHABETS = {
    "glottal stop ʔ": "ʔ",
    "glottal stop as 7": PRACTICAL,
    "lateral fricative ɬ": "ɬ",
    "lateral fricative ł": "ł",
    "barred lambda ƛ": "ƛ",
    "schwa ə": "ə",
    "pharyngeal ʕ": "ʕ",
    "combining marks": "̓̔̕",
}


def looks_heading(trimmed):
    """A numbered heading, told apart from a footnote by being short and not a sentence."""
    if not HEADING.match(trimmed):
        return None
    if len(trimmed) > 78 or trimmed.endswith("."):
        return None
    return HEADING.match(trimmed).group(1)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if len(sys.argv) < 2:
        out.write("  usage: paper_structure.py <name> [name ...]\n")
        out.flush()
        return 1

    for stem in sys.argv[1:]:
        path = os.path.join(PAPERS, "%s.txt" % stem)
        out.write("\n  %s\n" % stem)
        if not os.path.isfile(path):
            out.write("    no such file\n")
            continue

        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = [one.rstrip("\n") for one in handle]

        whole = "\n".join(lines)
        present = [name for name, marks in ALPHABETS.items()
                   if any(mark in whole for mark in marks)]
        out.write("    writes the language with: %s\n" % ", ".join(present))

        current = None
        blocks = {}
        clocks = {}
        held = {}
        order = []
        for line in lines:
            trimmed = line.strip()
            if PAGE.match(trimmed) or not trimmed:
                continue
            if APPENDIX.match(trimmed):
                current = trimmed[:40]
                if current not in order:
                    order.append(current)
                continue
            number = looks_heading(trimmed)
            if number:
                current = trimmed[:60]
                if current not in order:
                    order.append(current)
                continue
            if current is None:
                continue
            held[current] = held.get(current, 0) + 1
            if NUMBERED_BLOCK.match(trimmed):
                blocks[current] = blocks.get(current, 0) + 1
            if CLOCK.match(trimmed):
                clocks[current] = clocks.get(current, 0) + 1

        out.write("    %-58s %-7s %-8s %s\n" % ("heading", "lines", "blocks", "clocks"))
        for name in order:
            out.write("    %-58s %-7d %-8d %d\n"
                      % (name[:58], held.get(name, 0), blocks.get(name, 0), clocks.get(name, 0)))

    out.write("\n  blocks are lines opening with a bracketed number, clocks are timestamps on\n")
    out.write("  a line of their own. A section with lines and no blocks is running text\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
