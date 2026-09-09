#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Does which symbol follows which pick a language out of a field of them?
#
#   Usage:  python examples/language/4_measure/identity.py
#
# The test is the same one four separate scalars failed. Each text is held out, every language is
# described by the texts that remain, and the held out text goes to the nearest. If the square is
# what carries a language, its own texts come home and the scalars were reading a shadow of it.
#
# The square is swept over how many ranks it keeps, since keeping more is a finer reading of a
# smaller part of the alphabet and there is no reason to expect one width to be right.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.web import leave_one_out, web  # noqa: E402
from representation.text.corpus import load_language_texts  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")

RANKS = (8, 16, 32, 64)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    if not os.path.isdir(CORPORA):
        out.write("  no corpora at %s\n" % CORPORA)
        out.flush()
        return 1

    loaded = load_language_texts(CORPORA)
    if len(loaded) < 8:
        out.write("  only %d texts are long enough, which is too few to hold one out\n" % len(loaded))
        out.flush()
        return 1

    languages = sorted({row[0] for row in loaded})
    out.write("  %d texts over %d languages, so guessing gets %.1f percent\n\n"
              % (len(loaded), len(languages), 100.0 / len(languages)))
    out.write("  %-22s %-14s %s\n" % ("ranks kept", "correct", "share"))

    last = None
    for ranks in RANKS:
        rows = []
        for language, label, text in loaded:
            values = web(text, ranks)
            if values is not None:
                rows.append((language, label, values))
        if len(rows) < 8:
            continue
        correct, total, confused = leave_one_out(rows)
        out.write("  %-22s %-14s %.1f percent\n"
                  % ("the top %d symbols" % ranks, "%d of %d" % (correct, total),
                     100.0 * correct / total))
        last = confused

    if last:
        out.write("\n  where a text still goes wrong, at the widest square\n")
        for (was, went), count in sorted(last.items(), key=lambda pair: -pair[1])[:8]:
            out.write("    %-14s taken for %-14s %d\n" % (was, went, count))
    elif last is not None:
        out.write("\n  no text was placed in the wrong language at the widest square\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
