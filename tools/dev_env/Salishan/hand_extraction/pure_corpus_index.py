#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Write the README that opens the hand extractions, speaker first, from the config and the tables.
#
#   Usage:  python tools/dev_env/Salishan/hand_extraction/pure_corpus_index.py
#
# The list of who is in this corpus was kept by hand in refs.md and in the tables both, and two copies
# of a list drift. The names come from paper_config.py and the row counts from the tables, so neither
# is typed twice and refs.md points here instead of restating it.
#
# WHO GETS THE CREDIT
#
# The speaker. Every one of these languages belongs to the people who speak it and none of this work
# exists without them. The corpus everything else is measured against is their words written down.
#
# The names are read from the config and not derived from the who column. That column does several
# jobs across twenty tables, and a first version of this file guessed at it and put linguists in the
# speaker slot on eleven of them. Whose language a paper holds is a fact a person establishes by
# reading the paper, the same way its alphabet is, so it is declared and not inferred. Where a paper
# cites a published dictionary and never says who spoke, the entry is empty and this prints that.

import io
import os
import sys

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
HERE = os.path.dirname(os.path.abspath(__file__))
ORACLES = os.path.join(ROOT, "docs", "research", "Salishan", "pure_corpus")

sys.path.insert(0, os.path.join(os.path.dirname(HERE), "corpus_script_extraction"))

from paper_config import PAPERS  # noqa: E402

INDEX = os.path.join(ORACLES, "README.md")


def counted(path):
    """How many rows a table holds, not counting its header."""
    rows = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if (len(fields) < 4) or (fields[0] == "where"):
                continue
            rows += 1
    return rows


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    found = []
    for paper in PAPERS:
        path = os.path.join(ORACLES, paper.oracle)
        found.append((paper, counted(path) if os.path.isfile(path) else 0))

    with open(INDEX, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Whose words these are\n\n")
        handle.write("**Purpose:** Find whose language is in this corpus, and which table holds "
                     "it.\n")
        handle.write("**Scope:** every `.oracle.tsv` in this directory\n\n")
        handle.write("These languages belong to the people who speak them. None of this work "
                     "exists without them. Everything else in this research is measured against "
                     "the tables below, and the tables are their words, written down.\n\n")
        handle.write("Each entry opens with who spoke, because that is whose language it is. A "
                     "linguist wrote the paper and a person read the paper into a table, and "
                     "neither of those is whose language it is. Where a paper cites a published "
                     "dictionary and never says who spoke, the entry says so, and the linguist "
                     "does not go in the slot.\n\n")
        handle.write("Conditions the speakers set are recorded with them below and hold "
                     "wherever this corpus is used.\n\n")
        handle.write("Written by `tools/dev_env/Salishan/hand_extraction/pure_corpus_index.py` "
                     "from `corpus_script_extraction/paper_config.py`, which is the one place a "
                     "speaker's name is typed.\n\n")

        for paper, rows in found:
            handle.write("## %s\n\n" % paper.language)
            if paper.speakers:
                for one in paper.speakers:
                    handle.write("* **%s**\n" % one)
            else:
                handle.write("* The paper names no speaker. Its forms are cited from a "
                             "published source.\n")
            handle.write("\n%s, %d rows, `%s`\n\n" % (paper.stem, rows, paper.oracle))
            if paper.note:
                handle.write("%s\n\n" % paper.note)

        handle.write("---\n\n%d tables, %d rows read by hand.\n"
                     % (len(found), sum(one[1] for one in found)))

    out.write("  %d tables indexed, %d rows\n" % (len(found), sum(one[1] for one in found)))
    named = sum(1 for paper, rows in found if paper.speakers)
    out.write("  %d name their speakers, %d cite a published source\n"
              % (named, len(found) - named))
    out.write("  written to %s\n" % os.path.relpath(INDEX, ROOT))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
