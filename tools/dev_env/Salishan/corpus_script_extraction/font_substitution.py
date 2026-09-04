#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test a candidate character mapping for a paper whose font substituted plain letters for the writing.
#
#   Usage:  python tools/dev_env/font_substitution.py <damaged> <clean reference> [more references]
#
# salish_purity.py sorts papers by whether the marked characters survived extraction, and it reports two
# different failures under one heading. In most of the older papers the glyphs are simply gone and the
# words arrive with holes in them. In the two Lyon papers the glyphs were replaced: the text reads
# kmúsm @s iP sncPiws smiPmáy, where @ looks like a schwa and P like a glottal stop. A substitution is
# recoverable and a deletion is not, so the two need telling apart.
#
# Guessing the table is not acceptable. A mapping asserted from what the characters resemble would put
# words into a corpus that nobody said, and nothing downstream would ever question them.
#
# So the mapping is tested instead of asserted. Lyon has recent papers on the same language whose
# extraction kept its characters. Apply a candidate mapping to the damaged tokens and count how many
# become forms that appear in the clean papers. A mapping that is right turns a large share of them into
# attested words. A mapping that is wrong turns almost none, because a wrong substitution produces strings
# the language does not contain.
#
# The number to read is the change. If the hit rate before and after are both low, the reference does not
# share enough vocabulary to decide anything and the test says nothing either way.

import io
import os
import re
import sys

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")

EDGES = ".,!?;:“”‘’\"'()[]…«»"

# What the damaged text appears to write, and what the clean papers write in its place. Every entry
# here is a hypothesis and none of it is applied to anything until the hit rate says it holds.
# The caron entries come first: this font writes it as a separate character before its letter, so
# x̌ arrives as ˇx and č as ˇc. Replacing the bare letters first would consume them and leave the
# caron stranded, so order matters and a plain dict is relied on to keep insertion order.
CANDIDATE = {
    "ˇx": "x̌",
    "ˇc": "č",
    "ˇs": "š",
    "@": "ə",
    "P": "ʔ",
    "ì": "ɬ",
    "Q": "ʕ",
}


def tokens_of(path, floor=2):
    """Every token in a file, stripped of the punctuation around it."""
    held = {}
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith("====="):
                continue
            for token in line.split():
                plain = token.strip(EDGES)
                if len(plain) >= floor:
                    held[plain] = held.get(plain, 0) + 1
    return held


def applied(token, table):
    """One token with the candidate mapping applied."""
    for was, becomes in table.items():
        token = token.replace(was, becomes)
    return token


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if len(sys.argv) < 3:
        out.write("  usage: font_substitution.py <damaged> <clean reference> [more]\n")
        out.flush()
        return 1

    damaged = os.path.join(PAPERS, "%s.txt" % sys.argv[1])
    if not os.path.isfile(damaged):
        out.write("  no %s\n" % damaged)
        out.flush()
        return 1

    reference = {}
    for stem in sys.argv[2:]:
        path = os.path.join(PAPERS, "%s.txt" % stem)
        if not os.path.isfile(path):
            out.write("  no reference at %s\n" % path)
            continue
        for token, times in tokens_of(path).items():
            reference[token] = reference.get(token, 0) + times

    if not reference:
        out.write("  no reference tokens, nothing to test against\n")
        out.flush()
        return 1

    held = tokens_of(damaged)
    # Only tokens carrying a character the mapping would change are informative
    candidates = {token: times for token, times in held.items()
                  if any(was in token for was in CANDIDATE)}

    before = sum(times for token, times in candidates.items() if token in reference)
    after = 0
    turned = []
    for token, times in candidates.items():
        moved = applied(token, CANDIDATE)
        if moved in reference:
            after += times
            if (moved != token) and (len(turned) < 14):
                turned.append((token, moved, times))

    total = sum(candidates.values())
    out.write("  damaged   %s\n" % sys.argv[1])
    out.write("  reference %s\n" % ", ".join(sys.argv[2:]))
    out.write("\n  %d distinct reference tokens\n" % len(reference))
    out.write("  %d distinct damaged tokens carry a character the mapping changes, "
              "%d occurrences\n" % (len(candidates), total))
    out.write("\n  attested in the reference before the mapping  %d of %d, %.1f%%\n"
              % (before, total, (100.0 * before / total) if total else 0.0))
    out.write("  attested in the reference after the mapping   %d of %d, %.1f%%\n"
              % (after, total, (100.0 * after / total) if total else 0.0))

    if turned:
        out.write("\n  tokens the mapping turned into attested forms\n")
        for token, moved, times in turned:
            out.write("    %-24s -> %-24s x%d\n" % (token, moved, times))

    out.write("\n  the mapping under test\n")
    for was, becomes in CANDIDATE.items():
        out.write("    %s -> %s\n" % (was, becomes))

    out.write("\n  a large rise says the mapping holds. Both rates low says the reference does\n")
    out.write("  not share enough vocabulary to decide, and the test has said nothing\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
