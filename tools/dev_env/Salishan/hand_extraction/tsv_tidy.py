#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Make every hand extraction a tab-separated file a linter accepts.
#
#   Usage:  python tools/dev_env/Salishan/hand_extraction/tsv_tidy.py
#
# Two things fail csvlint and both were in every oracle file.
#
# The explanation of what the file is opened it, thirty-five to forty lines of it behind a hash.
# There is no comment syntax in a tab-separated file, and a linter reads the first line as the
# header. That prose is worth keeping, so it moves to a .oracle.md beside the table.
#
# The rows were ragged. A row with no gloss stopped after four fields where the header names five,
# and a linter counts that as a short row on every one of them. Each row is padded to the header's
# width with empty fields.
#
# A tab or a newline inside a field would do the same damage from the other direction, so both come
# out here as they do in the flag files.

import io
import os
import sys

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

# The tables sit in the research body, beside the prose that cites them, because they are the
# speakers' words written down and the evidence everything else here rests on.
ORACLES = os.path.join(ROOT, "docs", "research", "Salishan", "pure_corpus")


def tidy(text):
    """One field with the characters that would break a tab-separated file taken out."""
    return " ".join(text.split())


def split_out(path):
    """One oracle file separated into its prose and its table."""
    with open(path, encoding="utf-8") as handle:
        lines = [one.rstrip("\n") for one in handle]
    prose = [one.lstrip("#").strip() for one in lines if one.startswith("#")]
    table = [one for one in lines if one and not one.startswith("#")]
    return prose, table


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    done = 0
    for name in sorted(os.listdir(ORACLES)):
        if not name.endswith(".oracle.tsv"):
            continue
        path = os.path.join(ORACLES, name)
        prose, table = split_out(path)
        if not table:
            out.write("  %s holds no table\n" % name)
            continue

        columns = table[0].split("\t")
        width = len(columns)
        rows = []
        for line in table[1:]:
            fields = [tidy(one) for one in line.split("\t")]
            if len(fields) > width:
                # A tab inside a field would land here. Nothing merges silently: the extra fields
                # are joined back into the last column, which is where the text always sits.
                fields = fields[:width - 1] + [" ".join(fields[width - 1:])]
            fields += [""] * (width - len(fields))
            rows.append(fields)

        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write("\t".join(columns))
            handle.write("\n")
            for fields in rows:
                handle.write("\t".join(fields))
                handle.write("\n")

        beside = path[:-4] + ".md"
        if prose:
            with open(beside, "w", encoding="utf-8", newline="") as handle:
                handle.write("# %s\n\n" % name)
                for line in prose:
                    handle.write("%s\n" % line)
        done += 1
        out.write("  %-44s %d rows, %d columns, %d lines of prose moved to %s\n"
                  % (name[:44], len(rows), width, len(prose), os.path.basename(beside)))

    out.write("\n  %d hand extractions tidied\n" % done)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
